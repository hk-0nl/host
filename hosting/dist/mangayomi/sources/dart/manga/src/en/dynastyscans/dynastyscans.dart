import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

class DynastyScans extends MProvider {
  DynastyScans({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Future<MPages> getPopular(int page) async {
    // There is no explicit popular feed in the guide, use /chapters.json
    return getLatestUpdates(page);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final data = await _fetchJsonList("/chapters.json?page=$page");

    final List<MManga> mangas = [];
    for (final raw in data) {
      final chapter = _asMap(raw);
      // Usually Dynasty chapter JSON includes a 'tags' array where one tag is the series,
      // or a 'series' object. Without exact JSON, we link directly to the chapter as the manga entry
      // or to the series if present.
      final permalink = chapter["permalink"]?.toString() ?? "";
      if (permalink.isEmpty) continue;

      final manga = MManga();
      manga.link = "${source.baseUrl}/chapters/$permalink";
      manga.name = chapter["title"]?.toString() ?? "Chapter $permalink";
      manga.imageUrl = ""; // Rarely provided in chapter list JSON

      mangas.add(manga);
    }

    // Default to hasNextPage = true if we got a full page
    return MPages(mangas, mangas.length >= 20);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getLatestUpdates(page);
    }

    final uri = Uri.parse(
      "${source.baseUrl}/search?q=${Uri.encodeQueryComponent(trimmed)}&page=$page",
    );
    final res = await client.get(uri, headers: {"Connection": "close"});
    return _parseSearchResults(res.body);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final uri = Uri.parse(url);
    final isChapterUrl = uri.path.contains("/chapters/");

    String jsonUrl = url;
    if (!url.endsWith(".json")) {
      jsonUrl = "$url.json";
    }

    final res = await client.get(Uri.parse(jsonUrl), headers: {"Connection": "close"});
    final data = _asMap(jsonDecode(res.body));

    final manga = MManga();
    manga.link = url;
    manga.name =
        data["title"]?.toString() ?? data["name"]?.toString() ?? "Unknown";
    manga.description = data["description"]?.toString() ?? "";

    // Attempt to extract tags
    final tags = data["tags"] as List? ?? [];
    final tagNames = tags
        .map((t) => _asMap(t)["name"]?.toString() ?? "")
        .where((t) => t.isNotEmpty)
        .toList();
    manga.genre = tagNames;

    final fallbackChapter = MChapter(
      name: manga.name,
      url: isChapterUrl
          ? url
          : _chapterUrl(data["permalink"]?.toString() ?? ""),
    );

    if (data.containsKey("chapters")) {
      final List<MChapter> parsedChapters = [];
      final chs = data["chapters"] as List? ?? [];
      for (final ch in chs) {
        final cmap = _asMap(ch);
        final permalink = cmap["permalink"]?.toString() ?? "";
        if (permalink.isEmpty) continue;
        parsedChapters.add(
          MChapter(
            name: cmap["title"]?.toString() ?? "Chapter",
            url: _chapterUrl(permalink),
          ),
        );
      }
      manga.chapters = parsedChapters.isEmpty
          ? [fallbackChapter]
          : parsedChapters;
    } else {
      // Fallback: check if chapters are grouped inside the tags array
      final List<MChapter> parsedChapters = [];
      for (final t in tags) {
        final tMap = _asMap(t);
        if (tMap.containsKey("chapters")) {
          final chs = tMap["chapters"] as List? ?? [];
          for (final ch in chs) {
            final cmap = _asMap(ch);
            final permalink = cmap["permalink"]?.toString() ?? "";
            if (permalink.isNotEmpty) {
              parsedChapters.add(
                MChapter(
                  name: cmap["title"]?.toString() ?? "Chapter",
                  url: _chapterUrl(permalink),
                ),
              );
            }
          }
        }
      }
      manga.chapters = parsedChapters.isEmpty ? [fallbackChapter] : parsedChapters;
    }

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    String jsonUrl = url;
    if (!url.endsWith(".json")) {
      jsonUrl = "$url.json";
    }

    final res = await client.get(Uri.parse(jsonUrl), headers: {"Connection": "close"});
    final data = _asMap(jsonDecode(res.body));

    final pages = data["pages"] as List? ?? [];
    final List<dynamic> pageUrls = [];

    for (final raw in pages) {
      final pageInfo = _asMap(raw);
      final imagePath = pageInfo["image"]?.toString() ?? "";
      if (imagePath.isNotEmpty) {
        if (imagePath.startsWith("http")) {
          pageUrls.add(imagePath);
        } else {
          pageUrls.add("${source.baseUrl}$imagePath");
        }
      }
    }

    return pageUrls;
  }

  MPages _parseSearchResults(String html) {
    final document = parseHtml(html);
    final items = <MManga>[];
    final seen = <String>[];

    void addFromAnchors(List<dynamic> anchors, bool seriesOnly) {
      for (final anchor in anchors) {
        final href = anchor.getHref;
        final text = anchor.text.trim();
        if (href.isEmpty || text.isEmpty) {
          continue;
        }
        final isSeries = href.contains("/series/");
        final isChapter = href.contains("/chapters/");
        if (seriesOnly && !isSeries) {
          continue;
        }
        if (!seriesOnly && !isSeries && !isChapter) {
          continue;
        }
        final absolute = href.startsWith("http")
            ? href
            : source.baseUrl + href;
        if (seen.contains(absolute)) {
          continue;
        }
        seen.add(absolute);
        items.add(
          MManga()
            ..name = text
            ..link = absolute
            ..imageUrl = "",
        );
      }
    }

    final contentSelectors = [
      ".search_results a",
      ".search-result a",
      ".results a",
      "main a",
      "article a",
    ];

    bool addedSeries = false;
    for (final selector in contentSelectors) {
      final anchors = document.select(selector);
      if (anchors.isEmpty) {
        continue;
      }
      addFromAnchors(anchors, true);
      if (items.isNotEmpty) {
        addedSeries = true;
        break;
      }
    }

    if (!addedSeries) {
      for (final selector in contentSelectors) {
        final anchors = document.select(selector);
        if (anchors.isEmpty) {
          continue;
        }
        addFromAnchors(anchors, false);
        if (items.isNotEmpty) {
          break;
        }
      }
    }

    final hasNextPage =
        document.select('a[rel="next"]').isNotEmpty ||
        document
            .select('a[href*="page="]')
            .any((anchor) => anchor.text.trim() == "→");

    return MPages(items, hasNextPage);
  }

  List<dynamic> _decodeList(String body) {
    try {
      final d = jsonDecode(body);
      if (d is List) return d;
    } catch (_) {}
    return [];
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  Future<List<dynamic>> _fetchJsonList(String path) async {
    final res = await client.get(Uri.parse("${source.baseUrl}$path"), headers: {"Connection": "close"});
    return _decodeList(res.body);
  }

  String _chapterUrl(String permalink) {
    if (permalink.isEmpty) {
      return source.baseUrl;
    }
    return "${source.baseUrl}/chapters/$permalink";
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];
}

DynastyScans main(MSource source) => DynastyScans(source: source);
