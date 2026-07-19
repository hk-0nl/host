# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v5.aix`
- NovelUpdates v17: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v17.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

NovelUpdates v17 routes public NovelUpdates CDN covers through WordPress's `i0.wp.com` image CDN because direct CDN requests return 403 in Aidoku. Account and Cloudflare cookies are never forwarded to that image host. Chapter titles preserve raw release labels such as `c09` or `v1c07`; the visible metadata line includes `en`, date, and translation group where the primary series-page release table provides them. v17 matches primary-table metadata by exact release ID when linked and by normalized release label when NovelUpdates renders the Release cell as plain text. Complete, ongoing, canceled, dropped, and hiatus wording maps to Aidoku's native title-area status badge. `/extnu/{id}/` remains only the stable release key; chapter/group/series web fallback behavior is unchanged. Popular This Month entries include genre badges, and Home retains 33 tappable genre filters. Historical metadata beyond the primary release table, account tracking, and in-app translator-page extraction are not supported.
