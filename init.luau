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
        }
    }
}

local module = {}

local BotMethods = {}
BotMethods.__index = BotMethods

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
    __Identify:(self:Private) -> any
}

export type DiscordBot = {
    Intents: number;
    Token: string;
    AppID: number;

    On: (self: DiscordBot, Event: string, Callback: (Packet: any, Event:string?) -> nil) -> DiscordBot;
    Start: (self: DiscordBot) -> DiscordBot;
    Stop: (self: DiscordBot) -> DiscordBot;

    SendSocket:(self:DiscordBot, Packet:any) -> DiscordBot;
    SendContext:(self:DiscordBot, Method:string, Path:string, Body:any?, Headers:{[string]:any}?) -> any;
}

function BotMethods.On(self: DiscordBot & Private, Event: string, Callback)
    self.__ConnectedEvents[Event:lower()] = Callback
    return self
end

function BotMethods.SendSocket(self, Packet)
    if self.__Started and self.__Gateway then
        self.__Gateway:send(serde.encode(Packet))
    end
    return self
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

    Packet = nil::any

    if not ReturnPack.body then return nil end

    local ok, decoded = pcall(function()
        return serde.decode("json", ReturnPack.body)
    end)

    return ok and decoded or ReturnPack.body
end

function BotMethods.__Identify(self)
    local Packet = table.clone(StandardPack)
    Packet.d.token = self.Token
    Packet.d.intents = self.Intents
    self.__Gateway:send(serde.encode("json", Packet))
    Packet = nil
end

function BotMethods.__Resume(self:DiscordBot & Private)
    self.__Gateway:send(serde.encode("json", {
        op = 6,
        d = {
            token = self.Token,
            session_id = self.__SessionID,
            seq = self.__RST
        }
    }))

    if self.__ConnectedEvents["resume"] then
        task.spawn(function()
            self.__ConnectedEvents["resume"]()
        end)
    end
end

function BotMethods.Start(self: DiscordBot & Private)
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

    Gateway = nil
    url = nil

    table.insert(self.__Tasks, task.spawn(function()
        while self.__Started and self.__Gateway do
            local raw = self.__Gateway:next()
            if not raw then continue end

            local Packet = serde.decode("json", raw)
            self.__RST = Packet.s or self.__RST or 0
            raw = nil
            if Packet.t == "READY" then
                self.__SessionID = Packet.d.session_id
                if Packet.d.resume_gateway_url then
                    self.__GatewayURL = Packet.d.resume_gateway_url .. "?v=10&encoding=json"
                end
            end

            if Packet.op == 9 then
                if Packet.d == true then
                    task.wait(1)
                    self:__Resume()
                else
                    task.wait(1)
                    self:__Identify()
                end
            end

            if Packet.t then
                local ev = Packet.t:lower()
                local fn = self.__ConnectedEvents[ev]

                if fn then
                    task.spawn(function()
                        fn(Packet.d, Packet.t)
                    end)
                elseif self.__ConnectedEvents["undefined"] then
                    task.spawn(function()
                        self.__ConnectedEvents["undefined"](Packet.d, Packet.t)
                    end)
                end

                if self.__ConnectedEvents["signalstep"] then
                    task.spawn(function()
                        self.__ConnectedEvents["signalstep"]()
                    end)
                end

                ev = nil
                fn = nil
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

            if self.__ConnectedEvents["heartbeat"] then
                task.spawn(function()
                    self.__ConnectedEvents["heartbeat"](os.time())
                end)
            end
        end
    end))

    local InitialPacket = self:SendContext("GET", "applications/@me")
    self.AppID = InitialPacket.id

    return self
end


function BotMethods.Stop(self:DiscordBot & Private)
    for _, t in ipairs(self.__Tasks) do
        task.cancel(t)
    end
    table.clear(self.__Tasks)

    if self.__Gateway then
        self.__Gateway:close()
    end

    self.__Started = false
end

function module.New(Intents, Token)
    local self = setmetatable({
        Intents = Intents;
        Token = Token;

        __Tasks = {};
        __ConnectedEvents = {};
        __Started = false;

        __SessionID = nil;
        __GatewayURL = nil;
        __RST = 0;
    }, BotMethods)

    return self
end

return module
