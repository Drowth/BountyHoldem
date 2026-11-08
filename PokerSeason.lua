-- =========================================================================
-- Bounty Hold'em v1.1.8 by Lee
-- PokerSeason.lua: monthly seasons, chip resets and season badges
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- A season runs for a calendar month. On the 1st, whoever tops your chip
-- leaderboard (your characters and players you've played with) wins that
-- season; every character goes back to the starter stack and the winner
-- keeps a badge under their name on the player frame. Badges stack forever

local N = PokerNet
local Econ = PokerEconomy

PokerSeason = PokerSeason or {}
local S = PokerSeason

local BADGE = POKER_MEDIA .. "season_badge"
local ICON_SIZE  = 16
local ICON_STEP  = 9   -- Badges overlap like a short stack of coins
local MAX_ICONS  = 10  -- Past this the row shows a count instead

-- == Saved data ===========================================================
-- Account-wide PokerSeasonDB: current season, winner of each past season and
-- badge counts seen from other players. Per character: PokerChipsDB.season
-- and PokerChipsDB.badges (list of season keys won)
local function SDB()
    PokerSeasonDB = PokerSeasonDB or {}
    local d = PokerSeasonDB
    d.winners = d.winners or {}
    d.counts = d.counts or {}
    return d
end

local function Key(t) return date("%Y-%m", t) end

local function Label(key)
    local y, m = key:match("^(%d+)-(%d+)$")
    if not y then return key end
    return date("%B %Y", time({ year = tonumber(y), month = tonumber(m), day = 15, hour = 12 }))
end

-- Midnight on the 1st of next month
local function SeasonEnd()
    local t = date("*t")
    local y, m = t.year, t.month + 1
    if m > 12 then y, m = y + 1, 1 end
    return time({ year = y, month = m, day = 1, hour = 0, min = 0, sec = 0 })
end

local function Badges()
    if not PokerChipsDB then return {} end
    PokerChipsDB.badges = PokerChipsDB.badges or {}
    return PokerChipsDB.badges
end

local function IsBot(name)
    local names = PokerHost and PokerHost.BOT_NAMES
    if not names then return false end
    for _, b in ipairs(names) do if b == name then return true end end
    return false
end

-- == Badge row on the player frame ========================================
local row
local function BuildRow()
    local frame = _G["PlayerFrame"]
    if not frame then return end
    local name = _G["PlayerName"] or frame.name
    row = CreateFrame("Frame", "PokerSeasonBadgeRow", frame)
    row:SetSize(ICON_SIZE, ICON_SIZE)
    row:SetFrameLevel(frame:GetFrameLevel() + 10)
    if name then
        row:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    else
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 106, -36)
    end
    row.icons = {}
    for i = 1, MAX_ICONS do
        local tex = row:CreateTexture(nil, "OVERLAY", nil, i % 8)
        tex:SetTexture(BADGE)
        tex:SetSize(ICON_SIZE, ICON_SIZE)
        tex:SetPoint("LEFT", row, "LEFT", (i - 1) * ICON_STEP, 0)
        tex:Hide()
        row.icons[i] = tex
    end
    row.count = row:CreateFontString(nil, "OVERLAY")
    row.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    row.count:SetTextColor(1, 0.82, 0.25)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local list = Badges()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Bounty Hold'em season champion", 1, 0.82, 0.25)
        for i = #list, 1, -1 do GameTooltip:AddLine(Label(list[i]), 1, 1, 1) end
        GameTooltip:AddLine("Top of the chip leaderboard when the month ended", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function RefreshRow()
    if not row then BuildRow() end
    if not row then return end
    local n = #Badges()
    local shown = math.min(n, MAX_ICONS)
    for i, tex in ipairs(row.icons) do tex:SetShown(i <= shown) end
    row.count:ClearAllPoints()
    row.count:SetPoint("LEFT", row, "LEFT", (shown - 1) * ICON_STEP + ICON_SIZE + 2, 0)
    row.count:SetText(n > MAX_ICONS and ("x" .. n) or "")
    row:SetWidth(math.max(ICON_SIZE, (shown - 1) * ICON_STEP + ICON_SIZE))
    row:SetShown(n > 0)
end

-- == Sharing badge counts with the group ==================================
local shareQueued
local function Share()
    shareQueued = false
    local me = N.MyName()
    if not me then return end
    SDB().counts[me] = #Badges()
    if IsInGroup and IsInGroup() then N.Send("BADGES:" .. me .. ":" .. #Badges()) end
end
local function QueueShare(delay)
    if shareQueued then return end
    shareQueued = true
    C_Timer.After(delay, Share)
end

N.AddCommandHandler(function(cmd)
    local name, n = cmd:match("^BADGES:([^:]+):(%d+)$")
    if name and not IsBot(name) then SDB().counts[name] = tonumber(n) end
end)

-- == Season rollover ======================================================
local function Busy()
    return (Econ.IsSeated and Econ.IsSeated()) or (PokerHost and PokerHost.active)
end

-- Highest balance on this account's board when the month ended
local function TopOfBoard()
    local best, bestChips
    for name, e in pairs(PokerLeaderDB or {}) do
        local chips = type(e) == "table" and tonumber(e.chips)
        if chips and (e.mine or e.played) and not IsBot(name) then
            if not best or chips > bestChips or (chips == bestChips and name < best) then
                best, bestChips = name, chips
            end
        end
    end
    return best, bestChips
end

local function Check()
    if not PokerChipsDB or Busy() then return end
    local now = Key()
    local d = SDB()
    -- The first character on the account to log in after the 1st closes the season
    if d.season and d.season < now then
        local winner, chips = TopOfBoard()
        if winner then
            d.winners[d.season] = winner
            print(("|cff00cccc[Poker]|r The %s season is over. Champion: |cffffd100%s|r with %d chips.")
                :format(Label(d.season), winner, chips))
        end
        if PokerLeaderDB then wipe(PokerLeaderDB) end
    end
    d.season = now
    -- Then each character collects any badge and resets on its own login
    local db = PokerChipsDB
    if db.season and db.season < now then
        local me, list, won = N.MyName(), Badges(), 0
        local have = {}
        for _, k in ipairs(list) do have[k] = true end
        for k, name in pairs(d.winners) do
            if name == me and k >= db.season and k < now and not have[k] then
                list[#list + 1] = k
                won = won + 1
            end
        end
        table.sort(list)
        Econ.SeasonReset()
        if won > 0 then
            print(("|cff00cccc[Poker]|r |cffffd100You won the season!|r Your badge is under your name. Badges: %d."):format(#list))
            PlaySoundFile(POKER_MEDIA .. "win.ogg", "SFX")
        end
        print(("|cff00cccc[Poker]|r New season: %s. Everyone starts again on %d chips.")
            :format(Label(now), Econ.STARTER_CHIPS))
        QueueShare(2)
    end
    db.season = now
    RefreshRow()
end

-- == Leaderboard text =====================================================
function S.Tag(name)
    local n = tonumber(SDB().counts[name]) or 0
    if n <= 0 then return "" end
    return " |T" .. BADGE .. ":12:12:0:0|t" .. (n > 1 and ("|cffffd100" .. n .. "|r") or "")
end

function S.Title()
    return "Chip leaderboard: " .. date("%B")
end

function S.Foot()
    local days = math.max(0, math.ceil((SeasonEnd() - time()) / 86400))
    if days <= 1 then return "Season ends tonight at midnight" end
    return ("Players you've played with. Season ends in %d days"):format(days)
end

-- == Events ===============================================================
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event)
    if event == "GROUP_ROSTER_UPDATE" then QueueShare(6) return end
    -- After the chip pot has noted this character's final balance (it runs at +0)
    C_Timer.After(1, function()
        local ok, err = pcall(Check)
        if not ok then print("|cff00cccc[Poker]|r Season check failed: " .. tostring(err)) end
        QueueShare(6)
        C_Timer.NewTicker(60, function() pcall(Check) end)
    end)
end)
