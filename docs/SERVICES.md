# Services

>Each service exposes a small public API, emits signals, and supports dump/restore (JSON)

## Table of Contents

- [IdService](#idservice)
- [AgentRepo](#agentrepo)
- [EconomyService](#economyservice)
- [SkillsService](#skillsservice)
- [TimeService](#timeservice)
- [Scheduler](#scheduler)
- [PresenceService](#presenceservice)
- [NeedsService](#needsservice)
- [PlaceRepo](#placerepo)
- [SaveService](#saveservice)

## IdService

IdService is used to generate readable, unique IDs

### API

- `new_id(kind: String) -> StringName`
returns an ID like `kind:1731001234_42`

### Notes

- Pure utility, no persistence is required

## AgentRepo

In-memory registry of agents (character, organisation). Single source of truth for agent data

### Signals

- `agent_created(agent_id: StringName)`
- `agent_changed(agent_id: StringName)`

### Stored structure (per agent)

```
{
  "id": StringName, "kind": &"person"|&"org", "name": String,
  "account_id": StringName,  # may be empty
  "skills": Dictionary,      # skill_name -> 0.0..1.0
  "needs": {"energy": float, "hunger": float},  # 0..100
  "status": &"healthy"|&"hurt"
}
```

### API (main)

- `create_agent(agent_name: String) -> StringName` returns new agent ID
- `ag_get(agent_id: StringName) -> Dictionary` returns agent data (read-only)
- `set_ag_name(agent_id, new_name)`
- `set_account(agent_id, account_id)`
- Skills: `get_ag_skill(id, skill) -> float`, `set_ag_skill(id, skill, value)`
- Needs: `get_ag_need(id, need) -> float`, `set_ag_need(id, need, value)`
- Status: `get_ag_status(id) -> StringName`, `set_ag_status(id, status)`
- Utility: `get_all_ids() -> Array[StringName]`

### Persistence

- `dump() -> {"agents":{....}}`
- `restore(d: Dictionary)`

## EconomyService

Ledger of accounts and balances

### Signals

- `account_changed(account_id: StringName, balance: int)`
- `transfer_done(from_id: StringName, to_id: StringName, amount: int, reason: String)`

### API

- `create_account(initial:=0, account_id:=StringName()) -> StringName`
- `get_balance(account_id) -> int`
- `deposit(account_id, amount, reason:="")`
- `withdraw(account_id, amount, reason:="") -> bool`
- `transfer(from_id, to_id, amount, reason:="") -> bool`

### Persistence

- `dump() -> {"balances":{}, "exists":{}}`
- `restore(d)`

## SkillsService

Immediate skill progression (used by `Scheduler` events)

### Signals

- `skill_changed(agent_id, skill, value: float)`
- `practiced(agent_id, skill, minutes: int, gain: float)`

### Key Settings

- `BASE_GAIN_PER_HOUR := 0.03`
- `DIMINISHING_START := 0.6`
- `DIMINISHING_FACTOR := 0.5`

### API

- `practice(agent_id, skill: StringName, minutes: int, intensity: float=1.0) -> void`

### Misc

- Intensity can be computed via `NeedsService.compute_intensity(agent_id)`

## TimeService

Game clock. Emits minutes/hour/day signals. Holds absolute minutes

### Signals

- `time_minute(abs_minutes: int)`
- `hour_changed(day: int, hour: int)`
- `day_changed(day: int)`

### State

- `abs_minutes: int` - source of truth
- `paused: bool`, `speed: float` (minutes per real second)

### Helpers

- `get_day() -> int`, `get_hour() -> int`, `get_minute() -> int`
- `format_hhmm() -> String`, `format_d_hhmm() -> String`
- Control: `set_paused(p)`, `set_speed(x)`, `advance_minutes(mins)`

### Persistence

- `dump() -> {abs_minutes, speed, paused}`
- `restore(d)`

## Scheduler

Global agenda queue. Fires events at `start` time; supports presence requirement and grace window

### Signals

- `events_changed()`
- `event_fired(ev: Dictionary)`
- `event_missed(ev: Dictionary)`

### Event Model

```
{
  "id": "ev:…",
  "owner_id": "agent:…",
  "type": "practice|gig|travel_begin|travel_end|eat|sleep_end|…",
  "start": 123456,                 // int (absolute minutes)
  "requires_presence": false,
  "status": "scheduled|pending|fired|missed",
  "payload": { /* per type */ }
}
```

### Built-in event handlers

- `practice: { "skill": StringName, "minutes": int }`
→ calls `SkillsService.practice(owner_id, skill, minutes, NeedsService.compute_intensity(owner_id))`
(optionally `NeedsService.apply_activity_cost(...)` if enabled)

- `travel_begin`: `{ "to_place_id": StringName, "duration": int }` → set location to `__transit__`.

- `travel_end`: `{ "to_place_id": StringName }` → set location to destination.

- `eat`: `{ "amount": float [, "place_id": StringName] }` → `NeedsService.eat(...)`.

- `sleep_end`: `{ "duration": int [, "place_id": StringName] }` → `NeedsService.rest(...)`.

- `gig`: `{ "place_id": StringName, "from_agent_account_id": StringName, "to_agent_account_id": StringName, "payout": int }`
→ `EconomyService.transfer(from → to, payout, "Gig payout")`.

### API

- `schedule(ev: Dictionary) -> void` (sanitizes event; sort by `start`)
- Helpers:
	- `schedule_travel(owner_id, to_place_id, depart_at, duration_min) -> {begin_id, end_id}`
	- `schedule_eat(owner_id, at_minutes, amount:=25.0, requires_presence:=false, place_id:=StringName()) -> StringName`
	- `schedule_sleep(owner_id, start_minutes, duration_minutes, requires_presence:=false, place_id:=StringName()) -> {end_id}`
	- `schedule_gig(...)`
- Query: `upcoming(limit:=20) -> Array[Dictionary]`

### Rules

- Presence: if `requires_presence==true`, checks `PresenceService.is_at(owner_id, payload.place_id)`
- Grace window: pending until `start + GRACE_MINUTES` (default 30), then `missed`

### Persistence

- `dump() -> {"events":[...], ("history":[...])}`
- `restore(d)` (sanitizes: `start` forced to int, StringName coercions)

## PresenceService

Track agent location by logical `place_id`

### Signals

- `location_changed(agent_id, place_id)`

### Constants

- `PLACE_TRANSIT := &"__transit__"`
- `ALLOW_UNKNOWN_PLACES := true` (warn if unknown; set false to reject)

### API

- `set_location(agent_id, place_id)`
- `get_location(agent_id) -> StringName`
- `is_at(agent_id, place_id) -> bool`
- `place_exists(place_id) -> bool`

### Persistence

- `dump() -> {"where": {agent_id: place_id}}`
- `restore(d)`

## NeedsService

Needs ticking every minute + global agent status

### Signals

- `need_changed(agent_id, need: StringName, value: float)`
- `status_changed(agent_id, status: StringName)`

### Minute Tick

- `hunger += HUNGER_PER_MIN` (eg`0.02`)
- `energy += ENERGY_PER_MIN` (negative, eg`-0.03`)
- Threshold switch `status` (for now between `healthy` `hurt`)

### API

- `eat(agent_id, amount:=25.0)`
- `rest(agent_id, minutes:int)` (applies energy gain immediately; sleep is modeled by the event `sleep_end`)
- `compute_intensity(agent_id) -> float` (0.25..2.0; used by practice)
- `apply_activity_cost(agent_id, minutes, effort:=1.0)`

### Persistence

Uses AgentRepo’s needs/status; no separate dump/restore.

## PlaceRepo

Data registry of places (venues, homes, studios, shops...)
pure data

### Signals

- `place_created(place_id)`
- `place_changed(place_id)`
- `place_removed(place_id)`

### Stored Structure (per place)

```
{
  "id": StringName,
  "type": &"venue"|&"home"|&"studio"|&"shop"|...,
  "name": String,
  "meta": {
	"pos": Vector2? (serialized as [x,y]),
	"account_id": StringName?,   # org account (e.g. venue)
	... other arbitrary keys ...
  }
}
```

### API

- `create_place(p_type: StringName, p_name: String, meta:= {}) -> StringName`
- `get_place(place_id) -> Dictionary`
- `set_place_meta(place_id, key: String, value) -> void`
- `set_all_meta(place_id, meta: Dictionary) -> void`
- `remove(place_id) -> void`
- Lists: `list_ids(p_type:=StringName()) -> Array[StringName]`
- Helpers: `get_place_name(place_id) -> String`, `get_place_type(place_id) -> StringName`
- Travel mock: `estimate_travel_minutes(from_id, to_id, mode:=&"walk") -> int` (requires both places to have `meta.pos`)

### Persistence

- `dump() -> {"places": {...}}` (Vector2 serialized as `[x,y]`)
- `restore(d)` (rebuilds Vector2; StringName coercions)

## SaveService

Persist/restore the whole world as JSON (`user://save.json` by default)

### Signals

- `save_done(path: String, ok: bool)`
- `load_done(path: String, ok: bool)`

### API

- `save(path:=DEFAULT_PATH) -> bool`
- `load(path:=DEFAULT_PATH) -> bool`

### Order (load)

1. `TimeService.restore`
2. `AgentRepo.restore`
3. `EconomyService.restore`
4. `PresenceService.restore`
5. `PlaceRepo.restore`
6. `Scheduler.restore`

### Notes

- `schema` versioned; handle migrations later if format evolves
- use `OS.get_user_data_dir()` to find actual folder for `user://`
