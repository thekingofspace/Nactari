local task = require("@lune/task")
local net = require("@lune/net")
local serde = require("@lune/serde")

local GatewayURL = "wss://gateway.discord.gg/?v=10&encoding=json"
local EndPoint = "https://discord.com/api/v10"

local StandardPack = {
    op = 2;
    d = {
        token = "TOKEN HERE";
        intents = 0;
        properties = {
            os = "linux";
            browser = "noctari_prime";
            device = "noctari_prime";
        },
        shard = {0, 1};
    }
}

local Chain = {}
Chain.__index = Chain

local function cloneNode(node, parent)
    local new = setmetatable({
        _callback    = node._callback,
        _catch       = node._catch,
        _halt        = node._halt,
        _next        = nil,
        _parent      = parent,

        _lastResults = nil,
        _awaiting    = nil,
        _root        = node._root or node,

        __destroyed  = false,
    }, Chain)

    if node._next then
        new._next = cloneNode(node._next, new)
    end

    return new
end


function Chain.new(callback)
    local root = setmetatable({
        _callback = callback,
        _catch    = nil,
        _halt     = false,
        _next     = nil,

        _waiters  = {},
        _parent   = nil,

        _root     = nil,
    }, Chain)

    root._root = root
    return root
end

function Chain:AndThen(fn)
    local next = Chain.new(fn)
    self._next = next
    next._parent = self
    next._root = self._root
    return next
end

function Chain:Catch(fn)
    local next = Chain.new(nil)
    next._catch = fn
    self._next = next
    next._parent = self
    next._root = self._root
    return next
end

function Chain:Halt()
    local next = Chain.new(nil)
    next._halt = true
    self._next = next
    next._parent = self
    next._root = self._root
    return next
end


function Chain:Await()
    if self._root ~= self then
        error("Await() must be called on the base chain only.")
    end

    local thread = coroutine.running()
    if not thread then
        error("Await() must be inside a coroutine.")
    end

    local waiter = { thread = thread }
    table.insert(self._waiters, waiter)

    return coroutine.yield()
end


function Chain:spawn()
    return cloneNode(self._root, nil)
end


local function destroyChain(runtime)
    if runtime.__destroyed then return end
    runtime.__destroyed = true
    
    if runtime._next then
        destroyChain(runtime._next)
    end
    
    runtime._callback = nil
    runtime._catch = nil
    runtime._next = nil
    runtime._parent = nil
    runtime._lastResults = nil
    runtime._awaiting = nil
    runtime._root = nil
    
    if runtime._waiters then
        runtime._waiters = nil
    end
end


function Chain:_finish(results)
    if self.__destroyed then return end

    local root = self._root
    
    if root and root._waiters then
        local waiter = table.remove(root._waiters, 1)
        
        if waiter then
            if results and #results > 0 then
                coroutine.resume(waiter.thread, table.unpack(results))
            else
                coroutine.resume(waiter.thread)
            end
        end
        
        if #root._waiters == 0 then
            root._waiters = {}
        end
    end

    destroyChain(self)
    return results
end

function Chain:_passError(err)
    if self.__destroyed then return end

    if self._next and self._next._catch then
        local last = self._lastResults or {}
        local use

        local ok, catchResults = pcall(function()
            return { self._next._catch(err, table.unpack(last)) }
        end)

        if ok then
            use = (catchResults and #catchResults > 0) and catchResults or last
        else
            if self._next._next then
                return self._next:_passError(catchResults)
            end
            return self:_finish(last)
        end

        if self._next._next and self._next._next._halt then
            return self:_finish(use)
        end

        if self._next._next then
            return self._next._next:_execute(table.unpack(use))
        end

        return self:_finish(use)
    end

    if self._next then
        return self._next:_passError(err)
    end

    return self:_finish(self._lastResults or {})
end



function Chain:_execute(...)
    if self.__destroyed then return end

    if self._halt then
        return self:_finish(self._lastResults)
    end

    local incoming = { ... }
    if #incoming > 0 then
        self._lastResults = incoming
    end

    local ok, results

    if self._callback then
        ok, results = pcall(function(...)
            return { self._callback(...) }
        end, ...)
    else
        ok = true
        results = incoming
    end

    if ok then
        if results and #results > 0 then
            self._lastResults = results
        end

        if self._next then
            if self._next._halt then
                return self:_finish(self._lastResults)
            end

            return self._next:_execute(table.unpack(results))
        end

        return self:_finish(self._lastResults)
    end

    return self:_passError(results)
end

function Chain:Run(...)
    local runtime = self:spawn()
    return runtime:_execute(...)
end

function Chain:Destroy()
    if self._root == self then
        if self._waiters then
            for _, waiter in ipairs(self._waiters) do
                pcall(coroutine.resume, waiter.thread, nil)
            end
            self._waiters = {}
        end
    end
    
    destroyChain(self)
end


local module = {}

local BotMethods = {}
BotMethods.__index = BotMethods

export type Chain = {
    AndThen: (self: Chain, fn: (...any) -> ...any) -> Chain,
    Catch: (self: Chain, fn: (err: any, ...any) -> ...any) -> Chain,
    Await:(self:Chain) -> ...any;
    Halt:(self:Chain) -> Chain
}

export type Private = {
    __ConnectedEvents: {};
    __RST: number;
    __HeartCount: number;
    __Gateway: net.WebSocket;
    __Started: boolean;
    __Tasks:{any};

    __SessionID: string?;
    __GatewayURL: string?;
    __Resume:(self:Private) -> any;
    __Identify:(self:Private) -> any;
    __ShardList:{DiscordBot};

    ShardID: number;
    ShardCount: number;
}

export type DiscordBot = {
    Intents: number;
    Token: string;
    AppID: number;

    ShardID: number;
    ShardCount: number;

    On:(self:DiscordBot, Event:string, Callback:(Packet:any, Event:string?) -> nil) -> Chain;
    Start:(self:DiscordBot) -> DiscordBot;
    Stop:(self:DiscordBot) -> DiscordBot;

    SendSocket:(self:DiscordBot, Packet:any) -> DiscordBot;
    SendContext:(self:DiscordBot, Method:string, Path:string, Body:any?, Headers:{[string]:any}?) -> any;

    Fracture:(self:DiscordBot, ShardID:number, ShardCount:number) -> DiscordBot;
    GetShards:(self:DiscordBot) -> { DiscordBot };
    Grab:(self:DiscordBot, Event:string) -> Chain?;
}

function BotMethods.__Identify(self)
    local Packet = table.clone(StandardPack)
    Packet.d.token = self.Token
    Packet.d.intents = self.Intents
    Packet.d.shard = { self.ShardID, self.ShardCount }

    self.__Gateway:send(serde.encode("json", Packet))
end

function BotMethods.Fracture(self:DiscordBot & Private, ShardID:number, ShardCount:number)
    local NewBot = module.New(self.Intents, self.Token, ShardID, ShardCount)

    for name, callback in pairs(self.__ConnectedEvents) do
        NewBot.__ConnectedEvents[name] = callback
    end

    NewBot.AppID = self.AppID
    table.insert(self.__ShardList, NewBot)

    return NewBot
end

function BotMethods.On(self, Event, Callback)
    local ev = Event:lower()

    local chain = Chain.new(Callback)
    self.__ConnectedEvents[ev] = chain

    return chain
end

function BotMethods.SendSocket(self, Packet)
    if self.__Started and self.__Gateway then
        self.__Gateway:send(serde.encode(Packet))
    end
    return self
end

function BotMethods.Grab(self, Event:string): Chain?
    return self.__ConnectedEvents[Event:lower()]
end

function BotMethods.SendContext(self, Method, Path, Body, Headers)
    local Packet = {
        url = `{EndPoint}/{Path}`;
        method = Method:upper();
        headers = {
            ["Authorization"] = `Bot {self.Token}`;
            ["Content-Type"] = "application/json";
        }
    }

    if Headers then
        for k, v in pairs(Headers) do
            Packet.headers[k] = v
        end
    end

    if Body then
        Packet.body = typeof(Body) == "table"
            and serde.encode("json", Body)
            or Body
    end

    local ReturnPack = net.request(Packet)
    if ReturnPack.statusCode > 400 then
        error(`[ERROR CODE {ReturnPack.statusCode}]: {ReturnPack.statusMessage}, \n\n {ReturnPack.body}`)
    end

    if not ReturnPack.body then return nil end

    local ok, decoded = pcall(function()
        return serde.decode("json", ReturnPack.body)
    end)

    return ok and decoded or ReturnPack.body
end


function BotMethods.__Resume(self)
    self.__Gateway:send(serde.encode("json", {
        op = 6,
        d = {
            token = self.Token,
            session_id = self.__SessionID,
            seq = self.__RST
        }
    }))

    local chain = self.__ConnectedEvents["resume"]
    if chain then
        task.spawn(function()
            chain:_execute()
        end)
    end
end

function BotMethods.Start(self)
    if self.__Started then return end
    self.__Started = true

    local url = self.__GatewayURL or GatewayURL
    local Gateway = net.socket(url)
    self.__Gateway = Gateway

    if self.__SessionID ~= nil and self.__RST ~= nil then
        self:__Resume()
    else
        self:__Identify()
    end

    local Hello = serde.decode("json", Gateway:next())
    self.__HeartCount = Hello.d.heartbeat_interval / 1000

    table.insert(self.__Tasks, task.spawn(function()
        while self.__Started and self.__Gateway do
            local raw = self.__Gateway:next()
            if not raw then continue end

            local Packet = serde.decode("json", raw)
            self.__RST = Packet.s or self.__RST or 0

            if Packet.t == "READY" then
                self.__SessionID = Packet.d.session_id
                if Packet.d.resume_gateway_url then
                    self.__GatewayURL = Packet.d.resume_gateway_url .. "?v=10&encoding=json"
                end
            end

            if Packet.op == 9 then
                task.wait(1)
                if Packet.d == true then
                    self:__Resume()
                else
                    self:__Identify()
                end
            end

            if Packet.t then
                local ev = Packet.t:lower()
                local chain = self.__ConnectedEvents[ev]

                if chain then
                    task.spawn(function()
                        chain:Run(Packet.d, ev)
                    end)
                elseif self.__ConnectedEvents["undefined"] then
                    local undef = self.__ConnectedEvents["undefined"]
                    task.spawn(function()
                        undef:Run(Packet.d, ev)
                    end)
                end

                local stepChain = self.__ConnectedEvents["signalstep"]
                if stepChain then
                    task.spawn(function()
                        stepChain:Run()
                    end)
                end
            end
        end
    end))

    table.insert(self.__Tasks, task.spawn(function()
        while self.__Started and self.__Gateway do
            task.wait(self.__HeartCount)

            if not self.__Gateway then break end

            self.__Gateway:send(serde.encode("json", {
                op = 1;
                d = self.__RST or 0;
            }))

            local chain = self.__ConnectedEvents["heartbeat"]
            if chain then
                task.spawn(function()
                    chain:Run(os.time())
                end)
            end
        end
    end))

    local InitialPacket = self:SendContext("GET", "applications/@me")
    self.AppID = InitialPacket.id

    return self
end

function BotMethods.Stop(self)
    for _, t in ipairs(self.__Tasks) do
        task.cancel(t)
    end
    table.clear(self.__Tasks)

    if self.__Gateway then
        self.__Gateway:close(4000)
    end

    self.__Started = false
end

function BotMethods.GetShards(self)
    return self.__ShardList
end

function module.New(Intents:number, Token:string, ShardID:number?, ShardCount:number?):DiscordBot
    local self = setmetatable({
        Intents = Intents;
        Token = Token;

        ShardID = ShardID or 0;
        ShardCount = ShardCount or 1;

        __Tasks = {};
        __ConnectedEvents = {};
        __Started = false;

        __SessionID = nil;
        __GatewayURL = nil;
        __RST = 0;

        __ShardList = {};
    }, BotMethods)

    return self
end

return module
