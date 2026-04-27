import 'package:mangayomi/bridge_lib.dart';

class Nyaa extends MProvider {
  Nyaa({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Future<MPages> getPopular(int page) async {
    final res = await fetchPage(
      page: page,
      query: "",
      sortKey: "downloads",
      ascending: false,
    );
    return parseAnimeList(res);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await fetchPage(
      page: page,
      query: "",
      sortKey: "id",
      ascending: false,
    );
    return parseAnimeList(res);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    String sortKey = "";
    var ascending = false;

    for (final filter in filterList.filters) {
      if (filter.type == "SortFilter") {
        sortKey = filter.values[filter.state.index].value;
        ascending = filter.state.ascending;
      }
    }

    final res = await fetchPage(
      page: page,
      query: query.trim(),
      sortKey: sortKey,
      ascending: ascending,
    );
    return parseAnimeList(res);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final detailUrl = normalizeUrl(url);
    final res = await fetchText(Uri.parse(detailUrl), "load detail page");
    final document = parseHtml(res);
    final anime = MManga();

    anime.name = document.selectFirst(".panel-title")?.text.trim() ?? "";
    anime.description = extractPanelBody(document);

    final chapters = <MChapter>[];
    final torrentLink = document.selectFirst('a[href*="/download/"]')?.getHref;
    final magnetLink = document.selectFirst('a[href^="magnet:"]')?.getHref;

    if (torrentLink != null && torrentLink.isNotEmpty) {
      chapters.add(MChapter(name: "Torrent", url: normalizeUrl(torrentLink)));
    }
    if (magnetLink != null && magnetLink.isNotEmpty) {
      chapters.add(MChapter(name: "Magnet", url: magnetLink));
    }

    if (anime.name.isEmpty && chapters.isEmpty) {
      fail("could not parse detail page", url: detailUrl);
    }

    anime.chapters = chapters.isEmpty
        ? [MChapter(name: "Open Torrent Page", url: detailUrl)]
        : chapters;
    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    return [
      MVideo()
        ..url = url
        ..originalUrl = url
        ..quality = url.startsWith("magnet:") ? "magnet" : "torrent",
    ];
  }

  Future<String> fetchPage({
    required int page,
    required String query,
    required String sortKey,
    required bool ascending,
  }) async {
    final uri = Uri.parse(
      buildUrlWithQuery(getBaseUrl(), {
        "f": getFilterMode(),
        "c": getCategory(),
        "q": query,
        "p": page.toString(),
        if (sortKey.isNotEmpty) "s": sortKey,
        if (sortKey.isNotEmpty) "o": ascending ? "asc" : "desc",
      }),
    );
    return fetchText(uri, "load listing page");
  }

  String extractPanelBody(MDocument document) {
    final panelBody = document.selectFirst(".panel-body");
    if (panelBody == null) {
      return "";
    }

    final rows = panelBody.select(".row");
    final info = <String, String>{};

    for (final row in rows) {
      final labels = row.select(".col-md-1");
      for (final label in labels) {
        final key = label.text.replaceAll(":", "").trim();
        final valueDiv = label.nextElementSibling;
        if (key.isEmpty || valueDiv == null) {
          continue;
        }

        final links = valueDiv.select("a");
        final value = links.isNotEmpty
            ? links.map((anchor) => anchor.text.trim()).join(" - ")
            : valueDiv.text.trim();
        if (value.isNotEmpty) {
          info[key] = value;
        }
      }
    }

    final buffer = StringBuffer();
    if (info.isNotEmpty) {
      buffer.writeln("Torrent Info:");
      buffer.writeln();
      info.forEach((key, value) {
        buffer.writeln("${key.padRight(11)}: $value");
      });
    }

    if (getPreferenceValue(source.id, "torrent_description_visible") == true) {
      final description = document
          .select("#torrent-description")
          .map((element) => element.text.trim())
          .where((text) => text.isNotEmpty)
          .join("\n\n");
      if (description.isNotEmpty) {
        if (buffer.isNotEmpty) {
          buffer.writeln();
          buffer.writeln();
        }
        buffer.writeln("Torrent Description:");
        buffer.writeln();
        buffer.write(description);
      }
    }

    return buffer.toString().trim();
  }

  MPages parseAnimeList(String res) {
    final document = parseHtml(res);
    final rows = document.select("table.torrent-list tbody tr");
    final animeList = <MManga>[];

    for (final row in rows) {
      final detailAnchors = row
          .select('a[href^="/view/"]')
          .where((anchor) => !anchor.getHref.contains("#comments"))
          .toList();
      if (detailAnchors.isEmpty) {
        continue;
      }

      final detailAnchor = detailAnchors.first;
      final detailUrl = detailAnchor.getHref;
      final title = detailAnchor.attr("title").trim().isNotEmpty
          ? detailAnchor.attr("title").trim()
          : detailAnchor.text.trim();
      if (detailUrl.isEmpty || title.isEmpty) {
        continue;
      }

      final coverPath = row.selectFirst("td img.category-icon")?.getSrc ?? "";
      final anime = MManga()
        ..name = title
        ..link = normalizeUrl(detailUrl);
      if (coverPath.isNotEmpty) {
        anime.imageUrl = normalizeUrl(coverPath);
      }
      animeList.add(anime);
    }

    final hasNextPage = document
        .select('ul.pagination li.next a[href]')
        .isNotEmpty;
    return MPages(animeList, hasNextPage);
  }

  String getCategory() {
    return getPreferenceValue(
          source.id,
          "preferred_category_page",
        )?.toString() ??
        "1_0";
  }

  String getFilterMode() {
    return getPreferenceValue(source.id, "preferred_filter_mode")?.toString() ??
        "0";
  }

  String normalizeUrl(String url) {
    if (hasScheme(url)) {
      return url;
    }
    return "${getBaseUrl()}${getUrlWithoutDomain(url)}";
  }

  bool hasScheme(String url) {
    return RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(url);
  }

  String getBaseUrl() {
    final baseUrl = getPreferenceValue(source.id, "domain_url")?.trim();
    if (baseUrl == null || baseUrl.isEmpty) {
      return source.baseUrl;
    }
    return baseUrl.endsWith("/")
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  Future<String> fetchText(Uri uri, String context) async {
    try {
      final body = (await client.get(uri, headers: {"Connection": "close"})).body;
      if (body.trim().isEmpty) {
        fail("$context returned an empty response", url: uri.toString());
      }
      return body;
    } catch (error) {
      fail("$context request failed", error: error, url: uri.toString());
    }
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

  Never fail(String context, {Object? error, String? url}) {
    final parts = <String>["Nyaa: $context"];
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
      SortFilter("SortFilter", "Sort by", SortState(0, false), [
        SelectFilterOption("Default", ""),
        SelectFilterOption("Date", "id"),
        SelectFilterOption("Size", "size"),
        SelectFilterOption("Seeders", "seeders"),
        SelectFilterOption("Leechers", "leechers"),
        SelectFilterOption("Downloads", "downloads"),
      ]),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() {
    return [
      ListPreference(
        key: "preferred_category_page",
        title: "Category",
        summary: "",
        valueIndex: 0,
        entries: [
          "Anime",
          "Anime - AMV",
          "Anime - English",
          "Anime - Non-English",
          "Anime - Raw",
          "Live Action",
        ],
        entryValues: ["1_0", "1_1", "1_2", "1_3", "1_4", "4_0"],
      ),
      ListPreference(
        key: "preferred_filter_mode",
        title: "Filter",
        summary: "",
        valueIndex: 0,
        entries: ["No filter", "No remakes", "Trusted only"],
        entryValues: ["0", "1", "2"],
      ),
      SwitchPreferenceCompat(
        key: "torrent_description_visible",
        title: "Display Torrent Description",
        summary: "Show the markdown torrent description in the details view.",
        value: false,
      ),
      EditTextPreference(
        key: "domain_url",
        title: "Edit URL",
        summary: "",
        value: source.baseUrl,
        dialogTitle: "URL",
        dialogMessage: "",
      ),
    ];
  }
}

Nyaa main(MSource source) {
  return Nyaa(source: source);
}
