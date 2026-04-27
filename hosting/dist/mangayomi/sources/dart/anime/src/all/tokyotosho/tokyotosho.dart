import 'package:mangayomi/bridge_lib.dart';

class TokyoTosho extends MProvider {
  TokyoTosho({required this.source});

  final MSource source;
  final Client client = Client();

  @override
  Future getPopular(int page) async {
    final url = buildUrlWithQuery("${getBaseUrl()}/", {"cat": "1", "page": page.toString()});
    final res = await fetchText(Uri.parse(url), "load popular listing");
    return parseListing(res, "");
  }

  @override
  Future getLatestUpdates(int page) async {
    final url = buildUrlWithQuery("${getBaseUrl()}/", {"cat": "1", "page": page.toString()});
    final res = await fetchText(Uri.parse(url), "load latest listing");
    return parseListing(res, "");
  }

  @override
  Future search(String query, int page, FilterList filterList) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return getLatestUpdates(page);
    }

    final searchUrl = Uri.parse(
      buildUrlWithQuery("${getBaseUrl()}/search.php", {
        "terms": trimmedQuery,
        "type": "1",
        "searchName": "true",
        "searchComment": "true",
      }),
    );
    final res = await fetchText(searchUrl, "search torrents");
    return parseListing(res, "");
  }

  @override
  Future getDetail(String url) async {
    final anime = MManga();
    final detailUrl = normalizeUrl(url);
    final res = await fetchText(Uri.parse(detailUrl), "load detail page");
    final document = parseHtml(res);
    final details = parseDetails(document);

    anime.name =
        details["Torrent Name"] ??
        document.selectFirst("title")?.text.split(" :: ").first.trim() ??
        "";
    anime.description = buildDescription(details);

    final magnetLink = document.selectFirst('a[href^="magnet:"]')?.getHref;
    final torrentLink =
        document.selectFirst('a[type="application/x-bittorrent"]')?.getHref ??
        "";

    final chapters = <MChapter>[];
    if (magnetLink != null && magnetLink.isNotEmpty) {
      chapters.add(MChapter(name: "Magnet", url: magnetLink));
    }
    if (torrentLink.isNotEmpty) {
      chapters.add(MChapter(name: "Torrent", url: normalizeUrl(torrentLink)));
    }

    if (anime.name.isEmpty && chapters.isEmpty) {
      fail("could not parse detail page", url: detailUrl);
    }

    anime.chapters = chapters.isEmpty
        ? [MChapter(name: "Open Details", url: detailUrl)]
        : chapters;
    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    var rawUrl = url;
    if (rawUrl.contains("resolve_ct") && rawUrl.contains("url=")) {
      final proxyParam = extractQueryParameter(rawUrl, "url");
      if (proxyParam.isNotEmpty) {
        rawUrl = Uri.decodeComponent(proxyParam);
      }
    }

    final video = MVideo()
      ..url = rawUrl
      ..originalUrl = rawUrl
      ..quality = rawUrl.startsWith("magnet:") ? "magnet" : "torrent";
    return [video];
  }

  String extractQueryParameter(String url, String key) {
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

  MPages parseListing(String res, String query) {
    final document = parseHtml(res);
    final rows = document.select("table.listing tr");
    final animeList = <MManga>[];
    final seen = <String>{};

    for (final row in rows) {
      final titleCell = row.selectFirst("td.desc-top");
      if (titleCell == null) {
        continue;
      }

      final categoryHref = row.selectFirst('td[rowspan] a')?.getHref ?? "";
      if (!isAnimeCategory(categoryHref)) {
        continue;
      }

      String name = "";
      for (final anchor in titleCell.select("a")) {
        final href = anchor.getHref;
        final text = anchor.text.trim();
        if (href.startsWith("magnet:") || text.isEmpty) {
          continue;
        }
        name = text;
        break;
      }

      // Get details URL from desc-top or web cell
      String detailsUrl = "";
      // First try: anchor in title cell that goes to /details/
      for (final anchor in titleCell.select("a")) {
        final href = anchor.getHref;
        if (href.contains("/details/") || href.contains("?id=")) {
          detailsUrl = href;
          break;
        }
      }
      // Second try: web cell with 'details' text
      if (detailsUrl.isEmpty) {
        final webCell = row.selectFirst("td.web");
        if (webCell != null) {
          for (final anchor in webCell.select("a")) {
            final href = anchor.getHref;
            final text = anchor.text.trim().toLowerCase();
            if (text.contains("details") && href.isNotEmpty) {
              detailsUrl = href;
              break;
            }
          }
        }
      }
      // Third try: any non-magnet anchor in the row
      if (detailsUrl.isEmpty) {
        for (final anchor in row.select("a[href]")) {
          final href = anchor.getHref;
          if (!href.startsWith("magnet:") && href.isNotEmpty && href != "/") {
            detailsUrl = href;
            break;
          }
        }
      }

      if (name.isEmpty || detailsUrl.isEmpty || seen.contains(detailsUrl)) {
        continue;
      }
      if (query.isNotEmpty &&
          !name.toLowerCase().contains(query.toLowerCase().trim())) {
        continue;
      }

      seen.add(detailsUrl);
      animeList.add(
        MManga()
          ..name = name
          ..link = normalizeUrl(detailsUrl),
      );
    }

    return MPages(animeList, false);
  }

  Map<String, String> parseDetails(document) {
    final labels = document.select("div.details li.detailsleft");
    final values = document.select("div.details li.detailsright");
    final details = <String, String>{};
    final pairCount = labels.length < values.length
        ? labels.length
        : values.length;

    for (var index = 0; index < pairCount; index++) {
      final label = labels[index].text.replaceAll(":", "").trim();
      final value = values[index].text.trim();
      if (label.isNotEmpty && value.isNotEmpty) {
        details[label] = value;
      }
    }

    return details;
  }

  String buildDescription(Map<String, String> details) {
    final parts = <String>[];
    addDetail(parts, "Torrent Type", details["Torrent Type"]);
    addDetail(parts, "Date Submitted", details["Date Submitted"]);
    addDetail(parts, "Filesize", details["Filesize"]);
    addDetail(parts, "Website", details["Website"]);
    addDetail(parts, "Submitter", details["Submitter"]);
    addDetail(parts, "Authorized", details["Authorized"]);
    addDetail(parts, "Comment", details["Comment"]);
    return parts.join("\n");
  }

  void addDetail(List<String> parts, String label, String? value) {
    if (value == null || value.isEmpty) {
      return;
    }
    parts.add("$label: $value");
  }

  bool isAnimeCategory(String href) {
    return href.contains("cat=1") ||
        href.contains("cat=7") ||
        href.contains("cat=11");
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
    final parts = <String>["Tokyo Toshokan: $context"];
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
    ];
  }
}

TokyoTosho main(MSource source) {
  return TokyoTosho(source: source);
}
