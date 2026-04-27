import 'dart:convert';

import 'package:mangayomi/bridge_lib.dart';

class SubsPlease extends MProvider {
  SubsPlease({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Future getPopular(int page) async {
    final res = await fetchText(
      Uri.parse("${getBaseUrl()}/shows/"),
      "load show listing",
    );
    return parseShowList(res, "");
  }

  @override
  Future getLatestUpdates(int page) async {
    final res = await fetchText(
      Uri.parse("${getBaseUrl()}/shows/"),
      "load latest shows",
    );
    return parseShowList(res, "");
  }

  @override
  Future search(String query, int page, FilterList filterList) async {
    final res = await fetchText(
      Uri.parse("${getBaseUrl()}/shows/"),
      "search shows",
    );
    return parseShowList(res, query);
  }

  @override
  Future getDetail(String url) async {
    final showUrl = normalizeUrl(url);
    final res = await fetchText(Uri.parse(showUrl), "load show details");
    final document = parseHtml(res);
    final anime = MManga();
    anime.name =
        document.selectFirst(".entry-title")?.text.trim() ??
        titleFromUrl(showUrl);
    anime.description = document
        .select(".series-syn p")
        .map((element) => element.text.trim())
        .where((text) => text.isNotEmpty)
        .join("\n\n");

    final sidMatch = RegExp(
      r'id="show-release-table"[^>]*sid="(\d+)"',
    ).firstMatch(res);
    final sid = sidMatch?.group(1) ?? "";

    if (sid.isEmpty) {
      fail("missing sid in show page response", url: showUrl);
    }

    final showData = await fetchShowData(sid);
    final chapters = <MChapter>[];
    chapters.addAll(
      buildReleaseChapters(showUrl, sid, showData["batch"], "batch"),
    );
    chapters.addAll(
      buildReleaseChapters(showUrl, sid, showData["episode"], "episode"),
    );

    anime.chapters = chapters.isEmpty
        ? [MChapter(name: "Open Show Page", url: showUrl)]
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

    final uri = Uri.parse(rawUrl);
    final sid = extractQueryParameter(rawUrl, "sid");
    final entry = extractQueryParameter(rawUrl, "entry");
    final kind = extractQueryParameter(rawUrl, "kind");

    if (sid == null || entry == null || kind == null) {
      fail("invalid release URL; missing sid/entry/kind", url: url);
    }

    final showData = await fetchShowData(sid);
    final releases = showData[kind];
    if (releases is! Map) {
      fail("release section '$kind' was not found", url: url);
    }

    final release = Map<String, dynamic>.from(releases)[entry];
    if (release is! Map) {
      fail("release '$entry' was not found in section '$kind'", url: url);
    }

    final videos = buildVideos(release["downloads"]);
    if (videos.isEmpty) {
      fail("release has no torrent or magnet downloads", url: url);
    }
    return videos;
  }

  MPages parseShowList(String res, String query) {
    final document = parseHtml(res);
    final anchors = document.select('.all-shows-link a[href*="/shows/"]');
    final seen = <String>{};
    final animeList = <MManga>[];

    for (final anchor in anchors) {
      final href = anchor.getHref;
      final name = anchor.text.trim();

      if (href.isEmpty ||
          name.isEmpty ||
          href == "/shows/" ||
          seen.contains(href)) {
        continue;
      }
      if (query.isNotEmpty &&
          !name.toLowerCase().contains(query.toLowerCase().trim())) {
        continue;
      }

      seen.add(href);
      animeList.add(
        MManga()
          ..name = name
          ..link = normalizeUrl(href),
      );
    }

    return MPages(animeList, false);
  }

  Future<Map<String, dynamic>> fetchShowData(String sid) async {
    final apiUrl = Uri.parse(
      buildUrlWithQuery("${getBaseUrl()}/api/", {
        "f": "show",
        "sid": sid,
        "tz": "UTC",
      }),
    );
    final body = await fetchText(apiUrl, "load show API payload");
    final decoded = decodeJson(body, "decode show API payload", apiUrl);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    fail("show API payload was not a JSON object", url: apiUrl.toString());
  }

  List<MChapter> buildReleaseChapters(
    String showUrl,
    String sid,
    dynamic rawSection,
    String kind,
  ) {
    if (rawSection is! Map) {
      return [];
    }

    final releases = Map<String, dynamic>.from(rawSection);
    final chapters = <MChapter>[];

    for (final item in releases.entries) {
      final releaseKey = item.key;
      final releaseData = item.value;
      String suffix = "";
      if (releaseData is Map) {
        final time = releaseData["time"]?.toString() ?? "";
        if (time.isNotEmpty) {
          suffix = " [$time]";
        }
      }

      chapters.add(
        MChapter(
          name: "$releaseKey$suffix",
          url: buildReleaseUrl(showUrl, sid, releaseKey, kind),
        ),
      );
    }

    return chapters;
  }

  List<MVideo> buildVideos(dynamic rawDownloads) {
    if (rawDownloads is! List) {
      return [];
    }

    final videos = <MVideo>[];
    for (final item in rawDownloads) {
      if (item is! Map) {
        continue;
      }

      final download = Map<String, dynamic>.from(item);
      final resolution = download["res"]?.toString() ?? "";
      final torrentUrl = download["torrent"]?.toString() ?? "";
      final magnetUrl = download["magnet"]?.toString() ?? "";

      if (torrentUrl.isNotEmpty) {
        videos.add(buildVideo(torrentUrl, "${resolution}p torrent"));
      }
      if (magnetUrl.isNotEmpty) {
        videos.add(buildVideo(magnetUrl, "${resolution}p magnet"));
      }
    }

    return videos;
  }

  MVideo buildVideo(String url, String quality) {
    return MVideo()
      ..url = url
      ..originalUrl = url
      ..quality = quality;
  }

  String buildReleaseUrl(
    String showUrl,
    String sid,
    String entry,
    String kind,
  ) {
    return mergeQueryParameters(showUrl, {
      "sid": sid,
      "entry": entry,
      "kind": kind,
    });
  }

  String titleFromUrl(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) {
      return url;
    }
    return segments.last.replaceAll("-", " ").trim();
  }

  String normalizeUrl(String url) {
    if (url.startsWith("http://") || url.startsWith("https://")) {
      return url;
    }
    return "${getBaseUrl()}${getUrlWithoutDomain(url)}";
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

  String mergeQueryParameters(String url, Map<String, String> updates) {
    if (updates.isEmpty) {
      return url;
    }
    
    String baseUrl = url;
    String queryString = "";
    final questionMarkIndex = url.indexOf("?");
    if (questionMarkIndex != -1) {
      baseUrl = url.substring(0, questionMarkIndex);
      queryString = url.substring(questionMarkIndex + 1);
    }
    
    final params = <String, String>{};
    if (queryString.isNotEmpty) {
      for (final pair in queryString.split("&")) {
        final parts = pair.split("=");
        if (parts.isNotEmpty) {
          final key = Uri.decodeQueryComponent(parts[0]);
          final value = parts.length > 1 ? Uri.decodeQueryComponent(parts[1]) : "";
          params[key] = value;
        }
      }
    }
    
    for (final entry in updates.entries) {
      params[entry.key] = entry.value;
    }
    
    return buildUrlWithQuery(baseUrl, params);
  }

  String stripFragmentAndQuery(String url) {
    final fragmentIndex = url.indexOf("#");
    final withoutFragment = fragmentIndex == -1
        ? url
        : url.substring(0, fragmentIndex);
    final queryIndex = withoutFragment.indexOf("?");
    return queryIndex == -1
        ? withoutFragment
        : withoutFragment.substring(0, queryIndex);
  }

  Never fail(String context, {Object? error, String? url}) {
    final parts = <String>["SubsPlease: $context"];
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

SubsPlease main(MSource source) {
  return SubsPlease(source: source);
}
