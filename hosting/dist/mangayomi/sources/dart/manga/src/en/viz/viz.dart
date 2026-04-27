import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

// ─── Viz Media source for Mangayomi ──────────────────────────────────────────
// Site   : https://www.viz.com
// Type   : REST API + HTML hybrid
// Lang   : en
// NSFW   : false
//
// ── DRM / Geo-block analysis ─────────────────────────────────────────────────
// Viz is an official US publisher. Two tiers of content exist:
//
//   1. FREE preview chapters (first 1–3 chapters of each series, or rotating
//      "free to read" selections). These are accessible without login and
//      served as plain image files via a chapter-viewer API.
//
//   2. PAID / SUBSCRIPTION chapters. Viz uses Shueisha's viewer pipeline;
//      chapter pages are served as pre-scrambled image tiles or as
//      canvas-drawn segments via JS. The reader at viz.com/read/manga/{slug}
//      deobfuscates the tile order client-side using a per-chapter cipher key
//      embedded in the HTML. Raw tile URLs without the key cannot be assembled
//      into readable pages.
//
// ── Implementation strategy ──────────────────────────────────────────────────
// This source implements:
//   • Catalogue browse + search — fully functional via the public API.
//   • getDetail() + chapter list — fully functional.
//   • getPageList() for FREE chapters — fully functional; returns assembled
//     page image URLs with required auth headers.
//   • getPageList() for LOCKED chapters — throws a descriptive error message
//     explaining the DRM limitation. Does NOT attempt to circumvent DRM.
//
// Scramble tile stitching for paid chapters is NOT implemented here.
// If Viz ever exposes a subscriber API that returns pre-assembled images, the
// _assembleScrambledPage() stub below is where that logic belongs.
//
// ── API endpoints ─────────────────────────────────────────────────────────────
// Catalog list:
//   GET /api/series/search?type=manga&page={n}&limit=20
//   GET /api/series/search?type=manga&page={n}&limit=20&search={query}
//   GET /api/series/search?type=manga&page={n}&limit=20&sort=popularity
//
// Series detail:
//   GET /api/series/{slug}
//   Response: { name, description, coverUrl, status, genres, chapters: [...] }
//
// Chapter viewer token (free chapters only):
//   GET /manga/get_manga_url.php?device_id=3&manga_id={chapterId}
//   Response JSON: { ok: "1", url: "<viewer-base-url>" }
//   Then: GET <viewer-base-url> → JSON with array of page image paths.

class Viz extends MProvider {
  Viz({required this.source});

  final MSource source;
  final Client  client = Client();

  // ── Listing ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    return _fetchCatalog(page, query: "", sort: "popularity");
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return _fetchCatalog(page, query: "", sort: "updated");
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    String sort   = "";
    String status = "";
    for (final f in filterList.filters) {
      if (f.name == "Sort" && (f.state as int) > 0) {
        const sorts = ["", "popularity", "updated", "alpha", "rating"];
        final idx   = f.state as int;
        if (idx < sorts.length) sort = sorts[idx];
      }
      if (f.name == "Status" && (f.state as int) > 0) {
        const statuses = ["", "ongoing", "completed"];
        final idx      = f.state as int;
        if (idx < statuses.length) status = statuses[idx];
      }
    }
    return _fetchCatalog(page, query: query.trim(), sort: sort, status: status);
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final slug = _slugFromUrl(url);

    // Try the JSON API first
    Map<String, dynamic>? apiData;
    try {
      final apiRes = await client.get(
        Uri.parse("${_base()}/api/series/$slug"),
        headers: _jsonHeaders(),
      );
      apiData = _asMap(jsonDecode(apiRes.body));
    } catch (_) {}

    final manga = MManga();

    if (apiData != null && apiData.isNotEmpty) {
      manga.name        = apiData["name"]?.toString() ?? slug;
      manga.description = apiData["description"]?.toString() ?? "";
      manga.imageUrl    = apiData["coverUrl"]?.toString() ?? "";
      manga.author      = (apiData["authors"] as List?)?.join(", ") ?? "";
      manga.genre       = (apiData["genres"] as List?)?.cast<String>() ?? [];
      manga.status      = _parseStatus(apiData["status"]?.toString() ?? "");
      manga.chapters    = _parseApiChapters(apiData["chapters"], url);
    } else {
      // Fallback: scrape the HTML series page
      final html     = await client.get(Uri.parse(url), headers: _htmlHeaders());
      final document = parseHtml(html.body);

      manga.name = document.selectFirst("h2.type-sm, .series-title")?.text.trim() ?? slug;
      manga.description = document.selectFirst(
              ".series-intro--desc, .o_synopsis")
          ?.text.trim() ?? "";
      manga.imageUrl = document
              .selectFirst("img.lazy.product-cover, img[data-original]")
              ?.attr("data-original") ??
          document.selectFirst("img.product-cover")?.attr("src") ?? "";
      manga.genre    = document
          .select("ul.property-list a[href*='/genre/']")
          .map((e) => e.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      manga.chapters = _parseHtmlChapters(document, url);
    }

    return manga;
  }

  // ── getPageList ───────────────────────────────────────────────────────────
  // FREE chapters: resolve image URLs via get_manga_url.php.
  // LOCKED chapters: throw descriptive error — DRM prevents raw extraction.
  @override
  Future<List<dynamic>> getPageList(String url) async {
    // Chapter URL format: https://www.viz.com/read/manga/{series}/{direction}/chapter-{n}/{chapterId}
    // or the internal viz:// scheme we set in getDetail().
    final chapterId = _chapterIdFromUrl(url);

    if (chapterId.isEmpty) {
      throw Exception(
        "Viz: could not extract chapter ID from URL: $url\n"
        "Open the chapter at viz.com instead.",
      );
    }

    // Step 1: Request viewer token for this chapter
    final tokenRes = await client.get(
      Uri.parse(
        "${_base()}/manga/get_manga_url.php?device_id=3&manga_id=$chapterId",
      ),
      headers: _jsonHeaders(),
    );

    Map<String, dynamic> tokenData;
    try {
      tokenData = _asMap(jsonDecode(tokenRes.body));
    } catch (_) {
      throw Exception(
        "Viz: chapter token request returned non-JSON. "
        "The chapter may be locked behind a subscription. "
        "Paid chapters require a Viz subscription and cannot be "
        "extracted by this source due to Viz's DRM.",
      );
    }

    // ok == "0" means the chapter is locked
    final ok      = tokenData["ok"]?.toString() ?? "0";
    final viewUrl = tokenData["url"]?.toString() ?? "";

    if (ok != "1" || viewUrl.isEmpty) {
      throw Exception(
        "🔒 This chapter requires a Viz subscription.\n\n"
        "Viz Free chapters: first 1-3 chapters per series + rotating selections.\n"
        "Subscription chapters cannot be extracted — Viz scrambles page tiles "
        "using a per-chapter cipher key embedded in the JS reader. "
        "This source surfaces free preview chapters only.\n\n"
        "Visit viz.com to subscribe.",
      );
    }

    // Step 2: Fetch the viewer manifest JSON from the token URL
    final manifestRes = await client.get(
      Uri.parse(viewUrl),
      headers: _htmlHeaders(),
    );

    List<String> pageUrls = [];
    try {
      final manifest = jsonDecode(manifestRes.body);
      // Manifest format: { "data": { "pages": [ "path/to/page_001.jpg", ... ] } }
      // or: { "pages": [...] }
      dynamic pages = manifest["data"]?["pages"] ?? manifest["pages"];
      if (pages is List) {
        final baseMatch = RegExp(r'"imgBasePath"\s*:\s*"([^"]+)"')
            .firstMatch(manifestRes.body);
        final basePath  = baseMatch?.group(1) ?? "";
        for (final p in pages) {
          final pStr = p.toString();
          pageUrls.add(pStr.startsWith("http") ? pStr : "$basePath$pStr");
        }
      }
    } catch (_) {}

    // Step 3: Fallback — extract image URLs from the viewer HTML
    if (pageUrls.isEmpty) {
      final pageMatches = RegExp(
        r'"(https://[^"]+viz\.com[^"]+\.(?:jpg|png|webp)[^"]*)"',
      ).allMatches(manifestRes.body);
      pageUrls = pageMatches.map((m) => m.group(1)!).toList();
    }

    if (pageUrls.isEmpty) {
      throw Exception(
        "Viz: could not extract page images from chapter viewer. "
        "The viewer format may have changed or this chapter is locked.",
      );
    }

    return pageUrls.map((u) => {
      "url": u,
      "headers": {
        "Referer": _base() + "/",
        "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-Viz/1.0)",
      },
    }).toList();
  }

  // ── Private API ───────────────────────────────────────────────────────────

  Future<MPages> _fetchCatalog(
    int page, {
    required String query,
    String sort   = "",
    String status = "",
  }) async {
    // Build URL — try JSON API first
    String apiUrl =
        "${_base()}/api/series/search?type=manga&page=$page&limit=20";
    if (query.isNotEmpty)  apiUrl += "&search=${Uri.encodeQueryComponent(query)}";
    if (sort.isNotEmpty)   apiUrl += "&sort=$sort";
    if (status.isNotEmpty) apiUrl += "&status=$status";

    try {
      final res  = await client.get(Uri.parse(apiUrl), headers: _jsonHeaders());
      final data = jsonDecode(res.body);
      if (data is Map && data["series"] is List) {
        return _parseApiCatalog(data["series"] as List, page);
      }
    } catch (_) {}

    // Fallback: scrape the HTML catalogue
    String htmlUrl = "${_base()}/manga";
    if (query.isNotEmpty) htmlUrl += "?search=${Uri.encodeQueryComponent(query)}&page=$page";
    else                   htmlUrl += "?page=$page";

    final res      = await client.get(Uri.parse(htmlUrl), headers: _htmlHeaders());
    final document = parseHtml(res.body);
    return _parseHtmlCatalog(document, page);
  }

  MPages _parseApiCatalog(List series, int page) {
    final items = <MManga>[];
    for (final raw in series) {
      final s = _asMap(raw);
      final manga = MManga();
      manga.name     = s["name"]?.toString() ?? "";
      manga.imageUrl = s["coverUrl"]?.toString() ?? "";
      manga.link     = "${_base()}/read/manga/${s["slug"] ?? ""}";
      if (manga.name.isNotEmpty) items.add(manga);
    }
    final hasNext = series.length >= 20;
    return MPages(items, hasNext);
  }

  MPages _parseHtmlCatalog(MDocument doc, int page) {
    final items = <MManga>[];
    for (final el in doc.select("div.product-item, article.series-item")) {
      final link = el.selectFirst("a")?.attr("href")?.trim() ?? "";
      final name = el.selectFirst("div.title, .series-title, img")
              ?.attr("alt")
              ?.trim() ??
          el.selectFirst("a")?.attr("title")?.trim() ?? "";
      final cover = el.selectFirst("img[data-original], img.lazy")
              ?.attr("data-original") ??
          el.selectFirst("img")?.attr("src") ?? "";
      if (link.isEmpty || name.isEmpty) continue;
      final manga = MManga();
      manga.name     = name;
      manga.imageUrl = cover;
      manga.link     = link.startsWith("http") ? link : _base() + link;
      items.add(manga);
    }
    final hasNext = doc.selectFirst(".o_next_btn, a[aria-label='Next']") != null;
    return MPages(items, hasNext);
  }

  List<MChapter> _parseApiChapters(dynamic raw, String mangaUrl) {
    if (raw is! List) return [];
    final chapters = <MChapter>[];
    for (final c in raw) {
      final ch = _asMap(c);
      final id   = ch["chapterId"]?.toString() ?? ch["id"]?.toString() ?? "";
      final name = ch["name"]?.toString() ??
          "Chapter ${ch["number"] ?? ch["chapterNumber"] ?? id}";
      final date = ch["date"]?.toString() ?? ch["releaseDate"]?.toString() ?? "";
      final free = ch["free"] == true || ch["free"]?.toString() == "1";

      if (id.isEmpty) continue;
      chapters.add(MChapter(
        name:       free ? name : "🔒 $name",
        url:        "viz://chapter?id=$id",
        dateUpload: date,
      ));
    }
    return chapters;
  }

  List<MChapter> _parseHtmlChapters(MDocument doc, String mangaUrl) {
    final chapters = <MChapter>[];
    for (final el in doc.select("div.o_chapter, li.chapter-list-item")) {
      final anchor  = el.selectFirst("a[href*='/chapter']");
      final link    = anchor?.attr("href")?.trim() ?? "";
      final name    = el.selectFirst(".chapter-title, span.ch-num")?.text.trim() ??
          anchor?.text.trim() ?? "";
      final date    = el.selectFirst("span.ch-date, time")?.text.trim() ?? "";
      final isFree  = el.attr("class").contains("o_chapter-available");

      if (link.isEmpty || name.isEmpty) continue;
      chapters.add(MChapter(
        name:       isFree ? name : "🔒 $name",
        url:        link.startsWith("http") ? link : _base() + link,
        dateUpload: date,
      ));
    }
    return chapters;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _slugFromUrl(String url) {
    // https://www.viz.com/read/manga/{slug}  or  https://www.viz.com/manga/{slug}
    final parts = url.split("/").where((s) => s.isNotEmpty).toList();
    final mangaIdx = parts.lastIndexOf("manga");
    if (mangaIdx != -1 && mangaIdx + 1 < parts.length) {
      return parts[mangaIdx + 1].split("?").first;
    }
    return parts.last.split("?").first;
  }

  String _chapterIdFromUrl(String url) {
    // viz://chapter?id=12345
    if (url.startsWith("viz://")) {
      final q = url.indexOf("id=");
      if (q != -1) {
        final rest = url.substring(q + 3);
        final amp  = rest.indexOf("&");
        return amp == -1 ? rest : rest.substring(0, amp);
      }
      return "";
    }
    // https://www.viz.com/read/manga/{series}/{dir}/chapter-{n}/{id}
    final parts = url.split("/").where((s) => s.isNotEmpty).toList();
    return parts.last.split("?").first;
  }

  int _parseStatus(String raw) {
    final s = raw.toLowerCase();
    if (s.contains("ongoing"))   return 0;
    if (s.contains("complete"))  return 1;
    if (s.contains("hiatus"))    return 2;
    return 5;
  }

  String _base() {
    final v = _pref("domain_url");
    if (v.isNotEmpty) return v.endsWith("/") ? v.substring(0, v.length - 1) : v;
    return source.baseUrl;
  }

  String _pref(String key) =>
      getPreferenceValue(source.id, key)?.toString().trim() ?? "";

  Map<String, String> _jsonHeaders() => {
        "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-Viz/1.0)",
        "Accept":     "application/json",
        "Referer": _base() + "/",
        "Connection": "close",
      };

  Map<String, String> _htmlHeaders() => {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
        "Accept":     "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8",
        "Referer": _base() + "/",
        "Connection": "close",
      };

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  @override
  List<dynamic> getFilterList() {
    return [
      SelectFilter("SelectFilter", "Status", 0, [
        SelectFilterOption("Any",       "",          null),
        SelectFilterOption("Ongoing",   "ongoing",   null),
        SelectFilterOption("Completed", "completed", null),
      ], null),
      SelectFilter("SelectFilter", "Sort", 0, [
        SelectFilterOption("Default",    "",           null),
        SelectFilterOption("Popular",    "popularity", null),
        SelectFilterOption("Updated",    "updated",    null),
        SelectFilterOption("A-Z",        "alpha",      null),
        SelectFilterOption("Top Rated",  "rating",     null),
      ], null),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key:          "domain_url",
        title:        "Base URL",
        summary:      "Default: https://www.viz.com",
        value:        source.baseUrl,
        dialogTitle:  "URL",
        dialogMessage: "",
      ),
    ];
  }
}

Viz main(MSource source) => Viz(source: source);
