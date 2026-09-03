# AOTW local ROM matching by hash

## Finding

Yes. Given the Achievement of the Week's `Game.ID`, NeoStation can request that
game's supported hashes, then compare them with the RetroAchievements hashes
already stored for local ROMs. The public API is directional: it supplies
**game → supported hashes**, rather than a single documented **hash → game**
lookup. That direction is ideal for one known AOTW game.

- [`API_GetGameHashes.php`](https://api-docs.retroachievements.org/v1/get-game-hashes.html)
  takes the required game ID (`i`) and returns `Results`, including each
  supported `MD5`, filename-like `Name`, `Labels`, and optional `PatchUrl`.
- The official RAWeb implementation returns only the game's
  `compatibleHashes`, so an exact comparison represents a supported RA ROM,
  not merely an arbitrary hash match. See
  [`API_GetGameHashes.php`](https://github.com/RetroAchievements/RAWeb/blob/master/public/API/API_GetGameHashes.php).

## Recommended design

1. Once AOTW metadata is available, use its game ID to request supported hashes
   through a small service method. Cache the result by RA game ID.
2. Ask the local repository for ROMs whose persisted `ra_hash` exactly matches
   one of those values. Prefer this over re-reading every file: NeoStation's
   existing library-match pass already computes and persists RA-specific
   hashes, and indexes the local RA game-list data.
3. If one or more candidates match, offer an explicit action such as **Play
   compatible local ROM**. If several match, present a picker showing filename
   and system; do not silently choose a copy.
4. If no stored candidate matches, say **No compatible local ROM found**. This
   is not proof the user does not own the game: a ROM may be unscanned,
   unhashable, or a dump/version RA does not support.

## Constraints

- Do not compare an arbitrary whole-file MD5 with RA values. RetroAchievements'
  [Game Identification guide](https://docs.retroachievements.org/developer-docs/game-identification.html)
  documents console-specific transformations, including stripped headers,
  Nintendo 64 byte-order normalization, and disc boot/executable data.
  Reuse NeoStation's established RA hash pipeline or a persisted `ra_hash`.
- `API_GetGameList.php?i=<console>&h=1` can return hashes for every game on a
  system, but RA's [endpoint documentation](https://api-docs.retroachievements.org/v1/get-game-list.html)
  warns responses can be huge and recommends aggressive caching. It is not
  needed for the known AOTW game.
- The API requires the user's web API key, and RA says rate limiting is enabled
  and static game data should be cached/preloaded. See the
  [API usage guidance](https://api-docs.retroachievements.org/).
- Do not build on legacy `dorequest.php?r=gameid` examples: the current docs
  distinguish the documented Web API from the private/locked-down Connect API.
  See the [Standalone integration guide](https://api-docs.retroachievements.org/connect/standalone.html).

## Implementation implication

This is an extension of the AOTW card's existing local-game affordance, not a
database migration: add a read-only repository query that joins `user_roms`
to each ROM's already-persisted `ra_hash`, then make a single cached RA request
for the featured game's supported hashes.
