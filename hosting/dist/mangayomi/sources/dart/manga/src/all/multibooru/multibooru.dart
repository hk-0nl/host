import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

class MultiBooru extends MProvider {
  MultiBooru({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Future<MPages> getPopular(int page) async {
    return _fetchPage(page, sortIndex: 1); // 1 = order:score
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return _fetchPage(page, sortIndex: 0); // 0 = default sort (newest)
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    return _fetchPage(page, query: query);
  }

  @override
  Future<MManga> getDetail(String url) async {
    // If it's a full API fetch (e.g. from a deep link), we would fetch post.json.
    // For now, assume url passes enough data or it's a direct API query to /posts/<id>.json
    // But since `mangaFromPartial` sets the `url` to the JSON payload representing the post ID or API endpoint,
    // we do an API fetch.
    final res = await client.get(Uri.parse(url), headers: _getHeaders());
    final payload = jsonDecode(res.body);

    // Some APIs return array for single searches (like Gelbooru id search)
    Map<String, dynamic> data;
    if (payload is List) {
      if (payload.isEmpty) throw Exception("Post not found");
      data = Map<String, dynamic>.from(payload.first);
    } else if (payload is Map) {
      if (payload.containsKey("post")) {
        data = Map<String, dynamic>.from(payload["post"]);
      } else {
        data = Map<String, dynamic>.from(payload);
      }
    } else {
      throw Exception("Invalid payload");
    }

    final schemaDan = _useDanbooruSchema();
    final post = _normalizePost(data, isDanbooru: schemaDan);
    final manga = MManga();
    manga.name = _inferDisplayTitle(data, post, schemaDan);
    manga.imageUrl = _listCoverFromData(data, post);
    manga.author = post.artist;
    manga.artist = post.artist;

    final rawTags = post.tags;
    final tagList = rawTags.split(RegExp(r"\s+")).where((s) => s.isNotEmpty).toList();
    manga.genre = tagList;
    
    final ext = (post.fileExt).toLowerCase();
    final isVideo = ext == "webm" || ext == "mp4" || ext == "gif";

    if (isVideo) {
      manga.description = "🎬 VIDEO/ANIMATED POST (." + ext + ")\nDirect URL: " + post.fileUrl + "\n\nTags: " + post.tags + "\n\nArtist: " + post.artist;
      manga.chapters = _materializeChapters([
        MChapter(
          name: "Preview (animated — see description for direct link)",
          url: post.previewUrl.isNotEmpty ? post.previewUrl : post.fileUrl,
        ),
      ]);
    } else {
      manga.description = "Tags: " + post.tags + "\n\nArtist: " + post.artist;
      manga.chapters = _materializeChapters([
        MChapter(
          name: "Image" + (ext.isNotEmpty ? " ." + ext : ""),
          url: post.fileUrl,
        ),
      ]);
    }
    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    // Booru CDNs check Referer on image requests.
    // Use Map form so Mangayomi injects the header when fetching the image.
    return [
      {
        "url": url,
        "headers": {
          "Referer":    _getBaseUrl() + "/",
          "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-MultiBooru/1.0)",
        },
      }
    ];
  }
  
  // --- Core API Helpers ---
  
  Future<MPages> _fetchPage(int page, {String query = "", int sortIndex = 0}) async {
    final isDan = _useDanbooruSchema();
    final String tags = _buildTagQuery(
      isDanbooru: isDan,
      query: query,
      sortIndex: sortIndex,
    );

    // ── Tag blacklist ─────────────────────────────────────────────────────────
    final _blacklistRaw = _getPreference("tag_blacklist");
    String _allTags = tags;
    if (_blacklistRaw.isNotEmpty) {
      final _exclusions = _blacklistRaw
          .split(",")
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .map((t) => "-" + t)
          .join(" ");
      if (_exclusions.isNotEmpty) {
        _allTags = _allTags.isNotEmpty ? _allTags + " " + _exclusions : _exclusions;
      }
    }

    final uri = _buildListUri(
      isDanbooru: isDan,
      tags: _allTags,
      page: page,
    );

    final res = await client.get(uri, headers: _getHeaders());
    final payload = jsonDecode(res.body);
    
    List<dynamic> posts = [];
    if (payload is List) {
      posts = payload;
    } else if (payload is Map && payload.containsKey("post")) {
      // gelbooru sometimes wraps in {"post": [...]} or {"@attributes": ..., "post": [...]}
      final postData = payload["post"];
      if (postData is List) {
        posts = postData;
      } else if (postData != null) {
        posts = [postData];
      }
    }

    final items = <MManga>[];
    for (final postRaw in posts) {
      final data = Map<String, dynamic>.from(postRaw);
      final post = _normalizePost(data, isDanbooru: isDan);
      
      if (post.id.isEmpty) continue;
      
      // Skip videos if Aidoku-style enforcement is desired (Mangayomi supports videos, but this is a manga source)
      final e = (post.fileExt).toLowerCase();
      if (e == "webm" || e == "mp4" || e == "gif") {
        continue;
      }

      final manga = MManga();
      manga.name = _inferDisplayTitle(data, post, isDan);
      manga.imageUrl = _listCoverFromData(data, post);
      // Pass the API endpoint for this specific post to getDetail
      manga.link = _buildSinglePostUri(isDanbooru: isDan, id: post.id).toString();
      
      items.add(manga);
    }

    // Usually 20 posts per page. If we got less, it's the last page.
    final bool hasNextPage = items.length >= 20;
    return MPages(items, hasNextPage);
  }

  // --- Logic ported from Aidoku Multibooru template ---

  String _buildTagQuery({
    required bool isDanbooru,
    String query = '',
    String includeTags = '',
    String excludeTags = '',
    String artist = '',
    String character = '',
    String copyright = '',
    String rating = '',
    int sortIndex = 0,
  }) {
    final terms = <String>[];
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) terms.add(trimmed);

    // Normally we'd extract these from FilterList. 
    // Here we just pass the bare bones.
    
    final sortDan = ['', 'order:score', 'order:favcount', 'order:comment'];
    final sortGel = [
      '',
      'sort:score:desc',
      'sort:fav:desc',
      'sort:comment_count:desc',
    ];
    final sort = isDanbooru
        ? (sortIndex >= 0 && sortIndex < sortDan.length ? sortDan[sortIndex] : '')
        : (sortIndex >= 0 && sortIndex < sortGel.length ? sortGel[sortIndex] : '');
    if (sort.isNotEmpty) terms.add(sort);

    return terms.join(' ');
  }

  Uri _buildListUri({
    required bool isDanbooru,
    required String tags,
    required int page,
  }) {
    final baseUrl = _getBaseUrl();
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    if (isDanbooru) {
      String params = "limit=20&page=" + page.toString();
      if (tags.isNotEmpty) params += "&tags=" + Uri.encodeQueryComponent(tags);
      final login = _getPreference("login");
      final apiKey = _getPreference("api_key");
      if (login.isNotEmpty && apiKey.isNotEmpty) {
        params += "&login=" + Uri.encodeQueryComponent(login) + "&api_key=" + Uri.encodeQueryComponent(apiKey);
      }
      return Uri.parse(base + "/posts.json?" + params);
    } else {
      String params = "page=dapi&s=post&q=index&json=1&limit=20";
      params += "&pid=" + ((page - 1).clamp(0, 9999999)).toString();
      if (tags.isNotEmpty) params += "&tags=" + Uri.encodeQueryComponent(tags);
      
      final userId = _getPreference("user_id");
      final apiKey = _getPreference("api_key");
      if (userId.isNotEmpty && apiKey.isNotEmpty) {
        params += "&user_id=" + Uri.encodeQueryComponent(userId) + "&api_key=" + Uri.encodeQueryComponent(apiKey);
      }
      return Uri.parse(base + "/index.php?" + params);
    }
  }
  
  Uri _buildSinglePostUri({
    required bool isDanbooru,
    required String id,
  }) {
    final baseUrl = _getBaseUrl();
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    if (isDanbooru) {
      return Uri.parse(base + "/posts/" + id + ".json");
    } else {
      String params = "page=dapi&s=post&q=index&json=1&id=" + Uri.encodeQueryComponent(id);
      return Uri.parse(base + "/index.php?" + params);
    }
  }
  
  _BooruPost _normalizePost(Map<String, dynamic> data, {required bool isDanbooru}) {
    final post = _BooruPost();
    post.id = data["id"]?.toString() ?? "";
    post.tags = isDanbooru ? (data["tag_string"]?.toString() ?? "") : (data["tags"]?.toString() ?? "");
    post.artist = data["tag_string_artist"]?.toString() ?? "";
    post.fileExt = data["file_ext"]?.toString() ?? "";
    
    post.fileUrl = data["file_url"]?.toString() ?? data["large_file_url"]?.toString() ?? "";
    if (post.fileUrl.isEmpty && !isDanbooru && data.containsKey("directory") && data.containsKey("image")) {
       post.fileUrl = _getBaseUrl() + "/images/" + data["directory"].toString() + "/" + data["image"].toString();
    }
    
    post.previewUrl = data["preview_file_url"]?.toString() ?? data["preview_url"]?.toString() ?? post.fileUrl;
    
    return post;
  }

  // --- Preferences ---

  /// True when list/detail requests must use Danbooru `/posts.json` (not Gelbooru dapi).
  /// Infers Gelbooru DAPI for `api.rule34.*` and common Gelbooru hosts when preference is unset.
  bool _useDanbooruSchema() {
    final base = _getBaseUrl().toLowerCase();
    if (base.contains("api.rule34")) {
      return false;
    }
    final type = _getPreference("provider").toLowerCase();
    if (type == "gelbooru") {
      return false;
    }
    if (type == "danbooru") {
      return true;
    }
    if (type.isEmpty) {
      if (base.contains("gelbooru") || base.contains("safebooru")) {
        return false;
      }
      return true;
    }
    return true;
  }

  /// Rebuild chapters from primitive fields to avoid BridgedInstance cast errors in host DB merge.
  List<MChapter> _materializeChapters(List<MChapter> raw) {
    return raw
        .map(
          (c) => MChapter(
            name: c.name,
            url: c.url,
            dateUpload: c.dateUpload,
            scanlator: c.scanlator,
            isFiller: c.isFiller,
            thumbnailUrl: c.thumbnailUrl,
            description: c.description,
            downloadSize: c.downloadSize,
            duration: c.duration,
          ),
        )
        .toList();
  }

  String _listCoverFromData(Map<String, dynamic> data, _BooruPost post) {
    final candidates = <String?>[
      data["sample_url"]?.toString(),
      data["large_file_url"]?.toString(),
      data["preview_file_url"]?.toString(),
      data["preview_url"]?.toString(),
      post.fileUrl.isNotEmpty ? post.fileUrl : null,
    ];
    for (final c in candidates) {
      if (c != null && c.isNotEmpty) {
        return c;
      }
    }
    return "";
  }

  /// Ported from Aidoku multi.booru `infer_title` (simplified for Dart).
  String _inferDisplayTitle(
    Map<String, dynamic> data,
    _BooruPost post,
    bool isDanbooru,
  ) {
    if (isDanbooru) {
      final copy = _splitTagLine(
        data["tag_string_copyright"]?.toString() ?? "",
      );
      final chars = _splitTagLine(
        data["tag_string_character"]?.toString() ?? "",
      );
      if (copy.isNotEmpty && chars.isNotEmpty) {
        return _prettyTag(copy.first) + " - " + _prettyTag(chars.first);
      }
      if (copy.isNotEmpty) {
        return _prettyTag(copy.first);
      }
    }
    final parts = _splitTagLine(post.tags);
    if (parts.isNotEmpty) {
      final n = parts.length >= 3 ? 3 : parts.length;
      return parts.take(n).map(_prettyTag).join(", ");
    }
    return "Post #" + post.id;
  }

  List<String> _splitTagLine(String raw) {
    return raw
        .split(RegExp(r"\s+"))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  String _prettyTag(String tag) => tag.replaceAll("_", " ");

  String _getBaseUrl() {
    final url = _getPreference("domain_url");
    if (url.isNotEmpty) return url;
    return source.baseUrl; 
  }
  
  String _getPreference(String key) {
    return getPreferenceValue(source.id, key)?.toString().trim() ?? "";
  }
  
  Map<String, String> _getHeaders() {
    return {
      "User-Agent": "Mangayomi-Booru-Client/1.0",
      "Accept": "application/json",
    };
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key: "domain_url",
        title: "Base URL",
        summary: "The base domain for the Booru (e.g., https://danbooru.donmai.us or https://gelbooru.com)",
        value: source.baseUrl,
        dialogTitle: "URL",
        dialogMessage: "",
      ),
      ListPreference(
        key: "provider",
        title: "API Provider Schema",
        summary: "Danbooru uses /posts.json; Gelbooru uses dapi. Hosts api.rule34.* use Gelbooru DAPI automatically.",
        valueIndex: 0,
        entries: ["Danbooru", "Gelbooru"],
        entryValues: ["danbooru", "gelbooru"],
      ),
      EditTextPreference(
        key: "login",
        title: "Danbooru Login",
        summary: "Optional login username for Danbooru-based sites",
        value: "",
        dialogTitle: "Login",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "user_id",
        title: "Gelbooru User ID",
        summary: "Optional User ID for Gelbooru-based sites",
        value: "",
        dialogTitle: "User ID",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "api_key",
        title: "API Key",
        summary: "Optional API Key for bypassing limits",
        value: "",
        dialogTitle: "API Key",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "tag_blacklist",
        title: "AI Blocklist",
        summary: "Comma-separated tags to exclude from all results. Prepended as -tag exclusions on every request.",
        value: "ai_generated, stable_diffusion, midjourney",
        dialogTitle: "Tag Blacklist",
        dialogMessage: "Comma-separated list, e.g. ai_generated, stable_diffusion",
      ),
    ];
  }
  
  @override
  List<dynamic> getFilterList() {
    return [];
  }
}

class _BooruPost {
  String id = "";
  String tags = "";
  String artist = "";
  String previewUrl = "";
  String fileUrl = "";
  String fileExt = "";
}

MultiBooru main(MSource source) {
  return MultiBooru(source: source);
}
