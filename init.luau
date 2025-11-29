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

function Chain.new(callback)
    return setmetatable({
        _callback = callback,
        _catch = nil,
        _halt = false,
        _next = nil,

        _lastResults = nil,
        _awaiting = {},
    }, Chain)
end

function Chain:AndThen(fn)
    local nextChain = Chain.new(fn)
    self._next = nextChain
    return nextChain
end

function Chain:Catch(fn)
    local nextChain = Chain.new(nil)
    nextChain._catch = fn
    self._next = nextChain
    return nextChain
end

function Chain:Halt()
    local nextChain = Chain.new(nil)
    nextChain._halt = true
    self._next = nextChain
    return nextChain
end

function Chain:Await()
    local thread = coroutine.running()
    if not thread then
        error("Chain:Await() must be called inside a coroutine.")
    end

    table.insert(self._awaiting, thread)

    local r = { coroutine.yield() }

    if #r == 0 then
        if self._lastResults then
            return table.unpack(self._lastResults)
        end
    end

    return table.unpack(r)
end

function Chain:_execute(...)
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

    if ok and results and #results > 0 then
        self._lastResults = results
    end

    if #self._awaiting > 0 then
        local used = (ok and results and #results > 0)
            and results
            or self._lastResults

        for _, thread in ipairs(self._awaiting) do
            coroutine.resume(thread, table.unpack(used))
        end
        self._awaiting = {}
    end

    if ok then
        if self._next then
            if self._next._halt then
                if self._next._next then
                    return self._next._next:_execute(table.unpack(results))
                end
                return
            end
            return self._next:_execute(table.unpack(results))
        end
        return
    end

    return self:_passError(results)
end


function Chain:_passError(err)
    if self._next and self._next._catch then
        local last = self._lastResults or {}

        local ok, catchResults = pcall(function()
            return { self._next._catch(err, table.unpack(last)) }
        end)

        if self._next._next and self._next._next._halt then
            return
        end

        local useResults

        if ok then
            if catchResults and #catchResults > 0 then
                useResults = catchResults
                self._lastResults = catchResults
            else
                useResults = last
            end
        else
            if self._next._next then
                return self._next._next:_passError(catchResults)
            end
            return
        end

        if self._next._next then
            return self._next._next:_execute(table.unpack(useResults))
        end

        return
    end

    if self._next then
        return self._next:_passError(err)
    end

    return
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
                        chain:_execute(Packet.d, ev)
                    end)
                elseif self.__ConnectedEvents["undefined"] then
                    local undef = self.__ConnectedEvents["undefined"]
                    task.spawn(function()
                        undef:_execute(Packet.d, ev)
                    end)
                end

                local stepChain = self.__ConnectedEvents["signalstep"]
                if stepChain then
                    task.spawn(function()
                        stepChain:_execute()
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
                    chain:_execute(os.time())
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
        self.__Gateway:close()
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
