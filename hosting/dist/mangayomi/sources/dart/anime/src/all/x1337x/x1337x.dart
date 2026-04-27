import 'dart:convert';

import 'package:mangayomi/bridge_lib.dart';

class X1337x extends MProvider {
  X1337x({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Future getPopular(int page) async {
    final res = (await client.get(
      Uri.parse(buildCategorySearchUrl("anime", page)),
      headers: {"Connection": "close"},
    )).body;
    return parseResults(res);
  }

  @override
  Future getLatestUpdates(int page) async {
    final res = (await client.get(
      Uri.parse(buildCategorySearchUrl("anime", page)),
      headers: {"Connection": "close"},
    )).body;
    return parseResults(res);
  }

  @override
  Future search(String query, int page, FilterList filterList) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return getLatestUpdates(page);
    }

    final res = (await client.get(
      Uri.parse(buildCategorySearchUrl(trimmedQuery, page)),
      headers: {"Connection": "close"},
    )).body;
    return parseResults(res);
  }

  @override
  Future getDetail(String url) async {
    final detailUrl = stripFragment(normalizeUrl(url));
    final anime = MManga();
    final embedded = readEmbedded(url);
    final res = (await client.get(Uri.parse(detailUrl), headers: {"Connection": "close"})).body;
    final document = parseHtml(res);

    anime.name =
        document.selectFirst("h1")?.text.trim() ??
        embedded["name"]?.toString() ??
        "1337x";
    anime.description = buildDescription(embedded, detailUrl);

    final chapters = <MChapter>[];
    addChapter(
      chapters,
      "Magnet",
      document.selectFirst('a[href^="magnet:?"]')?.getHref,
    );

    final torrentAnchors = document.select("a[href]");
    for (final anchor in torrentAnchors) {
      final href = anchor.getHref;
      if (href.isEmpty) {
        continue;
      }
      final lowerHref = href.toLowerCase();
      final lowerText = anchor.text.toLowerCase();
      if (lowerHref.contains(".torrent") ||
          lowerHref.contains("itorrents") ||
          lowerText.contains("torrent download") ||
          lowerText.contains("mirror")) {
        addChapter(chapters, "Torrent", href);
        break;
      }
    }

    anime.chapters = chapters.isEmpty
        ? [MChapter(name: "Open Details", url: detailUrl)]
        : chapters;
    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    var rawUrl = url;
    // Unwrap the Mangayomi proxy URL if it exists
    if (rawUrl.contains("resolve_ct") && rawUrl.contains("url=")) {
      final proxyParam = extractQueryParameter(rawUrl, "url");
      if (proxyParam.isNotEmpty) {
        rawUrl = Uri.decodeComponent(proxyParam);
      }
    }

    return [
      MVideo()
        ..url = normalizeUrl(rawUrl)
        ..originalUrl = normalizeUrl(rawUrl)
        ..quality = rawUrl.startsWith("magnet:") ? "magnet" : "torrent",
    ];
  }

  MPages parseResults(String res) {
    final document = parseHtml(res);
    final rows = document.select("tbody tr");
    final results = <MManga>[];
    final seen = <String>{};

    for (final row in rows) {
      final anchor = row.selectFirst('a[href^="/torrent/"]');
      if (anchor == null) {
        continue;
      }

      final href = anchor.getHref;
      final name = anchor.text.trim();
      if (href.isEmpty || name.isEmpty || seen.contains(href)) {
        continue;
      }

      final metadata = {
        "name": name,
        "seeds": row.selectFirst("td.seeds")?.text.trim() ?? "",
        "leeches": row.selectFirst("td.leeches")?.text.trim() ?? "",
        "size": row.selectFirst("td.size")?.text.trim() ?? "",
      };

      seen.add(href);
      results.add(
        MManga()
          ..name = name
          ..link = buildEntryUrl(href, metadata),
      );
    }

    return MPages(results, false);
  }

  void addChapter(List<MChapter> chapters, String name, String? url) {
    if (url == null || url.isEmpty) {
      return;
    }

    chapters.add(MChapter(name: name, url: normalizeUrl(url)));
  }

  String buildDescription(Map<String, dynamic> embedded, String detailUrl) {
    final lines = <String>[];
    addLine(lines, "Detail URL", detailUrl);
    addLine(lines, "Size", embedded["size"]?.toString());
    addLine(lines, "Seeders", embedded["seeds"]?.toString());
    addLine(lines, "Leechers", embedded["leeches"]?.toString());
    if (lines.isEmpty) {
      lines.add(
        "General tracker source. Search and detail parsing are implemented, but availability still depends on 1337x accessibility from the runtime environment.",
      );
    }
    return lines.join("\n");
  }

  void addLine(List<String> lines, String label, String? value) {
    if (value == null || value.isEmpty) {
      return;
    }
    lines.add("$label: $value");
  }

  String buildCategorySearchUrl(String query, int page) {
    final safePage = page < 1 ? 1 : page;
    final encodedQuery = Uri.encodeComponent(query.trim());
    return "${getBaseUrl()}/category-search/$encodedQuery/Anime/$safePage/";
  }

  String buildEntryUrl(String href, Map<String, dynamic> metadata) {
    final encoded = Uri.encodeComponent(
      base64UrlEncode(utf8.encode(jsonEncode(metadata))),
    );
    return "${normalizeUrl(href)}#entry=$encoded";
  }

  Map<String, dynamic> readEmbedded(String url) {
    final fragment = Uri.parse(url).fragment;
    if (!fragment.startsWith("entry=")) {
      return {};
    }

    try {
      final payload = fragment.substring("entry=".length);
      final decoded = utf8.decode(
        base64Url.decode(Uri.decodeComponent(payload)),
      );
      final data = jsonDecode(decoded);
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
    } catch (_) {
      return {};
    }

    return {};
  }

  String stripFragment(String url) {
    final index = url.indexOf("#");
    return index == -1 ? url : url.substring(0, index);
  }

  String normalizeUrl(String url) {
    if (hasScheme(url)) {
      return url;
    }
    return "${getBaseUrl()}${getUrlWithoutDomain(url)}";
  }

  bool hasScheme(String url) {
    return RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(url);
  }

  String getBaseUrl() {
    final baseUrl = getPreferenceValue(source.id, "domain_url")?.trim();
    if (baseUrl == null || baseUrl.isEmpty) {
      return source.baseUrl;
    }
    return baseUrl.endsWith("/")
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  @override
  List<dynamic> getFilterList() {
    return [];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key: "domain_url",
        title: "Edit URL",
        summary: "",
        value: source.baseUrl,
        dialogTitle: "URL",
        dialogMessage: "",
      ),
    ];
  }
}

X1337x main(MSource source) {
  return X1337x(source: source);
}
