-- =========================================================================
-- Bounty Hold'em v1.1.5 by Lee
-- PokerCamp.lua: sitting at a campfire opens the poker window
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- Counts as a campfire when either:
--   * the Cozy Fire buff is on you, or
--   * you lit a Basic Campfire recently and are standing next to it
-- Sit detection: the sit key (X), /sit and the sit emote
--   /poker camp on | off    toggle the campfire trigger (on by default)
-- Some clients return secret event values that error when compared, so every
-- read is guarded and skipped if secret

local COZY_FIRE_SPELL   = 7353   -- Spell id of the Cozy Fire buff
local BASIC_CAMPFIRE    = 818    -- Spell id of Basic Campfire (Cooking)
local FIRE_LIFETIME     = 180    -- How long a lit fire stays valid, in seconds
local FIRE_RANGE        = 9      -- Range to the fire, in yards
local REOPEN_COOLDOWN   = 20     -- Minimum seconds between auto-opens

local fires = {}       -- Each entry: { x, y, map, t }
local sitting = false
local lastOpen = 0

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Calls fn under pcall; any error (secret value, missing API) returns nil
local function Safe(fn, ...)
    local ok, result = pcall(fn, ...)
    return ok and result or nil
end

local function Enabled()
    return not (PokerChipsDB and PokerChipsDB.campOff)
end

local function HasCozyFire()
    return Safe(function()
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(COZY_FIRE_SPELL)
            return aura ~= nil and not IsSecret(aura)
        end
        if UnitBuff then
            for i = 1, 40 do
                local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
                if not name then break end
                if not IsSecret(spellId) and spellId == COZY_FIRE_SPELL then return true end
            end
        end
        return false
    end)
end

local function NearLitFire()
    return Safe(function()
        local y, x, _, map = UnitPosition("player")
        if not x or IsSecret(x) or IsSecret(y) then return false end
        local now = GetTime()
        for i = #fires, 1, -1 do
            local f = fires[i]
            if now - f.t > FIRE_LIFETIME then
                table.remove(fires, i)
            elseif f.map == map then
                local dx, dy = f.x - x, f.y - y
                if dx * dx + dy * dy <= FIRE_RANGE * FIRE_RANGE then return true end
            end
        end
        return false
    end)
end

local function OpenPoker()
    if InCombatLockdown() then return end
    local now = GetTime()
    if now - lastOpen < REOPEN_COOLDOWN then return end
    local role = _G["PokerJoinTableFrame"]
    local tbl = _G["PokerTableFrame"]
    if (role and role:IsShown()) or (tbl and tbl:IsShown()) then return end
    lastOpen = now
    print("|cff00cccc[Poker]|r You settle down by the fire. Fancy a hand?")
    if SlashCmdList["POKER"] then SlashCmdList["POKER"]("") end
end

local function OnSat()
    sitting = true
    if not Enabled() then return end
    C_Timer.After(0.3, function()
        if sitting and (HasCozyFire() or NearLitFire()) then OpenPoker() end
    end)
end

local function OnStood()
    sitting = false
end

if SitStandOrDescendStart then
    hooksecurefunc("SitStandOrDescendStart", function()
        if Safe(function() return IsMounted() or IsFlying() or IsSwimming() end) then return end
        if sitting then OnStood() else OnSat() end
    end)
end

if DoEmote then
    hooksecurefunc("DoEmote", function(emote)
        if type(emote) ~= "string" or IsSecret(emote) then return end
        emote = emote:upper()
        if emote == "SIT" then OnSat()
        elseif emote == "STAND" then OnStood() end
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_STARTED_MOVING")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
f:SetScript("OnEvent", function(_, event, unit, _, spellId)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if IsSecret(spellId) or spellId ~= BASIC_CAMPFIRE then return end
        local ok, y, x, _, map = pcall(UnitPosition, "player")
        if ok and x and not IsSecret(x) then
            fires[#fires + 1] = { x = x, y = y, map = map, t = GetTime() }
        end
        return
    end
    OnStood()
end)

function PokerCamp_SetEnabled(on)
    PokerChipsDB = PokerChipsDB or {}
    PokerChipsDB.campOff = not on
    print("|cff00cccc[Poker]|r Campfire trigger " .. (on and "on" or "off") .. ".")
end
