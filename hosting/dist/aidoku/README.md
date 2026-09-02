# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v5.aix`
- Madokami v2: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.madokami-v2.aix`
- NovelUpdates v21: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v21.aix`
- NovelFire v1: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelfire-v1.aix`
- Royal Road v2: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.royalroad-v2.aix`
- Gelbooru v50: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.gelbooru-v50.aix`
- E-Hentai v6: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.ehentai-v6.aix`
- Hitomi v3: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.hitomi-v3.aix`
- nhentai v26: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.nhentai-v26.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

Madokami v2 provides authenticated search, author/genre filters, metadata, chapters, image pages, and deep links for the private Madokami server. A valid Madokami Basic Auth account is required. The package and non-credential protocol boundary are verified; authenticated catalog and reader behavior require a credentialed device smoke.

NovelFire v1 provides Popular, Ranking, Latest Releases, Recently Updated, New, and Completed listings; a four-section Home; title/author search; genre/status/country/order filters; rich covers, authors, genres, tags, descriptions, and status metadata; complete paginated English chapter lists with provider dates; public text reading; and book/chapter deep links. Seven serialized tests cover fixture contracts and the live public catalog/reader. Account library mutations are not supported.

Royal Road v2 provides nine discovery listings, a multi-section Home, title/keyword/author search, include/exclude tags, status/type/page/rating/sort filters, rich fiction metadata, dated English chapter titles, public text reading, and deep links. Search-backed discovery fallbacks keep listings and Home populated when Royal Road's canonical listing routes are unavailable. Account follows, favorites, notifications, and other mutations are not supported.

Gelbooru v50 provides signed-out search/filters; Latest and all-time Overall/Static/Animated discovery; Top Tags; categorized metadata; static/GIF/WebP image pages; explicit WebM/MP4 web handoff; Comments full-post discovery; distinct family, relationship-pool, and Similar Posts navigation; readable tags; optional family-as-chapters; saved searches; Favorites; and account/session controls. Saved-search chapters include bounded Gelbooru Tag Wiki help. V50 preserves provider-visible HTTP(S) labels and sends inline and See Also tag links to their Gelbooru wiki pages; stock Aidoku opens those links in Safari in scroll mode and leaves them inert in paged text. The reader browser button still opens the exact saved-search post listing. Website-session and DAPI features remain separate, and account mutations report provider results rather than claiming offline success.

E-Hentai v6 adds authenticated gallery favorite add/remove actions, source-local saved searches, and a bounded persistent page-manifest cache. Large galleries can be split into configurable 100, 250, 500, or 1000-page reader chapters to reduce Aidoku memory pressure; 250 pages is the default. Parallel manifest loading and reader chapter splitting are independent settings and can both be disabled. The full ordered manifest is cached across chunks, so later chunks and reopened galleries avoid rebuilding it. Eleven serialized tests cover discovery, metadata, saved-search and favorite states, 2,000-page cache and chapter splitting, original page-number preservation, MPV/Lo-Fi manifests, and animated-WebP resolution. A live 1,788-page gallery also passed the bounded final-chunk smoke test. Aidoku does not expose progress callbacks while a source constructs a page list, and iOS crash resistance still requires device testing.

Hitomi v3 provides recent/popular listings, text and creator/tag/type filters, rich gallery metadata, current `gg.js` image routing, language settings, and deep links. Its package metadata now declares the Aidoku 0.7.1 minimum required by its WASM API.

nhentai v26 adds public and favorite random discovery, Popular Month, popular tag browsing and API autocomplete across every provider category, dedicated filter boxes for all ten supported prefixes, raw prefixed main-search parity, and explicit provider-blacklist refresh/edit/apply controls. It retains v25 account favorites, local saved searches and blocklist, complete provider tags, readable creator handling, metadata, image pages, and deep links. Public mode uses nine requests per minute; a validated API key raises the shared budget to fifteen, with bounded response caching.

NovelUpdates v21 retains v18's cover routing, raw release labels, language/group/date display, native status badge, chapter handoff fallbacks, genre badges, and Home genre filters. It loads release pages 2+ through persistent-WebView navigation, discovers pagination across matching containers, and checks up to a 12-page safety cap. Decimal split labels such as `c214.1` are matched to release-table labels such as `c214 part1`; each page logs release-row and enrichment counts for runtime diagnosis. A failed page does not clear earlier metadata. Account tracking and in-app translator-page extraction are not supported.
