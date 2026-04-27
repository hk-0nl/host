import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

// ─── Gelbooru source for Mangayomi ───────────────────────────────────────────
// API: /index.php?page=dapi&s=post&q=index&json=1
// Pagination: &pid= (0-based, NOT the page number — pid = page - 1)
//
// ── Bug fixes in this revision ───────────────────────────────────────────────
// FIX 1 — Native image loading failing (403 on all posts):
//   img1–img4.gelbooru.com rejects requests without a matching Referer.
//   getPageList() now returns List<Map<String,dynamic>> with "headers" instead
//   of a bare List<String>, injecting Referer and User-Agent per image.
//   This is the same pattern used by MangaPark in the upstream extensions repo.
//
// FIX 2 — Animated/GIF chapter URL pointing at tiny thumb:
//   The previous video-fallback set chapter.url = preview_url for .gif posts,
//   which is a ~150×150 preview thumbnail served from a separate thumb CDN.
//   The correct URL for GIFs is sample_url (medium compressed) or file_url
//   (original, potentially large). We now use sample_url for GIFs so the
//   reader gets a properly sized image rather than a 150px thumb.
//   For .webm / .mp4 we keep preview_url as the still frame (correct — these
//   can't be embedded in the manga reader anyway).
//
// Auth: optional &user_id=&api_key= for higher rate limits and private content.
//
// Post key fields: id, tags, score, rating, file_url, sample_url,
//   preview_url, file_ext, width, height, source, created_at

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
    String tags      = query.trim();
    String ratingTag = "";
    String sortTag   = "";

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
    if (tags.isNotEmpty)      parts.add(tags);
    if (ratingTag.isNotEmpty) parts.add(ratingTag);
    if (sortTag.isNotEmpty)   parts.add(sortTag);
    return _fetchPage(page, extraTags: parts.join(" "));
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final id      = _idFromUrl(url);
    final post    = await _fetchPost(id);
    final fileUrl = post["file_url"]?.toString()    ?? "";
    final sample  = post["sample_url"]?.toString()  ?? fileUrl;
    final preview = post["preview_url"]?.toString() ?? sample;
    final ext     = (post["file_ext"]?.toString() ?? "").toLowerCase();

    // FIX 2: Classify post type precisely for the chapter URL.
    //   .mp4 / .webm → true video (use still preview in reader)
    //   .gif          → animated image (use sample_url — properly sized)
    //   everything else → still image (use file_url)
    final isVideo     = ext == "webm" || ext == "mp4";
    final isAnimated  = ext == "gif";

    final manga = MManga();
    manga.name     = _buildTitle(post, id);
    manga.imageUrl = preview.isNotEmpty ? preview : fileUrl;

    if (isVideo) {
      manga.description =
          "🎬 VIDEO POST (.$ext)"
          "\nDirect URL: $fileUrl"
          "\n\n${_buildDescription(post, id)}"
          "\n\nTip: Use the Rule34Video source for full video playback.";
      // Chapter URL = preview still frame (not the video file)
      manga.chapters = [
        MChapter(
          name: "Preview still (video — see description for direct link)",
          url:  preview.isNotEmpty ? preview : fileUrl,
        ),
      ];
    } else if (isAnimated) {
      // FIX 2: GIF chapter URL must be sample_url (medium-res GIF),
      // NOT preview_url (150×150 thumbnail). preview_url is only suitable
      // as the cover image, not the reader page.
      manga.description = _buildDescription(post, id);
      manga.chapters = [
        MChapter(
          name: "Animated GIF",
          url:  sample.isNotEmpty ? sample : fileUrl,
        ),
      ];
    } else {
      manga.description = _buildDescription(post, id);
      final chapters = <MChapter>[];
      if (fileUrl.isNotEmpty) {
        chapters.add(MChapter(name: "Image .$ext", url: fileUrl));
      }
      if (chapters.isEmpty) {
        chapters.add(MChapter(
          name: "Open Post",
          url:  "${_base()}/?page=post&s=view&id=$id",
        ));
      }
      manga.chapters = chapters;
    }
    return manga;
  }

  // ── getPageList ───────────────────────────────────────────────────────────
  // FIX 1: Return Map<String,dynamic> with "headers" field.
  // img1–img4.gelbooru.com checks Referer; without it the CDN returns 403,
  // which surfaces in Mangayomi as a broken image / blank reader page.
  @override
  Future<List<dynamic>> getPageList(String url) async {
    return [
      {
        "url": url,
        "headers": {
          "Referer":    _base() + "/",
          "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-Gelbooru/1.0)",
        },
      }
    ];
  }

  // ── Private API ───────────────────────────────────────────────────────────

  Future<MPages> _fetchPage(int page, {String extraTags = ""}) async {
    // Read and format AI blocklist
    final rawBlacklist = getPreferenceValue(source.id, "tag_blacklist")?.toString() ?? "";
    final blacklistTags = rawBlacklist
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => "-$e")
        .join(' ');

    String finalTags = extraTags;
    if (blacklistTags.isNotEmpty) {
      finalTags = finalTags.isEmpty ? blacklistTags : "$finalTags $blacklistTags";
    }

    // Gelbooru uses pid (0-based), not page (1-based).
    final pid = (page - 1).clamp(0, 9999999);
    String params = "page=dapi&s=post&q=index&json=1&limit=20&pid=$pid";
    if (finalTags.isNotEmpty) {
      params += "&tags=${Uri.encodeQueryComponent(finalTags)}";
    }
    params += _authParams();

    final uri = Uri.parse("${_base()}/index.php?$params");
    final res = await client.get(uri, headers: _headers());
    final posts = _decodePostList(res.body);

    final items = <MManga>[];
    for (final raw in posts) {
      final post = _asMap(raw);
      final id   = post["id"]?.toString() ?? "";
      if (id.isEmpty) continue;

      final fileUrl = post["file_url"]?.toString() ?? "";
      final preview = post["preview_url"]?.toString() ??
          post["sample_url"]?.toString()  ??
          fileUrl;

      final item = MManga();
      item.name     = _buildTitle(post, id);
      item.imageUrl = preview.isNotEmpty ? preview : fileUrl;
      item.link     = "gelbooru://post?id=$id";
      items.add(item);
    }
    return MPages(items, posts.length >= 20);
  }

  Future<Map<String, dynamic>> _fetchPost(String id) async {
    String params = "page=dapi&s=post&q=index&json=1&id=${Uri.encodeQueryComponent(id)}";
    params += _authParams();
    final uri = Uri.parse("${_base()}/index.php?$params");
    final res = await client.get(uri, headers: _headers());
    final posts = _decodePostList(res.body);
    if (posts.isEmpty) return {};
    return _asMap(posts.first);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _buildTitle(Map<String, dynamic> post, String id) {
    final tags    = post["tags"]?.toString() ?? "";
    final topTags = tags
        .split(" ")
        .where((t) => t.isNotEmpty && t.length > 2)
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
    final w = post["width"]?.toString()  ?? "";
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
    // Handle gelbooru:// internal scheme
    if (url.startsWith("gelbooru://")) {
      final q = url.indexOf("id=");
      if (q != -1) {
        final rest = url.substring(q + 3);
        final amp  = rest.indexOf("&");
        return amp == -1 ? rest : rest.substring(0, amp);
      }
    }
    // Handle ?...id=... in a standard URL
    final q = url.indexOf("id=");
    if (q != -1) {
      final rest = url.substring(q + 3);
      final amp  = rest.indexOf("&");
      return amp == -1 ? rest : rest.substring(0, amp);
    }
    return url.split("/").where((s) => s.isNotEmpty).last.split("?").first;
  }

  /// Parses Gelbooru DAPI responses, handling both the old bare-list format
  /// and the 0.2.5 wrapped { "@attributes": {...}, "post": [...] } format.
  List<dynamic> _decodePostList(String body) {
    try {
      final d = jsonDecode(body);
      if (d is List) return d;
      if (d is Map) {
        final posts = d["post"];
        if (posts is List) return posts;
        if (posts is Map)  return [posts]; // single-result edge case
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

  /// Returns "&user_id=...&api_key=..." if credentials are set, else "".
  String _authParams() {
    final userId = _pref("user_id");
    final apiKey = _pref("api_key");
    if (userId.isEmpty || apiKey.isEmpty) return "";
    return "&user_id=${Uri.encodeQueryComponent(userId)}"
        "&api_key=${Uri.encodeQueryComponent(apiKey)}";
  }

  Map<String, String> _headers() => {
        "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-Gelbooru/1.0)",
        "Accept":     "application/json",
        "Referer":    _base() + "/",
      };

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
        SelectFilterOption("Any",          "",                    null),
        SelectFilterOption("General",      "rating:general",      null),
        SelectFilterOption("Sensitive",    "rating:sensitive",    null),
        SelectFilterOption("Questionable", "rating:questionable", null),
        SelectFilterOption("Explicit",     "rating:explicit",     null),
      ], null),
      SelectFilter("SelectFilter", "Sort", 0, [
        SelectFilterOption("Newest",         "",                null),
        SelectFilterOption("Score (high→low)", "sort:score:desc", null),
        SelectFilterOption("Score (low→high)", "sort:score:asc",  null),
      ], null),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key:          "domain_url",
        title:        "Base URL",
        summary:      "e.g. https://gelbooru.com — can point at other Gelbooru-compatible boards",
        value:        source.baseUrl,
        dialogTitle:  "URL",
        dialogMessage: "",
      ),
      EditTextPreference(
        key:          "user_id",
        title:        "User ID",
        summary:      "Gelbooru User ID — required for explicit content and favorites. "
                      "Find it at gelbooru.com/index.php?page=account",
        value:        "",
        dialogTitle:  "User ID",
        dialogMessage: "",
      ),
      EditTextPreference(
        key:          "api_key",
        title:        "API Key",
        summary:      "Gelbooru API Key — found in your account settings.",
        value:        "",
        dialogTitle:  "API Key",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "tag_blacklist",
        title: "AI Blocklist",
        summary: "Comma-separated tags to exclude from all results. Prepended as -tag exclusions.",
        value: "ai_generated, stable_diffusion, midjourney",
        dialogTitle: "Tag Blacklist",
        dialogMessage: "Comma-separated list, e.g. ai_generated, stable_diffusion",
      ),
    ];
  }
}

Gelbooru main(MSource source) => Gelbooru(source: source);
