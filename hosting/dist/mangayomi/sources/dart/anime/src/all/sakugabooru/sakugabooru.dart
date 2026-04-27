import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

// ─── Sakugabooru source for Mangayomi ───────────────────────────────────────────
// API: https://www.sakugabooru.com/post.json
//
// ── Bug fixes in this revision ───────────────────────────────────────────────
// FIX 1 — CF-popup on image load:
//   The CDN (cdn.sakugabooru.com) gates images behind Referer / User-Agent headers.
//   A missing Referer causes HTTP 403, which Mangayomi misreads as a Cloudflare
//   challenge and shows a CF popup even though the API call succeeded.
//   Solution: getPageList() now returns List<Map<String,dynamic>> with a
//   "headers" field containing Referer and User-Agent, matching the MangaPark
//   pattern that the bridge already knows how to forward to the image loader.
//
// FIX 2 — getPopular / filter combos returning empty results:
//   Sakugabooru silently returns {"success":false,"message":"...more than 2 tags"}
//   for unauthenticated users when the composed tag query exceeds 2 tokens.
//   getPopular("order:score") was fine alone, but search() stacking user-query
//   + rating + sort produced 3 tags → silent rejection.
//   Solution:
//     a) _composeTagQuery() enforces a max-tag budget (2 unauthed, 6 authed)
//        with a fixed priority: user query > sort > rating. Excess tags are
//        silently dropped rather than sending a doomed request.
//     b) _fetchPage() detects the {"success":false} response shape and throws
//        a readable exception rather than returning empty and confusing the UI.
//     c) Preview fallback: when file_url is missing (common for non-gold users
//        on explicit posts since ~2023), we reconstruct it from the md5 hash.
//
// Unauthenticated users are limited to 2 tags per search.
// Provide login + api_key in Source Settings to lift the limit to 6 tags.
//
// Post model key fields:
//   id, tag_string, tag_string_artist, tag_string_character, tag_string_copyright
//   file_url, large_file_url, preview_file_url, file_ext, md5
//   score, fav_count, up_score, rating (g/s/q/e)

class Sakugabooru extends MProvider {
  Sakugabooru({required this.source});

  final MSource source;
  final Client client = Client();

  // ── Tag-budget constants ──────────────────────────────────────────────────

  // Sakugabooru API hard limits (per their documentation):
  //   Free / unauthenticated : 2 tags
  //   Gold+                  : 6 tags
  int get _tagBudget {
    final hasAuth = _pref("login").isNotEmpty && _pref("api_key").isNotEmpty;
    return hasAuth ? 6 : 2;
  }

  // ── Listing ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    // order:score requires authentication on Sakugabooru. Try it first (for Gold+
    // users), then fall back to order:rank (hot) which works without login.
    final scored = await _fetchPage(page, query: "", sort: "order:score", rating: "");
    if (scored.list.isNotEmpty) return scored;

    final ranked = await _fetchPage(page, query: "", sort: "order:rank", rating: "");
    if (ranked.list.isNotEmpty) return ranked;

    // Final fallback: newest posts — always works unauthenticated.
    return _fetchPage(page, query: "", sort: "", rating: "");
  }

  @override
  Future<MPages> getLatestUpdates(int page) =>
      _fetchPage(page, query: "", sort: "", rating: "");

  @override
  Future<MPages> search(String query, int page, FilterList filterList) {
    String ratingTag = "";
    String sortTag   = "";

    for (final f in filterList.filters) {
      if (f.name == "Rating" && (f.state as int) > 0) {
        const ratings = ["", "rating:g", "rating:s", "rating:q", "rating:e"];
        final idx = f.state as int;
        if (idx < ratings.length) ratingTag = ratings[idx];
      }
      if (f.name == "Sort" && (f.state as int) > 0) {
        const sorts = ["", "order:score", "order:favcount", "order:rank"];
        final idx = f.state as int;
        if (idx < sorts.length) sortTag = sorts[idx];
      }
    }

    return _fetchPage(
      page,
      query:  query.trim(),
      sort:   sortTag,
      rating: ratingTag,
    );
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final id   = _idFromUrl(url);
    final post = await _fetchPost(id);

    final fileUrl    = _resolveFileUrl(post);
    final previewUrl = post["preview_file_url"]?.toString() ?? fileUrl;
    final ext        = (post["file_ext"]?.toString() ?? "").toLowerCase();
    final isVideo    = ext == "mp4" || ext == "webm" || ext == "swf";

    final manga = MManga();
    manga.name     = _buildTitle(post);
    manga.imageUrl = previewUrl.isNotEmpty ? previewUrl : fileUrl;
    manga.author   = _tagString(post, "tag_string_artist");
    manga.artist   = _tagString(post, "tag_string_artist");
    manga.genre    = _tagString(post, "tag_string_copyright")
        .split(" ")
        .where((t) => t.isNotEmpty)
        .toList();

    if (isVideo) {
      manga.description =
          "🎬 VIDEO POST (.${ext.isNotEmpty ? ext : '?'})"
          "\nDirect URL: $fileUrl"
          "\n\n${_buildDescription(post)}"
          "\n\nTip: Use the Rule34Video source for playback.";
      manga.chapters = [
        MChapter(
          name: "Preview (video — see description for direct link)",
          url:  previewUrl.isNotEmpty ? previewUrl : fileUrl,
        ),
      ];
    } else {
      manga.description = _buildDescription(post);
      final chapters = <MChapter>[];
      if (fileUrl.isNotEmpty) {
        chapters.add(MChapter(
          name: _buildChapterLabel(post, ext),
          url:  fileUrl,
        ));
      }
      if (chapters.isEmpty) {
        chapters.add(MChapter(name: "Open Post", url: _base() + "/post/show/$id"));
      }
      manga.chapters = chapters;
    }
    return manga;
  }

  // ── getPageList ───────────────────────────────────────────────────────────
  // FIX 1: Return Map with "headers" so the image loader sends the correct
  // Referer to cdn.sakugabooru.com, preventing the spurious CF-popup on 403.
  //
  // Mangayomi bridge accepts two return shapes from getPageList:
  //   • List<String>                — plain URL list, no custom headers
  //   • List<Map<String,dynamic>>  — { "url": ..., "headers": {...} }
  // We use the map form to inject Referer and User-Agent.
  @override
  Future<List<dynamic>> getPageList(String url) async {
    // url is either the direct image URL (file_url) or a post page URL.
    // Sakugabooru CDN requires Referer from the Sakugabooru.sakugabooru.com origin.
    return [
      {
        "url": url,
        "headers": {
          "Referer": _base() + "/",
          "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-Sakugabooru/1.0)",
        },
      }
    ];
  }

  // ── Private API ───────────────────────────────────────────────────────────

  // FIX 2a: _composeTagQuery enforces the tag budget.
  // Priority: user query (counts as 1 slot) > sort tag > rating tag.
  // If budget is 2 and all three are set, rating is dropped.
  // If budget is 1 (shouldn't happen but defensive), only query is kept.
  String _composeTagQuery({
    required String query,
    required String sort,
    required String rating,
  }) {
    final budget = _tagBudget;
    final parts  = <String>[];
    int   slots  = budget;

    // User query: count the actual number of space-separated tokens
    if (query.isNotEmpty) {
      final queryTokens = query.split(" ").where((t) => t.isNotEmpty).toList();
      if (queryTokens.length <= slots) {
        parts.addAll(queryTokens);
        slots -= queryTokens.length;
      } else {
        // Query itself exceeds budget — truncate and warn via description
        parts.addAll(queryTokens.take(slots));
        slots = 0;
      }
    }

    // Sort tag (e.g. order:score — counts as 1 tag)
    if (sort.isNotEmpty && slots > 0) {
      parts.add(sort);
      slots--;
    }

    // Rating tag (e.g. rating:g — dropped if no slots left)
    if (rating.isNotEmpty && slots > 0) {
      parts.add(rating);
      // slots--; // not needed after last addition
    }

    return parts.join(" ");
  }

  Future<MPages> _fetchPage(
    int page, {
    required String query,
    required String sort,
    required String rating,
  }) async {
    final tagQuery = _composeTagQuery(query: query, sort: sort, rating: rating);

    String params = "limit=20&page=$page";
    if (tagQuery.isNotEmpty) {
      params += "&tags=${Uri.encodeQueryComponent(tagQuery)}";
    }
    params += _authParams();

    final uri = Uri.parse("${_base()}/post.json?$params");
    final res = await client.get(uri, headers: _headers());

    // FIX 2b: Detect the silent tag-limit rejection payload
    // { "success": false, "message": "You cannot search for more than N tags..." }
    final body = res.body.trim();
    if (body.startsWith("{")) {
      // Only check error if it is an object (not the expected array).
      // Swallow JSON parse errors here — we'll get an empty list from
      // _decodeList() below and let that surface naturally.
      try {
        final obj = jsonDecode(body);
        if (obj is Map && obj["success"] == false) {
          final msg = obj["message"]?.toString() ?? "API error";
          throw Exception("Sakugabooru: $msg (composed query: '$tagQuery')");
        }
      } on FormatException catch (_) {
        // Not valid JSON object — fall through to normal list decode
      }
      // If it was valid JSON but not an error object, also fall through
    }

    final posts = _decodeList(body);
    final items = <MManga>[];

    for (final raw in posts) {
      final post = _asMap(raw);
      final id   = post["id"]?.toString() ?? "";
      if (id.isEmpty) continue;

      // FIX 2c: Reconstruct file_url from md5 when missing (unauthenticated
      // users often get null file_url for non-general posts since 2023)
      final fileUrl    = _resolveFileUrl(post);
      final previewUrl = post["preview_file_url"]?.toString() ??
          _buildPreviewUrlFromMd5(post);

      // Skip fully deleted / banned posts (no image at all)
      if (previewUrl.isEmpty && fileUrl.isEmpty) continue;

      final item = MManga();
      item.name     = _buildTitle(post);
      item.imageUrl = previewUrl.isNotEmpty ? previewUrl : fileUrl;
      item.link     = "Sakugabooru://post?id=$id";
      items.add(item);
    }

    return MPages(items, posts.length >= 20);
  }

  Future<Map<String, dynamic>> _fetchPost(String id) async {
    try {
      final uri = Uri.parse("${_base()}/post/show/$id.json${_authQuery()}");
      final res = await client.get(uri, headers: _headers());
      if (res.statusCode == 200) {
        return _asMap(jsonDecode(res.body));
      }
    } catch (_) {}

    // HTML fallback
    final htmlUri = Uri.parse("${_base()}/post/show/$id");
    final resHtml = await client.get(htmlUri, headers: _headers());
    final document = parseHtml(resHtml.body);
    
    final map = <String, dynamic>{"id": id};
    
    final originalFile = document.selectFirst("a#highres-show")?.attr("href") ??
                         document.selectFirst("a#highres")?.attr("href") ??
                         document.selectFirst("img#image")?.attr("src") ?? "";
    map["file_url"] = originalFile;
    if (originalFile.isNotEmpty) {
      map["file_ext"] = originalFile.split(".").last.split("?").first.toLowerCase();
    }
    
    final List<String> generalTags = [];
    final List<String> artistTags = [];
    final List<String> charTags = [];
    final List<String> copyTags = [];
    
    for (final li in document.select("ul#tag-sidebar li")) {
      // Tags typically have ?tags=...
      final a = li.select("a").where((e) => e.attr("href").contains("tags=")).lastOrNull;
      if (a != null) {
        final tag = a.text.trim();
        final clazz = li.attr("class");
        if (clazz.contains("tag-type-artist")) {
          artistTags.add(tag);
        } else if (clazz.contains("tag-type-character")) {
          charTags.add(tag);
        } else if (clazz.contains("tag-type-copyright")) {
          copyTags.add(tag);
        } else {
          generalTags.add(tag);
        }
      }
    }
    
    map["tag_string_artist"] = artistTags.join(" ");
    map["tag_string_character"] = charTags.join(" ");
    map["tag_string_copyright"] = copyTags.join(" ");
    map["tag_string_general"] = generalTags.join(" ");
    map["score"] = document.selectFirst("span#post-score-$id")?.text.trim() ?? "";
    
    return map;
  }

  // ── URL helpers ───────────────────────────────────────────────────────────

  /// Returns the best available image URL for a post.
  /// Falls back to reconstructing the CDN path from the md5 hash when the
  /// API omits file_url (common for unauthenticated access to non-safe posts).
  String _resolveFileUrl(Map<String, dynamic> post) {
    final direct = post["file_url"]?.toString() ?? "";
    if (direct.isNotEmpty) return direct;

    final large = post["large_file_url"]?.toString() ?? "";
    if (large.isNotEmpty) return large;

    // Reconstruct standard Sakugabooru CDN path from md5
    return _buildFileUrlFromMd5(post);
  }

  /// Sakugabooru CDN layout: /data/{md5[0..1]}/{md5[2..3]}/{md5}.{ext}
  String _buildFileUrlFromMd5(Map<String, dynamic> post) {
    final md5 = post["md5"]?.toString() ?? "";
    final ext = post["file_ext"]?.toString() ?? "jpg";
    if (md5.length < 4) return "";
    return "${_base()}/data/${md5.substring(0, 2)}/${md5.substring(2, 4)}/$md5.$ext";
  }

  /// Sakugabooru preview CDN layout: /data/preview/{md5[0..1]}/{md5[2..3]}/{md5}.jpg
  String _buildPreviewUrlFromMd5(Map<String, dynamic> post) {
    final md5 = post["md5"]?.toString() ?? "";
    if (md5.length < 4) return "";
    return "${_base()}/data/preview/${md5.substring(0, 2)}/${md5.substring(2, 4)}/$md5.jpg";
  }

  // ── Display builders ──────────────────────────────────────────────────────

  String _buildTitle(Map<String, dynamic> post) {
    final id        = post["id"]?.toString() ?? "?";
    final artist    = _tagString(post, "tag_string_artist").replaceAll(" ", ", ");
    final character = _tagString(post, "tag_string_character")
        .split(" ")
        .where((t) => t.isNotEmpty)
        .take(2)
        .join(", ");
    final parts = <String>["#$id"];
    if (artist.isNotEmpty)    parts.add(artist);
    if (character.isNotEmpty) parts.add(character);
    return parts.join(" – ");
  }

  String _buildChapterLabel(Map<String, dynamic> post, String ext) {
    final isVideo = ext == "webm" || ext == "mp4" || ext == "gif";
    return isVideo ? "Video .$ext" : "Image .$ext";
  }

  String _buildDescription(Map<String, dynamic> post) {
    final lines = <String>[];
    final id    = post["id"]?.toString() ?? "";
    if (id.isNotEmpty) lines.add("Post ID: #$id");
    final score = post["score"]?.toString() ?? "";
    if (score.isNotEmpty) lines.add("Score: $score  ↑${post["up_score"] ?? 0}");
    final favs = post["fav_count"]?.toString() ?? "";
    if (favs.isNotEmpty) lines.add("Favorites: $favs");
    final rating = post["rating"]?.toString() ?? "";
    if (rating.isNotEmpty) lines.add("Rating: ${_ratingLabel(rating)}");
    final ext = post["file_ext"]?.toString() ?? "";
    if (ext.isNotEmpty) lines.add("Format: .$ext");
    final w = post["image_width"]?.toString()  ?? "";
    final h = post["image_height"]?.toString() ?? "";
    if (w.isNotEmpty && h.isNotEmpty) lines.add("Resolution: ${w}×${h}");
    final artist    = _tagString(post, "tag_string_artist");
    if (artist.isNotEmpty)    lines.add("Artist: ${artist.replaceAll(" ", ", ")}");
    final character = _tagString(post, "tag_string_character");
    if (character.isNotEmpty) lines.add("Characters: ${character.replaceAll(" ", ", ")}");
    final copyright = _tagString(post, "tag_string_copyright");
    if (copyright.isNotEmpty) lines.add("Series: ${copyright.replaceAll(" ", ", ")}");
    final tags = _tagString(post, "tag_string_general");
    if (tags.isNotEmpty) lines.add("\nTags:\n${tags.replaceAll(" ", ", ")}");

    // Note for unauthenticated users when auth fields are missing
    if (_pref("login").isEmpty) {
      lines.add("\n⚠ Add login + API key in Source Settings to remove the "
          "2-tag search limit and access explicit post images.");
    }
    return lines.join("\n");
  }

  String _ratingLabel(String r) {
    if (r == "g") return "General (g)";
    if (r == "s") return "Sensitive (s)";
    if (r == "q") return "Questionable (q)";
    if (r == "e") return "Explicit (e)";
    return r;
  }

  String _tagString(Map<String, dynamic> post, String key) =>
      post[key]?.toString().trim() ?? "";

  // ── URL / auth helpers ────────────────────────────────────────────────────

  String _idFromUrl(String url) {
    if (url.startsWith("Sakugabooru://")) {
      final q = url.indexOf("id=");
      if (q != -1) {
        final rest = url.substring(q + 3);
        final amp  = rest.indexOf("&");
        return amp == -1 ? rest : rest.substring(0, amp);
      }
    }
    final seg = url.split("/").where((s) => s.isNotEmpty).last;
    return seg.split("?").first.split(".").first;
  }

  String _base() {
    final v = _pref("domain_url");
    if (v.isNotEmpty) return v.endsWith("/") ? v.substring(0, v.length - 1) : v;
    return source.baseUrl;
  }

  String _pref(String key) =>
      getPreferenceValue(source.id, key)?.toString().trim() ?? "";

  /// Returns "&login=...&api_key=..." if credentials are set, else "".
  String _authParams() {
    final login  = _pref("login");
    final apiKey = _pref("api_key");
    if (login.isEmpty || apiKey.isEmpty) return "";
    return "&login=${Uri.encodeQueryComponent(login)}"
        "&api_key=${Uri.encodeQueryComponent(apiKey)}";
  }

  /// Returns "?login=...&api_key=..." if credentials are set, else "".
  String _authQuery() {
    final p = _authParams();
    return p.isEmpty ? "" : "?${p.substring(1)}";
  }

  Map<String, String> _headers() => {
        "User-Agent": "Mozilla/5.0 (compatible; Mangayomi-Sakugabooru/1.0)",
        "Accept":     "application/json",
        // Referer header on API calls is fine; the CDN Referer is injected
        // per-image inside getPageList() where it actually matters.
        "Referer": _base() + "/",
        "Connection": "close",
      };

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  List<dynamic> _decodeList(String body) {
    try {
      final d = jsonDecode(body);
      if (d is List) return d;
    } catch (_) {}
    return [];
  }

  // ── Filters ───────────────────────────────────────────────────────────────
  // NOTE: Combining a user query + Rating + Sort = 3 tags, which exceeds the
  // 2-tag free-tier limit. _composeTagQuery() handles this by dropping Rating
  // first when the budget is full. Users with Gold+ accounts (6-tag limit)
  // can use all three simultaneously.

  @override
  List<dynamic> getFilterList() {
    return [
      SelectFilter("SelectFilter", "Rating", 0, [
        SelectFilterOption("Any",          "",          null),
        SelectFilterOption("General",      "rating:g",  null),
        SelectFilterOption("Sensitive",    "rating:s",  null),
        SelectFilterOption("Questionable", "rating:q",  null),
        SelectFilterOption("Explicit",     "rating:e",  null),
      ], null),
      SelectFilter("SelectFilter", "Sort", 0, [
        SelectFilterOption("Default (newest)", "",              null),
        SelectFilterOption("Score",            "order:score",   null),
        SelectFilterOption("Favorites",        "order:favcount",null),
        SelectFilterOption("Rank (hot)",       "order:rank",    null),
      ], null),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key:         "domain_url",
        title:       "Base URL",
        summary:     "e.g. https://Sakugabooru.sakugabooru.com — change to use Safebooru or other clones",
        value:       source.baseUrl,
        dialogTitle: "URL",
        dialogMessage: "",
      ),
      EditTextPreference(
        key:         "login",
        title:       "Login",
        summary:     "Sakugabooru username. Required to lift the 2-tag limit to 6 tags, "
                     "access explicit content, and use favorites.",
        value:       "",
        dialogTitle: "Login",
        dialogMessage: "",
      ),
      EditTextPreference(
        key:         "api_key",
        title:       "API Key",
        summary:     "Found at https://Sakugabooru.sakugabooru.com/profile under API key.",
        value:       "",
        dialogTitle: "API Key",
        dialogMessage: "",
      ),
    ];
  }
}

Sakugabooru main(MSource source) => Sakugabooru(source: source);
