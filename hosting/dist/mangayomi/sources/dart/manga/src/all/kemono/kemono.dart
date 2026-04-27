import 'dart:convert';

import 'package:mangayomi/bridge_lib.dart';

class Kemono extends MProvider {
  Kemono({required this.source});

  final MSource source;
  final Client client = Client();

  // The Kemono API enforces offset stepping of 50 — using any other page
  // size causes duplicate or skipped results as the server snaps offsets.
  static const int pageSize = 50;

  @override
  Map<String, String> get headers => buildHeaders();

  @override
  Future<MPages> getPopular(int page) async {
    return fetchPostsPage(page: page, query: "", filterList: FilterList([]));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return fetchPostsPage(page: page, query: "", filterList: FilterList([]));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    return fetchPostsPage(
      page: page,
      query: query.trim(),
      filterList: filterList,
    );
  }

  @override
  Future<MManga> getDetail(String url) async {
    final key = parsePostKey(url);
    if (key == null) {
      fail("invalid post key", url: url);
    }

    final payload = await fetchPostByIds(
      service: key.service,
      userId: key.userId,
      postId: key.postId,
    );
    final post = extractPostObject(payload);
    final title = post["title"]?.toString().trim().isNotEmpty == true
        ? post["title"].toString().trim()
        : "Kemono Post ${key.postId}";

    final galleryFiles = collectImageFiles(post);
    final chunkSize = getChunkSizePreference();
    final chapters = <MChapter>[];

    for (var offset = 0; offset < galleryFiles.length; offset += chunkSize) {
      final remaining = galleryFiles.length - offset;
      final limit = remaining < chunkSize ? remaining : chunkSize;
      final start = offset + 1;
      final end = offset + limit;

      chapters.add(
        MChapter(
          name: "Images $start-$end",
          url: buildChapterUrl(
            service: key.service,
            userId: key.userId,
            postId: key.postId,
            offset: offset,
            limit: limit,
          ),
        ),
      );
    }

    if (chapters.isEmpty) {
      chapters.add(
        MChapter(
          name: "Open Post",
          url: buildChapterUrl(
            service: key.service,
            userId: key.userId,
            postId: key.postId,
            offset: 0,
            limit: 0,
          ),
        ),
      );
    }

    final manga = MManga();
    manga.name = title;
    manga.link = buildPostUrl(
      service: key.service,
      userId: key.userId,
      postId: key.postId,
    );
    manga.imageUrl = galleryFiles.isNotEmpty
        ? buildAssetUrl(galleryFiles.first.path)
        : "";
    manga.description = buildDescription(post, galleryFiles.length);
    manga.chapters = materializeChapters(chapters);
    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final chapterKey = parseChapterKey(url);
    if (chapterKey == null) {
      fail("invalid chapter key", url: url);
    }

    final payload = await fetchPostByIds(
      service: chapterKey.service,
      userId: chapterKey.userId,
      postId: chapterKey.postId,
    );
    final post = extractPostObject(payload);
    final galleryFiles = collectImageFiles(post);

    if (chapterKey.limit <= 0) {
      return <dynamic>[];
    }

    final slice = galleryFiles
        .skip(chapterKey.offset)
        .take(chapterKey.limit)
        .map((file) => buildAssetUrl(file.path))
        .where((url) => url.isNotEmpty)
        .toList();
    return List<dynamic>.from(slice);
  }

  Future<MPages> fetchPostsPage({
    required int page,
    required String query,
    required FilterList filterList,
  }) async {
    final offset = ((page < 1 ? 1 : page) - 1) * pageSize;
    var serviceFilter = "";

    for (final filter in filterList.filters) {
      if (filter.name == "Service") {
        final index = filter.state as int;
        final values = ["", "fanbox", "patreon", "onlyfans", "boosty"];
        if (index >= 0 && index < values.length) {
          serviceFilter = values[index];
        }
      }
    }

    final payload = await fetchPosts(
      offset: offset,
      limit: pageSize,
      query: query,
    );

    final items = <MManga>[];
    for (final raw in payload) {
      final post = asMap(raw);
      if (post.isEmpty) {
        continue;
      }

      final service = post["service"]?.toString() ?? "";
      final userId = post["user"]?.toString() ?? "";
      final postId = post["id"]?.toString() ?? "";
      if (service.isEmpty || userId.isEmpty || postId.isEmpty) {
        continue;
      }

      if (serviceFilter.isNotEmpty && service != serviceFilter) {
        continue;
      }

      final title = post["title"]?.toString().trim() ?? "";
      if (title.isEmpty && query.isNotEmpty) {
        continue;
      }

      final galleryFiles = collectImageFiles(post);
      final coverPath = galleryFiles.isNotEmpty
          ? galleryFiles.first.path
          : filePathFromMap(asMap(post["file"]));

      final manga = MManga();
      manga.name = title.isEmpty ? "Kemono Post $postId" : title;
      manga.link = buildPostUrl(
        service: service,
        userId: userId,
        postId: postId,
      );
      manga.imageUrl = coverPath.isEmpty ? "" : buildAssetUrl(coverPath);
      items.add(manga);
    }

    return MPages(items, payload.length >= pageSize);
  }

  Future<List<dynamic>> fetchPosts({
    required int offset,
    required int limit,
    required String query,
  }) async {
    final uri = Uri.parse(
      buildUrlWithQuery("${getApiBaseUrl()}/posts", {
        "o": offset.toString(),
        "limit": limit.toString(),
        if (query.isNotEmpty) "q": query,
      }),
    );
    final body = await fetchText(uri, "load posts feed");
    final decoded = decodeJson(body, "decode posts feed", uri.toString());
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map) {
      dynamic posts;
      if (decoded.containsKey("posts")) {
        posts = decoded["posts"];
      } else if (decoded.containsKey("items")) {
        posts = decoded["items"];
      } else if (decoded.containsKey("results")) {
        posts = decoded["results"];
      } else if (decoded.containsKey("data")) {
        posts = decoded["data"];
      }
      if (posts is List) {
        return posts;
      }
    }
    fail("posts feed was not a JSON array (type: ${decoded.runtimeType})", url: uri.toString());
  }

  Future<Map<String, dynamic>> fetchPostByIds({
    required String service,
    required String userId,
    required String postId,
  }) async {
    final uri = Uri.parse(
      "${getApiBaseUrl()}/$service/user/$userId/post/$postId",
    );
    final body = await fetchText(uri, "load post detail");
    final decoded = decodeJson(body, "decode post detail", uri.toString());
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    fail("post detail was not a JSON object", url: uri.toString());
  }

  Map<String, dynamic> extractPostObject(Map<String, dynamic> payload) {
    final nested = asMap(payload["post"]);
    return nested.isNotEmpty ? nested : payload;
  }

  List<_KemonoFile> collectImageFiles(Map<String, dynamic> post) {
    final files = <_KemonoFile>[];
    final seen = <String>{};

    void addFile(Map<String, dynamic> file) {
      final path = filePathFromMap(file);
      if (path.isEmpty || seen.contains(path) || !isImagePath(path)) {
        return;
      }
      seen.add(path);
      files.add(_KemonoFile(name: file["name"]?.toString() ?? "", path: path));
    }

    final primary = asMap(post["file"]);
    if (primary.isNotEmpty) {
      addFile(primary);
    }

    for (final raw in asList(post["attachments"])) {
      addFile(asMap(raw));
    }

    return files;
  }

  String buildDescription(Map<String, dynamic> post, int imageCount) {
    final lines = <String>[];
    final content = stripHtml(post["content"]?.toString() ?? "");
    if (content.isNotEmpty) {
      lines.add(content);
      lines.add("");
    }
    addLine(lines, "Service", post["service"]?.toString());
    addLine(lines, "Creator ID", post["user"]?.toString());
    addLine(lines, "Post ID", post["id"]?.toString());
    addLine(lines, "Published", post["published"]?.toString());
    addLine(lines, "Edited", post["edited"]?.toString());
    addLine(lines, "Imported", post["added"]?.toString());
    addLine(lines, "Images", imageCount.toString());
    return lines.join("\n").trim();
  }

  String stripHtml(String html) {
    if (html.isEmpty) {
      return "";
    }
    return parseHtml("<body>$html</body>").selectFirst("body")?.text.trim() ??
        "";
  }

  void addLine(List<String> lines, String label, String? value) {
    if (value == null || value.isEmpty || value == "null") {
      return;
    }
    lines.add("$label: $value");
  }

  String buildPostUrl({
    required String service,
    required String userId,
    required String postId,
  }) {
    return "kemono://post/$service/$userId/$postId";
  }

  String buildChapterUrl({
    required String service,
    required String userId,
    required String postId,
    required int offset,
    required int limit,
  }) {
    return buildUrlWithQuery("kemono://gallery/$service/$userId/$postId", {
      "offset": offset.toString(),
      "limit": limit.toString(),
    });
  }

  _PostKey? parsePostKey(String url) {
    final clean = url.split("?").first;
    final uri = Uri.parse(clean);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.scheme != "kemono" || uri.host != "post" || segments.length < 3) {
      return null;
    }
    return _PostKey(
      service: segments[0],
      userId: segments[1],
      postId: segments[2],
    );
  }

  _ChapterKey? parseChapterKey(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.scheme != "kemono" || uri.host != "gallery" || segments.length < 3) {
      return null;
    }
    return _ChapterKey(
      service: segments[0],
      userId: segments[1],
      postId: segments[2],
      offset: int.tryParse(_extractQueryParam(url, "offset")) ?? 0,
      limit: int.tryParse(_extractQueryParam(url, "limit")) ?? 0,
    );
  }

  /// Safe manual query-param parser — avoids Uri.queryParameters which may
  /// not behave correctly inside dart_eval for non-http URI schemes.
  String _extractQueryParam(String url, String key) {
    final qIdx = url.indexOf("?");
    if (qIdx == -1) return "";
    final query = url.substring(qIdx + 1);
    for (final pair in query.split("&")) {
      final eqIdx = pair.indexOf("=");
      if (eqIdx == -1) continue;
      if (Uri.decodeQueryComponent(pair.substring(0, eqIdx)) == key) {
        return Uri.decodeQueryComponent(pair.substring(eqIdx + 1));
      }
    }
    return "";
  }

  String buildAssetUrl(String path) {
    if (path.isEmpty) {
      return "";
    }
    if (path.startsWith("http://") || path.startsWith("https://")) {
      return path;
    }
    return "${getAssetBaseUrl()}${path.startsWith("/") ? path : "/$path"}";
  }

  String filePathFromMap(Map<String, dynamic> file) {
    return file["path"]?.toString().trim() ?? "";
  }

  bool isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith(".jpg") ||
        lower.endsWith(".jpeg") ||
        lower.endsWith(".png") ||
        lower.endsWith(".webp") ||
        lower.endsWith(".gif");
  }

  String getApiBaseUrl() {
    final value =
        getPreferenceValue(source.id, "api_url")?.toString().trim() ?? "";
    if (value.isNotEmpty) {
      return value.endsWith("/") ? value.substring(0, value.length - 1) : value;
    }
    // kemono.cr is the current primary domain (kemono.su is legacy/mirror)
    return "https://kemono.cr/api/v1";
  }

  String getAssetBaseUrl() {
    final value =
        getPreferenceValue(source.id, "asset_base_url")?.toString().trim() ??
        "";
    if (value.isNotEmpty) {
      return value.endsWith("/") ? value.substring(0, value.length - 1) : value;
    }
    final apiBase = getApiBaseUrl();
    if (apiBase.endsWith("/api/v1")) {
      return apiBase.substring(0, apiBase.length - "/api/v1".length);
    }
    return source.baseUrl;
  }

  int getChunkSizePreference() {
    final raw =
        getPreferenceValue(
          source.id,
          "chapter_chunk_size",
        )?.toString().trim() ??
        "";
    final parsed = int.tryParse(raw) ?? 25;
    if (parsed < 10) {
      return 10;
    }
    if (parsed > 25) {
      return 25;
    }
    return parsed;
  }

  Map<String, String> buildHeaders() {
    final userAgent =
        getPreferenceValue(source.id, "user_agent")?.toString().trim() ?? "";
    return {
      "User-Agent": userAgent.isEmpty ? defaultUserAgent : userAgent,
      "Accept": "application/json,text/plain,*/*",
      "Referer": getAssetBaseUrl() + "/",
      "Connection": "close",
    };
  }

  Future<String> fetchText(Uri uri, String context) async {
    try {
      // Fast path: try standard HTTP client. Mangayomi's client shares cookies
      // with the WebView, so if CF was already solved, this works instantly.
      final res = await client.get(uri, headers: buildHeaders());
      if (res.statusCode == 200) {
        final text = res.body.trim();
        // If it starts with [ or {, it's valid JSON from the API.
        if (text.startsWith('{') || text.startsWith('[')) {
          return text;
        }
      }
    } catch (_) {
      // Ignore network errors and fall through to WebView fallback.
    }

    // Slow path: WebView execution to bypass Cloudflare.
    try {
      final script = "document.body.innerText || document.documentElement.innerText;";
      var body = await evaluateJavascriptViaWebview(uri.toString(), script);
      
      if (body == null || body.trim().isEmpty) {
        fail("$context returned an empty response", url: uri.toString());
      }
      
      // The bridge stringifies the return value, so it may wrap the output in quotes.
      // Additionally, the webview may encode the JSON string as an HTML string inside <pre>.
      if (body.startsWith('"') && body.endsWith('"')) {
        body = jsonDecode(body).toString();
      }
      
      return body;
    } catch (error) {
      fail("$context request failed", url: uri.toString(), error: error);
    }
  }

  dynamic decodeJson(String body, String context, String url) {
    try {
      return jsonDecode(body);
    } catch (error) {
      fail("$context returned invalid JSON", url: url, error: error);
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

  List<MChapter> materializeChapters(List<MChapter> raw) {
    return raw
        .map(
          (chapter) => MChapter(
            name: chapter.name,
            url: chapter.url,
            dateUpload: chapter.dateUpload,
            scanlator: chapter.scanlator,
            isFiller: chapter.isFiller,
            thumbnailUrl: chapter.thumbnailUrl,
            description: chapter.description,
            downloadSize: chapter.downloadSize,
            duration: chapter.duration,
          ),
        )
        .toList();
  }

  Never fail(String context, {String? url, Object? error}) {
    final parts = <String>["Kemono: $context"];
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
      SelectFilter("SelectFilter", "Service", 0, [
        SelectFilterOption("All", "", null),
        SelectFilterOption("Fanbox", "fanbox", null),
        SelectFilterOption("Patreon", "patreon", null),
        SelectFilterOption("OnlyFans", "onlyfans", null),
        SelectFilterOption("Boosty", "boosty", null),
      ], null),  // 5th arg: typeName = null (required by bridge)
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key: "api_url",
        title: "API Base URL",
        summary: "Default: https://kemono.su/api/v1 (kemono.cr is the main site, but it has a Cloudflare block wall for the API)",
        value: "https://kemono.su/api/v1",
        dialogTitle: "API Base URL",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "asset_base_url",
        title: "Asset Base URL",
        summary: "Default: https://kemono.su",
        value: "https://kemono.su",
        dialogTitle: "Asset Base URL",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "chapter_chunk_size",
        title: "Chapter Chunk Size",
        summary: "Images per virtual chapter. Clamped to 10-25.",
        value: "25",
        dialogTitle: "Chapter Chunk Size",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "user_agent",
        title: "User Agent",
        summary: "Optional browser-like User-Agent override.",
        value: defaultUserAgent,
        dialogTitle: "User Agent",
        dialogMessage: "",
      ),
    ];
  }

  static const String defaultUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36";
}

class _KemonoFile {
  _KemonoFile({required this.name, required this.path});

  final String name;
  final String path;
}

class _PostKey {
  _PostKey({required this.service, required this.userId, required this.postId});

  final String service;
  final String userId;
  final String postId;
}

class _ChapterKey {
  _ChapterKey({
    required this.service,
    required this.userId,
    required this.postId,
    required this.offset,
    required this.limit,
  });

  final String service;
  final String userId;
  final String postId;
  final int offset;
  final int limit;
}

Kemono main(MSource source) => Kemono(source: source);
