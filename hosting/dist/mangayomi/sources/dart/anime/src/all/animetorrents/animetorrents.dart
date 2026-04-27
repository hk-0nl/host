import 'package:mangayomi/bridge_lib.dart';

class AnimeTorrents extends MProvider {
  AnimeTorrents({required this.source});

  final MSource source;

  @override
  Future getPopular(int page) async {
    fail(
      "browse is not implemented yet; configure session settings first and use this source only for authenticated parser work",
    );
  }

  @override
  Future getLatestUpdates(int page) async {
    fail(
      "latest updates are not implemented yet; authenticated parsing is still pending",
    );
  }

  @override
  Future search(String query, int page, FilterList filterList) async {
    fail(
      "search is not implemented yet; authenticated parsing is still pending",
    );
  }

  @override
  Future getDetail(String url) async {
    final anime = MManga();
    anime.name = "AnimeTorrents";
    anime.description =
        "Configurable auth scaffold. AnimeTorrents is a private tracker and still needs site-specific authenticated parsing, but you can now store the domain, cookie header, and user agent needed for a logged-in session.";
    anime.chapters = [MChapter(name: "Login Required", url: url)];
    return anime;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    fail(
      "video/torrent resolution is not implemented yet; this source is still an auth scaffold",
      url: url,
    );
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
        key: "cookie_header",
        title: "Cookie Header",
        summary:
            "Paste a logged-in Cookie header when you are ready to test authenticated requests.",
        value: "",
        dialogTitle: "Cookie Header",
        dialogMessage: "",
      ),
      EditTextPreference(
        key: "user_agent",
        title: "User Agent",
        summary: "Optional custom User-Agent for tracker requests.",
        value: "",
        dialogTitle: "User Agent",
        dialogMessage: "",
      ),
    ];
  }

  Never fail(String context, {String? url}) {
    final parts = <String>["AnimeTorrents: $context"];
    if (url != null && url.isNotEmpty) {
      parts.add(url);
    }
    final message = parts.join(" | ");
    print(message);
    throw Exception(message);
  }
}

AnimeTorrents main(MSource source) {
  return AnimeTorrents(source: source);
}
