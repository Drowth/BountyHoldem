-- =========================================================================
-- Bounty Hold'em v1.1.9 by Lee
-- PokerHost.lua: host mode, one client deals for the group
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- The host client holds the real game state (deck, stacks, pot, turn) and
-- drives the other clients through the PokerTable protocol that poker.lua draws
-- Host commands:
--   /poker host            open a table for the group
--   /poker close           shut the table
--   /poker start | pause   auto-deal hands / stop after the current hand
--   /poker blinds 5 10     set small and big blind (between hands only)
--   /poker timer 30        decision time in seconds
--   /poker kick <name>     unseat a player
--   /poker void            cancel the hand and refund all bets
--   /poker bot [n]         add n bots (results against bots count)
--   /poker nobots          remove all bots
-- Commands for everyone:
--   /poker chips           print your chip balance
--   /poker pot             toggle the on-screen chip pot
--   /poker killchat        toggle the "+N chips from a kill" chat line (off by default)
--   /poker camp on|off     open poker when sitting at a campfire

local N = PokerNet
local E = PokerEval

PokerHost = PokerHost or {}
local H = PokerHost

H.active      = false
H.autoDeal    = false
H.sb          = 5
H.bb          = 10
H.timer       = 30
H.grace       = 4     -- Grace seconds before the host auto-folds a silent player
H.handGap     = 7     -- Pause between hands, in seconds
H.settle      = 5     -- Seconds after a hand before Deal Hand unlocks
H.readyAt     = 0
H.seats       = {}    -- Per seat: { name, full, stack, ready }
H.dealerSeat  = nil
H.hand        = nil
H.handCounter = 0

local TAG = "|cff00cccc[Poker]|r "
local function Say(msg) print(TAG .. msg) end
local function Out(cmd) N.Broadcast(cmd) end
local function After(sec, fn) return C_Timer.NewTimer(sec, fn) end

-- == Helpers ==============================================================
local function SeatOf(name)
    for s = 1, 9 do
        local p = H.seats[s]
        if p and p.name == name then return s end
    end
end

-- Ascending seats for which pred(seat) is true
local function SeatsWhere(pred)
    local list = {}
    for s = 1, 9 do
        if H.seats[s] and pred(s) then list[#list + 1] = s end
    end
    return list
end

-- Next seat in list after from, wrapping round
local function NextIn(list, from)
    if #list == 0 then return nil end
    for _, s in ipairs(list) do
        if s > from then return s end
    end
    return list[1]
end

local function RandomHex(n)
    local t = {}
    for i = 1, n do t[i] = string.format("%x", math.random(0, 15)) end
    return table.concat(t)
end

local function SendSeatState(s)
    local p = H.seats[s]
    if p then
        Out(("SEAT_STATE:%d:OCCUPIED:%s:%d"):format(s, p.name, p.stack))
    else
        Out(("SEAT_STATE:%d:EMPTY"):format(s))
    end
end

local function SendBankroll(s)
    local p = H.seats[s]
    if p then Out(("BANKROLL_SET:%s:%d"):format(p.name, p.stack)) end
end

local function SendSettings()
    Out(("UPDATE_BB:%d:%d"):format(H.bb, H.sb))
    Out("UPDATE_RAKE:0")
    Out(("UPDATE_TIMER:%d"):format(H.timer))
end

-- Snapshot requests arrive from every client at once; answer them with one snapshot
function H.SendSnapshot()
    if not H.active or H.snapshotQueued then return end
    H.snapshotQueued = true
    C_Timer.After(1.5, function()
        H.snapshotQueued = false
        if H.active then H.SendSnapshotNow() end
    end)
end

function H.SendSnapshotNow()
    if not H.active then return end
    SendSettings()
    if H.practice then Out("PRACTICE:1") end
    for s = 1, 9 do SendSeatState(s) end
    if H.dealerSeat and H.seats[H.dealerSeat] then
        local h = H.hand
        if h then
            Out(("BLINDS_ASSIGN:%d:%d:%d:%s:%s:%s"):format(h.dealer, h.sbSeat, h.bbSeat,
                h.names[h.dealer] or "", h.names[h.sbSeat] or "", h.names[h.bbSeat] or ""))
        end
    end
end

-- == Hand state ===========================================================
local function PotTotal(h)
    local t = 0
    for _, p in pairs(h.players) do t = t + p.total end
    return t
end

local function SeatsWhereHand(h, pred)
    local list = {}
    for _, s in ipairs(h.order) do
        local p = h.players[s]
        if p and pred(p, s) then list[#list + 1] = s end
    end
    return list
end

local function Live(h)
    return SeatsWhereHand(h, function(p) return not p.folded end)
end

local function CanAct(h)
    return SeatsWhereHand(h, function(p) return not p.folded and not p.allin end)
end

local function Commit(h, s, amount)
    local p = h.players[s]
    local seat = H.seats[s]
    amount = math.max(0, math.min(amount, seat.stack))
    seat.stack = seat.stack - amount
    p.bet = p.bet + amount
    p.total = p.total + amount
    if seat.stack == 0 then p.allin = true end
    return amount
end

local function DrawCard(h)
    h.deckPos = h.deckPos + 1
    return h.deck[h.deckPos]
end

local function CancelTurnTimer(h)
    if h and h.turnTimer then
        h.turnTimer:Cancel()
        h.turnTimer = nil
    end
end

local Advance, StartStreet, Showdown, AwardByFold, EndHand

local function StartTurn(h, s)
    h.acting = s
    CancelTurnTimer(h)
    Out(("TURN_START:%d"):format(s))
    local handId = h.id
    h.turnTimer = After(H.timer + H.grace, function()
        local cur = H.hand
        if not cur or cur.id ~= handId or cur.acting ~= s then return end
        local p = cur.players[s]
        if not p or p.folded then return end
        Say((cur.names[s] or "?") .. " ran out of time.")
        p.folded = true
        p.acted = true
        Out("FOLD:" .. cur.names[s])
        Advance(cur)
    end)
    local seat = H.seats[s]
    if seat and seat.bot then
        After(1.8 + math.random() * 2.4, function() -- Bot thinking delay
            if H.hand == h and h.acting == s and H.BotAct then H.BotAct(h, s) end
        end)
    end
end

-- First seat after from that still has to act
local function NextToAct(h, from)
    local candidates = SeatsWhereHand(h, function(p)
        return not p.folded and not p.allin and (not p.acted or p.bet < h.currentBet)
    end)
    return NextIn(candidates, from)
end

local function RoundComplete(h)
    for _, s in ipairs(CanAct(h)) do
        local p = h.players[s]
        if not p.acted or p.bet < h.currentBet then return false end
    end
    return true
end

Advance = function(h)
    if H.hand ~= h then return end
    CancelTurnTimer(h)
    Out(("UPDATE_POT:%d"):format(PotTotal(h)))

    local live = Live(h)
    if #live == 1 then
        AwardByFold(h, live[1])
        return
    end

    if not RoundComplete(h) then
        local nextSeat = NextToAct(h, h.acting or h.dealer)
        if nextSeat then
            StartTurn(h, nextSeat)
            return
        end
    end

    -- End of betting round
    h.acting = nil
    Out("BETTING_ROUND_COMPLETE")
    local runout = #CanAct(h) <= 1
    if h.street == "river" then
        After(1.2, function() if H.hand == h then Showdown(h) end end)
    else
        After(1.2, function() if H.hand == h then StartStreet(h, runout) end end)
    end
end

StartStreet = function(h, runout)
    for _, p in pairs(h.players) do
        p.bet = 0
        p.acted = false
    end
    h.currentBet = 0
    h.minRaise = H.bb

    Out("BURN:" .. N.MyName())
    DrawCard(h) -- Burn card
    if h.street == "preflop" then
        h.street = "flop"
        local c1, c2, c3 = DrawCard(h), DrawCard(h), DrawCard(h)
        h.board = { c1, c2, c3 }
        Out(("FLOP:%s:%s:%s"):format(c1, c2, c3))
    elseif h.street == "flop" then
        h.street = "turn"
        local c = DrawCard(h)
        h.board[4] = c
        Out("TURN:" .. c)
    else
        h.street = "river"
        local c = DrawCard(h)
        h.board[5] = c
        Out("RIVER:" .. c)
    end
    Out(("UPDATE_POT:%d"):format(PotTotal(h)))

    if runout then
        -- At most one player can still bet: run out the board
        After(2.0, function()
            if H.hand ~= h then return end
            if h.street == "river" then Showdown(h) else StartStreet(h, true) end
        end)
        return
    end

    After(1.2, function()
        if H.hand ~= h then return end
        local first = NextToAct(h, h.dealer)
        if first then StartTurn(h, first) else Advance(h) end
    end)
end

local function PayOut(h, winnings)
    -- Payouts: [seat] = chips
    for s, amt in pairs(winnings) do
        if H.seats[s] then H.seats[s].stack = H.seats[s].stack + amt end
    end
end

local function SendBankrollsAndDeck(h)
    for _, s in ipairs(h.order) do SendBankroll(s) end
    Out("DECK_ORDER:" .. h.deckStr)
end

AwardByFold = function(h, winnerSeat)
    CancelTurnTimer(h)
    h.acting = nil
    local pot = PotTotal(h)
    PayOut(h, { [winnerSeat] = pot })
    local name = h.names[winnerSeat]
    Out(("HAND_OVER:%s:%d"):format(name, winnerSeat))
    Out(("POT_WINNER:%s:%d:0:%s:%s"):format(name, pot, h.sid, h.hid))
    SendBankrollsAndDeck(h)
    EndHand(h)
end

Showdown = function(h)
    CancelTurnTimer(h)
    h.acting = nil
    local live = Live(h)
    local liveSet, results = {}, {}
    for _, s in ipairs(live) do
        liveSet[s] = true
        local p = h.players[s]
        local cards = { p.hole[1], p.hole[2] }
        for _, c in ipairs(h.board) do cards[#cards + 1] = c end
        results[s] = E.Evaluate(cards)
    end

    -- Show hands
    for _, s in ipairs(live) do
        local p = h.players[s]
        Out(("SHOWDOWN_REVEAL:%d:%s:%s"):format(s, p.hole[1], p.hole[2]))
        Out(("SHOWDOWN_LINE:" .. TAG .. "|cff87ceeb%s|r shows [%s] [%s]: %s"):format(
            h.names[s], p.hole[1], p.hole[2], results[s].name))
    end

    -- Split into side pots
    local contributions = {}
    for s, p in pairs(h.players) do contributions[s] = p.total end
    local pots = E.BuildPots(contributions, liveSet)

    local winnings, mainWinners = {}, nil
    for pi, pot in ipairs(pots) do
        local bestScore, winners = -1, {}
        for _, s in ipairs(pot.eligible) do
            local sc = results[s].score
            if sc > bestScore then
                bestScore, winners = sc, { s }
            elseif sc == bestScore then
                winners[#winners + 1] = s
            end
        end
        table.sort(winners)
        local share = math.floor(pot.amount / #winners)
        local rem = pot.amount - share * #winners
        for i, s in ipairs(winners) do
            winnings[s] = (winnings[s] or 0) + share + ((i <= rem) and 1 or 0)
        end
        if pi == 1 then mainWinners = winners end
    end
    PayOut(h, winnings)

    -- Main pot winner highlight and popup
    local top = mainWinners[1]
    local best = results[top]
    Out("SHOWDOWN_HIGHLIGHT:" .. table.concat(best.cards, ","))
    Out(("SHOWDOWN_POPUP:%d:%s:%d:%d:%s"):format(top, h.names[top], winnings[top] or 0,
        best.category, table.concat(best.cards, ",")))

    local names, total, count = {}, 0, 0
    for _, s in ipairs(h.order) do
        if winnings[s] and winnings[s] > 0 then
            names[#names + 1] = h.names[s]
            total = total + winnings[s]
            count = count + 1
        end
    end
    if count == 1 then
        Out(("POT_WINNER:%s:%d:0:%s:%s"):format(names[1], total, h.sid, h.hid))
    else
        Out(("POT_SPLIT:%s:%d:0:%s:%s"):format(table.concat(names, ","), total, h.sid, h.hid))
    end
    SendBankrollsAndDeck(h)
    EndHand(h)
end

local function RemoveSeat(s, reason)
    local p = H.seats[s]
    if not p then return end
    H.seats[s] = nil
    Out(("PLAYER_LEFT_SEAT:%s:%d"):format(p.name, s))
    SendSeatState(s)
    if reason then Say(p.name .. " " .. reason) end
end

-- Handles a player leaving, being kicked or dropping from the group mid-hand;
-- chips already in the pot stay there
local function FoldOut(s, reason)
    local h = H.hand
    local p = H.seats[s]
    if not p then return end
    if h and h.players[s] and not h.players[s].folded then
        h.players[s].folded = true
        h.players[s].acted = true
        Out("FOLD:" .. p.name)
        H.seats[s] = nil
        SendSeatState(s)
        if reason then Say(p.name .. " " .. reason) end
        if h.acting == s or #Live(h) == 1 then
            Advance(h)
        else
            Out(("UPDATE_POT:%d"):format(PotTotal(h)))
        end
    else
        RemoveSeat(s, reason)
    end
end

local function ScheduleNextHand(delay)
    if H.nextHandTimer then H.nextHandTimer:Cancel() end
    H.nextHandTimer = After(delay or H.handGap, function()
        H.nextHandTimer = nil
        if H.active and H.autoDeal and not H.hand then H.StartHand() end
    end)
end

EndHand = function(h)
    CancelTurnTimer(h)
    H.hand = nil
    H.readyAt = GetTime() + H.settle -- Let the pot and showdown animations finish first
    -- Busted players stand once the pot animation has finished
    After(4, function()
        if H.hand then return end
        for s = 1, 9 do
            local p = H.seats[s]
            if p and p.ready and p.stack <= 0 then
                Out(("KICK_PLAYER:%s:%d"):format(p.name, s))
                RemoveSeat(s, "is out of chips and has left the table.")
            end
        end
    end)
    if H.autoDeal then ScheduleNextHand() end
end

-- == Starting a hand ======================================================
function H.StartHand()
    if H.hand then return end
    local eligible = SeatsWhere(function(s) return H.seats[s].ready and H.seats[s].stack > 0 end)
    if #eligible < 2 then
        Say("Waiting for at least two seated players with chips.")
        return
    end
    -- Seated players without a buy-in would break the clients' deal order
    for s = 1, 9 do
        local p = H.seats[s]
        if p and not p.ready then RemoveSeat(s, "was removed (no chip balance received).") end
        -- Busted players still seated would also break the deal order
        if p and p.ready and p.stack <= 0 then
            Out(("KICK_PLAYER:%s:%d"):format(p.name, s))
            RemoveSeat(s, "is out of chips and has left the table.")
        end
    end

    H.handCounter = H.handCounter + 1
    local h = {
        id = H.handCounter,
        order = eligible,
        players = {},
        names = {},
        board = {},
        street = "preflop",
        currentBet = 0,
        minRaise = H.bb,
    }
    for _, s in ipairs(eligible) do
        h.players[s] = { bet = 0, total = 0, folded = false, allin = false, acted = false, hole = {} }
        h.names[s] = H.seats[s].name
    end

    -- Dealer button
    if H.dealerSeat and H.seats[H.dealerSeat] then
        h.dealer = NextIn(eligible, H.dealerSeat)
    elseif H.dealerSeat then
        h.dealer = NextIn(eligible, H.dealerSeat)
    else
        h.dealer = eligible[math.random(1, #eligible)]
    end
    H.dealerSeat = h.dealer
    if #eligible == 2 then
        h.sbSeat = h.dealer
        h.bbSeat = NextIn(eligible, h.dealer)
    else
        h.sbSeat = NextIn(eligible, h.dealer)
        h.bbSeat = NextIn(eligible, h.sbSeat)
    end

    -- Deck: CRC committed before the deal, revealed after the hand
    h.deck = E.Shuffle(E.NewDeck())
    h.deckPos = 0
    h.deckStr = table.concat(h.deck, ",")
    h.sid = E.CRC32(h.deckStr)
    h.hid = ("%d-%s"):format(h.id, RandomHex(4))

    H.hand = h

    Out("NEXT_HAND")
    Out(("BLINDS_ASSIGN:%d:%d:%d:%s:%s:%s"):format(h.dealer, h.sbSeat, h.bbSeat,
        h.names[h.dealer], h.names[h.sbSeat], h.names[h.bbSeat]))
    Out("HAND_START")
    Out(("SHUFFLE:%s:%s"):format(h.sid, h.hid))

    local sbPaid = Commit(h, h.sbSeat, H.sb)
    local bbPaid = Commit(h, h.bbSeat, H.bb)
    Out(("SHOW_SB:%s:%d"):format(h.names[h.sbSeat], sbPaid))
    Out(("SHOW_BB:%s:%d"):format(h.names[h.bbSeat], bbPaid))
    h.currentBet = H.bb
    Out(("UPDATE_POT:%d"):format(PotTotal(h)))
    SendBankroll(h.sbSeat)
    SendBankroll(h.bbSeat)

    -- Two cards each, starting left of the button
    local start = NextIn(eligible, h.dealer)
    local idx
    for i, s in ipairs(eligible) do if s == start then idx = i end end
    for round = 1, 2 do
        for k = 0, #eligible - 1 do
            local s = eligible[((idx - 1 + k) % #eligible) + 1]
            h.players[s].hole[round] = DrawCard(h)
        end
    end
    Out(("DEAL_ANIM:%d"):format(#eligible * 2))

    local dealTime = #eligible * 2 * 0.22 + 1.0
    After(dealTime, function()
        if H.hand ~= h then return end
        -- Send hole cards after the deal animation lands, so nothing clears them
        for _, s in ipairs(eligible) do
            local p = h.players[s]
            if H.seats[s] and not H.seats[s].bot then N.SendHole(H.seats[s].name, p.hole[1], p.hole[2]) end
        end
        -- Preflop order: heads-up the button (small blind) acts first, else left of the big blind
        local first = NextToAct(h, h.bbSeat)
        if first then StartTurn(h, first) else Advance(h) end
    end)
end

function H.VoidHand()
    local h = H.hand
    if not h then Say("No hand in progress.") return end
    CancelTurnTimer(h)
    for s, p in pairs(h.players) do
        if H.seats[s] then H.seats[s].stack = H.seats[s].stack + p.total end
    end
    Out(("VOID_HAND:%s:%s"):format(N.MyName(), h.sid))
    for _, s in ipairs(h.order) do SendBankroll(s) end
    Out("UPDATE_POT:0")
    H.hand = nil
    H.readyAt = GetTime() + 2
    if H.autoDeal then ScheduleNextHand() end
end

-- == Player actions =======================================================
local function OnAction(kind, name, amount, sender)
    local h = H.hand
    if not h then return end
    if N.ShortName(sender) ~= name then return end -- Players may only act for themselves
    local s = SeatOf(name)
    if not s or not h.players[s] then return end
    local p = h.players[s]
    if p.folded then return end

    if kind == "FOLD" then
        -- Folds are accepted out of turn (timer expiry, leaving the table)
        p.folded = true
        p.acted = true
        if h.acting == s or #Live(h) == 1 then
            Advance(h)
        end
        return
    end

    if h.acting ~= s or p.allin then return end -- Out of turn

    if kind == "CHECK" then
        if p.bet < h.currentBet then
            -- Check not allowed: resync the player and prompt again
            SendBankroll(s)
            StartTurn(h, s)
            return
        end
    elseif kind == "CALL" then
        Commit(h, s, h.currentBet - p.bet)
    elseif kind == "RAISE" or kind == "ALL_IN" then
        local stack = H.seats[s].stack
        local target
        if kind == "ALL_IN" then
            target = p.bet + stack
        else
            target = tonumber(amount) or 0
            local minTarget = h.currentBet + h.minRaise
            if target < minTarget then target = minTarget end
            if target - p.bet >= stack then target = p.bet + stack end
        end
        if target <= h.currentBet then
            -- An all-in short of the current bet counts as a call
            Commit(h, s, target - p.bet)
        else
            local increase = target - h.currentBet
            Commit(h, s, target - p.bet)
            h.currentBet = target
            -- Only a full raise reopens the betting; a short all-in just has to be called
            if increase >= h.minRaise then
                h.minRaise = increase
                for os, op in pairs(h.players) do
                    if os ~= s and not op.folded and not op.allin then op.acted = false end
                end
            end
        end
    end
    p.acted = true
    SendBankroll(s)
    Advance(h)
end

-- == Practice bots ========================================================
-- Results against bots count towards real balances
H.BOT_NAMES = { "Gizzle", "Sprocket", "Mogsy", "Fizzbang", "Ratchet", "Nixxie", "Grubble", "Zapnik", "Tinkle" }
H.BOT_STACK = 1000

local function BotStrength(h, s)
    local p = h.players[s]
    local v1 = E.ParseCard(p.hole[1])
    local v2, s2 = E.ParseCard(p.hole[2])
    local _, s1 = E.ParseCard(p.hole[1])
    if #h.board == 0 then
        local hi, lo = math.max(v1, v2), math.min(v1, v2)
        local str = (hi + lo) / 28 * 0.6
        if v1 == v2 then str = str + 0.35 end
        if s1 == s2 then str = str + 0.05 end
        if hi - lo == 1 then str = str + 0.04 end
        return math.min(1, str)
    end
    local cards = { p.hole[1], p.hole[2] }
    for _, c in ipairs(h.board) do cards[#cards + 1] = c end
    local cat = E.Evaluate(cards).category
    local base = ({ [0] = 0.15, [1] = 0.45, [2] = 0.68, [3] = 0.8 })[cat] or 0.92
    -- A pair made only from board cards is weak
    if cat == 1 then
        local boardCat = (#h.board >= 5) and E.Evaluate(h.board).category or nil
        if boardCat == 1 then base = 0.25 end
    end
    return base
end

function H.BotAct(h, s)
    local p = h.players[s]
    local seat = H.seats[s]
    if not p or not seat or p.folded or p.allin then return end
    local name = seat.name
    local toCall = h.currentBet - p.bet
    local pot = PotTotal(h)
    local str = BotStrength(h, s)
    local r = math.random()

    local function Raise()
        local target = h.currentBet + math.max(h.minRaise, math.floor(pot * (0.5 + math.random() * 0.5)))
        if target - p.bet >= seat.stack then
            Out(("ALL_IN:%s:%d"):format(name, seat.stack))
            OnAction("ALL_IN", name, seat.stack, name)
        else
            Out(("RAISE:%s:%d"):format(name, target))
            OnAction("RAISE", name, target, name)
        end
    end

    if toCall <= 0 then
        if str > 0.65 and r < 0.6 then Raise()
        elseif str > 0.35 and r < 0.15 then Raise()
        else
            Out("CHECK:" .. name)
            OnAction("CHECK", name, nil, name)
        end
        return
    end

    local odds = toCall / (pot + toCall)
    if str > 0.8 and r < 0.45 then
        Raise()
    elseif str > odds + 0.1 or r < 0.12 then
        local amt = math.min(toCall, seat.stack)
        if amt >= seat.stack then
            Out(("ALL_IN:%s:%d"):format(name, seat.stack))
            OnAction("ALL_IN", name, seat.stack, name)
        else
            Out(("CALL:%s:%d"):format(name, amt))
            OnAction("CALL", name, amt, name)
        end
    else
        Out("FOLD:" .. name)
        OnAction("FOLD", name, nil, name)
    end
end

function H.AddBot(seat)
    local free = seat
    if free and (H.seats[free] or (seatMarkers and seatMarkers[free] and seatMarkers[free].occupied)) then
        Say("Seat " .. free .. " is taken.")
        return
    end
    if not free then
        for s = 1, 9 do if not H.seats[s] then free = s break end end
    end
    if not free then Say("The table is full.") return end
    local name
    for _, n in ipairs(H.BOT_NAMES) do
        if not SeatOf(n) then name = n break end
    end
    if not name then Say("No bot names left.") return end
    H.seats[free] = { name = name, full = nil, stack = H.BOT_STACK, ready = true, bot = true }
    SendSeatState(free)
    SendBankroll(free)
    Say(name .. " (bot) sits down in seat " .. free .. ".")
    if H.autoDeal and not H.hand and not H.nextHandTimer then ScheduleNextHand(3) end
end

function H.RemoveBot(s)
    local p = H.seats[s]
    if p and p.bot then FoldOut(s, "(bot) leaves the table.") end
end

-- Host-only "+ Bot" / "Remove" buttons on each seat
local HandleHostCommand -- Forward declaration

local function AddSeatBotButtons()
    local tbl = (PokerUI and PokerUI.TableFrame) or _G["PokerTableFrame"]
    if not tbl or not seatMarkers or H.seatBotButtons then return end
    H.seatBotButtons = {}

    -- Closing the table window as host closes the table too. Otherwise bots and
    -- auto-deal keep running on a table nobody can see, and the next "host"
    -- picks up that old table instead of a fresh one
    tbl:HookScript("OnHide", function()
        if H.active then
            Say("You closed the table window, so your table is closed.")
            H.Close()
        end
    end)
    for s = 1, 9 do
        local marker = seatMarkers[s]
        if marker and marker.button then
            local b = CreateFrame("Button", nil, tbl, "UIPanelButtonTemplate")
            b:SetSize(58, 20)
            b:SetPoint("CENTER", marker.button, "CENTER", 0, -22)
            b:SetFrameLevel(marker.button:GetFrameLevel() + 10)
            b:SetText("+ Bot")
            b:Hide()
            b:SetScript("OnClick", function(self)
                if self.mode == "add" then H.AddBot(s) else H.RemoveBot(s) end
            end)
            H.seatBotButtons[s] = b
        end
    end
    -- Host-only Start / Pause dealing button, top left below History
    local deal = CreateFrame("Button", nil, tbl, "UIPanelButtonTemplate")
    deal:SetSize(90, 26)
    deal:SetPoint("TOPLEFT", tbl, "TOPLEFT", 12, -89)
    deal:Hide()
    deal:SetScript("OnClick", function()
        if not H.hand then H.StartHand() end
    end)
    H.dealButton = deal

    -- Auto-deal tick box; when off the host deals each hand manually
    local auto = CreateFrame("CheckButton", nil, tbl, "UICheckButtonTemplate")
    auto:SetSize(24, 24)
    auto:SetPoint("TOPLEFT", deal, "BOTTOMLEFT", -2, -2)
    auto.label = auto:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    auto.label:SetPoint("LEFT", auto, "RIGHT", 2, 0)
    auto.label:SetText("Auto-deal")
    auto:Hide()
    auto:SetScript("OnClick", function(self)
        HandleHostCommand(self:GetChecked() and "start" or "pause", "")
    end)
    H.autoBox = auto

    local elapsed = 0
    tbl:HookScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.4 then return end
        elapsed = 0
        if H.active then
            -- One clear state at a time, so Deal Hand only lights up when a hand can start
            local wait = (H.readyAt or 0) - GetTime()
            local ready = #SeatsWhere(function(s) return H.seats[s].ready and H.seats[s].stack > 0 end)
            if H.hand then
                deal:SetText("In play...")
                deal:SetEnabled(false)
            elseif wait > 0 then
                deal:SetText(("Next hand %d"):format(math.ceil(wait)))
                deal:SetEnabled(false)
            elseif ready < 2 then
                deal:SetText("Need 2 players")
                deal:SetEnabled(false)
            else
                deal:SetText("Deal Hand")
                deal:SetEnabled(true)
            end
            deal:Show()
            auto:SetChecked(H.autoDeal)
            auto:Show()
        else
            deal:Hide()
            auto:Hide()
        end
        for s, b in pairs(H.seatBotButtons) do
            local seat = H.seats[s]
            local occupied = seatMarkers[s] and seatMarkers[s].occupied
            if H.active and not seat and not occupied then
                b.mode = "add"
                b:SetSize(58, 20)
                b:ClearAllPoints()
                b:SetPoint("CENTER", seatMarkers[s].button, "CENTER", 0, -22)
                b:SetText("+ Bot")
                b:Show()
            elseif H.active and seat and seat.bot then
                b.mode = "remove"
                b:SetSize(22, 20) -- Small, at the end of the name bar
                b:SetText("X")
                b:ClearAllPoints()
                local dx = (seatMarkers[s].type == "left") and 70 or -70
                b:SetPoint("CENTER", seatMarkers[s].button, "CENTER", dx, 0)
                b:Show()
            else
                b:Hide()
            end
        end
    end)
end
H.AddSeatBotButtons = AddSeatBotButtons

function H.RemoveBots()
    for s = 1, 9 do
        local p = H.seats[s]
        if p and p.bot then FoldOut(s, "(bot) leaves the table.") end
    end
end

-- == Seating ==============================================================
local function OnSitDown(name, seat, sender)
    if N.ShortName(sender) ~= name then return end
    local existing = H.seats[seat]
    local already = SeatOf(name)
    if (existing and existing.name ~= name) or (already and already ~= seat) then
        -- Seat taken or player already seated elsewhere: bounce them and resync everyone
        Out(("KICK_PLAYER:%s:%d"):format(name, seat))
        After(0.5, function() SendSeatState(seat) if already then SendSeatState(already) end end)
        return
    end
    H.seats[seat] = { name = name, full = sender, stack = 0, ready = false }
    -- Await BUYIN from the player's economy module
    After(6, function()
        local p = H.seats[seat]
        if p and p.name == name and not p.ready then
            Out(("KICK_PLAYER:%s:%d"):format(name, seat))
            RemoveSeat(seat, "could not sit (no chip balance received, are they on the latest version?).")
        end
    end)
end

local function OnBuyIn(name, amount, sender)
    if N.ShortName(sender) ~= name then return end
    local s = SeatOf(name)
    if not s then return end
    local p = H.seats[s]
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        Out(("KICK_PLAYER:%s:%d"):format(name, s))
        RemoveSeat(s, "has no chips. Go kill some mobs!")
        return
    end
    p.stack = amount
    p.ready = true
    p.full = sender
    SendSeatState(s)
    SendBankroll(s)
    if H.dealerSeat then
        local h = H.hand
        if h then
            Out(("BLINDS_ASSIGN:%d:%d:%d:%s:%s:%s"):format(h.dealer, h.sbSeat, h.bbSeat,
                h.names[h.dealer], h.names[h.sbSeat], h.names[h.bbSeat]))
        end
    end
    if H.autoDeal and not H.hand and not H.nextHandTimer then ScheduleNextHand(3) end
end

local function OnLeave(name, sender)
    if N.ShortName(sender) ~= name then return end
    local s = SeatOf(name)
    if not s then return end
    FoldOut(s, nil)
end

-- == Message routing ======================================================
local hostFrame = CreateFrame("Frame")
hostFrame:RegisterEvent("CHAT_MSG_ADDON")
if N.AddListener then N.AddListener(hostFrame) end
hostFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
hostFrame:RegisterEvent("PLAYER_LOGOUT")

local function InGroupByName(name)
    if name == N.MyName() then return true end
    for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        if N.ShortName(UnitName(unit)) == name then return true end
    end
    return false
end

hostFrame:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
    if not H.active then return end

    if event == "PLAYER_LOGOUT" then
        -- Send now: queued sends never fire during logout
        Poker_SendAddonMessage(N.PREFIX, "TABLE_CLOSED", Poker_Channel())
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        for s = 1, 9 do
            local p = H.seats[s]
            if p and not p.bot and not InGroupByName(p.name) then
                FoldOut(s, "left the group.")
            end
        end
        return
    end

    if prefix ~= N.PREFIX then return end

    if msg:find("^PLAYER_WAITING:") then
        N.Send("TABLE_OPENED")
        return
    end
    if msg == "REQUEST_SNAPSHOT" then
        H.SendSnapshot()
        return
    end

    local name, seat = msg:match("^PLAYER_SAT_DOWN:([^:]+):(%d+)$")
    if name then OnSitDown(name, tonumber(seat), sender) return end

    local bn, ba = msg:match("^BUYIN:([^:]+):(%d+)$")
    if bn then OnBuyIn(bn, ba, sender) return end

    name = msg:match("^PLAYER_LEFT_SEAT:([^:]+):%d+$")
    if name then OnLeave(name, sender) return end
    name = msg:match("^PLAYER_LEFT:([^:]+)")
    if name then OnLeave(N.ShortName(name), sender) return end

    name = msg:match("^FOLD:(.+)$")
    if name then OnAction("FOLD", name, nil, sender) return end
    name = msg:match("^CHECK:(.+)$")
    if name then OnAction("CHECK", name, nil, sender) return end
    local n2, a2 = msg:match("^CALL:([^:]+):(%d+)$")
    if n2 then OnAction("CALL", n2, a2, sender) return end
    n2, a2 = msg:match("^RAISE:([^:]+):(%d+)$")
    if n2 then OnAction("RAISE", n2, a2, sender) return end
    n2, a2 = msg:match("^ALL_IN:([^:]+):(%d+)$")
    if n2 then OnAction("ALL_IN", n2, a2, sender) return end
end)

-- == Host commands ========================================================
function H.Open()
    if H.active then Say("You are already hosting.") return end
    H.active = true
    H.practice = false
    H.seats = {}
    H.hand = nil
    H.dealerSeat = nil
    N.Send("TABLE_OPENED")
    SendSettings()
    for s = 1, 9 do SendSeatState(s) end
    Say("Table opened. Players type |cffffe6b3/poker|r and click Join Table, then pick a seat. Type |cffffe6b3/poker start|r when everyone is seated.")
end

function H.Close()
    if not H.active then Say("You are not hosting a table.") return end
    if H.hand then H.VoidHand() end
    H.autoDeal = false
    if H.nextHandTimer then H.nextHandTimer:Cancel() H.nextHandTimer = nil end
    for s = 1, 9 do
        local p = H.seats[s]
        if p then Out(("KICK_PLAYER:%s:%d"):format(p.name, s)) end
    end
    N.Send("TABLE_CLOSED")
    H.active = false
    H.practice = false
    H.seats = {}
    Say("Table closed.")
end

HandleHostCommand = function(cmd, rest)
    if cmd == "host" then H.Open() return true end
    if cmd == "check" then
        local function yn(v) return v and "|cff90ee90ok|r" or "|cffff5555MISSING|r" end
        Say("Module check: Net " .. yn(PokerNet and PokerNet.AddListener) .. ", HandEval " .. yn(PokerEval and PokerEval.CRC32)
            .. ", Economy " .. yn(PokerEconomy and PokerEconomy.Balance) .. ", ChipPot " .. yn(PokerChipPot_Toggle)
            .. ", Camp " .. yn(PokerCamp_SetEnabled) .. ", Host " .. yn(true))
        return true
    end
    if cmd == "chips" then PokerEconomy.PrintStatus() return true end
    if cmd == "killchat" then
        PokerChipsDB = PokerChipsDB or {}
        PokerChipsDB.killChat = not PokerChipsDB.killChat
        Say("Chip messages for kills are now " .. (PokerChipsDB.killChat and "on." or "off."))
        return true
    end
    if cmd == "pot" then if PokerChipPot_Toggle then PokerChipPot_Toggle() end return true end
    if cmd == "camp" then
        if rest == "on" or rest == "off" then
            PokerCamp_SetEnabled(rest == "on")
        else
            Say("Usage: /poker camp on|off")
        end
        return true
    end

    if cmd == "close" or cmd == "start" or cmd == "pause" or cmd == "blinds"
        or cmd == "timer" or cmd == "kick" or cmd == "void" or cmd == "bot" or cmd == "bots"
        or cmd == "nobots" then
        if not H.active then Say("You need to host a table first: |cffffe6b3/poker host|r") return true end
    else
        return false
    end

    if cmd == "close" then
        H.Close()
    elseif cmd == "start" then
        H.autoDeal = true
        Say("Dealing hands automatically.")
        if not H.hand then H.StartHand() end
    elseif cmd == "pause" then
        H.autoDeal = false
        if H.nextHandTimer then H.nextHandTimer:Cancel() H.nextHandTimer = nil end
        Say("Paused. The current hand will finish, then no new hands are dealt.")
    elseif cmd == "blinds" then
        local sb, bb = rest:match("^(%d+)%s+(%d+)$")
        sb, bb = tonumber(sb), tonumber(bb)
        if not sb or not bb or sb <= 0 or bb < sb then
            Say("Usage: /poker blinds <small> <big>, e.g. /poker blinds 5 10")
        else
            H.sb, H.bb = sb, bb
            Out(("UPDATE_BB:%d:%d"):format(bb, sb))
            Say(("Blinds set to %d/%d%s."):format(sb, bb, H.hand and " from the next hand" or ""))
        end
    elseif cmd == "timer" then
        local t = tonumber(rest)
        if not t or t < 10 or t > 120 then
            Say("Usage: /poker timer <10-120>")
        else
            H.timer = t
            Out(("UPDATE_TIMER:%d"):format(t))
        end
    elseif cmd == "kick" then
        local target = rest ~= "" and (rest:sub(1, 1):upper() .. rest:sub(2):lower()) or nil
        local s = target and SeatOf(target)
        if not s then
            Say("No seated player called " .. (target or "?") .. ".")
        else
            Out(("KICK_PLAYER:%s:%d"):format(target, s))
            FoldOut(s, "was removed by the host.")
        end
    elseif cmd == "void" then
        H.VoidHand()
    elseif cmd == "bot" or cmd == "bots" then
        local n = math.max(1, math.min(8, tonumber(rest) or 1))
        for _ = 1, n do H.AddBot() end
    elseif cmd == "nobots" then
        H.RemoveBots()
    end
    return true
end

-- "Host Table" button on the join window, so /poker host is optional
local function AddHostButton()
    local role = (PokerUI and PokerUI.RoleFrame) or _G["PokerJoinTableFrame"]
    if not role or H.hostBtn then return end
    local btn = CreateFrame("Button", nil, role, "GameMenuButtonTemplate")
    btn:SetSize(120, 28)
    btn:SetPoint("BOTTOMRIGHT", role, "BOTTOMRIGHT", -14, 10)
    local function Refresh()
        btn:SetText(H.active and "Close Table" or "Host Table")
    end
    btn:SetScript("OnClick", function()
        if H.active then H.Close() else H.Open() end
        Refresh()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(H.active and "Close your table" or "Be the dealer", 1, 1, 1)
        GameTooltip:AddLine("Hosting runs the game for your group from your client.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Playing alone? Host, join, sit, then type /poker bot 3 and /poker start.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    role:HookScript("OnShow", Refresh)
    Refresh()
    H.hostBtn = btn
end

-- Wraps poker.lua's /poker handler at load time (poker.lua loads first), so
-- it still works if something later fails
do
    local original = SlashCmdList["POKER"]
    SlashCmdList["POKER"] = function(msg)
        local raw = msg or ""
        local cmd, rest = raw:match("^%s*(%S+)%s*(.-)%s*$")
        cmd = cmd and cmd:lower()
        if cmd and HandleHostCommand(cmd, rest or "") then return end
        if original then original(msg) end
    end
    -- Some chat addons cache slash handlers; clear any stale copy
    if hash_SlashCmdList then hash_SlashCmdList["/POKER"] = nil end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    local ok, err = pcall(AddHostButton)
    if not ok then print("|cff00cccc[Poker]|r Could not add the Host Table button: " .. tostring(err)) end
    ok, err = pcall(H.AddSeatBotButtons)
    if not ok then print("|cff00cccc[Poker]|r Could not add seat bot buttons: " .. tostring(err)) end
end)
