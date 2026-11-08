-- =========================================================================
-- Bounty Hold'em v1.2.1 by Lee
-- PokerWelcome.lua: welcome window with how to play, shown on first load
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- Shown once per account (PokerBankDB.welcomed). The ? button in the lobby
-- opens it again

local MEDIA = POKER_MEDIA
local GOLD = "|cffffd100"

local STEPS = {
    { "Type /poker", "Or left-click the chip pot on your screen. This opens the lobby." },
    { "Earn chips", "Every mob you kill pays: normal 1, elite 5, rare 25, rare elite 30, boss 100. Greys pay nothing. Up to 1,000 a day, plus 100 free when you open poker each day. Chips are shared by all your characters." },
    { "Group up", "Get your friends into a party or raid. Everyone needs the addon." },
    { "Host a table", "One player clicks Host Table in the lobby. Everyone else gets a pop-up asking to join: click Yes." },
    { "Sit down", "Click an empty chair at the table. Your chips come with you." },
    { "Play", "The host presses Deal Hand. Blinds, check, call, raise or fold, and the best five cards win. Short on players? The host can add bots." },
    { "Win the season", "Click Leaderboard in the lobby to see who's ahead. On the 1st of each month the top player wins a badge for their name and everyone starts again on 200 chips." },
}

local win

local function Build()
    local ok, f = pcall(CreateFrame, "Frame", "PokerWelcomeFrame", UIParent, "BackdropTemplate")
    if not ok then f = CreateFrame("Frame", "PokerWelcomeFrame", UIParent) end
    win = f
    f:Hide()
    f:SetSize(580, 520)
    f:SetPoint("CENTER", 0, 30)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
            tile = true, tileSize = 16, edgeSize = 32,
            insets = { left = 10, right = 10, top = 10, bottom = 10 },
        })
        f:SetBackdropColor(0.06, 0.04, 0.02, 0.97)
    end
    tinsert(UISpecialFrames, "PokerWelcomeFrame") -- Escape closes it

    -- Tavern art strip behind the title
    local art = f:CreateTexture(nil, "ARTWORK")
    art:SetTexture(MEDIA .. "lobby_bg")
    art:SetPoint("TOPLEFT", 12, -12)
    art:SetPoint("TOPRIGHT", -12, -12)
    art:SetHeight(96)
    art:SetTexCoord(0, 1, 0.30, 0.48)
    art:SetAlpha(0.55)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\MORPHEUS.TTF", 34, "THICKOUTLINE")
    title:SetPoint("TOP", 0, -26)
    title:SetTextColor(1, 0.82, 0.25)
    title:SetShadowOffset(2, -2)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetText("Welcome to Bounty Hold'em")

    local sub = f:CreateFontString(nil, "OVERLAY")
    sub:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetTextColor(0.9, 0.85, 0.7)
    sub:SetText("Texas Hold'em for your party, paid for by the mobs you kill.")

    -- Numbered steps
    local prev
    for i, s in ipairs(STEPS) do
        local num = f:CreateFontString(nil, "OVERLAY")
        num:SetFont("Fonts\\MORPHEUS.TTF", 22, "OUTLINE")
        num:SetTextColor(1, 0.82, 0.25)
        num:SetWidth(30)
        num:SetJustifyH("RIGHT")
        if prev then
            num:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", -38, -9)
        else
            num:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -122)
        end
        num:SetText(i .. ".")
        local body = f:CreateFontString(nil, "OVERLAY")
        body:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        body:SetTextColor(0.92, 0.92, 0.92)
        body:SetWidth(490)
        body:SetJustifyH("LEFT")
        body:SetSpacing(2)
        body:SetPoint("TOPLEFT", num, "TOPRIGHT", 8, -3)
        body:SetText(GOLD .. s[1] .. "|r   " .. s[2])
        prev = body
    end

    -- Buttons
    local play = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    play:SetSize(150, 30)
    play:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 20)
    play:SetText("Let's play")
    play:SetScript("OnClick", function()
        f:Hide()
        local role = PokerUI and PokerUI.RoleFrame
        if not (role and role:IsShown()) and SlashCmdList["POKER"] then SlashCmdList["POKER"]("") end
    end)
    local close = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    close:SetSize(150, 30)
    close:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 20)
    close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)

    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", -6, -6)

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
    b:SetNormalTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    b:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
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
