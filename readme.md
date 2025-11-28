# Discord.luau

This module provides a minimal backend for connecting to the Discord Gateway using Lune’s WebSocket and HTTP libraries. It handles identification, resumes, event routing, heartbeats, and basic REST requests. It is intended as a thin packet layer — **not** a full Discord client.

The bot connects to the Discord Gateway URL and identifies using the provided token and intents. If session data exists, it attempts to resume automatically. After connecting, it listens for incoming packets, updates sequence numbers, and dispatches events to any registered handlers. Heartbeats are sent according to the interval provided by Discord.

## Events

Events are registered using:
`bot:On("event", callback)`

Event names are always converted to lowercase.

Triggered events:

* Any official Discord Gateway event (e.g. MESSAGE_CREATE, READY) if a handler exists.
* `undefined` — fired when an event is received with no matching handler.
* `heartbeat` — fired whenever a heartbeat is sent.
* `signalstep` — fired every time *any* event is processed.
* `resume` — fired after sending a resume request during reconnect logic.

## What This Backend Handles

* Connecting to the Discord Gateway.
* Identifying and resuming sessions.
* Automatic heartbeat loop.
* Dispatching events to registered callbacks.
* Sending packets through the WebSocket.
* Performing basic REST API requests.
* Updating session ID, sequence number, and resume URL.

## What This Backend Does **Not** Handle

* No shard management.
* No REST rate-limit buckets or global queue.
* No caching or internal Discord state tracking.
* No presence updates or status management. (Refer to SendSocket for that)
* No automatic full reconnection logic beyond Discord’s OP 7/9 resume system.

## REST Requests

`SendContext(method, path, body?, headers?)` sends a REST request to the Discord REST API.

Includes:

* Bot authorization header
* JSON encoding of table bodies
* JSON decoding on successful responses

Errors with `statusCode >= 400` raise an exception.

## WebSocket Sending

`SendSocket(packet)`
Encodes the packet as JSON and sends it through the active WebSocket.

## Starting and Stopping

`Start()`:

* Connects to the Gateway or resume URL
* Sends Identify or Resume depending on session state
* Begins event handler loop
* Starts heartbeat loop
* Loads the bot’s application ID from `/applications/@me`

`Stop()`:

* Cancels all running tasks
* Closes the WebSocket
* Resets internal state
