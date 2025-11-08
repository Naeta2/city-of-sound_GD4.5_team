# Events

> All events live in `Scheduler`
> They are fired minute by minute

## Event Template

```
{
  "id": "ev:…",                           // StringName
  "owner_id": "agent:…",                  // StringName (who "organizes" event)
  "type": "practice|gig|travel_begin|travel_end|eat|sleep_end|…",
  "start": 123456,                        // int : absolute minutes (TimeService.abs_minutes)
  "requires_presence": false,             // bool
  "status": "scheduled|pending|fired|missed",
  "payload": { /* specific to event_type */ }
}
```

## Invariants

- `start` is always an `int`
- `status` default is `&"scheduled"`
- `payload` default : `{}`

## Runtime

1. `scheduled` : waiting for `start`
2. when `start` :
	- if `requires_presence=false`: event fires immediately
	- if `requires_presence=true`:
		- if present (`PresenceService.is_at(owner_id, payload.place_id)`) : event fires
		- if not present : `pending` until `start + GRACE_MINUTES` (30 default), then `missed`
3. `fired/missed`: removed from list, may be added to _history

## Current event types

- `practice`, payload: `{ "skill": "guitar", "minutes": 60 }`
- `gig`, payload: `{"place_id": "place", "from_agent_account_id": "acct", "to_agent_account_id": "acct", "payout": 120}` `requires_presence=true`
- `travel_begin`, payload: `{"to_place_id": "place", "duration": 30}`
- `travel_end`, payload: `{"to_place_id": "place"}`
- `eat`, payload: `{"amount": 30, "place_id"(optional): "place"}`
- `sleep_end`, payload: `{"duration":360, "place_id":"place"}`
