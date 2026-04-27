import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

// ─── Kmanga source for Mangayomi ──────────────────────────────────────────────
// Site   : https://kmanga.nettruyenplus.com   (primary)
//          Mirror: https://kmanga.app         (alternate — set in prefs)
// Type   : HTML scraper (Madara / nettruyenplus hybrid)
// Lang   : en
// NSFW   : false (SFW catalogue — no explicit content)
//
// ── DRM / Geo-block analysis ─────────────────────────────────────────────────
// KManga is an aggregator, not an official publisher. As of 2025:
//   • No DRM on chapter images. Page images are served as standard JPGs/PNGs
//     from a CDN (usually cdn.kmanga.* or a shared nettruyenplus CDN).
//   • Light Cloudflare presence on some mirrors, but no JS challenge.
//     A browser-style User-Agent + Referer header is sufficient.
//   • Geo-restrictions: none observed, but the domain rotates frequently.
//     Domain override preference is provided for resilience.
//   • No image scrambling or canvas-drawing observed.
//
// ── Page structure ───────────────────────────────────────────────────────────
// Listing (Madara theme):
//   div.page-item-detail.manga  >  div.item-thumb  >  a[href]  >  img
//   div.page-item-detail.manga  >  div.item-summary  >  h3.h5  >  a
//
// Search: POST to /?s=<query>&post_type=wp-manga
//
// Detail:
//   div.post-title h1           → series name
//   div.summary__content        → description
//   div.manga-authors a         → author
//   div.genres-content a        → genres
//   div.post-status             → status
//   div.summary_image img       → cover (data-src or src)
//   ul.main.version-chap > li.wp-manga-chapter → chapters
//
// Chapter reader:
//   div.page-break img[data-src]  → page images (lazy-loaded)
//   Script: window["chapter_preloaded_images"] = [...]  (fallback)

class Kmanga extends MProvider {
  Kmanga({required this.source});

  final MSource source;
  final Client  client = Client();

  // ── Listing ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    final url  = "${_base()}/manga/?m_orderby=trending&page=$page";
    final res  = await client.get(Uri.parse(url), headers: _headers());
    return _parseListing(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url  = "${_base()}/manga/?m_orderby=latest&page=$page";
    final res  = await client.get(Uri.parse(url), headers: _headers());
    return _parseListing(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    String statusTag = "";
    String sortTag   = "";

    for (final f in filterList.filters) {
      if (f.name == "Status" && (f.state as int) > 0) {
        const statuses = ["", "ongoing", "completed", "hiatus", "cancelled"];
        final idx = f.state as int;
        if (idx < statuses.length) statusTag = statuses[idx];
      }
      if (f.name == "Sort" && (f.state as int) > 0) {
        const sorts = ["", "trending", "views", "new-manga", "latest", "alphabet", "rating"];
        final idx   = f.state as int;
        if (idx < sorts.length) sortTag = sorts[idx];
      }
    }

    String url = "${_base()}/?s=${Uri.encodeQueryComponent(query)}&post_type=wp-manga&page=$page";
    if (statusTag.isNotEmpty) url += "&status[]=$statusTag";
    if (sortTag.isNotEmpty)   url += "&m_orderby=$sortTag";

    final res = await client.get(Uri.parse(url), headers: _headers());
    return _parseListing(res.body);
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final res      = await client.get(Uri.parse(url), headers: _headers());
    final document = parseHtml(res.body);
    final manga    = MManga();

    manga.name = document.selectFirst("div.post-title h1, h1.manga-title")
        ?.text.trim() ?? "";

    // Description: prefer multi-paragraph form, fall back to full block text
    final descParagraphs = document
        .select("div.summary__content p")
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .join("\n\n");
    manga.description = descParagraphs.isNotEmpty
        ? descParagraphs
        : document.selectFirst("div.summary__content, div.manga-excerpt")
            ?.text.trim() ?? "";

    // Cover image — try data-src (lazy-loaded) first, then src
    final imgEl = document.selectFirst("div.summary_image img, .manga-thumbnail img");
    manga.imageUrl = imgEl?.attr("data-src")?.trim().isNotEmpty == true
        ? imgEl!.attr("data-src").trim()
        : imgEl?.attr("src")?.trim() ?? "";

    manga.author = document
        .select("div.author-content a, .manga-authors a")
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .join(", ");

    manga.artist = document
        .select("div.artist-content a")
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .join(", ");

    manga.genre = document
        .select("div.genres-content a, .genre-list a")
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final statusRaw = document
            .selectFirst("div.post-status .summary-content, .manga-status")
            ?.text.trim().toLowerCase() ??
        "";
    manga.status = _parseStatus(statusRaw);

    // Chapter list — try AJAX first, fall back to embedded HTML
    manga.chapters = await _fetchChapters(url, res.body);

    return manga;
  }

  // ── getPageList ───────────────────────────────────────────────────────────
  // No DRM on KManga. Images are standard JPGs served from a CDN.
  // Returns headers map to satisfy the CDN Referer check.
  @override
  Future<List<dynamic>> getPageList(String url) async {
    final res      = await client.get(Uri.parse(url), headers: _chapterHeaders(url));
    final document = parseHtml(res.body);

    // Primary: div.page-break img[data-src] (Madara lazy-load pattern)
    final pageEls = document.select(
      "div.page-break img, div.reading-content img, #arraydata img",
    );

    if (pageEls.isNotEmpty) {
      final pages = <dynamic>[];
      for (final el in pageEls) {
        String src = el.attr("data-src").trim();
        if (src.isEmpty) src = el.attr("src").trim();
        if (src.isEmpty) continue;
        // Resolve protocol-relative URLs
        if (src.startsWith("//")) src = "https:$src";
        pages.add({
          "url": src,
          "headers": {
            "Referer":    url,
            "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-Kmanga/1.0)",
            "Connection": "close",
          },
        });
      }
      if (pages.isNotEmpty) return pages;
    }

    // Fallback: window["chapter_preloaded_images"] = ["url1", "url2", ...]
    final preloadMatch = RegExp(
      r'''window\["chapter_preloaded_images"\]\s*=\s*(\[.*?\]);''',
      dotAll: true,
    ).firstMatch(res.body);
    if (preloadMatch != null) {
      try {
        final raw    = jsonDecode(preloadMatch.group(1)!);
        final images = (raw as List).cast<String>();
        return images.map((src) => {
          "url":     src.startsWith("//") ? "https:$src" : src,
          "headers": {
            "Referer":    url,
            "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-Kmanga/1.0)",
            "Connection": "close",
          },
        }).toList();
      } catch (_) {}
    }

    // Fallback 2: look for #arraydata hidden input value
    final arrayData = document.selectFirst("#arraydata")?.attr("value") ??
        RegExp(r'"arraydata"\s*value="([^"]+)"').firstMatch(res.body)?.group(1);
    if (arrayData != null && arrayData.isNotEmpty) {
      final urls = arrayData.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty);
      return urls.map((src) => {
        "url":     src.startsWith("//") ? "https:$src" : src,
        "headers": {"Referer": url, "Connection": "close"},
      }).toList();
    }

    throw Exception(
      "Kmanga: could not extract page images from chapter: $url\n"
      "The site layout may have changed. Try opening the chapter in the WebView.",
    );
  }

  // ── Private: chapter fetcher ──────────────────────────────────────────────

  Future<List<MChapter>> _fetchChapters(
    String mangaUrl,
    String rawHtml,  // raw HTML string from detail page (avoids .outerHtml)
  ) async {
    // Extract manga ID from the page HTML via regex
    final idMatch = RegExp(r'manga_id[":\s=]+(\d+)').firstMatch(rawHtml);

    if (idMatch != null) {
      final mangaId = idMatch.group(1)!;
      try {
        final ajaxRes = await client.post(
          Uri.parse("${_base()}/wp-admin/admin-ajax.php"),
          headers: {
            "Content-Type":     "application/x-www-form-urlencoded",
            "Referer":          mangaUrl,
            "X-Requested-With": "XMLHttpRequest",
            "User-Agent":       "Mozilla/5.0 (compatible; Mangayomi-Kmanga/1.0)",
            "Connection":       "close",
          },
          body: "action=manga_get_chapters&manga=$mangaId",
        );
        if (ajaxRes.body.contains("wp-manga-chapter")) {
          return _parseChaptersFromHtml(parseHtml(ajaxRes.body), mangaUrl);
        }
      } catch (_) {}
    }

    // Fall back to chapters embedded in the detail page
    return _parseChaptersFromHtml(parseHtml(rawHtml), mangaUrl);
  }

  List<MChapter> _parseChaptersFromHtml(MDocument doc, String mangaUrl) {
    final chapters = <MChapter>[];
    for (final el in doc.select("li.wp-manga-chapter")) {
      final anchor = el.selectFirst("a");
      if (anchor == null) continue;
      String link = anchor.attr("href").trim();
      final name  = anchor.text.trim();
      final date  = el.selectFirst("span.chapter-release-date i")?.text.trim() ?? "";
      if (link.isEmpty || name.isEmpty) continue;
      if (!link.startsWith("http")) link = "${_base()}$link";
      chapters.add(MChapter(name: name, url: link, dateUpload: date));
    }
    return chapters;
  }

  MPages _parseListing(String html) {
    final document = parseHtml(html);
    final items    = <MManga>[];

    for (final el in document.select(
      "div.page-item-detail.manga, "
      "div.c-tabs-item__content, "
      "div.col-6.col-sm-3.col-lg-2",
    )) {
      final anchor = el.selectFirst("a");
      if (anchor == null) continue;
      String link = anchor.attr("href").trim();
      if (link.isEmpty) continue;
      if (!link.startsWith("http")) link = "${_base()}$link";

      final name = el.selectFirst("h3.h5, span.manga-title, a[title]")
              ?.text.trim() ??
          anchor.attr("title")?.trim() ?? "";

      final imgEl = el.selectFirst("img");
      String cover = imgEl?.attr("data-src")?.trim() ?? "";
      if (cover.isEmpty) cover = imgEl?.attr("src")?.trim() ?? "";
      if (cover.startsWith("//")) cover = "https:$cover";

      if (name.isEmpty) continue;

      final manga = MManga();
      manga.name     = name;
      manga.imageUrl = cover;
      manga.link     = link;
      items.add(manga);
    }

    final hasNext = html.contains('class="next page-numbers"') ||
        html.contains('"next"') && html.contains("page-numbers");
    return MPages(items, hasNext);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _parseStatus(String raw) {
    if (raw.contains("ongoing"))   return 0;
    if (raw.contains("completed")) return 1;
    if (raw.contains("hiatus"))    return 2;
    if (raw.contains("cancelled") || raw.contains("canceled")) return 3;
    return 5;
  }

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
        "Accept":     "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8",
        "Referer": _base() + "/",
        "Connection": "close",
      };

  Map<String, String> _chapterHeaders(String chapterUrl) => {
        ..._headers(),
        "Referer": chapterUrl,
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
        SelectFilterOption("Default",    "",          null),
        SelectFilterOption("Trending",   "trending",  null),
        SelectFilterOption("Most Views", "views",     null),
        SelectFilterOption("Newest",     "new-manga", null),
        SelectFilterOption("Latest",     "latest",    null),
        SelectFilterOption("A-Z",        "alphabet",  null),
        SelectFilterOption("Rating",     "rating",    null),
      ], null),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key:          "domain_url",
        title:        "Base URL",
        summary:      "Default: https://kmanga.nettruyenplus.com\n"
                      "Alternate: https://kmanga.app",
        value:        source.baseUrl,
        dialogTitle:  "URL",
        dialogMessage: "",
      ),
    ];
  }
}

Kmanga main(MSource source) => Kmanga(source: source);
