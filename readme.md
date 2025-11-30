# Discord.luau

A powerful Discord bot framework built for [Lune](https://lune-org.github.io/docs), featuring a chainable async API, automatic reconnection handling, and shard support.

## Features

- **Chain-based Event Handling**: Build complex async flows with `.AndThen()`, `.Catch()`, `.Halt()`, and `.Throw()`
- **Automatic Reconnection**: Handles Discord gateway resumption and session management
- **Sharding Support**: Scale your bot across multiple shards
- **Type-Safe**: Full TypeScript-style type annotations for better IDE support
- **REST API Integration**: Built-in methods for Discord API calls with automatic authorization

## Installation

```lua
local DiscordBot = require("path/to/module")
```

## Quick Start

```lua
local bot = DiscordBot.New(
    0,                    -- Intents (0 for none, or bitfield)
    "YOUR_BOT_TOKEN",     -- Bot token
    0,                    -- Shard ID (optional, defaults to 0)
    1                     -- Shard count (optional, defaults to 1)
)

bot:On("ready", function(data)
    print("Bot is ready!")
    print("Logged in as:", data.user.username)
end)

bot:On("message_create", function(message)
    if message.content == "!ping" then
        bot:SendContext("POST", `channels/{message.channel_id}/messages`, {
            content = "Pong!"
        })
    end
end)

bot:Start()
```

## Core Methods

### `DiscordBot.New(Intents, Token, ShardID?, ShardCount?)`

Creates a new Discord bot instance.

```lua
local bot = DiscordBot.New(0, "YOUR_TOKEN")
```

### `bot:On(Event, Callback)`

Registers an event handler. Returns a Chain for advanced async handling.

```lua
bot:On("message_create", function(message)
    print("Received message:", message.content)
end)
```

Common events: `ready`, `message_create`, `interaction_create`, `guild_create`, etc.

### `bot:Start()`

Connects to Discord gateway and starts the bot.

```lua
bot:Start()
```

### `bot:Stop()`

Gracefully disconnects from Discord, cancels all tasks, and waits for active chains to complete.

```lua
bot:Stop()
```

### `bot:SendContext(Method, Path, Body?, Headers?)`

Makes a REST API call to Discord.

```lua
local channel = bot:SendContext("GET", `channels/{channelId}`)

bot:SendContext("POST", `channels/{channelId}/messages`, {
    content = "Hello, Discord!"
})
```

### `bot:SendSocket(Packet)`

Sends a raw gateway packet.

```lua
bot:SendSocket({
    op = 1,
    d = nil
})
```

## Advanced Features

### Chain API

The Chain API allows you to build complex async workflows with error handling:

```lua
bot:On("message_create", function(message)
    return message
end)
:AndThen(function(message)
    print("Processing message:", message.content)
    if message.content:match("error") then
        error("Found error keyword!")
    end
    return message
end)
:Catch(function(err, message)
    print("Error occurred:", err)
    -- Send error message to channel
    bot:SendContext("POST", `channels/{message.channel_id}/messages`, {
        content = "An error occurred while processing your message."
    })
end)
:Halt()
```

#### Chain Methods

- **`:AndThen(fn)`** - Executes after the previous step succeeds
- **`:Catch(fn)`** - Handles errors from previous steps
- **`:Halt()`** - Stops chain execution after a catch
- **`:Throw(fn)`** - Conditionally throws errors based on logic
- **`:Await()`** - Blocks until chain completes (must be in coroutine)

### Sharding

Create multiple shards for large bots:

```lua
local mainBot = DiscordBot.New(0, "YOUR_TOKEN", 0, 2)

mainBot:On("message_create", function(message)
    print("Shard 0:", message.content)
end)

local shard1 = mainBot:Fracture(1, 2)

mainBot:Start()
shard1:Start()

-- Get all shards
local shards = mainBot:GetShards()
print("Total shards:", #shards)
```

### Special Events

The module provides several special events beyond standard Discord gateway events:

#### Lifecycle Events

- **`Start`** - Triggered before the bot connects to Discord gateway
  ```lua
  bot:On("Start", function()
      print("Initiating connection...")
  end)
  ```

- **`Started`** - Triggered after successful connection and authentication
  ```lua
  bot:On("Started", function()
      print("Bot is now online!")
  end)
  ```

- **`Stop`** - Triggered when `bot:Stop()` is called, before disconnection
  ```lua
  bot:On("Stop", function()
      print("Shutting down...")
  end)
  ```

- **`Stopped`** - Triggered after complete shutdown (all tasks cancelled, chains finished)
  ```lua
  bot:On("Stopped", function()
      print("Bot has been stopped")
  end)
  ```

#### Network Events

- **`heartbeat`** - Triggered on each heartbeat sent to Discord (receives timestamp)
  ```lua
  bot:On("heartbeat", function(timestamp)
      print("Heartbeat sent at:", timestamp)
  end)
  ```

- **`resume`** - Triggered when the bot resumes a previous session
  ```lua
  bot:On("resume", function()
      print("Session resumed successfully")
  end)
  ```

- **`socket_send`** - Triggered after sending any gateway packet
  ```lua
  bot:On("socket_send", function()
      print("Gateway packet sent")
  end)
  ```

- **`rest_send`** - Triggered after REST API calls (receives response data)
  ```lua
  bot:On("rest_send", function(response)
      print("REST API response:", response)
  end)
  ```

#### Event Processing

- **`signal_step`** - Triggered on each Discord gateway event received (before specific handlers)
  ```lua
  bot:On("signal_step", function()
      -- Useful for metrics, logging, or rate limiting
      print("Processing gateway event...")
  end)
  ```

- **`undefined`** - Catches all Discord events that don't have specific handlers
  ```lua
  bot:On("undefined", function(data, eventName)
      print("Unhandled event:", eventName)
      print("Data:", data)
  end)
  ```

## Extending Noctari

The module provides global extension points for adding custom functionality to all bot instances.

### Global Variables

#### `CreationBoot`

A global table that allows you to inject custom initialization logic into every bot instance during creation. Functions added to this table are executed when `DiscordBot.New()` is called.

**Basic Usage:**
```lua
-- Add initialization logic
table.insert(CreationBoot, function(bot)
    print("Bot created with token:", bot.Token:sub(1, 10) .. "...")
    bot.__CustomState = { initialized = true }
end)

local bot = DiscordBot.New(0, "YOUR_TOKEN")
-- "Bot created with token: YOUR_TOKEN..." is printed
```

#### `ExposedMethods`

A global table for adding custom methods that will be available on ALL bot instances. This is the preferred way to extend bot functionality globally, as it applies to both existing and future bots.

**Basic Usage:**
```lua
-- Add a custom method globally
ExposedMethods.CustomMethod = function(self, arg)
    print("Custom method called with:", arg)
    return "result"
end

-- All bots (even existing ones) now have this method
local bot = DiscordBot.New(0, "YOUR_TOKEN")
bot:CustomMethod("test") -- Works!
```

**How Method Resolution Works:**

When you call `bot:MethodName()`, Noctari searches for the method in this order:

1. **Built-in methods** (`BotMethods`) - Core functionality like `Start()`, `Stop()`, `On()`, etc.
2. **Global extended methods** (`ExposedMethods`) - Methods added via the `ExposedMethods` table
3. **Instance properties** - Direct properties on the bot instance

This means `ExposedMethods` can be used to add new methods without overriding core functionality.

**Example: Adding utility methods**
```lua
-- Add multiple utility methods
ExposedMethods.Log = function(self, level, message)
    print(`[{level:upper()}] [{os.date()}] {message}`)
end

ExposedMethods.GetUptime = function(self)
    return os.time() - (self.__StartTime or os.time())
end

ExposedMethods.IsConnected = function(self)
    return self.__Started and self.__Gateway ~= nil
end

-- Use with any bot
local bot = DiscordBot.New(0, "YOUR_TOKEN")
bot:Log("info", "Bot initialized")
bot:Start()

print("Bot connected:", bot:IsConnected())
print("Uptime:", bot:GetUptime(), "seconds")
```

**Use cases:**
- Adding custom utility methods globally to all bots
- Creating helper functions that all bots can use
- Extending bot functionality without modifying the core module
- Building reusable bot components

**Comparison: `ExposedMethods` vs `CreationBoot`**

```lua
-- ExposedMethods: Global methods for all bots
ExposedMethods.Ping = function(self)
    return "Pong!"
end

-- CreationBoot: Per-instance initialization and instance-specific methods
table.insert(CreationBoot, function(bot)
    -- Initialize instance-specific state
    bot.__StartTime = os.time()
    bot.__MessageCount = 0
    
    -- Track messages for THIS specific bot
    bot:On("message_create", function(message)
        bot.__MessageCount += 1
    end)
end)

local bot1 = DiscordBot.New(0, "TOKEN_1")
local bot2 = DiscordBot.New(0, "TOKEN_2")

-- Both bots have the Ping method from ExposedMethods
print(bot1:Ping()) -- "Pong!"
print(bot2:Ping()) -- "Pong!"

-- But each has independent message counters from CreationBoot
bot1:Start()
bot2:Start()
-- bot1.__MessageCount and bot2.__MessageCount are tracked separately
```

**When to use each:**
- **`ExposedMethods`**: For shared utility functions that don't need per-instance state
- **`CreationBoot`**: For initialization logic, instance-specific state, and per-bot customization

**Example: Combining ExposedMethods and CreationBoot**

```lua
-- Global logging method using ExposedMethods
ExposedMethods.Log = function(self, level, message)
    print(`[{level:upper()}] [{self.Token:sub(1, 6)}...] {message}`)
end

-- Per-instance setup using CreationBoot
table.insert(CreationBoot, function(bot)
    bot.__EventLog = {}
    
    -- Track all events for this specific bot
    local originalOn = bot.On
    bot.On = function(self, event, callback)
        return originalOn(self, event, function(...)
            table.insert(self.__EventLog, {
                event = event,
                timestamp = os.time()
            })
            return callback(...)
        end)
    end
end)

-- Add method to view event log
ExposedMethods.GetEventLog = function(self)
    return self.__EventLog
end

-- Usage
local bot = DiscordBot.New(0, "YOUR_TOKEN")
bot:Log("info", "Bot initialized") -- Uses ExposedMethods

bot:On("ready", function()
    bot:Log("info", "Bot is ready!")
end)

bot:Start()
-- Later: Check event log (tracked per-instance via CreationBoot)
print("Total events:", #bot:GetEventLog())
```

#### `exposedbots`

A global table that stores all created bot instances, indexed by their token. This allows you to retrieve existing bot instances from anywhere in your code.

```lua
-- Create a bot
local bot1 = DiscordBot.New(0, "TOKEN_1")

-- Later, retrieve it from anywhere
local bot2 = DiscordBot.FromGlobal("TOKEN_1")
print(bot1 == bot2) -- true

-- Access all active bots
for token, bot in pairs(exposedbots) do
    print("Active bot with token:", token:sub(1, 10) .. "...")
end
```

**Use cases:**
- Singleton pattern for bot instances
- Managing multiple bots from a central location
- Debugging and introspection
- Shared state between modules

**Example: Multi-bot manager**

```lua
local BotManager = {}

function BotManager.CreateOrGet(token, intents)
    local existing = DiscordBot.FromGlobal(token)
    if existing then
        print("Reusing existing bot instance")
        return existing
    end
    
    print("Creating new bot instance")
    return DiscordBot.New(intents, token)
end

function BotManager.StopAll()
    for token, bot in pairs(exposedbots) do
        print("Stopping bot:", token:sub(1, 10) .. "...")
        bot:Stop()
    end
end

function BotManager.GetActiveBotCount()
    local count = 0
    for _ in pairs(exposedbots) do
        count += 1
    end
    return count
end

-- Usage
local bot = BotManager.CreateOrGet("TOKEN_1", 0)
bot:Start()

print("Active bots:", BotManager.GetActiveBotCount())

-- Cleanup
BotManager.StopAll()
```

### Advanced Extension Example

Combining both global variables to create a comprehensive plugin system:

```lua
-- === PLUGIN 1: Command Handler ===
-- Use ExposedMethods for command-related utilities
ExposedMethods.RegisterCommand = function(self, name, handler)
    if not self.__Commands then
        self.__Commands = {}
    end
    self.__Commands[name] = handler
end

ExposedMethods.HandleCommand = function(self, message)
    if not self.__Commands then return false end
    
    local prefix = self.__CommandPrefix or "!"
    if message.content:sub(1, #prefix) ~= prefix then
        return false
    end
    
    local args = message.content:sub(#prefix + 1):split(" ")
    local commandName = table.remove(args, 1)
    
    if self.__Commands[commandName] then
        self.__Commands[commandName](message, args)
        return true
    end
    
    return false
end

-- Use CreationBoot for initialization
table.insert(CreationBoot, function(bot)
    bot.__Commands = {}
    bot.__CommandPrefix = "!"
    
    -- Auto-handle commands on message_create
    bot:On("message_create", function(message)
        if not message.author.bot then
            bot:HandleCommand(message)
        end
    end)
end)

-- === PLUGIN 2: Statistics Tracker ===
ExposedMethods.GetStats = function(self)
    return {
        reconnects = self.__ReconnectCount or 0,
        events = self.__EventCount or 0,
        commands = self.__CommandCount or 0,
        uptime = os.time() - (self.__StartTime or os.time())
    }
end

table.insert(CreationBoot, function(bot)
    bot.__ReconnectCount = 0
    bot.__EventCount = 0
    bot.__CommandCount = 0
    bot.__StartTime = os.time()
    
    bot:On("resume", function()
        bot.__ReconnectCount += 1
    end)
    
    bot:On("signal_step", function()
        bot.__EventCount += 1
    end)
    
    -- Track command usage
    local originalRegister = ExposedMethods.RegisterCommand
    ExposedMethods.RegisterCommand = function(self, name, handler)
        return originalRegister(self, name, function(...)
            self.__CommandCount += 1
            return handler(...)
        end)
    end
end)

-- === USAGE ===
local bot = DiscordBot.New(512, "YOUR_TOKEN")

-- Register commands using global method
bot:RegisterCommand("ping", function(message, args)
    bot:SendContext("POST", `channels/{message.channel_id}/messages`, {
        content = "Pong!"
    })
end)

bot:RegisterCommand("stats", function(message, args)
    local stats = bot:GetStats()
    bot:SendContext("POST", `channels/{message.channel_id}/messages`, {
        content = `**Bot Statistics**
Reconnections: {stats.reconnects}
Events Processed: {stats.events}
Commands Used: {stats.commands}
Uptime: {stats.uptime}s`
    })
end)

bot:Start()

-- Check stats programmatically
task.delay(60, function()
    print("Stats after 60s:", bot:GetStats())
end)
```

## Examples

### Echo Bot

```lua
local bot = DiscordBot.New(512, "YOUR_TOKEN") -- 512 = MESSAGE_CONTENT intent

bot:On("message_create", function(message)
    if not message.author.bot and message.content:sub(1, 1) == "!" then
        bot:SendContext("POST", `channels/{message.channel_id}/messages`, {
            content = message.content:sub(2)
        })
    end
end)

bot:Start()
```

### Slash Command Handler

```lua
bot:On("interaction_create", function(interaction)
    if interaction.type == 2 then -- APPLICATION_COMMAND
        if interaction.data.name == "hello" then
            bot:SendContext("POST", 
                `interactions/{interaction.id}/{interaction.token}/callback`,
                {
                    type = 4, -- CHANNEL_MESSAGE_WITH_SOURCE
                    data = {
                        content = "Hello, " .. interaction.member.user.username .. "!"
                    }
                }
            )
        end
    end
end)
```

### Error Handling with Chains

```lua
bot:On("message_create", function(message)
    return message
end)
:AndThen(function(message)
    local data = bot:SendContext("GET", `channels/{message.channel_id}`)
    return message, data
end)
:Catch(function(err, message)
    warn("Failed to fetch channel:", err)
    return message
end)
:AndThen(function(message, channelData)
    print("Channel name:", channelData and channelData.name or "Unknown")
end)
```

## Notes

- The module automatically handles Discord reconnections and session resumption
- All REST API calls include automatic `Bot` token authorization
- Gateway intents must be properly configured for events to work
- The Chain API uses a task queue to prevent blocking

## License

This module is provided as-is for use with Discord bots built on Lune.

## Requirements

- [Lune](https://lune-org.github.io/docs) runtime
- Valid Discord bot token
- Properly configured gateway intents
