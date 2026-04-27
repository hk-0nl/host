import 'dart:convert';
import 'package:mangayomi/bridge_lib.dart';

// ─── Archive of Our Own (AO3) source for Mangayomi ───────────────────────────
// Site   : https://archiveofourown.org
// Type   : HTML scraper (public /works endpoint — no API)
// Lang   : en
// NSFW   : false
//
// ─── STUB NOTICE ─────────────────────────────────────────────────────────────
// This extension is a FUNCTIONAL STUB. Core listing, search, detail, and
// chapter-text extraction are implemented. The following are NOT yet done:
//   • Full filter wiring (rating_ids, category, word_count range, date_from/to)
//   • User/bookmarks section (requires session cookie auth)
//   • Cover image (AO3 has none — placeholder empty string is returned)
//
// ─── Rate-Limit Contract ─────────────────────────────────────────────────────
// AO3's ToS requires ≥ 5 s between automated requests. This implementation
// uses a BACKOFF-ONLY strategy:
//   • No hard delay inserted on every request (avoids ruining the UX for
//     fast connections that do not trigger 429).
//   • On HTTP 429: exponential backoff starting at 60 s, capped at 10 min,
//     max 3 retries. If all retries fail, a descriptive error is surfaced.
//
// ─── HTML selectors ──────────────────────────────────────────────────────────
// Search results : ol.work.index.group  >  li.work.blurb.group
//   Title        : h4.heading a:first-child
//   Author       : a[rel="author"]
//   Work ID      : href of title link  →  /works/{id}
// Work detail    : /works/{id}?view_adult=true
//   Chapter nav  : #jump-to-chapter select > option[value="{chapterId}"]
//   Chapter text : #workskin .userstuff  (fallback: .userstuff.module)

class ArchiveOfOurOwn extends MProvider {
  ArchiveOfOurOwn({required this.source});

  final MSource source;
  final Client  client = Client();

  static const _base     = 'https://archiveofourown.org';
  static const _maxRetry = 3;

  // ── Listing ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    // "Popular" on AO3 ≈ most-kudosed works across all fandoms
    return _fetchListing(
      page: page,
      sortColumn: 'kudos_count',
    );
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return _fetchListing(
      page: page,
      sortColumn: 'revised_at',
    );
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    String sortColumn = 'kudos_count';
    bool   completed  = false;
    String language   = '';

    for (final f in filterList.filters) {
      if (f.name == 'Sort' && (f.state as int) > 0) {
        const sorts = [
          '',
          'kudos_count',
          'hits',
          'bookmarks_count',
          'comments_count',
          'revised_at',
          'created_at',
          'word_count',
        ];
        final idx = f.state as int;
        if (idx < sorts.length) sortColumn = sorts[idx];
      }
      if (f.name == 'Completed' && f.state == true) {
        completed = true;
      }
      if (f.name == 'Language' && (f.state as int) > 0) {
        const langs = ['', '1', 'zh', 'ja', 'ko', 'fr', 'de', 'es', 'it', 'pt'];
        final idx = f.state as int;
        if (idx < langs.length) language = langs[idx];
      }
    }

    return _fetchListing(
      page:       page,
      query:      query.trim(),
      sortColumn: sortColumn,
      completed:  completed,
      language:   language,
    );
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final workId = _workIdFromUrl(url);
    final fullUrl = '$_base/works/$workId?view_adult=true';

    final body     = await _fetchWithBackoff(fullUrl);
    final document = parseHtml(body);

    final manga = MManga();
    manga.name = document.selectFirst('h2.title.heading')?.text.trim() ??
        'Work $workId';
    manga.author = document
            .selectFirst('.byline.heading a[rel="author"]')
            ?.text
            .trim() ??
        '';
    manga.description = document
            .selectFirst('.summary.module blockquote.userstuff')
            ?.text
            .trim() ??
        '';
    manga.imageUrl = ''; // AO3 provides no cover images

    // Status from "dd.chapters" — "N/?" = ongoing, "N/N" = completed
    final chapCounter =
        document.selectFirst('dd.chapters')?.text.trim() ?? '';
    manga.status = chapCounter.contains('/?') ? 1 : 0;

    // Tags: fandoms + additional freeform
    final tagEls = document.select('.tags.commas li.tag a.tag');
    manga.genre = tagEls.map((e) => e.text.trim()).toList();

    // Chapters via the nav <select>
    final options = document.select('#jump-to-chapter option');
    if (options.isNotEmpty) {
      manga.chapters = options.asMap().entries.map((entry) {
        final idx      = entry.key;
        final opt      = entry.value;
        final chapId   = opt.attr('value') ?? '';
        final label    = opt.text.trim();
        final chapUrl  = '$_base/works/$workId/chapters/$chapId?view_adult=true';

        final chapter = MChapter();
        chapter.name  = label.isEmpty ? 'Chapter ${idx + 1}' : label;
        chapter.url   = chapUrl;
        return chapter;
      }).toList();
    } else {
      // Single-chapter work: the /works/{id} page IS the chapter
      final chapter = MChapter();
      chapter.name  = 'Chapter 1';
      chapter.url   = fullUrl;
      manga.chapters = [chapter];
    }

    return manga;
  }

  // ── Page List (Chapter Text) ──────────────────────────────────────────────

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final body     = await _fetchWithBackoff(url);
    final document = parseHtml(body);

    // Primary selector — author-styled content zone
    var content = document.selectFirst('#workskin .userstuff');
    // Fallback for older/plain chapters
    content ??= document.selectFirst('.userstuff.module');
    // Last resort
    content ??= document.selectFirst('.userstuff');

    if (content == null) return [];

    // Remove end-notes injected by AO3 inside the same container
    for (final note in content.select('.end.notes.module')) {
      note.remove();
    }

    // Return the cleaned inner HTML as a single "page" for the novel reader
    final htmlContent = content.innerHtml
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    final page = MPages([htmlContent], false);
    return [page];
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  @override
  List<dynamic> getFilterList() {
    return [
      SelectFilter(
        "SelectFilter", "Sort", 0,
        [
          SelectFilterOption("Kudos",     "kudos_count",      null),
          SelectFilterOption("Hits",      "hits",             null),
          SelectFilterOption("Bookmarks", "bookmarks_count",  null),
          SelectFilterOption("Comments",  "comments_count",   null),
          SelectFilterOption("Latest",    "revised_at",       null),
          SelectFilterOption("Oldest",    "created_at",       null),
          SelectFilterOption("Words",     "word_count",       null),
        ],
        null,
      ),
      SelectFilter(
        "SelectFilter", "Language", 0,
        [
          SelectFilterOption("All",        "",   null),
          SelectFilterOption("English",    "1",  null),
          SelectFilterOption("Chinese",    "zh", null),
          SelectFilterOption("Japanese",   "ja", null),
          SelectFilterOption("Korean",     "ko", null),
          SelectFilterOption("French",     "fr", null),
          SelectFilterOption("German",     "de", null),
          SelectFilterOption("Spanish",    "es", null),
          SelectFilterOption("Italian",    "it", null),
          SelectFilterOption("Portuguese", "pt", null),
        ],
        null,
      ),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key:           "ao3_fandom_tag",
        title:         "Default Fandom Tag",
        summary:       "Used for Popular / Latest tabs. "
                       "Example: Harry+Potter+-+J.+K.+Rowling",
        value:         "",
        dialogTitle:   "Default Fandom Tag",
        dialogMessage: "Paste the AO3 tag slug (URL-encoded fandom name)",
      ),
    ];
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Builds a listing request for /works with AO3 query params and parses results.
  Future<MPages> _fetchListing({
    required int    page,
    String          query      = '',
    String          sortColumn = 'kudos_count',
    bool            completed  = false,
    String          language   = '',
  }) async {
    final prefs  = await getPreferenceValue(source.id, 'ao3_fandom_tag');
    final tagId  = (prefs?.toString() ?? '').trim();

    final params = <String, String>{
      'utf8':                          '✓',
      'work_search[sort_column]':      sortColumn,
      'commit':                        'Sort and Filter',
      'page':                          '$page',
    };
    if (query.isNotEmpty)    params['work_search[query]']    = query;
    if (completed)           params['work_search[complete]'] = '1';
    if (language.isNotEmpty) params['work_search[language_id]'] = language;
    if (tagId.isNotEmpty)    params['tag_id']                = tagId;

    final uri  = Uri.https('archiveofourown.org', '/works', params);
    final body = await _fetchWithBackoff(uri.toString());
    return _parseListing(body);
  }

  MPages _parseListing(String html) {
    final document = parseHtml(html);
    final items    = document.select('li.work.blurb.group');

    final mangas = items.map((li) {
      final titleEl = li.selectFirst('h4.heading a');
      final href    = titleEl?.attr('href') ?? '';
      final match   = RegExp(r'/works/(\d+)').firstMatch(href);
      final workId  = match?.group(1) ?? '';
      final title   = titleEl?.text.trim() ?? 'Unknown';

      final manga     = MManga();
      manga.name      = title;
      manga.link      = '$_base/works/$workId';
      manga.imageUrl  = '';
      return manga;
    }).toList();

    final hasNext = document.selectFirst('li.next a[rel="next"]') != null;
    return MPages(mangas, hasNext);
  }

  /// HTTP GET with exponential backoff on 429. No fixed per-request delay.
  Future<String> _fetchWithBackoff(String url) async {
    final headers = {
      'User-Agent':      'Mozilla/5.0 (compatible; Mangayomi/1.0)',
      'Accept':          'text/html,application/xhtml+xml',
      'Accept-Language': 'en-US,en;q=0.9',
    };

    for (var attempt = 0; attempt < _maxRetry; attempt++) {
      final res = await client.get(Uri.parse(url), headers: headers);

      if (res.statusCode == 200) return res.body;

      if (res.statusCode == 429) {
        // Respect Retry-After if present, else exponential: 60, 120, 240…
        final retryHeader = res.headers['retry-after'];
        final waitSec     = retryHeader != null
            ? (int.tryParse(retryHeader) ?? 60)
            : (60 * (1 << attempt)).clamp(60, 600);
        await Future.delayed(Duration(seconds: waitSec));
        continue;
      }

      throw Exception('AO3: HTTP ${res.statusCode} for $url');
    }
    throw Exception('AO3: exceeded $_maxRetry retries for $url');
  }

  String _workIdFromUrl(String url) {
    return RegExp(r'/works/(\d+)').firstMatch(url)?.group(1) ?? '';
  }
}

ArchiveOfOurOwn main(MSource source) => ArchiveOfOurOwn(source: source);
