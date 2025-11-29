# Discord.luau

This module provides a minimal backend for connecting to the Discord Gateway using Lune’s WebSocket and HTTP libraries. It implements a lightweight event-driven packet layer with optional manual sharding. The design focuses on simplicity: identification, resuming, event routing, heartbeats, and basic REST requests.

A bot connects to the Gateway using your token, intents, and shard configuration. If a previous session exists, the client attempts to resume automatically. The backend listens for packets, updates sequence numbers, and dispatches events to handlers. Heartbeats run on an internal task loop using the interval provided by Discord.

---

## Event System

Events are registered using:

```lua
bot:On("event", function(data, eventName) end)
```

Event names are normalized to lowercase.

### Supported Routed Events

* **Any Discord event** you register (e.g. `"ready"`, `"message_create"`).
* **`undefined`**
  Fired when an event has no handler.
* **`heartbeat`**
  Fired each time a heartbeat is sent.
* **`signal_step`**
  Fired once for *every* packet processed.
* **`resume`**
  Fired after sending a resume packet (OP 6).
* **`rest_send`**
  Fired after sending a rest request.
* **`socket_send`**
  Fired after sending a socket request.

### Chainable Events

All event handlers return a **Chain** object which allows:

```lua
:AndThen(function() end)
:Catch(function(err) end)
:Await()
```

Example:

```lua
bot:On("ready", function(d)
    print("Bot is ready.")
end)
:AndThen(function()
    print("Next step.")
end)
:Catch(function(err)
    print("Error:", err)
end)
```

You can chain indefinitely. Returned values flow only to the next chain step.

### Grab an Existing Event Chain

You can fetch an already-registered event chain:

```lua
local chain = bot:Grab("ready")
if chain then
    chain:AndThen(function()
        print("Late extension")
    end)
end
```

---

## Sharding

This backend supports **manual**, **non-automated** sharding.
Each bot instance represents **one shard**.

Create a shard with:

```lua
local Bot = Discord.New(intents, token, shardID?, shardCount?)
```

Example with 3 shards:

```lua
local S0 = Discord.New(Intents, Token, 0, 3)
local S1 = Discord.New(Intents, Token, 1, 3)
local S2 = Discord.New(Intents, Token, 2, 3)
```

### Fracture — Duplicate a Bot Into a New Shard

Instead of redefining events manually for each shard:

```lua
local NewShard = Bot:Fracture(newID, shardCount)
```

Fracture copies:

* Registered events
* Token
* Intents
* Application ID (if already fetched)

The new shard acts independently with its own gateway connection.

### Getting All Shards

```lua
local list = Bot:GetShards()
```

---

## What This Backend Handles

* Gateway connection & WebSocket management
* Identify packets
* Resume packets (OP 6)
* Automatic heartbeat scheduling
* Packet routing to event handlers
* Sequence number (`s`) tracking
* Resume URL tracking
* REST API requests (simple)
* Chainable event flow (`AndThen`, `Catch`, `Await`)
* Event duplication via `Fracture()`
* Grab existing handlers via `Grab()`

---

## What This Backend Does **Not** Handle

* No automatic shard manager
* No rate-limit handling or bucket logic for REST
* No caching of guilds, channels, or users
* No presence or status helpers
* No advanced reconnection logic (only OP 7/9)

This is intentionally a thin layer, not a full Discord client.

---

## REST Requests

```lua
bot:SendContext(method, path, body?, headers?)
```

Features:

* JSON when sending tables
* JSON decoding on successful response
* Automatic Authorization header

Errors (`statusCode >= 400`) throw an exception with details.

---

## WebSocket Sending

```lua
bot:SendSocket(packet)
```

Encodes the packet as JSON and sends it through the gateway socket.

---

## Starting & Stopping

### Start

```lua
bot:Start()
```

Start performs:

1. Open WebSocket connection
2. Send Identify or Resume
3. Start packet listener loop
4. Start heartbeat loop
5. Fetch your Application ID
6. Track session + resume URLs

### Stop

```lua
bot:Stop()
```

This:

* Cancels all running task threads
* Closes the WebSocket
* Clears internal state
