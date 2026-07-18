# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v5.aix`
- NovelUpdates v10: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v10.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

NovelUpdates v10 removes unsupported chapter thumbnails, selects the authenticated `data-id` / `extnu` release links for numeric and nonnumeric labels, and reloads its source-owned WebView after successful account or Cloudflare login changes. Series covers retain their request headers. NovelUpdates' chapter endpoint does not provide date or translation-group metadata; bounded enrichment from the series page remains planned. Account tracking and in-app translator-page extraction are not supported.
