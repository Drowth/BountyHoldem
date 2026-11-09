-- =========================================================================
-- Bounty Hold'em v1.2.3 by Lee
-- PokerSizeBar.lua: small drag bar on the window edge that sets its size
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- One slim vertical bar inside the right edge of the lobby and of the table.
-- Drag up for bigger, down for smaller; the size applies when you let go and
-- is saved per character

local MIN_SCALE, MAX_SCALE = 0.5, 1.5
local BAR_HEIGHT = 120

local function Clamp(v)
    if v < MIN_SCALE then return MIN_SCALE end
    if v > MAX_SCALE then return MAX_SCALE end
    return v
end

-- Builds a bar on frame; apply(scale, keepPlace) resizes it, dbKey stores it
local function BuildBar(frame, apply, dbKey, xOff, yOff)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(18, BAR_HEIGHT + 30)
    holder:SetPoint("RIGHT", frame, "RIGHT", xOff, yOff)
    holder:SetFrameLevel(frame:GetFrameLevel() + 20)

    -- Slider runs from -MAX at the top to -MIN at the bottom, so up means bigger
    local bar = CreateFrame("Slider", nil, holder)
    bar:SetOrientation("VERTICAL")
    bar:SetSize(10, BAR_HEIGHT)
    bar:SetPoint("BOTTOM", holder, "BOTTOM", 0, 0)
    bar:SetMinMaxValues(-MAX_SCALE, -MIN_SCALE)
    bar:SetValueStep(0.01)
    bar:SetObeyStepOnDrag(true)
    bar:EnableMouse(true)

    -- Track: dark groove with a thin gold edge
    local edge = bar:CreateTexture(nil, "BACKGROUND")
    edge:SetColorTexture(0.8, 0.62, 0.2, 0.6)
    edge:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, 0)
    edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -2, 0)
    local groove = bar:CreateTexture(nil, "BORDER")
    groove:SetColorTexture(0, 0, 0, 0.85)
    groove:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
    groove:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)

    -- Thumb: a small gold chip
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(POKER_MEDIA .. "1chip")
    thumb:SetSize(16, 16)
    bar:SetThumbTexture(thumb)

    -- Label above and live value while dragging
    local label = holder:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    label:SetTextColor(1, 0.82, 0.25)
    label:SetPoint("TOP", holder, "TOP", 0, -2)
    label:SetText("SIZE")
    local value = holder:CreateFontString(nil, "OVERLAY")
    value:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    value:SetTextColor(1, 1, 1)
    value:SetPoint("RIGHT", bar, "LEFT", -4, 0)
    value:Hide()

    local syncing = false
    local function Sync()
        syncing = true
        bar:SetValue(-Clamp(frame:GetScale()))
        syncing = false
    end

    bar:SetScript("OnValueChanged", function(_, v)
        if syncing then return end
        value:SetText(string.format("%.2fx", -v))
        value:Show()
    end)
    bar:SetScript("OnMouseUp", function()
        local scale = Clamp(-bar:GetValue())
        value:Hide()
        apply(scale, true)
        if PokerChipsDB then PokerChipsDB[dbKey] = scale end
        Sync() -- Bar moved with the window; put the thumb back on the saved value
    end)
    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Window size", 1, 1, 1)
        GameTooltip:AddLine("Drag up for bigger, down for smaller", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame:HookScript("OnShow", Sync)

    -- Restore the saved size
    local saved = PokerChipsDB and tonumber(PokerChipsDB[dbKey])
    if saved then apply(Clamp(saved), false) end
    Sync()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    -- After PokerLobby has restyled the lobby (it runs at +0.2s)
    C_Timer.After(0.3, function()
        local ui = PokerUI
        if not ui then return end
        local ok, err = pcall(function()
            if ui.RoleFrame and ui.ApplyPokerScale then
                BuildBar(ui.RoleFrame, ui.ApplyPokerScale, "lobbyScale", -8, 20)
            end
            if ui.TableFrame and ui.ApplyTablePokerScale then
                BuildBar(ui.TableFrame, ui.ApplyTablePokerScale, "tableScale", -8, 0)
            end
        end)
        if not ok then print("|cff00cccc[Poker]|r Size bar failed: " .. tostring(err)) end
    end)
end)
