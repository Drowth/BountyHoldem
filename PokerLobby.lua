-- =========================================================================
-- Bounty Hold'em v1.1.8 by Lee
-- PokerLobby.lua: restyled welcome window
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- Bottom action bar with a large Join button and status line, chips on the
-- left, Host on the right and a small Settings gear. With media\lobby_bg.tga
-- installed, the art fills the window and the title uses the Warcraft font

local MEDIA = POKER_MEDIA
local NEW_ART = true -- Set true once media\lobby_bg.tga (1280 x 672, no text) is in place
local VERSION = "v1.1.8"

local function Style()
    local ui = PokerUI
    local role = ui and ui.RoleFrame -- This copy's own lobby, not whichever frame holds the global name
    if not role or not ui or role.pokerLobbyStyled then return end
    role.pokerLobbyStyled = true
    local inset = role.Inset or role

    -- == Background art ===================================================
    if NEW_ART and ui.roleBackground then
        local bg = ui.roleBackground
        bg:SetTexture(MEDIA .. "lobby_bg")
        bg:ClearAllPoints()
        bg:SetAllPoints(inset)
        bg:SetTexCoord(0, 1, 0, 1)

        local title = inset:CreateFontString(nil, "OVERLAY")
        title:SetFont("Fonts\\MORPHEUS.TTF", 64, "THICKOUTLINE")
        title:SetPoint("TOP", inset, "TOP", 0, -34)
        title:SetTextColor(1, 0.82, 0.25)
        title:SetShadowOffset(3, -3)
        title:SetShadowColor(0, 0, 0, 1)
        title:SetText("Bounty Hold'em")

        local sub = inset:CreateFontString(nil, "OVERLAY")
        sub:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        sub:SetPoint("TOP", title, "BOTTOM", 0, -2)
        sub:SetTextColor(0.9, 0.85, 0.7)
        sub:SetText("Every kill pays. Bring your party.   " .. VERSION)
    end

    -- == Bottom action bar ================================================
    local bar = CreateFrame("Frame", nil, role, "BackdropTemplate")
    bar:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(78)
    bar:SetFrameLevel(inset:GetFrameLevel() + 2)
    local shade = bar:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 1)
    if shade.SetGradient and CreateColor then
        pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0, 0, 0, 0.92), CreateColor(0, 0, 0, 0))
    else
        shade:SetAlpha(0.75)
    end
    local line = bar:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.8, 0.62, 0.2, 0.7)
    line:SetHeight(2)
    line:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)

    -- Join button, large and centred
    local join = ui.joinTableBtn
    if join then
        join:SetParent(bar)
        join:ClearAllPoints()
        join:SetSize(210, 40)
        join:SetPoint("TOP", bar, "TOP", 0, -10)
        join:SetFrameLevel(bar:GetFrameLevel() + 2)
        local fs = join:GetFontString()
        if fs then fs:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE") end
    end

    local status = bar:CreateFontString(nil, "OVERLAY")
    status:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    status:SetPoint("TOP", join or bar, "BOTTOM", 0, -6)

    -- Host button, right side
    local host = PokerHost and PokerHost.hostBtn
    local function PlaceHost()
        host = PokerHost and PokerHost.hostBtn
        if not host then return end
        host:SetParent(bar)
        host:ClearAllPoints()
        host:SetSize(130, 30)
        host:SetPoint("RIGHT", bar, "RIGHT", -14, 4)
        host:SetFrameLevel(bar:GetFrameLevel() + 2)
    end
    PlaceHost()

    -- Chip balance, left side
    local Econ = PokerEconomy
    local chips = bar:CreateFontString(nil, "OVERLAY")
    chips:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    chips:SetPoint("LEFT", bar, "LEFT", 16, 8)
    local chipsSub = bar:CreateFontString(nil, "OVERLAY")
    chipsSub:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    chipsSub:SetTextColor(0.7, 0.7, 0.7)
    chipsSub:SetPoint("TOPLEFT", chips, "BOTTOMLEFT", 0, -3)
    chipsSub:SetText("your chips")
    if Econ and Econ.balanceText then Econ.balanceText:Hide() end

    -- Settings gear, top right corner
    local settings = ui.roleScaleBtn
    if settings then
        settings:ClearAllPoints()
        settings:SetSize(30, 30)
        settings:SetPoint("TOPRIGHT", role, "TOPRIGHT", -10, -30)
        settings:SetText("")
        local icon = settings:CreateTexture(nil, "OVERLAY")
        icon:SetTexture("Interface\\Icons\\Trade_Engineering")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetPoint("TOPLEFT", 5, -5)
        icon:SetPoint("BOTTOMRIGHT", -5, 5)
        settings:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Volume", 1, 1, 1)
            GameTooltip:AddLine("Window size is the bar on the right edge", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        settings:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Refresh chips and status
    local acc = 0
    role:HookScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.3 then return end
        acc = 0
        if not host then PlaceHost() end
        if Econ and Econ.Balance then
            chips:SetText(("|T%s1chip:20:20:0:0|t |cffffd100%d|r"):format(MEDIA, Econ.Balance()))
        end
        local hosting = PokerHost and PokerHost.active
        if join and join:IsEnabled() then
            status:SetText(hosting and "|cff33ff33Your table is open. Join it, then pick a seat.|r"
                or "|cff33ff33A table is open. Join now!|r")
        else
            status:SetText("|cffbbbbbbNo table open yet. Host one, or wait for a friend to.|r")
        end
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    -- Host and Economy also hook PLAYER_LOGIN; style the lobby after them
    C_Timer.After(0.2, function()
        local ok, err = pcall(Style)
        if not ok then print("|cff00cccc[Poker]|r Lobby style failed: " .. tostring(err)) end
    end)
end)
