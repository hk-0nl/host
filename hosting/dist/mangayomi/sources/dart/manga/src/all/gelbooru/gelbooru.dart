import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

// ─── Gelbooru source for Mangayomi ───────────────────────────────────────────
// API: /index.php?page=dapi&s=post&q=index&json=1
// Pagination: &pid= (0-based)
//
// ── Changes in 0.0.3 ─────────────────────────────────────────────────────────
// FEAT  — Optional account-free fringeBenefits cookie exposes all site content.
//
// ── Changes in 0.0.2 ─────────────────────────────────────────────────────────
// FIX 1 — Connection: close added to _headers() (mandatory arch rule — was missing)
// FIX 2 — _fetchPost was returning MPages([], false) on null response instead of
//          {}. This caused a type cast crash when getDetail tried post["file_url"].
// FEAT  — getVideoList implemented for multi-media type support.
// FEAT  — Video posts now use actual video file URL as chapter URL (not preview still).
//
// See 0.0.1 revision comments for CDN Referer and GIF sample_url fixes.

class Gelbooru extends MProvider {
  Gelbooru({required this.source});

  final MSource source;
  final Client client = Client();

  // ── Listing ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) =>
      _fetchPage(page, extraTags: "sort:score:desc");

  @override
  Future<MPages> getLatestUpdates(int page) => _fetchPage(page, extraTags: "");

  @override
  Future<MPages> search(String query, int page, FilterList filterList) {
    String tags = query.trim();
    String ratingTag = "";
    String sortTag = "";
    for (final f in filterList.filters) {
      if (f.name == "Rating" && (f.state as int) > 0) {
        const ratings = [
          "",
          "rating:general",
          "rating:sensitive",
          "rating:questionable",
          "rating:explicit",
        ];
        final idx = f.state as int;
        if (idx < ratings.length) ratingTag = ratings[idx];
      }
      if (f.name == "Sort") {
        final idx = f.state as int;
        if (idx == 1) sortTag = "sort:score:desc";
        if (idx == 2) sortTag = "sort:score:asc";
      }
    }
    final parts = <String>[];
    if (tags.isNotEmpty) parts.add(tags);
    if (ratingTag.isNotEmpty) parts.add(ratingTag);
    if (sortTag.isNotEmpty) parts.add(sortTag);
    return _fetchPage(page, extraTags: parts.join(" "));
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final id = _idFromUrl(url);
    final post = await _fetchPost(id);
    final fileUrl = post["file_url"]?.toString() ?? "";
    final sample = post["sample_url"]?.toString() ?? fileUrl;
    final preview = post["preview_url"]?.toString() ?? sample;
    final ext = (post["file_ext"]?.toString() ?? "").toLowerCase();
    final isVideo = ext == "webm" || ext == "mp4";
    final isAnimated = ext == "gif";

    final manga = MManga();
    manga.name = _buildTitle(post, id);
    manga.imageUrl = preview.isNotEmpty ? preview : fileUrl;

    if (isVideo) {
      // FEAT: Use actual video file URL so getVideoList() hands it to the player.
      manga.description =
          "VIDEO POST (." +
          ext +
          ")" +
          "\nDirect URL: " +
          fileUrl +
          "\n\n" +
          _buildDescription(post, id) +
          "\n\nOpen as video chapter for in-app playback.";
      manga.chapters = [
        MChapter(
          name: "Play video (." + ext + ")",
          url: fileUrl.isNotEmpty ? fileUrl : preview,
        ),
      ];
    } else if (isAnimated) {
      manga.description = _buildDescription(post, id);
      manga.chapters = [
        MChapter(
          name: "Animated GIF",
          url: sample.isNotEmpty ? sample : fileUrl,
        ),
      ];
    } else {
      manga.description = _buildDescription(post, id);
      final chapters = <MChapter>[];
      if (fileUrl.isNotEmpty)
        chapters.add(MChapter(name: "Image ." + ext, url: fileUrl));
      if (chapters.isEmpty) {
        chapters.add(
          MChapter(
            name: "Open Post",
            url: _base() + "/?page=post&s=view&id=" + id,
          ),
        );
      }
      manga.chapters = chapters;
    }
    return manga;
  }

  // ── getPageList ───────────────────────────────────────────────────────────

  @override
  Future<List<dynamic>> getPageList(String url) async {
    return [
      {
        "url": url,
        "headers": {
          "Referer": _base() + "/",
          "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-Gelbooru/1.0)",
        },
      },
    ];
  }

  // ── getVideoList ──────────────────────────────────────────────────────────
  // FEAT: Multi-media type support. Video file URLs are returned as MVideo.

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final lower = url.toLowerCase();
    final isVideo = lower.endsWith(".mp4") || lower.endsWith(".webm");
    if (!isVideo) return [];
    final ext = url.split(".").last.split("?").first.toLowerCase();
    return [
      MVideo()
        ..url = url
        ..originalUrl = url
        ..quality = "Direct ." + ext,
    ];
  }

  // ── Private API ───────────────────────────────────────────────────────────

  Future<MPages> _fetchPage(int page, {String extraTags = ""}) async {
    final rawBlacklist =
        getPreferenceValue(source.id, "tag_blacklist")?.toString() ?? "";
    final blacklistTags = rawBlacklist
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => "-" + e)
        .join(' ');

    String finalTags = extraTags;
    if (blacklistTags.isNotEmpty) {
      finalTags = finalTags.isEmpty
          ? blacklistTags
          : finalTags + " " + blacklistTags;
    }

    final pid = (page - 1).clamp(0, 9999999);
    String params =
        "page=dapi&s=post&q=index&json=1&limit=20&pid=" + pid.toString();
    if (finalTags.isNotEmpty)
      params += "&tags=" + Uri.encodeQueryComponent(finalTags);
    params += _authParams();

    final uri = Uri.parse(_base() + "/index.php?" + params);
    final res = await _safeGet(uri, headers: _headers());
    if (res == null) return _fetchHtmlPage(page, finalTags);
    final posts = _decodePostList(res.body);

    final items = <MManga>[];
    for (final raw in posts) {
      final post = _asMap(raw);
      final id = post["id"]?.toString() ?? "";
      if (id.isEmpty) continue;
      final fileUrl = post["file_url"]?.toString() ?? "";
      final preview =
          post["preview_url"]?.toString() ??
          post["sample_url"]?.toString() ??
          fileUrl;
      final item = MManga();
      item.name = _buildTitle(post, id);
      item.imageUrl = preview.isNotEmpty ? preview : fileUrl;
      item.link = "gelbooru://post?id=" + id;
      items.add(item);
    }
    return MPages(items, posts.length >= 20);
  }

  // FIX 2: Return {} on null, not MPages([], false).
  Future<Map<String, dynamic>> _fetchPost(String id) async {
    String params =
        "page=dapi&s=post&q=index&json=1&id=" + Uri.encodeQueryComponent(id);
    params += _authParams();
    final uri = Uri.parse(_base() + "/index.php?" + params);
    final res = await _safeGet(uri, headers: _headers());
    if (res == null) return _fetchHtmlPost(id);
    final posts = _decodePostList(res.body);
    if (posts.isEmpty) return _fetchHtmlPost(id);
    return _asMap(posts.first);
  }

  Future<MPages> _fetchHtmlPage(int page, String tags) async {
    final offset = (page - 1).clamp(0, 9999999) * 42;
    String params = "page=post&s=list&pid=" + offset.toString();
    if (tags.isNotEmpty) params += "&tags=" + Uri.encodeQueryComponent(tags);
    final res = await _safeGet(
      Uri.parse(_base() + "/index.php?" + params),
      headers: _headers(),
    );
    if (res == null) return MPages([], false);

    final pattern = RegExp(
      r'''href="([^"]*page=post(?:&amp;|&)s=view(?:&amp;|&)id=(\d+)[^"]*)"[^>]*>\s*<img[^>]+(?:data-src|src)="([^"]+)"''',
      caseSensitive: false,
      multiLine: true,
    );
    final items = <MManga>[];
    final seen = <String>{};
    for (final match in pattern.allMatches(res.body)) {
      final id = match.group(2) ?? "";
      final thumbnail = _absoluteUrl(_decodeHtml(match.group(3) ?? ""));
      if (id.isEmpty || thumbnail.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      final item = MManga();
      item.name = "#" + id;
      item.imageUrl = thumbnail;
      item.link = "gelbooru://post?id=" + id;
      items.add(item);
    }
    return MPages(items, items.length >= 42);
  }

  Future<Map<String, dynamic>> _fetchHtmlPost(String id) async {
    final uri = Uri.parse(
      _base() +
          "/index.php?page=post&s=view&id=" +
          Uri.encodeQueryComponent(id),
    );
    final res = await _safeGet(uri, headers: _headers());
    if (res == null) return {};

    final originalMatch = RegExp(
      r'''href="([^"]+)"[^>]*>\s*Original image''',
      caseSensitive: false,
    ).firstMatch(res.body);
    final openGraphMatch = RegExp(
      r'''<meta[^>]+property="og:image"[^>]+content="([^"]+)"''',
      caseSensitive: false,
    ).firstMatch(res.body);
    final sampleMatch = RegExp(
      r'''<img[^>]+id="image"[^>]+src="([^"]+)"''',
      caseSensitive: false,
    ).firstMatch(res.body);
    final titleMatch = RegExp(
      r'''<title>(.*?)</title>''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(res.body);

    final fileUrl = _absoluteUrl(
      _decodeHtml(originalMatch?.group(1) ?? openGraphMatch?.group(1) ?? ""),
    );
    if (fileUrl.isEmpty) return {};
    final sampleUrl = _absoluteUrl(
      _decodeHtml(sampleMatch?.group(1) ?? fileUrl),
    );
    final path = Uri.tryParse(fileUrl)?.path ?? fileUrl;
    final dot = path.lastIndexOf(".");
    final extension = dot == -1 ? "" : path.substring(dot + 1).toLowerCase();
    final title = _decodeHtml(titleMatch?.group(1) ?? "");
    final tags = title.split(" - Image View").first.replaceAll(", ", " ");

    return <String, dynamic>{
      "id": id,
      "file_url": fileUrl,
      "sample_url": extension == "gif" ? fileUrl : sampleUrl,
      "preview_url": sampleUrl,
      "file_ext": extension,
      "tags": tags,
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _buildTitle(Map<String, dynamic> post, String id) {
    final tags = post["tags"]?.toString() ?? "";
    final topTags = tags
        .split(" ")
        .where((t) => t.isNotEmpty && t.length > 2)
        .take(3)
        .join(", ");
    return topTags.isNotEmpty ? "#" + id + " \u2013 " + topTags : "#" + id;
  }

  String _buildDescription(Map<String, dynamic> post, String id) {
    final lines = <String>[];
    lines.add("Post ID: #" + id);
    final score = post["score"]?.toString() ?? "";
    if (score.isNotEmpty) lines.add("Score: " + score);
    final rating = post["rating"]?.toString() ?? "";
    if (rating.isNotEmpty) lines.add("Rating: " + rating);
    final ext = post["file_ext"]?.toString() ?? "";
    if (ext.isNotEmpty) lines.add("Format: ." + ext);
    final w = post["width"]?.toString() ?? "";
    final h = post["height"]?.toString() ?? "";
    if (w.isNotEmpty && h.isNotEmpty)
      lines.add("Resolution: " + w + "\u00d7" + h);
    final src = post["source"]?.toString() ?? "";
    if (src.isNotEmpty) lines.add("Source: " + src);
    final created = post["created_at"]?.toString() ?? "";
    if (created.isNotEmpty) lines.add("Posted: " + created);
    final tags = post["tags"]?.toString() ?? "";
    if (tags.isNotEmpty) lines.add("\nTags:\n" + tags.replaceAll(" ", ", "));
    return lines.join("\n");
  }

  String _idFromUrl(String url) {
    if (url.startsWith("gelbooru://")) {
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

  String _decodeHtml(String value) => value
      .replaceAll("&amp;", "&")
      .replaceAll("&quot;", '"')
      .replaceAll("&#039;", "'")
      .replaceAll("&lt;", "<")
      .replaceAll("&gt;", ">");

  String _absoluteUrl(String value) {
    if (value.startsWith("//")) return "https:" + value;
    if (value.startsWith("/")) return _base() + value;
    return value;
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

  String _base() {
    final v = _pref("domain_url");
    if (v.isNotEmpty) return v.endsWith("/") ? v.substring(0, v.length - 1) : v;
    return source.baseUrl;
  }

  String _pref(String key) =>
      getPreferenceValue(source.id, key)?.toString().trim() ?? "";

  bool _prefEnabled(String key) {
    final value = _pref(key).toLowerCase();
    return value == "true" || value == "1" || value == "yes" || value == "on";
  }

  String _authParams() {
    final userId = _pref("user_id");
    final apiKey = _pref("api_key");
    if (userId.isEmpty || apiKey.isEmpty) return "";
    return "&user_id=" +
        Uri.encodeQueryComponent(userId) +
        "&api_key=" +
        Uri.encodeQueryComponent(apiKey);
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-Gelbooru/1.0)",
      "Accept": "application/json",
      "Referer": _base() + "/",
      "Connection": "close",
    };
    if (_prefEnabled("display_all_site_content")) {
      headers["Cookie"] = "fringeBenefits=yup";
    }
    return headers;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  @override
  List<dynamic> getFilterList() {
    return [
      SelectFilter("SelectFilter", "Rating", 0, [
        SelectFilterOption("Any", "", null),
        SelectFilterOption("General", "rating:general", null),
        SelectFilterOption("Sensitive", "rating:sensitive", null),
        SelectFilterOption("Questionable", "rating:questionable", null),
        SelectFilterOption("Explicit", "rating:explicit", null),
      ], null),
      SelectFilter("SelectFilter", "Sort", 0, [
        SelectFilterOption("Newest", "", null),
        SelectFilterOption("Score (high\u2192low)", "sort:score:desc", null),
        SelectFilterOption("Score (low\u2192high)", "sort:score:asc", null),
      ], null),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key: "domain_url",
        title: "Base URL",
        summary: "e.g. https://gelbooru.com",
        value: source.baseUrl,
        dialogTitle: "URL",
        dialogMessage: "",
      ),
      SwitchPreferenceCompat(
        key: "display_all_site_content",
        title: "Display all site content",
        summary: "Use Gelbooru's account-free browser content preference.",
        value: false,
      ),
      EditTextPreference(
        key: "user_id",
        title: "User ID",
        summary: "Gelbooru User ID for explicit content and favorites.",
        value: "",
        dialogTitle: "User ID",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "api_key",
        title: "API Key",
        summary: "Gelbooru API Key \u2014 found in your account settings.",
        value: "",
        dialogTitle: "API Key",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "tag_blacklist",
        title: "AI Blocklist",
        summary: "Comma-separated tags to exclude from all results.",
        value: "ai_generated, stable_diffusion, midjourney",
        dialogTitle: "Tag Blacklist",
        dialogMessage:
            "Comma-separated list, e.g. ai_generated, stable_diffusion",
      ),
    ];
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

Gelbooru main(MSource source) => Gelbooru(source: source);
