# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v5.aix`
- NovelUpdates v12: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v12.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

NovelUpdates v12 routes public NovelUpdates CDN covers through WordPress's `i0.wp.com` image CDN because direct CDN requests return 403 in Aidoku. Account and Cloudflare cookies are never forwarded to that image host. Chapter titles include the NovelUpdates release ID and visible English language, while recent rows retain available date and translation-group metadata. Metadata enrichment is limited to releases present in the series-page table; account tracking and in-app translator-page extraction are not supported.
