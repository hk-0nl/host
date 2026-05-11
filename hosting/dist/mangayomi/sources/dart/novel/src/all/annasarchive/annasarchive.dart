import 'package:mangayomi/bridge_lib.dart';

// Anna's Archive — Novel source for hk-0nl registry
// dart_eval hardened: no string interpolation, no Map.entries, Connection:close on all requests
// itemType: 2 (novel/book)

class AnnasArchive extends MProvider {
  AnnasArchive({required this.source});

  final MSource source;
  final Client client = Client();

  Map<String, String> get _headers => {
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
        "Connection": "close",
      };

  // ---------------------------------------------------------------------------
  // Browse endpoints
  // ---------------------------------------------------------------------------

  @override
  Future<MPages> getPopular(int page) async {
    return _fetchPage("", page, sort: "most_relevant", fileType: "", lang: "");
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return _fetchPage("", page, sort: "newest", fileType: "", lang: "");
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    String fileType = "";
    String lang = "";
    String sort = "";

    for (final filter in filterList.filters) {
      if (filter.type == "SelectFilter") {
        final idx = (filter.state as int?) ?? 0;
        if (idx >= 0 && idx < filter.values.length) {
          final val = filter.values[idx].value;
          final name = filter.name;
          if (name == "File Type") {
            fileType = val;
          } else if (name == "Language") {
            lang = val;
          } else if (name == "Sort") {
            sort = val;
          }
        }
      }
    }

    return _fetchPage(query, page, sort: sort, fileType: fileType, lang: lang);
  }

  // ---------------------------------------------------------------------------
  // Core search fetch — no string interpolation, manual URL assembly
  // ---------------------------------------------------------------------------

  Future<MPages> _fetchPage(
    String query,
    int page, {
    String sort = "",
    String fileType = "",
    String lang = "",
  }) async {
    final encoded = query.trim().replaceAll(" ", "+");

    String url = source.baseUrl + "/search?index=&sort=" + sort;
    if (lang.isNotEmpty) {
      url = url + "&lang=" + lang;
    }
    url = url + "&display=&q=" + encoded;
    if (fileType.isNotEmpty) {
      url = url + "&ext=" + fileType;
    }

    final res = await client.get(Uri.parse(url), headers: _headers);
    final document = parseHtml(res.body);

    // Each search result has an anchor with class js-vim-focus
    final links = document.select("a.js-vim-focus");
    final List<MManga> books = [];

    for (final link in links) {
      final href = link.attr("href");
      if (href.isEmpty) continue;

      final book = MManga()
        ..name = link.text.trim()
        ..link = source.baseUrl + href;

      // Thumbnail may be a child img
      final img = link.selectFirst("img");
      if (img != null) {
        book.imageUrl = img.attr("src");
      }

      books.add(book);
    }

    return MPages(books, books.length >= 10);
  }

  // ---------------------------------------------------------------------------
  // Detail page — parses /md5/<hash> page
  // ---------------------------------------------------------------------------

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(Uri.parse(url), headers: _headers);
    final document = parseHtml(res.body);

    final book = MManga()..link = url;

    final titleEl = document.selectFirst("div.font-semibold.text-2xl");
    book.name = titleEl?.text.trim() ?? "";

    final imgEl = document.selectFirst("img");
    book.imageUrl = imgEl?.attr("src") ?? "";

    final authorEl = document.selectFirst("a.text-base");
    book.author = authorEl?.text.trim() ?? "";

    final infoEl = document.selectFirst("div.text-gray-800");
    book.description = infoEl?.text.trim() ?? "";

    // Slow download mirror: scan all <a> tags for /slow_download/ path segment
    // Avoids CSS attribute wildcard selectors which may not be bridged
    String mirrorUrl = "";
    final allAnchors = document.select("a");
    for (final a in allAnchors) {
      final href = a.attr("href");
      if (href.contains("/slow_download/")) {
        mirrorUrl = source.baseUrl + href;
        break;
      }
    }

    final chapterUrl = mirrorUrl.isNotEmpty ? mirrorUrl : url;
    book.chapters = [MChapter(name: "Download", url: chapterUrl)];

    return book;
  }

  // ---------------------------------------------------------------------------
  // Page list — renders a minimal HTML download prompt
  // ---------------------------------------------------------------------------

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final html = "<html><body style=\"font-family:sans-serif;padding:20px;background:#fafafa;\">"
        + "<h2 style=\"color:#222;\">Anna's Archive</h2>"
        + "<p><a href=\""
        + url
        + "\" style=\"font-size:18px;font-weight:bold;color:#1a73e8;\">"
        + "Download (slow, free, no account needed)"
        + "</a></p>"
        + "<p style=\"color:#555;margin-top:16px;font-size:14px;\">"
        + "If the link does not open automatically, copy the URL into a browser. "
        + "A VPN may be required if Anna's Archive is blocked in your region."
        + "</p>"
        + "</body></html>";
    return [html];
  }

  // ---------------------------------------------------------------------------
  // Filters
  // ---------------------------------------------------------------------------

  @override
  List<dynamic> getFilterList() {
    return [
      SelectFilter("SelectFilter", "File Type", 0, [
        SelectFilterOption("Any", "", null),
        SelectFilterOption("EPUB", "epub", null),
        SelectFilterOption("PDF", "pdf", null),
        SelectFilterOption("CBZ", "cbz", null),
        SelectFilterOption("CBR", "cbr", null),
        SelectFilterOption("MOBI", "mobi", null),
        SelectFilterOption("AZW3", "azw3", null),
        SelectFilterOption("TXT", "txt", null),
        SelectFilterOption("DJVU", "djvu", null),
      ], null),
      SelectFilter("SelectFilter", "Language", 0, [
        SelectFilterOption("Any", "", null),
        SelectFilterOption("English", "en", null),
        SelectFilterOption("Russian", "ru", null),
        SelectFilterOption("Chinese", "zh", null),
        SelectFilterOption("German", "de", null),
        SelectFilterOption("French", "fr", null),
        SelectFilterOption("Spanish", "es", null),
        SelectFilterOption("Japanese", "ja", null),
        SelectFilterOption("Portuguese", "pt", null),
        SelectFilterOption("Italian", "it", null),
        SelectFilterOption("Dutch", "nl", null),
        SelectFilterOption("Polish", "pl", null),
        SelectFilterOption("Ukrainian", "uk", null),
      ], null),
      SelectFilter("SelectFilter", "Sort", 0, [
        SelectFilterOption("Most Relevant", "", null),
        SelectFilterOption("Newest", "newest", null),
        SelectFilterOption("Oldest", "oldest", null),
        SelectFilterOption("Largest", "largest", null),
        SelectFilterOption("Smallest", "smallest", null),
      ], null),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() => [];
}

AnnasArchive main(MSource source) => AnnasArchive(source: source);
