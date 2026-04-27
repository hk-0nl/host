import 'dart:convert';

import 'package:mangayomi/bridge_lib.dart';

class HentaiHaven extends MProvider {
  HentaiHaven({required this.source});

  final MSource source;
  final Client client = Client();
  String? cachedWardenToken;

  @override
  Future<MPages> getPopular(int page) async {
    if (page == 1) {
      final payload = await fetchHomePayload();
      final pages = parseHomeSection(payload, getPreferredHomeSection());
      if (pages.list.isNotEmpty) {
        return pages;
      }
    }
    return fetchAllHentaiPage(page);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    if (page == 1) {
      final payload = await fetchHomePayload();
      final pages = parseLatestEpisodes(payload);
      if (pages.list.isNotEmpty) {
        return pages;
      }
    }
    return fetchAllHentaiPage(page);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    if (query.trim().isEmpty) {
      return fetchAllHentaiPage(page);
    }

    final payload = await apiGet(
      "search",
      queryParameters: {"q": query.trim()},
    );
    return parseSearchResults(payload);
  }

  @override
  Future<MManga> getDetail(String url) async {
    var hentaiId = extractQueryParameter(url, "hid");
    if (hentaiId.isEmpty) {
      hentaiId = await resolveHentaiId(url);
    }

    if (hentaiId.isEmpty) {
      final fallback = MManga();
      fallback.name = titleFromUrl(url);
      fallback.chapters = [MChapter(name: "Open Page", url: normalizeUrl(url))];
      return fallback;
    }

    final payload = await apiGet("hentai/$hentaiId");
    final data = asMap(payload["data"]);
    final anime = MManga();

    // API now returns post_title / post_name / post_thumbnail instead of title/name/thumbnail
    anime.name =
        data["post_title"]?.toString() ??
        data["title"]?.toString() ??
        data["post_name"]?.toString() ??
        titleFromUrl(url);
    anime.imageUrl =
        data["post_thumbnail"]?.toString() ??
        data["thumbnail"]?.toString() ??
        "";
    anime.description = buildDescription(data);
    final chapters = <MChapter>[];
    final hentaiNameForEpisode = data["post_name"]?.toString() ?? data["name"]?.toString() ?? "";
    final episodes = asList(data["post_episodes"]);

    for (final entry in episodes) {
      final episode = asMap(entry);
      final episodeId =
          episode["chapter_id"]?.toString() ??
          episode["id"]?.toString() ??
          "";
      final episodeName =
          episode["chapter_name"]?.toString() ??
          episode["name"]?.toString() ??
          "";
      final episodeSlug =
          episode["chapter_slug"]?.toString() ??
          episode["slug"]?.toString() ??
          "";
      final contentHtml =
          episode["chapter_content"]?.toString() ??
          episode["content"]?.toString() ??
          "";
      final streamUrl = extractIframeSrc(contentHtml);

      // dateUpload MUST be milliseconds-since-epoch as a string.
      // Mangayomi calls int.parse(dateUpload) directly — a raw date string
      // (e.g. "2024-03-15 10:00:00") crashes the tile renderer causing the
      // "gray box" where all episode buttons are invisible.
      final rawDate =
          episode["chapter_date"]?.toString() ??
          episode["date"]?.toString() ??
          "";
      final episodeDate = _toMillisString(rawDate);

      if (episodeName.isEmpty) {
        continue;
      }

      final pageUrl = buildEpisodeUrl(
        hentaiNameForEpisode,
        episodeSlug,
        hentaiId,
        episodeId,
      );
      final chapterUrl = streamUrl.isNotEmpty
          ? "$pageUrl&stream=${Uri.encodeComponent(streamUrl)}"
          : pageUrl;

      chapters.add(
        MChapter(
          name: episodeName,
          url: chapterUrl,
          dateUpload: episodeDate,
        ),
      );
    }

    if (chapters.isEmpty) {
      chapters.add(MChapter(name: anime.name, url: normalizeUrl(url)));
    }
    anime.chapters = chapters;

    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    // Step 1 – Determine page URL and pre-embedded stream (from chapter URL).
    final embeddedStream = extractQueryParameter(url, "stream");
    // Safely strip the &stream= suffix if present; indexOf can return -1 if
    // the chapter URL has no embedded stream param (e.g. fallback page URL).
    final streamParamIdx = url.indexOf("&stream");
    final cleanUrl = streamParamIdx != -1
        ? url.substring(0, streamParamIdx)
        : (url.contains("?") ? url : url);
    final pageUrl = normalizeUrl(cleanUrl);
    final baseOrigin = getBaseUrl();

    // Step 2 – Load the main episode page to harvest session cookies.
    // The site sets a session cookie on the first page load that is required
    // to authorise both the iframe and the CDN segment requests.
    String sessionCookies = "";
    try {
      final pageRes = await client.get(
        Uri.parse(pageUrl),
        headers: {
          "User-Agent": getUserAgent(),
          "Accept": "text/html,application/xhtml+xml,*/*",
          "Accept-Language": "en-US,en;q=0.9",
          "Connection": "close",
        },
      );
      sessionCookies = _extractCookies(pageRes.headers);
    } catch (_) {}

    // Resolve the iframe URL: prefer the one baked into the chapter URL,
    // otherwise fall back to the already-cached stream param.
    String streamUrl = embeddedStream.isNotEmpty
        ? Uri.decodeComponent(embeddedStream)
        : "";

    // If we do not already have a stream URL, try re-scraping the page body.
    // (Handles cases where getDetail ran before the API returned chapter_content.)
    if (streamUrl.isEmpty) {
      try {
        final pageRes2 = await client.get(
          Uri.parse(pageUrl),
          headers: {
            "User-Agent": getUserAgent(),
            "Cookie": sessionCookies,
            "Referer": baseOrigin,
            "Connection": "close",
          },
        );
        streamUrl = _extractUrlWithExtension(pageRes2.body, ".m3u8");
        if (streamUrl.isEmpty) {
          streamUrl = extractIframeSrc(pageRes2.body);
        }
      } catch (_) {}
    }

    if (streamUrl.isEmpty) {
      return [
        MVideo()
          ..url = pageUrl
          ..originalUrl = pageUrl
          ..quality = "page",
      ];
    }

    // If the stream URL is already a direct media file, wrap it with session
    // headers so the native player can pass them when fetching segments.
    final isDirect =
        streamUrl.endsWith(".m3u8") || streamUrl.endsWith(".mp4");
    if (isDirect) {
      final headers = _buildPlayerHeaders(
        referer: baseOrigin,
        origin: baseOrigin,
        cookies: sessionCookies,
      );
      return [
        MVideo()
          ..url = streamUrl
          ..originalUrl = streamUrl
          ..quality = streamUrl.endsWith(".mp4") ? "MP4" : "HLS"
          ..headers = headers,
      ];
    }

    // Step 3 – The stream URL is a player iframe.  Load it with the session
    // cookies + correct Referer so the player subdomain sets its own cookies
    // and returns the real signed playlist URL.
    final iframeOrigin = _extractOrigin(streamUrl);
    String iframeCookies = sessionCookies;
    String iframeBody = "";
    try {
      final iframeRes = await client.get(
        Uri.parse(streamUrl),
        headers: {
          "User-Agent": getUserAgent(),
          "Referer": baseOrigin,
          "Origin": baseOrigin,
          "Cookie": sessionCookies,
          "Accept": "text/html,application/xhtml+xml,*/*",
          "Connection": "close",
        },
      );
      // Merge any new cookies the player subdomain sets (warden binding).
      final iframeSetCookies = _extractCookies(iframeRes.headers);
      if (iframeSetCookies.isNotEmpty) {
        iframeCookies = _mergeCookies(sessionCookies, iframeSetCookies);
      }
      iframeBody = iframeRes.body;
    } catch (_) {}

    // Build the player headers we will use for the resolved stream.
    final playerHeaders = _buildPlayerHeaders(
      referer: streamUrl,
      origin: iframeOrigin,
      cookies: iframeCookies,
    );

    // Initial check: if the iframe HTML naturally contained it.
    String m3u8 = _extractUrlWithExtension(iframeBody, ".m3u8");
    String mp4 = _extractUrlWithExtension(iframeBody, ".mp4");

    // If obfuscated (like player.hentaihaven.app uses AES + HLS.js), 
    // run the URL through Mangayomi's headless webview. The webview will 
    // automatically handle Cloudflare and execute the heavy JS decryption.
    if (m3u8.isEmpty && mp4.isEmpty) {
      try {
        // Inject a script that:
        //   1) Pokes the video element to trigger playback → CDN request
        //   2) After 2.5s scans performance.getEntriesByType("resource") for
        //      the decrypted .m3u8 / .mp4 URL, then returns it via setResponse.
        //   3) Falls back to returning full page HTML so _extractUrlWithExtension
        //      can scan it as a last resort.
        final script = """
          setTimeout(function() {
              var v = document.querySelector('video');
              if (v) { try { v.play(); } catch(e) {} }
              setTimeout(function() {
                  var found = '';
                  var resources = window.performance.getEntriesByType('resource');
                  for (var i = 0; i < resources.length; i++) {
                      var u = resources[i].name;
                      if (u.indexOf('.m3u8') !== -1 || u.indexOf('.mp4') !== -1) {
                          found = u; break;
                      }
                  }
                  window.flutter_inappwebview.callHandler('setResponse',
                      found !== '' ? found : document.documentElement.outerHTML);
              }, 2500);
          }, 1500);
        """;
        // Bridge signature: evaluateJavascriptViaWebview(url, script)
        iframeBody = await evaluateJavascriptViaWebview(streamUrl, script) ?? "";
        m3u8 = _extractUrlWithExtension(iframeBody, ".m3u8");
        mp4  = _extractUrlWithExtension(iframeBody, ".mp4");
      } catch (_) {}
    }

    if (m3u8.isNotEmpty) {
      return [
        MVideo()
          ..url = m3u8
          ..originalUrl = m3u8
          ..quality = "HLS"
          ..headers = playerHeaders,
      ];
    }

    if (mp4.isNotEmpty) {
      return [
        MVideo()
          ..url = mp4
          ..originalUrl = mp4
          ..quality = "MP4"
          ..headers = playerHeaders,
      ];
    }

    // Fallback – return the iframe URL itself with session headers so the
    // native webview at least has the cookies it needs.
    return [
      MVideo()
        ..url = streamUrl
        ..originalUrl = streamUrl
        ..quality = "iframe"
        ..headers = playerHeaders,
    ];
  }

  // ---------------------------------------------------------------------------
  // Session / cookie helpers
  // ---------------------------------------------------------------------------

  /// Extract all Set-Cookie values from response headers and concatenate them
  /// into a single Cookie request header string.  Works with both
  /// comma-separated (multi-value) and bracket-list representations that the
  /// bridge Response.headers may return.
  String _extractCookies(Map<String, String> headers) {
    final parts = <String>[];
    // The bridge may return headers with lower-cased keys.
    for (final key in ["set-cookie", "Set-Cookie"]) {
      final raw = headers[key];
      if (raw == null || raw.isEmpty) continue;
      // Each Set-Cookie directive is semi-delimited; we only want name=value.
      for (final directive in raw.split(",")) {
        final nameValue = directive.trim().split(";").first.trim();
        if (nameValue.contains("=")) {
          parts.add(nameValue);
        }
      }
    }
    return parts.join("; ");
  }

  /// Merge a new set of cookies into an existing cookie string, overwriting
  /// any duplicate names.
  String _mergeCookies(String existing, String incoming) {
    final map = <String, String>{};
    for (final part in existing.split(";")) {
      final kv = part.trim();
      if (kv.contains("=")) {
        final idx = kv.indexOf("=");
        map[kv.substring(0, idx).trim()] = kv.substring(idx + 1).trim();
      }
    }
    for (final part in incoming.split(";")) {
      final kv = part.trim();
      if (kv.contains("=")) {
        final idx = kv.indexOf("=");
        map[kv.substring(0, idx).trim()] = kv.substring(idx + 1).trim();
      }
    }
    return map.entries.map((e) => "${e.key}=${e.value}").join("; ");
  }

  /// Build the headers map passed to MVideo so the native player sends them
  /// with every HLS playlist and segment request.
  Map<String, String> _buildPlayerHeaders({
    required String referer,
    required String origin,
    required String cookies,
  }) {
    final m = <String, String>{
      "Referer": referer,
      "Origin": origin,
      "User-Agent": getUserAgent(),
    };
    if (cookies.isNotEmpty) {
      m["Cookie"] = cookies;
    }
    return m;
  }

  /// Extract the scheme+host origin from a URL string.
  String _extractOrigin(String url) {
    try {
      final uri = Uri.parse(url);
      return "${uri.scheme}://${uri.host}";
    } catch (_) {
      return url;
    }
  }


  Future<MPages> fetchAllHentaiPage(int page) async {
    final payload = await apiGet(
      "hentai/all",
      queryParameters: {"p": page.toString()},
    );
    final data = asMap(payload["data"]);
    final entries = asList(data["hentais"]);
    final items = <MManga>[];

    for (final entry in entries) {
      final anime = mangaFromPartial(asMap(entry));
      if (anime != null) {
        items.add(anime);
      }
    }

    final currentPage = intFromValue(data["current_page"]) ?? page;
    final totalPages = intFromValue(data["total_pages"]) ?? currentPage;
    return MPages(items, currentPage < totalPages);
  }

  Future<Map<String, dynamic>> fetchHomePayload() {
    return apiGet("hentai/home");
  }

  Future<Map<String, dynamic>> apiGet(
    String path, {
    Map<String, String>? queryParameters,
    bool allowRetry = true,
  }) async {
    final token = await ensureWardenToken(forceRefresh: false);
    final uri = Uri.parse(
      buildUrlWithQuery("${getApiBaseUrl()}/$path", queryParameters),
    );
    final res = await client.get(uri, headers: buildApiHeaders(token));
    final payload = decodeMap(res.body);

    if (allowRetry && payloadIndicatesInvalidToken(payload)) {
      cachedWardenToken = null;
      final refreshedToken = await ensureWardenToken(forceRefresh: true);
      final retryRes = await client.get(
        uri,
        headers: buildApiHeaders(refreshedToken),
      );
      return decodeMap(retryRes.body);
    }

    return payload;
  }

  Future<String> ensureWardenToken({required bool forceRefresh}) async {
    final manualToken = getPreferenceValue(
      source.id,
      "warden_token",
    )?.toString().trim();
    if (!forceRefresh && manualToken != null && manualToken.isNotEmpty) {
      return manualToken;
    }

    if (!forceRefresh &&
        cachedWardenToken != null &&
        cachedWardenToken!.isNotEmpty) {
      return cachedWardenToken!;
    }

    final headers = {
      "content-type": "application/x-www-form-urlencoded; charset=utf-8",
      "user-agent": getUserAgent(),
      "warden": "",
      "Connection": "close",
    };
    final res = await client.post(
      Uri.parse("${getApiBaseUrl()}/warden"),
      headers: headers,
      body: encodeForm(buildWardenBody()),
    );
    final payload = decodeMap(res.body);
    final token = asMap(payload["data"])["token"]?.toString() ?? "";
    cachedWardenToken = token;
    return token;
  }

  MPages parseHomeSection(Map<String, dynamic> payload, String sectionKey) {
    final data = asMap(payload["data"]);
    final entries = asList(data[sectionKey]);
    final items = <MManga>[];

    for (final entry in entries) {
      final anime = mangaFromPartial(asMap(entry));
      if (anime != null) {
        items.add(anime);
      }
    }

    return MPages(items, true);
  }

  MPages parseLatestEpisodes(Map<String, dynamic> payload) {
    final data = asMap(payload["data"]);
    final entries = asList(data["last_episodes"]);
    final seen = <String>[];
    final items = <MManga>[];

    for (final entry in entries) {
      final episode = asMap(entry);
      final hentaiId = episode["hentai_id"]?.toString() ?? "";
      if (hentaiId.isEmpty || seen.contains(hentaiId)) {
        continue;
      }

      final hentaiName = episode["hentai_name"]?.toString() ?? "";
      final hentaiTitle =
          episode["hentai_title"]?.toString() ??
          episode["hentai_name"]?.toString() ??
          "";
      if (hentaiTitle.isEmpty) {
        continue;
      }

      seen.add(hentaiId);
      items.add(
        MManga()
          ..name = hentaiTitle
          ..link = buildHentaiUrl(hentaiName, hentaiId)
          ..imageUrl = episode["hentai_thumbnail"]?.toString() ?? "",
      );
    }

    return MPages(items, true);
  }

  MPages parseSearchResults(Map<String, dynamic> payload) {
    final entries = asList(payload["data"]);
    final items = <MManga>[];

    for (final entry in entries) {
      final anime = mangaFromPartial(asMap(entry));
      if (anime != null) {
        items.add(anime);
      }
    }

    return MPages(items, false);
  }

  MManga? mangaFromPartial(Map<String, dynamic> item) {
    final id = item["id"]?.toString() ?? item["post_ID"]?.toString() ?? "";
    final name = item["name"]?.toString() ?? item["post_name"]?.toString() ?? "";
    final title = item["title"]?.toString() ?? item["post_title"]?.toString() ?? "";
    if (id.isEmpty || title.isEmpty) {
      return null;
    }

    return MManga()
      ..name = title
      ..link = buildHentaiUrl(name, id)
      ..imageUrl = item["thumbnail"]?.toString() ?? item["post_thumbnail"]?.toString() ?? "";
  }

  List<MChapter> buildEpisodeChapters(
    String hentaiId,
    String hentaiName,
    List<dynamic> entries,
  ) {
    final chapters = <MChapter>[];

    for (final entry in entries) {
      final episode = asMap(entry);
      // New API: chapter_id, chapter_name, chapter_content (m3u8), chapter_date
      final episodeId =
          episode["chapter_id"]?.toString() ??
          episode["id"]?.toString() ??
          "";
      final episodeName =
          episode["chapter_name"]?.toString() ??
          episode["name"]?.toString() ??
          "";
      final episodeSlug =
          episode["chapter_slug"]?.toString() ??
          episode["slug"]?.toString() ??
          "";
      // Embed stream URL directly so getVideoList needs no extra API call
      final contentHtml =
          episode["chapter_content"]?.toString() ??
          episode["content"]?.toString() ??
          "";
      final streamUrl = extractIframeSrc(contentHtml);

      final rawDate =
          episode["chapter_date"]?.toString() ??
          episode["date"]?.toString() ??
          "";
      final episodeDate = _toMillisString(rawDate);

      if (episodeName.isEmpty) {
        continue;
      }

      final pageUrl = buildEpisodeUrl(
        hentaiName,
        episodeSlug,
        hentaiId,
        episodeId,
      );
      final chapterUrl = streamUrl.isNotEmpty
          ? "$pageUrl&stream=${Uri.encodeComponent(streamUrl)}"
          : pageUrl;

      chapters.add(
        MChapter(
          name: episodeName,
          url: chapterUrl,
          dateUpload: episodeDate,
        ),
      );
    }

    return chapters;
  }

  String buildDescription(Map<String, dynamic> data) {
    final parts = <String>[];
    // New API uses post_content; fall back to content for compatibility
    final description = stripHtml(
      data["post_content"]?.toString() ?? data["content"]?.toString() ?? "",
    );
    if (description.isNotEmpty) {
      parts.add(description);
    }

    final details = <String>[];
    addDetail(
      details,
      "Alternative Title",
      data["post_title_alternative"]?.toString() ??
          data["title_alternative"]?.toString(),
    );
    addDetail(
      details,
      "Views",
      data["post_views"]?.toString() ?? data["views"]?.toString(),
    );
    addDetail(
      details,
      "Date",
      data["post_date"]?.toString() ?? data["date"]?.toString(),
    );
    addDetail(
      details,
      "Rating",
      buildRatingLine(
        asMap(data["post_rating"] ?? data["rating"]),
      ),
    );
    addDetail(
      details,
      "Tags",
      joinNames(asList(data["post_tags"] ?? data["tags"])),
    );
    addDetail(
      details,
      "Genres",
      joinNames(asList(data["post_genres"] ?? data["genres"])),
    );
    addDetail(
      details,
      "Authors",
      joinNames(asList(data["post_authors"] ?? data["authors"])),
    );
    addDetail(
      details,
      "Releases",
      joinNames(asList(data["post_releases"] ?? data["releases"])),
    );

    if (details.isNotEmpty) {
      if (parts.isNotEmpty) {
        parts.add("");
      }
      parts.addAll(details);
    }

    return parts.join("\n").trim();
  }

  String buildRatingLine(Map<String, dynamic> rating) {
    final value = rating["rating"]?.toString() ?? "";
    final votes = rating["votes"]?.toString() ?? "";
    if (value.isEmpty) {
      return "";
    }
    return votes.isEmpty ? value : "$value ($votes votes)";
  }

  String joinNames(List<dynamic> entries) {
    return entries
        .map((entry) => asMap(entry)["name"]?.toString() ?? "")
        .where((name) => name.isNotEmpty)
        .join(", ");
  }

  void addDetail(List<String> lines, String label, String? value) {
    if (value == null || value.isEmpty || value == "null") {
      return;
    }
    lines.add("$label: $value");
  }

  /// Convert a raw API date string to milliseconds-since-epoch (as String).
  ///
  /// Mangayomi calls `int.parse(chapter.dateUpload!)` directly inside the
  /// chapter-tile renderer. If a non-numeric string reaches that call it throws
  /// a FormatException that silently crash-renders every episode tile as a
  /// blank gray cell — producing the "infinite gray box" on the episode list.
  ///
  /// Handles:
  ///   • already-numeric ms strings ("1712880000000")
  ///   • ISO-8601 / MySQL datetime ("2024-04-12T03:00:00Z", "2024-04-12 03:00:00")
  ///   • Null / empty (returns "" → dateUpload omitted in the UI)
  String _toMillisString(String raw) {
    if (raw.isEmpty) return "";
    // Already a unix-millis number?
    final asInt = int.tryParse(raw);
    if (asInt != null) return raw;
    // Try ISO-8601 / MySQL datetime.
    try {
      final dt = DateTime.parse(raw.trim().replaceFirst(" ", "T"));
      return dt.millisecondsSinceEpoch.toString();
    } catch (_) {}
    // Unrecognised format — omit so the tile still renders.
    return "";
  }

  Future<String> resolveHentaiId(String url) async {
    final slug = slugFromUrl(url);
    if (slug.isEmpty) {
      return "";
    }

    final payload = await apiGet("search", queryParameters: {"q": slug});
    for (final entry in asList(payload["data"])) {
      final item = asMap(entry);
      final candidateSlug = item["name"]?.toString() ?? "";
      if (candidateSlug == slug || item["title"]?.toString() == slug) {
        return item["id"]?.toString() ?? "";
      }
    }

    return "";
  }

  bool payloadIndicatesInvalidToken(Map<String, dynamic> payload) {
    final data = payload["data"]?.toString() ?? "";
    return data.startsWith("502") ||
        data.toLowerCase().contains("invalid token") ||
        data.toLowerCase().contains("forbidden");
  }

  Map<String, String> buildApiHeaders(String token) {
    return {
      "content-type": "application/x-www-form-urlencoded; charset=utf-8",
      "user-agent": getUserAgent(),
      "warden": token,
      "Connection": "close",
    };
  }

  Map<String, String> buildWardenBody() {
    return {
      "sdkInt": "33",
      "board": "goldfish_x86_64",
      "brand": "google",
      "display":
          "sdk_gphone_x86_64-userdebug 13 TE1A.220922.028 10190541 dev-keys",
      "fingerprint":
          "google/sdk_gphone_x86_64/emu64xa:13/TE1A.220922.028/10190541:userdebug/dev-keys",
      "manufacturer": "Google",
      "model": "sdk_gphone_x86_64",
    };
  }

  String encodeForm(Map<String, String> body) {
    return body.entries
        .map(
          (entry) =>
              "${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}",
        )
        .join("&");
  }

  Map<String, dynamic> decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return {};
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

  int? intFromValue(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? "");
  }

  String stripHtml(String html) {
    if (html.isEmpty) {
      return "";
    }
    return parseHtml("<body>$html</body>").selectFirst("body")?.text.trim() ?? "";
  }

  /// Extract the first HTTP(S) URL ending with [ext] found anywhere in [body].
  /// Scans backward from the extension marker to find the http(s):// prefix.
  String _extractUrlWithExtension(String body, String ext) {
    int idx = 0;
    while (true) {
      final extIdx = body.indexOf(ext, idx);
      if (extIdx == -1) break;
      // Walk back to find protocol prefix
      final httpIdx = body.lastIndexOf("http", extIdx);
      if (httpIdx == -1) {
        idx = extIdx + ext.length;
        continue;
      }
      // Slice candidate URL (ext + up to 10 extra chars for query params)
      final end = extIdx + ext.length;
      String candidate = body.substring(httpIdx, end);
      // Strip escaped slashes and common JSON noise
      candidate = candidate.replaceAll("\\/", "/");
      // Walk end to include optional query string chars but stop at quote/space/bracket
      int tailIdx = end;
      while (tailIdx < body.length) {
        final ch = body.substring(tailIdx, tailIdx + 1);
        if (ch == '"' || ch == "'" || ch == ' ' || ch == '\n' || ch == '\r' || ch == '>' || ch == ')') break;
        candidate += ch;
        tailIdx++;
      }
      // Sanity: must start with http and not be too short
      if (candidate.startsWith("http") && candidate.length > 10) {
        return candidate;
      }
      idx = extIdx + ext.length;
    }
    return "";
  }

  String extractIframeSrc(String html) {
    if (html.isEmpty) return "";

    // Find <iframe or <IFRAME occurrence
    final tagLower = html.toLowerCase();
    int iframeIdx = tagLower.indexOf("<iframe");
    if (iframeIdx == -1) return "";

    // Find src= after the <iframe tag
    int srcIdx = tagLower.indexOf(" src=", iframeIdx);
    if (srcIdx == -1) srcIdx = tagLower.indexOf("\tsrc=", iframeIdx);
    if (srcIdx == -1) return "";

    // Advance past " src=" or "\tsrc="
    // We know srcIdx points at the space/tab, so the quote is at srcIdx+5
    final attrStart = srcIdx + 5; // space + s + r + c + =
    if (attrStart >= html.length) return "";

    // Detect delimiter: double or single quote
    final delimChar = html.codeUnitAt(attrStart);
    // double-quote = 34, single-quote = 39
    if (delimChar != 34 && delimChar != 39) return "";

    final valueStart = attrStart + 1;
    final endIdx = html.indexOf(
      delimChar == 34 ? '"' : "'",
      valueStart,
    );
    if (endIdx == -1) return "";
    return html.substring(valueStart, endIdx);
  }

  String buildHentaiUrl(String name, String id) {
    final safeName = name.isEmpty ? id : name;
    return "${getBaseUrl()}/watch/$safeName?hid=$id";
  }

  String buildEpisodeUrl(
    String hentaiName,
    String episodeSlug,
    String hentaiId,
    String episodeId,
  ) {
    final parts = <String>[
      "${getBaseUrl()}/watch",
      hentaiName.isEmpty ? hentaiId : hentaiName,
    ];
    if (episodeSlug.isNotEmpty) {
      parts.add(episodeSlug);
    }
    return "${parts.join("/")}?hid=$hentaiId&eid=$episodeId";
  }

  String extractQueryParameter(String url, String key) {
    return extractQueryParam(normalizeUrl(url), key);
  }

  String slugFromUrl(String url) {
    final segments = Uri.parse(
      normalizeUrl(url),
    ).pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.isEmpty) {
      return "";
    }
    return segments.last;
  }

  String titleFromUrl(String url) {
    final slug = slugFromUrl(url);
    if (slug.isEmpty) {
      return url;
    }
    return slug.replaceAll("-", " ").trim();
  }

  String normalizeUrl(String url) {
    if (url.startsWith("http://") || url.startsWith("https://")) {
      return url;
    }
    return "${getBaseUrl()}${getUrlWithoutDomain(url)}";
  }

  String getPreferredHomeSection() {
    return getPreferenceValue(
          source.id,
          "home_section_page_one",
        )?.toString().trim() ??
        "trending_month";
  }

  String getUserAgent() {
    final userAgent = getPreferenceValue(
      source.id,
      "user_agent",
    )?.toString().trim();
    if (userAgent == null || userAgent.isEmpty) {
      return "HH_xxx_APP";
    }
    return userAgent;
  }

  String getApiBaseUrl() {
    final apiUrl = getPreferenceValue(source.id, "api_url")?.toString().trim();
    if (apiUrl == null || apiUrl.isEmpty) {
      return "https://api.hentaihaven.app/v1";
    }
    return apiUrl.endsWith("/")
        ? apiUrl.substring(0, apiUrl.length - 1)
        : apiUrl;
  }

  String extractQueryParam(String url, String key) {
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

  String getBaseUrl() {
    final baseUrl = getPreferenceValue(
      source.id,
      "domain_url",
    )?.toString().trim();
    if (baseUrl == null || baseUrl.isEmpty) {
      return source.baseUrl;
    }
    return baseUrl.endsWith("/")
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
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
      EditTextPreference(
        key: "api_url",
        title: "API URL",
        summary: "Direct API endpoint for HentaiHaven-compatible backends.",
        value: "https://api.hentaihaven.app/v1",
        dialogTitle: "API URL",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "warden_token",
        title: "Warden Token",
        summary:
            "Optional manual token. Leave empty to auto-fetch a token from the API.",
        value: "",
        dialogTitle: "Warden Token",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "user_agent",
        title: "User Agent",
        summary:
            "User-Agent header used for API requests and token generation.",
        value: "HH_xxx_APP",
        dialogTitle: "User Agent",
        dialogMessage: "",
      ),
      ListPreference(
        key: "home_section_page_one",
        title: "Popular Page 1 Section",
        summary: "",
        valueIndex: 0,
        entries: [
          "Trending Month",
          "Latest Hentai",
          "Yuri",
          "Ecchi",
          "Incest",
          "Tentacle",
          "Uncensored",
        ],
        entryValues: [
          "trending_month",
          "last",
          "yuri",
          "ecchi",
          "incest",
          "tentacle",
          "uncensored",
        ],
      ),
    ];
  }
}

HentaiHaven main(MSource source) {
  return HentaiHaven(source: source);
}
