-- =========================================================================
-- Bounty Hold'em v1.2.1 by Lee
-- PokerHandEval.lua: hand evaluation, deck helpers and CRC32
-- =========================================================================
-- Only one installed copy runs; a second folder (e.g. an old Poker install) stays idle
if POKER_OWNER and POKER_OWNER ~= (...) then return end
-- Texas Hold'em scoring, deck utilities and CRC32 checks
-- Plain Lua 5.1 with no WoW API calls, so it can be tested outside the game

PokerEval = PokerEval or {}
local E = PokerEval

E.RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }
E.SUITS = { "C", "D", "H", "S" }

local RANK_VALUE = {}
for i, r in ipairs(E.RANKS) do RANK_VALUE[r] = i + 1 end -- Rank values: "2" is 2 through "A" is 14

-- Category ids follow the table client: 9 Royal Flush down to 0 High Card
E.CATEGORY_NAMES = {
    [9] = "Royal Flush", [8] = "Straight Flush", [7] = "Four of a Kind", [6] = "Full House",
    [5] = "Flush", [4] = "Straight", [3] = "Three of a Kind", [2] = "Two Pair",
    [1] = "One Pair", [0] = "High Card",
}

function E.ParseCard(code)
    local suit = code:sub(-1)
    local rank = code:sub(1, -2)
    return RANK_VALUE[rank], suit
end

function E.NewDeck()
    local deck = {}
    for _, s in ipairs(E.SUITS) do
        for _, r in ipairs(E.RANKS) do
            deck[#deck + 1] = r .. s
        end
    end
    return deck
end

-- Fisher-Yates shuffle; rng(n) returns an integer in [1, n], math.random by default
function E.Shuffle(deck, rng)
    rng = rng or math.random
    for i = #deck, 2, -1 do
        local j = rng(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

-- Scores a 5-card hand: returns category (0 to 8, straight flush is 8), a
-- sortable numeric score, and a royal flush flag
local function Score5(cards)
    local vals, suits = {}, {}
    for i = 1, 5 do
        local v, s = E.ParseCard(cards[i])
        vals[i] = v
        suits[i] = s
    end

    local flush = suits[1] == suits[2] and suits[1] == suits[3] and suits[1] == suits[4] and suits[1] == suits[5]

    local counts = {}
    for _, v in ipairs(vals) do counts[v] = (counts[v] or 0) + 1 end
    -- Sort groups by count, then by value, both descending
    local groups = {}
    for v, c in pairs(counts) do groups[#groups + 1] = { v = v, c = c } end
    table.sort(groups, function(a, b)
        if a.c ~= b.c then return a.c > b.c end
        return a.v > b.v
    end)

    local straightHigh
    if #groups == 5 then
        local sorted = { vals[1], vals[2], vals[3], vals[4], vals[5] }
        table.sort(sorted, function(a, b) return a > b end)
        if sorted[1] - sorted[5] == 4 then
            straightHigh = sorted[1]
        elseif sorted[1] == 14 and sorted[2] == 5 and sorted[5] == 2 then
            straightHigh = 5 -- Ace-low straight (wheel)
        end
    end

    local cat, tiebreak
    if straightHigh and flush then
        cat, tiebreak = 8, { straightHigh }
    elseif groups[1].c == 4 then
        cat, tiebreak = 7, { groups[1].v, groups[2].v }
    elseif groups[1].c == 3 and groups[2].c == 2 then
        cat, tiebreak = 6, { groups[1].v, groups[2].v }
    elseif flush then
        local sorted = { vals[1], vals[2], vals[3], vals[4], vals[5] }
        table.sort(sorted, function(a, b) return a > b end)
        cat, tiebreak = 5, sorted
    elseif straightHigh then
        cat, tiebreak = 4, { straightHigh }
    elseif groups[1].c == 3 then
        cat, tiebreak = 3, { groups[1].v, groups[2].v, groups[3].v }
    elseif groups[1].c == 2 and groups[2].c == 2 then
        cat, tiebreak = 2, { groups[1].v, groups[2].v, groups[3].v }
    elseif groups[1].c == 2 then
        cat, tiebreak = 1, { groups[1].v, groups[2].v, groups[3].v, groups[4].v }
    else
        local sorted = { vals[1], vals[2], vals[3], vals[4], vals[5] }
        table.sort(sorted, function(a, b) return a > b end)
        cat, tiebreak = 0, sorted
    end

    local score = cat
    for i = 1, 5 do score = score * 15 + (tiebreak[i] or 0) end
    return cat, score, (cat == 8 and straightHigh == 14)
end

-- Best 5-card hand from up to 7 cards
-- Returns { score, category (client ids, royal is 9), name, cards = { 5 codes } }
function E.Evaluate(cards)
    local n = #cards
    local best
    for a = 1, n - 4 do
        for b = a + 1, n - 3 do
            for c = b + 1, n - 2 do
                for d = c + 1, n - 1 do
                    for e = d + 1, n do
                        local hand = { cards[a], cards[b], cards[c], cards[d], cards[e] }
                        local cat, score, royal = Score5(hand)
                        if not best or score > best.score then
                            best = { score = score, category = royal and 9 or cat, cards = hand }
                        end
                    end
                end
            end
        end
    end
    if best then best.name = E.CATEGORY_NAMES[best.category] end
    return best
end

-- Builds side pots. contributions: { [seat] = chips put in this hand }
-- live: { [seat] = true } for seats that have not folded
-- Returns { amount = n, eligible = { seat, ... } } entries, main pot first
function E.BuildPots(contributions, live)
    local levels, seen = {}, {}
    for seat, amt in pairs(contributions) do
        if live[seat] and amt > 0 and not seen[amt] then
            seen[amt] = true
            levels[#levels + 1] = amt
        end
    end
    table.sort(levels)

    local pots, prev = {}, 0
    for li, level in ipairs(levels) do
        local amount, eligible = 0, {}
        for seat, amt in pairs(contributions) do
            local part = math.min(amt, level) - prev
            if part > 0 then amount = amount + part end
            if live[seat] and amt >= level then eligible[#eligible + 1] = seat end
        end
        -- Folded chips above the top live level go into the final pot
        if li == #levels then
            for seat, amt in pairs(contributions) do
                if amt > level then amount = amount + (amt - level) end
            end
        end
        table.sort(eligible)
        if amount > 0 then pots[#pots + 1] = { amount = amount, eligible = eligible } end
        prev = level
    end
    return pots
end

-- IEEE CRC32, matching common online tools; uses WoW's bit library if available
do
    local bxor, band, rshift
    if bit and bit.bxor then
        bxor, band, rshift = bit.bxor, bit.band, bit.rshift
    else
        bxor = function(a, b)
            local r, p = 0, 1
            while a > 0 or b > 0 do
                local x, y = a % 2, b % 2
                if x ~= y then r = r + p end
                a, b, p = (a - x) / 2, (b - y) / 2, p * 2
            end
            return r
        end
        band = function(a, b)
            local r, p = 0, 1
            while a > 0 and b > 0 do
                local x, y = a % 2, b % 2
                if x == 1 and y == 1 then r = r + p end
                a, b, p = (a - x) / 2, (b - y) / 2, p * 2
            end
            return r
        end
        rshift = function(a, n) return math.floor(a / (2 ^ n)) end
    end

    local function u32(x) if x < 0 then x = x + 4294967296 end return x end

    local crcTable
    local function BuildTable()
        crcTable = {}
        for i = 0, 255 do
            local c = i
            for _ = 1, 8 do
                if c % 2 == 1 then
                    c = u32(bxor(rshift(c, 1), 0xEDB88320))
                else
                    c = rshift(c, 1)
                end
            end
            crcTable[i] = u32(c)
        end
    end

    function E.CRC32(str)
        if not crcTable then BuildTable() end
        local crc = 0xFFFFFFFF
        for i = 1, #str do
            local idx = u32(band(bxor(crc, str:byte(i)), 0xFF))
            crc = u32(bxor(rshift(crc, 8), crcTable[idx]))
        end
        crc = u32(bxor(crc, 0xFFFFFFFF))
        return string.format("%08x", crc)
    end
end
