import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

// ─── Pixiv source for Mangayomi ───────────────────────────────────────────────
// Site   : https://www.pixiv.net  (via https://app-api.pixiv.net)
// Type   : Unofficial mobile App API (reverse-engineered from iOS/Android apps)
// Lang   : all
// NSFW   : true (R-18 content gated by token x_restrict — returned if token allows)
//
// ─── STUB NOTICE ─────────────────────────────────────────────────────────────
// This extension is a FUNCTIONAL STUB. Core listing, search, detail, and
// image-page extraction are implemented. The following are NOT yet done:
//   • Ugoira (animated) illust support (requires a separate /ugoira/metadata call)
//   • "Recommended" / Following feed endpoints (require premium or social graph)
//   • R-18 explicit content filtering via filter settings
//   • Token validation error surfacing to the settings UI
//
// ─── Authentication — REQUIRED SETUP ─────────────────────────────────────────
// Pixiv retired password-based login on 2021-02-08.
// This extension uses the PKCE Refresh Token flow:
//
//  1. The user obtains a refresh_token ONCE using the `gppt` Python CLI tool:
//       pip install gppt
//       gppt login
//     It opens a browser, the user signs in once, and `gppt` prints the tokens.
//     Copy the `refresh_token` value and paste it into the extension settings.
//
//  2. On every launch, this extension exchanges the refresh_token for a short-
//     lived access_token (TTL: 3600 s). The access_token is cached in memory
//     and refreshed proactively 5 minutes before expiry.
//
// ─── Image CDN auth ──────────────────────────────────────────────────────────
// All images at i.pximg.net require:
//   Referer: https://www.pixiv.net/
// Without it the CDN returns 403 Forbidden.
//
// ─── API endpoints used ──────────────────────────────────────────────────────
//  Popular/Trending : GET /v1/illust/ranking?mode=day&filter=for_ios
//  Latest           : GET /v1/illust/new?content_type=illust&filter=for_ios
//  Search           : GET /v1/search/illust?word={q}&search_target=partial_match_for_tags&sort=date_desc&filter=for_ios
//  Detail           : GET /v1/illust/detail?illust_id={id}
//  Auth             : POST https://oauth.secure.pixiv.net/auth/token

class Pixiv extends MProvider {
  Pixiv({required this.source});

  final MSource source;
  final Client  client = Client();

  // ── Auth constants (from Pixiv Android app — stable since 2020) ───────────

  static const _authUrl      = 'https://oauth.secure.pixiv.net/auth/token';
  static const _apiBase      = 'https://app-api.pixiv.net';
  static const _clientId     = 'MOBrBDS8blbauoSck0ZfDbtuzpyT';
  static const _clientSecret = 'lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj';
  static const _userAgent    = 'PixivIOSApp/7.13.3 (iOS 14.6; iPhone13,2)';
  static const _imageReferer = 'https://www.pixiv.net/';

  // ── In-memory token cache ─────────────────────────────────────────────────
  // These are instance-level; dart_eval re-creates the instance per session,
  // so the token is re-minted once per Mangayomi session — acceptable overhead.

  String?   _accessToken;
  DateTime? _expiresAt;

  // ── Listing ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    // Pixiv uses cursor-based pagination via next_url, not page numbers.
    // For getPopular (ranking), only one page of 30 exists; subsequent "pages"
    // from Mangayomi will hit the same endpoint — acceptable for a stub.
    final token = await _getAccessToken();
    if (token == null) {
      return MPages([], false);
    }
    final res = await client.get(
      Uri.parse('$_apiBase/v1/illust/ranking?mode=day&filter=for_ios'),
      headers: _appHeaders(token),
    );
    return _parseIllustList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final token = await _getAccessToken();
    if (token == null) {
      return MPages([], false);
    }
    final res = await client.get(
      Uri.parse('$_apiBase/v1/illust/new?content_type=illust&filter=for_ios'),
      headers: _appHeaders(token),
    );
    return _parseIllustList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    if (query.trim().isEmpty) return getPopular(page);

    String sortMode = 'date_desc';
    for (final f in filterList.filters) {
      if (f.name == 'Sort' && (f.state as int) > 0) {
        const sorts = ['', 'date_desc', 'date_asc'];
        final idx = f.state as int;
        if (idx < sorts.length) sortMode = sorts[idx];
      }
    }

    final token = await _getAccessToken();
    if (token == null) {
      return MPages([], false);
    }
    final uri = Uri.parse(
      '$_apiBase/v1/search/illust'
      '?word=${Uri.encodeComponent(query.trim())}'
      '&search_target=partial_match_for_tags'
      '&sort=$sortMode'
      '&filter=for_ios',
    );
    final res = await client.get(uri, headers: _appHeaders(token));
    return _parseIllustList(res.body);
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final illustId = _idFromUrl(url);
    final token    = await _getAccessToken();
    if (token == null) {
      throw Exception('Pixiv: no refresh_token set. '
          'Paste your token in Source Settings → Refresh Token.');
    }

    final res  = await client.get(
      Uri.parse('$_apiBase/v1/illust/detail?illust_id=$illustId'),
      headers: _appHeaders(token),
    );
    final data = jsonDecode(res.body)['illust'] as Map<String, dynamic>;

    final manga     = MManga();
    manga.name      = data['title']?.toString() ?? 'Pixiv #$illustId';
    manga.imageUrl  = (data['image_urls'] as Map)['large']?.toString() ?? '';
    manga.author    = (data['user'] as Map)['name']?.toString() ?? '';
    manga.description = data['caption']?.toString() ?? '';
    manga.status    = 0; // Illusts are always complete
    manga.genre     = (data['tags'] as List?)
            ?.map((t) => (t as Map)['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    // Single virtual chapter → getPageList resolves images
    final chapter = MChapter();
    chapter.name  = manga.name ?? 'Gallery';
    chapter.url   = url;
    manga.chapters = [chapter];

    return manga;
  }

  // ── Page List ─────────────────────────────────────────────────────────────

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final illustId = _idFromUrl(url);
    final token    = await _getAccessToken();
    if (token == null) {
      throw Exception('Pixiv: no refresh_token set. '
          'Paste your token in Source Settings → Refresh Token.');
    }

    final res    = await client.get(
      Uri.parse('$_apiBase/v1/illust/detail?illust_id=$illustId'),
      headers: _appHeaders(token),
    );
    final illust    = jsonDecode(res.body)['illust'] as Map<String, dynamic>;
    final pageCount = (illust['page_count'] as num?)?.toInt() ?? 1;

    List<String> imageUrls;
    if (pageCount == 1) {
      final single    = illust['meta_single_page'] as Map<String, dynamic>?;
      final imgUrl    = single?['original_image_url']?.toString() ?? '';
      imageUrls = imgUrl.isNotEmpty ? [imgUrl] : [];
    } else {
      final metaPages = illust['meta_pages'] as List? ?? [];
      imageUrls = metaPages
          .map((p) => ((p as Map)['image_urls'] as Map?)?['original']?.toString() ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
    }

    // Mangayomi needs Map<String,dynamic> entries with headers for the CDN Referer
    return imageUrls.asMap().entries.map((entry) {
      return {
        'index':    entry.key,
        'imageUrl': entry.value,
        'headers':  {'Referer': _imageReferer},
      };
    }).toList();
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  List<dynamic> getFilterList() {
    return [
      SelectFilter(
        'Sort', 'sort', 0,
        [
          SelectFilterOption('Newest First', 'date_desc'),
          SelectFilterOption('Oldest First', 'date_asc'),
        ]
      ),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key:           'pixiv_refresh_token',
        title:         'Pixiv Refresh Token',
        summary:       'Required. Get yours with: pip install gppt && gppt login',
        value:         '',
        dialogTitle:   'Pixiv Refresh Token',
        dialogMessage: 'Paste the refresh_token value printed by gppt or your '
                       'manual PKCE setup. This token does NOT expire unless '
                       'you manually revoke it from Pixiv account security settings.',
        text:          '',
      ),
    ];
  }

  // ── Auth helpers ──────────────────────────────────────────────────────────

  /// Returns a valid access_token, refreshing if needed.
  /// Returns null when no refresh_token is configured.
  Future<String?> _getAccessToken() async {
    final refreshToken =
        (await getPreferenceValue(source.id, 'pixiv_refresh_token'))
            ?.toString()
            .trim() ??
            '';

    if (refreshToken.isEmpty) return null;

    // Use cached token if still valid (with 5-minute pre-expiry buffer)
    if (_accessToken != null &&
        _expiresAt != null &&
        DateTime.now().isBefore(_expiresAt!.subtract(const Duration(minutes: 5)))) {
      return _accessToken!;
    }

    return _refreshAccessToken(refreshToken);
  }

  Future<String> _refreshAccessToken(String refreshToken) async {
    final res = await client.post(
      Uri.parse(_authUrl),
      headers: {
        'User-Agent':    _userAgent,
        'App-OS':        'ios',
        'App-OS-Version':'14.6',
        'App-Version':   '7.13.3',
        'Content-Type':  'application/x-www-form-urlencoded',
      },
      body: 'client_id=$_clientId'
          '&client_secret=$_clientSecret'
          '&grant_type=refresh_token'
          '&include_policy=true'
          '&refresh_token=$refreshToken',
    );

    if (res.statusCode != 200) {
      throw Exception(
          'Pixiv: token refresh failed (${res.statusCode}). '
          'Check your refresh_token in Source Settings.');
    }

    final data       = jsonDecode(res.body) as Map<String, dynamic>;
    _accessToken     = data['access_token'] as String;
    final expiresIn  = (data['expires_in'] as num).toInt();
    _expiresAt       = DateTime.now().add(Duration(seconds: expiresIn));
    return _accessToken!;
  }

  Map<String, String> _appHeaders(String accessToken) => {
    'Authorization':  'Bearer $accessToken',
    'User-Agent':     _userAgent,
    'App-OS':         'ios',
    'App-OS-Version': '14.6',
    'App-Version':    '7.13.3',
    'Accept-Language':'en_US',
    'Referer':        _imageReferer,
  };

  MPages _parseIllustList(String responseBody) {
    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    final list = (json['illusts'] as List?)?.cast<Map<String, dynamic>>() ??
        (json['ranking'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final mangas = list.map((item) {
      final id        = item['id']?.toString() ?? '';
      final imageUrls = item['image_urls'] as Map<String, dynamic>?;
      final manga     = MManga();
      manga.name      = item['title']?.toString() ?? 'Pixiv #$id';
      manga.link      = 'https://www.pixiv.net/artworks/$id';
      manga.imageUrl  = imageUrls?['medium']?.toString() ?? '';
      return manga;
    }).toList();

    final hasNext = json['next_url'] != null;
    return MPages(mangas, hasNext);
  }

  String _idFromUrl(String url) {
    return RegExp(r'/artworks/(\d+)').firstMatch(url)?.group(1) ??
        RegExp(r'illust_id=(\d+)').firstMatch(url)?.group(1) ?? '';
  }
}

Pixiv main(MSource source) {
  return Pixiv(source: source);
}
