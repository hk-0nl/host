import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

// ─── Rule34 source for Mangayomi ──────────────────────────────────────────────
// API base: https://api.rule34.xxx  (NOT the main site rule34.xxx)
// Endpoint: /index.php?page=dapi&s=post&q=index&json=1
// Pagination: &pid= (0-based)
// No account auth via API currently (only session cookies after login).
// Video posts: file_ext in {webm, mp4}, animated GIF posts use file_ext=gif.
// Tag-based type filter: use tag "animated" for GIF/webm, "video" for full video.
//
// Post key fields: id, tags, score, rating, file_url, sample_url, preview_url,
//   file_ext, width, height, source, created_at, change

class Rule34 extends MProvider {
  Rule34({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Future<MPages> getPopular(int page) =>
      // Use DAPI URL sort params (sort:score tag is web-search only, ignored by DAPI)
      _fetchPage(page, extraTags: "", sort: "score", order: "desc");

  @override
  Future<MPages> getLatestUpdates(int page) => _fetchPage(page, extraTags: "");

  @override
  Future<MPages> search(String query, int page, FilterList filterList) {
    String tags = query.trim();
    String typeTag = "";
    String ratingTag = "";

    for (final f in filterList.filters) {
      if (f.name == "Media Type" && (f.state as int) > 0) {
        final types = ["", "animated", "-animated -video", "video"];
        final idx = f.state as int;
        if (idx < types.length) typeTag = types[idx];
      }
      if (f.name == "Rating" && (f.state as int) > 0) {
        final ratings = ["", "rating:general", "rating:questionable", "rating:explicit"];
        final idx = f.state as int;
        if (idx < ratings.length) ratingTag = ratings[idx];
      }
    }

    final parts = <String>[];
    if (tags.isNotEmpty) parts.add(tags);
    if (typeTag.isNotEmpty) parts.add(typeTag);
    if (ratingTag.isNotEmpty) parts.add(ratingTag);
    return _fetchPage(page, extraTags: parts.join(" "));
  }

  @override
  Future<MManga> getDetail(String url) async {
    final id = _idFromUrl(url);
    final post = await _fetchPost(id);

    final fileUrl = post["file_url"]?.toString() ?? "";
    final sample = post["sample_url"]?.toString() ?? fileUrl;
    final preview = post["preview_url"]?.toString() ?? sample;
    final ext = (post["file_ext"]?.toString() ?? "").toLowerCase();
    final isVideo = ext == "webm" || ext == "mp4";

    final manga = MManga();
    manga.name = _buildTitle(post, id);
    manga.imageUrl = preview.isNotEmpty ? preview : fileUrl;

    if (isVideo) {
      // Video posts: the manga reader can't render mp4/webm — show the still
      // preview image instead, and surface the direct video URL in the description
      // so the user can copy/open it externally.
      manga.description =
          "🎬 VIDEO POST (.$ext)"
          "\nDirect URL: $fileUrl"
          "\n\n${_buildDescription(post, id)}"
          "\n\nTip: Use the Rule34Video source for full video playback.";
      manga.chapters = [
        MChapter(
          // Use file_url for the chapter URL so the player gets the actual
          // video file. preview is a tiny static JPEG — wrong for playback.
          name: "Preview (video — see description for direct link)",
          url: fileUrl.isNotEmpty ? fileUrl : preview,
        ),
      ];
    } else {
      manga.description = _buildDescription(post, id);
      final chapters = <MChapter>[];
      if (fileUrl.isNotEmpty) {
        final isGif = ext == "gif";
        chapters.add(MChapter(
          name: isGif ? "Animated GIF" : "Image .$ext",
          url: fileUrl,
        ));
      }
      if (chapters.isEmpty) {
        chapters.add(MChapter(name: "Open Post", url: "https://rule34.xxx/index.php?page=post&s=view&id=$id"));
      }
      manga.chapters = chapters;
    }
    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    // Rule34 CDN (img3.rule34.xxx, etc.) checks Referer.
    // Return Map form so Mangayomi injects the header on the image request.
    return [
      {
        "url": url,
        "headers": {
          "Referer":    "https://rule34.xxx/",
          "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-Rule34/1.0)",
        },
      }
    ];
  }

  // ── Private API ───────────────────────────────────────────────────────────

  Future<MPages> _fetchPage(int page, {String extraTags = "", String sort = "", String order = ""}) async {
    final pid = (page - 1).clamp(0, 9999999);
    // ── Tag blacklist ─────────────────────────────────────────────────────────
    final _blacklistRaw = _pref("tag_blacklist");
    if (_blacklistRaw.isNotEmpty) {
      final _exclusions = _blacklistRaw
          .split(",")
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .map((t) => "-$t")
          .join(" ");
      if (_exclusions.isNotEmpty) {
        extraTags = extraTags.isNotEmpty ? "$extraTags $_exclusions" : _exclusions;
      }
    }
    String params = "page=dapi&s=post&q=index&json=1&limit=20&pid=$pid";
    if (extraTags.isNotEmpty) params += "&tags=${Uri.encodeQueryComponent(extraTags)}";
    // DAPI URL-param sort (same as Gelbooru; tag-based sort:score not supported in DAPI)
    if (sort.isNotEmpty) params += "&sort=${Uri.encodeQueryComponent(sort)}";
    if (order.isNotEmpty) params += "&order=${Uri.encodeQueryComponent(order)}";
    final userId = _pref("user_id");
    final apiKey = _pref("api_key");
    if (userId.isNotEmpty && apiKey.isNotEmpty) {
      params += "&user_id=${Uri.encodeQueryComponent(userId)}&api_key=${Uri.encodeQueryComponent(apiKey)}";
    }
    final uri = Uri.parse("${_apiBase()}/index.php?$params");
    final res = await client.get(uri, headers: _headers());
    final posts = _decodePostList(res.body);

    final items = <MManga>[];
    for (final raw in posts) {
      final post = _asMap(raw);
      final id = post["id"]?.toString() ?? "";
      if (id.isEmpty) continue;
      final fileUrl = post["file_url"]?.toString() ?? "";
      final preview = post["preview_url"]?.toString() ?? post["sample_url"]?.toString() ?? fileUrl;

      final item = MManga();
      item.name = _buildTitle(post, id);
      item.imageUrl = preview.isNotEmpty ? preview : fileUrl;
      item.link = "rule34://post?id=$id";
      items.add(item);
    }
    return MPages(items, posts.length >= 20);
  }

  Future<Map<String, dynamic>> _fetchPost(String id) async {
    String params = "page=dapi&s=post&q=index&json=1&id=${Uri.encodeQueryComponent(id)}";
    final userId = _pref("user_id");
    final apiKey = _pref("api_key");
    if (userId.isNotEmpty && apiKey.isNotEmpty) {
      params += "&user_id=${Uri.encodeQueryComponent(userId)}&api_key=${Uri.encodeQueryComponent(apiKey)}";
    }
    final uri = Uri.parse("${_apiBase()}/index.php?$params");
    final res = await client.get(uri, headers: _headers());
    final posts = _decodePostList(res.body);
    if (posts.isEmpty) return {};
    return _asMap(posts.first);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _buildTitle(Map<String, dynamic> post, String id) {
    final tags = post["tags"]?.toString() ?? "";
    // Show first few short meaningful tags (skip meta-tags like aspect ratio)
    final topTags = tags
        .split(" ")
        .where((t) => t.isNotEmpty && t.length > 2 && !t.contains(":"))
        .take(3)
        .join(", ");
    return topTags.isNotEmpty ? "#$id – $topTags" : "#$id";
  }

  String _buildDescription(Map<String, dynamic> post, String id) {
    final lines = <String>[];
    lines.add("Post ID: #$id");
    final score = post["score"]?.toString() ?? "";
    if (score.isNotEmpty) lines.add("Score: $score");
    final rating = post["rating"]?.toString() ?? "";
    if (rating.isNotEmpty) lines.add("Rating: $rating");
    final ext = post["file_ext"]?.toString() ?? "";
    if (ext.isNotEmpty) lines.add("Format: .$ext");
    final w = post["width"]?.toString() ?? "";
    final h = post["height"]?.toString() ?? "";
    if (w.isNotEmpty && h.isNotEmpty) lines.add("Resolution: ${w}×${h}");
    final src = post["source"]?.toString() ?? "";
    if (src.isNotEmpty) lines.add("Source: $src");
    final created = post["created_at"]?.toString() ?? "";
    if (created.isNotEmpty) lines.add("Posted: $created");
    final tags = post["tags"]?.toString() ?? "";
    if (tags.isNotEmpty) lines.add("\nTags:\n${tags.replaceAll(" ", ", ")}");
    return lines.join("\n");
  }

  String _idFromUrl(String url) {
    if (url.startsWith("rule34://")) {
      final q = url.indexOf("id=");
      if (q != -1) {
        final rest = url.substring(q + 3);
        final amp = rest.indexOf("&");
        return amp == -1 ? rest : rest.substring(0, amp);
      }
    }
    final q = url.indexOf("id=");
    if (q != -1) {
      final rest = url.substring(q + 3);
      final amp = rest.indexOf("&");
      return amp == -1 ? rest : rest.substring(0, amp);
    }
    return url.split("/").where((s) => s.isNotEmpty).last.split("?").first;
  }

  List<dynamic> _decodePostList(String body) {
    try {
      final d = jsonDecode(body);
      if (d is List) return d;
      if (d is Map) {
        final posts = d["post"];
        if (posts is List) return posts;
        if (posts is Map) return [posts];
      }
    } catch (_) {}
    return [];
  }

  String _apiBase() {
    final v = _pref("api_url");
    if (v.isNotEmpty) return v.endsWith("/") ? v.substring(0, v.length - 1) : v;
    return "https://api.rule34.xxx";
  }

  String _pref(String key) =>
      getPreferenceValue(source.id, key)?.toString().trim() ?? "";

  Map<String, String> _headers() => {
        "User-Agent": "Mangayomi-Rule34/1.0",
        "Accept": "application/json",
        "Connection": "close",
      };

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  // ── Filters (5 positional per bridge spec) ────────────────────────────────

  @override
  List<dynamic> getFilterList() {
    return [
      SelectFilter("SelectFilter", "Media Type", 0, [
        SelectFilterOption("All", "", null),
        SelectFilterOption("Animated (GIF/WebM)", "animated", null),
        SelectFilterOption("Images Only", "-animated -video", null),
        SelectFilterOption("Video Only", "video", null),
      ], null),
      SelectFilter("SelectFilter", "Rating", 0, [
        SelectFilterOption("Any", "", null),
        SelectFilterOption("General", "rating:general", null),
        SelectFilterOption("Questionable", "rating:questionable", null),
        SelectFilterOption("Explicit", "rating:explicit", null),
      ], null),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key: "api_url",
        title: "API Base URL",
        summary: "The Rule34 DAPI endpoint. Default: https://api.rule34.xxx",
        value: "https://api.rule34.xxx",
        dialogTitle: "API URL",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "user_id",
        title: "User ID (REQUIRED BY R34)",
        summary: "Rule34 API now mandates authentication. Find your ID at rule34.xxx/index.php?page=account&s=options",
        value: "",
        dialogTitle: "User ID",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "api_key",
        title: "API Key (REQUIRED BY R34)",
        summary: "Rule34 API Key. Generate or find it in your account options.",
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
}

Rule34 main(MSource source) => Rule34(source: source);
