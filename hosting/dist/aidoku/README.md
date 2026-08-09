# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v5.aix`
- Madokami v2: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.madokami-v2.aix`
- NovelUpdates v21: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v21.aix`
- NovelFire v1: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelfire-v1.aix`
- Royal Road v2: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.royalroad-v2.aix`
- Gelbooru v12: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.gelbooru-v12.aix`
- E-Hentai v4: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.ehentai-v4.aix`
- Hitomi v3: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.hitomi-v3.aix`
- nhentai v19: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.nhentai-v19.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

Madokami v2 provides authenticated search, author/genre filters, metadata, chapters, image pages, and deep links for the private Madokami server. A valid Madokami Basic Auth account is required. The package and non-credential protocol boundary are verified; authenticated catalog and reader behavior require a credentialed device smoke.

NovelFire v1 provides Popular, Ranking, Latest Releases, Recently Updated, New, and Completed listings; a four-section Home; title/author search; genre/status/country/order filters; rich covers, authors, genres, tags, descriptions, and status metadata; complete paginated English chapter lists with provider dates; public text reading; and book/chapter deep links. Seven serialized tests cover fixture contracts and the live public catalog/reader. Account library mutations are not supported.

Royal Road v2 provides nine discovery listings, a multi-section Home, title/keyword/author search, include/exclude tags, status/type/page/rating/sort filters, rich fiction metadata, dated English chapter titles, public text reading, and deep links. Search-backed discovery fallbacks keep listings and Home populated when Royal Road's canonical listing routes are unavailable. Account follows, favorites, notifications, and other mutations are not supported.

Gelbooru v12 provides signed-out search/filters, Latest and all-time Overall/Static/Animated discovery, Top Tags Home links, categorized metadata, static/GIF image pages, and explicit WebM/MP4 web fallback because Aidoku has no native video page type. Display All OFF adds Gelbooru's documented loli/shota exclusions to both HTML and DAPI queries, while ON removes them; the website preference cookie remains a secondary compatibility path. The media item is chapter 1 so Aidoku's Read action opens content first. Chapter 2 is Post information and includes provider-authored translation notes plus public comments with profile-linked author, timestamp, comment ID, body, and score when Gelbooru supplies them. Website authentication, Favorites, Saved Searches, comment mutations, and relationship groups remain foundations or planned work rather than claimed account functionality.

E-Hentai v4 adds read-only authenticated Favorites alongside Watched, richer language-filtered browse/Home metadata, Title Only and Uploader finder controls, a Require Gallery Torrent filter, and strict viewer recovery that rejects quota placeholders or HTML instead of returning them as images. Six serialized tests cover public discovery, Home, filters, details, chapters, deep links, and direct no-download animated-WebP URL resolution for gallery 4055860 pages 134/158. ExHentai, Favorites, and igneous refresh require a permitted account and remain credential-gated. Aidoku's static/tinted animated-WebP rendering is an app decoder limitation and is not fixed by this source release.

Hitomi v3 provides recent/popular listings, text and creator/tag/type filters, rich gallery metadata, current `gg.js` image routing, language settings, and deep links. Its package metadata now declares the Aidoku 0.7.1 minimum required by its WASM API.

nhentai v19 provides recent/popular listings, Home sections, creator/tag/sort filters, language/title/blocklist settings, rich gallery metadata, image pages, and deep links. It uses a conservative six-request-per-minute budget to leave headroom for Home plus follow-up requests, loads Home sections sequentially, and honors the provider's 60-second `Retry-After` once instead of returning blank search/listing results.

NovelUpdates v21 retains v18's cover routing, raw release labels, language/group/date display, native status badge, chapter handoff fallbacks, genre badges, and Home genre filters. It loads release pages 2+ through persistent-WebView navigation, discovers pagination across matching containers, and checks up to a 12-page safety cap. Decimal split labels such as `c214.1` are matched to release-table labels such as `c214 part1`; each page logs release-row and enrichment counts for runtime diagnosis. A failed page does not clear earlier metadata. Account tracking and in-app translator-page extraction are not supported.
