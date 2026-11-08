-- =========================================================================
-- Bounty Hold'em v1.1.8 by Lee
-- PokerTableCues.lua: big action callouts and "pick a seat" hints
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- * Every check, call, raise, fold and all-in pops up in large letters on
--   that player's seat, so bot moves are hard to miss
-- * Until you sit down, empty seats pulse with SIT and the felt says how to join

local N = PokerNet
local GOLD_ICON = " |T" .. POKER_MEDIA .. "1chip:16:16:0:0|t"

local tbl
local callouts = {}
local hint
local sitLabels = {}

-- == Action callouts ======================================================
local STYLE = {
    FOLD   = { r = 0.75, g = 0.75, b = 0.75, text = "FOLD" },
    CHECK  = { r = 0.55, g = 0.85, b = 1.00, text = "CHECK" },
    CALL   = { r = 0.40, g = 1.00, b = 0.40, text = "CALL" },
    RAISE  = { r = 1.00, g = 0.82, b = 0.20, text = "RAISE" },
    ALL_IN = { r = 1.00, g = 0.35, b = 0.25, text = "ALL IN" },
}

local function SeatOf(name)
    local seats = occupiedSeats
    if not seats or not name then return nil end
    for s = 1, 9 do
        if seats[s] and N.ShortName(seats[s]) == N.ShortName(name) then return s end
    end
end

local function GetCallout(seat)
    local c = callouts[seat]
    if c then return c end
    c = CreateFrame("Frame", nil, tbl)
    c:SetSize(220, 60)
    c:SetFrameLevel(tbl:GetFrameLevel() + 40)
    c.text = c:CreateFontString(nil, "OVERLAY")
    c.text:SetFont("Fonts\\MORPHEUS.TTF", 26, "THICKOUTLINE")
    c.text:SetPoint("CENTER")
    c.text:SetShadowOffset(2, -2)
    c.text:SetShadowColor(0, 0, 0, 1)
    c:Hide()
    callouts[seat] = c
    return c
end

-- Pops in large, holds, then fades
local function ShowCallout(seat, kind, amount)
    local style = STYLE[kind]
    local marker = seatMarkers and seatMarkers[seat]
    if not style or not marker or not marker.button or not tbl:IsShown() then return end
    local c = GetCallout(seat)
    c:ClearAllPoints()
    c:SetPoint("CENTER", marker.button, "CENTER", 0, 30)
    local label = style.text
    if amount and kind ~= "FOLD" and kind ~= "CHECK" then label = label .. " " .. amount .. GOLD_ICON end
    c.text:SetText(label)
    c.text:SetTextColor(style.r, style.g, style.b)
    c:SetAlpha(1)
    c:Show()
    local t = 0
    c:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        if t < 0.15 then
            self:SetScale(1.6 - 4 * t) -- 1.6 down to 1.0
        elseif t < 1.9 then
            self:SetScale(1)
        elseif t < 2.5 then
            self:SetAlpha(1 - (t - 1.9) / 0.6)
        else
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)
end

local function OnCommand(cmd)
    if not tbl then return end
    local kind, name, amount = cmd:match("^(%u[%u_]*):([^:]+):(%d+)$")
    if not kind then
        kind, name = cmd:match("^(%u+):([^:]+)$")
    end
    if not kind or not STYLE[kind] then return end
    local seat = SeatOf(name)
    if seat then ShowCallout(seat, kind, amount) end
end

-- == Seat hints ===========================================================
local function UpdateHints()
    local seated = playerSeat ~= nil
    local anyFree = false
    for s = 1, 9 do
        local marker = seatMarkers and seatMarkers[s]
        local label = sitLabels[s]
        if marker and label then
            local free = not marker.occupied
            label:SetShown(not seated and free)
            if free then anyFree = true end
        end
    end
    hint:SetShown(not seated and anyFree)
end

local function Build()
    tbl = (PokerUI and PokerUI.TableFrame) or _G["PokerTableFrame"]
    if not tbl or not seatMarkers then return end

    hint = tbl:CreateFontString(nil, "OVERLAY")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    hint:SetTextColor(1, 0.82, 0.25)
    hint:SetPoint("CENTER", tbl, "CENTER", 0, -100) -- Under the board cards
    hint:SetText("Click an empty chair to sit down")

    for s = 1, 9 do
        local marker = seatMarkers[s]
        local pos = portraitPositions and portraitPositions[s]
        if marker and marker.button and pos then
            local holder = CreateFrame("Frame", nil, tbl)
            holder:SetSize(44, 20)
            holder:SetPoint("CENTER", tbl, "CENTER", pos.x, pos.y)
            holder:SetFrameLevel(marker.button:GetFrameLevel() + 5)
            holder:EnableMouse(false) -- Clicks go through to the seat
            local label = holder:CreateFontString(nil, "OVERLAY")
            label:SetFont("Fonts\\FRIZQT__.TTF", 14, "THICKOUTLINE")
            label:SetTextColor(0.4, 1, 0.4)
            label:SetPoint("CENTER")
            label:SetText("SIT")
            holder:Hide()
            sitLabels[s] = holder

            marker.button:HookScript("OnEnter", function(self)
                if playerSeat or marker.occupied then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Click to sit here", 1, 1, 1)
                GameTooltip:Show()
            end)
            marker.button:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    -- Pulse the SIT labels and keep hints in step with the seats
    local acc, clock = 0, 0
    tbl:HookScript("OnUpdate", function(_, dt)
        clock = clock + dt
        local a = 0.55 + 0.45 * math.abs(math.sin(clock * 3))
        for _, holder in pairs(sitLabels) do holder:SetAlpha(a) end
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        UpdateHints()
    end)
    UpdateHints()
end

N.AddCommandHandler(OnCommand)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    C_Timer.After(0.4, function()
        local ok, err = pcall(Build)
        if not ok then print("|cff00cccc[Poker]|r Table cues failed: " .. tostring(err)) end
    end)
end)
