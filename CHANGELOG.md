# Changelog

## 1.1.6 (2026-11-08)

- Every check, call, raise, fold and all-in now pops up in large letters on that player's seat, so bot moves are easy to follow
- Deal Hand only lights up when a hand can start. Otherwise it says why: "In play...", a countdown to the next hand, or "Need 2 players"
- Until you sit down, empty chairs pulse with SIT and the felt says "Click an empty chair to sit down"

## 1.1.5 (2026-11-08)

- New check sound: a quick double knock

## 1.1.4 (2026-11-08)

- Fixed multiplayer on servers that give characters a surname (sender shows as "Name Surname"). The host now recognises players, so seats get their chip stack, hands deal and players can act.
- Hole cards now reach players on those servers too
- The host no longer gets a "want to play?" prompt for their own table
- No more chat line for every kill; the chip pot already shows each gain. Type /poker killchat to turn it back on.

## 1.1.3 (2026-11-07)

- Closing the table window while hosting now closes your table. Before, bots and auto-deal kept playing on a table nobody could see, and hosting again picked up that old table.

## 1.1.2 (2026-11-07)

- Window size is now a small drag bar on the right edge of the lobby and the table. Drag up for bigger, down for smaller. The size is remembered per character.
- Resizing keeps the window where you put it instead of jumping back to the centre
- The table's Settings button is now Volume
- The lobby art always stays inside its own window

## 1.1.1 (2026-11-07)

- Fixed kills paying twice and two chip pots showing when an old copy in AddOns\Poker was still installed. The old copy is now switched off automatically; /reload and delete that folder.
- Only one installed copy of the addon ever runs

## 1.1.0 (2026-11-06)

First public release as Bounty Hold'em.

- Party and raid tables: one player hosts, the rest get an invite
- Chips from every kill, with a daily cap and a starter stack
- Chip pot on screen with a leaderboard on right-click
- Bots to fill empty seats
- Sit at a campfire to open the table
- New hand-painted deck, chips, seats, table and lobby
- New chip and card sounds
