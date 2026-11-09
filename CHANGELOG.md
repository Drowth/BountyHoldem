# Changelog

## 1.2.2 (2026-11-08)

- Leaderboard button moved under Host Table so it no longer hides behind Join Table
- New gold ? button for How to play
- Five new lobby scenes (mountain lodge, pirate ship, goblin casino, haunted crypt, moonlit glade). The lobby shows a different one each time it opens

## 1.2.1 (2026-11-08)

- Welcome window on first load explains how to play, step by step
- A ? button in the lobby opens it again any time

## 1.2.0 (2026-11-08)

- Leaderboard button in the lobby, next to Host Table

## 1.1.9 (2026-11-08)

- Chips are now shared by every character on your account, so you can play with your full bank on any alt
- The 1,000 daily kill cap and the 100-chip daily bonus are now once per account, not per character
- Season badges belong to your account and show under your name on every character
- Moving over: your bank starts at your richest character's balance (balances aren't added together)
- The leaderboard shows you as one line, under the character you're playing

## 1.1.8 (2026-11-08)

- Monthly seasons: on the 1st of every month the season ends and everyone's chips reset to 200
- Whoever tops your chip leaderboard when the month ends wins a season badge, shown under their name on the player frame. Badges stack, one for every season won
- The leaderboard now shows your characters and the players you've actually played with, with their season badges and the days left in the season
- The join prompt when someone in your group starts a table now reads "Do you want to join?" with Yes and No

## 1.1.7 (2026-11-08)

- Daily bonus: open poker once every 24 hours for 100 free chips (separate from the kill cap)

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
