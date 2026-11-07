-- =========================================================================
-- Bounty Hold'em v1.1.2 by Lee
-- PokerNet.lua: networking layer for every client and the host
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
POKER_OWNER = ...
-- Media path follows the installed folder name, so a renamed package still loads its art
local addonName = ...
POKER_ADDON = addonName or "BountyHoldem"
POKER_MEDIA = "Interface\\AddOns\\" .. POKER_ADDON .. "\\media\\"

-- Shared send and receive code:
--   * Poker_Channel(): RAID, PARTY, or local loopback when solo (for testing)
--   * Throttled send queues per prefix (WoW allows a burst of about 10 addon
--     messages, then roughly 1 per second), so nothing is silently dropped
--   * Batching: the host packs several table commands into one PREFIX_BATCH
--     message; clients unpack and pass each to the poker.lua handlers
--   * Hole cards come by private addon whisper on PREFIX_HOLE, not chat whispers
--   * DEAL_ANIM:n runs the deal animation locally rather than via /roll

PokerNet = PokerNet or {}
local N = PokerNet

N.PREFIX       = "PokerTable" -- Player actions and single messages (original protocol)
N.PREFIX_BATCH = "PokerTblX"  -- Host to table, batched commands
N.PREFIX_HOLE  = "PokerHole"  -- Host to one player, hole cards
N.SEP          = "\n"
N.MAX_LEN      = 250

C_ChatInfo.RegisterAddonMessagePrefix(N.PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(N.PREFIX_BATCH)
C_ChatInfo.RegisterAddonMessagePrefix(N.PREFIX_HOLE)

function N.ShortName(name)
    if not name then return nil end
    return name:match("^([^-]+)") or name
end

function N.MyName()
    return N.ShortName(UnitName("player"))
end

function N.MyFullName()
    local name, realm = UnitFullName("player")
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName())
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- Global, so poker.lua can use it instead of a hard-coded "RAID"
-- Returns channel, target. Solo returns "LOOPBACK": the message stays inside
-- this client, since servers reject addon whispers to yourself
function Poker_Channel()
    if IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return "LOOPBACK"
end

-- Addon-message frames owned by this addon. Loopback only calls these, as
-- calling Blizzard frames from addon code taints them and blocks the addon
N.listeners = N.listeners or {}
function N.AddListener(frame) N.listeners[#N.listeners + 1] = frame end

-- Delivers a message to this client's Poker frames as if the server echoed it
function N.Loopback(prefix, msg)
    local sender = N.MyFullName()
    C_Timer.After(0, function()
        local frames = { _G["PokerJoinTableFrame"], _G["PokerTableFrame"] }
        for _, fr in ipairs(N.listeners) do frames[#frames + 1] = fr end
        for _, frame in ipairs(frames) do
            local fn = frame:GetScript("OnEvent")
            if fn then
                local ok, err = pcall(fn, frame, "CHAT_MSG_ADDON", prefix, msg, "WHISPER", sender)
                if not ok then geterrorhandler()(err) end
            end
        end
    end)
end

-- Replacement for C_ChatInfo.SendAddonMessage, used by poker.lua
function Poker_SendAddonMessage(prefix, msg, chan, target)
    if chan == "LOOPBACK" or (chan == "WHISPER" and target and N.ShortName(target) == N.MyName()) then
        N.Loopback(prefix, msg)
        return true
    end
    return C_ChatInfo.SendAddonMessage(prefix, msg, chan, target)
end

-- == Throttled queue (token bucket per prefix) ============================
local BURST, REGEN = 10, 1.0 -- Bucket size and refill seconds per token
local queues = {}            -- [prefix] = { tokens, last, items = { { msg, chan, target } } }
local pumpScheduled = false

local function GetQueue(prefix)
    local q = queues[prefix]
    if not q then
        q = { tokens = BURST, last = GetTime(), items = {} }
        queues[prefix] = q
    end
    return q
end

local function Refill(q)
    local now = GetTime()
    q.tokens = math.min(BURST, q.tokens + (now - q.last) / REGEN)
    q.last = now
end

local function SendRaw(prefix, msg, chan, target)
    local ok, result = pcall(Poker_SendAddonMessage, prefix, msg, chan, target)
    if not ok then return true end -- Invalid arguments: drop instead of retrying forever
    if result == false then return false end
    if type(result) == "number" and result ~= 0 then
        -- Enum.SendAddonMessageResult: 0 is success; anything else (throttled, no group) failed
        return false
    end
    return true
end

local function Pump()
    pumpScheduled = false
    local waiting = false
    for prefix, q in pairs(queues) do
        Refill(q)
        while #q.items > 0 and q.tokens >= 1 do
            local item = q.items[1]
            if SendRaw(prefix, item[1], item[2], item[3]) then
                table.remove(q.items, 1)
                q.tokens = q.tokens - 1
            else
                q.tokens = 0 -- Throttled by the server; wait for a refill
                break
            end
        end
        if #q.items > 0 then waiting = true end
    end
    if waiting and not pumpScheduled then
        pumpScheduled = true
        C_Timer.After(REGEN, Pump)
    end
end

function N.Queue(prefix, msg, chan, target)
    if not chan then chan, target = Poker_Channel() end
    local q = GetQueue(prefix)
    q.items[#q.items + 1] = { msg, chan, target }
    if not pumpScheduled then
        pumpScheduled = true
        C_Timer.After(0, Pump)
    end
end

-- Single unbatched message on the main prefix
function N.Send(msg)
    N.Queue(N.PREFIX, msg)
end

-- == Host batching ========================================================
-- N.Broadcast gathers this frame's commands and sends them in as few messages as possible
local pending, flushScheduled = {}, false

local function FlushBroadcasts()
    flushScheduled = false
    local buf = ""
    for _, cmd in ipairs(pending) do
        if #cmd > N.MAX_LEN then cmd = cmd:sub(1, N.MAX_LEN) end
        if buf == "" then
            buf = cmd
        elseif #buf + #N.SEP + #cmd <= N.MAX_LEN then
            buf = buf .. N.SEP .. cmd
        else
            N.Queue(N.PREFIX_BATCH, buf)
            buf = cmd
        end
    end
    if buf ~= "" then N.Queue(N.PREFIX_BATCH, buf) end
    wipe(pending)
end

function N.Broadcast(cmd)
    pending[#pending + 1] = cmd
    if not flushScheduled then
        flushScheduled = true
        C_Timer.After(0, FlushBroadcasts)
    end
end

-- Hole cards for one player; fullName is "Name-Realm" or "Name"
function N.SendHole(fullName, c1, c2)
    N.Queue(N.PREFIX_HOLE, "HOLE:" .. c1 .. ":" .. c2, "WHISPER", fullName)
end

-- == Client receive: unpack batches into poker.lua handlers ===============
-- Other modules (economy, HUD) subscribe here to see every table command
N.commandHandlers = N.commandHandlers or {}
function N.AddCommandHandler(fn) N.commandHandlers[#N.commandHandlers + 1] = fn end
local function RunHandlers(cmd, sender)
    for _, fn in ipairs(N.commandHandlers) do
        local ok, err = pcall(fn, cmd, sender)
        if not ok then geterrorhandler()(err) end
    end
end

local dealAnimUntil = 0
local pendingHole

local function Dispatch(cmd, channel, sender)
    local roleFrame = _G["PokerJoinTableFrame"]
    local tableFrame = _G["PokerTableFrame"]
    if roleFrame and roleFrame:GetScript("OnEvent") then
        roleFrame:GetScript("OnEvent")(roleFrame, "CHAT_MSG_ADDON", N.PREFIX, cmd, channel, sender)
    end
    if tableFrame and tableFrame:GetScript("OnEvent") then
        tableFrame:GetScript("OnEvent")(tableFrame, "CHAT_MSG_ADDON", N.PREFIX, cmd, channel, sender)
    end
    -- Pass each command on to subscribed modules
    RunHandlers(cmd, sender)
end

local function ShowHole(c1, c2, sender)
    local tableFrame = _G["PokerTableFrame"]
    if N.OnHole then pcall(N.OnHole, c1, c2) end
    if not tableFrame then return end
    local fn = tableFrame:GetScript("OnEvent")
    if not fn then return end
    -- Route through the original whisper path, which reveals our hole cards
    fn(tableFrame, "CHAT_MSG_WHISPER", "[" .. c1 .. "]", sender)
    fn(tableFrame, "CHAT_MSG_WHISPER", "[" .. c2 .. "]", sender)
end

local function RunDealAnim(count, sender)
    local tableFrame = _G["PokerTableFrame"]
    if not tableFrame then return end
    local fn = tableFrame:GetScript("OnEvent")
    if not fn then return end
    local step = 0.22
    dealAnimUntil = GetTime() + count * step + 0.6
    for i = 1, count do
        C_Timer.After((i - 1) * step, function()
            -- The original CHAT_MSG_SYSTEM handler reads a roll line as "deal next card"
            fn(tableFrame, "CHAT_MSG_SYSTEM", "Dealer rolls 1 (1-100)")
        end)
    end
    C_Timer.After(count * step + 0.6, function()
        if pendingHole then
            local h = pendingHole
            pendingHole = nil
            ShowHole(h[1], h[2], h[3])
        end
    end)
end

local recv = CreateFrame("Frame")
recv:RegisterEvent("CHAT_MSG_ADDON")
N.AddListener(recv)
recv:RegisterEvent("PLAYER_LOGIN")
recv:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
    if event == "PLAYER_LOGIN" then
        -- Cards and deal ticks now arrive only by addon message, so ignore other
        -- players' chat whispers and /roll lines
        local tableFrame = _G["PokerTableFrame"]
        if tableFrame then
            tableFrame:UnregisterEvent("CHAT_MSG_WHISPER")
            tableFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
        end
        return
    end

    if prefix == N.PREFIX_BATCH then
        for cmd in (msg .. N.SEP):gmatch("(.-)" .. N.SEP) do
            if cmd ~= "" then
                local n = cmd:match("^DEAL_ANIM:(%d+)$")
                if n then
                    RunDealAnim(tonumber(n), sender)
                else
                    Dispatch(cmd, channel, sender)
                end
            end
        end
    elseif prefix == N.PREFIX_HOLE then
        local c1, c2 = msg:match("^HOLE:([^:]+):([^:]+)$")
        if c1 and c2 then
            if GetTime() < dealAnimUntil then
                pendingHole = { c1, c2, sender } -- Reveal once our cards have landed
            else
                ShowHole(c1, c2, sender)
            end
        end
    elseif prefix == N.PREFIX then
        RunHandlers(msg, sender)
    end
end)

-- == Old copy check =======================================================
-- An older install in AddOns\Poker runs alongside and doubles every kill, so
-- switch it off for the next load and say how to finish
do
    local check = CreateFrame("Frame")
    check:RegisterEvent("PLAYER_LOGIN")
    check:SetScript("OnEvent", function()
        if POKER_OWNER == "Poker" then return end
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        local disable = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
        if not isLoaded or not disable then return end
        local ok, loaded = pcall(isLoaded, "Poker")
        if not ok or not loaded then return end
        pcall(disable, "Poker")
        C_Timer.After(3, function()
            print("|cff00cccc[Poker]|r An old copy in AddOns\\Poker was also running, so every kill counted twice. "
                .. "It is now switched off: type |cffffe6b3/reload|r, then delete that folder.")
        end)
    end)
end
