import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class ScribbleHub extends MProvider {
  ScribbleHub({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get(
      Uri.parse("${source.baseUrl}/series-ranking/?sort=1&order=1&pg=$page"),
    );
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get(
      Uri.parse("${source.baseUrl}/latest-series/?pg=$page"),
    );
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final url =
        "${source.baseUrl}/?s=${Uri.encodeQueryComponent(query)}&post_type=fictionposts";
    // Pagination for search is a bit different, but usually &pg=$page works if supported,
    // or /page/$page/?s=...
    final pagedUrl = page > 1
        ? "${source.baseUrl}/page/$page/?s=${Uri.encodeQueryComponent(query)}&post_type=fictionposts"
        : url;
    final res = await client.get(Uri.parse(pagedUrl));
    return _parseList(res.body);
  }

  MPages _parseList(String html) {
    final document = parseHtml(html);
    final elements = document.select("div.search_main_box");
    final List<MManga> mangas = [];

    for (final el in elements) {
      final a = el.selectFirst("div.search_title > a");
      if (a == null) continue;

      final manga = MManga();
      manga.name = a.text.trim();
      manga.link = a.attr("href");

      final img = el.selectFirst("div.search_img img");
      if (img != null) {
        manga.imageUrl = img.attr("src");
      }

      mangas.add(manga);
    }

    final next = document.selectFirst("a.page-link.next") != null;
    return MPages(mangas, next);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(Uri.parse(url));
    final document = parseHtml(res.body);

    final manga = MManga();
    manga.link = url;
    manga.name = document.selectFirst("div.fic_title")?.text.trim() ?? "";
    manga.imageUrl =
        document.selectFirst("div.fic_image img")?.attr("src") ?? "";
    manga.author =
        document.selectFirst("span.auth_name_fic")?.text.trim() ?? "";

    final desc = document.selectFirst("div.wi_fic_desc")?.text.trim() ?? "";
    manga.description = desc;

    final genres = document.select("a.fic_genre");
    manga.genre = genres.map((e) => e.text.trim()).toList();

    // Chapter list: It uses AJAX, we need mypostid
    final mypostid =
        document.selectFirst("input#mypostid")?.attr("value") ?? "";

    if (mypostid.isNotEmpty) {
      final chapters = await _getAllChapters(mypostid);
      manga.chapters = chapters;
    }

    return manga;
  }

  Future<List<MChapter>> _getAllChapters(String postId) async {
    final List<MChapter> allChapters = [];
    int page = 1;

    while (true) {
      final res = await client.post(
        Uri.parse("${source.baseUrl}/wp-admin/admin-ajax.php"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: "action=wi_getreleases_pagination&pagenum=$page&mypostid=$postId",
      );

      final document = parseHtml(res.body);
      final chapterElements = document.select("li.toc_w");
      if (chapterElements.isEmpty) break;

      for (final el in chapterElements) {
        final a = el.selectFirst("a");
        if (a == null) continue;

        final chapter = MChapter();
        chapter.name = a.text.trim();
        chapter.url = a.attr("href");
        final dateText = el.selectFirst("span.fic_date_pub")?.text.trim() ?? "";
        // Optional: date parsing

        allChapters.add(chapter);
      }

      page++;
      if (page > 50) break;
    }

    // Usually Scribble Hub chapters are returned descending (newest first).
    // Mangayomi expects them in the order they were released if possible, but
    // descending is also fine as long as we add them properly.
    return allChapters;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final res = await client.get(Uri.parse(url));
    final document = parseHtml(res.body);

    final content = document.selectFirst("div#chp_raw");
    if (content != null) {
      // Remove author notes if present
      final authorNotes = content.selectFirst("div.wi_authornotes");
      if (authorNotes != null) {
        // Since we can't easily remove elements in the bridge, we'll extract text.
        // Or we can just get outerHtml and replace the author notes html with empty.
        final html = content.outerHtml;
        final cleanHtml = html.replaceAll(authorNotes.outerHtml, "");
        return [cleanHtml];
      }
      return [content.outerHtml];
    }

    return <dynamic>[];
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];
}

ScribbleHub main(MSource source) => ScribbleHub(source: source);
