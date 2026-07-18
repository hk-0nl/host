# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v5.aix`
- NovelUpdates v15: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v15.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

NovelUpdates v15 routes public NovelUpdates CDN covers through WordPress's `i0.wp.com` image CDN because direct CDN requests return 403 in Aidoku. Account and Cloudflare cookies are never forwarded to that image host. Chapter titles preserve raw release labels such as `c09` or `v1c07`; the visible metadata line includes `en`, date, and translation group where the primary series-page release table provides them. v15 removes v14's unreliable secondary release-page requests to restore that known-good metadata path. Popular This Month entries now include genre badges, and Home retains 33 tappable genre filters. Historical date/group pagination, account tracking, and in-app translator-page extraction are not supported.
