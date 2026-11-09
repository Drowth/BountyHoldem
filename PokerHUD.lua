-- =========================================================================
-- Bounty Hold'em v1.2.3 by Lee
-- PokerHUD.lua: large board, hand panel, winner banner and chip popups
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- Puts the key information front and centre:
--   * Large board cards on the felt with a FLOP / TURN / RIVER callout
--   * Hand panel under the table: hole cards, current hand name, stack and a
--     YOUR TURN alert
--   * Winner banner at the end of each hand
--   * +/- chip popups on your stack and the chip pot

local N = PokerNet
local E = PokerEval

local MEDIA = POKER_MEDIA
local GOLD = "|cffffd100"

local HUD = {}
PokerHUD = HUD

local tbl          -- Table frame (PokerTableFrame)
local boardFrame, boardCards = nil, {}
local streetText
local handPanel, handCards, handName, stackText, turnText
local banner, bannerText, bannerSub
local actionZone, waitText, dockedBox

-- Move poker.lua's Fold / Check / Raise bar from the table into the dock
local function DockActions()
    if dockedBox or not actionZone then return end
    local ui = PokerUI
    local box = ui and ui.decisionBox
    if not box then return end
    box:SetParent(actionZone)
    box:ClearAllPoints()
    box:SetPoint("CENTER", actionZone, "CENTER", 0, 0)
    box:SetScale(1.22)
    box:SetFrameLevel(handPanel:GetFrameLevel() + 6)
    if box.SetBackdropColor then
        box:SetBackdropColor(0, 0, 0, 0)
        box:SetBackdropBorderColor(0, 0, 0, 0)
    end
    dockedBox = box
end

local state = {
    hole = {},          -- Our hole cards
    board = {},         -- Board cards
    folded = false,
    stack = nil,        -- Last known table stack
    handStartStack = nil,
    lastCategory = nil, -- Filled from SHOWDOWN_POPUP
    lastWinnerName = nil,
    turnSeat = nil,
    seatNames = {},
}

local function Me() return N.MyName() end

-- == Animation helpers ====================================================
-- Hand-rolled, since animation APIs differ between clients
local function FadeOutLater(frame, hold, fade)
    frame.fadeT = -(hold or 3)
    frame.fadeLen = fade or 0.6
    frame:SetAlpha(1)
    frame:Show()
    frame:SetScript("OnUpdate", function(self, dt)
        self.fadeT = self.fadeT + dt
        if self.fadeT < 0 then return end
        local a = 1 - self.fadeT / self.fadeLen
        if a <= 0 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
        else
            self:SetAlpha(a)
        end
    end)
end

local floatPool = {}
local function FloatText(anchor, text, r, g, b, size)
    if not anchor then return end
    local f = table.remove(floatPool)
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(160, 30)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetPoint("CENTER")
    end
    f.text:SetFont("Fonts\\FRIZQT__.TTF", size or 22, "THICKOUTLINE")
    f.text:SetText(text)
    f.text:SetTextColor(r, g, b)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", anchor, "TOP", 0, 0)
    f:SetAlpha(1)
    f:Show()
    local t = 0
    f:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        self:ClearAllPoints()
        self:SetPoint("BOTTOM", anchor, "TOP", 0, t * 40)
        if t > 1.2 then self:SetAlpha(math.max(0, 1 - (t - 1.2) / 0.8)) end
        if t > 2 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            floatPool[#floatPool + 1] = self
        end
    end)
end

-- == Card widgets =========================================================
local function MakeCard(parent, w, h)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    c:SetSize(w, h)
    c.tex = c:CreateTexture(nil, "ARTWORK")
    c.tex:SetAllPoints()
    c.glow = c:CreateTexture(nil, "OVERLAY")
    c.glow:SetPoint("TOPLEFT", -4, 4)
    c.glow:SetPoint("BOTTOMRIGHT", 4, -4)
    c.glow:SetColorTexture(1, 0.82, 0, 0.35)
    c.glow:Hide()
    c:Hide()
    return c
end

local function SetCard(c, code)
    if not code then
        c:Hide()
        c.code = nil
        c.glow:Hide()
        return
    end
    c.code = code
    c.tex:SetTexture(MEDIA .. code)
    c:SetAlpha(1)
    c.glow:Hide()
    c:Show()
end

-- Small drop-in pop when a card appears
local function PopIn(c, delay)
    c:SetAlpha(0)
    local t = -(delay or 0)
    c:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        if t < 0 then return end
        local p = math.min(1, t / 0.25)
        self:SetAlpha(p)
        self:SetScale(1.25 - 0.25 * p)
        if p >= 1 then self:SetScript("OnUpdate", nil) self:SetScale(1) end
    end)
end

-- == Build ================================================================
local function Build()
    tbl = _G["PokerTableFrame"]
    if not tbl or boardFrame then return end

    -- Board: five large cards over the felt
    boardFrame = CreateFrame("Frame", nil, tbl)
    boardFrame:SetSize(300, 100)
    boardFrame:SetPoint("CENTER", tbl, "CENTER", 0, -30)
    boardFrame:SetFrameLevel(tbl:GetFrameLevel() + 30)
    for i = 1, 5 do
        local c = MakeCard(boardFrame, 46, 92)
        c:SetPoint("CENTER", boardFrame, "CENTER", (i - 3) * 52, 0)
        boardCards[i] = c
    end

    streetText = boardFrame:CreateFontString(nil, "OVERLAY")
    streetText:SetFont("Fonts\\FRIZQT__.TTF", 30, "THICKOUTLINE")
    streetText:SetPoint("BOTTOM", boardFrame, "TOP", 0, 6)
    streetText:SetTextColor(1, 0.82, 0)
    local streetHolder = CreateFrame("Frame", nil, boardFrame)
    streetHolder:SetAllPoints(streetText)
    streetText:SetParent(streetHolder)
    boardFrame.streetHolder = streetHolder
    streetHolder:Hide()

    -- Dock under the table: hand on the left, actions on the right
    handPanel = CreateFrame("Frame", "PokerYourHandPanel", tbl, "BackdropTemplate")
    handPanel:SetSize(780, 140)
    handPanel:SetPoint("TOP", tbl, "BOTTOM", 0, -2)
    handPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    handPanel:SetBackdropColor(0, 0, 0, 0.88)
    handPanel:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)

    local title = handPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -10)
    title:SetText("YOUR HAND")

    handCards = {}
    for i = 1, 2 do
        local c = MakeCard(handPanel, 50, 100)
        c:SetPoint("TOPLEFT", handPanel, "TOPLEFT", 14 + (i - 1) * 54, -28)
        handCards[i] = c
    end

    handName = handPanel:CreateFontString(nil, "OVERLAY")
    handName:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    handName:SetPoint("TOPLEFT", handPanel, "TOPLEFT", 132, -34)
    handName:SetWidth(220)
    handName:SetJustifyH("LEFT")
    handName:SetText("")

    stackText = handPanel:CreateFontString(nil, "OVERLAY")
    stackText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    stackText:SetPoint("TOPLEFT", handName, "BOTTOMLEFT", 0, -10)
    stackText:SetJustifyH("LEFT")

    turnText = handPanel:CreateFontString(nil, "OVERLAY")
    turnText:SetFont("Fonts\\FRIZQT__.TTF", 16, "THICKOUTLINE")
    turnText:SetPoint("TOPLEFT", stackText, "BOTTOMLEFT", 0, -10)
    turnText:SetTextColor(0.3, 1, 0.3)
    turnText:SetText("")

    -- Divider and action area
    local div = handPanel:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(0.6, 0.5, 0.2, 0.6)
    div:SetSize(2, 112)
    div:SetPoint("LEFT", handPanel, "LEFT", 372, 0)

    actionZone = CreateFrame("Frame", nil, handPanel)
    actionZone:SetPoint("TOPLEFT", handPanel, "TOPLEFT", 380, -6)
    actionZone:SetPoint("BOTTOMRIGHT", handPanel, "BOTTOMRIGHT", -8, 6)

    waitText = actionZone:CreateFontString(nil, "OVERLAY")
    waitText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    waitText:SetPoint("CENTER")
    waitText:SetTextColor(0.75, 0.75, 0.75)
    waitText:SetText("")

    DockActions()

    handPanel:Hide()

    -- Keep the dock in sync with the seat and action bar
    local acc = 0
    tbl:HookScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        if not dockedBox then DockActions() end
        local seated = playerSeat ~= nil or state.hole[1] ~= nil
        if seated ~= handPanel:IsShown() then handPanel:SetShown(seated) end
        if not seated then return end
        local acting = dockedBox and dockedBox:IsShown()
        if acting then
            waitText:SetText("")
        elseif state.folded then
            waitText:SetText("You folded. Waiting for the hand to finish")
        elseif not (state.hole[1] or (handCards and handCards[1]:IsShown())) then
            waitText:SetText("Waiting for the next hand")
        elseif state.turnSeat and state.seatNames[state.turnSeat] then
            waitText:SetText("Waiting for " .. state.seatNames[state.turnSeat] .. "...")
        else
            waitText:SetText("Waiting...")
        end
    end)

    -- Winner banner across the table centre
    banner = CreateFrame("Frame", nil, tbl, "BackdropTemplate")
    banner:SetSize(620, 74)
    banner:SetPoint("CENTER", tbl, "CENTER", 0, 70)
    banner:SetFrameLevel(tbl:GetFrameLevel() + 60)
    banner:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    banner:SetBackdropColor(0, 0, 0, 0.88)
    banner:SetBackdropBorderColor(1, 0.82, 0, 1)
    bannerText = banner:CreateFontString(nil, "OVERLAY")
    bannerText:SetFont("Fonts\\FRIZQT__.TTF", 24, "THICKOUTLINE")
    bannerText:SetPoint("TOP", banner, "TOP", 0, -12)
    bannerSub = banner:CreateFontString(nil, "OVERLAY")
    bannerSub:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    bannerSub:SetPoint("TOP", bannerText, "BOTTOM", 0, -6)
    banner:Hide()

    tbl:HookScript("OnHide", function() handPanel:Hide() end)
    tbl:HookScript("OnShow", function() if playerSeat or state.hole[1] then handPanel:Show() end end)
end

-- == Updates ==============================================================
local RANK_WORD = { ["2"] = "Twos", ["3"] = "Threes", ["4"] = "Fours", ["5"] = "Fives", ["6"] = "Sixes",
    ["7"] = "Sevens", ["8"] = "Eights", ["9"] = "Nines", ["10"] = "Tens", J = "Jacks", Q = "Queens",
    K = "Kings", A = "Aces" }
local RANK_HIGH = { ["2"] = "Two", ["3"] = "Three", ["4"] = "Four", ["5"] = "Five", ["6"] = "Six",
    ["7"] = "Seven", ["8"] = "Eight", ["9"] = "Nine", ["10"] = "Ten", J = "Jack", Q = "Queen",
    K = "King", A = "Ace" }

local function Rank(code) return code and code:sub(1, -2) end

local function DescribeHand()
    local h = state.hole
    if not h[1] or not h[2] then return "" end
    if #state.board == 0 then
        if Rank(h[1]) == Rank(h[2]) then return "Pocket " .. RANK_WORD[Rank(h[1])] end
        local v1 = E.ParseCard(h[1])
        local v2 = E.ParseCard(h[2])
        local hi = v1 >= v2 and h[1] or h[2]
        local suited = h[1]:sub(-1) == h[2]:sub(-1)
        return RANK_HIGH[Rank(hi)] .. " high" .. (suited and ", suited" or "")
    end
    local cards = { h[1], h[2] }
    for _, c in ipairs(state.board) do cards[#cards + 1] = c end
    if #cards < 5 then return "" end
    local best = E.Evaluate(cards)
    local name = best.name
    if best.category == 1 or best.category == 3 or best.category == 7 then
        -- Name the rank, e.g. "Pair of Tens", "Three Tens"
        local counts = {}
        for _, c in ipairs(best.cards) do local r = Rank(c) counts[r] = (counts[r] or 0) + 1 end
        for r, n in pairs(counts) do
            if n >= 2 then
                if best.category == 1 then name = "Pair of " .. RANK_WORD[r]
                elseif best.category == 3 then name = "Three " .. RANK_WORD[r]
                else name = "Four " .. RANK_WORD[r] end
            end
        end
    end
    return name, best
end

local function RefreshHand()
    if not handPanel then return end
    if not state.hole[1] then
        SetCard(handCards[1], nil)
        SetCard(handCards[2], nil)
        handName:SetText("|cff999999No cards yet|r")
        stackText:SetText(state.stack and ("Chips: |cffffff00%d|r"):format(state.stack) or "")
        return
    end
    for i = 1, 2 do
        SetCard(handCards[i], state.hole[i])
        handCards[i]:SetAlpha(state.folded and 0.35 or 1)
    end
    local name = DescribeHand()
    if state.folded then
        handName:SetText("|cff999999Folded|r")
    else
        handName:SetText(GOLD .. (name or "") .. "|r")
    end
    local stack = state.stack or 0
    local delta = state.handStartStack and (stack - state.handStartStack) or 0
    local d = ""
    if delta > 0 then d = ("  |cff33ff33(+%d this hand)|r"):format(delta)
    elseif delta < 0 then d = ("  |cffff5555(%d this hand)|r"):format(delta) end
    stackText:SetText(("Chips: |cffffff00%d|r%s"):format(stack, d))
end

local function ClearBoard()
    wipe(state.board)
    for i = 1, 5 do SetCard(boardCards[i], nil) end
    if boardFrame then boardFrame.streetHolder:Hide() end
end

local function ShowStreet(label)
    streetText:SetText(label)
    FadeOutLater(boardFrame.streetHolder, 1.6, 0.6)
end

local function AddBoard(codes, label)
    for _, code in ipairs(codes) do
        local i = #state.board + 1
        if i <= 5 then
            state.board[i] = code
            SetCard(boardCards[i], code)
            PopIn(boardCards[i], (#codes > 1) and (_ - 1) * 0.15 or 0)
        end
    end
    ShowStreet(label)
    RefreshHand()
end

local function Highlight(list)
    local set = {}
    for code in list:gmatch("([^,]+)") do set[code] = true end
    for i = 1, 5 do
        local c = boardCards[i]
        if c.code then
            c.glow:SetShown(set[c.code] == true)
            c:SetAlpha(set[c.code] and 1 or 0.45)
        end
    end
    for i = 1, 2 do
        local c = handCards[i]
        if c and c.code then c.glow:SetShown(set[c.code] == true) end
    end
end

local function ShowBanner(main, sub)
    bannerText:SetText(main)
    bannerSub:SetText(sub or "")
    FadeOutLater(banner, 5, 0.8)
end

local function SetStack(amount)
    amount = tonumber(amount)
    if not amount then return end
    local prev = state.stack
    state.stack = amount
    if prev and amount ~= prev then
        local delta = amount - prev
        local pot = _G["PokerChipPotFrame"]
        if delta > 0 then
            FloatText(stackText and handPanel:IsShown() and handPanel or pot, "+" .. delta, 0.2, 1, 0.2)
            if pot and pot:IsShown() then FloatText(pot, "+" .. delta, 0.2, 1, 0.2, 18) end
        elseif delta < 0 then
            if handPanel and handPanel:IsShown() then FloatText(handPanel, tostring(delta), 1, 0.3, 0.3, 18) end
            if pot and pot:IsShown() then FloatText(pot, tostring(delta), 1, 0.3, 0.3, 18) end
        end
    end
    RefreshHand()
end

-- == Table commands =======================================================
local function OnCommand(cmd, sender)
    if not boardFrame then Build() end
    if not boardFrame then return end
    local me = Me()

    if cmd == "NEXT_HAND" or cmd:match("^SHUFFLE:") then
        if cmd == "NEXT_HAND" then
            ClearBoard()
            -- Hole cards use their own channel and can arrive before NEXT_HAND; keep fresh ones
            if GetTime() - (state.holeAt or -100) > 3 then wipe(state.hole) end
            state.folded = false
            state.lastCategory = nil
            banner:Hide()
            state.turnSeat = nil
            if handPanel then
                turnText:SetText("")
                handPanel:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
            end
        end
        state.handStartStack = state.stack
        RefreshHand()
        return
    end

    local c1, c2, c3 = cmd:match("^FLOP:([^:]+):([^:]+):([^:]+)")
    if c1 then ClearBoard() AddBoard({ c1, c2, c3 }, "THE FLOP") return end
    local t = cmd:match("^TURN:(%w+)$")
    if t then AddBoard({ t }, "THE TURN") return end
    local r = cmd:match("^RIVER:(%w+)$")
    if r then AddBoard({ r }, "THE RIVER") return end

    local seat = cmd:match("^TURN_START:(%d+)$")
    if seat then
        state.turnSeat = tonumber(seat)
        if handPanel then
            local mine = tonumber(seat) == playerSeat and not state.folded
            turnText:SetText(mine and "YOUR TURN!" or "")
            handPanel:SetBackdropBorderColor(mine and 0.3 or 0.6, mine and 1 or 0.5, mine and 0.3 or 0.2, 1)
        end
        return
    end

    local fname = cmd:match("^FOLD:(.+)$")
    if fname then
        if fname == me then state.folded = true RefreshHand() end
        return
    end

    local bn, ba = cmd:match("^BANKROLL_SET:([^:]+):(%d+)")
    if bn then
        if bn == me then SetStack(ba) end
        return
    end
    local sNum, sn, sa = cmd:match("^SEAT_STATE:(%d+):OCCUPIED:([^:]+):(%d+)$")
    if sNum then state.seatNames[tonumber(sNum)] = sn end
    local eNum = cmd:match("^SEAT_STATE:(%d+):EMPTY")
    if eNum then state.seatNames[tonumber(eNum)] = nil return end
    if sn then
        if sn == me and not state.stack then state.stack = tonumber(sa) RefreshHand() end
        return
    end

    local list = cmd:match("^SHOWDOWN_HIGHLIGHT:(.+)$")
    if list then Highlight(list) return end

    local _, _, _, cat = cmd:match("^SHOWDOWN_POPUP:(%d+):([^:]+):(%d+):(%d+):")
    if cat then state.lastCategory = tonumber(cat) return end

    local wName, wAmt = cmd:match("^POT_WINNER:([^:]+):(%d+)")
    if wName then
        local how = state.lastCategory and (" with " .. (E.CATEGORY_NAMES[state.lastCategory] or "")) or ""
        if not state.lastCategory then how = " (everyone else folded)" end
        local mainLine
        if wName == me then
            mainLine = ("|cff33ff33YOU WIN %s chips!|r"):format(wAmt)
        else
            mainLine = ("%s%s wins %s chips|r"):format(GOLD, wName, wAmt)
        end
        local sub = how
        local delta = state.handStartStack and state.stack and (state.stack - state.handStartStack)
        C_Timer.After(0.6, function()
            -- BANKROLL_SET follows straight after; show the net result for the hand
            local d = state.handStartStack and state.stack and (state.stack - state.handStartStack) or delta
            local mine = ""
            if d and d > 0 then mine = ("   |cff33ff33You: +%d|r"):format(d)
            elseif d and d < 0 then mine = ("   |cffff5555You: %d|r"):format(d) end
            ShowBanner(mainLine, sub .. mine)
        end)
        return
    end

    local names, total = cmd:match("^POT_SPLIT:([^:]+):(%d+)")
    if names then
        local nice = names:gsub(",", ", ")
        C_Timer.After(0.6, function()
            local d = state.handStartStack and state.stack and (state.stack - state.handStartStack)
            local mine = ""
            if d and d > 0 then mine = ("   |cff33ff33You: +%d|r"):format(d)
            elseif d and d < 0 then mine = ("   |cffff5555You: %d|r"):format(d) end
            ShowBanner(GOLD .. "Split pot: " .. nice .. "|r", ("%d chips shared"):format(tonumber(total) or 0) .. mine)
        end)
        return
    end

    if cmd:match("^PLAYER_LEFT_SEAT:" .. me .. ":") or cmd:match("^KICK_PLAYER:" .. me .. ":") then
        wipe(state.hole)
        state.stack = nil
        state.handStartStack = nil
        RefreshHand()
        return
    end
end

N.AddCommandHandler(OnCommand)
N.OnHole = function(c1, c2)
    if not boardFrame then Build() end
    state.hole[1], state.hole[2] = c1, c2
    state.holeAt = GetTime()
    state.folded = false
    RefreshHand()
    if handCards then
        PopIn(handCards[1], 0)
        PopIn(handCards[2], 0.15)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() pcall(Build) end)
