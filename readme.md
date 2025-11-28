# Discord.luau

This module provides a minimal backend for connecting to the Discord Gateway using Lune’s WebSocket and HTTP libraries. It handles identification, resumes, event routing, heartbeats, and simple REST requests. It is intended as a thin packet layer — not a full Discord client.

A bot connects to the Discord Gateway URL and identifies using the provided token, intents, and optional shard information. If a previous session exists, it will attempt to resume. After connecting, it listens for incoming packets, tracks sequence numbers, and dispatches events to registered handlers. Heartbeats are sent using the interval from Discord.

## Events

Events are registered using:
`bot:On("event", callback)`

Event names are always converted to lowercase.

Triggered events:

* Any official Discord Gateway event (MESSAGE_CREATE, READY, etc.) if a handler exists.
* `undefined` — fired when an event is received with no matching handler.
* `heartbeat` — fired when a heartbeat is sent.
* `signalstep` — fired for every processed event.
* `resume` — fired after sending a resume request.

## Sharding

This backend supports manual sharding.

Each bot instance represents one shard.
Shard configuration is set using:

`Discord.New(intents, token, shardID?, shardCount?)`

Example:

```lua
local Shard0 = Discord.New(Intents, Token, 0, 3)
local Shard1 = Discord.New(Intents, Token, 1, 3)
local Shard2 = Discord.New(Intents, Token, 2, 3)
```

### Fracture

Instead of redefining all events for each shard, you can duplicate an existing bot:

`local NewShard = Bot:Fracture(shardID, shardCount)`

This copies:

* all registered events
* intents
* token
* app ID (if already loaded)

The new shard functions identically but runs on a separate gateway connection.

## What This Backend Handles

* Connecting to the Gateway.
* Identify and resume packets.
* Automatic heartbeat loop.
* Event routing to callbacks.
* Session ID, resume URL, and sequence tracking.
* Sending WebSocket packets.
* Basic REST API requests.

## What This Backend Does **Not** Handle

* No automatic shard manager.
* No REST rate limits or request queuing.
* No caching or state tracking of guilds, channels, or users.
* No presence or status helpers.
* No reconnection logic beyond Discord’s OP 7/9 rules.

## REST Requests

`SendContext(method, path, body?, headers?)`
Sends a request to the Discord REST API with:

* Authorization header
* JSON encoding when passing Lua tables
* JSON decoding for valid responses

Errors with `statusCode >= 400` throw an exception.

## WebSocket Sending

`SendSocket(packet)`
Encodes the packet as JSON and sends it over the WebSocket.

## Starting and Stopping

`Start()`:

* Connects to the Gateway or resume URL
* Sends Identify or Resume
* Runs the event processing loop
* Starts the heartbeat loop
* Fetches application ID from `/applications/@me`

`Stop()`:

* Cancels internal tasks
* Closes the WebSocket
* Clears running state
