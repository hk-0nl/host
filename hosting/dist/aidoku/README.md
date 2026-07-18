# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v5.aix`
- NovelUpdates v11: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v11.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

NovelUpdates v11 enriches recent chapters from the series page's Latest Release table with compact chapter labels, dates, and translation groups. It also persists successful account and Cloudflare WebView cookie snapshots and forwards them to NovelUpdates CDN cover requests. Reopen both login settings once after updating so v11 can capture the current cookies. Metadata enrichment is limited to releases present in the series-page table; account tracking and in-app translator-page extraction are not supported.
