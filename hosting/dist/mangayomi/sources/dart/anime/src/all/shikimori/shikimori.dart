import 'dart:convert';

import 'package:mangayomi/bridge_lib.dart';

class Shikimori extends MProvider {
  Shikimori({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Future<MPages> getPopular(int page) async {
    final payload = await fetchAnimeList(
      page: page,
      query: "",
      order: getOrderPreference(fallback: "popularity"),
    );
    return toPages(payload);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final payload = await fetchAnimeList(
      page: page,
      query: "",
      order: "aired_on",
    );
    return toPages(payload);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    var order = getOrderPreference(fallback: "popularity");

    for (final filter in filterList.filters) {
      if (filter.type == "SortFilter") {
        order = filter.values[filter.state.index].value;
      }
    }

    final payload = await fetchAnimeList(
      page: page,
      query: query.trim(),
      order: order,
      kind: getKindPreference(),
      status: getStatusPreference(),
      rating: getRatingPreference(),
    );
    return toPages(payload);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final animeId = extractAnimeId(url);
    if (animeId.isEmpty) {
      fail("could not extract anime id from URL", url: url);
    }

    final detailPayload = await apiGet("animes/$animeId");
    final anime = asMap(
      decodeJson(detailPayload, "decode anime detail", "animes/$animeId"),
    );
    final screenshotsPayload = await apiGet("animes/$animeId/screenshots");
    final externalLinksPayload = await apiGet("animes/$animeId/external_links");
    final videosPayload = await apiGet("animes/$animeId/videos");

    final item = MManga();
    item.name = anime["name"]?.toString().trim().isNotEmpty == true
        ? anime["name"].toString()
        : anime["russian"]?.toString() ?? titleFromUrl(url);
    item.imageUrl = resolveImageUrl(asMap(anime["image"])["original"]);
    item.description = buildDescription(
      anime,
      asList(
        decodeJson(
          screenshotsPayload,
          "decode screenshots payload",
          "animes/$animeId/screenshots",
        ),
      ),
      asList(
        decodeJson(
          externalLinksPayload,
          "decode external links payload",
          "animes/$animeId/external_links",
        ),
      ),
      asList(
        decodeJson(
          videosPayload,
          "decode videos payload",
          "animes/$animeId/videos",
        ),
      ),
    );

    final chapters = <MChapter>[];
    for (final videoValue in asList(
      decodeJson(
        videosPayload,
        "decode videos payload",
        "animes/$animeId/videos",
      ),
    )) {
      final video = asMap(videoValue);
      final playerUrl =
          video["player_url"]?.toString() ?? video["url"]?.toString() ?? "";
      if (playerUrl.isEmpty) {
        continue;
      }

      final labelParts = <String>[
        "Video",
        if ((video["kind"]?.toString() ?? "").isNotEmpty)
          video["kind"].toString(),
        if ((video["hosting"]?.toString() ?? "").isNotEmpty)
          video["hosting"].toString(),
        if ((video["name"]?.toString() ?? "").isNotEmpty)
          video["name"].toString(),
      ];
      chapters.add(MChapter(name: labelParts.join(" | "), url: playerUrl));
    }

    for (final linkValue in asList(
      decodeJson(
        externalLinksPayload,
        "decode external links payload",
        "animes/$animeId/external_links",
      ),
    )) {
      final link = asMap(linkValue);
      final targetUrl = link["url"]?.toString() ?? "";
      if (targetUrl.isEmpty) {
        continue;
      }

      final labelParts = <String>[
        "External",
        if ((link["source"]?.toString() ?? "").isNotEmpty)
          link["source"].toString(),
        if ((link["kind"]?.toString() ?? "").isNotEmpty)
          link["kind"].toString(),
      ];
      chapters.add(MChapter(name: labelParts.join(" | "), url: targetUrl));
    }

    item.chapters = chapters.isEmpty
        ? [MChapter(name: "Open Entry", url: normalizeUrl(url))]
        : chapters;
    return item;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final normalized = normalizeUrl(url);
    return [
      MVideo()
        ..url = normalized
        ..originalUrl = normalized
        ..quality = classifyVideoQuality(normalized),
    ];
  }

  Future<List<dynamic>> fetchAnimeList({
    required int page,
    required String query,
    required String order,
    String? kind,
    String? status,
    String? rating,
  }) async {
    final response = await apiGet(
      "animes",
      queryParameters: {
        "page": page.toString(),
        "limit": "50",
        "order": order,
        if (query.isNotEmpty) "search": query,
        if (kind != null && kind.isNotEmpty) "kind": kind,
        if (status != null && status.isNotEmpty) "status": status,
        if (rating != null && rating.isNotEmpty) "rating": rating,
        if (getCensoredPreference() != "any")
          "censored": getCensoredPreference() == "true" ? "true" : "false",
      },
    );
    final decoded = decodeJson(response, "decode anime list", "animes");
    if (decoded is List) {
      return decoded;
    }
    fail("anime list payload was not a JSON array", url: "animes");
  }

  MPages toPages(List<dynamic> entries) {
    final items = <MManga>[];
    for (final entry in entries) {
      final anime = asMap(entry);
      final id = anime["id"]?.toString() ?? "";
      final name = anime["name"]?.toString().trim().isNotEmpty == true
          ? anime["name"].toString()
          : anime["russian"]?.toString() ?? "";
      if (id.isEmpty || name.isEmpty) {
        continue;
      }

      items.add(
        MManga()
          ..name = name
          ..link = buildAnimeUrl(anime["url"]?.toString() ?? "/animes/$id", id)
          ..imageUrl = resolveImageUrl(asMap(anime["image"])["original"]),
      );
    }
    return MPages(items, entries.length >= 50);
  }

  String buildDescription(
    Map<String, dynamic> anime,
    List<dynamic> screenshots,
    List<dynamic> externalLinks,
    List<dynamic> videos,
  ) {
    final lines = <String>[];
    final description = stripHtml(anime["description_html"]?.toString() ?? "");
    if (description.isNotEmpty) {
      lines.add(description);
    }

    addLine(lines, "Russian Title", anime["russian"]?.toString());
    addLine(lines, "Score", anime["score"]?.toString());
    addLine(lines, "Kind", anime["kind"]?.toString());
    addLine(lines, "Status", anime["status"]?.toString());
    addLine(lines, "Rating", anime["rating"]?.toString());
    addLine(lines, "Episodes", anime["episodes"]?.toString());
    addLine(lines, "Episodes Aired", anime["episodes_aired"]?.toString());
    addLine(lines, "Aired", anime["aired_on"]?.toString());
    addLine(lines, "Released", anime["released_on"]?.toString());
    addLine(lines, "Duration", anime["duration"]?.toString());
    addLine(lines, "MAL ID", anime["myanimelist_id"]?.toString());
    addLine(lines, "Franchise", anime["franchise"]?.toString());
    addLine(lines, "Genres", joinNames(asList(anime["genres"])));
    addLine(lines, "Studios", joinNames(asList(anime["studios"])));
    addLine(lines, "Licensors", joinStrings(asList(anime["licensors"])));
    addLine(lines, "External Links", externalLinks.length.toString());
    addLine(lines, "Videos", videos.length.toString());
    addLine(lines, "Screenshots", screenshots.length.toString());

    if (screenshots.isNotEmpty) {
      final sample = screenshots
          .take(5)
          .map((entry) => resolveImageUrl(asMap(entry)["preview"]))
          .where((value) => value.isNotEmpty)
          .join("\n");
      if (sample.isNotEmpty) {
        lines.add("");
        lines.add("Screenshot Previews:");
        lines.add(sample);
      }
    }

    return lines.join("\n").trim();
  }

  void addLine(List<String> lines, String label, String? value) {
    if (value == null || value.isEmpty || value == "null") {
      return;
    }
    lines.add("$label: $value");
  }

  String joinNames(List<dynamic> values) {
    return values
        .map((value) => asMap(value))
        .map(
          (value) => value["russian"]?.toString().trim().isNotEmpty == true
              ? value["russian"].toString()
              : value["name"]?.toString() ?? "",
        )
        .where((value) => value.isNotEmpty)
        .join(", ");
  }

  String joinStrings(List<dynamic> values) {
    return values
        .map((value) => value?.toString() ?? "")
        .where((value) => value.isNotEmpty)
        .join(", ");
  }

  Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  List<dynamic> asList(dynamic value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  String stripHtml(String html) {
    if (html.isEmpty) {
      return "";
    }
    return parseHtml("<body>$html</body>").selectFirst("body")?.text.trim() ?? "";
  }

  String resolveImageUrl(dynamic rawValue) {
    final value = rawValue?.toString() ?? "";
    if (value.isEmpty) {
      return "";
    }
    if (value.startsWith("http://") || value.startsWith("https://")) {
      return value;
    }
    return "${getBaseUrl()}$value";
  }

  String buildAnimeUrl(String url, String id) {
    return mergeQueryParameters(normalizeUrl(url), {"id": id});
  }

  String extractAnimeId(String url) {
    final uri = Uri.parse(normalizeUrl(url));
    final fromQuery = extractQueryParameter(url, "id");
    if (fromQuery.isNotEmpty) {
      return fromQuery;
    }

    for (final segment in uri.pathSegments) {
      final match = RegExp(r'^\d+$').firstMatch(segment);
      if (match != null) {
        return match.group(0) ?? "";
      }

      final prefixedMatch = RegExp(r'^(\d+)-').firstMatch(segment);
      if (prefixedMatch != null) {
        return prefixedMatch.group(1) ?? "";
      }
    }
    return "";
  }

  String titleFromUrl(String url) {
    final uri = Uri.parse(normalizeUrl(url));
    if (uri.pathSegments.isEmpty) {
      return url;
    }
    return uri.pathSegments.last.replaceAll("-", " ").trim();
  }

  String classifyVideoQuality(String url) {
    final lower = url.toLowerCase();
    if (lower.contains("youtube") || lower.contains("youtu.be")) {
      return "youtube";
    }
    if (lower.contains("vk.com")) {
      return "vk";
    }
    if (lower.contains("vimeo")) {
      return "vimeo";
    }
    return "link";
  }

  String normalizeUrl(String url) {
    if (url.startsWith("http://") || url.startsWith("https://")) {
      return url;
    }
    return "${getBaseUrl()}${getUrlWithoutDomain(url)}";
  }

  String getOrderPreference({required String fallback}) {
    final value = getPreferenceValue(
      source.id,
      "preferred_order",
    )?.toString().trim();
    if (value == null || value.isEmpty) {
      return fallback;
    }
    return value;
  }

  String getKindPreference() {
    final value =
        getPreferenceValue(source.id, "preferred_kind")?.toString().trim() ??
        "any";
    return value == "any" ? "" : value;
  }

  String getStatusPreference() {
    final value =
        getPreferenceValue(source.id, "preferred_status")?.toString().trim() ??
        "any";
    return value == "any" ? "" : value;
  }

  String getRatingPreference() {
    final value =
        getPreferenceValue(source.id, "preferred_rating")?.toString().trim() ??
        "any";
    return value == "any" ? "" : value;
  }

  String getCensoredPreference() {
    return getPreferenceValue(
          source.id,
          "preferred_censored",
        )?.toString().trim() ??
        "any";
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
  
  String getBaseUrl() {
    final value = getPreferenceValue(
      source.id,
      "domain_url",
    )?.toString().trim();
    if (value == null || value.isEmpty) {
      return source.baseUrl;
    }
    return value.endsWith("/") ? value.substring(0, value.length - 1) : value;
  }

  String getApiBaseUrl() {
    final value = getPreferenceValue(source.id, "api_url")?.toString().trim();
    if (value == null || value.isEmpty) {
      return "${source.baseUrl}/api";
    }
    return value.endsWith("/") ? value.substring(0, value.length - 1) : value;
  }

  Future<String> apiGet(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = Uri.parse(
      buildUrlWithQuery("${getApiBaseUrl()}/$path", queryParameters),
    );
    return fetchText(uri, "load API resource '$path'");
  }

  Future<String> fetchText(Uri uri, String context) async {
    try {
      final body = (await client.get(
        uri,
        headers: {
          "User-Agent": "Mangayomi-Shikimori-Source",
          "Connection": "close",
        },
      )).body;
      if (body.trim().isEmpty) {
        fail("$context returned an empty response", url: uri.toString());
      }
      return body;
    } catch (error) {
      fail("$context request failed", error: error, url: uri.toString());
    }
  }

  dynamic decodeJson(String body, String context, String path) {
    try {
      return jsonDecode(body);
    } catch (error) {
      fail("$context returned invalid JSON", error: error, url: path);
    }
  }

  String buildUrlWithQuery(
    String baseUrl,
    Map<String, String>? queryParameters,
  ) {
    if (queryParameters == null || queryParameters.isEmpty) {
      return baseUrl;
    }
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
    final parts = <String>["Shikimori: $context"];
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
    return [
      SortFilter("SortFilter", "Sort by", SortState(0, false), [
        SelectFilterOption("Popularity", "popularity"),
        SelectFilterOption("Ranked", "ranked"),
        SelectFilterOption("Aired On", "aired_on"),
        SelectFilterOption("Episodes", "episodes"),
        SelectFilterOption("Name", "name"),
        SelectFilterOption("Created At", "created_at"),
      ]),
    ];
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
      EditTextPreference(
        key: "api_url",
        title: "API URL",
        summary: "",
        value: source.baseUrl + "/api",
        dialogTitle: "API URL",
        dialogMessage: "",
      ),
      ListPreference(
        key: "preferred_order",
        title: "Default Order",
        summary: "",
        valueIndex: 0,
        entries: [
          "Popularity",
          "Ranked",
          "Aired On",
          "Episodes",
          "Name",
          "Created At",
        ],
        entryValues: [
          "popularity",
          "ranked",
          "aired_on",
          "episodes",
          "name",
          "created_at",
        ],
      ),
      ListPreference(
        key: "preferred_censored",
        title: "Censored Filter",
        summary: "",
        valueIndex: 0,
        entries: ["Any", "Censored Only", "Uncensored Only"],
        entryValues: ["any", "true", "false"],
      ),
      ListPreference(
        key: "preferred_kind",
        title: "Preferred Kind",
        summary: "",
        valueIndex: 0,
        entries: ["Any", "TV", "Movie", "OVA", "ONA", "Special", "Music"],
        entryValues: ["any", "tv", "movie", "ova", "ona", "special", "music"],
      ),
      ListPreference(
        key: "preferred_status",
        title: "Preferred Status",
        summary: "",
        valueIndex: 0,
        entries: ["Any", "Announced", "Ongoing", "Released"],
        entryValues: ["any", "anons", "ongoing", "released"],
      ),
      ListPreference(
        key: "preferred_rating",
        title: "Preferred Rating",
        summary: "",
        valueIndex: 0,
        entries: ["Any", "G", "PG", "PG-13", "R", "R+", "Rx"],
        entryValues: ["any", "g", "pg", "pg_13", "r", "r_plus", "rx"],
      ),
    ];
  }
}

Shikimori main(MSource source) {
  return Shikimori(source: source);
}
