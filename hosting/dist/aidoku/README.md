# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v5.aix`
- NovelUpdates v19: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v19.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

NovelUpdates v19 retains v18's cover routing, raw release labels, language/group/date display, native status badge, chapter handoff fallbacks, genre badges, and Home genre filters. It detects the release paginator and fetches up to 12 pages in one bounded 30-second WebKit batch, preserving primary and successfully fetched metadata after partial failures. Parted labels such as `c214 part1`, `part2`, and `part3` are matched independently. The long-series acceptance target is Got Dropped into a Ghost Story, Still Gotta Work, currently 9 release pages. Account tracking and in-app translator-page extraction are not supported.
