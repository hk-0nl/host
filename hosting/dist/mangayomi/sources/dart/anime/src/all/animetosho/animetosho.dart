import 'dart:convert';

import 'package:mangayomi/bridge_lib.dart';

class AnimeTosho extends MProvider {
  AnimeTosho({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Future getPopular(int page) async {
    final entries = await fetchEntries({"q": "", "only_tor": "1"});
    return toPages(entries);
  }

  @override
  Future getLatestUpdates(int page) async {
    final entries = await fetchEntries({"q": "", "only_tor": "1"});
    return toPages(entries);
  }

  @override
  Future search(String query, int page, FilterList filterList) async {
    final entries = await fetchEntries({"q": query.trim(), "only_tor": "1"});
    return toPages(entries);
  }

  @override
  Future getDetail(String url) async {
    final detailUrl = normalizeUrl(url);
    final anime = MManga();
    final embeddedEntry = readEmbeddedEntry(detailUrl);

    if (embeddedEntry != null) {
      anime.name = embeddedEntry["title"]?.toString() ?? "";
      anime.description = buildDescription(embeddedEntry);
      anime.chapters = buildChapters(embeddedEntry, detailUrl);
      return anime;
    }

    final requestUrl = Uri.parse(stripFragment(detailUrl));
    final res = await fetchText(requestUrl, "load detail page");
    final document = parseHtml(res);

    anime.name = document.selectFirst("h1, h2")?.text.trim() ?? "";
    anime.description = document
        .select("body")
        .map((e) => e.text)
        .join("\n")
        .trim();

    final chapters = <MChapter>[];
    addChapter(
      chapters,
      "Torrent",
      document.selectFirst('a[href*="/torrent/"]')?.getHref,
    );
    addChapter(
      chapters,
      "Magnet",
      document.selectFirst('a[href^="magnet:"]')?.getHref,
    );
    addChapter(
      chapters,
      "NZB",
      document.selectFirst('a[href*="/nzb"]')?.getHref,
    );

    if (anime.name.isEmpty && chapters.isEmpty) {
      fail("could not parse detail page", url: requestUrl.toString());
    }

    anime.chapters = chapters.isEmpty
        ? [MChapter(name: "Open Entry", url: detailUrl)]
        : chapters;
    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    var rawUrl = url;
    if (rawUrl.contains("resolve_ct") && rawUrl.contains("url=")) {
      final proxyParam = extractQueryParameter(rawUrl, "url");
      if (proxyParam.isNotEmpty) {
        rawUrl = Uri.decodeComponent(proxyParam);
      }
    }

    final embeddedEntry = readEmbeddedEntry(rawUrl);
    if (embeddedEntry != null) {
      final videos = <MVideo>[];
      addVideo(videos, embeddedEntry["torrent_url"]?.toString(), "torrent");
      addVideo(videos, embeddedEntry["magnet_uri"]?.toString(), "magnet");
      addVideo(videos, embeddedEntry["nzb_url"]?.toString(), "nzb");
      if (videos.isNotEmpty) {
        return videos;
      }
    }

    final video = MVideo()
      ..url = rawUrl
      ..originalUrl = rawUrl
      ..quality = rawUrl.startsWith("magnet:") ? "magnet" : "link";
    return [video];
  }

  String extractQueryParameter(String url, String key) {
    final questionMarkIndex = url.indexOf("?");
    if (questionMarkIndex == -1) {
      return "";
    }
    final queryString = url.substring(questionMarkIndex + 1);
    for (final pair in queryString.split("&")) {
      final parts = pair.split("=");
      if (parts.isNotEmpty && Uri.decodeQueryComponent(parts[0]) == key) {
        return parts.length > 1 ? Uri.decodeQueryComponent(parts[1]) : "";
      }
    }
    return "";
  }

  Future<List<Map<String, dynamic>>> fetchEntries(
    Map<String, String> queryParameters,
  ) async {
    final apiUrl = Uri.parse(
      buildUrlWithQuery("https://feed.animetosho.org/json", queryParameters),
    );
    final body = await fetchText(apiUrl, "load feed");
    final decoded = decodeJson(body, "decode feed", apiUrl);
    if (decoded is! List) {
      fail("feed payload was not a JSON array", url: apiUrl.toString());
    }

    final entries = <Map<String, dynamic>>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }

      final entry = Map<String, dynamic>.from(item);
      if ((entry["status"]?.toString() ?? "") != "complete") {
        continue;
      }
      entries.add(entry);
    }

    entries.sort(
      (left, right) => (right["timestamp"] as num? ?? 0).compareTo(
        left["timestamp"] as num? ?? 0,
      ),
    );
    return entries;
  }

  MPages toPages(List<Map<String, dynamic>> entries) {
    final animeList = <MManga>[];
    final seen = <String>{};

    for (final entry in entries) {
      final link = entry["link"]?.toString() ?? "";
      final title = entry["title"]?.toString() ?? "";
      if (link.isEmpty || title.isEmpty || seen.contains(link)) {
        continue;
      }

      seen.add(link);
      animeList.add(
        MManga()
          ..name = title
          ..link = buildEntryUrl(link, entry),
      );
    }

    return MPages(animeList, false);
  }

  List<MChapter> buildChapters(Map<String, dynamic> entry, String detailUrl) {
    final chapters = <MChapter>[];
    addChapter(chapters, "Torrent", entry["torrent_url"]?.toString());
    addChapter(chapters, "Magnet", entry["magnet_uri"]?.toString());
    addChapter(chapters, "NZB", entry["nzb_url"]?.toString());
    addChapter(chapters, "Article", entry["article_url"]?.toString());
    addChapter(chapters, "Website", entry["website_url"]?.toString());

    return chapters.isEmpty
        ? [MChapter(name: "Open Entry", url: stripFragment(detailUrl))]
        : chapters;
  }

  void addChapter(List<MChapter> chapters, String name, String? url) {
    if (url == null || url.isEmpty) {
      return;
    }

    chapters.add(MChapter(name: name, url: normalizeUrl(url)));
  }

  void addVideo(List<MVideo> videos, String? url, String quality) {
    if (url == null || url.isEmpty) {
      return;
    }

    videos.add(
      MVideo()
        ..url = normalizeUrl(url)
        ..originalUrl = normalizeUrl(url)
        ..quality = quality,
    );
  }

  String buildDescription(Map<String, dynamic> entry) {
    final lines = <String>[];
    addLine(lines, "Article", entry["article_title"]?.toString());
    addLine(lines, "Article URL", entry["article_url"]?.toString());
    addLine(lines, "Website", entry["website_url"]?.toString());
    addLine(lines, "Seeders", entry["seeders"]?.toString());
    addLine(lines, "Leechers", entry["leechers"]?.toString());
    addLine(lines, "Downloads", entry["torrent_download_count"]?.toString());
    addLine(lines, "Size", formatSize(entry["total_size"]));
    addLine(lines, "Files", entry["num_files"]?.toString());
    addLine(lines, "AniDB AID", entry["anidb_aid"]?.toString());
    addLine(lines, "AniDB EID", entry["anidb_eid"]?.toString());
    addLine(lines, "Status", entry["status"]?.toString());
    addLine(lines, "Published", formatTimestamp(entry["timestamp"]));
    return lines.join("\n");
  }

  void addLine(List<String> lines, String label, String? value) {
    if (value == null || value.isEmpty) {
      return;
    }
    lines.add("$label: $value");
  }

  String formatTimestamp(dynamic rawTimestamp) {
    if (rawTimestamp is! num) {
      return "";
    }
    return DateTime.fromMillisecondsSinceEpoch(
      rawTimestamp.toInt() * 1000,
      isUtc: true,
    ).toIso8601String();
  }

  String formatSize(dynamic rawSize) {
    if (rawSize is! num) {
      return "";
    }

    const units = ["B", "KB", "MB", "GB", "TB"];
    var size = rawSize.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    final decimals = unitIndex == 0 ? 0 : 2;
    return "${size.toStringAsFixed(decimals)} ${units[unitIndex]}";
  }

  String buildEntryUrl(String link, Map<String, dynamic> entry) {
    final payload = {
      "title": entry["title"],
      "torrent_url": entry["torrent_url"],
      "magnet_uri": entry["magnet_uri"],
      "nzb_url": entry["nzb_url"],
      "article_url": entry["article_url"],
      "article_title": entry["article_title"],
      "website_url": entry["website_url"],
      "seeders": sanitizePeerCount(entry["seeders"]),
      "leechers": sanitizePeerCount(entry["leechers"]),
      "torrent_download_count": entry["torrent_download_count"],
      "total_size": entry["total_size"],
      "num_files": entry["num_files"],
      "anidb_aid": entry["anidb_aid"],
      "anidb_eid": entry["anidb_eid"],
      "status": entry["status"],
      "timestamp": entry["timestamp"],
    };

    final encoded = Uri.encodeComponent(
      base64UrlEncode(utf8.encode(jsonEncode(payload))),
    );
    return "${normalizeUrl(link)}#entry=$encoded";
  }

  Map<String, dynamic>? readEmbeddedEntry(String url) {
    final fragment = Uri.parse(url).fragment;
    if (!fragment.startsWith("entry=")) {
      return null;
    }

    final rawPayload = fragment.substring("entry=".length);
    if (rawPayload.isEmpty) {
      return null;
    }

    try {
      final decoded = utf8.decode(
        base64Url.decode(Uri.decodeComponent(rawPayload)),
      );
      final data = jsonDecode(decoded);
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  int sanitizePeerCount(dynamic rawValue) {
    if (rawValue is! num) {
      return 0;
    }
    final value = rawValue.toInt();
    return value > 30000 ? 0 : value;
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

  Future<String> fetchText(Uri uri, String context) async {
    try {
      final body = (await client.get(uri, headers: {"Connection": "close"})).body;
      if (body.trim().isEmpty) {
        fail("$context returned an empty response", url: uri.toString());
      }
      return body;
    } catch (error) {
      fail("$context request failed", error: error, url: uri.toString());
    }
  }

  dynamic decodeJson(String body, String context, Uri uri) {
    try {
      return jsonDecode(body);
    } catch (error) {
      fail("$context returned invalid JSON", error: error, url: uri.toString());
    }
  }

  String buildUrlWithQuery(
    String baseUrl,
    Map<String, String> queryParameters,
  ) {
    final filtered = queryParameters.entries
        .where((entry) => entry.value.isNotEmpty)
        .map(
          (entry) =>
              "${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}",
        )
        .join("&");
    if (filtered.isEmpty) {
      return baseUrl;
    }
    final separator = baseUrl.contains("?") ? "&" : "?";
    return "$baseUrl$separator$filtered";
  }

  Never fail(String context, {Object? error, String? url}) {
    final parts = <String>["AnimeTosho: $context"];
    if (url != null && url.isNotEmpty) {
      parts.add(url);
    }
    if (error != null) {
      parts.add(error.toString());
    }
    final message = parts.join(" | ");
    print(message);
    throw Exception(message);
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

AnimeTosho main(MSource source) {
  return AnimeTosho(source: source);
}
