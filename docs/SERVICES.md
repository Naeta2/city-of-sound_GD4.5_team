# Services

>Each service exposes a small public API, emits signals, and supports dump/restore (JSON)

## Table of Contents

- [IdService](#idservice)
- [Link Text](#agentrepo)
- [Link Text](#economyservice)
- 
- 

## IdService

IdService is used to generate readable, unique IDs

### API

`new_id(kind: String)` returns a unique StringName that looks like this : str(prefix)/str(kind):_flot(system unix time at creation)_int(incremental integer)
example : agent:_1762613558_3

## AgentRepo

AgentRepo stores all agents and their stats

### API

`create_agent(agent_name: String)` creates an agent with name agent_name and returns its id as a StringName
`ag_get(agent_id: StringName)` returns a dictionary with all stats for agent_id

## EconomyService
