# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v5.aix`
- NovelUpdates v16: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v16.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

NovelUpdates v16 routes public NovelUpdates CDN covers through WordPress's `i0.wp.com` image CDN because direct CDN requests return 403 in Aidoku. Account and Cloudflare cookies are never forwarded to that image host. Chapter titles preserve raw release labels such as `c09` or `v1c07`; the visible metadata line includes `en`, date, and translation group where the primary series-page release table provides them. `/extnu/{id}/` is retained only as the stable release key. The web destination now prefers a direct translator URL or NovelUpdates `nu_goto_chapter` link, then the translation-group page, then the series page; the text reader exposes the same destination as a Markdown link. Popular This Month entries include genre badges, and Home retains 33 tappable genre filters. Historical date/group pagination, account tracking, and in-app translator-page extraction are not supported.
