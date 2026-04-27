import 'dart:convert';
import 'dart:math';

import 'package:mangayomi/bridge_lib.dart';

class HanimeTv extends MProvider {
  HanimeTv({required this.source});

  final MSource source;
  final Client client = Client();

  static const String searchApiUrl = "https://search.htv-services.com/";

  @override
  Map<String, String> get headers => buildApiHeaders();

  @override
  Future<MPages> getPopular(int page) async {
    return fetchSearchPage(
      page: page,
      query: "",
      orderBy: "views",
      ascending: false,
    );
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return fetchSearchPage(
      page: page,
      query: "",
      orderBy: "created_at_unix",
      ascending: false,
    );
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    String orderBy = "created_at_unix";
    var ascending = false;

    for (final filter in filterList.filters) {
      if (filter.type == "SortFilter") {
        orderBy = filter.values[filter.state.index].value;
        ascending = filter.state.ascending;
      }
    }

    return fetchSearchPage(
      page: page,
      query: query.trim(),
      orderBy: orderBy,
      ascending: ascending,
    );
  }

  @override
  Future<MManga> getDetail(String url) async {
    final slug = extractSlug(url);
    final payload = await fetchVideoPayload(slug);
    final video = asMap(payload["hentai_video"]);
    final franchiseVideos = asList(payload["hentai_franchise_hentai_videos"]);
    final tagList = asList(payload["hentai_tags"]);

    final anime = MManga();
    anime.name = video["name"]?.toString() ?? slug;
    anime.imageUrl = video["cover_url"]?.toString() ?? "";
    anime.description = buildDescription(video, tagList);
    anime.chapters = buildEpisodeChapters(franchiseVideos);

    if (anime.chapters == null || anime.chapters!.isEmpty) {
      anime.chapters = [MChapter(name: anime.name, url: buildVideoUrl(slug))];
    }
    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final slug = extractSlug(url);
    final payload = await fetchVideoPayload(slug);
    final manifest = asMap(payload["videos_manifest"]);
    final servers = asList(manifest["servers"]);
    final videos = <MVideo>[];

    for (final serverValue in servers) {
      final server = asMap(serverValue);
      final serverName = server["name"]?.toString() ?? "server";
      for (final streamValue in asList(server["streams"])) {
        final stream = asMap(streamValue);
        final streamUrl = stream["url"]?.toString() ?? "";
        if (streamUrl.isEmpty) {
          continue;
        }

        final kind = stream["kind"]?.toString() ?? "";
        final width = stream["width"]?.toString() ?? "";
        final height = stream["height"]?.toString() ?? "";
        final qualityLabel = [
          if (height.isNotEmpty) "${height}p",
          if (width.isNotEmpty) width,
          if (kind.isNotEmpty) kind,
          serverName,
        ].join(" ").trim();

        videos.add(
          MVideo()
            ..url = streamUrl
            ..originalUrl = streamUrl
            ..quality = qualityLabel.isEmpty ? "stream" : qualityLabel,
        );
      }
    }

    return videos.isEmpty
        ? [
            MVideo()
              ..url = buildVideoUrl(slug)
              ..originalUrl = buildVideoUrl(slug)
              ..quality = "page",
          ]
        : videos;
  }

  Future<MPages> fetchSearchPage({
    required int page,
    required String query,
    required String orderBy,
    required bool ascending,
  }) async {
    final body = {
      "blacklist": parseCsvPreference("default_blacklist"),
      "brands": parseCsvPreference("default_brands"),
      "order_by": orderBy,
      "ordering": ascending ? "asc" : "desc",
      "page": page - 1,
      "search_text": query,
      "tags": parseCsvPreference("default_tags"),
      "tags_mode": "AND",
    };

    final res = await client.post(
      Uri.parse(searchApiUrl),
      headers: {
        "Content-Type": "application/json",
        "Connection": "close",
      },
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(res.body);
    final payload = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    final hitsRaw = payload["hits"]?.toString() ?? "[]";
    final hitsDecoded = jsonDecode(hitsRaw);
    final hitList = hitsDecoded is List ? hitsDecoded : <dynamic>[];
    final items = <MManga>[];

    for (final entry in hitList) {
      if (entry is! Map) {
        continue;
      }
      final item = Map<String, dynamic>.from(entry);
      final slug = item["slug"]?.toString() ?? "";
      final name = item["name"]?.toString() ?? "";
      if (slug.isEmpty || name.isEmpty) {
        continue;
      }

      items.add(
        MManga()
          ..name = name
          ..link = buildVideoUrl(slug)
          ..imageUrl = item["cover_url"]?.toString() ?? "",
      );
    }

    final currentPage = (payload["page"] as num?)?.toInt() ?? (page - 1);
    final totalPages = (payload["nbPages"] as num?)?.toInt() ?? currentPage + 1;
    return MPages(items, currentPage + 1 < totalPages);
  }

  Future<Map<String, dynamic>> fetchVideoPayload(String slug) async {
    final uri = Uri.parse(
      buildUrlWithQuery("${getBaseUrl()}/api/v8/video", {"id": slug}),
    );
    final res = await client.get(uri, headers: buildApiHeaders());
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return {};
  }

  Map<String, String> buildApiHeaders() {
    return {
      "User-Agent": "Mozilla/5.0",
      "Referer": "https://hanime.tv/",
      "x-signature": buildSignature(),
      "x-signature-version": "web2",
      "Connection": "close",
    };
  }

  String buildSignature() {
    final random = Random();
    const alphabet = "0123456789abcdef";
    final buffer = StringBuffer();
    for (var index = 0; index < 32; index++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  List<MChapter> buildEpisodeChapters(List<dynamic> entries) {
    final chapters = <MChapter>[];
    final seen = <String>{};

    for (final entry in entries) {
      final item = asMap(entry);
      final slug = item["slug"]?.toString() ?? "";
      final name = item["name"]?.toString() ?? "";
      if (slug.isEmpty || name.isEmpty || seen.contains(slug)) {
        continue;
      }
      seen.add(slug);
      chapters.add(
        MChapter(
          name: name,
          url: buildVideoUrl(slug),
          dateUpload: item["released_at_unix"]?.toString() ?? "",
        ),
      );
    }

    return chapters;
  }

  String buildDescription(Map<String, dynamic> video, List<dynamic> tags) {
    final descriptionParts = <String>[];
    final htmlDescription = video["description"]?.toString() ?? "";
    final plainDescription = stripHtml(htmlDescription);
    if (plainDescription.isNotEmpty) {
      descriptionParts.add(plainDescription);
    }

    final metadata = <String>[];
    addMetadata(metadata, "Brand", video["brand"]?.toString());
    addMetadata(metadata, "Views", video["views"]?.toString());
    addMetadata(metadata, "Likes", video["likes"]?.toString());
    addMetadata(metadata, "Dislikes", video["dislikes"]?.toString());
    addMetadata(metadata, "Downloads", video["downloads"]?.toString());
    addMetadata(metadata, "Monthly Rank", video["monthly_rank"]?.toString());
    addMetadata(metadata, "Released", video["released_at"]?.toString());
    addMetadata(
      metadata,
      "Censored",
      video["is_censored"] == true ? "Yes" : "No",
    );

    final tagNames = tags
        .map((entry) => asMap(entry)["text"]?.toString() ?? "")
        .where((text) => text.isNotEmpty)
        .join(", ");
    if (tagNames.isNotEmpty) {
      metadata.add("Tags: $tagNames");
    }

    if (metadata.isNotEmpty) {
      if (descriptionParts.isNotEmpty) {
        descriptionParts.add("");
      }
      descriptionParts.addAll(metadata);
    }

    return descriptionParts.join("\n").trim();
  }

  void addMetadata(List<String> lines, String label, String? value) {
    if (value == null || value.isEmpty || value == "null") {
      return;
    }
    lines.add("$label: $value");
  }

  String stripHtml(String html) {
    if (html.isEmpty) {
      return "";
    }
    return parseHtml("<body>$html</body>").selectFirst("body")?.text.trim() ?? "";
  }

  List<String> parseCsvPreference(String key) {
    final raw = getPreferenceValue(source.id, key)?.toString() ?? "";
    return raw
        .split(",")
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
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

  String extractSlug(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) {
      return url;
    }
    return segments.last;
  }

  String buildVideoUrl(String slug) {
    return "${getBaseUrl()}/videos/hentai/$slug";
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

  @override
  List<dynamic> getFilterList() {
    return [
      SortFilter("SortFilter", "Sort by", SortState(0, false), [
        SelectFilterOption("Latest", "created_at_unix"),
        SelectFilterOption("Released", "released_at_unix"),
        SelectFilterOption("Views", "views"),
        SelectFilterOption("Likes", "likes"),
        SelectFilterOption("Title", "title_sortable"),
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
        key: "default_tags",
        title: "Default Tags",
        summary: "Comma-separated Hanime tags to include in all searches.",
        value: "",
        dialogTitle: "Tags",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "default_blacklist",
        title: "Default Blacklist",
        summary: "Comma-separated Hanime tags to exclude in all searches.",
        value: "",
        dialogTitle: "Blacklist",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "default_brands",
        title: "Default Brands",
        summary: "Comma-separated Hanime brands to include in all searches.",
        value: "",
        dialogTitle: "Brands",
        dialogMessage: "",
      ),
    ];
  }
}

HanimeTv main(MSource source) {
  return HanimeTv(source: source);
}
