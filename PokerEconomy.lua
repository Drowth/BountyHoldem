-- =========================================================================
-- Bounty Hold'em v1.1.7 by Lee
-- PokerEconomy.lua: chip earning, saved balance and table sync
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- Kills earn chips, saved per character in PokerChipsDB. Your full balance
-- is your stack when seated, and the host's BANKROLL_SET messages keep the
-- saved balance in step during play

local N = PokerNet

PokerEconomy = PokerEconomy or {}
local Econ = PokerEconomy

-- == Tuning ===============================================================
Econ.STARTER_CHIPS = 200   -- One-time grant on a character's first load
Econ.DAILY_CAP     = 1000  -- Daily cap on chips earned from kills
Econ.REWARDS = {
    normal    = 1,
    elite     = 5,
    rare      = 25,
    rareelite = 30,
    boss      = 100,
    trivial   = 0, -- Trivial and minus mobs (small adds, swarms) pay nothing
    minus     = 0,
}
Econ.SUMMARY_DELAY = 4 -- Seconds to gather kill payouts into one chat line

local db
local function Today() return date("%Y-%m-%d") end

local function EnsureDB()
    PokerChipsDB = PokerChipsDB or {}
    db = PokerChipsDB
    if not db.initialised then
        db.chips = Econ.STARTER_CHIPS
        db.pending = 0
        db.totalEarned = 0
        db.initialised = true
        db.starterGiven = true
    end
    db.chips = db.chips or 0
    db.pending = db.pending or 0
    if db.day ~= Today() then
        db.day = Today()
        db.earnedToday = 0
    end
end

local function Seated() return playerSeat ~= nil end

function Econ.Balance()
    if not db then return 0 end
    return (db.chips or 0) + (db.pending or 0)
end

local balanceText
local function RefreshDisplay()
    if balanceText then
        balanceText:SetText(("Chips: |cffffff00%d|r"):format(Econ.Balance()))
    end
end
Econ.RefreshDisplay = RefreshDisplay

-- Chips earned while seated go to "pending" so the table's authoritative stack
-- cannot overwrite them; they are added back when you stand up
local function FoldPending()
    if db.pending and db.pending > 0 then
        db.chips = db.chips + db.pending
        db.pending = 0
    end
    RefreshDisplay()
    if Econ.OnBalanceChanged then Econ.OnBalanceChanged() end
end

local practice = false -- Set by a PRACTICE:1 table; results there are not saved

local function SetFromTable(amount)
    amount = tonumber(amount)
    if not amount or practice then return end
    db.chips = math.max(0, math.floor(amount))
    RefreshDisplay()
    if Econ.OnBalanceChanged then Econ.OnBalanceChanged() end
end

-- == Earning ==============================================================
local summary = { chips = 0, kills = 0, best = nil, scheduled = false, capped = false }

local function FlushSummary()
    summary.scheduled = false
    if summary.kills == 0 then
        if summary.capped then print("|cff00cccc[Poker]|r Daily chip cap reached. Kills pay again tomorrow.") end
        summary.capped = false
        return
    end
    local extra = summary.best and (" incl. " .. summary.best) or ""
    -- The chip pot already shows each gain, so the chat line is opt-in (/poker killchat)
    if db and db.killChat then print(("|cff00cccc[Poker]|r |cff90ee90+%d chips|r from %d kill%s%s. Balance: |cffffff00%d|r")
        :format(summary.chips, summary.kills, summary.kills == 1 and "" or "s", extra, Econ.Balance())) end
    if summary.capped then
        print("|cff00cccc[Poker]|r Daily chip cap reached. Kills pay again tomorrow.")
    end
    summary.chips, summary.kills, summary.best, summary.capped = 0, 0, nil, false
end

local function Award(amount, label)
    EnsureDB()
    if amount <= 0 then return end
    local room = Econ.DAILY_CAP - (db.earnedToday or 0)
    if room <= 0 then
        if not db.capWarned or db.capWarned ~= db.day then
            db.capWarned = db.day
            summary.capped = true
            if not summary.scheduled then
                summary.scheduled = true
                C_Timer.After(Econ.SUMMARY_DELAY, FlushSummary)
            end
        end
        return
    end
    amount = math.min(amount, room)
    db.earnedToday = (db.earnedToday or 0) + amount
    db.totalEarned = (db.totalEarned or 0) + amount
    if Seated() then
        db.pending = db.pending + amount
    else
        db.chips = db.chips + amount
    end
    if db.earnedToday >= Econ.DAILY_CAP then summary.capped = true end

    summary.chips = summary.chips + amount
    summary.kills = summary.kills + 1
    if label and label ~= "normal" then summary.best = label end
    if not summary.scheduled then
        summary.scheduled = true
        C_Timer.After(Econ.SUMMARY_DELAY, FlushSummary)
    end
    RefreshDisplay()
    if Econ.OnEarn then Econ.OnEarn(amount, label) end
end

-- == Daily bonus =========================================================
-- Opening poker pays a bonus once every 24 hours (real time, per character).
-- It sits outside the kill cap
Econ.DAILY_BONUS = 100
Econ.DAILY_COOLDOWN = 24 * 60 * 60

function Econ.ClaimDaily()
    EnsureDB()
    local now = time()
    local last = tonumber(db.lastDaily) or 0
    if now - last < Econ.DAILY_COOLDOWN then return false end
    db.lastDaily = now
    local amount = Econ.DAILY_BONUS
    if Seated() then
        db.pending = (db.pending or 0) + amount
    else
        db.chips = (db.chips or 0) + amount
    end
    RefreshDisplay()
    if Econ.OnEarn then Econ.OnEarn(amount, "daily") end
    print(("|cff00cccc[Poker]|r Daily bonus: |cff90ee90+%d chips|r. Come back in 24 hours for the next one.")
        :format(amount))
    return true
end

-- Highest grey mob level for the player's level: the game's value when the
-- client provides it, otherwise the classic formula
local function GreyLevel()
    if UnitQuestTrivialLevelRange then
        local ok, range = pcall(UnitQuestTrivialLevelRange, "player")
        if ok and type(range) == "number" then
            return UnitLevel("player") - range
        end
    end
    local lvl = UnitLevel("player")
    if lvl <= 5 then return 0
    elseif lvl <= 39 then return lvl - 5 - math.floor(lvl / 10)
    elseif lvl <= 59 then return lvl - 1 - math.floor(lvl / 5)
    else return lvl - 9 end
end

-- == Kill detection =======================================================
-- Newer clients hide combat log data ("secret values"), so kills come from
-- three guarded sources:
--   1. The combat log, where this client still allows it
--   2. Otherwise the "X dies, you gain N experience" line, which only XP-worthy
--      mobs produce, so greys never pay
--   3. ENCOUNTER_END for dungeon and raid bosses
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

-- Mob info gathered from target, mouseover, nameplates and boss frames
local mobByGUID = {}  -- Keyed by GUID: { kind, grey, t }
local mobByName = {}  -- Keyed by name: { kind, grey, t }

local function Classify(unit)
    local class = UnitClassification(unit)
    local level = UnitLevel(unit)
    if IsSecret(class) then class = "normal" end
    if IsSecret(level) then level = 0 end
    class = class or "normal"
    level = level or 0
    if class == "worldboss" or level == -1 or unit:match("^boss%d") then return "boss", false end
    local kind = (class == "rareelite" or class == "rare" or class == "elite"
        or class == "trivial" or class == "minus") and class or "normal"
    return kind, (level > 0 and level <= GreyLevel())
end

local function Learn(unit)
    pcall(function()
        if not UnitExists(unit) or UnitIsPlayer(unit) then return end
        local kind, grey = Classify(unit)
        local info = { kind = kind, grey = grey, t = GetTime() }
        local guid = UnitGUID(unit)
        if guid and not IsSecret(guid) then
            local prev = mobByGUID[guid]
            if prev and prev.kind == "boss" then info.kind = "boss" end
            mobByGUID[guid] = info
        end
        local name = UnitName(unit)
        if name and not IsSecret(name) then mobByName[name] = info end
    end)
end

-- == Source 1: combat log =================================================
local cleuWorks = false
local tagged = {}  -- [guid] = when our group last damaged it
local AFFIL_GROUP = 0x1 + 0x2 + 0x4   -- Self, party and raid flags
local TYPE_PLAYER, REACTION_FRIENDLY = 0x400, 0x10
local DAMAGE_EVENTS = {
    SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true, SPELL_BUILDING_DAMAGE = true,
    DAMAGE_SHIELD = true, DAMAGE_SPLIT = true,
}

local function OnCombatLog()
    local _, sub, _, _, _, srcFlags, _, dstGUID, _, dstFlags = CombatLogGetCurrentEventInfo()
    if IsSecret(sub) or IsSecret(srcFlags) or IsSecret(dstGUID) or IsSecret(dstFlags) then return end
    if DAMAGE_EVENTS[sub] then
        if not srcFlags or bit.band(srcFlags, AFFIL_GROUP) == 0 then return end
        if not dstGUID then return end
        local gtype = dstGUID:match("^(%a+)-")
        if gtype ~= "Creature" and gtype ~= "Vehicle" then return end
        if dstFlags and (bit.band(dstFlags, TYPE_PLAYER) ~= 0 or bit.band(dstFlags, REACTION_FRIENDLY) ~= 0) then return end
        cleuWorks = true
        tagged[dstGUID] = GetTime()
        if not mobByGUID[dstGUID] and UnitGUID("target") == dstGUID then Learn("target") end
    elseif (sub == "UNIT_DIED" or sub == "PARTY_KILL") and dstGUID and tagged[dstGUID] then
        tagged[dstGUID] = nil
        local info = mobByGUID[dstGUID]
        mobByGUID[dstGUID] = nil
        if info and info.grey then return end
        local kind = info and info.kind or "normal"
        if kind == "boss" then return end -- Instance bosses are paid by ENCOUNTER_END
        Award(Econ.REWARDS[kind] or 1, kind)
    end
end

-- == Source 2: XP chat line ===============================================
local xpPattern
do
    -- Localised "%s dies, you gain %d experience." Every variant (rested, group
    -- bonus) shares the same opening, so match only that
    local fmt = COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."
    local head = fmt:match("^(.-%%d)") or fmt
    head = head:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    head = head:gsub("%%s", "(.-)"):gsub("%%d", "%%d+")
    xpPattern = "^" .. head
end

local function OnXPMessage(msg)
    if cleuWorks or type(msg) ~= "string" or IsSecret(msg) then return end
    local name = msg:match(xpPattern)
    if not name or name == "" then return end
    local info = mobByName[name]
    local kind = info and info.kind or "normal"
    if kind == "boss" then return end -- Bosses are paid by ENCOUNTER_END
    Award(Econ.REWARDS[kind] or 1, kind)
end

-- == Source 2b: XP bar rising =============================================
-- Some clients also block the XP chat line, so the main signal is the XP bar:
-- a gain during or just after combat, not from a quest turn-in, counts as a kill
local lastXP, lastMax, lastLevel
local lastQuestAt, inCombat, combatEndedAt = -100, false, -100

local function ReadXP()
    local ok, xp, max, lvl = pcall(function()
        return UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    end)
    if not ok or IsSecret(xp) or IsSecret(max) or IsSecret(lvl) then return nil end
    return xp, max, lvl
end

local function OnXPUpdate()
    local xp, max, lvl = ReadXP()
    if not xp then return end
    local prevXP, prevMax, prevLvl = lastXP, lastMax, lastLevel
    lastXP, lastMax, lastLevel = xp, max, lvl
    if not prevXP then return end
    local gained
    if lvl > prevLvl then
        gained = (prevMax - prevXP) + xp
    else
        gained = xp - prevXP
    end
    if gained <= 0 then return end
    local now = GetTime()
    if now - lastQuestAt < 2 then return end                 -- Quest turn-in
    if not inCombat and now - combatEndedAt > 3 then return end -- Gathering or exploration
    local kind = "normal"
    if UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target") then
        local ok, k = pcall(Classify, "target")
        if ok and k then kind = k end
    end
    if kind == "boss" then return end -- Bosses are paid by ENCOUNTER_END
    Award(Econ.REWARDS[kind] or 1, kind)
end

-- == Source 3: bosses =====================================================
local function OnEncounterEnd(_, _, _, _, success)
    if IsSecret(success) then return end
    if success == 1 or success == true then Award(Econ.REWARDS.boss, "boss") end
end

local function Prune()
    local now = GetTime()
    for g, t in pairs(tagged) do if now - t > 300 then tagged[g] = nil end end
    for g, i in pairs(mobByGUID) do if now - i.t > 600 then mobByGUID[g] = nil end end
    for n, i in pairs(mobByName) do if now - i.t > 600 then mobByName[n] = nil end end
end

-- == Table sync: host commands and our own seat changes ===================
local function OnCommand(cmd, sender)
    if not db then return end
    local me = N.MyName()
    local fromMe = N.ShortName(sender) == me

    if cmd == "PRACTICE:1" then
        if not practice then
            practice = true
            print("|cff00cccc[Poker]|r Practice table: your saved chips will not change here.")
        end
        return
    end
    if cmd == "TABLE_OPENED" or cmd == "TABLE_CLOSED" then
        practice = false
        return
    end

    local n, amt = cmd:match("^BANKROLL_SET:([^:]+):(%d+)")
    if n then
        if n == me and Seated() then SetFromTable(amt) end
        return
    end
    if cmd:match("^BANKROLL_BULK:") then
        for pair in cmd:sub(15):gmatch("([^;]+)") do
            local pn, pa = pair:match("^([^=]+)=(%d+)$")
            if pn == me and Seated() then SetFromTable(pa) end
        end
        return
    end

    local sn = cmd:match("^PLAYER_SAT_DOWN:([^:]+):%d+")
    if sn and sn == me and fromMe then
        FoldPending()
        N.Send("BUYIN:" .. me .. ":" .. Econ.Balance())
        return
    end

    local ln = cmd:match("^PLAYER_LEFT_SEAT:([^:]+):%d+")
    if ln and ln == me and fromMe then
        C_Timer.After(0, FoldPending)
        return
    end
end
N.AddCommandHandler(OnCommand)

-- == Events ===============================================================
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
for _, ev in ipairs({ "PLAYER_XP_UPDATE", "QUEST_TURNED_IN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ENCOUNTER_END",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }) do
    pcall(f.RegisterEvent, f, ev)
end
-- On clients with secret values, even registering for the combat log or combat
-- chat triggers the "blocked from an action" popup, so only register where that
-- system is absent
if not issecretvalue then
    pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
    pcall(f.RegisterEvent, f, "CHAT_MSG_COMBAT_XP_GAIN")
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        EnsureDB()
        if not Seated() then FoldPending() end
        local role = (PokerUI and PokerUI.RoleFrame) or _G["PokerJoinTableFrame"]
        local tbl = (PokerUI and PokerUI.TableFrame) or _G["PokerTableFrame"]
        -- Opening the lobby or the table claims the daily bonus when it is due
        if role then role:HookScript("OnShow", function() pcall(Econ.ClaimDaily) end) end
        if tbl then tbl:HookScript("OnShow", function() pcall(Econ.ClaimDaily) end) end
        if role then
            balanceText = role:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            balanceText:SetPoint("BOTTOMLEFT", role, "BOTTOMLEFT", 16, 12)
            Econ.balanceText = balanceText
        end
        RefreshDisplay()
        C_Timer.NewTicker(60, Prune)
        lastXP, lastMax, lastLevel = ReadXP()
        return
    end
    if not db then return end

    if event == "PLAYER_XP_UPDATE" then
        -- Skip if the XP chat line or combat log already counted this kill
        if issecretvalue then pcall(OnXPUpdate) else lastXP, lastMax, lastLevel = ReadXP() end
        return
    elseif event == "QUEST_TURNED_IN" then
        lastQuestAt = GetTime()
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        combatEndedAt = GetTime()
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        pcall(OnCombatLog)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local msg = ...
        pcall(OnXPMessage, msg)
    elseif event == "ENCOUNTER_END" then
        pcall(OnEncounterEnd, ...)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Learn("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Learn("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        if unit and not IsSecret(unit) then Learn(unit) end
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        for i = 1, 5 do
            local u = "boss" .. i
            if UnitExists(u) then Learn(u) end
        end
    end
end)

function Econ.PrintStatus()
    EnsureDB()
    print(("|cff00cccc[Poker]|r Chips: |cffffff00%d|r. Earned today: %d of %d. Lifetime earned: %d.")
        :format(Econ.Balance(), db.earnedToday or 0, Econ.DAILY_CAP, db.totalEarned or 0))
end
