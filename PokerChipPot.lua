-- =========================================================================
-- Bounty Hold'em v1.1.2 by Lee
-- PokerChipPot.lua: on-screen chip pot that fills as you earn chips
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- Small movable pot showing your balance; it bounces and a green +N drops in
-- on every kill payout
--   /poker pot        toggle the pot
-- Left-click opens poker, right-click shows the chip leaderboard
-- Drag to move; position is saved per character

local Econ = PokerEconomy

local MEDIA = POKER_MEDIA
local BOUNCE_TIME = 0.5    -- Pot bounce length, in seconds
local GAIN_TIME   = 0.7    -- Time for the +N to drop into the pot

local N = PokerNet
local LB_ROWS  = 15                 -- Most names shown on the leaderboard
local LB_STALE = 30 * 24 * 3600     -- Forget players not seen for 30 days

local pot, countText, shown
local board, RefreshBoard, NoteSelf, QueueShare

local function SavePos()
    if not PokerChipsDB or not pot then return end
    local x, y = pot:GetCenter()
    local s = pot:GetEffectiveScale() / UIParent:GetEffectiveScale()
    PokerChipsDB.potPos = { x = x * s, y = y * s }
end

local function SetCount(n)
    shown = n
    if NoteSelf then NoteSelf(n) end
    countText:SetText(("|cffffff00%d|r"):format(n))
    if pot and pot.label then
        pot.label:SetText(playerSeat and "chips (at table)" or "chips")
    end
end

local function BuildPot()
    pot = CreateFrame("Button", "PokerChipPotFrame", UIParent)
    pot:SetSize(72, 72)
    pot:SetFrameStrata("MEDIUM")
    pot:SetMovable(true)
    pot:EnableMouse(true)
    pot:RegisterForDrag("LeftButton")
    pot:SetClampedToScreen(true)
    pot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pot:SetScript("OnDragStart", function(self) self.dragging = true self:StartMoving() end)
    pot:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePos()
        self.dragging = false
        self.dragEndedAt = GetTime()
    end)
    -- A drag release also fires a click; ignore it
    pot:SetScript("OnClick", function(self, button)
        if self.dragging or GetTime() - (self.dragEndedAt or 0) < 0.2 then return end
        if button == "RightButton" then
            PokerChipPot_ToggleBoard()
        elseif SlashCmdList["POKER"] then
            SlashCmdList["POKER"]("")
        end
    end)

    local pos = PokerChipsDB and PokerChipsDB.potPos
    if pos then
        pot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        pot:SetPoint("RIGHT", UIParent, "RIGHT", -120, 40)
    end

    -- Small pile drawn from the existing chip art, on a child frame so it can hop
    local stack = CreateFrame("Frame", nil, pot)
    stack:SetSize(72, 72)
    stack:SetPoint("CENTER")
    pot.stack = stack
    local pile = {
        { "100chip", 0, 6, 44 }, { "25chip", -14, -2, 40 }, { "5chip", 14, -2, 40 },
        { "1chip", 0, -10, 42 }, { "500chip", -6, 14, 36 }, { "1000chip", 8, 16, 34 },
    }
    for i, c in ipairs(pile) do
        local t = stack:CreateTexture(nil, "ARTWORK", nil, i - 1)
        t:SetTexture(MEDIA .. c[1])
        t:SetSize(c[4], c[4])
        t:SetPoint("CENTER", stack, "CENTER", c[2], c[3])
    end

    countText = pot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    countText:SetPoint("TOP", pot, "BOTTOM", 0, 2)

    local label = pot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pot.label = label
    label:SetPoint("TOP", countText, "BOTTOM", 0, -1)
    label:SetText("chips")

    -- Bounce: the pile hops with a damped sine and the count pulses
    pot.bump = { t = nil }
    function pot.bump:IsPlaying() return self.t ~= nil end
    function pot.bump:Stop()
        self.t = nil
        stack:ClearAllPoints()
        stack:SetPoint("CENTER")
        countText:SetTextHeight(16)
    end
    function pot.bump:Play() self.t = 0 end
    pot:SetScript("OnUpdate", function(self, elapsed)
        local b = self.bump
        if not b.t then return end
        b.t = b.t + elapsed
        if b.t >= BOUNCE_TIME then b:Stop() return end
        local k = b.t / BOUNCE_TIME
        local hop = math.abs(math.sin(k * math.pi * 2.5)) * 10 * (1 - k)
        stack:ClearAllPoints()
        stack:SetPoint("CENTER", pot, "CENTER", 0, hop)
        countText:SetTextHeight(16 + 6 * (1 - k))
    end)

    pot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Poker chips", 1, 1, 1)
        local db = PokerChipsDB or {}
        GameTooltip:AddLine(("Earned today: %d / %d"):format(db.earnedToday or 0, Econ.DAILY_CAP), 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Kill mobs to earn chips.", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Left-click: open poker", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click: chip leaderboard", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Drag to move", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("/poker pot to hide", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    pot:SetScript("OnLeave", function() GameTooltip:Hide() end)

    SetCount(Econ.Balance())
    if PokerChipsDB and PokerChipsDB.potHidden then pot:Hide() end
end

-- Green +N that drops into the pot and fades; strings are pooled
local gainPool = {}
local function ShowGain(amount)
    local g = table.remove(gainPool)
    if not g then
        g = CreateFrame("Frame", nil, pot)
        g:SetSize(80, 24)
        g:SetFrameLevel(pot:GetFrameLevel() + 5)
        g.text = g:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        g.text:SetPoint("CENTER")
        g.text:SetTextColor(0.2, 1, 0.2)
    end
    g.text:SetText("+" .. amount)
    local t = 0
    g:SetAlpha(1)
    g:Show()
    g:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        local k = math.min(1, t / GAIN_TIME)
        local e = 1 - (1 - k) * (1 - k) -- Ease out
        self:ClearAllPoints()
        self:SetPoint("CENTER", pot, "CENTER", 0, 50 - 45 * e)
        self:SetAlpha(k < 0.6 and 1 or (1 - k) / 0.4)
        if k >= 1 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            gainPool[#gainPool + 1] = self
        end
    end)
end

local function OnEarn(amount, kind)
    if not pot then return end
    if not pot:IsShown() then SetCount(Econ.Balance()) return end
    ShowGain(amount)
    -- Count and bounce land as the +N reaches the pot
    C_Timer.After(GAIN_TIME * 0.6, function()
        SetCount(Econ.Balance())
        if pot.bump:IsPlaying() then pot.bump:Stop() end
        pot.bump:Play()
        PlaySoundFile(MEDIA .. "chips.MP3", "SFX")
    end)
end

local function OnEarnSafe(amount, kind)
    pcall(OnEarn, amount, kind)
    QueueShare(15)
    -- Always settle on the correct total, whatever the animation does
    C_Timer.After(GAIN_TIME + 0.5, function()
        if pot then SetCount(Econ.Balance()) end
    end)
end
Econ.OnEarn = OnEarnSafe
Econ.OnBalanceChanged = function()
    if pot then SetCount(Econ.Balance()) end
end

-- == Leaderboard ==========================================================
-- Balances this client has seen: your own characters (account-wide in
-- PokerLeaderDB), WALLET shares from group members, and table buy-ins and
-- bankroll updates
local function LBData()
    PokerLeaderDB = PokerLeaderDB or {}
    return PokerLeaderDB
end

local function Note(name, chips, mine)
    chips = tonumber(chips)
    if not name or name == "" or not chips then return end
    local d = LBData()
    local e = d[name] or {}
    e.chips, e.t = chips, time()
    if mine then e.mine = true end
    d[name] = e
    if board and board:IsShown() then RefreshBoard() end
end

NoteSelf = function(n)
    local me = N and N.MyName and N.MyName()
    if me then Note(me, n, true) end
end

local function Prune()
    local now, d = time(), LBData()
    for name, e in pairs(d) do
        if type(e) ~= "table" or not e.chips or (not e.mine and now - (e.t or 0) > LB_STALE) then
            d[name] = nil
        end
    end
end

local function Age(e, me, name)
    if name == me then return "|cff33ff33you|r" end
    if e.mine then return "|cff66bbffalt|r" end
    local s = time() - (e.t or 0)
    if s < 60 then return "now" end
    if s < 3600 then return ("%dm ago"):format(math.max(1, math.floor(s / 60))) end
    if s < 86400 then return ("%dh ago"):format(math.floor(s / 3600)) end
    return ("%dd ago"):format(math.floor(s / 86400))
end

local function BuildBoard()
    local ok, b = pcall(CreateFrame, "Frame", "PokerLeaderboardFrame", UIParent, "BackdropTemplate")
    if not ok then b = CreateFrame("Frame", "PokerLeaderboardFrame", UIParent) end
    board = b
    b:Hide()
    b:SetSize(250, 56 + LB_ROWS * 16)
    b:SetFrameStrata("DIALOG")
    b:SetClampedToScreen(true)
    b:EnableMouse(true)
    if b.SetBackdrop then
        b:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        b:SetBackdropColor(0.05, 0.04, 0.02, 0.92)
        b:SetBackdropBorderColor(0.8, 0.65, 0.3)
    end
    tinsert(UISpecialFrames, "PokerLeaderboardFrame") -- Escape closes it

    local title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Chip leaderboard")

    b.rows = {}
    for i = 1, LB_ROWS do
        local y = -30 - (i - 1) * 16
        local r = {}
        r.rank = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.rank:SetPoint("TOPLEFT", 12, y)
        r.rank:SetWidth(20)
        r.rank:SetJustifyH("RIGHT")
        r.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("TOPLEFT", 38, y)
        r.name:SetWidth(100)
        r.name:SetJustifyH("LEFT")
        r.chips = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.chips:SetPoint("TOPLEFT", 136, y)
        r.chips:SetWidth(52)
        r.chips:SetJustifyH("RIGHT")
        r.age = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.age:SetPoint("TOPLEFT", 194, y)
        r.age:SetWidth(48)
        r.age:SetJustifyH("LEFT")
        b.rows[i] = r
    end

    b.empty = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.empty:SetPoint("TOP", 0, -34)
    b.empty:SetText("No balances seen yet")

    local foot = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("BOTTOM", 0, 10)
    foot:SetText("Your characters and players seen in your group")
end

RefreshBoard = function()
    if not board then return end
    local me = N and N.MyName and N.MyName()
    local list = {}
    for name, e in pairs(LBData()) do
        if type(e) == "table" and e.chips then list[#list + 1] = { name = name, e = e } end
    end
    table.sort(list, function(a, b)
        if a.e.chips ~= b.e.chips then return a.e.chips > b.e.chips end
        return a.name < b.name
    end)
    board.empty:SetShown(#list == 0)
    for i, r in ipairs(board.rows) do
        local it = list[i]
        if it then
            local gold = i == 1 and "|cffffd100" or ""
            r.rank:SetText(gold .. i .. ".|r")
            r.name:SetText((it.name == me and "|cff33ff33" or gold) .. it.name .. "|r")
            r.chips:SetText("|cffffff00" .. it.e.chips .. "|r")
            r.age:SetText(Age(it.e, me, it.name))
        end
        r.rank:SetShown(it ~= nil)
        r.name:SetShown(it ~= nil)
        r.chips:SetShown(it ~= nil)
        r.age:SetShown(it ~= nil)
    end
end

function PokerChipPot_ToggleBoard()
    if not board then BuildBoard() end
    if board:IsShown() then board:Hide() return end
    board:ClearAllPoints()
    -- Open on whichever side of the pot has more room
    if pot and (pot:GetCenter() or 0) > UIParent:GetWidth() / 2 then
        board:SetPoint("RIGHT", pot, "LEFT", -8, 0)
    else
        board:SetPoint("LEFT", pot, "RIGHT", 8, 0)
    end
    RefreshBoard()
    board:Show()
end

-- Share our balance with the group when it changes or the group changes
local shareQueued
local function ShareBalance()
    shareQueued = false
    if not IsInGroup or not IsInGroup() then return end
    local me = N.MyName()
    if me then N.Send("WALLET:" .. me .. ":" .. Econ.Balance()) end
end
QueueShare = function(delay)
    if shareQueued then return end
    shareQueued = true
    C_Timer.After(delay, ShareBalance)
end

local function IsBot(name)
    local names = PokerHost and PokerHost.BOT_NAMES
    if not names then return false end
    for _, b in ipairs(names) do if b == name then return true end end
    return false
end

N.AddCommandHandler(function(cmd)
    local n, a = cmd:match("^WALLET:([^:]+):(%d+)$")
    if not n then n, a = cmd:match("^BUYIN:([^:]+):(%d+)$") end
    if n then Note(n, a) return end
    -- Bankroll lines also cover practice bots, which stay off the board
    n, a = cmd:match("^BANKROLL_SET:([^:]+):(%d+)")
    if n then
        if not IsBot(n) then Note(n, a) end
        return
    end
    if cmd:match("^BANKROLL_BULK:") then
        for pair in cmd:sub(15):gmatch("([^;]+)") do
            local pn, pa = pair:match("^([^=]+)=(%d+)$")
            if pn and not IsBot(pn) then Note(pn, pa) end
        end
    end
end)

function PokerChipPot_Toggle()
    if not pot then return end
    if pot:IsShown() then
        pot:Hide()
        PokerChipsDB.potHidden = true
    else
        pot:Show()
        PokerChipsDB.potHidden = false
        SetCount(Econ.Balance())
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event)
    if event == "GROUP_ROSTER_UPDATE" then QueueShare(5) return end
    -- Economy also initialises PokerChipsDB on PLAYER_LOGIN; defer a frame so it goes first
    C_Timer.After(0, function()
        Prune()
        BuildPot()
        QueueShare(5)
    end)
end)
