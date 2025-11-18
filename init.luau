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
    __Tasks:{any}
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
    Drop: (self: DiscordBot) -> nil;
}

function BotMethods.On(self: DiscordBot & Private, Event: string, Callback: (Packet: any) -> nil)
    self.__ConnectedEvents[Event:lower()] = Callback
    return self
end

function BotMethods.SendSocket(self:DiscordBot & Private, Packet:any)
    if self.__Started then
        self.__Gateway:send(serde.encode(Packet))
    end
    return self
end

function BotMethods.SendContext(self:DiscordBot & Private, Method:string, Path:string, Body:any?, Headers:{[string]:string}?)
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
        if typeof(Body) == "table" then
            Packet.body = serde.encode("json", Body)
        else
            Packet.body = Body
        end
    end

    local ReturnPack = net.request(Packet)

    if ReturnPack.statusCode > 400 then
        error(`[ERROR CODE {ReturnPack.statusCode}]: {ReturnPack.statusMessage}, \n\n {ReturnPack.body}`)
    end

    if not ReturnPack.body then
        return nil
    end

    local success, decoded = pcall(function()
        return serde.decode("json", ReturnPack.body)
    end)

    if success then
        return decoded
    else
        return ReturnPack.body
    end
end

function BotMethods.Start(self: DiscordBot & Private)
    if self.__Started then
        return
    end

    self.__Started = true

    local EntryPacket = table.clone(StandardPack)
    EntryPacket.d.token = self.Token
    EntryPacket.d.intents = self.Intents

    local Gateway = net.socket(GatewayURL)
    self.__Gateway = Gateway

    Gateway:send(serde.encode("json", EntryPacket))
    EntryPacket = nil::any

    local Handshake = Gateway:next()
    Handshake = serde.decode("json", Handshake)

    self.__HeartCount = Handshake.d.heartbeat_interval / 1000
    self.__RST = Handshake.s
    Handshake = nil::any

    table.insert(self.__Tasks, task.spawn(function()
        while self.__Started and self.__Gateway do
            local raw = self.__Gateway:next()
            if not raw then continue end

            local Packet = serde.decode("json", raw)
            self.__RST = Packet.s

            if Packet.t then
                local ev = Packet.t:lower()
                local callback = self.__ConnectedEvents[ev]

                if callback then
                    task.spawn(function()
                        callback(Packet.d)
                    end)
                elseif self.__ConnectedEvents["undefined"] then
                    task.spawn(function()
                        self.__ConnectedEvents["undefined"](Packet.d, Packet.t)
                    end)
                end

                ev = nil::any
                callback = nil::any
            end

            raw = nil::any
        end
    end))

    table.insert(self.__Tasks, task.spawn(function()
        while self.__Started and self.__Gateway do
            task.wait(self.__HeartCount)

            if not self.__Gateway then
                break
            end

            self.__Gateway:send(serde.encode("json", {
                op = 1;
                d = self.__RST;
            }))

            if not self.__ConnectedEvents["heartbeat"] then continue end

            self.__ConnectedEvents["heartbeat"](os.time())
        end
    end))

    Gateway = nil::any

    local InitialPacket = self:SendContext("GET", "applications/@me")

    self.AppID = InitialPacket.id

    InitialPacket = nil;

    return self
end

function BotMethods.Stop(self: DiscordBot & Private)
    for I, item in ipairs(self.__Tasks) do
        task.cancel(item)
    end

    table.clear(self.__Tasks)

    self.__Gateway:close()
end


function module.New(Intents: number, Token: string): DiscordBot
    local self: DiscordBot = setmetatable({
        Intents = Intents;
        Token = Token;
        __Tasks = {};
        __ConnectedEvents = {};
        __Started = false;
    }, BotMethods)::any

    return self
end

return module
