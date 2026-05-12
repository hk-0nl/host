import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

// ─── MangaDex source for Mangayomi ───────────────────────────────────────────
// API   : https://api.mangadex.org  (v5, public browse — no auth required)
// Type  : JSON API
// Lang  : en (translatedLanguage[]=en)
// NSFW  : false (contentRating safe+suggestive only)
//
// dart_eval constraints observed throughout:
//   • NO string interpolation — all URLs built with string concatenation.
//   • NO Map.entries — iterate with .keys when map iteration needed.
//   • All JSON decode results cast explicitly before use.
// ─────────────────────────────────────────────────────────────────────────────

class MangaDex extends MProvider {
  MangaDex({required this.source});

  final MSource source;
  final Client client = Client();

  static const String _apiBase = "https://api.mangadex.org";
  static const String _coverBase = "https://uploads.mangadex.org/covers";

  // ── Public helpers ────────────────────────────────────────────────────────

  Map<String, String> _headers() => {
    "User-Agent": "Mangayomi-MangaDex/1.0",
    "Accept": "application/json",
    "Connection": "close",
  };

  String _base() => source.baseUrl;

  // ── Listing ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    final offset = (page - 1) * 20;
    final url = _apiBase +
        "/manga?limit=20&offset=" +
        offset.toString() +
        "&order[followedCount]=desc" +
        "&contentRating[]=safe&contentRating[]=suggestive" +
        "&includes[]=cover_art&includes[]=author";
    return await _fetchMangaList(url);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final offset = (page - 1) * 20;
    final url = _apiBase +
        "/manga?limit=20&offset=" +
        offset.toString() +
        "&order[latestUploadedChapter]=desc" +
        "&contentRating[]=safe&contentRating[]=suggestive" +
        "&includes[]=cover_art&includes[]=author";
    return await _fetchMangaList(url);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final offset = (page - 1) * 20;
    String url = _apiBase +
        "/manga?limit=20&offset=" +
        offset.toString() +
        "&contentRating[]=safe&contentRating[]=suggestive" +
        "&includes[]=cover_art&includes[]=author";

    if (query.isNotEmpty) {
      url += "&title=" + Uri.encodeQueryComponent(query);
    }

    for (final f in filterList.filters) {
      if (f.name == "Status" && (f.state as int) > 0) {
        const statuses = ["", "ongoing", "completed", "hiatus", "cancelled"];
        final idx = f.state as int;
        if (idx < statuses.length && statuses[idx].isNotEmpty) {
          url += "&status[]=" + statuses[idx];
        }
      }
      if (f.name == "Sort") {
        const sorts = [
          "followedCount",
          "relevance",
          "latestUploadedChapter",
          "title",
          "createdAt",
          "updatedAt",
          "year",
        ];
        final idx = f.state as int;
        if (idx < sorts.length) {
          url += "&order[" + sorts[idx] + "]=desc";
        }
      }
    }

    return await _fetchMangaList(url);
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    // url is the manga UUID stored as the link
    final mangaId = url.startsWith("http") ? _extractId(url) : url;
    final detailUrl = _apiBase +
        "/manga/" +
        mangaId +
        "?includes[]=cover_art&includes[]=author&includes[]=artist";
    final res = await _safeGet(Uri.parse(detailUrl), headers: _headers());
    if (res == null) return MManga();
    final Map<String, dynamic> body = jsonDecode(res.body) as Map<String, dynamic>;
    final Map<String, dynamic> data = body["data"] as Map<String, dynamic>;
    final Map<String, dynamic> attrs = data["attributes"] as Map<String, dynamic>;
    final List<dynamic> rels = data["relationships"] as List<dynamic>;

    final manga = MManga();
    manga.link = mangaId;

    // Title
    final titleMap = attrs["title"] as Map<String, dynamic>;
    manga.name = _firstNonEmpty(titleMap);

    // Description
    final descMap = attrs["description"] as Map<String, dynamic>? ?? {};
    manga.description = descMap.containsKey("en")
        ? descMap["en"].toString()
        : _firstNonEmpty(descMap);

    // Status
    manga.status = _parseStatus(attrs["status"]?.toString() ?? "");

    // Genres / tags
    final tags = attrs["tags"] as List<dynamic>? ?? [];
    final genre = <String>[];
    for (final tag in tags) {
      final tagMap = tag as Map<String, dynamic>;
      final tagAttrs = tagMap["attributes"] as Map<String, dynamic>;
      final nameMap = tagAttrs["name"] as Map<String, dynamic>;
      final name = nameMap.containsKey("en") ? nameMap["en"].toString() : "";
      if (name.isNotEmpty) genre.add(name);
    }
    manga.genre = genre;

    // Relationships
    String? coverFileName;
    String? authorName;
    String? artistName;
    for (final rel in rels) {
      final relMap = rel as Map<String, dynamic>;
      final type = relMap["type"]?.toString() ?? "";
      final relAttrs = relMap["attributes"] as Map<String, dynamic>?;
      if (type == "cover_art" && relAttrs != null) {
        coverFileName = relAttrs["fileName"]?.toString();
      }
      if (type == "author" && relAttrs != null && authorName == null) {
        authorName = relAttrs["name"]?.toString();
      }
      if (type == "artist" && relAttrs != null && artistName == null) {
        artistName = relAttrs["name"]?.toString();
      }
    }
    manga.author = authorName ?? "";
    manga.artist = artistName ?? authorName ?? "";
    if (coverFileName != null) {
      manga.imageUrl = _coverBase + "/" + mangaId + "/" + coverFileName;
    }

    // Chapters
    manga.chapters = await _fetchChapters(mangaId);
    return manga;
  }

  // ── getPageList ───────────────────────────────────────────────────────────

  @override
  Future<List<dynamic>> getPageList(String url) async {
    // url = chapter UUID
    final chapterId = url.startsWith("http") ? _extractId(url) : url;
    final atHomeUrl = _apiBase + "/at-home/server/" + chapterId;
    final res = await _safeGet(Uri.parse(atHomeUrl), headers: _headers());
    if (res == null) return MManga();
    final Map<String, dynamic> body = jsonDecode(res.body) as Map<String, dynamic>;
    final String baseUrl = body["baseUrl"]?.toString() ?? "";
    final Map<String, dynamic> chapter = body["chapter"] as Map<String, dynamic>? ?? {};
    final String hash = chapter["hash"]?.toString() ?? "";
    final List<dynamic> data = chapter["data"] as List<dynamic>? ?? [];

    final pages = <Map<String, dynamic>>[];
    for (final filename in data) {
      pages.add({
        "url": baseUrl + "/data/" + hash + "/" + filename.toString(),
        "headers": {
          "Referer": "https://mangadex.org/",
          "Connection": "close",
        },
      });
    }
    return pages;
  }

  // ── Private: chapter fetcher ──────────────────────────────────────────────

  Future<List<MChapter>> _fetchChapters(String mangaId) async {
    final chapters = <MChapter>[];
    int offset = 0;
    const limit = 500;
    int total = 1;

    while (offset < total) {
      final url = _apiBase +
          "/manga/" +
          mangaId +
          "/feed?limit=" +
          limit.toString() +
          "&offset=" +
          offset.toString() +
          "&order[chapter]=asc" +
          "&translatedLanguage[]=en" +
          "&includes[]=scanlation_group";
      final res = await _safeGet(Uri.parse(url), headers: _headers());
      if (res == null) return MManga();
      final Map<String, dynamic> body = jsonDecode(res.body) as Map<String, dynamic>;
      total = (body["total"] as num?)?.toInt() ?? 0;
      final List<dynamic> data = body["data"] as List<dynamic>? ?? [];

      for (final item in data) {
        final ch = item as Map<String, dynamic>;
        final chAttrs = ch["attributes"] as Map<String, dynamic>;
        final chId = ch["id"]?.toString() ?? "";
        if (chId.isEmpty) continue;

        // Skip external-only chapters (they have externalUrl set and pages=0)
        final ext = chAttrs["externalUrl"]?.toString() ?? "";
        if (ext.isNotEmpty) continue;

        final chNum = chAttrs["chapter"]?.toString() ?? "";
        final vol = chAttrs["volume"]?.toString() ?? "";
        final title = chAttrs["title"]?.toString() ?? "";

        String name = "";
        if (vol.isNotEmpty) name = "Vol." + vol + " ";
        name += "Ch." + (chNum.isNotEmpty ? chNum : "?");
        if (title.isNotEmpty) name += " - " + title;
        name = name.trim();

        final pubAt = chAttrs["publishAt"]?.toString() ?? "";
        final dateMs = pubAt.isNotEmpty
            ? DateTime.tryParse(pubAt)?.millisecondsSinceEpoch.toString() ??
                DateTime.now().millisecondsSinceEpoch.toString()
            : DateTime.now().millisecondsSinceEpoch.toString();

        // Scanlator group
        String scanlator = "";
        final rels = ch["relationships"] as List<dynamic>? ?? [];
        for (final r in rels) {
          final rMap = r as Map<String, dynamic>;
          if (rMap["type"] == "scanlation_group") {
            final rAttrs = rMap["attributes"] as Map<String, dynamic>?;
            if (rAttrs != null) {
              scanlator = rAttrs["name"]?.toString() ?? "";
              break;
            }
          }
        }

        chapters.add(MChapter(
          name: name,
          url: chId,
          dateUpload: dateMs,
          scanlator: scanlator.isNotEmpty ? scanlator : null,
        ));
      }

      offset += data.length;
      if (data.isEmpty) break;
    }

    // Reverse so newest chapter is first
    return chapters.reversed.toList();
  }

  // ── Private: manga list ───────────────────────────────────────────────────

  Future<MPages> _fetchMangaList(String url) async {
    final res = await _safeGet(Uri.parse(url), headers: _headers());
    if (res == null) return MPages([], false);
    final Map<String, dynamic> body = jsonDecode(res.body) as Map<String, dynamic>;
    final List<dynamic> data = body["data"] as List<dynamic>? ?? [];
    final int limit = (body["limit"] as num?)?.toInt() ?? 20;
    final int offset = (body["offset"] as num?)?.toInt() ?? 0;
    final int total = (body["total"] as num?)?.toInt() ?? 0;

    final items = <MManga>[];
    for (final item in data) {
      final m = item as Map<String, dynamic>;
      final mangaId = m["id"]?.toString() ?? "";
      final attrs = m["attributes"] as Map<String, dynamic>;
      final rels = m["relationships"] as List<dynamic>? ?? [];

      final titleMap = attrs["title"] as Map<String, dynamic>;
      final title = _firstNonEmpty(titleMap);
      if (title.isEmpty) continue;

      String? coverFileName;
      for (final r in rels) {
        final rMap = r as Map<String, dynamic>;
        if (rMap["type"] == "cover_art") {
          final rAttrs = rMap["attributes"] as Map<String, dynamic>?;
          if (rAttrs != null) {
            coverFileName = rAttrs["fileName"]?.toString();
            break;
          }
        }
      }

      final manga = MManga();
      manga.name = title;
      manga.link = mangaId;
      if (coverFileName != null) {
        manga.imageUrl = _coverBase + "/" + mangaId + "/" + coverFileName;
      }
      items.add(manga);
    }

    final hasNext = (offset + limit) < total;
    return MPages(items, hasNext);
  }

  // ── Private: helpers ──────────────────────────────────────────────────────

  /// Extract UUID from a mangadex.org URL, or return input if already UUID.
  String _extractId(String url) {
    final parts = url.split("/");
    // URL format: https://mangadex.org/title/{uuid}/slug
    for (int i = 0; i < parts.length; i++) {
      if (parts[i] == "title" || parts[i] == "chapter") {
        if (i + 1 < parts.length) return parts[i + 1];
      }
    }
    return url;
  }

  /// Return first non-empty value from a localised string map.
  /// Prefers "en", then any other key.
  String _firstNonEmpty(Map<String, dynamic> map) {
    if (map.containsKey("en")) {
      final v = map["en"]?.toString() ?? "";
      if (v.isNotEmpty) return v;
    }
    final keys = map.keys.toList();
    for (final k in keys) {
      final v = map[k]?.toString() ?? "";
      if (v.isNotEmpty) return v;
    }
    return "";
  }

  int _parseStatus(String raw) {
    if (raw == "ongoing") return 0;
    if (raw == "completed") return 1;
    if (raw == "hiatus") return 2;
    if (raw == "cancelled") return 3;
    return 5;
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  @override
  List<dynamic> getFilterList() {
    return [
      SelectFilter("SelectFilter", "Status", 0, [
        SelectFilterOption("Any", "", null),
        SelectFilterOption("Ongoing", "ongoing", null),
        SelectFilterOption("Completed", "completed", null),
        SelectFilterOption("Hiatus", "hiatus", null),
        SelectFilterOption("Cancelled", "cancelled", null),
      ], null),
      SelectFilter("SelectFilter", "Sort", 0, [
        SelectFilterOption("Most Followed", "followedCount", null),
        SelectFilterOption("Relevance", "relevance", null),
        SelectFilterOption("Latest Upload", "latestUploadedChapter", null),
        SelectFilterOption("Title", "title", null),
        SelectFilterOption("Newest", "createdAt", null),
        SelectFilterOption("Recently Updated", "updatedAt", null),
        SelectFilterOption("Year", "year", null),
      ], null),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [];
  }

  Future<Response?> _safeGet(Uri url, {Map<String, String>? headers}) async {
    try {
      final res = await client.get(url, headers: headers ?? {});
      if (res.statusCode >= 400) return null;
      return res;
    } catch (e) {
      return null;
    }
  }

}

MangaDex main(MSource source) => MangaDex(source: source);
