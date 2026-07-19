# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v5.aix`
- NovelUpdates v21: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v21.aix`
- Royal Road v1: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.royalroad-v1.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

Royal Road v1 provides nine discovery listings, a multi-section Home, title/keyword/author search, include/exclude tags, status/type/page/rating/sort filters, rich fiction metadata, dated English chapter titles, public text reading, and deep links. Account follows, favorites, notifications, and other mutations are not supported.

NovelUpdates v21 retains v18's cover routing, raw release labels, language/group/date display, native status badge, chapter handoff fallbacks, genre badges, and Home genre filters. It loads release pages 2+ through persistent-WebView navigation, discovers pagination across matching containers, and checks up to a 12-page safety cap. Decimal split labels such as `c214.1` are matched to release-table labels such as `c214 part1`; each page logs release-row and enrichment counts for runtime diagnosis. A failed page does not clear earlier metadata. Account tracking and in-app translator-page extraction are not supported.
