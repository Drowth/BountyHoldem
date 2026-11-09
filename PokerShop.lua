-- =========================================================================
-- Bounty Hold'em v1.2.2 by Lee
-- PokerShop.lua: chip shop for lobby scenes and table felts
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- Chips reset every season, so the shop is where they turn into something
-- that lasts. Purchases are account-wide in PokerBankDB.owned and survive
-- every reset. Your lobby scene is your own view; the host's felt is what
-- everyone at their table sees

local N = PokerNet
local Econ = PokerEconomy
local MEDIA = POKER_MEDIA

PokerShop = PokerShop or {}
local Shop = PokerShop

-- == Catalogue ============================================================
local SCENES = {
    { id = "tavern", name = "Tavern",        tex = "lobby_bg",   price = 0 },
    { id = "lodge",  name = "Snowy Lodge",   tex = "lobby_bg_1", price = 1500 },
    { id = "glade",  name = "Moonlit Glade", tex = "lobby_bg_5", price = 2500 },
    { id = "ship",   name = "Pirate Ship",   tex = "lobby_bg_2", price = 3000 },
    { id = "crypt",  name = "Haunted Crypt", tex = "lobby_bg_4", price = 5000 },
    { id = "casino", name = "Goblin Casino", tex = "lobby_bg_3", price = 15000 },
}
local FELTS = {
    { id = "green",   name = "Classic Green", tex = nil,             price = 0 },
    { id = "crimson", name = "Crimson",       tex = "felt_crimson",  price = 1000 },
    { id = "royal",   name = "Royal Blue",    tex = "felt_royal",    price = 1000 },
    { id = "violet",  name = "Violet",        tex = "felt_violet",   price = 2500 },
    { id = "onyx",    name = "Onyx",          tex = "felt_onyx",     price = 8000 },
}
local BY_ID = {}
for _, it in ipairs(SCENES) do it.kind = "scene" BY_ID[it.id] = it end
for _, it in ipairs(FELTS) do it.kind = "felt" BY_ID[it.id] = it end

local function Bank()
    PokerBankDB = PokerBankDB or {}
    PokerBankDB.owned = PokerBankDB.owned or {}
    return PokerBankDB
end

local function Owns(it) return it.price == 0 or Bank().owned[it.id] == true end

local function Equipped(kind)
    local b = Bank()
    local id = kind == "scene" and b.scene or b.felt
    local it = id and BY_ID[id]
    if it and it.kind == kind and Owns(it) then return it end
    return kind == "scene" and SCENES[1] or FELTS[1]
end

function Shop.SceneTexture() return Equipped("scene").tex end

-- == Table felt ===========================================================
-- Cut to the felt oval of pokertablegraphic_player (1920 art drawn at 935,
-- centred 0,-12 on the table): oval box 434,705 to 1489,1200 in art pixels
local feltTex
local hostFelt -- Felt id sent by another player's table, if we're at it

local function ActiveFelt()
    if hostFelt and not (PokerHost and PokerHost.active) then
        local it = BY_ID[hostFelt]
        if it and it.kind == "felt" then return it end
    end
    return Equipped("felt")
end

local function ApplyFelt()
    local tbl = PokerUI and PokerUI.TableFrame
    if not tbl then return end
    if not feltTex then
        local k = 935 / 1920
        feltTex = tbl:CreateTexture(nil, "ARTWORK", nil, 1)
        feltTex:SetSize(1055 * k, 495 * k)
        feltTex:SetPoint("CENTER", tbl, "CENTER", -467.5 + 961.5 * k, 455.5 - 952.5 * k)
    end
    local it = ActiveFelt()
    if it.tex then
        feltTex:SetTexture(MEDIA .. it.tex)
        feltTex:Show()
    else
        feltTex:Hide()
    end
end

local function SendFelt()
    if PokerHost and PokerHost.active then N.Send("FELT:" .. Equipped("felt").id) end
end

N.AddCommandHandler(function(cmd, sender)
    local id = cmd:match("^FELT:(%w+)$")
    if id then
        if N.ShortName(sender) ~= N.MyName() then hostFelt = id end
        ApplyFelt()
        return
    end
    if cmd == "TABLE_CLOSED" then
        hostFelt = nil
        ApplyFelt()
    elseif cmd == "REQUEST_SNAPSHOT" or cmd:match("^PLAYER_SAT_DOWN:") then
        SendFelt()
    end
end)

-- == Buying and equipping =================================================
local win, Refresh

local function Equip(it)
    local b = Bank()
    if it.kind == "scene" then
        b.scene = it.id
        if PokerUI and PokerUI.ShowLobbyScene then PokerUI.ShowLobbyScene() end
    else
        b.felt = it.id
        ApplyFelt()
        SendFelt()
    end
    PlaySoundFile(MEDIA .. "chips.MP3", "SFX")
    if Refresh then Refresh() end
end

local pendingBuy
StaticPopupDialogs["POKER_SHOP_BUY"] = {
    text = "Buy %s for %s chips?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
        local it = pendingBuy
        pendingBuy = nil
        if not it or Owns(it) then return end
        local ok, why = Econ.Spend(it.price)
        if not ok then
            print("|cff00cccc[Poker]|r " .. (why or "Can't buy that right now."))
            return
        end
        Bank().owned[it.id] = true
        print(("|cff00cccc[Poker]|r Bought |cffffd100%s|r. It's yours for good, even after the season resets."):format(it.name))
        Equip(it)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function Commas(n)
    local s = tostring(math.floor(n))
    while true do
        local r, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = r
        if k == 0 then return s end
    end
end

local function OnItemClick(it)
    if Owns(it) then Equip(it) return end
    if Econ.IsSeated and Econ.IsSeated() then
        print("|cff00cccc[Poker]|r Stand up from the table before shopping.")
        return
    end
    if Econ.Balance() < it.price then
        print(("|cff00cccc[Poker]|r %s costs %s chips. You have %s."):format(it.name, Commas(it.price), Commas(Econ.Balance())))
        return
    end
    pendingBuy = it
    StaticPopup_Show("POKER_SHOP_BUY", it.name, Commas(it.price))
end

-- == Shop window ==========================================================
local CARD_W, CARD_H = 196, 158
local tab = "scene"

local function Build()
    local ok, f = pcall(CreateFrame, "Frame", "PokerShopFrame", UIParent, "BackdropTemplate")
    if not ok then f = CreateFrame("Frame", "PokerShopFrame", UIParent) end
    win = f
    f:Hide()
    f:SetSize(3 * CARD_W + 4 * 12, 2 * CARD_H + 150)
    f:SetPoint("CENTER", 0, 20)
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
    tinsert(UISpecialFrames, "PokerShopFrame")

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\MORPHEUS.TTF", 30, "THICKOUTLINE")
    title:SetTextColor(1, 0.82, 0.25)
    title:SetPoint("TOP", 0, -18)
    title:SetText("Shop")

    f.balance = f:CreateFontString(nil, "OVERLAY")
    f.balance:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    f.balance:SetPoint("TOPLEFT", 22, -26)

    f.hint = f:CreateFontString(nil, "OVERLAY")
    f.hint:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    f.hint:SetTextColor(0.75, 0.75, 0.75)
    f.hint:SetPoint("BOTTOM", 0, 18)

    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", -6, -6)

    -- Tabs
    f.tabs = {}
    for i, t in ipairs({ { "scene", "Lobby scenes" }, { "felt", "Table felts" } }) do
        local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
        b:SetSize(150, 26)
        b:SetPoint("TOP", f, "TOP", (i == 1) and -80 or 80, -60)
        b:SetText(t[2])
        b:SetScript("OnClick", function() tab = t[1] Refresh() end)
        b.kind = t[1]
        f.tabs[i] = b
    end

    -- Item cards
    f.cards = {}
    for i = 1, 6 do
        local c = CreateFrame("Frame", nil, f, "BackdropTemplate")
        c:SetSize(CARD_W, CARD_H)
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        c:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + col * (CARD_W + 12), -96 - row * (CARD_H + 10))
        if c.SetBackdrop then
            c:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            c:SetBackdropColor(0, 0, 0, 0.6)
        end
        c.pic = c:CreateTexture(nil, "ARTWORK")
        c.pic:SetPoint("TOP", 0, -6)
        c.pic:SetSize(CARD_W - 12, 92)
        c.name = c:CreateFontString(nil, "OVERLAY")
        c.name:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        c.name:SetPoint("TOP", c.pic, "BOTTOM", 0, -4)
        c.btn = CreateFrame("Button", nil, c, "GameMenuButtonTemplate")
        c.btn:SetSize(CARD_W - 40, 24)
        c.btn:SetPoint("BOTTOM", 0, 6)
        f.cards[i] = c
    end

    f:SetScript("OnShow", function() Refresh() end)
end

Refresh = function()
    if not win or not win:IsShown() then return end
    win.balance:SetText(("|T%s1chip:16:16:0:0|t |cffffd100%s|r"):format(MEDIA, Commas(Econ.Balance())))
    for _, b in ipairs(win.tabs) do
        local fs = b:GetFontString()
        if fs then fs:SetTextColor(b.kind == tab and 1 or 0.6, b.kind == tab and 0.82 or 0.6, b.kind == tab and 0.25 or 0.6) end
    end
    local list = tab == "scene" and SCENES or FELTS
    local current = Equipped(tab)
    for i, c in ipairs(win.cards) do
        local it = list[i]
        c:SetShown(it ~= nil)
        if it then
            if it.kind == "scene" then
                c.pic:SetTexture(MEDIA .. it.tex)
                c.pic:SetTexCoord(0, 1, 0.12, 0.88)
            elseif it.tex then
                c.pic:SetTexture(MEDIA .. it.tex)
                c.pic:SetTexCoord(0.15, 0.85, 0.2, 0.8)
            else
                c.pic:SetColorTexture(0.06, 0.32, 0.14, 1)
            end
            c.name:SetText(it.name)
            local owned = Owns(it)
            if current.id == it.id then
                c.btn:SetText("In use")
                c.btn:Disable()
            elseif owned then
                c.btn:SetText("Use")
                c.btn:Enable()
            else
                c.btn:SetText("Buy  " .. Commas(it.price))
                c.btn:Enable()
            end
            c.btn:SetScript("OnClick", function() OnItemClick(it) end)
            if c.SetBackdropBorderColor then
                if current.id == it.id then c:SetBackdropBorderColor(1, 0.82, 0.25)
                else c:SetBackdropBorderColor(0.4, 0.35, 0.3) end
            end
        end
    end
    win.hint:SetText(tab == "scene"
        and "Your lobby scene is just for you. Purchases are kept forever, even when chips reset."
        or "Everyone at your table sees the felt you use when you host. Purchases are kept forever.")
end

function PokerShop_Toggle()
    if not win then Build() end
    win:SetShown(not win:IsShown())
end

-- Keep the balance current while the shop is open
local oldChanged = Econ.OnBalanceChanged
Econ.OnBalanceChanged = function(...)
    if oldChanged then oldChanged(...) end
    if Refresh then Refresh() end
end

-- == Lobby button =========================================================
local function AddLobbyButton()
    local ui = PokerUI
    local role = ui and ui.RoleFrame
    if not role then return end
    local b = CreateFrame("Button", nil, role)
    b:SetSize(30, 30)
    local gear = ui.roleScaleBtn
    if gear then
        b:SetPoint("RIGHT", gear, "LEFT", -42, 0)
    else
        b:SetPoint("TOPRIGHT", role, "TOPRIGHT", -82, -30)
    end
    b:SetFrameLevel(role:GetFrameLevel() + 25)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MEDIA .. "step_open")
    icon:SetAllPoints()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(MEDIA .. "step_open")
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.35)
    b:SetScript("OnClick", PokerShop_Toggle)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Shop", 1, 1, 1)
        GameTooltip:AddLine("Spend chips on lobby scenes and table felts. They're yours for good.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    C_Timer.After(0.5, function()
        local ok, err = pcall(function()
            AddLobbyButton()
            ApplyFelt()
            local tbl = PokerUI and PokerUI.TableFrame
            if tbl then tbl:HookScript("OnShow", ApplyFelt) end
            if PokerHost and PokerHost.Open then
                hooksecurefunc(PokerHost, "Open", function() C_Timer.After(0.5, SendFelt) end)
            end
            if PokerUI and PokerUI.ShowLobbyScene then PokerUI.ShowLobbyScene() end
        end)
        if not ok then print("|cff00cccc[Poker]|r Shop failed: " .. tostring(err)) end
    end)
end)
