---
title: RetroAchievements
layout: default
parent: Features
nav_order: 1
---

# RetroAchievements

NeoStation connects to your RetroAchievements account so you can browse matched games, achievement progress, recent unlocks, completions, masteries, and per-game leaderboards without leaving the app.

## Sign In

1. Open the **RetroAchievements** tab.
2. Enter your RetroAchievements username.
3. Enter your personal Web API key.
4. Select **Login**.

Use **Get API Key** in NeoStation to open the RetroAchievements control panel, where you can obtain your personal key. NeoStation does not use a shared build-time key. Your API key is used for your account's requests and is stored with the rest of your saved login credentials when the device allows it.

If the device cannot save the credentials, the session can still work until you sign out or close the app. You will need to sign in again next time.

## The RetroAchievements Mini-App

After you sign in, the tab is divided into three sub-tabs: **Dashboard**, **Unlocks**, and **Games**. Use the pill strip, touch, or the D-pad to switch between them. The active sub-tab owns its data loading, so switching away does not keep its spinner or requests running.

### Dashboard

The Dashboard contains your profile and standing, Achievement of the Week, and compact previews of your recent unlocks, recently played games, completions, and masteries. Your profile includes a standing pill with your rank and percentile when those values are available. Select **Refresh** in the header to reload the active RetroAchievements view without leaving the tab.

### Unlocks

**Unlocks** shows your recent achievements from the last 30 days. Open the full list to browse more results. Selecting an unlock opens the game's RetroAchievements page and highlights that achievement. This works whether or not the game is installed locally.

### Games

**Games** combines your recently played games with your completion-progress games into one list. Use the filters to show **All**, **Mastered**, or **Beaten** games. Beaten includes games with a beaten softcore, beaten hardcore, completed, or mastered award; mastered remains available as its own narrower filter. The list is loaded in pages as you move through it, including when a filtered result is beyond the first page. Selecting a game opens its RetroAchievements page.

## Game Achievements

Selecting a game from **Games**, or selecting an unlock from **Unlocks**, opens a dedicated RetroAchievements page keyed by the game's RA ID. The page shows the artwork, console, achievement totals, casual and hardcore progress, and the complete achievement list in API order. Use **All**, **Unlocked**, **Locked**, or **Missable** filters; missable is an overlapping category and can include unlocked achievements. Each row shows its badge, description, points, available unlock date, and casual/hardcore rarity when the API provides valid counts. An external guide action appears only when the game supplies a valid web URL.

The game page also contains a **Leaderboards** view. It loads only when opened, shows paginated entries, and highlights the signed-in user's entry when RetroAchievements returns one. A game can have no leaderboards or no entries even when the game itself is matched.

## Match Your Library

NeoStation can match new ROMs after the startup scan. To process your whole library with visible progress:

1. Open **Settings → Tools**.
2. Select **Match RetroAchievements Games**.

Matching reads unmatched ROMs to identify them. It can take several minutes for a large library. Selecting the tool again pauses it; completed matches are kept and a later run continues. Disc images are sampled, but NeoStation does not move or delete files while matching.

You can run matching while signed out, but you must sign in to see RetroAchievements results. When a match needs correcting, NeoStation provides a RetroAchievements title search for a manual match.

## Offline Use

NeoStation caches successful RetroAchievements responses on the device. If the network is unavailable and cached data exists, the tab can show the last synced results and displays an offline banner. New data, uncached pages, and refreshes need a connection; reconnect and select **Refresh** to update them.

## Sign Out

Disconnecting signs you out and removes the saved RetroAchievements credentials from that device. Cached account data is cleared with the session.

## Related Pages

- [Adding Your Games](/library/adding-your-games/)
- [Troubleshooting](/troubleshooting/)
