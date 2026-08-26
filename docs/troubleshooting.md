---
title: Troubleshooting
layout: default
nav_order: 7
---

# Troubleshooting

## My games do not appear

1. Open **Settings → Directories** and confirm the ROM folder is listed.
2. Select **Rescan All ROM Folders**.
3. Check that the games are in a supported format for the detected system.
4. On Android, grant access again by choosing the ROM folder through the system picker.

## A game will not launch

Check the emulator configured for that system. NeoStation can report missing RetroArch, a missing RetroArch executable or core directory, a missing core, a missing standalone executable, or an unconfigured emulator. Configure or reinstall the item named in the message, then try again.

## Scraping fails

Confirm that you are signed in to ScreenScraper and that the game system is mapped. A successful metadata request can still have failed media downloads; retry after checking your connection.

## RetroAchievements has no matches

Run **Settings → Tools → Match RetroAchievements Games**. Matching a large library can take time and may be paused and resumed. Sign in to the RetroAchievements tab to view results.

## Steam Deck controls feel wrong

Launch NeoStation from Steam. See [Steam Deck & SteamOS](/platforms/steam-deck-and-steamos/) for the lizard-mode symptoms and setup.

## Collecting Useful Information

When opening an issue, include your platform, NeoStation version, the system and emulator involved, the exact error message, and whether the problem happens after a rescan or restart. Do not share account passwords or API keys.

## Related Pages

- [Getting Started](/getting-started/getting-started/)
- [Configuring Emulators](/configuration/configuring-emulators/)
- [Scraping & Metadata](/features/scraping-and-metadata/)
