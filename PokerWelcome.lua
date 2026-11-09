-- =========================================================================
-- Bounty Hold'em v1.2.3 by Lee
-- PokerWelcome.lua: welcome window with how to play, shown on first load
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- Shown once per account (PokerBankDB.welcomed). The ? button in the lobby
-- opens it again

local MEDIA = POKER_MEDIA
local GOLD = "|cffffd100"

local STEPS = {
    { "step_open",   "Type /poker", "Or left-click the chip pot on your screen. This opens the lobby." },
    { "step_earn",   "Earn chips", "Every mob you kill pays: normal 1, elite 5, rare 25, rare elite 30, boss 100. Greys pay nothing. Up to 1,000 a day, plus 100 free when you open poker each day. Chips are shared by all your characters." },
    { "step_group",  "Group up", "Get your friends into a party or raid. Everyone needs the addon." },
    { "step_host",   "Host a table", "One player clicks Host Table in the lobby. Everyone else gets a pop-up asking to join: click Yes." },
    { "step_sit",    "Sit down", "Click an empty chair at the table. Your chips come with you." },
    { "step_play",   "Play", "The host presses Deal Hand. Blinds, check, call, raise or fold, and the best five cards win. Short on players? The host can add bots." },
    { "step_season", "Win the season", "Click Leaderboard in the lobby to see who's ahead. On the 1st of each month the top player wins a badge for their name and everyone starts again on 200 chips." },
}

local W, ICON, TEXT_W = 760, 50, 630

local win

-- Gold-framed red button from media\welcome_button
local function ArtButton(parent, label, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    local tex = b:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(MEDIA .. "welcome_button")
    tex:SetTexCoord(0, 1, 0.24, 0.76)
    tex:SetAllPoints()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(MEDIA .. "welcome_button")
    hl:SetTexCoord(0, 1, 0.24, 0.76)
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.35)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    fs:SetTextColor(1, 0.9, 0.6)
    fs:SetPoint("CENTER", 0, 1)
    fs:SetText(label)
    b:SetScript("OnMouseDown", function() fs:SetPoint("CENTER", 1, 0) end)
    b:SetScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 1) end)
    return b
end

local function Build()
    local ok, f = pcall(CreateFrame, "Frame", "PokerWelcomeFrame", UIParent, "BackdropTemplate")
    if not ok then f = CreateFrame("Frame", "PokerWelcomeFrame", UIParent) end
    win = f
    f:Hide()
    f:SetWidth(W)
    f:SetPoint("CENTER", 0, 10)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
            edgeSize = 32,
            insets = { left = 10, right = 10, top = 10, bottom = 10 },
        })
    end
    tinsert(UISpecialFrames, "PokerWelcomeFrame") -- Escape closes it

    -- Tavern painting, darkened so the steps read on top
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(MEDIA .. "welcome_bg")
    bg:SetPoint("TOPLEFT", 10, -10)
    bg:SetPoint("BOTTOMRIGHT", -10, 10)
    local dim = f:CreateTexture(nil, "BORDER")
    dim:SetColorTexture(0, 0, 0, 0.55)
    dim:SetAllPoints(bg)

    -- Wooden sign hanging over the top edge, with the title on its face
    local sign = CreateFrame("Frame", nil, f)
    sign:SetSize(660, 210)
    sign:SetPoint("CENTER", f, "TOP", 0, -10)
    sign:SetFrameLevel(f:GetFrameLevel() + 5)
    local board = sign:CreateTexture(nil, "ARTWORK")
    board:SetTexture(MEDIA .. "welcome_banner")
    board:SetTexCoord(0, 1, 0.18, 0.82)
    board:SetAllPoints()
    local title = sign:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\MORPHEUS.TTF", 34, "THICKOUTLINE")
    title:SetPoint("CENTER", 0, -6)
    title:SetTextColor(1, 0.82, 0.25)
    title:SetShadowOffset(2, -2)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetText("Welcome to Bounty Hold'em")

    local sub = f:CreateFontString(nil, "OVERLAY")
    sub:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    sub:SetPoint("TOP", f, "TOP", 0, -120)
    sub:SetTextColor(0.9, 0.85, 0.7)
    sub:SetText("Texas Hold'em for your party, paid for by the mobs you kill.")

    -- Steps: medallion icon, then the text beside it
    local y = -152
    for _, s in ipairs(STEPS) do
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(MEDIA .. s[1])
        icon:SetSize(ICON, ICON)
        icon:SetPoint("TOPLEFT", f, "TOPLEFT", 32, y)
        local body = f:CreateFontString(nil, "OVERLAY")
        body:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
        body:SetShadowOffset(1, -1)
        body:SetTextColor(0.94, 0.92, 0.88)
        body:SetWidth(TEXT_W)
        body:SetJustifyH("LEFT")
        body:SetSpacing(2)
        body:SetText(GOLD .. s[2] .. "|r   " .. s[3])
        local h = body:GetStringHeight() or 0
        if h <= 0 or h > 160 then h = 36 end
        body:SetPoint("LEFT", icon, "RIGHT", 14, 0)
        if h > ICON then
            body:ClearAllPoints()
            body:SetPoint("TOPLEFT", icon, "TOPRIGHT", 14, 0)
        end
        y = y - math.max(ICON, h) - 12
    end

    -- Buttons
    local play = ArtButton(f, "Let's play", 230, 58)
    play:SetPoint("TOPRIGHT", f, "TOP", -8, y - 8)
    play:SetScript("OnClick", function()
        f:Hide()
        local role = PokerUI and PokerUI.RoleFrame
        if not (role and role:IsShown()) and SlashCmdList["POKER"] then SlashCmdList["POKER"]("") end
    end)
    local close = ArtButton(f, "Close", 230, 58)
    close:SetPoint("TOPLEFT", f, "TOP", 8, y - 8)
    close:SetScript("OnClick", function() f:Hide() end)
    f:SetHeight(-y + 86)

    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", -6, -6)
    x:SetFrameLevel(sign:GetFrameLevel() + 2)

    -- Seen once is enough; the lobby's ? button brings it back
    f:SetScript("OnShow", function()
        if PokerBankDB then PokerBankDB.welcomed = true end
        PlaySoundFile(MEDIA .. "chips.MP3", "SFX")
    end)
end

function PokerWelcome_Show()
    if not win then Build() end
    win:Show()
end

-- ? button in the lobby, beside the volume gear
local function AddLobbyButton()
    local ui = PokerUI
    local role = ui and ui.RoleFrame
    if not role then return end
    local b = CreateFrame("Button", nil, role)
    b:SetSize(30, 30)
    local gear = ui.roleScaleBtn
    if gear then
        b:SetPoint("RIGHT", gear, "LEFT", -6, 0)
    else
        b:SetPoint("TOPRIGHT", role, "TOPRIGHT", -46, -30)
    end
    b:SetFrameLevel(role:GetFrameLevel() + 25)
    -- Gold ? on the chip medallion, matching the welcome art
    local chip = b:CreateTexture(nil, "ARTWORK")
    chip:SetTexture(MEDIA .. "step_open")
    chip:SetAllPoints()
    chip:SetVertexColor(0.55, 0.45, 0.4)
    local q = b:CreateFontString(nil, "OVERLAY")
    q:SetFont("Fonts\\MORPHEUS.TTF", 22, "THICKOUTLINE")
    q:SetTextColor(1, 0.82, 0.25)
    q:SetPoint("CENTER", 1, 0)
    q:SetText("?")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(MEDIA .. "step_open")
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.3)
    b:SetScript("OnClick", PokerWelcome_Show)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("How to play", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    -- After the lobby is styled (+0.2s); then greet new players once the screen settles
    C_Timer.After(0.5, function()
        local ok, err = pcall(AddLobbyButton)
        if not ok then print("|cff00cccc[Poker]|r Help button failed: " .. tostring(err)) end
    end)
    C_Timer.After(4, function()
        if PokerBankDB and PokerBankDB.welcomed then return end
        if InCombatLockdown and InCombatLockdown() then return end -- Next login instead
        local ok, err = pcall(PokerWelcome_Show)
        if not ok then print("|cff00cccc[Poker]|r Welcome window failed: " .. tostring(err)) end
    end)
end)
