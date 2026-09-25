# Aidoku Sources

Install the source list in Aidoku:

- `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/index.json`

Current packages:

- Anna's Archive v10: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.annasarchive-v10.aix`
- Madokami v2: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.madokami-v2.aix`
- NovelUpdates v21: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelupdates-v21.aix`
- NovelFire v1: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.novelfire-v1.aix`
- Royal Road v2: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.royalroad-v2.aix`
- Gelbooru v71: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.gelbooru-v71.aix`
- E-Hentai v14: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.ehentai-v14.aix`
- Hitomi v3: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.hitomi-v3.aix`
- nhentai v26: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.nhentai-v26.aix`
- BookReadFree v2: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.bookreadfree-v2.aix`
- Scribble Hub v5: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.scribblehub-v5.aix`
- Web Novel Translations v3: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.webnoveltranslations-v3.aix`
- Wordrain69 v2: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.wordrain69-v2.aix`
- OPDS Catalog v6: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/en.opds-v6.aix`
- Kemono v6: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.kemono-v6.aix`
- Newgrounds v19: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.newgrounds-v19.aix`
- Danbooru v23: `https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/aidoku/sources/multi.danbooru-v23.aix`

Anna's Archive defaults to `annas-archive.gl`. Change the source settings to use `.li`, `.org`, `.se`, or a custom reachable mirror.

OPDS Catalog v6 supports OPDS 1.x/2.x navigation, facets, ordered publication
resources, an editable list of feed roots, bounded Combined browsing, optional
search across mounted feeds, explicit HTML catalog discovery, provider-advertised
advanced search fields, richer acquisition metadata, and on-demand diagnostics.
EPUB/PDF/CBZ/CBR decoding and local import remain host-application responsibilities.

Kemono v4 provides public post, creator, service, tag, DM, popular, and random
discovery; scoped service/creator/media filters; creator timelines; local saved
searches; and authenticated provider favorites. Reader media uses compatible
previews by default with optional original files, while video/audio/archive
attachments retain explicit web fallbacks. V4 also repairs native Aidoku tag and
artist routing, provider shard URLs, session-first mutations, and companion
content duplication. Private or paid content, archive extraction, and native
video/audio reading remain unsupported.

Newgrounds v13 provides Featured, Latest, Popular, Animated, and Comics art
discovery plus Movie, Game, Collection, Forum, Artist News, and Audio discovery;
title, creator, tag, category, rating,
date, animation, frontpage, field-match, and sort filters; rich submission
metadata; static and multi-image art reading; medium/original image quality;
deep links; and explicit Newgrounds handoffs for Game, Movie, and Audio playback.
Collections use Newgrounds' first-party visual-link endpoint for sleeves, authors,
descriptions, and an in-source paged entry index. Community cards expose readable
topic/post details and provider handoffs. Home includes separate Art, Movie,
Game, and Audio sections plus links to the heavier Collection and Community
listings. A configured profile adds paginated Favorite Art, Movie, Game, and Audio
listings, and a signed-in browser
session enables account-gated submissions plus scoped add/remove favorite
actions using Newgrounds' current rendered provider forms inside the authenticated source WebView. V4 captures parent-domain browser
cookies and validates an authenticated provider page before closing or persisting the
login sheet. V5 keeps free-text and provider tags separate, supports comma-separated
multi-tag filters, and uses fast native HTML requests before falling back to the bounded
WebView for NG Guard. V6 captures Newgrounds' own rendered favorite request contract
before replaying it with the persisted account session. V7 also forwards the page-specific
CSRF request header required by Newgrounds' same-site AJAX prefilter. V9 keeps
dead or removed links out of the WebView fallback, adds isolated Collection,
Forum, and Artist News search scopes, reads full forum pages and news comments,
and exposes public Favorite Games. V10 bounds and resets the hidden action
WebView on every outcome, discovers long forum page counts from provider
pagination text, and splits oversized forum/news posts into bounded reader pages.
V11 observes the provider's own `ajaxSubmit` success and error callbacks instead
of relying on document-level AJAX events, so account actions receive the exact
completion result from the authenticated source WebView. V12 invokes that
first-party helper directly on the selected rendered form, avoiding a jQuery
instance mismatch while preserving provider serialization, session cookies,
and actionable provider errors. V13 selects only the rendered form bound to
Newgrounds' actual `NgFavorites` handler while explicitly excluding review forms,
preventing favorite actions from submitting the review agreement workflow.
V14 uses Newgrounds' current favorite widget on the authenticated submission
page and confirms the returned favorite state. Favorite target links are
restricted to Newgrounds submission URLs before the source forwards cookies.
V15 adds creator Follow/Unfollow links to signed-in submission details using
the first-party follow widget. It requires a single matching creator control
and confirms the provider's returned active state before reporting success.
V16 also displays Follow/Unfollow when the fetched public page appears signed out;
the action still checks the authenticated WebView session before changing state.
Local saved searches retain
the full query and filter expression and are available from Home, a dedicated
listing, search utility items, and source settings. Aidoku's external
browser has a separate cookie store, so browser handoffs may require another sign-in.
Uploads and native video/audio playback remain unsupported.

Danbooru v23 adds opt-in Oldest and Score Low (Last Month) search sorts while
keeping the existing sort choices unchanged. Query-builder and free-tier budget
tests pass; provider result ordering still needs an on-device check because
workstation requests to the posts API receive Cloudflare responses. V22 remains
available for rollback.

Madokami v2 provides authenticated search, author/genre filters, metadata, chapters, image pages, and deep links for the private Madokami server. A valid Madokami Basic Auth account is required. The package and non-credential protocol boundary are verified; authenticated catalog and reader behavior require a credentialed device smoke.

NovelFire v1 provides Popular, Ranking, Latest Releases, Recently Updated, New, and Completed listings; a four-section Home; title/author search; genre/status/country/order filters; rich covers, authors, genres, tags, descriptions, and status metadata; complete paginated English chapter lists with provider dates; public text reading; and book/chapter deep links. Seven serialized tests cover fixture contracts and the live public catalog/reader. Account library mutations are not supported.

Royal Road v2 provides nine discovery listings, a multi-section Home, title/keyword/author search, include/exclude tags, status/type/page/rating/sort filters, rich fiction metadata, dated English chapter titles, public text reading, and deep links. Search-backed discovery fallbacks keep listings and Home populated when Royal Road's canonical listing routes are unavailable. Account follows, favorites, notifications, and other mutations are not supported.

Gelbooru v50 provides signed-out search/filters; Latest and all-time Overall/Static/Animated discovery; Top Tags; categorized metadata; static/GIF/WebP image pages; explicit WebM/MP4 web handoff; Comments full-post discovery; distinct family, relationship-pool, and Similar Posts navigation; readable tags; optional family-as-chapters; saved searches; Favorites; and account/session controls. Saved-search chapters include bounded Gelbooru Tag Wiki help. V50 preserves provider-visible HTTP(S) labels and sends inline and See Also tag links to their Gelbooru wiki pages; stock Aidoku opens those links in Safari in scroll mode and leaves them inert in paged text. The reader browser button still opens the exact saved-search post listing. Website-session and DAPI features remain separate, and account mutations report provider results rather than claiming offline success.

Gelbooru v69 adds an opt-in Oldest search sort using the provider's documented
`sort:id:asc` token. Existing sort choices and defaults are unchanged. The
50-test WASM suite and package/schema checks pass; on-device result order is
the remaining check. V68 remains available for rollback.

Gelbooru v70 adds an Advanced Query filter that passes raw provider syntax,
including `{blue_hair ~ red_hair}` for ordinary-tag OR. Saved searches retain
the exact expression, use it as the label instead of splitting group syntax,
and keep only real tags in native tag/wiki lists. A live two-page source test
checks OR membership and distinct pagination; the 51-test WASM suite passes.
Native on-device filter and account-backed saved-search checks remain.
V69 remains available for rollback.

Gelbooru v71 replaces the visible single-choice Media search filter with an
Aidoku include/exclude/cancel multi-select for Animated, Video, and Sound.
Older saved searches using the previous Media filter still resolve. The
52-test WASM suite, release package, and schema validation pass; v70 remains
available for rollback.

E-Hentai v13 keeps v12's split-gallery caching, timeout protection, ExHentai session priming, and selected-domain actions. Accounts with Gold Star or the Multi-Page Viewer Hath perk still use one compact MPV manifest. Because ordinary credentials do not unlock MPV, the default fallback builds and persists one full-gallery Lo-Fi manifest so every split chapter becomes warm after the initial crawl. V13 stores large manifests in bounded 250-entry defaults chunks, validates complete provider page counts, falls back to standard gallery pagination when Lo-Fi construction fails, and reports the exact Full Gallery failure instead of silently presenting a range cache as success. A Range Only setting retains the lower-cost per-chunk behavior. Nineteen deterministic tests, a live 1,256-page full-manifest crawl, and all Aidoku package/schema gates pass. V12 remains available for rollback.

Hitomi v3 provides recent/popular listings, text and creator/tag/type filters, rich gallery metadata, current `gg.js` image routing, language settings, and deep links. Its package metadata now declares the Aidoku 0.7.1 minimum required by its WASM API.

nhentai v26 adds public and favorite random discovery, Popular Month, popular tag browsing and API autocomplete across every provider category, dedicated filter boxes for all ten supported prefixes, raw prefixed main-search parity, and explicit provider-blacklist refresh/edit/apply controls. It retains v25 account favorites, local saved searches and blocklist, complete provider tags, readable creator handling, metadata, image pages, and deep links. Public mode uses nine requests per minute; a validated API key raises the shared budget to fifteen, with bounded response caching.

BookReadFree v2 provides Featured and Latest discovery, title search, cover and author metadata, newest-first page-part chapters, text reading with AMP fallback, supported inline image pages, and book/chapter deep links. Transient Nginx/502 documents are rejected instead of being exposed as blank titles.

Scribble Hub v5 uses Scribble Hub's public `fictionapp/v1` API for Trending, Latest Series, and Recently Updated discovery, search, series metadata, bounded chapter loading, text reading, supported inline image pages, deep links, and release dates/language metadata. It does not require a Cloudflare verification panel or account credentials; the prior WebView-based v1-v4 packages remain available in the repository for rollback.

Web Novel Translations v2 uses the current wntl.net JSON contract for Latest, Popular, and Completed discovery, search, covers, metadata, ordered chapter loading, text reading, and deep links. The provider endpoint currently fails the desktop native TLS handshake in this environment; treat native transport as requiring device validation.

Wordrain69 v2 provides Latest and Popular discovery, search, metadata, oldest-first AJAX chapter loading, text reading, meaningful inline image pages, and deep links. Small promotional images are excluded from reader pages, and the Popular listing uses the provider-supported views order.

NovelUpdates v21 retains v18's cover routing, raw release labels, language/group/date display, native status badge, chapter handoff fallbacks, genre badges, and Home genre filters. It loads release pages 2+ through persistent-WebView navigation, discovers pagination across matching containers, and checks up to a 12-page safety cap. Decimal split labels such as `c214.1` are matched to release-table labels such as `c214 part1`; each page logs release-row and enrichment counts for runtime diagnosis. A failed page does not clear earlier metadata. Account tracking and in-app translator-page extraction are not supported.
