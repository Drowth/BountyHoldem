-- =========================================================================
-- Bounty Hold'em v1.1.8 by Lee
-- poker.lua: table client (lobby, table, seats, betting, animations)
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end

seatMarkers = seatMarkers or {}
playerSeat = playerSeat or nil -- Seat the local player occupies
playerPortrait = playerPortrait or nil -- Local player's portrait frame
playerNameText = playerNameText or nil
playerBankrolls = playerBankrolls or {}
pendingBankrollSets = pendingBankrollSets or {}
playerBets = playerBets or {}
playerBankrollTexts = playerBankrollTexts or {}
seatTurnTimers = seatTurnTimers or {}      -- [seatNum] = timer frame
seatTurnEndTimes = seatTurnEndTimes or {}  -- [seatNum] = end time
flopCardTextures = flopCardTextures or {}
turnCardTexture = turnCardTexture or nil
riverCardTexture = riverCardTexture or nil
PLAYER_TIMER_DURATION = PLAYER_TIMER_DURATION or 30 -- Decision time in seconds; the host can change it
hasPlayerFolded = hasPlayerFolded or false
playerFlopIndex = playerFlopIndex or 0
sdGateTime = sdGateTime or nil
playedWinSound = playedWinSound or false
lastDealSoundAt = lastDealSoundAt or 0
lastTurnSoundAt = lastTurnSoundAt or 0
preflopRoundActive = preflopRoundActive or false
bbHasActed = bbHasActed or false
bbSeat = bbSeat or nil
lastActionTexts = lastActionTexts or {}
TURN_RING_SCALE = TURN_RING_SCALE or 1.0
scoopInProgress = scoopInProgress or false
seatCardCodes = seatCardCodes or {}    -- [seatNum][cardIndex] = card code, e.g. "4D"
flopCodes = flopCodes or {}            -- Board codes, used for highlighting
turnCode = turnCode or nil
riverCode = riverCode or nil
nameConfig = nameConfig or {
     fontSize = 8,
     color = {r = 1, g = 1, b = 1, a = 1}, -- RGBA white
     
     -- Name offsets from each seat's centre, one row per seat
     positions = {
         -- Left side, seats 1 to 4, all below the seat
         {x = 19, y = 7, align = "CENTER"},
         {x = 19, y = 7, align = "CENTER"},
         {x = 19, y = 7, align = "CENTER"},
         {x = 19, y = 7, align = "CENTER"},
         
         -- Right side, seats 5 to 9, all below the seat
         {x = -19, y = 7, align = "CENTER"},
         {x = -19, y = 7, align = "CENTER"},
         {x = -19, y = 7, align = "CENTER"},
         {x = -19, y = 7, align = "CENTER"},
         {x = -19, y = 7, align = "CENTER"},
     }
}
activePortraitFrames = activePortraitFrames or {}
-- Portrait offsets, one row per seat (1 to 9), each tunable
portraitPositions = portraitPositions or {
     {x = 192, y = 175},
     {x = 327, y = 55},
     {x = 322, y = -90},
     {x = 162, y = -195},
     {x = 42, y = -195},
     {x = -152, y = -195},
     {x = -328, y = -90},
     {x = -328, y = 55},
     {x = -192, y = 175},
}
occupiedSeats = occupiedSeats or {}
seatNameTexts = seatNameTexts or {}
seatBankrollTexts = seatBankrollTexts or {}
seatPortraitFrames = seatPortraitFrames or {}
seatCardTextures = seatCardTextures or {} -- Card textures per [seatNum][cardIndex]
-- seatCardCodes is created further up
dealingOrder = dealingOrder or {}      -- Seat for each deal position: [index] = seatNum
dealingIndex = dealingIndex or 1
myCardIndex = myCardIndex or 0
currentActingSeat = currentActingSeat or nil
bettingOrder = bettingOrder or {}
bettingIndex = bettingIndex or 1
dealingCardCount = dealingCardCount or {}  -- [seatNum] = cards dealt so far
playerSeatNum = playerSeatNum or nil    -- Local player's seat number
lastBet = lastBet or 0
lastRaiseAmount = lastRaiseAmount or 0
seatTurnGlows = seatTurnGlows or {}
activeTurnGlowSeat = activeTurnGlowSeat or nil

local function GateShowdownCall(fn)
    local now = GetTime and GetTime() or 0
    local gate = sdGateTime or 0
    local delay = gate > now and (gate - now) or 0
    if delay > 0 then
        C_Timer.After(delay, fn)
    else
        fn()
    end
end

PlayChipsSound = function()
    PlaySoundFile(POKER_MEDIA .. "chips.MP3", "Master")
end

PlayCheckSound = function()
    -- Two quick knocks, baked into one file so they stay in time
    PlaySoundFile(POKER_MEDIA .. "check.ogg", "Master")
end

-- Card lands: one of five pre-pitched takes, never the same twice running
local DEAL_SOUNDS = 5
local lastDealVariant = 0
PlayDealSound = function()
    local v = math.random(1, DEAL_SOUNDS - 1)
    if v >= lastDealVariant then v = v + 1 end
    lastDealVariant = v
    PlaySoundFile(POKER_MEDIA .. "deal" .. v .. ".ogg", "Master")
end

PlayDealSoundOnce = function()
    local now = GetTime and GetTime() or 0
    if now - (lastDealSoundAt or 0) > 0.12 then
        PlayDealSound()
        lastDealSoundAt = now
    end
end

local _PR_HAND_TRACK = {
    currentShuffleID = nil,
    currentHandID    = nil,
    winnerApplied    = {},   -- Key is handID .. ":" .. playerName
}

Poker_FindSeatByName = function(name)
    if not name then return nil end
    for s = 1, 9 do
        local fs = seatNameTexts[s]
        if fs and fs:GetText() == name then
            return s
        end
    end
    return nil
end

Poker_UpdateSeatBankrollText = function(name, amount)
    local seat = Poker_FindSeatByName(name)
    if seat and seatBankrollTexts[seat] then
        seatBankrollTexts[seat]:SetText(("%d |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t"):format(amount))
    end
    -- Also update the per-player bankroll text, if one exists
    if playerBankrollTexts[name] then
        playerBankrollTexts[name]:SetText(("%d |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t"):format(amount))
    end
end

Poker_ApplyBankrollAuthoritative = function(name, amount)
    amount = tonumber(amount)
    if not name or not amount then return end
    playerBankrolls[name] = amount
    Poker_UpdateSeatBankrollText(name, amount)
end

Poker_RequestSnapshotAfterDelay = function()
    -- Ask for a refresh in case a bulk update was lost to throttling
    if Poker_RequestSnapshotScheduled then return end
    Poker_RequestSnapshotScheduled = true
    C_Timer.After(3, function()
        Poker_SendAddonMessage("PokerTable", "REQUEST_SNAPSHOT", Poker_Channel())
        Poker_RequestSnapshotScheduled = nil
    end)
end

EnsureSeatTurnGlow = function(seatNum)
    if seatTurnGlows[seatNum] then return seatTurnGlows[seatNum] end
    local anchor = seatPortraitFrames[seatNum] or (seatMarkers[seatNum] and seatMarkers[seatNum].button)
    local seatFrame = seatMarkers[seatNum] and seatMarkers[seatNum].button
    if not anchor or not seatFrame then return nil end

    -- Ring lives on the seat frame so the seat border (OVERLAY) draws over it
    local ring = seatFrame:CreateTexture(nil, "ARTWORK", nil, 1) -- ARTWORK sublevel 1, beneath the seat OVERLAY
    ring:SetTexture(POKER_MEDIA .. "turn_ring.tga")
    ring:SetAlpha(0)
    ring:Hide()

    -- Alpha pulse (0% to 100%) via an AnimationGroup
    local ag = ring:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local pulse = ag:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0)
    pulse:SetDuration(0.9)
    pulse:SetOrder(1)
    ring._ag = ag

    seatTurnGlows[seatNum] = ring
    return ring
end

HideAllSeatTurnGlows = function()
    activeTurnGlowSeat = nil
    for _, glow in pairs(seatTurnGlows) do
        if glow._ag then glow._ag:Stop() end
        glow:SetAlpha(0)
        glow:Hide()
    end
end

local function ShowSeatTurnGlow(seatNum)
    if activeTurnGlowSeat and seatTurnGlows[activeTurnGlowSeat] then
        local prev = seatTurnGlows[activeTurnGlowSeat]
        if prev._ag then prev._ag:Stop() end
        prev:SetAlpha(0)
        prev:Hide()
    end
    local anchor = seatPortraitFrames[seatNum] or (seatMarkers[seatNum] and seatMarkers[seatNum].button)
    local ring = EnsureSeatTurnGlow(seatNum)
    if not (ring and anchor) then return end

    -- Match the portrait's position and size, scaled by TURN_RING_SCALE
    local w, h = (anchor.GetSize and anchor:GetSize()) or 42, 42
    local size = math.max(w or 42, h or 42) * TURN_RING_SCALE
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    ring:SetSize(size, size)

    activeTurnGlowSeat = seatNum
    ring:Show()
    ring:SetAlpha(1)
    if ring._ag then ring._ag:Play() end
end

do
    local function PrintPokerWelcome_P()
        local teal = "|cff00cccc"
        print(teal .. "Bounty Hold'em v1.1.8 by Lee loaded. Type /poker to get started!|r")
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, _, addon)
        if addon == POKER_ADDON then
            C_Timer.After(0.5, PrintPokerWelcome_P)
            f:UnregisterEvent("ADDON_LOADED")
        end
    end)
end

local RoleFrame = CreateFrame("Frame", "PokerJoinTableFrame", UIParent, "BasicFrameTemplateWithInset")
RoleFrame:SetFrameStrata("DIALOG")
RoleFrame:SetSize(640, 360)
RoleFrame:SetPoint("CENTER")
RoleFrame:Hide()

-- Clear the template backgrounds so the custom art shows
if RoleFrame.Bg then RoleFrame.Bg:Hide() end
if RoleFrame.Inset and RoleFrame.Inset.Bg then RoleFrame.Inset.Bg:Hide() end

-- Background art inside the inset border
local bgParent = RoleFrame.Inset or RoleFrame
local roleBackground = bgParent:CreateTexture(nil, "ARTWORK")
roleBackground:SetTexture(POKER_MEDIA .. "lobby_bg.tga")
roleBackground:ClearAllPoints()
roleBackground:SetPoint("CENTER", bgParent, "CENTER", -1, -8)
roleBackground:SetSize(710, 666)
roleBackground:SetDrawLayer("ARTWORK", 0)
roleBackground:SetVertexColor(1, 1, 1, 1)

-- Keep the inset above the frame background
if RoleFrame.Inset then
    RoleFrame.Inset:SetFrameLevel(RoleFrame:GetFrameLevel() + 1)
end

RoleFrame.title = RoleFrame:CreateFontString(nil, "OVERLAY")
RoleFrame.title:SetFontObject("GameFontHighlight")
RoleFrame.title:SetPoint("LEFT", RoleFrame.TitleBg, "LEFT", 10, 0)
RoleFrame.title:SetText("Bounty Hold'em v1.1.8 by Lee")

-- Allow dragging the lobby frame
RoleFrame:SetMovable(true)
RoleFrame:EnableMouse(true)
RoleFrame:RegisterForDrag("LeftButton")
RoleFrame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)
RoleFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)

-- Lobby scale setting, same idea as rouletteScale
local pokerScale = 1.0

-- Applies the lobby scale
-- keepPlace keeps the window's centre where it is on screen, otherwise it re-centres
local function ApplyPokerScale(scale, keepPlace)
    pokerScale = scale
    local cx, cy = RoleFrame:GetCenter()
    local old = RoleFrame:GetScale()
    RoleFrame:SetScale(scale)
    RoleFrame:ClearAllPoints()
    if keepPlace and cx then
        RoleFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * old / scale, cy * old / scale)
    else
        RoleFrame:SetPoint("CENTER")
    end
end

ApplyPokerScale(pokerScale)

-- Step 1: SCALE button on the lobby frame
local roleScaleBtn = CreateFrame("Button", nil, RoleFrame, "GameMenuButtonTemplate")
roleScaleBtn:SetSize(80, 28)
roleScaleBtn:SetText("Settings")
roleScaleBtn:SetPoint("TOPRIGHT", RoleFrame, "TOPRIGHT", -12, -32)

-- Step 2: volume popup, hidden until opened
local roleVolumePopup = CreateFrame("Frame", nil, RoleFrame, "BackdropTemplate")
roleVolumePopup:SetSize(220, 68)
roleVolumePopup:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
roleVolumePopup:SetBackdropColor(0, 0, 0, 0.95)
roleVolumePopup:SetPoint("BOTTOMLEFT", RoleFrame, "TOPLEFT", 0, 0) -- Sits just above the frame
roleVolumePopup:SetFrameStrata("FULLSCREEN_DIALOG")
roleVolumePopup:Hide()

-- Step 3: volume slider inside the popup
local roleVolumeSlider = CreateFrame("Slider", "PokerRoleVolumeSlider", roleVolumePopup, "OptionsSliderTemplate")
roleVolumeSlider:SetOrientation("HORIZONTAL")
roleVolumeSlider:SetSize(180, 18)
roleVolumeSlider:SetPoint("CENTER", roleVolumePopup, "CENTER", 0, 3)
roleVolumeSlider:SetMinMaxValues(0, 1)
roleVolumeSlider:SetValueStep(0.01)
roleVolumeSlider:SetObeyStepOnDrag(false)
roleVolumeSlider:SetValue(GetCVar("Sound_MasterVolume") and tonumber(GetCVar("Sound_MasterVolume")) or 1)

local roleVolumeTitle = roleVolumePopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
roleVolumeTitle:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
roleVolumeTitle:SetTextColor(1, 1, 1, 1)
roleVolumeTitle:SetText("VOLUME")
roleVolumeTitle:SetPoint("BOTTOM", roleVolumePopup, "BOTTOM", 0, 12)
roleVolumeTitle:SetJustifyH("CENTER")

_G[roleVolumeSlider:GetName() .. 'Low']:SetText("0%")
_G[roleVolumeSlider:GetName() .. 'High']:SetText("100%")
_G[roleVolumeSlider:GetName() .. 'Low']:ClearAllPoints()
_G[roleVolumeSlider:GetName() .. 'Low']:SetPoint("TOPLEFT", roleVolumeSlider, "BOTTOMLEFT", -4, 0)
_G[roleVolumeSlider:GetName() .. 'High']:ClearAllPoints()
_G[roleVolumeSlider:GetName() .. 'High']:SetPoint("TOPRIGHT", roleVolumeSlider, "BOTTOMRIGHT", 4, 0)
_G[roleVolumeSlider:GetName() .. 'Text']:SetText("")

-- Live value readout above the slider
local roleVolumeValueLabel = roleVolumePopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
roleVolumeValueLabel:SetPoint("BOTTOM", roleVolumeSlider, "TOP", 0, 2)
roleVolumeValueLabel:SetTextColor(1, 1, 1, 1)
roleVolumeValueLabel:SetText(string.format("%d%%", (roleVolumeSlider:GetValue() * 100)))

local initialVolume = tonumber(GetCVar("Sound_MasterVolume")) or 1
roleVolumeSlider:SetValue(initialVolume)

roleVolumeSlider:SetScript("OnValueChanged", function(self, value)
    SetCVar("Sound_MasterVolume", value)
    SetCVar("Sound_SFXVolume", value)
    roleVolumeValueLabel:SetText(string.format("%d%%", value * 100))
end)

-- SCALE button click
roleScaleBtn:SetScript("OnClick", function()
    -- Size now lives on the drag bar at the window's edge (PokerSizeBar.lua)
    roleVolumePopup:SetShown(not roleVolumePopup:IsShown())
end)

-- Close the popups when the lobby hides
RoleFrame:HookScript("OnHide", function()
    roleVolumePopup:Hide()
end)

-- Join Table button, centred on the frame
local joinTableBtn = CreateFrame("Button", nil, RoleFrame, "GameMenuButtonTemplate")
joinTableBtn:SetSize(120, 28)
joinTableBtn:SetText("Join Table")
joinTableBtn:SetPoint("CENTER", RoleFrame, "CENTER", 0, -115) -- 20px below centre
joinTableBtn:Disable() -- Starts disabled

-- Table frame, hidden until joined
local TableFrame = CreateFrame("Frame", "PokerTableFrame", UIParent, "BasicFrameTemplateWithInset")
TableFrame:SetSize(960, 540) -- 1920 x 1080 art at half scale
-- Draw over unit frames and action bars from other UI addons
TableFrame:SetFrameStrata("DIALOG")
TableFrame:SetPoint("CENTER")
TableFrame:Hide()

-- Table background, added once the frame is fully built
local tableBackground = TableFrame:CreateTexture(nil, "ARTWORK")
tableBackground:SetTexture(POKER_MEDIA .. "pokertablegraphic_player.tga")
tableBackground:SetSize(935, 935)
tableBackground:SetPoint("CENTER", TableFrame, "CENTER", 0, -12)

-- Allow dragging the table frame
TableFrame:SetMovable(true)
TableFrame:EnableMouse(true)
TableFrame:RegisterForDrag("LeftButton")
TableFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
TableFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

TableFrame.title = TableFrame:CreateFontString(nil, "OVERLAY")
TableFrame.title:SetFontObject("GameFontHighlight")
TableFrame.title:SetPoint("LEFT", TableFrame.TitleBg, "LEFT", 10, 0)
TableFrame.title:SetText("Bounty Hold'em v1.1.8 by Lee")

-- Vertical button stack, top left (110 x 28)
local function CreateTopLeftBtn(label, anchorFrame)
    local btn = CreateFrame("Button", nil, TableFrame, "GameMenuButtonTemplate")
    btn:SetSize(90, 28)
    if anchorFrame then
        btn:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, 1)
    else
        btn:SetPoint("TOPLEFT", TableFrame, "TOPLEFT", 12, -30) -- Below the frame title
    end
    btn:SetText(label)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(label, 1, 1, 1)
        if label == "Guide" then
            GameTooltip:AddLine("View poker hand rankings", 0.7, 0.7, 0.7)
        elseif label == "History" then
            GameTooltip:AddLine("View previous hands and chat messages", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function()
        print("|cff00cccc[Poker]|r " .. label .. " clicked.")
        -- Placeholder: not yet linked to a panel
    end)
    return btn
end

local guideBtn = CreateTopLeftBtn("Guide", nil)
local historyBtn= CreateTopLeftBtn("History", guideBtn)

pokerPrintBuffer = pokerPrintBuffer or {}

-- == History panel (right side) ===========================================
local historyPanel

-- Shared two-part title, styled like the Guide panel
local function CreateCombinedTitle(panel, leftWord, rightWords)
    local titleBox = CreateFrame("Frame", nil, panel)
    titleBox:SetSize(272, 20)
    titleBox:SetPoint("TOP", panel, "TOP", 0, -10)

    local leftFS = titleBox:CreateFontString(nil, "OVERLAY")
    leftFS:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    leftFS:SetTextColor(1,1,1,1)
    leftFS:SetText(leftWord)

    local rightFS = titleBox:CreateFontString(nil, "OVERLAY")
    rightFS:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    rightFS:SetTextColor(1,1,1,1)
    rightFS:SetText(rightWords)

    local lw = leftFS:GetStringWidth()
    local rw = rightFS:GetStringWidth()
    local total = lw + rw
    leftFS:ClearAllPoints()
    leftFS:SetPoint("LEFT", titleBox, "CENTER", -total/2, 0)
    rightFS:ClearAllPoints()
    rightFS:SetPoint("LEFT", leftFS, "RIGHT", 0, 0)
end



local function CreateHistoryPanel()
    if historyPanel then return historyPanel end

    historyPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    historyPanel:SetWidth(292)
    historyPanel:SetPoint("TOPLEFT", TableFrame, "TOPRIGHT", -3, 0)
    historyPanel:SetPoint("BOTTOMLEFT", TableFrame, "BOTTOMRIGHT", 0, 0)
    historyPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    historyPanel:SetBackdropColor(0,0,0,0.85)
    historyPanel:SetBackdropBorderColor(1,1,1,0.4)
    historyPanel:SetFrameStrata("DIALOG")
    historyPanel:Hide()
    historyPanel:HookScript("OnShow", function(self)
        self:SetScale(TableFrame:GetScale())
    end)

    -- Title via the shared helper
    CreateCombinedTitle(historyPanel, "POKER", "HAND HISTORY")
    local TITLE_BLOCK_HEIGHT = 34
    local HAND_HEADER_HEIGHT = 16

    -- Teal rule under the title
    local titleDivider = historyPanel:CreateTexture(nil, "OVERLAY")
    titleDivider:SetColorTexture(0, 0.8, 0.8, 1)
    titleDivider:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 8, -TITLE_BLOCK_HEIGHT)
    titleDivider:SetPoint("TOPRIGHT", historyPanel, "TOPRIGHT", -8, -TITLE_BLOCK_HEIGHT)
    titleDivider:SetHeight(2)

    -- Half for hands, half for chat
    local totalH = TableFrame:GetHeight()
    local topH   = math.floor(totalH * 0.45)
    local bottomH= totalH - topH

    -- == Top half: hand history (hole and board cards per row) ============
    local handsContainer = CreateFrame("Frame", nil, historyPanel)
    handsContainer:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 4, -(4 + TITLE_BLOCK_HEIGHT + HAND_HEADER_HEIGHT))
    handsContainer:SetPoint("TOPRIGHT", historyPanel, "TOPRIGHT", -4, -(4 + TITLE_BLOCK_HEIGHT + HAND_HEADER_HEIGHT))

    local handsHeader = CreateFrame("Frame", nil, historyPanel)
    handsHeader:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 4, -(4 + TITLE_BLOCK_HEIGHT))
    handsHeader:SetPoint("TOPRIGHT", historyPanel, "TOPRIGHT", -4, -(4 + TITLE_BLOCK_HEIGHT))
    handsHeader:SetHeight(HAND_HEADER_HEIGHT)

    -- Column widths and offsets; inner width is panel width minus padding and scrollbar
    local INTERNAL_W = 292 - 8 - 26  -- Panel width less horizontal padding and scrollbar space
    local HAND_COL_W   = 20
    local CARDS_COL_W  = 22*2 + 2      -- Two hole cards plus a 2px gap
    local BOARD_COL_W  = 22*5 + 2*4    -- Five board cards plus four gaps
    local POT_COL_W    = math.max(40, INTERNAL_W - (HAND_COL_W + CARDS_COL_W + BOARD_COL_W + 16)) -- Whatever width is left
    local X_HAND  = 0
    local X_CARDS = X_HAND  + HAND_COL_W + 4
    local X_BOARD = X_CARDS + CARDS_COL_W + 8
    local X_POT   = X_BOARD + BOARD_COL_W + 8

    local function MakeHeaderLabel(text, x, width, justify)
        local fs = handsHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        fs:SetTextColor(0, 0.82, 0.82, 1)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetPoint("LEFT", handsHeader, "LEFT", x, 0)
        fs:SetWidth(width)
        fs:SetText(text)
        return fs
    end
    MakeHeaderLabel("#",  X_HAND,  HAND_COL_W,  "CENTER")
    MakeHeaderLabel("Cards", X_CARDS, CARDS_COL_W, "LEFT")
    MakeHeaderLabel("Board", X_BOARD, BOARD_COL_W, "LEFT")
    MakeHeaderLabel("Pot",   X_POT,   POT_COL_W,   "LEFT")

    local headerUnderline = historyPanel:CreateTexture(nil, "OVERLAY")
    headerUnderline:SetColorTexture(0,0.8,0.8,0.35)
    headerUnderline:SetPoint("TOPLEFT", handsHeader, "BOTTOMLEFT", 0, -1)
    headerUnderline:SetPoint("TOPRIGHT", handsHeader, "BOTTOMRIGHT", 0, -1)
    headerUnderline:SetHeight(1)

    local handsScroll = CreateFrame("ScrollFrame", "PokerHistoryHandsScroll", handsContainer, "UIPanelScrollFrameTemplate")
    handsScroll:SetPoint("TOPLEFT", handsContainer, "TOPLEFT", 0, 0)
    handsScroll:SetPoint("BOTTOMRIGHT", handsContainer, "BOTTOMRIGHT", -26, 0)

    local handsContent = CreateFrame("Frame", nil, handsScroll)
    handsContent:SetSize(1,1)
    handsScroll:SetScrollChild(handsContent)

    -- Auto-scroll helpers for the hands list, as in the chat panel
    local function Hands_IsAtBottom()
        local maxOff = math.max(0, (handsContent:GetHeight() or 0) - (handsScroll:GetHeight() or 0))
        return handsScroll:GetVerticalScroll() >= (maxOff - 2)
    end

    local function Hands_ScrollToBottom()
        local maxOff = math.max(0, (handsContent:GetHeight() or 0) - (handsScroll:GetHeight() or 0))
        handsScroll:SetVerticalScroll(maxOff)
        local sb = handsScroll.ScrollBar or _G["PokerHistoryHandsScrollScrollBar"]
        if sb then
            sb:SetMinMaxValues(0, maxOff)
            sb:SetValue(maxOff)
        end
    end

    -- Exposed for other code
    historyPanel.ScrollHandsToBottom = Hands_ScrollToBottom
    historyPanel.IsHandsAtBottom     = Hands_IsAtBottom

    -- Stay pinned to the bottom on resize, but only if already there
    handsScroll:HookScript("OnSizeChanged", function()
        if Hands_IsAtBottom() then
            Hands_ScrollToBottom()
        end
    end)

    local handsSlider = handsScroll.ScrollBar or _G["PokerHistoryHandsScrollScrollBar"]
    if handsSlider then
        handsSlider:ClearAllPoints()
        handsSlider:SetPoint("TOPRIGHT", handsContainer, "TOPRIGHT", 0, -19)
        handsSlider:SetPoint("BOTTOMRIGHT", handsContainer, "BOTTOMRIGHT", 0, 15)
    end

    -- Grey rule between the hands and chat halves
    if historyPanel.sectionDivider then
        historyPanel.sectionDivider:Hide()
    end
    local sectionDivider = historyPanel:CreateTexture("PokerHistoryTopBottomDivider", "OVERLAY")
    sectionDivider:SetColorTexture(0.7, 0.7, 0.7, 0.35) -- Faint grey
    sectionDivider:SetHeight(1)
    -- Placed just above the chat container, which starts at -(topH + TITLE_BLOCK_HEIGHT + 4)
    sectionDivider:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 6, -(topH + TITLE_BLOCK_HEIGHT + 2))
    sectionDivider:SetPoint("TOPRIGHT", historyPanel, "TOPRIGHT", -6, -(topH + TITLE_BLOCK_HEIGHT + 2))
    historyPanel.sectionDivider = sectionDivider

    local handRows = {}
    local currentHandRow
    local HAND_ROW_H = 60

    local function CreateHandRow()
        local row = CreateFrame("Frame", nil, handsContent)
        row:SetSize(INTERNAL_W, HAND_ROW_H)
        row:SetPoint("TOPLEFT", handsContent, "TOPLEFT", 0, -(#handRows * HAND_ROW_H))

        -- Hand number, set when a hand starts
        row.handNumFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.handNumFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        row.handNumFS:SetTextColor(1, 1, 1)
        row.handNumFS:SetPoint("LEFT", row, "LEFT", X_HAND + 2, 5)
        row.handNumFS:SetWidth(HAND_COL_W - 4)
        row.handNumFS:SetJustifyH("CENTER")
        row.handNumFS:SetText("")

        -- Hole card column
        row.hole = {}
        local holeX = X_CARDS
        for i=1,2 do
            local tex = row:CreateTexture(nil, "ARTWORK")
            tex:SetTexture(POKER_MEDIA .. "card_back.tga")
            tex:SetSize(22,44)
            tex:SetPoint("TOPLEFT", row, "TOPLEFT", holeX, -2)
            holeX = holeX + 22 + 2
            row.hole[i] = tex
        end

        -- Board card column
        row.board = {}
        local boardX = X_BOARD
        for i=1,5 do
            local tex = row:CreateTexture(nil, "ARTWORK")
            tex:SetTexture(POKER_MEDIA .. "card_back.tga")
            tex:SetSize(22,44)
            tex:SetPoint("TOPLEFT", row, "TOPLEFT", boardX, -2)
            boardX = boardX + 22 + 2
            row.board[i] = tex
        end

        -- Pot, right-aligned
        row.potFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.potFS:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
        row.potFS:SetPoint("RIGHT", row, "LEFT", X_POT + POT_COL_W, 5)
        row.potFS:SetWidth(POT_COL_W - 2)
        row.potFS:SetJustifyH("LEFT")
        row.potFS:SetText("")

        -- Shuffle ID and Hand ID line
        row.idsFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.idsFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
        row.idsFS:SetJustifyH("LEFT")
        row.idsFS:SetTextColor(1,1,1,1)
        -- Placed below the cards and pot line: cards are 44px tall from y = -2, so
        -- about y = -48
        row.idsFS:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -48)
        row.idsFS:SetWidth(INTERNAL_W - 4)
        row.idsFS:SetText("")  -- Set later by setIDs()

        -- Row separator
        local line = row:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(0,0.8,0.8,0.25)
        line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        line:SetHeight(1)
        
        table.insert(handRows, row)
        handsContent:SetHeight(#handRows * HAND_ROW_H)
        Hands_ScrollToBottom()
        return row
    end

    historyPanel._hands = {
        CreateHandRow = CreateHandRow,
        getCurrent = function() return currentHandRow end,
        setCurrent = function(r) currentHandRow = r end,
        rows = handRows
    }

    historyPanel._hands.setPot = function(amount)
        local r = historyPanel._hands.getCurrent and historyPanel._hands.getCurrent()
        if not r or not r.potFS then return end
        if amount and tonumber(amount) then
            r.potFS:SetFormattedText("%d|T" .. POKER_MEDIA .. "1chip:10:10:0:0|t", amount)
        else
            r.potFS:SetText("")
        end
    end

    historyPanel._hands.setHandNumber = function(num)
        local r = historyPanel._hands.getCurrent and historyPanel._hands.getCurrent()
        if r and r.handNumFS then
            r.handNumFS:SetText(num or "")
        end
    end

    historyPanel._hands.setIDs = function(shuffleID, handID)
        local r = historyPanel._hands.getCurrent and historyPanel._hands.getCurrent()
        if not r or not r.idsFS then return end
        r.shuffleID = shuffleID
        r.handID = handID
        local white  = "|cffffffff"
        local orange = "|cffffe6b3"
        local spaces = "     "  -- Five-space gap between the two fields
        r.idsFS:SetText(
            white .. "Shuffle ID:|r " .. orange .. (shuffleID or "?") .. "|r" ..
            spaces ..
            white .. "Hand ID:|r " .. orange .. (handID or "?") .. "|r"
        )
    end

    -- == Divider between the halves =======================================
    local midDivider = historyPanel:CreateTexture(nil, "OVERLAY")
    midDivider:SetColorTexture(0.8,0.8,0.8,0.20)
    midDivider:SetHeight(1)
    midDivider:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 6, -(topH + TITLE_BLOCK_HEIGHT))
    midDivider:SetPoint("TOPRIGHT", historyPanel, "TOPRIGHT", -6, -(topH + TITLE_BLOCK_HEIGHT))

    -- Re-anchor the hands list 2px above the divider to stop early clipping
    handsContainer:ClearAllPoints()
    handsContainer:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 4, -(4 + TITLE_BLOCK_HEIGHT + HAND_HEADER_HEIGHT))
    handsContainer:SetPoint("TOPRIGHT", historyPanel, "TOPRIGHT", -4, -(4 + TITLE_BLOCK_HEIGHT + HAND_HEADER_HEIGHT))
    handsContainer:SetPoint("BOTTOMLEFT", midDivider, "TOPLEFT", 0, 2)
    handsContainer:SetPoint("BOTTOMRIGHT", midDivider, "TOPRIGHT", 0, 2)

    -- == Bottom half: chat log (bottom-anchored font strings) =============
    local chatContainer = CreateFrame("Frame", nil, historyPanel)
    chatContainer:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 4, -(topH + TITLE_BLOCK_HEIGHT + 4))
    chatContainer:SetPoint("BOTTOMRIGHT", historyPanel, "BOTTOMRIGHT", -4, 4)

    -- Scroll frame and scrollbar, same template as the hands list
    local chatScroll = CreateFrame("ScrollFrame", "PokerHistoryChatScroll", chatContainer, "UIPanelScrollFrameTemplate")
    chatScroll:SetPoint("TOPLEFT", chatContainer, "TOPLEFT", 0, 0)
    chatScroll:SetPoint("BOTTOMRIGHT", chatContainer, "BOTTOMRIGHT", -26, 0)

    local chatContent = CreateFrame("Frame", nil, chatScroll)
    chatContent:SetSize(1,1)
    chatScroll:SetScrollChild(chatContent)

    local chatSlider = chatScroll.ScrollBar or _G["PokerHistoryChatScrollScrollBar"]
    if chatSlider then
        chatSlider:ClearAllPoints()
        -- 10px shorter overall (5px inset top and bottom)
        chatSlider:SetPoint("TOPRIGHT", chatContainer, "TOPRIGHT", 0, -17)
        chatSlider:SetPoint("BOTTOMRIGHT", chatContainer, "BOTTOMRIGHT", 0, 16)
    end

    -- Layout values
    local CHAT_LEFT_PAD   = 4
    local CHAT_RIGHT_PAD  = 4
    local CHAT_TOP_MARGIN = 2
    local CHAT_BOTTOM_MARGIN = 6
    local CHAT_LINE_GAP   = 2
    local CHAT_MAX_LINES  = 4000

    local chatLines = {}

    -- Width allows for the scrollbar plus an extra 20px
    local function UpdateChatContentWidth()
        local full = chatScroll:GetWidth()
        if full <= 0 then return end
        local avail = full - 26 + 20
        local maxAllowed = full - 4
        if avail > maxAllowed then avail = maxAllowed end
        if avail < 60 then avail = 60 end
        chatContent:SetWidth(avail)
        -- Apply the width to existing lines so they wrap correctly
        for _, fs in ipairs(chatLines) do
            fs:SetWidth(avail - CHAT_LEFT_PAD - CHAT_RIGHT_PAD)
        end
    end

    -- Bottom-anchored layout: newest line at the bottom, older lines pushed up
    local function ReflowChat()
        local viewH = chatScroll:GetHeight()
        if viewH <= 0 then
            -- Wait until visible
            chatScroll._pendingReflow = true
            return
        end

        -- Measure line heights once the width is set
        local totalTextH = 0
        local heights = {}
        for i, fs in ipairs(chatLines) do
            local h = fs:GetStringHeight()
            if h <= 0 then h = 10 end
            heights[i] = h
            totalTextH = totalTextH + h + (i == #chatLines and 0 or CHAT_LINE_GAP)
        end

        local needed = totalTextH + CHAT_TOP_MARGIN + CHAT_BOTTOM_MARGIN
        local contentH = math.max(needed, viewH) -- At least the view height, so bottom anchoring works
        chatContent:SetHeight(contentH)

        -- Bottom spacing: if content overflows the view, only the bottom margin
        -- applies and scrolling handles the rest; if it fits, shift the block down
        -- so the newest line sits on the bottom margin
        local bottomAnchorOffset = CHAT_BOTTOM_MARGIN
        local y = bottomAnchorOffset

        -- Lay out oldest first, offsetting each line from the bottom by the total
        -- height of the newer lines
        local offsetsFromBottom = {}
        local running = 0
        for i = #chatLines, 1, -1 do
            offsetsFromBottom[i] = running
            running = running + heights[i] + CHAT_LINE_GAP
        end
        -- Newest line has offset 0
        for i, fs in ipairs(chatLines) do
            local bottomOffset = bottomAnchorOffset + offsetsFromBottom[i]
            fs:ClearAllPoints()
            fs:SetPoint("BOTTOMLEFT", chatContent, "BOTTOMLEFT", CHAT_LEFT_PAD, bottomOffset)
            fs:SetPoint("RIGHT", chatContent, "RIGHT", -CHAT_RIGHT_PAD, 0)
        end

        chatScroll:UpdateScrollChildRect()
    end

    -- True when scrolled to the bottom
    local function IsAtBottom()
        local maxOff = math.max(0, chatContent:GetHeight() - chatScroll:GetHeight())
        return chatScroll:GetVerticalScroll() >= (maxOff - 2)
    end

    local function ScrollChatToBottom()
        local maxOff = math.max(0, chatContent:GetHeight() - chatScroll:GetHeight())
        chatScroll:SetVerticalScroll(maxOff)
        if chatSlider then
            chatSlider:SetMinMaxValues(0, maxOff)
            chatSlider:SetValue(maxOff)
        end
    end

    -- Mouse wheel scrolling
    chatScroll:EnableMouseWheel(true)
    chatScroll:SetScript("OnMouseWheel", function(self, delta)
        ScrollFrameTemplate_OnMouseWheel(self, delta)
        if chatSlider then
            local maxOff = math.max(0, chatContent:GetHeight() - self:GetHeight())
            chatSlider:SetMinMaxValues(0, maxOff)
            chatSlider:SetValue(self:GetVerticalScroll())
        end
    end)

    -- Force the slider in sync; the template only sets a basic script
    if chatSlider and not chatSlider._hooked then
        chatSlider:HookScript("OnValueChanged", function(self, val)
            chatScroll:SetVerticalScroll(val)
        end)
        chatSlider._hooked = true
    end

    -- Public entry point for adding a line
    historyPanel._log = {
        push = function(msg)
            if not msg or msg == "" or msg == ".." then return end
            local stayBottom = IsAtBottom()

            -- Drop the oldest lines
            if #chatLines >= CHAT_MAX_LINES then
                local oldest = table.remove(chatLines, 1)
                if oldest then
                    oldest:Hide()
                    oldest:SetParent(nil)
                end
            end

            local fs = chatContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(true)
            fs:SetNonSpaceWrap(true)
            fs:SetTextColor(1, 1, 1, 1)
            fs:SetText(msg)
            fs:SetWidth((chatContent:GetWidth() > 0 and (chatContent:GetWidth() - CHAT_LEFT_PAD - CHAT_RIGHT_PAD)) or 240)
            table.insert(chatLines, fs)

            UpdateChatContentWidth()
            ReflowChat()

            -- Refresh the slider range
            local maxOff = math.max(0, chatContent:GetHeight() - chatScroll:GetHeight())
            if chatSlider then
                chatSlider:SetMinMaxValues(0, maxOff)
            end
            if stayBottom then
                ScrollChatToBottom()
            end
        end
    }

    -- Respond to width and size changes
    chatScroll:HookScript("OnSizeChanged", function()
        UpdateChatContentWidth()
        ReflowChat()
        if IsAtBottom() then ScrollChatToBottom() end
    end)

    -- Write out queued messages
    if pokerPrintBuffer and #pokerPrintBuffer > 0 then
        for i, line in ipairs(pokerPrintBuffer) do
            -- Lines that already carry the green NEW ROUND header pass through as is
            if line:find("======== NEW ROUND ========") then
                historyPanel._log.push(line)
            else
                -- Clean raw [Poker] lines; leave cleaned ones alone
                if line:find("%[Poker%]") or (not line:find("^|cff00cccc> ")) then
                    local cleaned = PokerHistoryPrepareLine(line)
                    pokerPrintBuffer[i] = cleaned
                    historyPanel._log.push(cleaned)
                else
                    historyPanel._log.push(line)
                end
            end
        end
        ReflowChat()
        ScrollChatToBottom()
    else
        -- Set up the base layout
        UpdateChatContentWidth()
        ReflowChat()
        ScrollChatToBottom()
    end

    historyPanel:HookScript("OnShow", function()
        C_Timer.After(0.05, function()
            UpdateChatContentWidth()
            ReflowChat()
            ScrollChatToBottom()
        end)
    end)

    historyPanel._updateChatWidth = UpdateChatContentWidth
    historyPanel._reflowChat     = ReflowChat

    return historyPanel
end

local function ToggleHistoryPanel()
    local panel = historyPanel or CreateHistoryPanel()
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

-- Hook up the History button
historyBtn:SetScript("OnClick", function() ToggleHistoryPanel() end)

-- == Print hook (copies poker prints to the history panel) ================
local _origPrint = _origPrint or print

-- Builds the cleaned history line; the WoW chat frame output is untouched
local function PokerHistoryPrepareLine(line)
    if not line then return "" end

    -- Step 1: drop the [Poker] tag, coloured or plain
    line = line:gsub("|cff%x%x%x%x%x%x%[Poker%]|r", "")
    line = line:gsub("%[Poker%]", "")

    -- Step 2: drop leading empty colour pairs (|cXXXXXXXX|r) left by bullet removal
    line = line:gsub("^(|c%x%x%x%x%x%x%x%x|r)+", "")

    -- Step 3: drop leading colour resets, then spaces
    line = line:gsub("^(|r)+", "")
    line = line:gsub("^%s+", "")

    -- Step 4: drop bullet tokens anywhere, coloured or plain, with nearby spaces;
    -- runs twice to catch nested spacing
    for _ = 1, 2 do
        line = line:gsub("%s*|c%x%x%x%x%x%x%x%x%[%s*•%s*%]|r%s*", " ")
        line = line:gsub("%s*%[%s*•%s*%]%s*", " ")
    end

    -- Step 5: squash repeated spaces
    line = line:gsub("%s%s+", " ")

    -- Step 6: trim both ends
    line = line:gsub("^%s+", ""):gsub("%s+$", "")

    -- Step 7: drop leading empty colour codes once more after squashing
    line = line:gsub("^(|c%x%x%x%x%x%x%x%x|r)+", "")
    line = line:gsub("^%s+", "")

    if line == "" then return "" end

    -- Step 8: leave NEW ROUND headers without the teal prefix
    if line:find("NEW ROUND") and line:find("========") then
        return "|cff00ff00" .. line .. "|r"
    end

    -- Step 9: strip any leading spaces still left, including before a colour code
    line = line:gsub("^%s+", "")

    -- Step 10: add the teal prompt with a single space after it
    local out = "|cff00cccc> |r" .. line
    -- Collapse extra spaces straight after the prefix
    out = out:gsub("(|cff00cccc> |r)%s+", "%1")

    return out
end

print = function(...)
    _origPrint(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    local full = table.concat(parts, " ")
    if not full:find("%[Poker%]") then return end

    pokerPrintBuffer = pokerPrintBuffer or {}

    -- A Shuffle ID line gets a green NEW ROUND header inserted above it
    if full:find("Shuffle ID:") then
        local header = "|cff00ff00======== NEW ROUND ========" -- No teal > prefix here
        table.insert(pokerPrintBuffer, header)
        if historyPanel and historyPanel._log then
            historyPanel._log.push(header)
        end
    end

    local cleaned = PokerHistoryPrepareLine(full)
    table.insert(pokerPrintBuffer, cleaned)
    if historyPanel and historyPanel._log then
        historyPanel._log.push(cleaned)
    end
end

-- == Hand history helpers =================================================
local historyHandCounter = historyHandCounter or 0
local function History_StartNewHand()
    local panel = historyPanel or CreateHistoryPanel()
    local hands = panel._hands
    local row = hands.CreateHandRow()
    hands.setCurrent(row)
    historyHandCounter = historyHandCounter + 1
    hands.setHandNumber(historyHandCounter)
    -- Start with an empty pot display
    panel._hands.setPot(nil)
end

local function History_SetIDs(shuffleID, handID)
    local panel = historyPanel or CreateHistoryPanel()
    if panel and panel._hands and panel._hands.setIDs then
        panel._hands.setIDs(shuffleID, handID)
    end
end

local function History_SetHole(cardCode)
    local panel = historyPanel
    if not panel or not panel._hands then return end
    local row = panel._hands.getCurrent()
    if not row then return end
    -- First free hole card slot
    for i=1,2 do
        if not row._holeCodes then row._holeCodes = {} end
        if not row._holeCodes[i] then
            row._holeCodes[i] = cardCode
            row.hole[i]:SetTexture(POKER_MEDIA .. cardCode .. ".tga")
            break
        end
    end
end

local function History_SetBoardCards(list) -- Card codes in order
    local panel = historyPanel
    if not panel or not panel._hands then return end
    local row = panel._hands.getCurrent()
    if not row then return end
    for i, code in ipairs(list) do
        if i <= 5 and code and code ~= "" then
            row.board[i]:SetTexture(POKER_MEDIA .. code .. ".tga")
        end
    end
end

-- Local player's seat number, or nil
GetMySeat = function()
    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    for s = 1, 9 do
        if seatMarkers[s] and seatMarkers[s].occupied then
            local fs = seatNameTexts[s]
            if fs and fs:GetText() == myName then
                return s
            end
        end
    end
    return nil
end

-- == Guide panel (left side) ==============================================
guidePanel = guidePanel or nil

local function CreateGuideTitle(panel)
    -- Container that centres the two-part title ("POKER" bold, " HAND RANKINGS")
    local titleBox = CreateFrame("Frame", nil, panel)
    titleBox:SetSize(272, 20)
    titleBox:SetPoint("TOP", panel, "TOP", 0, -10)

    local pokerFS = titleBox:CreateFontString(nil, "OVERLAY")
    pokerFS:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE") -- Heavier weight
    pokerFS:SetTextColor(1, 1, 1, 1)
    pokerFS:SetText("POKER")

    local restFS = titleBox:CreateFontString(nil, "OVERLAY")
    restFS:SetFont("Fonts\\FRIZQT__.TTF", 13, "") -- Regular weight
    restFS:SetTextColor(1, 1, 1, 1)
    restFS:SetText("HAND RANKINGS")

    -- Centre on the combined width
    local pokerW = pokerFS:GetStringWidth()
    local restW  = restFS:GetStringWidth()
    local totalW = pokerW + restW
    pokerFS:ClearAllPoints()
    pokerFS:SetPoint("LEFT", titleBox, "CENTER", -totalW/2, 0)
    restFS:ClearAllPoints()
    restFS:SetPoint("LEFT", pokerFS, "RIGHT", 0, 0)
end

local function AddDivider(panel, yOffset)
    local line = panel:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(0, 0.8, 0.8, 1) -- Teal, #00cccc
    line:SetSize(292 - 16, 2)
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -yOffset)
    return yOffset + 12
end

-- Rank row builder with optional dimmed cards (dimCodes)
local function AddRankRow(panel, yOffset, codes, title, subtitle, dimCodes)
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(292 - 16, 56) -- Tall enough for a card
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -yOffset)

    -- Uppercase lookup of cards to dim
    local dimSet = {}
    if dimCodes then
        for _, c in ipairs(dimCodes) do
            dimSet[c:upper()] = true
        end
    end

    -- Cards on the left
    local cardW, cardH, gap = 24, 48, 2
    local totalCardsW = (#codes * cardW) + ((#codes - 1) * gap)
    for i, code in ipairs(codes) do
        local codeU = code:upper()
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetSize(cardW, cardH)
        t:SetTexture(POKER_MEDIA .. codeU .. ".tga")
        t:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (cardW + gap), 0)
        if dimSet[codeU] then
            t:SetAlpha(0.5)
        end
    end

    -- Text to the right of the cards
    local textAreaX = totalCardsW + 8
    local titleFS = row:CreateFontString(nil, "OVERLAY")
    titleFS:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    titleFS:SetTextColor(0, 0.8, 0.8, 1) -- Teal
    titleFS:SetJustifyH("LEFT")
    titleFS:SetPoint("TOPLEFT", row, "TOPLEFT", textAreaX, -6)
    titleFS:SetText(title)

    local subFS = row:CreateFontString(nil, "OVERLAY")
    subFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    subFS:SetTextColor(1, 1, 1, 1)
    subFS:SetJustifyH("LEFT")
    subFS:SetWidth((292 - 16) - textAreaX) -- Wrap when needed
    subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -3)
    subFS:SetText(subtitle)

    -- Advance y by the taller of card height and title plus subtitle, plus spacing
    local rowHeight = math.max(cardH, titleFS:GetStringHeight() + subFS:GetStringHeight() + 4)
    return yOffset + rowHeight - 4
end

local function CreateGuidePanel()
    if guidePanel then return guidePanel end
    -- Sibling of TableFrame, docked to its left edge
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetWidth(292)
    panel:SetPoint("TOPRIGHT", TableFrame, "TOPLEFT", 0, 0)      -- Flush with the edge
    panel:SetPoint("BOTTOMRIGHT", TableFrame, "BOTTOMLEFT", 0, 0) -- Matches TableFrame height
    -- Fall back to 0.85 scale until tablePokerScale is set
    panel:SetScale((TableFrame and TableFrame.GetScale and TableFrame:GetScale()) or (tablePokerScale or 1.0))
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(1, 1, 1, 0.4)
    panel:SetFrameStrata("DIALOG")
    panel:Hide()

    -- Re-sync scale on show in case it changed while hidden
    panel:HookScript("OnShow", function(self)
        self:SetScale((TableFrame and TableFrame:GetScale()) or (tablePokerScale or 1.0))
    end)

    -- Heading
    CreateGuideTitle(panel)
    local y = 34 -- Room for the heading
    y = AddDivider(panel, y)

    -- Rank 1: Royal Flush
    y = AddRankRow(
        panel, y,
        {"10H","JH","QH","KH","AH"},
        "ROYAL FLUSH",
        "10-J-Q-K-A, all in the same suit."
    )

    -- Rank 2: Straight Flush
    y = AddRankRow(
        panel, y,
        {"6S","7S","8S","9S","10S"},
        "STRAIGHT FLUSH",
        "Five consecutive cards in the same suit."
    )

    -- Rank 3: Four of a Kind
    y = AddRankRow(
        panel, y,
        {"10H","10S","10D","10C","AD"},
        "FOUR OF A KIND",
        "Four cards of the same rank.",
        {"AD"} -- Dimmed
    )

    -- Rank 4: Full House
    y = AddRankRow(
        panel, y,
        {"AC","AD","AS","KD","KC"},
        "FULL HOUSE",
        "Three cards of the same rank and two of another."
    )

    -- Rank 5: Flush
    y = AddRankRow(
        panel, y,
        {"2S","5S","7S","JS","AS"},
        "FLUSH",
        "Five cards of the same suit, in any order."
    )

    -- Rank 6: Straight
    y = AddRankRow(
        panel, y,
        {"4S","5H","6S","7H","8C"},
        "STRAIGHT",
        "Five consecutive cards of different suits."
    )

    -- Rank 7: Three of a Kind
    y = AddRankRow(
        panel, y,
        {"8H","8S","8D","AS","4H"},
        "THREE OF A KIND",
        "Three cards of the same rank.",
        {"AS","4H"} -- Dimmed
    )

    -- Rank 8: Two Pair
    y = AddRankRow(
        panel, y,
        {"AS","AH","KS","KD","2S"},
        "TWO PAIR",
        "Two cards of one rank and two of another.",
        {"2S"} -- Dimmed
    )

    -- Rank 9: One Pair
    y = AddRankRow(
        panel, y,
        {"JH","JS","5H","7S","2C"},
        "ONE PAIR",
        "Two cards of the same rank.",
        {"5H","7S","2C"} -- Dimmed
    )

    -- Rank 10: High Card
    y = AddRankRow(
        panel, y,
        {"QS","JH","6S","4D","3C"},
        "HIGH CARD",
        "Highest card when no other combination is possible.",
        {"JH","6S","4D","3C"} -- Dimmed
    )

    local footer = panel:CreateFontString(nil, "OVERLAY")
    footer:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    footer:SetTextColor(1, 1, 1, 0.9)
    footer:SetJustifyH("CENTER")
    footer:SetJustifyV("MIDDLE")
    footer:SetText("If two players have the same hand and it doesn’t yet use all five cards, the highest unused card (called the kicker) decides the winner; if that’s also the same, the pot is split between all eligible players.")
    footer:SetWidth(292 - 16)  -- Keep inside the horizontal padding
    footer:ClearAllPoints()
    footer:SetPoint("BOTTOM", panel, "BOTTOM", 0, 12)

    guidePanel = panel
    return panel
end

local function ToggleGuidePanel()
    local panel = guidePanel or CreateGuidePanel()
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

-- Guide button toggles the panel
guideBtn:SetScript("OnClick", function() ToggleGuidePanel() end)
-- == Table scale and volume ===============================================

-- Table scale setting, mirrors the lobby one
local tablePokerScale = 1.0

-- Applies the table scale
-- keepPlace keeps the window's centre where it is on screen, otherwise it re-centres
local function ApplyTablePokerScale(scale, keepPlace)
    tablePokerScale = scale
    local cx, cy = TableFrame:GetCenter()
    local old = TableFrame:GetScale()
    TableFrame:SetScale(scale)
    TableFrame:ClearAllPoints()
    if keepPlace and cx then
        TableFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * old / scale, cy * old / scale)
    else
        TableFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- Keep the Guide panel scaled and docked to TableFrame
    if guidePanel then
        guidePanel:SetScale(scale)
        guidePanel:ClearAllPoints()
        guidePanel:SetPoint("TOPRIGHT", TableFrame, "TOPLEFT", 0, 0)
        guidePanel:SetPoint("BOTTOMRIGHT", TableFrame, "BOTTOMLEFT", 0, 0)
    end

    if historyPanel then
        historyPanel:SetScale(scale)
        historyPanel:ClearAllPoints()
        historyPanel:SetPoint("TOPLEFT", TableFrame, "TOPRIGHT", -3, 0)
        historyPanel:SetPoint("BOTTOMLEFT", TableFrame, "BOTTOMRIGHT", 0, 0)
        if historyPanel._updateChatWidth then historyPanel._updateChatWidth() end
        if historyPanel._reflowChat then historyPanel._reflowChat() end
    end
end

ApplyTablePokerScale(tablePokerScale)

-- Step 1: SCALE button on the table frame
local tableScaleBtn = CreateFrame("Button", nil, TableFrame, "GameMenuButtonTemplate")
tableScaleBtn:SetSize(90, 28)
tableScaleBtn:SetText("Volume")
tableScaleBtn:SetPoint("TOPRIGHT", TableFrame, "TOPRIGHT", -12, -30)

-- Step 2: volume popup, hidden until opened
local tableVolumePopup = CreateFrame("Frame", nil, TableFrame, "BackdropTemplate")
tableVolumePopup:SetSize(220, 68)
tableVolumePopup:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
tableVolumePopup:SetBackdropColor(0, 0, 0, 0.95)
tableVolumePopup:SetPoint("BOTTOMLEFT", TableFrame, "TOPLEFT", 0, 0) -- Sits just above the frame
tableVolumePopup:SetFrameStrata("FULLSCREEN_DIALOG")
tableVolumePopup:Hide()

-- Step 3: volume slider inside the popup
local tableVolumeSlider = CreateFrame("Slider", "PokerTableVolumeSlider", tableVolumePopup, "OptionsSliderTemplate")
tableVolumeSlider:SetOrientation("HORIZONTAL")
tableVolumeSlider:SetSize(180, 18)
tableVolumeSlider:SetPoint("CENTER", tableVolumePopup, "CENTER", 0, 3)
tableVolumeSlider:SetMinMaxValues(0, 1)
tableVolumeSlider:SetValueStep(0.01)
tableVolumeSlider:SetObeyStepOnDrag(false)
tableVolumeSlider:SetValue(GetCVar("Sound_MasterVolume") and tonumber(GetCVar("Sound_MasterVolume")) or 1)

local tableVolumeTitle = tableVolumePopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
tableVolumeTitle:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
tableVolumeTitle:SetTextColor(1, 1, 1, 1)
tableVolumeTitle:SetText("VOLUME")
tableVolumeTitle:SetPoint("BOTTOM", tableVolumePopup, "BOTTOM", 0, 12)
tableVolumeTitle:SetJustifyH("CENTER")

_G[tableVolumeSlider:GetName() .. 'Low']:SetText("0%")
_G[tableVolumeSlider:GetName() .. 'High']:SetText("100%")
_G[tableVolumeSlider:GetName() .. 'Low']:ClearAllPoints()
_G[tableVolumeSlider:GetName() .. 'Low']:SetPoint("TOPLEFT", tableVolumeSlider, "BOTTOMLEFT", -4, 0)
_G[tableVolumeSlider:GetName() .. 'High']:ClearAllPoints()
_G[tableVolumeSlider:GetName() .. 'High']:SetPoint("TOPRIGHT", tableVolumeSlider, "BOTTOMRIGHT", 4, 0)
_G[tableVolumeSlider:GetName() .. 'Text']:SetText("")

-- Live value readout above the slider
local tableVolumeValueLabel = tableVolumePopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tableVolumeValueLabel:SetPoint("BOTTOM", tableVolumeSlider, "TOP", 0, 2)
tableVolumeValueLabel:SetTextColor(1, 1, 1, 1)
tableVolumeValueLabel:SetText(string.format("%d%%", (tableVolumeSlider:GetValue() * 100)))

local initialTableVolume = tonumber(GetCVar("Sound_MasterVolume")) or 1
tableVolumeSlider:SetValue(initialTableVolume)

tableVolumeSlider:SetScript("OnValueChanged", function(self, value)
    SetCVar("Sound_MasterVolume", value)
    SetCVar("Sound_SFXVolume", value)
    tableVolumeValueLabel:SetText(string.format("%d%%", value * 100))
end)

local potValue = 0
local potText = TableFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
potText:SetPoint("CENTER", TableFrame, "CENTER", 0, 25)
potText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
potText:SetText("Total Pot: 0 |T" .. POKER_MEDIA .. "1chip:16:16:0:0|t")

local function GetMinRaiseAmount()
    -- Highest current bet at the table
    local maxBet = 0
    for _, bet in pairs(playerBets) do
        if bet > maxBet then maxBet = bet end
    end
    -- Last raise size, or the big blind if nobody has raised
    local minRaise = lastRaiseAmount
    if minRaise == 0 then minRaise = BB end
    -- Minimum total bet is maxBet + minRaise
    return maxBet + minRaise
end

-- Deal animation settings (client side)
local playerDeckPos = { x = -50, y = 98 }  -- Deck start point, relative to TableFrame centre; tune to taste
local seatCardAngles = {
    [1] = 294, [2] = 262, [3] = 242, [4] = 207, [5] = 180,
    [6] = 168, [7] = 137, [8] = 110, [9] = 60,
}

-- Setters for tuning at runtime
function Poker_SetDeckPos(x, y)
    playerDeckPos.x, playerDeckPos.y = x, y
end
function Poker_SetSeatAngle(seat, degrees)
    if seat >= 1 and seat <= 9 then seatCardAngles[seat] = degrees end
end

-- Flies one card back from the deck to a seat, fades it, then calls onArrive()
local function AnimateDealCardToSeat(seatNum, onArrive)
    local seatFrame = seatMarkers[seatNum] and seatMarkers[seatNum].button
    if not seatFrame then if onArrive then onArrive() end return end

    -- Target: portrait centre, relative to TableFrame
    local destX, destY = seatFrame:GetCenter()
    local fx, fy = TableFrame:GetCenter()
    destX, destY = (destX - fx), (destY - fy)

    -- Origin: the deck
    local startX, startY = playerDeckPos.x, playerDeckPos.y

    -- The moving card back
    local cardTex = TableFrame:CreateTexture(nil, "OVERLAY")
    cardTex:SetTexture(POKER_MEDIA .. "card_back.tga")
    cardTex:SetSize(28, 56)
    cardTex:SetPoint("CENTER", TableFrame, "CENTER", startX, startY)
    cardTex:SetAlpha(1)
    local angleDeg = seatCardAngles[seatNum] or 0
    cardTex:SetRotation(math.rad(angleDeg))
    cardTex:Show()

    local duration = 0.5
    local fadePortion = 0.3
    local elapsed = 0

    TableFrame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        local t = math.min(elapsed / duration, 1)
        local x = startX + (destX - startX) * t
        local y = startY + (destY - startY) * t
        cardTex:SetPoint("CENTER", TableFrame, "CENTER", x, y)

        if t < (1 - fadePortion) then
            cardTex:SetAlpha(1)
        else
            local ft = (t - (1 - fadePortion)) / fadePortion
            if ft < 0 then ft = 0 elseif ft > 1 then ft = 1 end
            cardTex:SetAlpha(1 - ft)
        end

        if t >= 1 then
            TableFrame:SetScript("OnUpdate", nil)
            cardTex:Hide()
            cardTex:SetParent(nil)
            if onArrive then onArrive() end
        end
    end)
end

local function ShowCardAboveSeat(seatNum, cardCode, cardIndex, isPlayer)
    seatCardTextures[seatNum] = seatCardTextures[seatNum] or {}
    seatCardCodes[seatNum] = seatCardCodes[seatNum] or {}

    local isBack = (cardCode == "card_back")
    local existingFront = seatCardCodes[seatNum][cardIndex] -- Non-nil once a card face is showing

    -- Never let a card back replace a face already revealed in this slot
    if isBack and existingFront then
        return
    end

    -- Only clear the old texture when the card changes or a face is shown
    if seatCardTextures[seatNum][cardIndex] then
        seatCardTextures[seatNum][cardIndex]:Hide()
        seatCardTextures[seatNum][cardIndex]:SetParent(nil)
        seatCardTextures[seatNum][cardIndex] = nil
    end

    local seatFrame = seatMarkers[seatNum] and seatMarkers[seatNum].button
    if not seatFrame then return end

    local baseX, baseY
    if seatMarkers[seatNum] and seatMarkers[seatNum].type == "left" then
        baseX, baseY = -3, 38
    else
        baseX, baseY = -30, 38
    end
    local offsetX = (cardIndex - 1) * 32

    local texName = isBack and POKER_MEDIA .. "card_back.tga"
        or (POKER_MEDIA .. cardCode .. ".tga")

    local cardTex = TableFrame:CreateTexture(nil, "OVERLAY")
    cardTex:SetTexture(texName)
    cardTex:SetSize(28, 56)
    cardTex:SetPoint("CENTER", seatFrame, "CENTER", baseX + offsetX, baseY)
    cardTex:Show()

    seatCardTextures[seatNum][cardIndex] = cardTex
    seatCardCodes[seatNum][cardIndex] = isBack and nil or cardCode
end

local function ExtractCardCodeFromWhisper(msg)
    if not msg or msg == "" then return nil end
    local last
    for token in msg:gmatch("%[([^%]]+)%]") do
        token = token:upper()
        if token:match("^[2-9TJQKA][CDHS]$") or token:match("^10[CDHS]$") then
            last = token
        end
    end
    return last
end

local function NextHoleIndexForSeat(seatNum)
    seatCardCodes[seatNum] = seatCardCodes[seatNum] or {}
    for i = 1, 2 do
        if not seatCardCodes[seatNum][i] then
            return i
        end
    end
    return 2
end

-- The old small board cards sit on a hidden holder; PokerHUD draws the large board
local BoardHolder = CreateFrame("Frame", nil, TableFrame)
BoardHolder:SetAllPoints(TableFrame)
BoardHolder:Hide()

local function ShowFlopCard(cardCode, cardIndex)
    local flopPositions = {
        [1] = {x = -66, y = -12},
        [2] = {x = -33, y = -12},
        [3] = {x = 0, y = -12},
    }
    local pos = flopPositions[cardIndex]
    if flopCardTextures[cardIndex] then
        flopCardTextures[cardIndex]:Hide()
        flopCardTextures[cardIndex]:SetParent(nil)
        flopCardTextures[cardIndex] = nil
    end
    local cardTex = BoardHolder:CreateTexture(nil, "OVERLAY")
    cardTex:SetTexture(POKER_MEDIA .. cardCode .. ".tga")
    cardTex:SetSize(28, 56)
    cardTex:SetPoint("CENTER", TableFrame, "CENTER", pos.x, pos.y)
    cardTex:Show()
    flopCardTextures[cardIndex] = cardTex
    flopCodes[cardIndex] = cardCode
end

local function ClearFlopCards()
    for i = 1, 3 do
        if flopCardTextures[i] then
            flopCardTextures[i]:Hide()
            flopCardTextures[i]:SetParent(nil)
            flopCardTextures[i] = nil
        end
        flopCodes[i] = nil
    end
end

local function ClearTurnRiverCards()
    if turnCardTexture then
        turnCardTexture:Hide()
        turnCardTexture:SetParent(nil)
        turnCardTexture = nil
    end
    if riverCardTexture then
        riverCardTexture:Hide()
        riverCardTexture:SetParent(nil)
        riverCardTexture = nil
    end
end

local function ShowTurnCard(cardCode)
    if turnCardTexture then
        turnCardTexture:Hide()
        turnCardTexture:SetParent(nil)
        turnCardTexture = nil
    end
    local pos = { x = 33, y = -12 }
    local cardTex = BoardHolder:CreateTexture(nil, "OVERLAY")
    cardTex:SetTexture(POKER_MEDIA .. cardCode .. ".tga")
    cardTex:SetSize(28, 56)
    cardTex:SetPoint("CENTER", TableFrame, "CENTER", pos.x, pos.y)
    cardTex:Show()
    turnCardTexture = cardTex
    turnCode = cardCode
end

local function ShowRiverCard(cardCode)
    if riverCardTexture then
        riverCardTexture:Hide()
        riverCardTexture:SetParent(nil)
        riverCardTexture = nil
    end
    local pos = { x = 66, y = -12 }
    local cardTex = BoardHolder:CreateTexture(nil, "OVERLAY")
    cardTex:SetTexture(POKER_MEDIA .. cardCode .. ".tga")
    cardTex:SetSize(28, 56)
    cardTex:SetPoint("CENTER", TableFrame, "CENTER", pos.x, pos.y)
    cardTex:Show()
    riverCardTexture = cardTex
    riverCode = cardCode
end

local function ResetAllCardOpacity()
    for seatNum, texs in pairs(seatCardTextures) do
        for _, tex in pairs(texs) do
            if tex and tex.SetAlpha then tex:SetAlpha(1) end
        end
    end
    for i=1,3 do if flopCardTextures[i] then flopCardTextures[i]:SetAlpha(1) end end
    if turnCardTexture then turnCardTexture:SetAlpha(1) end
    if riverCardTexture then riverCardTexture:SetAlpha(1) end
end

local function ApplyWinningHighlight(codesSet)
    -- Seat hole cards
    for seatNum, texs in pairs(seatCardTextures) do
        for idx, tex in pairs(texs) do
            if tex and tex.SetAlpha then
                local code = seatCardCodes[seatNum] and seatCardCodes[seatNum][idx]
                if code and codesSet[code] then tex:SetAlpha(1) else tex:SetAlpha(0.25) end
            end
        end
    end
    -- Community cards
    for i=1,3 do
        local tex = flopCardTextures[i]
        if tex then
            local keep = flopCodes[i] and codesSet[flopCodes[i]]
            tex:SetAlpha(keep and 1 or 0.25)
        end
    end
    if turnCardTexture then
        local keep = turnCode and codesSet[turnCode]
        turnCardTexture:SetAlpha(keep and 1 or 0.25)
    end
    if riverCardTexture then
        local keep = riverCode and codesSet[riverCode]
        riverCardTexture:SetAlpha(keep and 1 or 0.25)
    end
end

local seatSpeechBubbles = {}
local GOLD_ICON = " |T" .. POKER_MEDIA .. "1chip:10:10:0:0|t"

local function EnsureSeatSpeechBubble(seatNum)
    if seatSpeechBubbles[seatNum] then return seatSpeechBubbles[seatNum] end
    local bubble = CreateFrame("Frame", nil, TableFrame, "BackdropTemplate")
    bubble:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    bubble:SetBackdropColor(0, 0, 0, 0.8)
    bubble:SetFrameStrata("DIALOG")
    bubble.text = bubble:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bubble.text:SetPoint("CENTER")
    bubble.text:SetTextColor(1, 1, 1, 1)
    bubble:Hide()
    seatSpeechBubbles[seatNum] = bubble
    return bubble
end

local function ShowSeatSpeechBubble(seatNum, text)
    if not seatNum then return end
    local anchor = seatPortraitFrames[seatNum] or (seatMarkers[seatNum] and seatMarkers[seatNum].button)
    if not anchor then return end

    local bubble = EnsureSeatSpeechBubble(seatNum)
    bubble.text:SetText(text)
    -- Fit to the text
    local w = math.max(36, bubble.text:GetStringWidth() + 16)
    local h = math.max(16, bubble.text:GetStringHeight() + 18)
    bubble:SetSize(w, h)

    bubble:ClearAllPoints()
    bubble:SetPoint("BOTTOM", anchor, "TOP", 0, 3)
    bubble:SetAlpha(1)
    bubble:Show()

    -- Fade out after a short delay
    local hold, fade = 1.5, 1.5
    local t = 0
    bubble:SetScript("OnUpdate", function(self, delta)
        t = t + delta
        if t > hold then
            local ft = (t - hold) / fade
            if ft >= 1 then
                self:SetScript("OnUpdate", nil)
                self:Hide()
            else
                self:SetAlpha(1 - ft)
            end
        end
    end)
end

local function UpdateBlinds(dealerSeat)
    -- Occupied seats, ascending
    local occupied = {}
    for i = 1, 9 do
        if occupiedSeats[i] then
            table.insert(occupied, i)
        end
    end

    -- Reset every seat to normal first
    for i = 1, 9 do
        if seatMarkers[i] then
            if seatMarkers[i].type == "left" then
                seatMarkers[i].texture:SetTexture(POKER_MEDIA .. "Normal_Left.tga")
            else
                seatMarkers[i].texture:SetTexture(POKER_MEDIA .. "Normal_Right.tga")
            end
        end
    end

    -- Blinds need at least two players
    if #occupied < 2 then
        return
    end

    -- Dealer's position in the occupied list
    local dealerIdx
    for idx, seat in ipairs(occupied) do
        if seat == dealerSeat then
            dealerIdx = idx
            break
        end
    end
    if not dealerIdx then return end

    if #occupied == 2 then
        -- Heads-up: dealer posts the small blind, the other player the big blind
        local sbSeatLocal = dealerSeat
        local bbSeatLocal = occupied[((dealerSeat == occupied[1]) and 2 or 1)]
        -- Apply the blind textures
        for i = 1, 9 do
            if seatMarkers[i] then
                if i == sbSeatLocal then
                    if seatMarkers[i].type == "left" then
                        seatMarkers[i].texture:SetTexture(POKER_MEDIA .. "SB_Left.tga")
                    else
                        seatMarkers[i].texture:SetTexture(POKER_MEDIA .. "SB_Right.tga")
                    end
                elseif i == bbSeatLocal then
                    if seatMarkers[i].type == "left" then
                        seatMarkers[i].texture:SetTexture(POKER_MEDIA .. "BB_Left.tga")
                    else
                        seatMarkers[i].texture:SetTexture(POKER_MEDIA .. "BB_Right.tga")
                    end
                end
            end
        end
        bbSeat = bbSeatLocal  -- Remember the big blind seat globally
    else
        -- Three or more: small blind next after the dealer, big blind after that
        local sbIdx = (dealerIdx % #occupied) + 1
        local bbIdx = (sbIdx % #occupied) + 1
        local sbSeatLocal = occupied[sbIdx]
        local bbSeatLocal = occupied[bbIdx]
        for i = 1, 9 do
            if seatMarkers[i] then
                if i == sbSeatLocal then
                    if seatMarkers[i].type == "left" then
                        seatMarkers[i].texture:SetTexture(POKER_MEDIA .. "SB_Left.tga")
                    else
                        seatMarkers[i].texture:SetTexture(POKER_MEDIA .. "SB_Right.tga")
                    end
                elseif i == bbSeatLocal then
                    if seatMarkers[i].type == "left" then
                        seatMarkers[i].texture:SetTexture(POKER_MEDIA .. "BB_Left.tga")
                    else
                        seatMarkers[i].texture:SetTexture(POKER_MEDIA .. "BB_Right.tga")
                    end
                end
            end
        end
        bbSeat = bbSeatLocal  -- Remember the big blind seat globally
    end
end

local function GetUnitIDByName(name)
    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        if UnitName(unit) == name then
            return unit
        end
        local punit = "party" .. i
        if UnitName(punit) == name then
            return punit
        end
    end
    if UnitName("player") == name then
        return "player"
    end
    return nil
end

-- Portrait builder
local function CreatePlayerPortrait(seatNumber, playerName, unitID)
    if not seatNumber or not portraitPositions[seatNumber] then return end

    -- Clear only this seat's old portrait
    if seatPortraitFrames[seatNumber] then
        seatPortraitFrames[seatNumber]:Hide()
        seatPortraitFrames[seatNumber]:SetParent(nil)
        seatPortraitFrames[seatNumber]:ClearAllPoints()
        seatPortraitFrames[seatNumber] = nil
    end

    local portraitMask = CreateFrame("Frame", nil, TableFrame)
    portraitMask:SetSize(42, 42)
    portraitMask:SetPoint("CENTER", TableFrame, "CENTER", portraitPositions[seatNumber].x, portraitPositions[seatNumber].y)

    local maskTexture = portraitMask:CreateMaskTexture()
    maskTexture:SetTexture("Interface\\Minimap\\UI-Minimap-Background", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    maskTexture:SetAllPoints(portraitMask)

    local portrait = portraitMask:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(42, 42)
    portrait:SetAllPoints(portraitMask)
    portrait:AddMaskTexture(maskTexture)

    if unitID then
        SetPortraitTexture(portrait, unitID)
    else
        -- Unit outside your group, such as a practice bot
        portrait:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    end

    seatPortraitFrames[seatNumber] = portraitMask
end



-- Central info panel, 100px above centre
local infoFrame = CreateFrame("Frame", nil, TableFrame, "BackdropTemplate")
infoFrame:SetSize(170, 55)
infoFrame:SetPoint("TOPRIGHT", TableFrame, "TOPRIGHT", -14, -62) -- Below Settings, clear of the felt
infoFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
infoFrame:SetBackdropColor(0, 0, 0, 0.65)
infoFrame:SetBackdropBorderColor(1, 1, 1, 0.4)
infoFrame:SetFrameStrata("DIALOG")

local BB = 50
local SB = 25
local Rake = 5.0
local RakeCapMult = 5

-- Smaller font for the info panel
local infoFont = "Fonts\\FRIZQT__.TTF"
local infoFontSize = 10 -- Around 10 to 12 works best

-- Row 1: BB and SB, centred
local bbLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bbLabel:SetFont(infoFont, infoFontSize, "")
bbLabel:SetText("BB:")
bbLabel:SetTextColor(1, 1, 1, 1)

local bbValue = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bbValue:SetFont(infoFont, infoFontSize, "")
bbValue:SetText("|cffffff00" .. BB .. "|r |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
bbValue:SetTextColor(1, 1, 1, 1)

local sbLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sbLabel:SetFont(infoFont, infoFontSize, "")
sbLabel:SetText("SB:")
sbLabel:SetTextColor(1, 1, 1, 1)

local sbValue = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sbValue:SetFont(infoFont, infoFontSize, "")
sbValue:SetText("|cffffff00" .. SB .. "|r |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
sbValue:SetTextColor(1, 1, 1, 1)

-- Place row 1, centred with a gap
bbLabel:SetPoint("TOP", infoFrame, "TOP", -51, -7)
bbValue:SetPoint("LEFT", bbLabel, "RIGHT", 4, 0)
sbLabel:SetPoint("LEFT", bbValue, "RIGHT", 24, 0)
sbValue:SetPoint("LEFT", sbLabel, "RIGHT", 4, 0)

-- Row 2: Rake and Cap, centred, tighter gap
local rakeLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
rakeLabel:SetFont(infoFont, infoFontSize, "")
rakeLabel:SetText("Rake:")
rakeLabel:SetTextColor(1, 1, 1, 1)

local rakeValue = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
rakeValue:SetFont(infoFont, infoFontSize, "")
rakeValue:SetText("|cffffff00" .. string.format("%.1f", Rake) .. "%|r")
rakeValue:SetTextColor(1, 1, 1, 1)

local capLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
capLabel:SetFont(infoFont, infoFontSize, "")
capLabel:SetText("Cap:")
capLabel:SetTextColor(1, 1, 1, 1)

local capValue = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
capValue:SetFont(infoFont, infoFontSize, "")
capValue:SetText("|cffffff00" .. RakeCapMult .. "x BB|r")
capValue:SetTextColor(1, 1, 1, 1)

-- Place row 2, centred with a gap
rakeLabel:SetPoint("TOP", infoFrame, "TOP", -58, -22)
rakeValue:SetPoint("LEFT", rakeLabel, "RIGHT", 4, 0)
capLabel:SetPoint("LEFT", rakeValue, "RIGHT", 24, 0)
capValue:SetPoint("LEFT", capLabel, "RIGHT", 4, 0)

-- Row 3: player timer, centred, tighter gap
local timerLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
timerLabel:SetFont(infoFont, infoFontSize, "")
timerLabel:SetText("Player Timer:")
timerLabel:SetTextColor(1, 1, 1, 1)

local timerValue = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
timerValue:SetFont(infoFont, infoFontSize, "")
timerValue:SetText("|cffffff00" .. "30s|r")
timerValue:SetTextColor(1, 1, 1, 1)

-- Place row 3, centred
timerLabel:SetPoint("TOP", infoFrame, "TOP", -15, -37)
timerValue:SetPoint("LEFT", timerLabel, "RIGHT", 8, 0)

-- Decision box above the info panel
local decisionBox = CreateFrame("Frame", nil, TableFrame, "BackdropTemplate")
decisionBox:SetSize(280, 105)
decisionBox:SetPoint("BOTTOM", infoFrame, "TOP", 0, 4)
decisionBox:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
})
decisionBox:SetBackdropColor(0, 0, 0, 0.85)
decisionBox:SetBackdropBorderColor(1, 1, 1, 0.5)
decisionBox:SetFrameStrata("DIALOG")
decisionBox:Hide()

-- Row 1: slider on the right, value label to its left
local raiseSlider = CreateFrame("Slider", "PokerRaiseSlider", decisionBox, "OptionsSliderTemplate")
raiseSlider:SetOrientation("HORIZONTAL")
raiseSlider:SetSize(180, 24) -- Thicker and slightly wider
raiseSlider:SetPoint("TOPRIGHT", decisionBox, "TOPRIGHT", -14, -10) -- 12px in from the top and right
raiseSlider:SetMinMaxValues(100, 10000)
raiseSlider:SetValueStep(1)
raiseSlider:SetObeyStepOnDrag(false)
raiseSlider:SetValue(100)

-- Hide the slider's default labels
local low = _G[raiseSlider:GetName() .. 'Low']
local high = _G[raiseSlider:GetName() .. 'High']
local text = _G[raiseSlider:GetName() .. 'Text']
if low then low:SetText("") end
if high then high:SetText("") end
if text then text:SetText("") end

-- Live value label left of the slider
local raiseValueLabel = decisionBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
raiseValueLabel:SetPoint("RIGHT", raiseSlider, "LEFT", -8, 0)
raiseValueLabel:SetTextColor(1, 1, 1, 1)
raiseValueLabel:SetText("100 |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")

-- Percent buttons and an amount box:
local percentBtns = {}  -- Index 1 is 25%, 2 is 50%, 3 is 100%
local pctSpecs = {
    { label = "25%", pct = 0.25 },
    { label = "50%", pct = 0.50 },
    { label = "100%", pct = 1.00 },
}
local btnWidth, btnHeight, btnSpacing = 47, 28, 3
for i, spec in ipairs(pctSpecs) do
    local btn = CreateFrame("Button", nil, decisionBox, "GameMenuButtonTemplate")
    btn:SetSize(btnWidth, btnHeight)
    btn:SetText(spec.label)
    btn:SetPoint("TOPLEFT", decisionBox, "TOPLEFT", 12 + (i-1)*(btnWidth + btnSpacing), -35)
    btn._pct = spec.pct
    percentBtns[i] = btn
end

-- Amount box in the slot the old 75% button used
local amountEdit = CreateFrame("EditBox", nil, decisionBox, "InputBoxTemplate")
amountEdit:SetSize(42, btnHeight)
-- Same position as button 4
amountEdit:SetPoint("TOPLEFT", decisionBox, "TOPLEFT", 19 + (3)*(btnWidth + btnSpacing), -35)
amountEdit:SetAutoFocus(false)
amountEdit:SetNumeric(false)        -- Input is filtered by hand
amountEdit:SetMaxLetters(8)
amountEdit:SetText("0")
amountEdit:ClearFocus()

decisionBox.amountEdit  = amountEdit

local allInBtn = CreateFrame("Button", nil, decisionBox, "GameMenuButtonTemplate")
allInBtn:SetSize(55, 28)
allInBtn:SetText("All-In")
allInBtn:SetPoint("TOPLEFT", amountEdit, "TOPRIGHT", 3, 0)
decisionBox.allInBtn = allInBtn

-- Row 2: Fold, Call, Raise, Check, Bet
local foldBtn = CreateFrame("Button", nil, decisionBox, "GameMenuButtonTemplate")
foldBtn:SetSize(55, 28)
foldBtn:SetText("Fold")
foldBtn:SetPoint("BOTTOMLEFT", decisionBox, "BOTTOMLEFT", 12, 12)

local callBtn = CreateFrame("Button", nil, decisionBox, "GameMenuButtonTemplate")
callBtn:SetSize(90, 28)
local callAmount = 25 -- Updated at runtime
callBtn:SetText("Call " .. callAmount .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
callBtn:SetPoint("LEFT", foldBtn, "RIGHT", 3, 0)

local checkBtn = CreateFrame("Button", nil, decisionBox, "GameMenuButtonTemplate")
checkBtn:SetSize(90, 28)
checkBtn:SetText("Check")
checkBtn:SetPoint("LEFT", foldBtn, "RIGHT", 3, 0)
checkBtn:Hide()

local raiseBtn = CreateFrame("Button", nil, decisionBox, "GameMenuButtonTemplate")
raiseBtn:SetSize(106, 28)
raiseBtn:SetText("Raise to 100 |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
raiseBtn:SetPoint("LEFT", callBtn, "RIGHT", 3, 0)

local betBtn = CreateFrame("Button", nil, decisionBox, "GameMenuButtonTemplate")
betBtn:SetSize(106, 28)
betBtn:SetText("Bet")
betBtn:SetPoint("LEFT", callBtn, "RIGHT", 3, 0)
betBtn:Hide()

betBtn:SetScript("OnClick", function()
    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    local betAmount = math.floor(decisionBox.raiseSlider:GetValue() + 0.0001)
    if playerSeat then ShowSeatSpeechBubble(playerSeat, "Bet " .. betAmount .. GOLD_ICON) end
    Poker_SendAddonMessage("PokerTable", "RAISE:" .. myName .. ":" .. betAmount, Poker_Channel())
    decisionBox:Hide()
end)

local function GetCurrentMinTotal()
    local maxBet = 0
    for _, b in pairs(playerBets) do if b > maxBet then maxBet = b end end
    -- New betting round, with nothing to call yet
    local isBetRound = (maxBet == 0) and (not preflopRoundActive)
    if isBetRound then
        return BB -- Smallest opening bet
    end
    -- Raise round: use the last raise size or the big blind
    local minRaise = (lastRaiseAmount > 0) and lastRaiseAmount or BB
    return maxBet + minRaise
end


local smallFont = "Fonts\\FRIZQT__.TTF"
local smallFontSize = 10

-- Per-button setup after creation
foldBtn.Text:SetFont(smallFont, smallFontSize)
callBtn.Text:SetFont(smallFont, smallFontSize)
checkBtn.Text:SetFont(smallFont, smallFontSize)
raiseBtn.Text:SetFont(smallFont, smallFontSize)
betBtn.Text:SetFont(smallFont, smallFontSize)
for _, btn in ipairs(percentBtns) do
    btn.Text:SetFont(smallFont, smallFontSize)
end
allInBtn.Text:SetFont(smallFont, smallFontSize)

-- Keep references for the action logic
decisionBox.foldBtn = foldBtn
decisionBox.callBtn = callBtn
decisionBox.checkBtn = checkBtn
decisionBox.raiseBtn = raiseBtn
decisionBox.betBtn = betBtn
decisionBox.percentBtns = percentBtns
decisionBox.allInBtn = allInBtn
decisionBox.raiseSlider = raiseSlider
decisionBox.raiseValueLabel = raiseValueLabel

local UpdatePercentButtons
local UpdateAllInLock

local function UpdateCallButton()
    -- Work out the table's top bet and our amount to call
    local maxBet = 0
    for _, bet in pairs(playerBets) do
        if bet > maxBet then maxBet = bet end
    end
    local myBet = playerBets[playerSeat] or 0
    local callAmount = maxBet - myBet

    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    local bankroll = playerBankrolls[myName] or 0

    -- Case 1: no bet to face this street (flop onwards), so Check or Bet
    if not preflopRoundActive and maxBet == 0 then
        -- Button states
        callBtn:Hide()
        checkBtn:Show(); checkBtn:Enable()
        raiseBtn:Hide()
        betBtn:Show()

        -- Slider range from the big blind up to the bankroll, whichever is lower
        local minBet = math.min(BB, bankroll)
        decisionBox.raiseSlider:SetMinMaxValues(minBet, bankroll)
        decisionBox.raiseSlider:SetValue(minBet)
        decisionBox.raiseSlider:Enable()

        -- Labels and text
        local goldText = tostring(minBet) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t"
        decisionBox.raiseValueLabel:SetText(goldText)
        betBtn:SetText("Bet " .. goldText)

        -- Bet needs at least a big blind
        if bankroll >= BB and BB > 0 then betBtn:Enable() else betBtn:Disable() end

        UpdatePercentButtons()
        UpdateAllInLock()
        return
    end

    -- Case 2: facing a bet, preflop or later
    betBtn:Hide()
    raiseBtn:Show()

    -- Min-raise text for the Raise button
    local minRaise = lastRaiseAmount; if minRaise == 0 then minRaise = BB end
    local minTo = maxBet + minRaise
    local goldRaiseText = tostring(minTo) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t"
    raiseBtn:SetText("Raise to " .. goldRaiseText)

    if callAmount > 0 then
        -- Call is always shown when facing a bet
        callBtn:SetText("Call " .. callAmount .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
        callBtn:Show()
        checkBtn:Hide()
    else
        -- Nothing owed: show Check in place of Call
        callBtn:Hide()
        checkBtn:Show()
        checkBtn:Enable()
    end

    -- Cannot cover the call: show buttons but only enable Fold and All-In
    if callAmount > 0 and bankroll < callAmount then
        -- Call and Raise stay visible but disabled
        if callAmount > 0 then callBtn:Disable() end
        raiseBtn:Disable()

        -- Pin the slider to the bankroll and disable percent buttons
        local lockMin = math.max(1, bankroll)
        decisionBox.raiseSlider:SetMinMaxValues(lockMin, bankroll)
        decisionBox.raiseSlider:SetValue(bankroll)
        decisionBox.raiseSlider:Disable()

        -- Label shows the pinned value
        decisionBox.raiseValueLabel:SetText(tostring(bankroll) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")

        -- Percent buttons off
        for _, btn in ipairs(decisionBox.percentBtns or {}) do
            btn:Disable()
            btn:SetScript("OnClick", nil)
        end

        -- Fold and All-In only
        if foldBtn then foldBtn:Enable() end
        if allInBtn then allInBtn:SetEnabled(bankroll > 0) end

        UpdatePercentButtons()
        UpdateAllInLock()
        return
    end

    -- Regular facing-bet path, call is affordable
    if callAmount > 0 then
        callBtn:Enable()
        checkBtn:Hide()
    else
        callBtn:Hide()
        checkBtn:Show(); checkBtn:Enable()
    end

    -- Minimum raise-to total is maxBet + max(lastRaiseAmount, BB)
    local minVal = math.min(minTo, bankroll)
    local maxVal = bankroll
    decisionBox.raiseSlider:SetMinMaxValues(minVal, maxVal)
    decisionBox.raiseSlider:SetValue(minVal)

    local goldText = tostring(minVal) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t"
    decisionBox.raiseValueLabel:SetText(goldText)
    raiseBtn:SetText("Raise to " .. goldText)
    raiseBtn:Enable()

    UpdatePercentButtons()
    UpdateAllInLock()
end

local function UpdateRaiseSliderForBankroll()
    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    local bankroll = playerBankrolls[myName] or 0

    local maxBet = 0
    for _, bet in pairs(playerBets) do if bet > maxBet then maxBet = bet end end
    local myBet = playerBets[playerSeat] or 0
    local callAmount = maxBet - myBet

    if callAmount > 0 and bankroll < callAmount then
        -- Too short: All-In only
        decisionBox.raiseSlider:SetMinMaxValues(math.max(1, bankroll), bankroll)
        decisionBox.raiseSlider:SetValue(bankroll)
        decisionBox.raiseSlider:Disable()
        if decisionBox.raiseBtn then decisionBox.raiseBtn:Disable() end
        if decisionBox.betBtn then decisionBox.betBtn:Disable() end
        for _, b in ipairs(decisionBox.percentBtns or {}) do b:Disable() end
        if decisionBox.allInBtn then decisionBox.allInBtn:SetEnabled(bankroll > 0) end
        return
    end

    local minVal, maxVal
    if not preflopRoundActive and maxBet == 0 then
        minVal = math.min(BB, bankroll)
        maxVal = bankroll
        decisionBox.raiseSlider:SetMinMaxValues(minVal, maxVal)
        decisionBox.raiseSlider:SetValue(minVal)
        decisionBox.raiseValueLabel:SetText(minVal .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
        decisionBox.betBtn:SetText("Bet " .. minVal .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
    else
        local minRaise = lastRaiseAmount; if minRaise == 0 then minRaise = BB end
        local minTotal = maxBet + minRaise
        minVal = math.min(minTotal, bankroll)
        maxVal = bankroll
        decisionBox.raiseSlider:SetMinMaxValues(minVal, maxVal)
        decisionBox.raiseSlider:SetValue(minVal)
        decisionBox.raiseValueLabel:SetText(minVal .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
        decisionBox.raiseBtn:SetText("Raise to " .. minVal .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
    end

    UpdateAllInLock()
    UpdatePercentButtons()
end

-- Percent and All-In helpers
local function EffectiveMinTotalForPercentButtons()
    local maxBet = 0
    for _, bet in pairs(playerBets) do if bet > maxBet then maxBet = bet end end
    local myBet = playerBets[playerSeat] or 0

    -- Preflop first to act is handled separately
    if preflopRoundActive and not bbHasActed and maxBet == BB and myBet == 0 then
        return BB
    end

    if maxBet == 0 then
        return BB -- No bet yet this street: minimum is the big blind
    end

    local minRaise = (lastRaiseAmount > 0) and lastRaiseAmount or BB
    return maxBet + minRaise
end

-- Assigned to the forward-declared local, not a new local function
UpdatePercentButtons = function()
    if not decisionBox or not decisionBox:IsShown() then return end
    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    local bankroll = playerBankrolls[myName] or 0
    local pot = potValue or 0
    local slider = decisionBox.raiseSlider
    if not slider then return end

    local minTotal = GetCurrentMinTotal()

    for _, btn in ipairs(decisionBox.percentBtns or {}) do
        -- Target is ceil(pot * pct), so 18.75 becomes 19
        local target = math.ceil(pot * btn._pct)
        -- Disabled when target < minTotal, target > bankroll, or bankroll < minTotal
        if target < minTotal or target > bankroll or bankroll < minTotal then
            btn:Disable()
            btn:SetScript("OnClick", nil)
        else
            btn:Enable()
            btn:SetScript("OnClick", function()
                -- Only move the slider when target >= minTotal
                slider:SetValue(target)
            end)
        end
    end

    -- Amount box needs at least 1 chip
    decisionBox.amountEdit:SetEnabled(bankroll > 0)
end

-- == Amount box and slider sync ===========================================
local _editChanging = false
local _sliderChanging = false

-- Cleans numeric input
local function SanitizeNumber(str)
    str = (str or ""):gsub("[^0-9]", "")
    if str == "" then return 0 end
    return tonumber(str) or 0
end

amountEdit:SetScript("OnTextChanged", function(self, userInput)
    if not userInput or _sliderChanging then return end
    _editChanging = true

    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    local bankroll = playerBankrolls[myName] or 0
    local vRaw = self:GetText() or ""
    -- An empty box is allowed while typing and reads as 0
    local v = tonumber(vRaw:match("^(%d+)$") or "") or 0
    if v > bankroll then v = bankroll end

    local minTotal = GetCurrentMinTotal()
    local slider = decisionBox.raiseSlider
    local isBetRound = (function()
        local maxBet = 0
        for _, b in pairs(playerBets) do if b > maxBet then maxBet = b end end
        return (maxBet == 0) and (not preflopRoundActive)
    end)()

    -- Value changed, ignoring leading zeros
    if tostring(v) ~= vRaw and vRaw ~= "" then
        self:SetText(tostring(v))
        self:SetCursorPosition(#tostring(v))
    end

    -- Toggle the Bet and Raise buttons
    if isBetRound then
        if v >= minTotal then
            decisionBox.betBtn:Enable()
            -- Move the slider to match
            slider:SetValue(v)
        else
            decisionBox.betBtn:Disable()
            -- Hold the slider at minTotal, never below it
            slider:SetValue(minTotal)
        end
    else
        if v >= minTotal then
            decisionBox.raiseBtn:Enable()
            slider:SetValue(v)
        else
            decisionBox.raiseBtn:Disable()
            slider:SetValue(minTotal)
        end
    end

    -- Below the minimum, the slider label still shows minTotal
    if v < minTotal then
        local goldText = tostring(minTotal) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t"
        decisionBox.raiseValueLabel:SetText(goldText)
        if isBetRound then
            decisionBox.betBtn:SetText("Bet " .. goldText)
        else
            decisionBox.raiseBtn:SetText("Raise to " .. goldText)
        end
    end

    UpdatePercentButtons()
    UpdateAllInLock()
    _editChanging = false
end)

amountEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
amountEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Assigned to the forward-declared local, not a new local function
UpdateAllInLock = function()
    if not decisionBox or not decisionBox:IsShown() then return end
    local slider = decisionBox.raiseSlider
    if not slider then return end

    -- Slider position
    local minVal, maxVal = slider:GetMinMaxValues()
    local v = math.floor(slider:GetValue() + 0.0001)
    local atMax = (math.floor(maxVal + 0.0001) == v)

    -- Work out whether we are short of the call
    local maxBet = 0
    for _, bet in pairs(playerBets) do if bet > maxBet then maxBet = bet end end
    local myBet = playerBets[playerSeat] or 0
    local callAmount = maxBet - myBet
    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    local bankroll = playerBankrolls[myName] or 0
    local shortToCall = (callAmount > 0) and (bankroll < callAmount)

    if atMax then
        -- Fold and All-In stay enabled
        if decisionBox.foldBtn then decisionBox.foldBtn:Enable() end
        if decisionBox.allInBtn then decisionBox.allInBtn:Enable() end

        -- Block raise, bet and percent buttons
        if decisionBox.raiseBtn then decisionBox.raiseBtn:Disable() end
        if decisionBox.betBtn then decisionBox.betBtn:Disable() end
        for _, btn in ipairs(decisionBox.percentBtns or {}) do btn:Disable() end

        -- When short, Call stays visible but disabled
        if shortToCall and decisionBox.callBtn and decisionBox.callBtn:IsShown() then
            decisionBox.callBtn:Disable()
        end
        -- UpdateCallButton owns Check/Call visibility and state, so leave them here
        return
    end

    -- Slider below max: restore normal actions unless short of the call
    if decisionBox.betBtn and decisionBox.betBtn:IsShown() then
        decisionBox.betBtn:Enable()
    end
    if decisionBox.checkBtn and decisionBox.checkBtn:IsShown() then
        decisionBox.checkBtn:Enable()
    end
    if decisionBox.raiseBtn and decisionBox.raiseBtn:IsShown() then
        if shortToCall then decisionBox.raiseBtn:Disable() else decisionBox.raiseBtn:Enable() end
    end
    if decisionBox.callBtn and decisionBox.callBtn:IsShown() then
        if shortToCall then decisionBox.callBtn:Disable() else decisionBox.callBtn:Enable() end
    end

    UpdatePercentButtons()
end

local backRowDenoms = {1000, 500, 100}
local frontRowDenoms = {25, 5, 1}
local chipDenoms = {1000, 500, 100, 25, 5, 1}
local chipTextures = {
    [1] = POKER_MEDIA .. "1chip.tga",
    [5] = POKER_MEDIA .. "5chip.tga",
    [25] = POKER_MEDIA .. "25chip.tga",
    [100] = POKER_MEDIA .. "100chip.tga",
    [500] = POKER_MEDIA .. "500chip.tga",
    [1000] = POKER_MEDIA .. "1000chip.tga",
}
local seatChipFrames = {}

local function ShowChipsAtSeat(seatNum, amount)
    local originalAmount = amount

    -- Clear old chips but keep the amount box
    if seatChipFrames[seatNum] then
        for _, chip in ipairs(seatChipFrames[seatNum]) do
            chip:Hide()
            chip:SetParent(nil)
        end
        -- Keep seatChipFrames[seatNum], or the amountBox reference is lost
    else
        seatChipFrames[seatNum] = {}
    end

    local seatFrame = seatMarkers[seatNum] and seatMarkers[seatNum].button
    if not seatFrame then return end

    local chipAnchorPositions = {
        [1] = {x = -60, y = -100},
        [2] = {x = -138, y = -25},
        [3] = {x = -135, y = 50},
        [4] = {x = -35, y = 110},
        [5] = {x = -30, y = 110},
        [6] = {x = 25, y = 110},
        [7] = {x = 141, y = 50},
        [8] = {x = 141, y = -30},
        [9] = {x = 60, y = -100},
    }
    local anchor = chipAnchorPositions[seatNum] or {x = 0, y = 30}

    local direction = (seatNum >= 1 and seatNum <= 4) and -1 or 1
    local baseY = anchor.y
    local stackSpacing = 22
    local chipSize = 24

    local tempAmount = amount

    -- Back row, large chips
    local backX = anchor.x
    for _, denom in ipairs(backRowDenoms) do
        local count = math.floor(tempAmount / denom)
        if count > 0 then
            for i = 1, count do
                local chip = TableFrame:CreateTexture(nil, "OVERLAY")
                chip:SetTexture(chipTextures[denom])
                chip:SetSize(chipSize, chipSize)
                chip:SetPoint("CENTER", seatFrame, "CENTER", backX, baseY + (i-1)*3 + 2)
                chip:Show()
                table.insert(seatChipFrames[seatNum], chip)
            end
            backX = backX + direction * stackSpacing
            tempAmount = tempAmount - count * denom
        end
    end

    -- Front row, small chips, shifted half a chip sideways
    local frontX = anchor.x + direction * (stackSpacing / 2)
    for _, denom in ipairs(frontRowDenoms) do
        local count = math.floor(tempAmount / denom)
        if count > 0 then
            for i = 1, count do
                local chip = TableFrame:CreateTexture(nil, "OVERLAY")
                chip:SetTexture(chipTextures[denom])
                chip:SetSize(chipSize, chipSize)
                chip:SetPoint("CENTER", seatFrame, "CENTER", frontX, baseY + (i-1)*3 - 10)
                chip:Show()
                table.insert(seatChipFrames[seatNum], chip)
            end
            frontX = frontX + direction * stackSpacing
            tempAmount = tempAmount - count * denom
        end
    end

    -- Front row stack count, one per denomination used
    local numFrontStacks = 0
    local tempAmountBox = originalAmount
    for _, denom in ipairs(frontRowDenoms) do
        local count = math.floor(tempAmountBox / denom)
        if count > 0 then
            numFrontStacks = numFrontStacks + 1
            tempAmountBox = tempAmountBox - count * denom
        end
    end

    -- Centre the box under the middle front stack
    local boxOffsetX
    if numFrontStacks > 0 then
        local middleIndex = (numFrontStacks - 1) / 2
        boxOffsetX = anchor.x + direction * ((stackSpacing / 2) + middleIndex * stackSpacing)
    else
        boxOffsetX = anchor.x
    end
    local boxOffsetY = baseY - chipSize / 2 - 11

    -- Amount box only when amount > 0
    if originalAmount > 0 then
        local amtText = tostring(originalAmount) .. " |T" .. POKER_MEDIA .. "1chip:10:10:0:0|t"
        if seatChipFrames[seatNum].amountBox then
            -- Update the existing box
            local box = seatChipFrames[seatNum].amountBox
            local amtFS = box.amtFS
            if amtFS then
                amtFS:SetText(amtText)
                -- Resize if needed
                local tempFontString = TableFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                tempFontString:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
                tempFontString:SetText(amtText)
                local textWidth = tempFontString:GetStringWidth()
                tempFontString:Hide()
                local boxWidth = math.max(32, textWidth + 12)
                box:SetSize(boxWidth, 15)
            end
            box:ClearAllPoints()
            box:SetPoint("CENTER", seatFrame, "CENTER", boxOffsetX, boxOffsetY)
            box:Show()
        else
            -- Build a new box
            local box = CreateFrame("Frame", nil, TableFrame, "BackdropTemplate")
            local tempFontString = TableFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tempFontString:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            tempFontString:SetText(amtText)
            local textWidth = tempFontString:GetStringWidth()
            tempFontString:Hide()
            local boxWidth = math.max(32, textWidth + 12)
            box:SetSize(boxWidth, 15)
            box:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 7,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            box:SetBackdropColor(0, 0, 0, 0.65)
            box:SetFrameStrata("DIALOG")
            box:SetPoint("CENTER", seatFrame, "CENTER", boxOffsetX, boxOffsetY)
            local amtFS = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            amtFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            amtFS:SetTextColor(1, 0.82, 0, 1)
            amtFS:SetPoint("CENTER", box, "CENTER", 0, 0)
            amtFS:SetText(amtText)
            box.amtFS = amtFS -- Keep for later updates
            box:Show()
            seatChipFrames[seatNum].amountBox = box
        end
    else
        -- Hide the amount box if present
        if seatChipFrames[seatNum].amountBox then
            seatChipFrames[seatNum].amountBox:Hide()
        end
    end
end

local seatProgressBars = {}

-- Progress bar offsets per seat; tune as needed
local progressBarOffsets = {
    [1] = {x = 20, y = 72},
    [2] = {x = 20, y = 72},
    [3] = {x = 20, y = 72},
    [4] = {x = 20, y = 72},
    [5] = {x = -20, y = 72}, -- Shifted left for seat 5
    [6] = {x = -20, y = 72},
    [7] = {x = -20, y = 72},
    [8] = {x = -20, y = 72},
    [9] = {x = -20, y = 72},
}

local function CreateSeatProgressBar(seatNum)
    if seatProgressBars[seatNum] then return end

    local seatFrame = seatMarkers[seatNum] and seatMarkers[seatNum].button
    if not seatFrame then return end

    local offset = progressBarOffsets[seatNum] or {x = 0, y = 72}

    -- Border frame around the bar
    local border = CreateFrame("Frame", nil, TableFrame, "BackdropTemplate")
    border:SetSize(77, 12) -- Bar size plus a 3px border
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 4,
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    border:SetBackdropColor(0, 0, 0, 0.1)
    border:SetBackdropBorderColor(1, 1, 1, 1)
    border:SetFrameStrata("DIALOG")
    border:SetPoint("TOP", seatFrame, "BOTTOM", offset.x, offset.y)

    -- Bar frame inside the border
    local bar = CreateFrame("StatusBar", nil, border)
    bar:SetSize(75, 10)
    bar:SetPoint("CENTER", border, "CENTER", 0, 0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.2, 0.6, 1)
    bar:SetMinMaxValues(0, 60)
    bar:SetValue(0)
    bar:SetFrameStrata("DIALOG")

    -- Bar background
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetColorTexture(0, 0, 0, 0.4)

    seatProgressBars[seatNum] = bar
end

-- Last-action helpers (client UI)
local function EnsureLastActionFS(seatNum)
    if lastActionTexts[seatNum] then return lastActionTexts[seatNum] end
    local bar = seatProgressBars[seatNum]
    local parent = (bar and bar.GetParent and bar:GetParent()) or (seatMarkers[seatNum] and seatMarkers[seatNum].button) or TableFrame
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
    fs:SetTextColor(1, 1, 1, 1)
    fs:ClearAllPoints()
    fs:SetPoint("TOP", parent, "BOTTOM", 0, -2)
    fs:Hide()
    lastActionTexts[seatNum] = fs
    return fs
end

local function SetLastAction(seatNum, kind, amount)
    if not seatNum then return end
    local fs = EnsureLastActionFS(seatNum)
    local label = "Latest: "
    if kind == "FOLD" then
        fs:SetText(label .. "|cffff9999Fold|r")
    elseif kind == "CHECK" then
        fs:SetText(label .. "|cffffffffCheck|r")
    elseif kind == "CALL" then
        fs:SetText(label .. "|cffffffffCall " .. tostring(amount or 0) .. GOLD_ICON .. "|r")
    elseif kind == "RAISE" then
        fs:SetText(label .. "|cffffffffRaise " .. tostring(amount or 0) .. GOLD_ICON .. "|r")
    elseif kind == "ALL_IN" then
        fs:SetText(label .. "|cffb4dfffAll-In " .. tostring(amount or 0) .. GOLD_ICON .. "|r")
    else
        fs:SetText("")
    end
    fs:Show()
end

local function ClearAllLastActions()
    for i = 1, 9 do
        if lastActionTexts[i] then lastActionTexts[i]:Hide() end
    end
end

local function StopSeatTurnTimer(seatNum)
    if seatTurnTimers[seatNum] then
        seatTurnTimers[seatNum]:SetScript("OnUpdate", nil)
        seatProgressBars[seatNum]:SetValue(0)
        -- Leave the bar up so its faded background stays visible
        seatTurnEndTimes[seatNum] = nil
    end
end

local function StartSeatTurnTimer(seatNum, duration)
    if not seatProgressBars[seatNum] then return end
    duration = duration or PLAYER_TIMER_DURATION

    -- Stop any running timer
    if seatTurnTimers[seatNum] then
        seatTurnTimers[seatNum]:SetScript("OnUpdate", nil)
    end

    local bar = seatProgressBars[seatNum]
    bar:SetMinMaxValues(0, duration)
    bar:SetValue(duration)
    bar:Show()

    local startTime = GetTime()
    local endTime = startTime + duration
    seatTurnEndTimes[seatNum] = endTime

    -- Run the bar animation
    if not seatTurnTimers[seatNum] then seatTurnTimers[seatNum] = bar end
    bar:SetScript("OnUpdate", function(self)
        local now = GetTime()
        local remaining = math.max(0, endTime - now)
        self:SetValue(remaining)
        if remaining <= 0 then
            self:SetScript("OnUpdate", nil)
            self:SetValue(0)
            -- Auto-fold when it is the local player
            if playerSeat == seatNum and not hasPlayerFolded then
                print("|cff00cccc[Poker]|r |cffe32636[•]|r You took too long! Auto-folding your hand.")
                -- Same as pressing Fold
                local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
                Poker_SendAddonMessage("PokerTable", "FOLD:" .. myName, Poker_Channel())
                hasPlayerFolded = true
                if decisionBox then decisionBox:Hide() end
            end
        end
    end)
end

decisionBox.allInBtn:SetScript("OnClick", function()
    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    local bankroll = playerBankrolls[myName] or 0
    if bankroll <= 0 then return end
    if playerSeat then ShowSeatSpeechBubble(playerSeat, "All-In for " .. bankroll .. GOLD_ICON) end
    Poker_SendAddonMessage("PokerTable", "ALL_IN:" .. myName .. ":" .. bankroll, Poker_Channel())
    decisionBox:Hide()
end)



-- Amount every live (unfolded) player has matched
local function GetMatchedPot()
    -- Bets from every unfolded player
    local bets = {}
    for seatNum, name in pairs(occupiedSeats or playerSeats) do
        local isActive = true
        if seatMarkers and seatMarkers[seatNum] and not seatMarkers[seatNum].occupied then
            isActive = false
        end
        if isActive then
            table.insert(bets, playerBets[seatNum] or 0)
        end
    end
    if #bets == 0 then return 0 end

    -- Matched pot: the lowest bet plus whatever every player has also matched above it
    table.sort(bets)
    local matchedPot = 0
    local prev = 0
    for i = 1, #bets do
        local thisLevel = bets[i] - prev
        if thisLevel > 0 then
            matchedPot = matchedPot + thisLevel * (#bets - i + 1)
            prev = bets[i]
        end
    end
    return matchedPot
end

raiseSlider:SetValueStep(1)
raiseSlider:SetScript("OnValueChanged", function(self, value)
    local minVal, maxVal = self:GetMinMaxValues()
    local snapped = math.floor(value + 0.0001)
    if snapped < minVal then snapped = minVal end
    if snapped > maxVal then snapped = maxVal end
    if snapped ~= value then
        self:SetValue(snapped)
        return
    end

    local goldText = snapped .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t"
    raiseValueLabel:SetText(goldText)
    if betBtn:IsShown() then
        betBtn:SetText("Bet " .. goldText)
    end
    if raiseBtn:IsShown() then
        raiseBtn:SetText("Raise to " .. goldText)
    end

    -- Always copy the slider value into the box, even over a lower typed number
    if not _editChanging then
        _sliderChanging = true
        amountEdit:SetText(tostring(snapped))
        amountEdit:SetCursorPosition(#tostring(snapped))
        _sliderChanging = false
    end

    UpdateAllInLock()
    UpdatePercentButtons()
end)

-- == Set up the amount box when the decision box first shows ==============
decisionBox:HookScript("OnShow", function()
    local v = math.floor(decisionBox.raiseSlider:GetValue() + 0.0001)
    amountEdit:SetText(tostring(v))
    UpdatePercentButtons()
end)

-- Number of players still in the hand
function GetNumActivePlayers()
    local n = 0
    for seatNum, name in pairs(occupiedSeats or playerSeats) do
        local isActive = true
        if seatMarkers and seatMarkers[seatNum] and not seatMarkers[seatNum].occupied then
            isActive = false
        end
        if isActive then n = n + 1 end
    end
    return n
end

-- Button wiring
foldBtn:SetScript("OnClick", function()
    if playerSeat then ShowSeatSpeechBubble(playerSeat, "Fold..") end
    -- Dim this seat's cards to 25%
    if seatCardTextures[playerSeat] then
        for _, tex in pairs(seatCardTextures[playerSeat]) do
            tex:SetAlpha(0.25)
        end
    end
    -- Tell the other players
    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    Poker_SendAddonMessage("PokerTable", "FOLD:" .. myName, Poker_Channel())
    hasPlayerFolded = true
    decisionBox:Hide()
end)
callBtn:SetScript("OnClick", function()
    local maxBet = 0
    for _, bet in pairs(playerBets) do if bet > maxBet then maxBet = bet end end
    local myBet = playerBets[playerSeat] or 0
    local callAmount = maxBet - myBet
    if callAmount <= 0 then
        if playerSeat then ShowSeatSpeechBubble(playerSeat, "Check..") end
        local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
        Poker_SendAddonMessage("PokerTable", "CHECK:" .. myName, Poker_Channel())
        decisionBox:Hide()
        return
    end

    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    local bankroll = playerBankrolls[myName] or 0
    if bankroll < callAmount then
        if playerSeat and bankroll > 0 then
            ShowSeatSpeechBubble(playerSeat, "All-In for " .. bankroll .. GOLD_ICON)
        end
        -- Treat an invalid call as All-In instead
        if bankroll > 0 then
            Poker_SendAddonMessage("PokerTable", "ALL_IN:" .. myName .. ":" .. bankroll, Poker_Channel())
        end
        decisionBox:Hide()
        return
    end
    if playerSeat then ShowSeatSpeechBubble(playerSeat, "Call " .. callAmount .. GOLD_ICON) end

    Poker_SendAddonMessage("PokerTable", "CALL:" .. myName .. ":" .. callAmount, Poker_Channel())
    decisionBox:Hide()
end)

checkBtn:SetScript("OnClick", function()
    if playerSeat then ShowSeatSpeechBubble(playerSeat, "Check..") end
    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    Poker_SendAddonMessage("PokerTable", "CHECK:" .. myName, Poker_Channel())
    decisionBox:Hide()
end)

raiseBtn:SetScript("OnClick", function()
    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
    local bankroll = playerBankrolls[myName] or 0
    local requestedTo = math.floor(decisionBox.raiseSlider:GetValue() + 0.0001)

    local myBet = playerBets[playerSeat] or 0
    -- Table top bet before this action
    local preMax = 0
    for _, bet in pairs(playerBets) do if bet > preMax then preMax = bet end end

    local toCall = math.max(0, preMax - myBet)
    local minRaise = (lastRaiseAmount > 0) and lastRaiseAmount or BB
    local isBet = (preMax == 0)

    -- Apply the minimums
    local minTo = isBet and math.min(BB, bankroll) or (preMax + minRaise)
    local raiseTo = math.max(requestedTo, minTo)

    -- Cap by bankroll: toCall + raiseAmt cannot exceed it
    local raiseAmount = math.max(0, raiseTo - preMax)
    local totalPutIn = toCall + raiseAmount
    if totalPutIn > bankroll then
        -- Lower raiseTo so totalPutIn equals the bankroll
        local maxExtra = math.max(0, bankroll - toCall)
        raiseAmount = maxExtra
        raiseTo = preMax + raiseAmount
        totalPutIn = toCall + raiseAmount
    end

    -- Speech bubble, after clamping
    if playerSeat then
        local txt = isBet and ("Bet " .. raiseTo .. GOLD_ICON) or ("Raise to " .. raiseTo .. GOLD_ICON)
        ShowSeatSpeechBubble(playerSeat, txt)
    end

    -- Apply on this client
    playerBankrolls[myName] = bankroll - totalPutIn
    playerBets[playerSeat] = (playerBets[playerSeat] or 0) + totalPutIn
    ShowChipsAtSeat(playerSeat, playerBets[playerSeat])
    if seatBankrollTexts[playerSeat] then
        seatBankrollTexts[playerSeat]:SetText((playerBankrolls[myName] or 0) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
    end

    -- Update raise tracking for the next action
    if not isBet then
        lastRaiseAmount = raiseAmount
        lastBet = raiseTo
    else
        lastRaiseAmount = BB
        lastBet = raiseTo
    end

    -- Tell the dealer and players
    Poker_SendAddonMessage("PokerTable", "RAISE:" .. myName .. ":" .. raiseTo, Poker_Channel())
    decisionBox:Hide()
end)



-- Creates the player name text for a seat
local function CreatePlayerNameText(seatNumber, customName)
   if not seatNumber or not nameConfig.positions[seatNumber] or not seatMarkers[seatNumber] then
        return
    end
    local playerName = customName or (UnitName("player"):match("([^-]+)") or UnitName("player"))
    local config = nameConfig.positions[seatNumber]
    local seatButton = seatMarkers[seatNumber].button

    -- Remove this seat's old name text
    if seatNameTexts[seatNumber] then
        seatNameTexts[seatNumber]:Hide()
        seatNameTexts[seatNumber]:SetParent(nil)
        seatNameTexts[seatNumber] = nil
    end

    local nameText = seatButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetFont("Fonts\\FRIZQT__.TTF", nameConfig.fontSize, nameConfig.fontOutline)
    nameText:SetTextColor(nameConfig.color.r, nameConfig.color.g, nameConfig.color.b, nameConfig.color.a)
    nameText:SetText(playerName)
    nameText:SetJustifyH(config.align)
    nameText:SetPoint(config.align, seatButton, "CENTER", config.x, config.y)
    seatNameTexts[seatNumber] = nameText

    if seatBankrollTexts[seatNumber] then
        seatBankrollTexts[seatNumber]:Hide()
        seatBankrollTexts[seatNumber]:SetParent(nil)
        seatBankrollTexts[seatNumber] = nil
    end

    -- Player's bankroll, 0 if unknown
    local bankroll = playerBankrolls[playerName] or 0
    if pendingBankrollSets[playerName] then
        bankroll = pendingBankrollSets[playerName]
        playerBankrolls[playerName] = bankroll
        pendingBankrollSets[playerName] = nil
    end

    -- Build the new bankroll text
    local bankrollText = seatButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bankrollText:SetFont("Fonts\\FRIZQT__.TTF", nameConfig.fontSize, nameConfig.fontOutline)
    bankrollText:SetTextColor(1, 0.82, 0, 1)
    bankrollText:SetJustifyH(config.align)
    bankrollText:SetPoint(config.align, nameText, "CENTER", 0, -13)
    bankrollText:SetText((playerBankrolls[playerName] or 0) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
    seatBankrollTexts[seatNumber] = bankrollText

    playerBankrollTexts[playerName] = bankrollText
end

-- Dealer button spots on the client table; tune to the table art
local dealerButtonPositions = {
    [1] = {x = 178, y = 104},
    [2] = {x = 243, y = 55},
    [3] = {x = 245, y = -75},
    [4] = {x = 168, y = -129},
    [5] = {x = 4, y = -129},
    [6] = {x = -168, y = -129},
    [7] = {x = -245, y = -75},
    [8] = {x = -244, y = 48},
    [9] = {x = -178, y = 104},
}

local dealerButtonFrame = nil
local currentDealerSeat = nil

-- Animation path helper, same as the dealer side
local function GetDealerPath(fromSeat, toSeat)
    local path = {}
    local idx = fromSeat
    repeat
        table.insert(path, idx)
        idx = idx % 9 + 1
    until idx == toSeat
    table.insert(path, toSeat)
    return path
end

-- Slides the dealer button from seat to seat
local function AnimateDealerButton(fromSeat, toSeat)
    if not dealerButtonFrame then return end

    local path = GetDealerPath(fromSeat, toSeat)
    local step = 1
    local duration = 0.18 -- Seconds per seat
    local elapsed = 0

    local function moveToNext()
        if step >= #path then
            -- Land on the final spot
            local pos = dealerButtonPositions[path[#path]]
            dealerButtonFrame:SetPoint("CENTER", TableFrame, "CENTER", pos.x, pos.y)
            dealerButtonFrame:SetScript("OnUpdate", nil)
            currentDealerSeat = toSeat
            return
        end

        local startPos = dealerButtonPositions[path[step]]
        local endPos = dealerButtonPositions[path[step + 1]]
        elapsed = 0

        dealerButtonFrame:SetScript("OnUpdate", function(self, delta)
            elapsed = elapsed + delta
            local t = math.min(elapsed / duration, 1)
            local x = startPos.x + (endPos.x - startPos.x) * t
            local y = startPos.y + (endPos.y - startPos.y) * t
            self:SetPoint("CENTER", TableFrame, "CENTER", x, y)
            if t >= 1 then
                step = step + 1
                moveToNext()
            end
        end)
    end

    moveToNext()
end

-- Places the dealer button at a seat
local function SetDealerButton(seatNumber)
    if not dealerButtonPositions[seatNumber] then return end

    if not dealerButtonFrame then
        dealerButtonFrame = CreateFrame("Frame", nil, TableFrame)
        dealerButtonFrame:SetSize(32, 32)
        local dealerTexture = dealerButtonFrame:CreateTexture(nil, "OVERLAY")
        dealerTexture:SetAllPoints(dealerButtonFrame)
        dealerTexture:SetTexture(POKER_MEDIA .. "dealer_button.tga")
    end

    local pos = dealerButtonPositions[seatNumber]
    dealerButtonFrame:SetPoint("CENTER", TableFrame, "CENTER", pos.x, pos.y)
    dealerButtonFrame:Show()
    currentDealerSeat = seatNumber
end

-- Table SCALE button click
tableScaleBtn:SetScript("OnClick", function()
    -- Size now lives on the drag bar at the window's edge (PokerSizeBar.lua)
    tableVolumePopup:SetShown(not tableVolumePopup:IsShown())
end)

-- Join Table click: also adds your own portrait
joinTableBtn:SetScript("OnClick", function()
    -- Clear the leave flag on join
    hasLeftTable = false
    
    -- Tell everyone the player joined
    Poker_SendAddonMessage("PokerTable", "PLAYER_JOINED:" .. UnitName("player"), Poker_Channel())
    
    -- Hide the lobby
    RoleFrame:Hide()
    
    -- Show the table at its own saved size, centred
    ApplyTablePokerScale(tablePokerScale)
    TableFrame:Show()
end)

local function AwardPotToWinner(winnerSeat)
    -- Credit the pot to the winner's bankroll
    for i = 1, 9 do
        StopSeatTurnTimer(i)
    end
    -- Clear chips and amount boxes from every seat
    for seatNum = 1, 9 do
        if seatChipFrames[seatNum] then
            for _, chip in ipairs(seatChipFrames[seatNum]) do
                chip:Hide()
                chip:SetParent(nil)
            end
            seatChipFrames[seatNum] = {}
        end
        if seatChipFrames[seatNum] and seatChipFrames[seatNum].amountBox then
            seatChipFrames[seatNum].amountBox:Hide()
        end
    end
    -- Clear the centre pot stack
    HidePotStack()

    -- Force a local pot UI reset
    potValue = 0
    if potText then
        potText:SetText("Total Pot: 0 |T" .. POKER_MEDIA .. "1chip:16:16:0:0|t")
    end
end

local function AnimatePotCollection(callback)
    -- Collect chips from every seat
    local chipsToAnimate = {}
    for seatNum = 1, 9 do
        if seatChipFrames[seatNum] then
            for _, chip in ipairs(seatChipFrames[seatNum]) do
                chip:SetAlpha(1)
                chip:Show()
                table.insert(chipsToAnimate, chip)
            end
        end
    end

    -- Hide all amount boxes at once
    for seatNum = 1, 9 do
        if seatChipFrames[seatNum] and seatChipFrames[seatNum].amountBox then
            seatChipFrames[seatNum].amountBox:Hide()
        end
    end

    -- Record start points, relative to TableFrame centre
    local startPositions = {}
    for _, chip in ipairs(chipsToAnimate) do
        local point, relTo, relPoint, x, y = chip:GetPoint()
        -- Convert to TableFrame space if parented elsewhere
        if relTo ~= TableFrame then
            local wx, wy = chip:GetCenter()
            local fx, fy = TableFrame:GetCenter()
            x, y = wx - fx, wy - fy
        end
        startPositions[chip] = {x = x, y = y}
    end

    local duration = 0.7
    local elapsed = 0
    local targetY = 15 -- End point raised by 15px

    local function onUpdate(_, delta)
        elapsed = elapsed + delta
        local t = math.min(elapsed / duration, 1)
        for _, chip in ipairs(chipsToAnimate) do
            local sx, sy = startPositions[chip].x, startPositions[chip].y
            chip:SetPoint("CENTER", TableFrame, "CENTER", sx * (1-t), sy * (1-t) + targetY * t)
            chip:SetAlpha(1 - t * 0.5)
        end
        if t >= 1 then
            for _, chip in ipairs(chipsToAnimate) do
                chip:Hide()
                chip:SetParent(nil)
            end
            TableFrame:SetScript("OnUpdate", nil)
            ShowPotStack()
            if callback then callback() end
        end
    end
    TableFrame:SetScript("OnUpdate", onUpdate)
end

-- Split pot: every winner's share animates at the same time
local function AnimatePotSplitToWinners(winnerSeats, sharesBySeat, onDone)
    -- winnerSeats lists seat numbers; sharesBySeat[seatNum] is the amount
    -- Chip textures per winner, starting at the centre
    local fx, fy = TableFrame:GetCenter()
    local chipSize = 24
    local denomOrder = {1000, 500, 100, 25, 5, 1}
    local startRadius = 0 -- Start at the centre with a small offset per winner
    local chips = {}  -- Each: { tex, sx, sy, tx, ty }

    -- Target points in TableFrame space
    local targets = {}
    for _, seatNum in ipairs(winnerSeats) do
        local seatFrame = seatMarkers[seatNum] and seatMarkers[seatNum].button
        if seatFrame then
            local wx, wy = seatFrame:GetCenter()
            targets[seatNum] = { x = wx - fx, y = wy - fy }
        end
    end

    -- Slight angle per winner so chips do not stack exactly
    local angleStep = (math.pi * 2) / math.max(1, #winnerSeats)
    local function offsetForIndex(i)
        local ang = (i - 1) * angleStep
        return startRadius * math.cos(ang), startRadius * math.sin(ang)
    end

    -- Chip sprites per winner's share, by denomination
    for idx, seatNum in ipairs(winnerSeats) do
        local share = sharesBySeat[seatNum] or 0
        local target = targets[seatNum]
        if share > 0 and target then
            local amt = share
            local ox, oy = offsetForIndex(idx)
            for _, d in ipairs(denomOrder) do
                local count = math.floor(amt / d)
                for i = 1, count do
                    local tex = TableFrame:CreateTexture(nil, "OVERLAY")
                    tex:SetTexture(chipTextures[d])
                    tex:SetSize(chipSize, chipSize)
                    tex:SetPoint("CENTER", TableFrame, "CENTER", ox, oy)
                    tex:SetAlpha(1)
                    tex:Show()
                    table.insert(chips, {
                        tex = tex,
                        sx = ox, sy = oy,
                        tx = target.x, ty = target.y
                    })
                end
                amt = amt - count * d
                if amt <= 0 then break end
            end
        end
    end

    -- Animate every chip together
    local duration, elapsed = 0.7, 0
    TableFrame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        local t = math.min(elapsed / duration, 1)
        for _, c in ipairs(chips) do
            local x = c.sx + (c.tx - c.sx) * t
            local y = c.sy + (c.ty - c.sy) * t
            c.tex:SetPoint("CENTER", TableFrame, "CENTER", x, y)
            c.tex:SetAlpha(1 - t * 0.5)
        end
        if t >= 1 then
            for _, c in ipairs(chips) do
                c.tex:Hide()
                c.tex:SetParent(nil)
            end
            TableFrame:SetScript("OnUpdate", nil)
            -- Clear the centre pot stack and reset its text
            HidePotStack()
            potValue = 0
            if potText then
                potText:SetText("Total Pot: 0 |T" .. POKER_MEDIA .. "1chip:16:16:0:0|t")
            end
            if onDone then onDone() end
        end
    end)
end

local function HasAnySeatChips()
    for seatNum = 1, 9 do
        if seatChipFrames[seatNum] then
            for _, chip in ipairs(seatChipFrames[seatNum]) do
                if chip and chip:IsShown() then
                    return true
                end
            end
        end
    end
    return false
end

local roundAnimating = false
local function EndBettingRoundLocal()
    if roundAnimating then return end
    roundAnimating = true
    if decisionBox then decisionBox:Hide() end
    for i = 1, 9 do StopSeatTurnTimer(i) end
    AnimatePotCollection(function()
        roundAnimating = false
    end)
end
function ShowPotStack()
    -- Drop the previous pot stack
    if TableFrame.potStackChips then
        for _, chip in ipairs(TableFrame.potStackChips) do
            chip:Hide()
            chip:SetParent(nil)
        end
    end
    TableFrame.potStackChips = {}

    local pot = potValue or 0
    local chips = {}
    local tempPot = pot
    local backRowDenoms = {1000, 500, 100}
    local frontRowDenoms = {25, 5, 1}
    local chipDenoms = {1000, 500, 100, 25, 5, 1}
    -- Same chipTextures table as elsewhere

    -- Chip count per denomination
    local chipCounts = {}
    for _, denom in ipairs(chipDenoms) do
        chipCounts[denom] = math.floor(tempPot / denom)
        tempPot = tempPot - chipCounts[denom] * denom
    end

    local stackSpacing = 22
    local chipSize = 24
    local baseY = 50 -- Height above the pot text

    -- Back row, large chips
    local backX = 0
    local numBackStacks = 0
    for _, denom in ipairs(backRowDenoms) do
        local count = chipCounts[denom]
        if count > 0 then
            numBackStacks = numBackStacks + 1
            for i = 1, count do
                local chip = TableFrame:CreateTexture(nil, "OVERLAY")
                chip:SetTexture(chipTextures[denom])
                chip:SetSize(chipSize, chipSize)
                chip:SetPoint("CENTER", TableFrame, "CENTER", backX, baseY + (i-1)*3)
                chip:SetAlpha(1)
                chip:Show()
                table.insert(TableFrame.potStackChips, chip)
            end
            backX = backX + stackSpacing
        end
    end

    -- Front row, small chips, shifted half a chip sideways
    local frontX = (numBackStacks > 0) and (stackSpacing / 2) or 0
    for _, denom in ipairs(frontRowDenoms) do
        local count = chipCounts[denom]
        if count > 0 then
            for i = 1, count do
                local chip = TableFrame:CreateTexture(nil, "OVERLAY")
                chip:SetTexture(chipTextures[denom])
                chip:SetSize(chipSize, chipSize)
                chip:SetPoint("CENTER", TableFrame, "CENTER", frontX, baseY + (i-1)*3 - 10)
                chip:SetAlpha(1)
                chip:Show()
                table.insert(TableFrame.potStackChips, chip)
            end
            frontX = frontX + stackSpacing
        end
    end
end

function HidePotStack()
    if TableFrame.potStackChips then
        for _, chip in ipairs(TableFrame.potStackChips) do
            chip:Hide()
            chip:SetParent(nil)
        end
        TableFrame.potStackChips = nil
    end
end

local function AnimatePotToWinner(winnerSeat, onDone)
    -- Animate the existing centre stack when there is one
    local potChips = {}
    if TableFrame.potStackChips and #TableFrame.potStackChips > 0 then
        for _, chip in ipairs(TableFrame.potStackChips) do
            chip:SetAlpha(1)
            chip:Show()
            table.insert(potChips, chip)
        end
    else
        -- Otherwise build temporary chips from potValue at the centre
        local pot = potValue or 0
        if pot <= 0 then
            AwardPotToWinner(winnerSeat)
            if onDone then onDone() end
            return
        end
        local chips = {}
        local tempPot = pot
        for _, denom in ipairs(chipDenoms) do
            local count = math.floor(tempPot / denom)
            for i = 1, count do table.insert(chips, denom) end
            tempPot = tempPot - count * denom
        end
        for i, denom in ipairs(chips) do
            local chip = TableFrame:CreateTexture(nil, "OVERLAY")
            chip:SetTexture(chipTextures[denom])
            chip:SetSize(32, 32)
            chip:SetPoint("CENTER", TableFrame, "CENTER", 0, (i-1)*6)
            chip:SetAlpha(1)
            chip:Show()
            table.insert(potChips, chip)
        end
    end

    local seatFrame = seatMarkers[winnerSeat] and seatMarkers[winnerSeat].button
    if not seatFrame then
        for _, chip in ipairs(potChips) do chip:Hide() chip:SetParent(nil) end
        TableFrame.potStackChips = nil
        AwardPotToWinner(winnerSeat)
        if onDone then onDone() end
        return
    end

    -- Winner's target point, TableFrame space
    local wx, wy = seatFrame:GetCenter()
    local fx, fy = TableFrame:GetCenter()
    wx, wy = wx - fx, wy - fy

    -- Store start points in TableFrame space
    local startPositions = {}
    for i, chip in ipairs(potChips) do
        local point, relTo, relPoint, sx, sy = chip:GetPoint()
        if relTo ~= TableFrame then
            local cx, cy = chip:GetCenter()
            sx, sy = cx - fx, cy - fy
        end
        startPositions[i] = {x = sx or 0, y = sy or ((i-1)*6)}
    end

    local duration, elapsed = 0.7, 0
    local function onUpdate(_, delta)
        elapsed = elapsed + delta
        local t = math.min(elapsed / duration, 1)
        for i, chip in ipairs(potChips) do
            local sx, sy = startPositions[i].x, startPositions[i].y
            chip:SetPoint("CENTER", TableFrame, "CENTER", sx + (wx - sx) * t, sy + (wy - sy) * t)
            chip:SetAlpha(1 - t * 0.5)
        end
        if t >= 1 then
            for _, chip in ipairs(potChips) do
                chip:Hide()
                chip:SetParent(nil)
            end
            TableFrame.potStackChips = nil
            TableFrame:SetScript("OnUpdate", nil)
            AwardPotToWinner(winnerSeat)
            if onDone then onDone() end
        end
    end
    TableFrame:SetScript("OnUpdate", onUpdate)
end

local function AnimatePotWin(foldedSeatNum, winnerSeat)
    -- Hide both seats' amount boxes
    for _, seatNum in ipairs({foldedSeatNum, winnerSeat}) do
        if seatChipFrames[seatNum] and seatChipFrames[seatNum].amountBox then
            seatChipFrames[seatNum].amountBox:Hide()
        end
    end

    -- Chips fly from both seats to the centre and fade
    local chipsToAnimate = {}
    for _, seatNum in ipairs({foldedSeatNum, winnerSeat}) do
        if seatChipFrames[seatNum] then
            for _, chip in ipairs(seatChipFrames[seatNum]) do
                chip:SetAlpha(1)
                chip:Show()
                table.insert(chipsToAnimate, chip)
            end
        end
    end

    local duration = 0.7
    local elapsed = 0
    local startPositions = {}
    for _, chip in ipairs(chipsToAnimate) do
        local point, relTo, relPoint, x, y = chip:GetPoint()
        startPositions[chip] = {x = x, y = y}
    end

    local function onUpdate(_, delta)
        elapsed = elapsed + delta
        local t = math.min(elapsed / duration, 1)
        for _, chip in ipairs(chipsToAnimate) do
            local sx, sy = startPositions[chip].x, startPositions[chip].y
            local tx, ty = 0, 0 -- Relative to TableFrame centre
            chip:SetPoint("CENTER", TableFrame, "CENTER", sx + (tx - sx) * t, sy + (ty - sy) * t)
            chip:SetAlpha(1 - t)
        end
        if t >= 1 then
            -- Clear the chips
            for _, chip in ipairs(chipsToAnimate) do
                chip:Hide()
                chip:SetParent(nil)
            end
            TableFrame:SetScript("OnUpdate", nil)
            -- Spawn a pot chip at the centre
            AnimatePotToWinner(winnerSeat)
        end
    end
    TableFrame:SetScript("OnUpdate", onUpdate)
end

local function ShowDeckOrderPopup(deckOrderStr)
    if PokerDeckOrderPopup then
        PokerDeckOrderPopup:Hide()
        PokerDeckOrderPopup = nil
    end

    local popup = CreateFrame("Frame", "PokerDeckOrderPopup", UIParent, "DialogBoxFrame")
    popup:SetSize(520, 160)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", popup, "TOP", 0, -16)
    title:SetText("Deck Order")

    -- Deck order box: single line, no highlight
    local editBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    editBox:SetSize(480, 20)
    editBox:SetAutoFocus(false)
    editBox:SetPoint("TOP", title, "BOTTOM", 0, -10)
    editBox:SetText(deckOrderStr)
    editBox:SetCursorPosition(0)
    editBox:SetMaxLetters(1024)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    -- Link caption
    local linkLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    linkLabel:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -10)
    linkLabel:SetText("CRC Tool Link")

    local linkSubLabel = popup:CreateFontString(nil, "OVERLAY")
    linkSubLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    linkSubLabel:SetTextColor(1, 1, 1, 1) -- White
    linkSubLabel:SetPoint("LEFT", linkLabel, "RIGHT", 8, 0)
    linkSubLabel:SetText("(paste the deck order into 'Input' and verify the Shuffle ID matches)")

    -- Link box along the bottom
    local linkBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    linkBox:SetSize(480, 20)
    linkBox:SetAutoFocus(false)
    linkBox:SetPoint("TOPLEFT", linkLabel, "BOTTOMLEFT", 0, -2)
    linkBox:SetText("https://emn178.github.io/online-tools/crc/")
    linkBox:SetCursorPosition(0)
    linkBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)

    popup:Show()
end

local function ResetAllSeatCardsAndBoard()
    -- Hole cards per seat
    for seat = 1, 9 do
        if seatCardTextures[seat] then
            for _, tex in pairs(seatCardTextures[seat]) do
                tex:Hide()
                tex:SetParent(nil)
            end
            seatCardTextures[seat] = {}
        end
        seatCardCodes[seat] = {}         -- Must clear revealed face codes
        dealingCardCount[seat] = 0       -- Restart deal indexes at 0
    end
    -- Community cards
    ClearFlopCards()
    ClearTurnRiverCards()
    playerFlopIndex = 0
    turnCode, riverCode = nil, nil
    -- Local reveal counter
    myCardIndex = 0
end

-- Leave Seat button, bottom right corner
local leaveSeatBtn = CreateFrame("Button", nil, TableFrame, "GameMenuButtonTemplate")
leaveSeatBtn:SetSize(110, 28)
leaveSeatBtn:SetText("Leave Seat")
leaveSeatBtn:ClearAllPoints()
leaveSeatBtn:SetPoint("BOTTOMRIGHT", TableFrame, "BOTTOMRIGHT", -12, 12) -- Bottom right
leaveSeatBtn:Disable() -- Starts disabled

-- Sitting In / Sitting Out toggle with an animated slider
local TOGGLE_W, TOGGLE_H = 110, 28
local BORDER_EDGE = 12        -- Stronger border
local BORDER_INSET = 2

local sitToggle = CreateFrame("Button", nil, TableFrame, "BackdropTemplate")
sitToggle:SetSize(TOGGLE_W, TOGGLE_H)
sitToggle:SetPoint("BOTTOMRIGHT", leaveSeatBtn, "TOPRIGHT", 0, 1)
sitToggle:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = BORDER_EDGE,
    insets = { left = BORDER_INSET, right = BORDER_INSET, top = BORDER_INSET, bottom = BORDER_INSET }
})
sitToggle:SetBackdropColor(0.06, 0.06, 0.06, 0.90)
sitToggle:SetBackdropBorderColor(1, 1, 1, 0.9)

-- Area not covered by the knob; the label is centred in it
local labelRegion = CreateFrame("Frame", nil, sitToggle)
labelRegion:SetAllPoints(sitToggle)

-- Label, slightly larger font
local sitLabel = labelRegion:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sitLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
sitLabel:SetJustifyH("CENTER")
sitLabel:SetJustifyV("MIDDLE")
sitLabel:SetPoint("CENTER", labelRegion, "CENTER", 0, 0)
sitLabel:SetText("Sitting In")

-- Square knob, touching the inner border when idle
local knob = CreateFrame("Frame", nil, sitToggle, "BackdropTemplate")
local function SizeKnobToBar()
    local side = sitToggle:GetHeight() - 2 * BORDER_INSET
    knob:SetSize(side, side)
end
knob:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10, insets = { left = 1, right = 1, top = 1, bottom = 1 }
})
SizeKnobToBar()
knob:SetPoint("LEFT", sitToggle, "LEFT", BORDER_INSET, 0)

-- Toggle state and animation
local sitState = "IN" -- Either "IN" or "OUT"
local TOGGLE_FADE_OUT = 0.08
local TOGGLE_SLIDE_DUR = 0.12
local TOGGLE_FADE_IN  = 0.12
local sitToggleAnimating = false

local function EnsureLabelAnimGroups()
    -- Fade out: 1 to 0
    if not sitLabel._fadeOutAG then
        local ag = sitLabel:CreateAnimationGroup()
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1); a:SetToAlpha(0); a:SetDuration(TOGGLE_FADE_OUT); a:SetOrder(1)
        sitLabel._fadeOutAG = ag
    end
    -- Fade in: 0 to 1
    if not sitLabel._fadeInAG then
        local ag = sitLabel:CreateAnimationGroup()
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(TOGGLE_FADE_IN); a:SetOrder(1)
        -- Pin alpha to 1 at the end
        ag:SetScript("OnFinished", function() sitLabel:SetAlpha(1) end)
        sitLabel._fadeInAG = ag
    end
end

-- Lays out the label area so the text centres in the free space
local function UpdateSitLabelLayout()
    local w = sitToggle:GetWidth()
    local h = sitToggle:GetHeight()
    local kW = knob:GetWidth()
    -- Free space is on the side away from the knob
    labelRegion:ClearAllPoints()
    if sitState == "IN" then
        -- Knob left, label on the right
        labelRegion:SetPoint("TOPLEFT", sitToggle, "TOPLEFT", BORDER_INSET + kW, -BORDER_INSET)
        labelRegion:SetPoint("BOTTOMRIGHT", sitToggle, "BOTTOMRIGHT", -BORDER_INSET, BORDER_INSET)
    else
        -- Knob right, label on the left
        labelRegion:SetPoint("TOPLEFT", sitToggle, "TOPLEFT", BORDER_INSET, -BORDER_INSET)
        labelRegion:SetPoint("BOTTOMRIGHT", sitToggle, "BOTTOMRIGHT", -BORDER_INSET - kW, BORDER_INSET)
    end
    sitLabel:ClearAllPoints()
    sitLabel:SetPoint("CENTER", labelRegion, "CENTER", 0, 0)
end

local function SetSitState(state, animated)
    sitState = state
    local toRight = (state == "OUT")
    EnsureLabelAnimGroups()

    -- Stop running animations and default to fully visible
    sitToggle:SetScript("OnUpdate", nil)
    if sitLabel._fadeOutAG:IsPlaying() then sitLabel._fadeOutAG:Stop() end
    if sitLabel._fadeInAG:IsPlaying()  then sitLabel._fadeInAG:Stop()  end
    sitLabel:SetAlpha(1)
    sitToggleAnimating = false

    -- Size the knob to meet the border
    SizeKnobToBar()

    -- Work out slide targets
    local leftX  = BORDER_INSET
    local rightX = sitToggle:GetWidth() - knob:GetWidth() - BORDER_INSET
    local targetX = toRight and rightX or leftX

    -- Applies end-state colours and text
    local function ApplyEndVisuals()
        if state == "OUT" then
            sitLabel:SetText("Sitting Out")
            sitLabel:SetTextColor(1.0, 0.6, 0.6, 1)       -- Light red text
            sitToggle:SetBackdropColor(0.10, 0.05, 0.05, 0.92)
            knob:SetBackdropColor(1.0, 0.6, 0.6, 1.0)     -- Light red knob
            knob:SetBackdropBorderColor(0.25, 0.08, 0.08, 1)
        else
            sitLabel:SetText("Sitting In")
            sitLabel:SetTextColor(0.6, 1.0, 0.6, 1)       -- Light green text
            sitToggle:SetBackdropColor(0.05, 0.10, 0.05, 0.92)
            knob:SetBackdropColor(0.6, 1.0, 0.6, 1.0)     -- Light green knob
            knob:SetBackdropBorderColor(0.08, 0.25, 0.08, 1)
        end
        UpdateSitLabelLayout()
    end

    -- Instant change: move the knob, update visuals, keep the label visible
    if not animated then
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", sitToggle, "LEFT", targetX, 0)
        ApplyEndVisuals()
        sitLabel:SetAlpha(1)           -- Always visible when idle
        sitToggleAnimating = false
        return
    end

    -- Animated change: fade the label out, slide the knob, then update text,
    -- colours and layout and fade the label back in
    sitToggleAnimating = true

    -- Re-attach the fade-out callback every call to be safe
    sitLabel._fadeOutAG:SetScript("OnFinished", function()
        -- Slide the knob
        local startX = select(4, knob:GetPoint()) or leftX
        local delta = targetX - startX
        local dur, t = TOGGLE_SLIDE_DUR, 0

        sitToggle:SetScript("OnUpdate", function(self, dt)
            t = t + dt
            local k = math.min(t / dur, 1)
            local x = startX + delta * k
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", sitToggle, "LEFT", x, 0)
            if k >= 1 then
                -- Knob has arrived
                self:SetScript("OnUpdate", nil)
                -- Apply the new state's visuals
                ApplyEndVisuals()
                -- Bring the label back
                sitLabel:SetAlpha(0)
                if sitLabel._fadeInAG:IsPlaying() then sitLabel._fadeInAG:Stop() end
                sitLabel._fadeInAG:Play()
                sitToggleAnimating = false
            end
        end)
    end)

    -- Start the fade out from full alpha
    sitLabel:SetAlpha(1)
    if sitLabel._fadeOutAG:IsPlaying() then sitLabel._fadeOutAG:Stop() end
    sitLabel._fadeOutAG:Play()
end

-- First layout
SetSitState("IN", false)
UpdateSitLabelLayout()

-- Handle the rare size change
sitToggle:HookScript("OnSizeChanged", function()
    SizeKnobToBar()
    UpdateSitLabelLayout()
end)

-- Disabled: click handler that toggled Sitting In / Out and told the dealer
-- (feature marked coming soon; original code kept in backup_v1.0.7)

-- Hover tooltip
sitToggle:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText("Toggle Sitting In / Sitting Out", 1, 1, 1)
    -- Disabled: hint line, replaced by COMING SOON below
    GameTooltip:AddLine("COMING SOON!", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
sitToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- == Showdown popup (client view) =========================================
local P_SDPFrame, P_SDPCards, P_SDPFadeTimer, P_SDPAutoHide

local function Poker_HideShowdownPopup()
    if P_SDPFadeTimer then P_SDPFadeTimer:Cancel() P_SDPFadeTimer = nil end
    if P_SDPAutoHide then P_SDPAutoHide:Cancel() P_SDPAutoHide = nil end
    if P_SDPCards then
        for _, tex in ipairs(P_SDPCards) do tex:Hide() tex:SetParent(nil) end
    end
    P_SDPCards = {}
    if P_SDPFrame then P_SDPFrame:Hide() end
end

Poker_ShowShowdownPopup = function(winnerName, payout, handNameStr, codes)
    if not P_SDPFrame then
        P_SDPFrame = CreateFrame("Frame", "PokerShowdownPopup", UIParent, "BackdropTemplate")
        P_SDPFrame:SetSize(270, 92)
        P_SDPFrame:SetPoint("TOP", TableFrame, "TOP", 0, -30)
        P_SDPFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left=4, right=4, top=4, bottom=4 }
        })
        P_SDPFrame:SetBackdropColor(0,0,0,0.92)
        P_SDPFrame.title = P_SDPFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        P_SDPFrame.title:SetPoint("TOP", P_SDPFrame, "TOP", 0, -10)
        P_SDPFrame.title:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    else
        if P_SDPFrame:GetParent() ~= UIParent then
            P_SDPFrame:SetParent(UIParent)
            P_SDPFrame:ClearAllPoints()
            P_SDPFrame:SetPoint("TOP", TableFrame, "TOP", 0, -30)
        end
    end

    P_SDPFrame:SetToplevel(true)
    P_SDPFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    P_SDPFrame:SetFrameLevel(10000)

    Poker_HideShowdownPopup()
    P_SDPFrame:Show()
    P_SDPFrame:Raise()
    P_SDPCards = {}

    local nameC  = "|cff87ceeb" .. (winnerName or "Winner") .. "|r"
    local amtC   = "|cffffff00" .. (payout or 0) .. "|r |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t"
    local handC  = "|cffffcc00" .. (handNameStr or "Hand") .. "|r"
    local white  = "|cffffffff"
    P_SDPFrame.title:SetText(
        nameC .. white .. " won the pot of|r\n" ..
        amtC .. white .. " with a " .. handC .. "!|r"
    )

    local cardW, cardH, gap = 32, 64, 3
    local count = #codes
    local totalW = (count > 0) and (count * cardW + (count - 1) * gap) or 0
    local startX = -totalW / 2 + cardW / 2
    for i, code in ipairs(codes) do
        local tex = P_SDPFrame:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(POKER_MEDIA .. code .. ".tga")
        tex:SetSize(cardW, cardH)
        tex:SetPoint("TOP", P_SDPFrame, "TOP", startX + (i - 1) * (cardW + gap), -29)
        tex:Show()
        table.insert(P_SDPCards, tex)
    end

    -- Fade out after 7s, over about 2s
    P_SDPAutoHide = C_Timer.NewTimer(7, function()
        local duration, elapsed = 2.0, 0
        P_SDPFrame:SetAlpha(1)
        P_SDPFrame:SetScript("OnUpdate", function(self, delta)
            elapsed = elapsed + delta
            local t = math.min(elapsed / duration, 1)
            self:SetAlpha(1 - t)
            if t >= 1 then
                self:SetScript("OnUpdate", nil)
                Poker_HideShowdownPopup()
                P_SDPFrame:SetAlpha(1)
            end
        end)
    end)
end

-- Register the prefix used by dealer messages
C_ChatInfo.RegisterAddonMessagePrefix("PokerTable")

-- Listen for addon messages
RoleFrame:RegisterEvent("CHAT_MSG_ADDON")
TableFrame:RegisterEvent("CHAT_MSG_ADDON") -- TableFrame receives addon messages too
TableFrame:RegisterEvent("CHAT_MSG_SYSTEM")
TableFrame:RegisterEvent("CHAT_MSG_WHISPER")

-- Invite group members when a table opens: once per table, never the host,
-- and held until combat ends. Own frame, as Blizzard popups taint
local autoOpenedBy, invitePending
local invite = CreateFrame("Frame", "PokerInviteFrame", UIParent, "BasicFrameTemplateWithInset")
invite:SetSize(300, 110)
invite:SetPoint("TOP", UIParent, "TOP", 0, -160)
invite:SetFrameStrata("DIALOG")
invite:Hide()
if invite.TitleText then invite.TitleText:SetText("Bounty Hold'em") end
invite.text = invite:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
invite.text:SetPoint("TOP", invite, "TOP", 0, -34)
invite.text:SetWidth(270)
local inviteYes = CreateFrame("Button", nil, invite, "UIPanelButtonTemplate")
inviteYes:SetSize(100, 24)
inviteYes:SetPoint("BOTTOMRIGHT", invite, "BOTTOM", -6, 12)
inviteYes:SetText("Yes")
local inviteNo = CreateFrame("Button", nil, invite, "UIPanelButtonTemplate")
inviteNo:SetSize(100, 24)
inviteNo:SetPoint("BOTTOMLEFT", invite, "BOTTOM", 6, 12)
inviteNo:SetText("No")
inviteNo:SetScript("OnClick", function() invite:Hide() end)
inviteYes:SetScript("OnClick", function()
    invite:Hide()
    if playerSeat then return end
    -- Join straight away when the table is open, else just show the lobby
    if joinTableBtn:IsEnabled() then
        joinTableBtn:Click()
    elseif not RoleFrame:IsShown() then
        SlashCmdList["POKER"]("")
    end
end)
-- Close the invite on its own after a minute
invite:SetScript("OnShow", function(self) self.shownAt = GetTime() end)
invite:SetScript("OnUpdate", function(self)
    if GetTime() - (self.shownAt or 0) > 60 then self:Hide() end
end)

local function ShowInvite(host)
    if playerSeat or TableFrame:IsShown() then return end
    if UnitAffectingCombat("player") then
        invitePending = host
        return
    end
    invitePending = nil
    invite.text:SetText("|cffda70d6" .. host .. "|r has started a poker table.\nDo you want to join?")
    invite:Show()
    PlaySoundFile(POKER_MEDIA .. "chips.MP3", "SFX")
end
local inviteWatcher = CreateFrame("Frame")
inviteWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
inviteWatcher:SetScript("OnEvent", function()
    if invitePending then ShowInvite(invitePending) end
end)

-- Handles dealer messages and player joins
RoleFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        -- Only poker table messages
        if prefix == "PokerTable" then
            if message == "TABLE_OPENED" then
                -- Enable Join Table
                joinTableBtn:Enable()
                local playerName = sender:match("([^-]+)") or sender
                print("|cff00cccc[Poker]|r A table has been opened by |cffda70d6" .. playerName .. "|r - you can now join.")
                -- Request a fresh snapshot so seats fill straight away
                Poker_SendAddonMessage("PokerTable", "REQUEST_SNAPSHOT", Poker_Channel())
                if PokerNet.ShortName(sender) ~= PokerNet.MyName() and autoOpenedBy ~= playerName then
                    autoOpenedBy = playerName
                    ShowInvite(playerName)
                end
                return
                
            elseif message == "TABLE_CLOSED" then
                -- Disable Join Table and hide the table
                joinTableBtn:Disable()
                TableFrame:Hide()
                autoOpenedBy, invitePending = nil, nil
                invite:Hide()
                local dealerName = sender:match("([^-]+)") or sender
                print("|cff00cccc[Poker]|r The table has been closed by |cffda70d6" .. dealerName .. "|r.")
            elseif message:match("^PLAYER_JOINED:") then
                -- Player name from the message
                local playerName = message:match("^PLAYER_JOINED:(.+)")
            elseif message:match("^PLAYER_LEFT:") then
                -- Player name from the message; the reason is not shown
                local playerName = message:match("^PLAYER_LEFT:([^:]+)")
                if playerName then
                    -- Leave notice: teal [Poker] tag, pale red text, same for everyone
                    print("|cff00cccc[Poker]|r |cffff9999" .. playerName .. " has left the table.|r")
                end
            elseif message:match("^DEALER_ASSIGNED:") then
                local playerName, seatNum = message:match("^DEALER_ASSIGNED:([^:]+):(%d+)")
                seatNum = tonumber(seatNum)
                if seatNum and dealerButtonPositions[seatNum] then
                    -- Chat line
                    local dealerName = sender:match("([^-]+)") or sender
                    local seatPlayerColor = "|cff87ceeb" .. playerName .. "|r" -- Light blue
                    local dealerColor = "|cffda70d6" .. dealerName .. "|r" -- Purple
                    print("|cff00cccc[Poker]|r " .. dealerColor .. " has assigned Seat " .. seatNum .. " (" .. seatPlayerColor .. ") as the Dealer.")

                    -- Place or animate the dealer button
                    if currentDealerSeat and currentDealerSeat ~= seatNum then
                        AnimateDealerButton(currentDealerSeat, seatNum)
                    else
                        SetDealerButton(seatNum)
                    end
                    currentDealerSeat = seatNum

                    -- Refresh blinds and portrait borders
                    UpdateBlinds(seatNum)
                end
            end
        end
    end
end)

local __U = {
    -- Frames
    TableFrame           = TableFrame,
    decisionBox          = decisionBox,
    joinTableBtn         = joinTableBtn,
    roleScaleBtn         = roleScaleBtn,
    RoleFrame            = RoleFrame,
    ApplyPokerScale      = ApplyPokerScale,
    ApplyTablePokerScale = ApplyTablePokerScale,
    roleBackground       = roleBackground,
    potText              = potText,

    -- Seat and board state tables (references stay stable)
    seatMarkers          = seatMarkers,
    occupiedSeats        = occupiedSeats,
    seatNameTexts        = seatNameTexts,
    seatBankrollTexts    = seatBankrollTexts,
    seatPortraitFrames   = seatPortraitFrames,
    seatCardTextures     = seatCardTextures,
    seatCardCodes        = seatCardCodes,
    seatTurnTimers       = seatTurnTimers,
    seatTurnEndTimes     = seatTurnEndTimes,
    seatProgressBars     = seatProgressBars,
    seatChipFrames       = seatChipFrames,
    playerBets           = playerBets,
    playerBankrolls      = playerBankrolls,

    flopCardTextures     = flopCardTextures,
    flopCodes            = flopCodes,
    -- turnCardTexture, riverCardTexture, turnCode and riverCode are left out on
    -- purpose: they get reassigned, so the outer locals are used instead

    -- Layout values the handlers need
    dealerButtonPositions = dealerButtonPositions,

    -- Helper functions (references stay stable)
    CreatePlayerPortrait  = CreatePlayerPortrait,
    CreatePlayerNameText  = CreatePlayerNameText,
    UpdateBlinds          = UpdateBlinds,

    ShowCardAboveSeat     = ShowCardAboveSeat,
    ShowFlopCard          = ShowFlopCard,
    ClearFlopCards        = ClearFlopCards,
    ClearTurnRiverCards   = ClearTurnRiverCards,
    ShowTurnCard          = ShowTurnCard,
    ShowRiverCard         = ShowRiverCard,

    ResetAllCardOpacity   = ResetAllCardOpacity,
    ApplyWinningHighlight = ApplyWinningHighlight,

    AnimateDealerButton   = AnimateDealerButton,
    SetDealerButton       = SetDealerButton,

    StopSeatTurnTimer     = StopSeatTurnTimer,
    StartSeatTurnTimer    = StartSeatTurnTimer,

    ShowChipsAtSeat       = ShowChipsAtSeat,
    HidePotStack          = HidePotStack,
    ShowPotStack          = ShowPotStack,
    AnimatePotCollection  = AnimatePotCollection,
    AnimatePotToWinner    = AnimatePotToWinner,
    HasAnySeatChips       = HasAnySeatChips,

    ShowDeckOrderPopup    = ShowDeckOrderPopup,
}
PokerUI = __U -- Exposed so PokerHUD can move the action bar into the dock

if not Poker_HandleAddonMessage_PlayerSide then
    local function PokerInternal_HandlePokerMessage(msg)
        if not msg or msg == "" then return end

        -- Format: POT_WINNER:winner:payout:rake:shuffleID:handID
        if msg:find("^POT_WINNER:") then
            local winner, payout, rake, sid, hid =
                msg:match("^POT_WINNER:([^:]+):(%d+):(%d+):([^:]*):([^:]*)")
            payout = tonumber(payout)
            if sid and sid ~= "" then _PR_HAND_TRACK.currentShuffleID = sid end
            if hid and hid ~= "" then _PR_HAND_TRACK.currentHandID    = hid end
            local hidKey = (_PR_HAND_TRACK.currentHandID or "unknown") .. ":" .. (winner or "")
            if winner and payout and not _PR_HAND_TRACK.winnerApplied[hidKey] then
                local old = playerBankrolls[winner] or 0
                playerBankrolls[winner] = old + payout
                Poker_UpdateSeatBankrollText(winner, playerBankrolls[winner])
                _PR_HAND_TRACK.winnerApplied[hidKey] = true
            end
            Poker_RequestSnapshotAfterDelay()
            return
        end

        -- Format: POT_SPLIT:name1,name2,...:totalPayout:rake:shuffleID:handID
        if msg:find("^POT_SPLIT:") then
            local namesCSV, totalP, rakeAmt, sid2, hid2 =
                msg:match("^POT_SPLIT:([^:]+):(%d+):(%d+):([^:]*):([^:]*)")
            if sid2 and sid2 ~= "" then _PR_HAND_TRACK.currentShuffleID = sid2 end
            if hid2 and hid2 ~= "" then _PR_HAND_TRACK.currentHandID    = hid2 end
            -- No provisional credit on a split; wait for BANKROLL_SET or BANKROLL_BULK
            Poker_RequestSnapshotAfterDelay()
            return
        end

        -- Format: BANKROLL_SET:Player:Amount
        if msg:find("^BANKROLL_SET:") then
            local n, a = msg:match("^BANKROLL_SET:([^:]+):(%d+)")
            Poker_ApplyBankrollAuthoritative(n, a)
            return
        end

        -- Format: BANKROLL_BULK:name=amt;name=amt;...
        if msg:find("^BANKROLL_BULK:") then
            local payload = msg:sub(#"BANKROLL_BULK:" + 1)
            for pair in payload:gmatch("([^;]+)") do
                local n, a = pair:match("^([^=]+)=(%d+)$")
                if n and a then
                    Poker_ApplyBankrollAuthoritative(n, a)
                end
            end
            return
        end

        -- Format: SHUFFLE:shuffleID:handID (captured if present)
        if msg:find("^SHUFFLE:") then
            local sid3, hid3 = msg:match("^SHUFFLE:([^:]+):([^:]+)")
            if sid3 and sid3 ~= "" then _PR_HAND_TRACK.currentShuffleID = sid3 end
            if hid3 and hid3 ~= "" then _PR_HAND_TRACK.currentHandID    = hid3 end
            return
        end
    end

    function Poker_HandleAddonMessage_PlayerSide(prefix, msg)
        if prefix ~= "PokerTable" then return end
        PokerInternal_HandlePokerMessage(msg)
    end
end

-- == Table frame event handler ============================================
TableFrame:SetScript("OnEvent", function(self, event, ...)
    -- Heavy references pulled from one upvalue into locals to stay under Lua's 60-upvalue limit
    local U = __U
    local TableFrame, decisionBox, potText =
        U.TableFrame, U.decisionBox, U.potText
    local seatMarkers, occupiedSeats, seatNameTexts, seatBankrollTexts, seatPortraitFrames =
        U.seatMarkers, U.occupiedSeats, U.seatNameTexts, U.seatBankrollTexts, U.seatPortraitFrames
    local seatCardTextures, seatCardCodes, seatTurnTimers, seatTurnEndTimes, seatProgressBars, seatChipFrames =
        U.seatCardTextures, U.seatCardCodes, U.seatTurnTimers, U.seatTurnEndTimes, U.seatProgressBars, U.seatChipFrames
    local playerBets, playerBankrolls =
        U.playerBets, U.playerBankrolls
    local flopCardTextures, flopCodes =
        U.flopCardTextures, U.flopCodes
    local dealerButtonPositions =
        U.dealerButtonPositions

    -- Helpers
    local CreatePlayerPortrait, CreatePlayerNameText, UpdateBlinds =
        U.CreatePlayerPortrait, U.CreatePlayerNameText, U.UpdateBlinds
    local ShowCardAboveSeat, ShowFlopCard, ClearFlopCards, ClearTurnRiverCards, ShowTurnCard, ShowRiverCard =
        U.ShowCardAboveSeat, U.ShowFlopCard, U.ClearFlopCards, U.ClearTurnRiverCards, U.ShowTurnCard, U.ShowRiverCard
    local ResetAllCardOpacity, ApplyWinningHighlight =
        U.ResetAllCardOpacity, U.ApplyWinningHighlight
    local AnimateDealerButton, SetDealerButton =
        U.AnimateDealerButton, U.SetDealerButton
    local StopSeatTurnTimer, StartSeatTurnTimer =
        U.StopSeatTurnTimer, U.StartSeatTurnTimer
    local ShowChipsAtSeat, HidePotStack, ShowPotStack, AnimatePotCollection, AnimatePotToWinner, HasAnySeatChips =
        U.ShowChipsAtSeat, U.HidePotStack, U.ShowPotStack, U.AnimatePotCollection, U.AnimatePotToWinner, U.HasAnySeatChips
    local ShowDeckOrderPopup =
        U.ShowDeckOrderPopup
        
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if Poker_HandleAddonMessage_PlayerSide then
            Poker_HandleAddonMessage_PlayerSide(prefix, message)
        end

        if prefix == "PokerTable" then
            if message == "HAND_START" then
                if leaveSeatBtn then leaveSeatBtn:Disable() end
                return
            elseif message:match("^PLAYER_JOINED:") then
                local playerName = message:match("^PLAYER_JOINED:(.+)")
                if playerName then
                    playerName = playerName:match("([^-]+)") or playerName
                    print("|cff00cccc[Poker]|r |cff90ee90" .. playerName .. " has joined the table.|r")
                end
            elseif message:match("^PLAYER_LEFT:") then
                local playerName = message:match("^PLAYER_LEFT:([^:]+)")
                if playerName then
                    playerName = playerName:match("([^-]+)") or playerName
                end
            -- Player takes a seat
            elseif message:match("^PLAYER_SAT_DOWN:") then
                local playerName, seatNum = message:match("^PLAYER_SAT_DOWN:([^:]+):(%d+)")
                seatNum = tonumber(seatNum)
                if playerName and seatNum then
                    occupiedSeats[seatNum] = playerName
                    seatMarkers[seatNum].occupied = true
                    local unitID = GetUnitIDByName(playerName)
                    CreatePlayerPortrait(seatNum, playerName, unitID)
                    CreatePlayerNameText(seatNum, playerName)
                    print("|cff00cccc[Poker]|r |cff90ee90" .. playerName .. " has sat down in Seat " .. seatNum .. ".|r")
                end
            -- Player leaves a seat
            elseif message:match("^PLAYER_LEFT_SEAT:") then
                local playerName, seatNum = message:match("^PLAYER_LEFT_SEAT:([^:]+):(%d+)")
                seatNum = tonumber(seatNum)
                if seatNum then
                    occupiedSeats[seatNum] = nil
                    seatMarkers[seatNum].occupied = false

                    -- Remove only this seat's portrait
                    if seatPortraitFrames[seatNum] then
                        seatPortraitFrames[seatNum]:Hide()
                        seatPortraitFrames[seatNum]:SetParent(nil)
                        seatPortraitFrames[seatNum]:ClearAllPoints()
                        seatPortraitFrames[seatNum] = nil
                    end

                    -- Remove only this seat's name text
                    if seatNameTexts[seatNum] then
                        seatNameTexts[seatNum]:Hide()
                        seatNameTexts[seatNum]:SetParent(nil)
                        seatNameTexts[seatNum] = nil
                    end

                    -- Remove only this seat's bankroll text
                    if seatBankrollTexts[seatNum] then
                        seatBankrollTexts[seatNum]:Hide()
                        seatBankrollTexts[seatNum]:SetParent(nil)
                        seatBankrollTexts[seatNum] = nil
                    end
                    if lastActionTexts[seatNum] then lastActionTexts[seatNum]:Hide() end
                    print("|cff00cccc[Poker]|r |cffff9999" .. playerName .. " has left Seat " .. seatNum .. ".|r")
                    UpdateBlinds(currentDealerSeat)
                end
            elseif message:match("^KICK_PLAYER:") then
                local target, seatStr = message:match("^KICK_PLAYER:([^:]+):(%d+)")
                local myShort = UnitName("player"):match("([^-]+)") or UnitName("player")
                if target and target == myShort then
                    local dealer = sender:match("([^-]+)") or sender
                    print("|cff00cccc[Poker]|r You have been removed from your seat by |cffda70d6" .. dealer .. "|r.")
                    if type(LeaveSeat) == "function" then
                        LeaveSeat()
                    else
                        -- Fallback only; unused once LeaveSeat is global
                        if playerSeat then
                            if seatMarkers[playerSeat] then
                                seatMarkers[playerSeat].occupied = false
                            end
                            occupiedSeats[playerSeat] = nil
                            playerSeat = nil
                            if leaveSeatBtn then leaveSeatBtn:Disable() end
                        end
                    end
                end
                return
            elseif message:match("^SEAT_STATE:") then
                -- SEAT_STATE formats:
                --   Empty seat:  SEAT_STATE:<seat>:EMPTY
                --   Taken seat:  SEAT_STATE:<seat>:OCCUPIED:<name>:<bankroll>
                local seat, status, rest = message:match("^SEAT_STATE:(%d+):(%u+):?(.*)$")
                local seatNum = tonumber(seat)
                if not seatNum then return end

                if status == "EMPTY" then
                    -- Flag as empty
                    occupiedSeats[seatNum] = nil
                    if seatMarkers[seatNum] then seatMarkers[seatNum].occupied = false end
                    -- Remove the portrait
                    if seatPortraitFrames[seatNum] then
                        seatPortraitFrames[seatNum]:Hide()
                        seatPortraitFrames[seatNum]:SetParent(nil)
                        seatPortraitFrames[seatNum] = nil
                    end
                    -- Remove name and bankroll text
                    if seatNameTexts[seatNum] then
                        seatNameTexts[seatNum]:Hide()
                        seatNameTexts[seatNum]:SetParent(nil)
                        seatNameTexts[seatNum] = nil
                    end
                    if seatBankrollTexts[seatNum] then
                        seatBankrollTexts[seatNum]:Hide()
                        seatBankrollTexts[seatNum]:SetParent(nil)
                        seatBankrollTexts[seatNum] = nil
                    end

                elseif status == "OCCUPIED" then
                    local name, amountStr = rest:match("^([^:]+):(%d+)$")
                    local bankroll = tonumber(amountStr) or 0
                    if not name or name == "" then return end
                

                    -- Record occupancy and bankroll
                    occupiedSeats[seatNum] = name
                    if seatMarkers[seatNum] then seatMarkers[seatNum].occupied = true end
                    playerBankrolls[name] = bankroll

                    -- Draw portrait and text
                    local unitID = GetUnitIDByName(name)
                    CreatePlayerPortrait(seatNum, name, unitID)
                    CreatePlayerNameText(seatNum, name)
                    -- Set bankroll text to the snapshot value exactly
                    if seatBankrollTexts[seatNum] then
                        seatBankrollTexts[seatNum]:SetText(bankroll .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
                    end
                end

                -- Refresh the blinds overlay if the dealer is known
                if currentDealerSeat then
                    UpdateBlinds(currentDealerSeat)
                end
                return

            elseif message:match("^BLINDS_ASSIGN:") then
                local dSeat, sbSeatNum, bbSeatNum, dName, sbName, bbName =
                    message:match("^BLINDS_ASSIGN:(%d+):(%d+):(%d+):([^:]*):([^:]*):([^:]*)")
                dSeat = tonumber(dSeat)
                sbSeatNum = tonumber(sbSeatNum)
                bbSeatNum = tonumber(bbSeatNum)
                -- Place the dealer button and refresh the blinds overlay
                if dSeat then
                    if currentDealerSeat and currentDealerSeat ~= dSeat then
                        AnimateDealerButton(currentDealerSeat, dSeat)
                    else
                        SetDealerButton(dSeat)
                    end
                    currentDealerSeat = dSeat
                    UpdateBlinds(dSeat)      -- Sets SB/BB textures and the global bbSeat
                    bbSeat = bbSeatNum or bbSeat
                end
                -- SEAT_STATE has already built any missing portraits for these seats
                return

            -- == BANKROLL_ADD =============================================
            elseif message:match("^BANKROLL_ADD:") then
                local targetName, amount = message:match("^BANKROLL_ADD:([^:]+):(%d+)")
                amount = tonumber(amount)
                if targetName and amount then
                    playerBankrolls[targetName] = (playerBankrolls[targetName] or 0) + amount
                    -- Only update seated players
                    for seatNum, name in pairs(occupiedSeats) do
                        if name == targetName and seatMarkers[seatNum] then
                            seatMarkers[seatNum].occupied = true
                            CreatePlayerNameText(seatNum, targetName)
                        end
                    end
                    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
                    local dealerName = sender:match("([^-]+)") or sender
                    if targetName == myName then
                        print("|cff00cccc[Poker]|r |cffda70d6" .. dealerName .. "|r has added |cffffff00" .. amount .. " chips|r to your bankroll.")
                    else
                        print("|cff00cccc[Poker]|r |cff87ceeb" .. targetName .. "|r has bought-in for |cffffff00" .. amount .. " chips|r.")
                    end
                end

            -- == BANKROLL_REMOVE ==========================================
            elseif message:match("^BANKROLL_REMOVE:") then
                local targetName, amount = message:match("^BANKROLL_REMOVE:([^:]+):(%d+)")
                amount = tonumber(amount)
                if targetName and amount then
                    playerBankrolls[targetName] = math.max(0, (playerBankrolls[targetName] or 0) - amount)
                    -- This player's seat
                    for seatNum, name in pairs(occupiedSeats) do
                        if name == targetName then
                            seatMarkers[seatNum].occupied = true
                            CreatePlayerNameText(seatNum, targetName)
                        end
                    end
                    local myName = UnitName("player"):match("([^-]+)") or UnitName("player")
                    local dealerName = sender:match("([^-]+)") or sender
                    if targetName == myName then
                        print("|cff00cccc[Poker]|r |cffda70d6" .. dealerName .. "|r has removed |cffffff00" .. amount .. " chips|r from your bankroll.")
                    else
                        print("|cff00cccc[Poker]|r |cff87ceeb" .. targetName .. "|r has withdrew |cffffff00" .. amount .. " chips|r.")
                    end
                end

            elseif message:match("^BANKROLL_SET:") then
                local name, amt = message:match("^BANKROLL_SET:([^:]+):(%d+)")
                if name and amt then
                    amt = tonumber(amt)
                    playerBankrolls[name] = amt
                    local updated = false
                    -- Update every seat with a matching name
                    for seatNum, fs in pairs(seatNameTexts) do
                        if fs:GetText() == name then
                            if seatBankrollTexts[seatNum] then
                                seatBankrollTexts[seatNum]:SetText(amt .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
                            end
                            updated = true
                        end
                    end
                    -- Update the per-player text if there is one
                    if playerBankrollTexts[name] then
                        playerBankrollTexts[name]:SetText(amt .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
                        updated = true
                    end
                    -- UI not built yet: cache for when the seat is created
                    if not updated then
                        pendingBankrollSets[name] = amt
                    end
                end

            elseif message:match("^POT_SPLIT:") then
                local namesCSV, totalStr, rakeStr = message:match("^POT_SPLIT:([^:]+):(%d+):(%d+)")
                local payoutTotal = tonumber(totalStr) or 0   -- Total after rake (the dealer already took it)
                local rake  = tonumber(rakeStr) or 0
                -- Names of the winners
                local winners = {}
                for n in string.gmatch(namesCSV or "", "([^,]+)") do table.insert(winners, n) end
                local listText = (#winners == 2) and (winners[1] .. " and " .. winners[2]) or table.concat(winners, ", ")
                print("|cff00cccc[Poker]|r |cffe32636[•]|r " .. listText .. " have split the pot of |cffffff00" .. payoutTotal .. " chips|r (Rake: |cffffff00" .. rake .. " chips|r).")

                -- Win sound if we are among the winners, once per hand
                local myShort = UnitName("player"):match("([^-]+)") or UnitName("player")
                for _, w in ipairs(winners) do
                    if w == myShort and not playedWinSound then
                        PlaySoundFile(POKER_MEDIA .. "win.ogg", "Master")
                        playedWinSound = true
                        break
                    end
                end

                -- Winner seats in ascending order, matching the dealer's remainder rule
                local winnerSeats = {}
                for _, w in ipairs(winners) do
                    for s, pname in pairs(occupiedSeats) do
                        if pname == w then table.insert(winnerSeats, s) break end
                    end
                end
                table.sort(winnerSeats, function(a,b) return a < b end)

                -- Shares as the dealer computes them: floor, remainder to the lowest seats
                local count = math.max(1, #winnerSeats)
                local baseShare = math.floor(payoutTotal / count)
                local remainder = payoutTotal % count
                local sharesBySeat = {}
                for i, s in ipairs(winnerSeats) do
                    sharesBySeat[s] = baseShare + ((i <= remainder) and 1 or 0)
                end

                if historyPanel and historyPanel._hands then
                    historyPanel._hands.setPot(payoutTotal)
                end

                -- Animate the split from a visible centre stack
                if #winnerSeats > 0 then
                    AnimatePotSplitToWinners(winnerSeats, sharesBySeat, function()
                        -- The dealer sends BANKROLL_SET for each player after the animation
                    end)
                end
                return

            elseif message:match("^UPDATE_BB:") then
                local bb, sb = message:match("^UPDATE_BB:(%d+):(%d+)")
                if bb and sb then
                    local changed = BB ~= tonumber(bb) or SB ~= tonumber(sb)
                    BB = tonumber(bb)
                    SB = tonumber(sb)
                    bbValue:SetText("|cffffff00" .. BB .. "|r |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
                    sbValue:SetText("|cffffff00" .. SB .. "|r |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
                    if changed then print("|cff00cccc[Poker]|r |cff228B22[New]|r |cffffffffBB:|r |cffffff00" .. BB .. " chips|r |cffffffff|r |cffffffffSB:|r |cffffff00" .. SB .. " chips|r") end
                end
            elseif message:match("^UPDATE_RAKE:") then
                local rake = message:match("^UPDATE_RAKE:([%d%.]+)")
                if rake then
                    local changed = Rake ~= tonumber(rake)
                    Rake = tonumber(rake)
                    rakeValue:SetText("|cffffff00" .. string.format("%.1f", Rake) .. "%|r")
                    if changed then print("|cff00cccc[Poker]|r |cff228B22[New]|r |cffffffffRake:|r |cffffff00" .. string.format("%.1f", Rake) .. "%|r") end
                end
            elseif message:match("^UPDATE_RAKECAP:") then
                local rakeCapMult = message:match("^UPDATE_RAKECAP:(%d+)")
                if rakeCapMult then
                    RakeCapMult = tonumber(rakeCapMult)
                    capValue:SetText("|cffffff00" .. RakeCapMult .. "x BB|r")
                    print("|cff00cccc[Poker]|r |cff228B22[New]|r |cffffffffRake cap:|r |cffffff00" .. RakeCapMult .. "x BB|r")
                end
            elseif message:match("^UPDATE_TIMER:") then
                local timer = message:match("^UPDATE_TIMER:(%d+)")
                if timer then
                    local changed = PLAYER_TIMER_DURATION ~= tonumber(timer)
                    PLAYER_TIMER_DURATION = tonumber(timer)
                    if changed then print("|cff00cccc[Poker]|r |cff228B22[New]|r |cffffffffTimer:|r |cffffff00" .. timer .. " seconds|r") end
                end
            elseif message:match("^SHUFFLE:") then
                -- No leaving once Shuffle and Hand IDs arrive
                if leaveSeatBtn then leaveSeatBtn:Disable() end

                local shuffleID, handID = message:match("^SHUFFLE:([^:]+):([^:]+)")
                if shuffleID and handID then
                    print("|cff00cccc[Poker]|r |cffe32636[•]|r Shuffle ID: |cffffe6b3" .. shuffleID)
                    print("|cff00cccc[Poker]|r |cffe32636[•]|r Hand ID: |cffffe6b3" .. handID)
                end
                -- Work out the deal order for this hand
                dealingOrder = {}
                dealingCardCount = {}
                -- Occupied seats, ascending
                local occupied = {}
                for i = 1, 9 do
                    if seatMarkers[i] and seatMarkers[i].occupied then
                        table.insert(occupied, i)
                    end
                end
                -- Dealer's position
                local dealerIdx
                for idx, seat in ipairs(occupied) do
                    if seat == currentDealerSeat then
                        dealerIdx = idx
                        break
                    end
                end
                if dealerIdx then
                    local n = #occupied
                    for round = 1, 2 do
                        for i = 1, n do
                            local idx = ((dealerIdx + i - 1) % n) + 1
                            table.insert(dealingOrder, occupied[idx])
                        end
                    end
                end
                dealingIndex = 1
                myCardIndex = 0

                ResetAllSeatCardsAndBoard()
                -- Clear card display on every seat
                for seatNum, texs in pairs(seatCardTextures) do
                    for _, tex in pairs(texs) do
                        tex:Hide()
                    end
                    seatCardTextures[seatNum] = {}
                end
                -- Reset card counts
                for i = 1, 9 do dealingCardCount[i] = 0 end
                History_StartNewHand()
                History_SetIDs(shuffleID, handID)
            elseif message:match("^UPDATE_POT:") then
                local newPot = tonumber(message:match("^UPDATE_POT:(%d+)"))
                if newPot then
                    potValue = newPot
                    if potText then
                        potText:SetText("Total Pot: " .. potValue .. " |T" .. POKER_MEDIA .. "1chip:16:16:0:0|t")
                    end
                    -- Refresh percent buttons and the all-in lock
                    UpdatePercentButtons()
                    UpdateAllInLock()
                end
            elseif message == "FLOP_BEGIN" then
                EndBettingRoundLocal()
                HideAllSeatTurnGlows()
                return
            elseif message:match("^ALL_IN:") then
                PlayChipsSound()
                local allInName, allInAmount = message:match("^ALL_IN:([^:]+):(%d+)")
                allInAmount = tonumber(allInAmount)
                local seatNum
                if allInName and allInAmount then
                    -- This player's seat
                    for s, name in pairs(occupiedSeats) do
                        if name == allInName then seatNum = s break end
                    end
                    if seatNum then
                        -- Apply the bet and new bankroll
                        playerBets[seatNum] = (playerBets[seatNum] or 0) + allInAmount
                        playerBankrolls[allInName] = (playerBankrolls[allInName] or 0) - allInAmount
                        ShowChipsAtSeat(seatNum, playerBets[seatNum])
                        if seatBankrollTexts[seatNum] then
                            seatBankrollTexts[seatNum]:SetText((playerBankrolls[allInName] or 0) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
                        end
                        print("|cff00cccc[Poker]|r |cffe32636[•]|r |cffb4dfff" .. allInName .. "|r went all-in for " .. allInAmount .. " chips.")
                    end
                end
                if seatNum then SetLastAction(seatNum, "ALL_IN", allInAmount) end
                -- Otherwise move the turn on as usual (3+ players, or nobody all-in)
                if #bettingOrder == 2 then
                    -- The other seat in a heads-up hand
                    local nextIndex
                    for i, seat in ipairs(bettingOrder) do
                        if occupiedSeats[seat] and occupiedSeats[seat] ~= allInName then
                            nextIndex = i
                            break
                        end
                    end
                else
                end
                -- Speech bubble
                if allInName and allInAmount then
                    for s, pname in pairs(occupiedSeats) do
                        if pname == allInName then ShowSeatSpeechBubble(s, "All-In for " .. allInAmount .. GOLD_ICON) break end
                    end
                end
            elseif message:match("^CHECK:") then
                local checkName = message:match("^CHECK:(.+)")
                PlayCheckSound()
                print("|cff00cccc[Poker]|r |cffe32636[•]|r |cffb4dfff" .. checkName .. "|r checks.")
                local actingSeat
                for s, pname in pairs(occupiedSeats) do
                    if pname == checkName then
                        actingSeat = s
                        break
                    end
                end
                if actingSeat and actingSeat == bbSeat then
                    bbHasActed = true
                end
                if actingSeat then SetLastAction(actingSeat, "CHECK") end
                decisionBox:Hide()
                -- Speech bubble
                for s, pname in pairs(occupiedSeats) do
                    if pname == checkName then ShowSeatSpeechBubble(s, "Check..") break end
                end
            elseif message:match("^BURN:") then
                local dealerName = message:match("^BURN:(.+)")
                print("|cff00cccc[Poker]|r |cffe32636[•]|r |cffda70d6" .. dealerName .. "|r has burnt a card.")
                PlaySoundFile(POKER_MEDIA .. "burn.MP3", "Master")
            elseif message:match("^SHOW_SID:") then
                local sid = message:match("^SHOW_SID:(.+)")
                if sid then
                    print("|cff00cccc[Poker]|r |cffe32636[•]|r |cffffffffShuffle ID:|r |cffffe6b3" .. sid)
                end
            elseif message:match("^SHOW_HID:") then
                local hid = message:match("^SHOW_HID:(.+)")
                if hid then
                    print("|cff00cccc[Poker]|r |cffe32636[•]|r |cffffffffHand ID:|r |cffffe6b3" .. hid)
                end
            elseif message:match("^SHOW_SB:") then
                local name, sb = message:match("^SHOW_SB:([^:]+):(%d+)")
                sb = tonumber(sb)
                if name and sb then
                    print("|cff00cccc[Poker]|r |cffe32636[•]|r |cff87ceeb" .. name .. "|r posts the small blind of |cffffff00" .. sb .. " chips|r.")
                    -- This player's seat
                    for seatNum, pname in pairs(occupiedSeats) do
                        if pname == name then
                            -- Take it from the bankroll
                            playerBankrolls[name] = (playerBankrolls[name] or 0) - sb
                            playerBets[seatNum] = (playerBets[seatNum] or 0) + sb
                            if seatBankrollTexts[seatNum] then
                                seatBankrollTexts[seatNum]:SetText((playerBankrolls[name] or 0) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
                            end
                            -- Display the chips
                            ShowChipsAtSeat(seatNum, sb)
                        end
                    end
                end
            elseif message:match("^SHOW_BB:") then
                local name, bb = message:match("^SHOW_BB:([^:]+):(%d+)")
                bb = tonumber(bb)
                if name and bb then
                    print("|cff00cccc[Poker]|r |cffe32636[•]|r |cff87ceeb" .. name .. "|r posts the big blind of |cffffff00" .. bb .. " chips|r.")
                    for seatNum, pname in pairs(occupiedSeats) do
                        if pname == name then
                            bbSeat = seatNum
                            playerBankrolls[name] = (playerBankrolls[name] or 0) - bb
                            playerBets[seatNum] = (playerBets[seatNum] or 0) + bb
                            if seatBankrollTexts[seatNum] then
                                seatBankrollTexts[seatNum]:SetText((playerBankrolls[name] or 0) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
                            end
                            ShowChipsAtSeat(seatNum, bb)
                        end
                    end
                end
            elseif message:match("^VOID_HAND:") then
                hasPlayerFolded = false
                bbHasActed = false
                preflopRoundActive = false
                playedWinSound = false
                ClearAllLastActions()
                Poker_HideShowdownPopup()
                HideAllSeatTurnGlows()
                HidePotStack()
                ResetAllSeatCardsAndBoard()
                ResetAllCardOpacity()
                local dealerName, shuffleID = message:match("^VOID_HAND:([^:]+):(.+)")
                print("|cff00cccc[Poker]|r |cffe32636[•]|r |cffda70d6" .. dealerName .. "|r has voided the current hand (Shuffle ID: |cffffe6b3" .. shuffleID .. "|r). All bets have been refunded.")

                -- Bankrolls are not touched here: the dealer sends BANKROLL_SET for each player
                -- Clear bets, chips and cards locally, then wait for BANKROLL_SET and UPDATE_POT:0

                -- Clear chips and amount boxes, hiding the box before the table entry resets
                for seatNum = 1, 9 do
                    local entry = seatChipFrames[seatNum]
                    if entry and entry.amountBox then
                        entry.amountBox:Hide()
                        entry.amountBox:SetParent(nil)
                        entry.amountBox = nil
                    end
                    if entry then
                        for _, chip in ipairs(entry) do
                            chip:Hide()
                            chip:SetParent(nil)
                        end
                        seatChipFrames[seatNum] = {}
                    end
                    playerBets[seatNum] = 0
                end

                -- Clear every card
                for seatNum, texs in pairs(seatCardTextures) do
                    for _, tex in pairs(texs) do
                        tex:Hide()
                        tex:SetParent(nil)
                    end
                    seatCardTextures[seatNum] = {}
                end
                ClearFlopCards()
                ClearTurnRiverCards()
                -- Also clear any locally tracked turn and river textures

                if decisionBox then decisionBox:Hide() end
                for i = 1, 9 do StopSeatTurnTimer(i) end
                if leaveSeatBtn then leaveSeatBtn:Enable() end
            elseif message:match("^SHOWDOWN_POPUP:") then
                local seatStr, winName, payoutStr, catStr, list = message:match("^SHOWDOWN_POPUP:(%d+):([^:]+):(%d+):(%d+):(.+)$")
                local payout = tonumber(payoutStr) or 0
                local cat = tonumber(catStr) or 0
                local codes = {}
                for code in string.gmatch(list, "([^,]+)") do table.insert(codes, code) end
                local hname = ({ [9]="Royal Flush",[8]="Straight Flush",[7]="Four of a Kind",[6]="Full House",[5]="Flush",[4]="Straight",[3]="Three of a Kind",[2]="Two Pair",[1]="One Pair",[0]="High Card" })[cat] or "Hand"
                GateShowdownCall(function()
                    -- Win sound if we won, once per hand
                    local myShort = UnitName("player"):match("([^-]+)") or UnitName("player")
                    if winName == myShort and not playedWinSound then
                        PlaySoundFile(POKER_MEDIA .. "win.ogg", "Master")
                        playedWinSound = true
                    end
                    Poker_ShowShowdownPopup(winName, payout, hname, codes)
                end)
                return
            elseif message == "NEXT_HAND" then
                Poker_HideShowdownPopup()
                HidePotStack()
                HideAllSeatTurnGlows()
                ResetAllSeatCardsAndBoard()
                ResetAllCardOpacity()
                ClearAllLastActions()
                playedWinSound = false
                preflopRoundActive = true
                bbHasActed = false
                hasPlayerFolded = false
                bbSeat = nil
                Poker_LastDeckOrderStr = nil
                local dealerName = sender:match("([^-]+)") or sender
                print("|cff00cccc[Poker]|r |cffda70d6" .. dealerName .. "|r has cleared the table.")

                -- Zero every player's bet
                for seatNum = 1, 9 do
                    playerBets[seatNum] = 0
                end

                -- Clear every card from the table
                for seatNum, texs in pairs(seatCardTextures) do
                    for _, tex in pairs(texs) do
                        tex:Hide()
                        tex:SetParent(nil)
                    end
                    seatCardTextures[seatNum] = {}
                end

                -- Reset every turn timer bar
                for i = 1, 9 do
                    StopSeatTurnTimer(i)
                end

                -- Reset turn and betting state
                currentActingSeat = nil
                bettingOrder = {}
                bettingIndex = 1
                dealingOrder = {}
                dealingIndex = 1
                myCardIndex = 0

                -- Reset min-raise and last bet for the new hand
                lastRaiseAmount = 0
                lastBet = 0

                -- Clear chips and amount boxes as well
                for seatNum = 1, 9 do
                    if seatChipFrames[seatNum] then
                        for _, chip in ipairs(seatChipFrames[seatNum]) do
                            chip:Hide()
                            chip:SetParent(nil)
                        end
                        seatChipFrames[seatNum] = {}
                    end
                    if seatChipFrames[seatNum] and seatChipFrames[seatNum].amountBox then
                        seatChipFrames[seatNum].amountBox:Hide()
                    end
                end

                -- Hide the decision box
                if decisionBox then decisionBox:Hide() end

                ClearFlopCards()
                ClearTurnRiverCards()
                if leaveSeatBtn then leaveSeatBtn:Enable() end

                UpdateRaiseSliderForBankroll()
            elseif message:match("^FOLD:") then
                local foldName = message:match("^FOLD:(.+)")
                print("|cff00cccc[Poker]|r |cffe32636[•]|r |cff87ceeb" .. foldName .. "|r has folded their hand.")
                
                local actingSeat
                for s, pname in pairs(occupiedSeats) do
                    if pname == foldName then
                        actingSeat = s
                        break
                    end
                end
                if actingSeat then SetLastAction(actingSeat, "FOLD") end
                if actingSeat and actingSeat == bbSeat then
                    bbHasActed = true
                end
                
                -- Dim their cards to 25%
                for seatNum, pname in pairs(occupiedSeats) do
                    if pname == foldName and seatCardTextures[seatNum] then
                        for _, tex in pairs(seatCardTextures[seatNum]) do
                            tex:SetAlpha(0.25)
                        end
                    end
                end

                -- If the remaining bets match, or one player is left, end the round locally
                local activeSeats = {}
                for seatNum, pname in pairs(occupiedSeats) do
                    if seatMarkers[seatNum] and seatMarkers[seatNum].occupied and pname ~= foldName then
                        table.insert(activeSeats, seatNum)
                    end
                end
                local betsMatch = false
                if #activeSeats <= 1 then
                    betsMatch = true
                else
                    local ref = playerBets[activeSeats[1]] or 0
                    betsMatch = true
                    for i = 2, #activeSeats do
                        if (playerBets[activeSeats[i]] or 0) ~= ref then
                            betsMatch = false
                            break
                        end
                    end
                end
                if betsMatch then
                    EndBettingRoundLocal()
                end
                -- Speech bubble
                for s, pname in pairs(occupiedSeats) do
                    if pname == foldName then ShowSeatSpeechBubble(s, "Fold..") break end
                end

            elseif message:match("^CALL:") then
                PlayChipsSound()
                local callName, callAmount = message:match("^CALL:([^:]+):(%d+)")
                callAmount = tonumber(callAmount)
                print("|cff00cccc[Poker]|r |cffe32636[•]|r |cff87ceeb" .. callName .. "|r called |cffffff00" .. callAmount .. " chips|r.")

                local actingSeat
                for s, pname in pairs(occupiedSeats) do
                    if pname == callName then
                        actingSeat = s
                        break
                    end
                end
                if actingSeat then SetLastAction(actingSeat, "CALL", callAmount) end
                if actingSeat and actingSeat == bbSeat then
                    bbHasActed = true
                end
                for seatNum, pname in pairs(occupiedSeats) do
                    if pname == callName then
                        actingSeat = seatNum
                        playerBets[seatNum] = (playerBets[seatNum] or 0) + callAmount
                        if playerBankrolls[callName] then
                            playerBankrolls[callName] = playerBankrolls[callName] - callAmount
                            if seatBankrollTexts[seatNum] then
                                seatBankrollTexts[seatNum]:SetText((playerBankrolls[callName] or 0) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
                            end
                        end
                        ShowChipsAtSeat(seatNum, playerBets[seatNum])
    
                    end
                end
                local maxBet = 0
                for _, bet in pairs(playerBets) do
                    if bet > maxBet then maxBet = bet end
                end
                -- Speech bubble
                for s, pname in pairs(occupiedSeats) do
                    if pname == callName then ShowSeatSpeechBubble(s, "Call " .. callAmount .. GOLD_ICON) break end
                end

            elseif message:match("^RAISE:") then
                PlayChipsSound()
                local raiseName, raiseTo = message:match("^RAISE:([^:]+):(%d+)")
                raiseTo = tonumber(raiseTo)

                -- Is this an opening bet (no maxBet before this raise)?
                local preMax = 0
                for _, bet in pairs(playerBets) do if bet > preMax then preMax = bet end end
                local isBet = (preMax == 0)

                local actingSeat
                for s, pname in pairs(occupiedSeats) do
                    if pname == raiseName then
                        actingSeat = s
                        break
                    end
                end
                if actingSeat and actingSeat == bbSeat then
                    bbHasActed = true
                end
                if actingSeat then SetLastAction(actingSeat, "RAISE", raiseTo) end
                raiseTo = tonumber(raiseTo)
                if raiseName and raiseTo then
                    -- This player's seat
                    local seatNum
                    for s, name in pairs(occupiedSeats) do
                        if name == raiseName then seatNum = s break end
                    end
                    if not seatNum then return end -- Unknown seat: wait for the next snapshot
                    local actingSeat = seatNum
                    local myBet = playerBets[seatNum] or 0
                    local maxBet = 0
                    for _, bet in pairs(playerBets) do
                        if bet > maxBet then maxBet = bet end
                    end
                    local toCall = maxBet - myBet
                    local raiseAmount = raiseTo - maxBet
                    local totalPutIn = toCall + raiseAmount

                    -- Apply the raise and new bankroll
                    playerBankrolls[raiseName] = (playerBankrolls[raiseName] or 0) - totalPutIn
                    playerBets[seatNum] = (playerBets[seatNum] or 0) + totalPutIn
                    ShowChipsAtSeat(seatNum, playerBets[seatNum])
                    if seatBankrollTexts[seatNum] then
                        seatBankrollTexts[seatNum]:SetText((playerBankrolls[raiseName] or 0) .. " |T" .. POKER_MEDIA .. "1chip:12:12:0:0|t")
                    end
                

                    lastRaiseAmount = raiseAmount
                    lastBet = raiseTo

                    print("|cff00cccc[Poker]|r |cffe32636[•]|r |cff87ceeb" .. raiseName .. "|r raised to |cffffff00" .. raiseTo .. " chips|r.")
                end
                -- Speech bubble once the seat is known
                if raiseName and raiseTo then
                    for s, pname in pairs(occupiedSeats) do
                        if pname == raiseName then
                            local txt = isBet and ("Bet " .. raiseTo .. GOLD_ICON) or ("Raise to " .. raiseTo .. GOLD_ICON)
                            ShowSeatSpeechBubble(s, txt)
                            break
                        end
                    end
                end
            elseif message:match("^HAND_OVER:") then
                -- Single winner by folds
                local winnerName, winnerSeat = message:match("^HAND_OVER:([^:]+):(%d+)")
                winnerSeat = tonumber(winnerSeat)
                -- Win sound if we won by folds, once per hand
                if winnerName then
                    local myShort = UnitName("player"):match("([^-]+)") or UnitName("player")
                    if winnerName == myShort and not playedWinSound then
                        PlaySoundFile(POKER_MEDIA .. "win.ogg", "Master")
                        playedWinSound = true
                    end
                end
                if winnerSeat then
                    scoopInProgress = true
                    AnimatePotCollection(function()
                        AnimatePotToWinner(winnerSeat, function()
                            scoopInProgress = false
                            -- Leaving is allowed again once the hand is settled
                            if leaveSeatBtn then leaveSeatBtn:Enable() end
                        end)
                    end)
                    if decisionBox then decisionBox:Hide() end
                    for i = 1, 9 do StopSeatTurnTimer(i) end
                end
                HideAllSeatTurnGlows()
                return
            
            elseif message:match("^TURN_START:") then
                local seatNum = tonumber(message:match("^TURN_START:(%d+)"))
                for i = 1, 9 do StopSeatTurnTimer(i) end
                if seatNum then StartSeatTurnTimer(seatNum, PLAYER_TIMER_DURATION) end
                if seatNum then ShowSeatTurnGlow(seatNum) end
                if playerSeat == seatNum and not hasPlayerFolded then
                    decisionBox:Show()
                    UpdateRaiseSliderForBankroll()
                    UpdateCallButton()
                    local now = GetTime and GetTime() or 0
                    if now - (lastTurnSoundAt or 0) > 0.5 then
                        PlaySoundFile(POKER_MEDIA .. "turn_sound.MP3", "Master")
                        PlaySoundFile(POKER_MEDIA .. "sound1.ogg", "Master")
                        PlaySoundFile(POKER_MEDIA .. "sound2.ogg", "Master")
                        lastTurnSoundAt = now
                    end
                    UpdatePercentButtons()
                    UpdateAllInLock()
                else
                    decisionBox:Hide()
                end

            elseif message:match("^FLOP_CARD:") then
                local cardName, cardCode = message:match("^FLOP_CARD:([^:]+):([^:]+)")
                print("|cff00cccc[Poker]|r |cffe32636[•]|r Flop: " .. cardName .. " [" .. cardCode .. "].")
                playerFlopIndex = (playerFlopIndex or 0) + 1
                ShowFlopCard(cardCode, playerFlopIndex)
                PlayDealSoundOnce()
            elseif message:match("^FLOP:") then
                local c1, c2, c3 = message:match("^FLOP:([^:]+):([^:]+):([^:]+)")
                print("|cff00cccc[Poker]|r |cffe32636[•]|r |cffffffffFlop:|r |cffffe6b3[" .. c1 .. "] [" .. c2 .. "] [" .. c3 .. "]|r")
                playerFlopIndex = 0 -- Ready for the next round
                preflopRoundActive = false
                -- Re-show all three flop cards for a resync if needed:
                ShowFlopCard(c1, 1)
                ShowFlopCard(c2, 2)
                ShowFlopCard(c3, 3)
                lastRaiseAmount = BB
                -- Zero every player's bet for the new betting round
                for seatNum = 1, 9 do
                    playerBets[seatNum] = 0
                    ShowChipsAtSeat(seatNum, 0)
                end
                HideAllSeatTurnGlows()
                History_SetBoardCards({c1,c2,c3})
            elseif message:match("^TURN:") then
                local code = message:match("^TURN:(%w+)")
                print("|cff00cccc[Poker]|r |cffe32636[•]|r |cffffffffTurn:|r |cffffe6b3[" .. code .. "]|r")
                -- Stop leftover timers when the street changes
                for i = 1, 9 do StopSeatTurnTimer(i) end
                -- Fallback: collect any chips the missed round-complete left behind
                if HasAnySeatChips() then
                    AnimatePotCollection()
                end
                ShowTurnCard(code)
                PlayDealSound()
                -- Reset the betting UI for the new street
                preflopRoundActive = false
                lastRaiseAmount = BB
                for seatNum = 1, 9 do
                    playerBets[seatNum] = 0
                    ShowChipsAtSeat(seatNum, 0)
                end
                HideAllSeatTurnGlows()
                History_SetBoardCards({flopCodes[1], flopCodes[2], flopCodes[3], code})
            elseif message:match("^RIVER:") then
                local code = message:match("^RIVER:(%w+)")
                print("|cff00cccc[Poker]|r |cffe32636[•]|r |cffffffffRiver:|r |cffffe6b3[" .. code .. "]|r")
                -- Stop leftover timers when the street changes
                for i = 1, 9 do StopSeatTurnTimer(i) end
                -- Fallback chip collection
                if HasAnySeatChips() then
                    AnimatePotCollection()
                end
                ShowRiverCard(code)
                PlayDealSound()
                -- Hold the showdown until at least 1.0s after the river
                sdGateTime = (GetTime and (GetTime() + 1.0)) or nil
                -- River betting round starts
                preflopRoundActive = false
                lastRaiseAmount = BB
                for seatNum = 1, 9 do
                    playerBets[seatNum] = 0
                    ShowChipsAtSeat(seatNum, 0)
                end
                HideAllSeatTurnGlows()
                History_SetBoardCards({flopCodes[1], flopCodes[2], flopCodes[3], turnCode, code})
            elseif message:match("^DECK_ORDER:") then
                local deckOrderStr = message:match("^DECK_ORDER:(.+)")
                if deckOrderStr then
                    Poker_LastDeckOrderStr = deckOrderStr
                    print("|cff00cccc[Poker]|r |cffe32636[•]|r Type |cffffe6b3/poker deck|r to view the shuffled deck order for that round.")
                end
            elseif message:match("^POT_WINNER:") then
                local winner, payout, rake = message:match("^POT_WINNER:([^:]+):(%d+):(%d+)")
                payout = tonumber(payout)
                rake = tonumber(rake)
                if winner and payout and rake then
                    local myShort = UnitName("player"):match("([^-]+)") or UnitName("player")
                    print("|cff00cccc[Poker]|r |cffe32636[•]|r |cff87ceeb" .. winner .. "|r has won the pot of |cffffff00" .. payout .. " chips|r (Rake: |cffffff00" .. rake .. " chips|r).")
                    if winner == myShort and not playedWinSound then
                        PlaySoundFile(POKER_MEDIA .. "win.ogg", "Master")
                        playedWinSound = true
                    end

                    -- Winner seat, needed only for the animation
                    local winnerSeatNum
                    for seatNum, name in pairs(occupiedSeats) do
                        if name == winner then winnerSeatNum = seatNum break end
                    end

                    if historyPanel and historyPanel._hands then
                        historyPanel._hands.setPot(payout)
                    end

                    -- Leave playerBankrolls alone here; BANKROLL_SET is the source of truth
                    if scoopInProgress then
                        -- This is the fold (HAND_OVER) path and the animation is already running, so
                        -- return early and let BANKROLL_SET set the exact amount
                        for i = 1, 9 do playerBets[i] = 0 end
                        if decisionBox then decisionBox:Hide() end
                        return
                    end

                    if winnerSeatNum then
                        AnimatePotToWinner(winnerSeatNum, function()
                            -- After the animation only clear bets; the bankroll comes from BANKROLL_SET
                            for i = 1, 9 do playerBets[i] = 0 end
                            if decisionBox then decisionBox:Hide() end
                        end)
                    else
                        -- No seat found: clear bets and pot visuals; BANKROLL_SET syncs the bankroll
                        for i = 1, 9 do playerBets[i] = 0 end
                        if decisionBox then decisionBox:Hide() end
                        HidePotStack()
                        potValue = 0
                        if potText then
                            potText:SetText("Total Pot: 0 |T" .. POKER_MEDIA .. "1chip:16:16:0:0|t")
                        end
                    end
                    if leaveSeatBtn then leaveSeatBtn:Enable() end
                end
                HideAllSeatTurnGlows()
                return
            elseif message == "BETTING_ROUND_COMPLETE" then
                EndBettingRoundLocal()
                HideAllSeatTurnGlows()
                return
            elseif message:match("^SHOWDOWN_REVEAL:") then
                local seatStr, c1, c2 = message:match("^SHOWDOWN_REVEAL:(%d+):(%w+):(%w+)$")
                local seatNum = tonumber(seatStr)
                if seatNum then
                    GateShowdownCall(function()
                        ShowCardAboveSeat(seatNum, c1, 1, false)
                        ShowCardAboveSeat(seatNum, c2, 2, false)
                    end)
                end
                return

            elseif message:match("^SHOWDOWN_LINE:") then
                local line = message:sub(("SHOWDOWN_LINE:"):len() + 1)
                if line and line ~= "" then
                    GateShowdownCall(function() print(line) end)
                end
                return

            elseif message:match("^SHOWDOWN_HIGHLIGHT:") then
                local list = message:match("^SHOWDOWN_HIGHLIGHT:(.+)")
                local set = {}
                if list and list ~= "" then
                    for code in string.gmatch(list, "([^,]+)") do
                        set[code] = true
                    end
                end
                GateShowdownCall(function() ApplyWinningHighlight(set) end)
                return
            end
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = ...
        local player, roll, min, max = msg:match("^(%S+) rolls (%d+) %((%d+)%-(%d+)%)")
        if player and roll and min and max and dealingOrder and #dealingOrder > 0 and dealingIndex <= #dealingOrder then
            -- Treat as a hole card only during the hole card deal
            if not dealingFlop and not dealingTurn and not dealingRiver then
                local seat = dealingOrder[dealingIndex]
                if seat then
                    -- Count the card for this seat
                    dealingCardCount[seat] = (dealingCardCount[seat] or 0) + 1
                    local idx = dealingCardCount[seat]

                    -- One deal sound per card, as it lands at the seat
                    AnimateDealCardToSeat(seat, function()
                        PlayDealSoundOnce()
                        -- Only show a card back if the slot is not revealed
                        if not seatCardCodes[seat] or not seatCardCodes[seat][idx] then
                            ShowCardAboveSeat(seat, "card_back", idx, seat == playerSeat)
                        end
                    end)
                end

                dealingIndex = dealingIndex + 1

                -- Once every card is out, wait for the dealer's TURN_START
            end
        end
    elseif event == "CHAT_MSG_WHISPER" then
        local msg, sender = ...
        local cardCode = ExtractCardCodeFromWhisper(msg)
        if cardCode and playerSeat then
            local idx = NextHoleIndexForSeat(playerSeat)
            ShowCardAboveSeat(playerSeat, cardCode, idx, true)
            History_SetHole(cardCode)
        end
    end
end)

-- Sends the leave message with a reason
hasLeftTable = false -- Stops the message being sent twice; global so Join can reset it

local function SendLeaveMessage(reason)
    if not hasLeftTable then
        hasLeftTable = true
        -- Dealer gets its own message format
        Poker_SendAddonMessage("PokerTable", "PLAYER_LEFT:" .. UnitName("player") .. ":" .. reason, Poker_Channel())
    end
end

-- Send a leave message on logout or reload
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
        -- Only if the table was open (player was seated)
        if TableFrame:IsShown() then
            SendLeaveMessage("reload")
        end
    end
end)

-- == Slash command ========================================================
SLASH_POKER1 = "/poker"
SlashCmdList["POKER"] = function(msg)
    msg = msg and msg:lower() or ""

    local function resolveSeat(optSeat)
        local s = tonumber(optSeat)
        if s and s >= 1 and s <= 9 then return s end
        if playerSeat then return playerSeat end
        for i = 1, 9 do if occupiedSeats[i] then return i end end
        return 1
    end

    if msg == "deck" then
        if Poker_LastDeckOrderStr then
            ShowDeckOrderPopup(Poker_LastDeckOrderStr)
        else
            print("|cff00cccc[Poker]|r No deck order available for this round yet.")
        end
        return
    end

    -- Toggle the lobby; volume sits behind the Settings gear, size on the edge drag bar
    if RoleFrame:IsShown() then
        RoleFrame:Hide()
        if roleVolumePopup then roleVolumePopup:Hide() end
    else
        RoleFrame:ClearAllPoints()
        RoleFrame:SetPoint("CENTER")
        RoleFrame:Show()
        -- Ask for a snapshot
        Poker_SendAddonMessage("PokerTable", "PLAYER_WAITING:" .. UnitName("player"), Poker_Channel())
    end
end

-- Left seats 1 to 4 (Empty_Left.tga), clickable: top right, right side,
-- bottom right, bottom centre
local leftSeatPositions = {
    {x = 230, y = 175},
    {x = 365, y = 55},
    {x = 360, y = -90},
    {x = 200, y = -195},
}

for i = 1, 4 do
    -- Button rather than a plain texture, so it can be clicked
    local leftSeatBtn = CreateFrame("Button", nil, TableFrame)
    leftSeatBtn:SetSize(170, 170)
    leftSeatBtn:SetPoint("CENTER", TableFrame, "CENTER", leftSeatPositions[i].x, leftSeatPositions[i].y)
    
    -- Seat texture
    local leftSeat = leftSeatBtn:CreateTexture(nil, "OVERLAY")
    leftSeat:SetTexture(POKER_MEDIA .. "Empty_Left.tga")
    leftSeat:SetAllPoints(leftSeatBtn)
    leftSeat:SetAlpha(0.7)
    
    -- Left seat click
    leftSeatBtn:SetScript("OnClick", function()
        -- Ignore clicks while already seated
        if playerSeat then
            -- Same seat: do nothing, no message
            if playerSeat == i then
                return -- Silent exit
            end
            -- Different seat: tell the player
            print("|cff00cccc[Poker]|r You must click the |cffff8000Leave Seat|r button in order to move.")
            return -- Seat changes are not allowed
        end
        
        -- Stop if the seat is taken
        if seatMarkers[i].occupied then
            print("|cff00cccc[Poker]|r That seat is already occupied by another player.|r")
            return
        end

        -- Take the seat
        playerSeat = i
        seatMarkers[playerSeat].occupied = true
        occupiedSeats[playerSeat] = UnitName("player"):match("([^-]+)") or UnitName("player")
        leftSeat:SetTexture(POKER_MEDIA .. "Normal_Left.tga")
        leftSeat:SetAlpha(1.0) -- Fully opaque once taken
        
        -- Size button and texture for the Normal image (275 x 275)
        leftSeatBtn:SetSize(170, 170)
        
        -- Build this seat's portrait
        CreatePlayerPortrait(i)

        -- Build this seat's name text
        CreatePlayerNameText(i)
        
        -- Get the player name and send it
        local playerName = UnitName("player"):match("([^-]+)") or UnitName("player")
        
        -- Tell the dealer which seat was picked
        Poker_SendAddonMessage("PokerTable", "PLAYER_SAT_DOWN:" .. playerName .. ":" .. i, Poker_Channel())

        
        for seatNum, marker in pairs(seatMarkers) do
            if seatNum ~= playerSeat and not marker.occupied then
                marker.texture:SetAlpha(0.5)
            end
        end

        -- Enable Leave Seat
        leaveSeatBtn:Enable()
    end)
    
    seatMarkers[i] = {
        button = leftSeatBtn,
        texture = leftSeat,
        type = "left",
        position = i,
        occupied = false
    }
    CreateSeatProgressBar(i)
end

-- Right seats 5 to 9 (Empty_Right.tga), clickable: bottom left, left side,
-- top left, top left of centre, top right of centre
local rightSeatPositions = {
    {x = 5, y = -195},
    {x = -190, y = -195},
    {x = -365, y = -90},
    {x = -365, y = 55},
    {x = -230, y = 175},
}

for i = 1, 5 do
    -- Button rather than a plain texture, so it can be clicked
    local rightSeatBtn = CreateFrame("Button", nil, TableFrame)
    rightSeatBtn:SetSize(170, 170)
    rightSeatBtn:SetPoint("CENTER", TableFrame, "CENTER", rightSeatPositions[i].x, rightSeatPositions[i].y)
    
    -- Seat texture
    local rightSeat = rightSeatBtn:CreateTexture(nil, "OVERLAY")
    rightSeat:SetTexture(POKER_MEDIA .. "Empty_Right.tga")
    rightSeat:SetAllPoints(rightSeatBtn)
    rightSeat:SetAlpha(0.7)
    
    -- Right seat click
    rightSeatBtn:SetScript("OnClick", function()
        -- Ignore clicks while already seated
        if playerSeat then
            -- Same seat: do nothing, no message
            if playerSeat == (i + 4) then
                return -- Silent exit
            end
            -- Different seat: tell the player
            print("|cff00cccc[Poker]|r You must click the |cffff8000Leave Seat|r button in order to move.")
            return -- Seat changes are not allowed
        end
        
        -- Stop if the seat is taken
        if seatMarkers[i + 4].occupied then
            print("|cff00cccc[Poker]|r That seat is already occupied by another player.|r")
            return
        end

        -- Take the seat
        playerSeat = i + 4 -- Index plus 4, as these are seats 5 to 9
        seatMarkers[playerSeat].occupied = true
        occupiedSeats[playerSeat] = UnitName("player"):match("([^-]+)") or UnitName("player")
        rightSeat:SetTexture(POKER_MEDIA .. "Normal_Right.tga")
        rightSeat:SetAlpha(1.0) -- Fully opaque once taken
        
        -- Size button and texture for the Normal image (275 x 275)
        rightSeatBtn:SetSize(170, 170)
        
        -- Build this seat's portrait
        CreatePlayerPortrait(i + 4)

        -- Build this seat's name text
        CreatePlayerNameText(i + 4)
        
        -- Get the player name and send it
        local playerName = UnitName("player"):match("([^-]+)") or UnitName("player")
        
        -- Tell the dealer which seat was picked
        Poker_SendAddonMessage("PokerTable", "PLAYER_SAT_DOWN:" .. playerName .. ":" .. (i + 4), Poker_Channel())
        
        
        for seatNum, marker in pairs(seatMarkers) do
            if seatNum ~= playerSeat and not marker.occupied then
                marker.texture:SetAlpha(0.5)
            end
        end

        -- Enable Leave Seat
        leaveSeatBtn:Enable()
    end)
    
    seatMarkers[i + 4] = {
        button = rightSeatBtn,
        texture = rightSeat,
        type = "right",
        position = i + 4,
        occupied = false
    }
    CreateSeatProgressBar(i + 4)
end

-- Leaves the current seat; global so the OnEvent closure can reach it
function LeaveSeat()
    if not playerSeat then
        -- Not seated: return quietly
        return
    end

    local seat = playerSeat
    local playerName = UnitName("player"):match("([^-]+)") or UnitName("player")

    -- Clear local occupancy straight away
    occupiedSeats[seat] = nil
    if seatMarkers[seat] then
        seatMarkers[seat].occupied = false
    end

    -- Tell the dealer and others so everyone updates
    Poker_SendAddonMessage("PokerTable",
        "PLAYER_LEFT_SEAT:" .. playerName .. ":" .. seat, Poker_Channel())

    -- Reset the seat texture
    local marker = seatMarkers[seat]
    if marker then
        if marker.type == "left" then
            marker.texture:SetTexture(POKER_MEDIA .. "Empty_Left.tga")
        else
            marker.texture:SetTexture(POKER_MEDIA .. "Empty_Right.tga")
        end
        marker.texture:SetAlpha(0.7)
        marker.button:SetSize(170, 170)
    end

    -- Remove the portrait
    if seatPortraitFrames[seat] then
        seatPortraitFrames[seat]:Hide()
        seatPortraitFrames[seat]:SetParent(nil)
        seatPortraitFrames[seat] = nil
    end

    -- Remove the name text
    if seatNameTexts[seat] then
        seatNameTexts[seat]:Hide()
        seatNameTexts[seat]:SetParent(nil)
        seatNameTexts[seat] = nil
    end

    -- Remove the bankroll text
    if seatBankrollTexts[seat] then
        seatBankrollTexts[seat]:Hide()
        seatBankrollTexts[seat]:SetParent(nil)
        seatBankrollTexts[seat] = nil
    end

    -- Reset alpha on every other empty seat
    for s, m in pairs(seatMarkers) do
        if not m.occupied then
            m.texture:SetAlpha(0.7)
        end
    end

    playerSeat = nil
    if leaveSeatBtn then leaveSeatBtn:Disable() end

    -- Recalculate blinds if the dealer seat is known
    if currentDealerSeat then
        UpdateBlinds(currentDealerSeat)
    end
end

-- Leave Seat click
leaveSeatBtn:SetScript("OnClick", function()
    LeaveSeat()
end)

-- Hook the table close button
TableFrame:HookScript("OnHide", function()

    -- Close any open side panels
    if guidePanel and guidePanel:IsShown() then guidePanel:Hide() end
    if historyPanel and historyPanel:IsShown() then historyPanel:Hide() end

    -- Closing the table frees the seat and sends a leave message
    if playerSeat then LeaveSeat() end
    SendLeaveMessage("closed")

    -- Hide the popups
    if tableVolumePopup then tableVolumePopup:Hide() end

    -- Re-centre for next time
    TableFrame:ClearAllPoints()
    TableFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end)

