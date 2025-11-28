# Discord.luau

This module provides a minimal backend for connecting to the Discord Gateway using Lune’s WebSocket and HTTP libraries. It handles the initial handshake, event dispatching, heartbeats, and basic REST requests.

The bot connects directly to the Discord Gateway URL and identifies using the provided token and intents. After connecting, it listens for incoming packets and routes them to any registered event callbacks. Heartbeats are automatically sent using the interval provided by Discord.

## Events

Events can be registered using `bot:On("event", callback)`.
All event names are normalized to lowercase.

Supported event routing:

* Any official Discord Gateway event (e.g. MESSAGE_CREATE, READY) if a callback is registered.
* automatic reconnection or session recovery.
* `undefined` — fired when an event is received with no matching handler.
* `heartbeat` — fired each time a heartbeat is sent.
* `signalstep` — fired whenever *any* event is processed.
* `resume` — fired when resuming the socket

What this backend does **not** handle:

* No shard management.
* No REST rate-limit handling or request queuing.
* No caching or internal state tracking.

## REST Requests

`SendContext(method, path, body?, headers?)` performs a simple REST request to Discord’s HTTP API.
It automatically includes bot authorization headers and JSON-encodes table bodies.

`SendSocket(packet)` Sends a packet to the socket.
It automatically JSON-encodes table bodies.

Errors with status codes above 400 raise an exception. Responses are JSON-decoded when possible.

## Starting and Stopping

`Start()` opens a WebSocket connection, identifies with Discord, initializes event listeners, and begins the heartbeat loop. It also loads the bot’s application ID from `/applications/@me`.

`Stop()` cancels all running tasks and closes the WebSocket connection.

This module is intended as a thin layer for sending and receiving packets — not a full-featured Discord client.
