import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

// ─── VyvyManga source for Mangayomi ──────────────────────────────────────────
// Site   : https://vyvymanga.net
// Type   : HTML scraper (Madara-family WordPress theme)
// Lang   : en
// NSFW   : false (SFW catalogue)
//
// ── Anti-bot posture ─────────────────────────────────────────────────────────
// VyvyManga serves a lightweight Cloudflare challenge on the first cold
// request from a new IP, but does NOT use JS rendering for content pages
// (the HTML is server-side rendered). This means:
//   • Browse, search, detail, chapter-list pages: plain client.get() works
//     once the CF cookie is satisfied via WebView (see note below).
//   • Image pages (reader): images are served directly from a CDN with a
//     Referer check. The "headers" map in getPageList() handles this.
//
// CF bypass strategy:
//   If client.get() receives an HTML page containing the CF challenge JS
//   rather than the expected manga listing, fall back to
//   evaluateJavascriptViaWebview() to let the in-app WebView solve the
//   challenge, capture the cookies, and return the rendered HTML.
//   The helper _fetchWithCfFallback() implements this pattern.
//
// ── Page structure ───────────────────────────────────────────────────────────
// Listing :  div.item  >  a[href]  >  img.thumb  (cover)
//            div.item  >  div.info  >  h3.title  >  a
// Detail  :  div.post-title  >  h1
//            div.description-summary > div.summary__content
//            div.post-status > div.summary-heading (status)
//            div.genres-content > a.badge
//            ul.main.version-chap > li.wp-manga-chapter
// Chapter :  div#manga-reading-nav-head  (page count)
//            div.page-break > img  (page images)
//            OR: window["chapter_preloaded_images"] JSON in <script>

class VyvyManga extends MProvider {
  VyvyManga({required this.source});

  final MSource source;
  final Client  client = Client();

  // ── Listing ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    final url = "${_base()}/manga/?m_orderby=trending&page=$page";
    final html = await _fetchWithCfFallback(url);
    return _parseListingPage(html);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = "${_base()}/manga/?m_orderby=latest&page=$page";
    final html = await _fetchWithCfFallback(url);
    return _parseListingPage(html);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    String status = "";
    String genre  = "";
    String order  = "";

    for (final f in filterList.filters) {
      if (f.name == "Status" && (f.state as int) > 0) {
        const statuses = ["", "ongoing", "completed", "hiatus", "cancelled"];
        final idx = f.state as int;
        if (idx < statuses.length) status = statuses[idx];
      }
      if (f.name == "Sort" && (f.state as int) > 0) {
        const sorts = ["", "trending", "views", "new-manga", "latest", "alphabet", "rating", "update"];
        final idx = f.state as int;
        if (idx < sorts.length) order = sorts[idx];
      }
    }

    String url = "${_base()}/?s=${Uri.encodeQueryComponent(query)}&post_type=wp-manga&page=$page";
    if (status.isNotEmpty) url += "&status[]=$status";
    if (genre.isNotEmpty)  url += "&genre[]=$genre";
    if (order.isNotEmpty)  url += "&m_orderby=$order";

    final html = await _fetchWithCfFallback(url);
    return _parseSearchPage(html);
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final html     = await _fetchWithCfFallback(url);
    final document = parseHtml(html);
    final manga    = MManga();

    manga.name = document.selectFirst("div.post-title h1, h1.manga-title")
        ?.text.trim() ?? "";

    manga.description = document
        .select("div.summary__content p")
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .join("\n\n");
    if (manga.description.isEmpty) {
      manga.description =
          document.selectFirst("div.summary__content, div.manga-description")
              ?.text.trim() ?? "";
    }

    manga.imageUrl = document
            .selectFirst("div.summary_image img")
            ?.attr("data-src") ??
        document.selectFirst("div.summary_image img")?.attr("src") ??
        "";

    manga.author = document
        .select("div.author-content a")
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .join(", ");

    manga.artist = document
        .select("div.artist-content a")
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .join(", ");

    manga.genre = document
        .select("div.genres-content a")
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final statusText = document
            .selectFirst("div.summary-content .post-status")
            ?.text
            .trim()
            .toLowerCase() ??
        "";
    manga.status = _parseStatus(statusText);

    // Chapter list — pass fetched html to avoid an extra network request
    final chapterHtml = await _fetchChapterList(url, html);
    manga.chapters    = _parseChapterList(chapterHtml, url);

    return manga;
  }

  // ── getPageList ───────────────────────────────────────────────────────────
  // Chapter URL → list of image URLs with headers.
  // VyvyManga embeds images in div.page-break > img[data-src] or img[src].
  // Some chapters also inject window["chapter_preloaded_images"] JSON in a
  // <script> tag; we check both.
  @override
  Future<List<dynamic>> getPageList(String url) async {
    final html     = await _fetchWithCfFallback(url);
    final document = parseHtml(html);

    // Primary: div.page-break images (lazy-loaded via data-src)
    final pageNodes = document.select(
      "div.page-break img, div.reading-content img",
    );

    if (pageNodes.isNotEmpty) {
      return pageNodes.map((el) {
        final src = el.attr("data-src").trim().isNotEmpty
            ? el.attr("data-src").trim()
            : el.attr("src").trim();
        return {
          "url": src,
          "headers": {
            "Referer": _base() + "/",
            "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-VyvyManga/1.0)",
            "Connection": "close",
          },
        };
      }).toList();
    }

    // Fallback: extract from window["chapter_preloaded_images"] JSON
    final preloadMatch = RegExp(
      r'''window\["chapter_preloaded_images"\]\s*=\s*(\[.*?\]);''',
      dotAll: true,
    ).firstMatch(html);
    if (preloadMatch != null) {
      try {
        final raw    = jsonDecode(preloadMatch.group(1)!);
        final images = (raw as List).cast<String>();
        return images.map((src) => {
          "url": src,
          "headers": {
            "Referer": _base() + "/",
            "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-VyvyManga/1.0)",
            "Connection": "close",
          },
        }).toList();
      } catch (_) {}
    }

    // Last resort: open the chapter URL itself
    return [
      {
        "url": url,
        "headers": {"Referer": _base() + "/", "Connection": "close"},
      }
    ];
  }

  // ── Private: chapter list fetcher ─────────────────────────────────────────

  /// Fetches the chapter list via the Madara AJAX endpoint.
  /// [rawDetailHtml] is the already-fetched detail page HTML — we pass it in
  /// to avoid a redundant second request.
  Future<String> _fetchChapterList(String mangaUrl, String rawDetailHtml) async {
    // Extract the numeric post ID from the already-fetched detail HTML
    try {
      final idMatch = RegExp(r'manga_id["\s:=]+(\d+)').firstMatch(rawDetailHtml);
      if (idMatch != null) {
        final mangaId = idMatch.group(1)!;
        final ajaxUrl = "${_base()}/wp-admin/admin-ajax.php";
        final res = await client.post(
          Uri.parse(ajaxUrl),
          headers: {
            "Content-Type": "application/x-www-form-urlencoded",
            "Referer":      mangaUrl,
            "User-Agent":   "Mozilla/5.0 (compatible; Mangayomi-VyvyManga/1.0)",
            "X-Requested-With": "XMLHttpRequest",
            "Connection":   "close",
          },
          body: "action=manga_get_chapters&manga=$mangaId",
        );
        if (res.body.contains("wp-manga-chapter")) return res.body;
      }
    } catch (_) {}
    // Fallback: chapter list is embedded directly in the detail page
    return rawDetailHtml;
  }

  // ── Private: parsers ──────────────────────────────────────────────────────

  MPages _parseListingPage(String html) {
    final document = parseHtml(html);
    final items    = <MManga>[];

    for (final el in document.select("div.c-tabs-item__content, div.page-item-detail")) {
      final anchor = el.selectFirst("a");
      if (anchor == null) continue;
      final link = anchor.attr("href").trim();
      if (link.isEmpty) continue;

      final title = el.selectFirst("h3.h5, span.font-title, .post-title")
              ?.text.trim() ??
          el.selectFirst("a")?.attr("title")?.trim() ??
          "";
      final img = el.selectFirst("img");
      final cover = img?.attr("data-src")?.trim().isNotEmpty == true
          ? img!.attr("data-src").trim()
          : img?.attr("src")?.trim() ?? "";

      final manga = MManga();
      manga.name     = title;
      manga.imageUrl = cover;
      manga.link     = link;
      items.add(manga);
    }
    final hasNext = html.contains('class="next page-numbers"') ||
        html.contains("nav-next");
    return MPages(items, hasNext);
  }

  MPages _parseSearchPage(String html) {
    final document = parseHtml(html);
    final items    = <MManga>[];

    for (final el in document.select("div.c-tabs-item__content, div.row.c-tabs-item")) {
      final anchor = el.selectFirst("a");
      if (anchor == null) continue;
      final link = anchor.attr("href").trim();
      if (link.isEmpty) continue;

      final title = el.selectFirst("h3, .post-title")?.text.trim() ??
          anchor.attr("title")?.trim() ?? "";
      final img   = el.selectFirst("img");
      final cover = img?.attr("data-src")?.trim().isNotEmpty == true
          ? img!.attr("data-src").trim()
          : img?.attr("src")?.trim() ?? "";

      final manga = MManga();
      manga.name     = title;
      manga.imageUrl = cover;
      manga.link     = link;
      items.add(manga);
    }
    final hasNext = html.contains('class="next page-numbers"');
    return MPages(items, hasNext);
  }

  List<MChapter> _parseChapterList(String html, String mangaUrl) {
    final document = parseHtml(html);
    final chapters = <MChapter>[];

    for (final el in document.select("li.wp-manga-chapter")) {
      final anchor = el.selectFirst("a");
      if (anchor == null) continue;
      final url    = anchor.attr("href").trim();
      final name   = anchor.text.trim();
      final date   = el.selectFirst("span.chapter-release-date i")?.text.trim() ?? "";
      if (url.isEmpty || name.isEmpty) continue;

      chapters.add(MChapter(
        name:       name,
        url:        url,
        dateUpload: date,
      ));
    }
    return chapters;
  }

  int _parseStatus(String raw) {
    if (raw.contains("ongoing"))   return 0;
    if (raw.contains("completed")) return 1;
    if (raw.contains("hiatus"))    return 2;
    if (raw.contains("cancelled") || raw.contains("canceled")) return 3;
    return 5;
  }

  // ── CF-bypass helper ──────────────────────────────────────────────────────

  /// Fetches a URL. If the response looks like a Cloudflare challenge page
  /// (contains the CF challenge JS signatures), falls back to
  /// evaluateJavascriptViaWebview() to solve it in the embedded browser.
  Future<String> _fetchWithCfFallback(String url) async {
    try {
      final res = await client.get(Uri.parse(url), headers: _headers());
      if (_isCfChallenge(res.body)) {
        // Let the in-app WebView handle the challenge.
        // The JS evaluates the CF challenge, sets cookies, and returns the
        // page HTML after a brief wait.
        final rendered = await evaluateJavascriptViaWebview(url);
        if (rendered != null && rendered.isNotEmpty && !_isCfChallenge(rendered)) {
          return rendered;
        }
        // CF still blocking — return what we have and let the caller fail
        // gracefully rather than crash.
      }
      return res.body;
    } catch (e) {
      // On network errors, try WebView before giving up
      try {
        final rendered = await evaluateJavascriptViaWebview(url);
        if (rendered != null && rendered.isNotEmpty) return rendered;
      } catch (_) {}
      rethrow;
    }
  }

  bool _isCfChallenge(String html) {
    return html.contains("cf_chl_") ||
        html.contains("jschl-answer") ||
        html.contains("Checking your browser") ||
        html.contains("challenge-form");
  }

  // ── Misc ──────────────────────────────────────────────────────────────────

  String _base() {
    final v = _pref("domain_url");
    if (v.isNotEmpty) return v.endsWith("/") ? v.substring(0, v.length - 1) : v;
    return source.baseUrl;
  }

  String _pref(String key) =>
      getPreferenceValue(source.id, key)?.toString().trim() ?? "";

  Map<String, String> _headers() => {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
        "Accept":     "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Referer": _base() + "/",
        "Connection": "close",
      };

  // ── Filters ───────────────────────────────────────────────────────────────

  @override
  List<dynamic> getFilterList() {
    return [
      SelectFilter("SelectFilter", "Status", 0, [
        SelectFilterOption("Any",       "",          null),
        SelectFilterOption("Ongoing",   "ongoing",   null),
        SelectFilterOption("Completed", "completed", null),
        SelectFilterOption("Hiatus",    "hiatus",    null),
        SelectFilterOption("Cancelled", "cancelled", null),
      ], null),
      SelectFilter("SelectFilter", "Sort", 0, [
        SelectFilterOption("Default",    "",           null),
        SelectFilterOption("Trending",   "trending",   null),
        SelectFilterOption("Most Views", "views",      null),
        SelectFilterOption("Newest",     "new-manga",  null),
        SelectFilterOption("Latest",     "latest",     null),
        SelectFilterOption("A-Z",        "alphabet",   null),
        SelectFilterOption("Rating",     "rating",     null),
        SelectFilterOption("Updated",    "update",     null),
      ], null),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key:          "domain_url",
        title:        "Base URL",
        summary:      "Default: https://vyvymanga.net",
        value:        source.baseUrl,
        dialogTitle:  "URL",
        dialogMessage: "",
      ),
    ];
  }
}

VyvyManga main(MSource source) => VyvyManga(source: source);
