# Bounty Hold'em: CurseForge kit

## Project details

- **Name:** Bounty Hold'em
- **Summary** (the one-liner under the name):
  > Texas Hold'em with your party. Every mob you kill pays you chips to play with.
- **Main category:** Minigames
- **Extra categories:** Roleplay
- **Game version:** the WoW Forever version (Interface 16001), the same one you pick for Fly2048
- **Licence:** All Rights Reserved (you can change it later)

## Description

Paste the README's How to play section, or this shorter version:

> **Kill stuff. Win chips. Play poker with your mates.**
>
> Every mob you kill drops chips into your pot. Normal mobs pay 1, elites 5, rares 25 and bosses 100. Grey mobs pay nothing.
>
> Got a group? One of you types **/poker host**, and everyone else gets a pop-up asking if they want to play. Click Play, grab a seat, and it's proper Texas Hold'em: blinds, raises, all-ins, best five cards wins.
>
> No group? Fill the seats with bots.
>
> Your chip pot sits on screen and bounces every time a kill pays out. Right-click it for a leaderboard of your alts and everyone you've played with.
>
> Chips are just for fun. No gold, no trading. Everyone at the table needs the addon.

## Logo prompt (400 x 400)

> Small square game icon, a single red poker chip with a little gold skull stamped in the middle, sitting on a dark green felt background, simple flat painted style with thick outlines, warm lighting from the top left, readable at 64 pixels, no text, no border

If it comes out too busy, add "minimal, two or three colours". Save it as a 400 x 400 PNG.

## Screenshots to grab

1. A full table mid-hand with the board out
2. The "has started a poker table, want to play?" pop-up
3. The chip pot with a green +5 dropping in
4. The leaderboard (right-click the pot)

## Uploading by hand

1. Go to CurseForge's authors site and click Create Project, then World of Warcraft, then Addon.
2. Fill in the name, summary, categories, description and logo from above, then submit. New projects go through a short approval.
3. Once it's approved, open Files, then Upload File. Pick `.release\BountyHoldem-1.1.0.zip`, set it to Release, pick the game version and paste the CHANGELOG text.
4. Copy the Project ID from the project's About box into the toc as `## X-Curse-Project-ID: 123456`, so future GitHub releases go to the same project.

## Automatic releases from GitHub (later)

1. Create a CurseForge API token (Account, then API tokens).
2. In the GitHub repo, open Settings, then Secrets and variables, then Actions, and add a secret called `CF_API_KEY` with the token.
3. Tag a release (for example `v1.1.1`) and push the tag. The workflow builds the zip and posts it to both CurseForge and GitHub.
