import 'package:mangayomi/bridge_lib.dart';

class Rule34Video extends MProvider {
  Rule34Video({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Map<String, String> get headers => buildHeaders();

  @override
  Future<MPages> getPopular(int page) async {
    final html = await fetchRoute(
      buildPagedUrl(
        buildBrowsePath(browseMode: "home", query: "", orientation: "all"),
        page,
      ),
      "load home listing",
    );
    return parseListingPage(html, page);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final html = await fetchRoute(
      buildPagedUrl("/latest-updates/", page),
      "load latest updates",
    );
    return parseListingPage(html, page);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    var browseMode = "search";
    var orientation = "all";

    for (final filter in filterList.filters) {
      if (filter.name == "Browse Mode") {
        final index = filter.state as int;
        final values = ["search", "latest", "home", "category", "model"];
        if (index >= 0 && index < values.length) {
          browseMode = values[index];
        }
      }

      if (filter.name == "Orientation") {
        final index = filter.state as int;
        final values = ["all", "straight", "gay", "futa", "music", "iwara"];
        if (index >= 0 && index < values.length) {
          orientation = values[index];
        }
      }
    }

    final path = buildBrowsePath(
      browseMode: browseMode,
      query: query.trim(),
      orientation: orientation,
    );
    final html = await fetchRoute(
      buildPagedUrl(path, page),
      "load browse route",
    );
    return parseListingPage(html, page);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final normalized = normalizeUrl(url);
    final html = await fetchRoute(normalized, "load video detail");
    final document = parseHtml(html);

    final anime = MManga();
    anime.name =
        document.selectFirst("h1")?.text.trim() ??
        extractMetaContent(html, "og:title") ??
        titleFromUrl(normalized);
    anime.imageUrl =
        extractMetaContent(html, "og:image") ??
        extractPosterUrl(document) ??
        "";
    anime.description = buildDescription(html, normalized, document);
    anime.chapters = [MChapter(name: "Play", url: normalized)];
    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final normalized = normalizeUrl(url);
    final html = await fetchRoute(normalized, "load video streams");
    final scripts = _extractScriptBlocks(html);
    final videos = <MVideo>[];
    final refHeaders = <String, String>{
      "Referer": getBaseUrl() + "/",
      "User-Agent": defaultUserAgent,
    };

    // ── Strategy 1: KVS var video_url / video_low / video_mid ─────────────────
    // rule34video.com uses KVS (Kernel Video Sharing). The player page
    // injects named JS vars for each available quality tier.
    final kvsVars = <String, String>{
      "HD": _extractJsVarFromScripts(scripts, "video_url"),
      "SD": _extractJsVarFromScripts(scripts, "video_low"),
      "MD": _extractJsVarFromScripts(scripts, "video_mid"),
    };
    for (final entry in kvsVars.entries) {
      final src = _toAbsoluteUrl(entry.value);
      if (src.isEmpty) continue;
      if (!src.contains(".mp4") && !src.contains(".m3u8") && !src.contains(".webm")) continue;
      videos.add(
        MVideo()
          ..url = src
          ..originalUrl = src
          ..quality = entry.key
          ..headers = refHeaders,
      );
    }

    // ── Strategy 2: KVS flashvars / player_vars object { 'video_url': '...' } ─────
    if (videos.isEmpty) {
      final flashSrc = _toAbsoluteUrl(_extractFlashvarsUrl(scripts));
      if (flashSrc.isNotEmpty) {
        videos.add(
          MVideo()
            ..url = flashSrc
            ..originalUrl = flashSrc
            ..quality = _inferQualityFromUrl(flashSrc)
            ..headers = refHeaders,
        );
      }
    }

    // ── Strategy 3: JWPlayer / VideoJS  file: 'URL'  entries ──────────────────
    if (videos.isEmpty) {
      for (final src in _extractJwPlayerFiles(scripts)) {
        final abs = _toAbsoluteUrl(src);
        if (abs.isEmpty) continue;
        videos.add(
          MVideo()
            ..url = abs
            ..originalUrl = abs
            ..quality = _inferQualityFromUrl(abs)
            ..headers = refHeaders,
        );
      }
    }

    // ── Strategy 4: Any quoted absolute .mp4 / .m3u8 in any script block ──────
    if (videos.isEmpty) {
      final genericPattern = RegExp(
        r'["\u0027](https?://[^"\u0027]+\.(?:mp4|m3u8|webm)[^"\u0027]*)["\u0027]',
        caseSensitive: false,
      );
      for (final script in scripts) {
        final match = genericPattern.firstMatch(script);
        final src = match?.group(1)?.trim() ?? "";
        if (src.isNotEmpty) {
          videos.add(
            MVideo()
              ..url = src
              ..originalUrl = src
              ..quality = _inferQualityFromUrl(src)
              ..headers = refHeaders,
          );
          break;
        }
      }
    }

    if (videos.isEmpty) {
      // Absolute last resort: surface the page URL so the player can attempt
      // its own embed detection rather than hard-crashing with nothing.
      return [
        MVideo()
          ..url = normalized
          ..originalUrl = normalized
          ..quality = "page (extraction failed)",
      ];
    }
    return videos;
  }

  MPages parseListingPage(String html, int page) {
    final document = parseHtml(html);
    final results = <MManga>[];
    final seen = <String>{};

    final anchors = document.select('a[href*="/video/"]');
    for (final anchor in anchors) {
      final href = anchor.getHref;
      final normalized = normalizeUrl(href);
      if (href.isEmpty ||
          !href.contains("/video/") ||
          seen.contains(normalized)) {
        continue;
      }

      final titleAttr = anchor.attr("title").trim();
      final name = titleAttr.isNotEmpty ? titleAttr : anchor.text.trim();
      if (name.isEmpty) {
        continue;
      }

      seen.add(normalized);
      final imageElement = anchor.selectFirst("img");
      final imageUrl =
          imageElement?.getSrc ?? imageElement?.attr("data-src") ?? "";
      results.add(
        MManga()
          ..name = name
          ..link = normalized
          ..imageUrl = imageUrl.isEmpty ? "" : normalizeUrl(imageUrl),
      );
    }

    final hasNextPage = looksPaginated(html, page);
    return MPages(results, hasNextPage);
  }

  Future<String> fetchRoute(String url, String context) async {
    final uri = Uri.parse(url);
    try {
      final response = await client.get(uri, headers: buildHeaders());
      final body = response.body;
      if (body.trim().isEmpty) {
        fail("$context returned an empty response", url: url);
      }

      if (body.contains("login-required") ||
          body.contains("Access denied") ||
          body.contains("geo-blocked")) {
        fail("$context returned a barrier page", url: url);
      }

      return body;
    } catch (error) {
      fail("$context request failed", url: url, error: error);
    }
  }

  String buildBrowsePath({
    required String browseMode,
    required String query,
    required String orientation,
  }) {
    final normalizedQuery = slugify(query);
    final categorySlug = slugify(getPreference("category_slug"));
    final modelSlug = slugify(getPreference("model_slug"));

    switch (browseMode) {
      case "latest":
        return "/latest-updates/";
      case "category":
        if (categorySlug.isNotEmpty) {
          return "/categories/$categorySlug/";
        }
        return "/latest-updates/";
      case "model":
        if (modelSlug.isNotEmpty) {
          return "/models/$modelSlug/";
        }
        return "/latest-updates/";
      case "home":
        return orientation == "all" ? "/" : "/$orientation/";
      case "search":
      default:
        if (normalizedQuery.isEmpty) {
          return orientation == "all" ? "/latest-updates/" : "/$orientation/";
        }
        return "/search/$normalizedQuery/";
    }
  }

  String buildPagedUrl(String path, int page) {
    final normalizedPath = path.startsWith("/") ? path : "/$path";
    final base = "${getBaseUrl()}$normalizedPath";
    if (page <= 1) {
      return base;
    }
    return buildUrlWithQuery(base, {"page": page.toString()});
  }

  Map<String, String> buildHeaders() {
    final userAgent = getPreference("user_agent");
    final cookieHeader = getPreference("cookie_header");
    final referer = getPreference("referer_url");
    final headers = <String, String>{
      "User-Agent": userAgent.isEmpty ? defaultUserAgent : userAgent,
      "Accept":
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.9",
      "Connection": "close",
    };

    if (cookieHeader.isNotEmpty) {
      headers["Cookie"] = cookieHeader;
    }
    if (referer.isNotEmpty) {
      headers["Referer"] = referer;
    } else {
      headers["Referer"] = "${getBaseUrl()}/";
    }

    return headers;
  }

  String buildDescription(String html, String url, dynamic document) {
    final lines = <String>[];

    // Meta description (KVS usually populates og:description or plain description)
    final metaDesc = extractMetaContent(html, "og:description") ??
        extractMetaContent(html, "description") ??
        "";
    if (metaDesc.isNotEmpty) lines.add(metaDesc);

    // Tags — try common KVS / rule34video DOM selectors
    final tagSelectors = [
      ".video-tags a",
      ".tags a",
      "ul.tags li a",
      ".tag_list a",
      ".item-tags a",
      ".categories a",
      ".video_categories a",
    ];
    for (final sel in tagSelectors) {
      final tagEls = document.select(sel);
      if (tagEls == null || tagEls.isEmpty) continue;
      final tags = <String>[];
      for (final el in tagEls) {
        final t = el.text?.trim() ?? "";
        if (t.isNotEmpty) tags.add(t);
      }
      if (tags.isNotEmpty) {
        if (lines.isNotEmpty) lines.add("");
        lines.add("Tags: ${tags.join(", ")}");
        break;
      }
    }

    // Models / actors — KVS often has a dedicated block
    final modelSelectors = [
      ".models a",
      ".model-list a",
      ".actors a",
      ".video-models a",
    ];
    for (final sel in modelSelectors) {
      final modelEls = document.select(sel);
      if (modelEls == null || modelEls.isEmpty) continue;
      final models = <String>[];
      for (final el in modelEls) {
        final t = el.text?.trim() ?? "";
        if (t.isNotEmpty) models.add(t);
      }
      if (models.isNotEmpty) {
        lines.add("Models: ${models.join(", ")}");
        break;
      }
    }

    // Views / rating — common KVS info bar
    final infoEl = document.selectFirst(".info-count, .video-views, .view_count");
    final infoText = infoEl?.text?.trim() ?? "";
    if (infoText.isNotEmpty) lines.add("Views: $infoText");

    return lines.join("\n").trim();
  }

  // ── Video extraction helpers ─────────────────────────────────────────────────────────

  /// Extracts all inline <script>...</script> block bodies without using
  /// dotAll regex (not reliable in dart_eval). Uses plain indexOf iteration.
  List<String> _extractScriptBlocks(String html) {
    final blocks = <String>[];
    var offset = 0;
    while (offset < html.length) {
      final tagStart = html.indexOf('<script', offset);
      if (tagStart == -1) break;
      final tagClose = html.indexOf('>', tagStart);
      if (tagClose == -1) break;
      final contentStart = tagClose + 1;
      final blockEnd = html.indexOf('</script>', contentStart);
      if (blockEnd == -1) break;
      final content = html.substring(contentStart, blockEnd);
      if (content.isNotEmpty) blocks.add(content);
      offset = blockEnd + 9; // len('</script>') == 9
    }
    return blocks;
  }

  /// KVS injects quality tiers as bare JS vars:
  ///   var video_url = 'https://cdn.example.com/file.mp4';
  ///   var video_low = 'https://cdn.example.com/file_low.mp4';
  String _extractJsVarFromScripts(List<String> scripts, String varName) {
    final pattern = RegExp(
      'var\\s+$varName\\s*=\\s*[\'"]([^\'"]+)[\'"]',
      caseSensitive: false,
    );
    for (final script in scripts) {
      final match = pattern.firstMatch(script);
      final val = match?.group(1)?.trim() ?? "";
      if (val.isNotEmpty) return val;
    }
    return "";
  }

  /// KVS also embeds URLs inside flashvars / player_vars object literals:
  ///   'video_url': 'https://cdn.example.com/file.mp4'
  String _extractFlashvarsUrl(List<String> scripts) {
    final pattern = RegExp(
      r"""['"]video_url['"]?\s*:\s*['"]([^'"]+)['"]""",
      caseSensitive: false,
    );
    for (final script in scripts) {
      final match = pattern.firstMatch(script);
      final val = match?.group(1)?.trim() ?? "";
      if (val.isNotEmpty) return val;
    }
    return "";
  }

  /// JWPlayer / VideoJS setup() call with  file: 'URL'  source entries.
  List<String> _extractJwPlayerFiles(List<String> scripts) {
    final results = <String>[];
    final pattern = RegExp(
      r"""['"]?file['"]?\s*:\s*['"]([^'"]+\.(?:mp4|m3u8|webm)[^'"]*)['"]""",
      caseSensitive: false,
    );
    for (final script in scripts) {
      for (final match in pattern.allMatches(script)) {
        final val = match.group(1)?.trim() ?? "";
        if (val.isNotEmpty && !results.contains(val)) results.add(val);
      }
    }
    return results;
  }

  /// Infer a human-readable quality label from CDN URL path segments.
  String _inferQualityFromUrl(String url) {
    if (url.contains("1080")) return "1080p";
    if (url.contains("720")) return "720p";
    if (url.contains("480")) return "480p";
    if (url.contains("360")) return "360p";
    if (url.contains("240")) return "240p";
    if (url.contains(".m3u8")) return "HLS";
    return "";
  }

  /// Resolve protocol-relative and root-relative paths to full URLs.
  String _toAbsoluteUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith("http://") || url.startsWith("https://")) return url;
    if (url.startsWith("//")) return "https:$url";
    if (url.startsWith("/")) return "${getBaseUrl()}$url";
    return url;
  }

  String? extractMetaContent(String html, String propertyOrName) {
    // Manual property escaping — RegExp.escape() is not available in dart_eval.
    final escaped = propertyOrName
        .replaceAll(r"\\", r"\\")
        .replaceAll(".", r"\.")
        .replaceAll("+", r"\+")
        .replaceAll("*", r"\*")
        .replaceAll("?", r"\?")
        .replaceAll("(", r"\(")
        .replaceAll(")", r"\)")
        .replaceAll("[", r"\[")
        .replaceAll("{", r"\{")
        .replaceAll("^", r"\^")
        .replaceAll(r"$", r"\$")
        .replaceAll("|", r"\|");
    final patterns = [
      RegExp(
        '<meta[^>]+property=["\']$escaped["\'][^>]+content=["\']([^"\']+)["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+name=["\']$escaped["\'][^>]+content=["\']([^"\']+)["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']$escaped["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+content=["\']([^"\']+)["\'][^>]+name=["\']$escaped["\']',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final value = match?.group(1)?.trim() ?? "";
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String? extractPosterUrl(dynamic document) {
    final selectors = [
      'video[poster]',
      'meta[property="og:image"]',
      '.thumb img',
      '.kt_video_block img',
      '.item img',
    ];

    for (final selector in selectors) {
      final element = document.selectFirst(selector);
      if (element == null) {
        continue;
      }
      var src = element.attr("poster").trim();
      if (src.isEmpty) {
        src = element.attr("src").trim();
      }
      if (src.isEmpty) {
        src = element.attr("data-src").trim();
      }
      if (src.isNotEmpty) {
        return normalizeUrl(src);
      }
    }
    return null;
  }

  bool looksPaginated(String html, int page) {
    final markers = [
      'page=${page + 1}',
      '/page/${page + 1}/',
      '/page${page + 1}/',
      'pagination-next',
      'next"',
    ];
    return markers.any((marker) => html.contains(marker));
  }

  String slugify(String input) {
    final trimmed = input.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return "";
    }
    // Use simple character-level transforms — complex \w regex classes
    // are not reliably available inside dart_eval.
    final buf = StringBuffer();
    bool lastWasDash = false;
    for (var i = 0; i < trimmed.length; i++) {
      final c = trimmed[i];
      final code = c.codeUnitAt(0);
      final isAlpha = (code >= 97 && code <= 122); // a-z
      final isDigit = (code >= 48 && code <= 57);  // 0-9
      final isDash = c == '-';
      if (isAlpha || isDigit || isDash) {
        if (isDash && lastWasDash) continue;
        buf.write(c);
        lastWasDash = isDash;
      } else if (!lastWasDash) {
        buf.write('-');
        lastWasDash = true;
      }
    }
    final result = buf.toString();
    // Trim leading/trailing dashes
    var start = 0;
    var end = result.length;
    while (start < end && result[start] == '-') start++;
    while (end > start && result[end - 1] == '-') end--;
    return result.substring(start, end);
  }

  String titleFromUrl(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) {
      return "rule34video";
    }
    return segments.last.replaceAll("-", " ").trim();
  }

  String normalizeUrl(String url) {
    if (url.isEmpty) {
      return url;
    }
    if (url.startsWith("http://") || url.startsWith("https://")) {
      return url;
    }
    return "${getBaseUrl()}${getUrlWithoutDomain(url)}";
  }

  String getBaseUrl() {
    final override = getPreference("domain_url");
    if (override.isEmpty) {
      return source.baseUrl;
    }
    return override.endsWith("/")
        ? override.substring(0, override.length - 1)
        : override;
  }

  String getPreference(String key) {
    return getPreferenceValue(source.id, key)?.toString().trim() ?? "";
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

  Never fail(String context, {String? url, Object? error}) {
    final parts = <String>["Rule34Video: $context"];
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
      SelectFilter("SelectFilter", "Browse Mode", 0, [
        SelectFilterOption("Search", "search", null),
        SelectFilterOption("Latest", "latest", null),
        SelectFilterOption("Home", "home", null),
        SelectFilterOption("Category", "category", null),
        SelectFilterOption("Model", "model", null),
      ], null),
      SelectFilter("SelectFilter", "Orientation", 0, [
        SelectFilterOption("All", "all", null),
        SelectFilterOption("Straight", "straight", null),
        SelectFilterOption("Gay", "gay", null),
        SelectFilterOption("Futa", "futa", null),
        SelectFilterOption("Music", "music", null),
        SelectFilterOption("Iwara", "iwara", null),
      ], null),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key: "domain_url",
        title: "Base URL",
        summary: "Default: https://rule34video.com",
        value: source.baseUrl,
        dialogTitle: "Base URL",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "category_slug",
        title: "Category Slug",
        summary:
            "Used when Browse Mode is set to Category, for routes like /categories/{slug}/",
        value: "",
        dialogTitle: "Category Slug",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "model_slug",
        title: "Model Slug",
        summary:
            "Used when Browse Mode is set to Model, for routes like /models/{slug}/",
        value: "",
        dialogTitle: "Model Slug",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "user_agent",
        title: "User Agent",
        summary: "Optional browser-like User-Agent override for testing.",
        value: defaultUserAgent,
        dialogTitle: "User Agent",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "referer_url",
        title: "Referer",
        summary: "Optional Referer override for route testing.",
        value: source.baseUrl + "/",
        dialogTitle: "Referer",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "cookie_header",
        title: "Cookie Header",
        summary: "Optional manual Cookie header for session testing only.",
        value: "",
        dialogTitle: "Cookie Header",
        dialogMessage: "",
      ),
    ];
  }

  static const String defaultUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36";
}

Rule34Video main(MSource source) {
  return Rule34Video(source: source);
}
