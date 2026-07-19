# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v5.aix`
- NovelUpdates v20: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v20.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

NovelUpdates v20 retains v18's cover routing, raw release labels, language/group/date display, native status badge, chapter handoff fallbacks, genre badges, and Home genre filters. It removes v19's unreliable batch path, always restores the proven page-2 request, discovers release pagination across matching containers, and fetches later pages individually up to a 12-page safety cap. A failed page does not clear earlier metadata. Parted labels such as `c214 part1`, `part2`, and `part3` are matched independently. Account tracking and in-app translator-page extraction are not supported.
