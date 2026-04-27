import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

class NHentai extends MProvider {
  NHentai({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Future<MPages> getPopular(int page) async {
    return _search('""', page, "popular");
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return _search('""', page, "date");
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    String sort = "date";
    for (final f in filterList.filters) {
      if (f.name == "Sort" && (f.state as int) > 0) {
        final idx = f.state as int;
        if (idx == 1) sort = "popular";
        if (idx == 2) sort = "date";
      }
    }
    // If query is empty, pass empty string
    final q = query.trim().isEmpty ? '""' : query.trim();
    return _search(q, page, sort);
  }

  Future<String> _fetchJson(Uri uri) async {
    final res = await client.get(uri, headers: {"Connection": "close"});
    final bypassEnabled = getPreferenceValue(source.id, "enable_cf_bypass");
    
    if (bypassEnabled == true && (res.statusCode == 403 || res.statusCode == 503)) {
      final html = await evaluateJavascriptViaWebview(uri.toString()) ?? "";
      if (html.trim().startsWith("<")) {
        final document = parseHtml(html);
        final pre = document.selectFirst("pre")?.text.trim() ?? "";
        if (pre.startsWith("{")) return pre;
        throw Exception("Cloudflare bypass failed. API returned HTML.");
      }
      return html;
    }
    
    final body = res.body.trim();
    if (body.startsWith("<")) {
      throw Exception("Cloudflare blocked the request. Enable Cloudflare Bypass in settings.");
    }
    return body;
  }

  Future<MPages> _search(String query, int page, String sort) async {
    final uri = Uri.parse(
      "${source.baseUrl}/api/galleries/search?query=${Uri.encodeQueryComponent(query)}&page=$page&sort=$sort",
    );
    final body = await _fetchJson(uri);
    final data = _asMap(jsonDecode(body));
    final results = data["result"] as List? ?? [];

    final List<MManga> mangas = [];
    for (final raw in results) {
      final post = _asMap(raw);
      final id = post["id"]?.toString() ?? "";
      if (id.isEmpty) continue;

      final manga = MManga();
      manga.link = "${source.baseUrl}/g/$id/";

      final titleObj = _asMap(post["title"]);
      manga.name =
          titleObj["pretty"]?.toString() ??
          titleObj["english"]?.toString() ??
          titleObj["japanese"]?.toString() ??
          "Unknown";

      final mediaId = post["media_id"]?.toString() ?? "";
      final images = _asMap(post["images"]);
      final cover = _asMap(images["cover"]);
      final ext = _mapType(cover["t"]?.toString() ?? "j");
      manga.imageUrl = "https://t.nhentai.net/galleries/$mediaId/cover.$ext";

      mangas.add(manga);
    }

    final totalPages = data["num_pages"] as int? ?? 1;
    final hasNextPage = page < totalPages;

    return MPages(mangas, hasNextPage);
  }

  @override
  Future<MManga> getDetail(String url) async {
    // Extract ID from url
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    final id = segments.last;

    final apiUri = Uri.parse("${source.baseUrl}/api/gallery/$id");
    final body = await _fetchJson(apiUri);
    final data = _asMap(jsonDecode(body));

    final manga = MManga();
    manga.link = url;

    final titleObj = _asMap(data["title"]);
    manga.name =
        titleObj["pretty"]?.toString() ??
        titleObj["english"]?.toString() ??
        titleObj["japanese"]?.toString() ??
        "Unknown";

    final mediaId = data["media_id"]?.toString() ?? "";
    final images = _asMap(data["images"]);
    final cover = _asMap(images["cover"]);
    final coverExt = _mapType(cover["t"]?.toString() ?? "j");
    manga.imageUrl = "https://t.nhentai.net/galleries/$mediaId/cover.$coverExt";

    final tags = data["tags"] as List? ?? [];
    final tagNames = tags
        .map((t) => _asMap(t)["name"]?.toString() ?? "")
        .where((t) => t.isNotEmpty)
        .toList();
    manga.genre = tagNames;

    final pages = images["pages"] as List? ?? [];
    manga.description =
        "Pages: ${pages.length}\nFavorites: ${data["num_favorites"] ?? 0}\n\nTags: ${tagNames.join(', ')}";
    manga.author = data["scanlator"]?.toString() ?? "";

    final chapter = MChapter();
    chapter.name = "Chapter 1";
    chapter.url = url; // Not used directly, but we store it
    manga.chapters = [chapter];

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    // Extract ID from url
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    final id = segments.last;

    final apiUri = Uri.parse("${source.baseUrl}/api/gallery/$id");
    final body = await _fetchJson(apiUri);
    final data = _asMap(jsonDecode(body));

    final mediaId = data["media_id"]?.toString() ?? "";
    final images = _asMap(data["images"]);
    final pages = images["pages"] as List? ?? [];

    final List<dynamic> pageUrls = [];
    for (int i = 0; i < pages.length; i++) {
      final pageInfo = _asMap(pages[i]);
      final ext = _mapType(pageInfo["t"]?.toString() ?? "j");
      pageUrls.add("https://i.nhentai.net/galleries/$mediaId/${i + 1}.$ext");
    }

    return pageUrls;
  }

  String _mapType(String t) {
    if (t == "j") return "jpg";
    if (t == "p") return "png";
    if (t == "g") return "gif";
    if (t == "w") return "webp";
    return "jpg";
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  @override
  List<dynamic> getFilterList() {
    return [
      SelectFilter("SelectFilter", "Sort", 0, [
        SelectFilterOption("Default", "", null),
        SelectFilterOption("Popular", "popular", null),
        SelectFilterOption("Date", "date", null),
      ], null),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      CheckBoxPreference(
        key: "enable_cf_bypass",
        title: "Enable Cloudflare Bypass",
        summary: "Enable if you encounter 403 or 503 errors. Slows down loading but bypasses Cloudflare checks.",
        value: false,
      )
    ];
  }
}

NHentai main(MSource source) => NHentai(source: source);
