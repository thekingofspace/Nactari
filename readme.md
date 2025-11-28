# Discord.luau

This module provides a basic backend for connecting to the Discord Gateway using Lune's WebSocket and HTTP libraries. It handles the initial handshake, event routing, heartbeats, and simple REST requests.

The bot connects directly to the Discord Gateway URL and identifies using the provided token and intents. Once connected, it listens for incoming packets and dispatches them to any registered event callbacks. The backend also sends periodic heartbeats using the interval provided by Discord.

## Events

You can bind events using `bot:On("event", callback)`.  
All Discord events are routed by name in lowercase.

Handled events:
- Any official Discord Gateway event (MESSAGE_CREATE, READY, etc.) if a callback is registered.
- `undefined` — called when an event is received without a registered handler.
- `heartbeat` — fired every time a heartbeat is sent.
- `signalstep` — fired every time *any* event is processed.

What it does not handle:
- No automatic reconnection.
- No shard management.
- No rate limit handling or queuing for REST requests.
- No caching, state tracking, or presence updates.
- No resume/identify recovery logic beyond storing the last sequence number.

## REST Requests

`SendContext(method, path, body?, headers?)` sends a simple REST request to Discord's HTTP API.  
It automatically attaches the bot authorization token and JSON-encodes tables.

Errors with status codes above 400 throw an exception. Responses are decoded from JSON when possible.

## Starting and Stopping

`Start()` opens a WebSocket connection, identifies with Discord, starts event listeners, and begins heartbeat loops. It also fetches the bot's application ID from `/applications/@me`.

`Stop()` cancels all running tasks and closes the WebSocket connection.

This backend is minimal and is intended as a thin layer for sending and receiving packets. It does not include full Discord client functionality.
