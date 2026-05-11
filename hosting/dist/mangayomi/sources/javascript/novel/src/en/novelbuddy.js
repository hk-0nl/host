const mangayomiSources = [
  {
    "name": "Novelbuddy",
    "id": 2507947282,
    "baseUrl": "https://novelbuddy.com",
    "lang": "en",
    "typeSource": "single",
    "iconUrl":
      "https://www.google.com/s2/favicons?sz=256&domain=https://novelbuddy.com/",
    "dateFormat": "",
    "dateFormatLocale": "",
    "isNsfw": false,
    "hasCloudflare": false,
    "sourceCodeUrl": "",
    "apiUrl": "",
    "version": "0.1.0",
    "isManga": false,
    "itemType": 2,
    "isFullData": false,
    "appMinVerReq": "0.5.0",
    "additionalParams": "",
    "sourceCodeLanguage": 1,
    "notes": "",
    "pkgPath": "novel/src/en/novelbuddy.js",
  },
];
class DefaultExtension extends MProvider {
  constructor() {
    super();
    this.client = new Client();
  }

  getPreference(key) {
    return new SharedPreferences().get(key);
  }

  getHeaders(url) {
    throw new Error("getHeaders not implemented");
  }

  absoluteUrl(url) {
    if (!url) return this.source.baseUrl;
    if (url.startsWith("http://") || url.startsWith("https://")) return url;
    if (url.startsWith("//")) return "https:" + url;
    return this.source.baseUrl + (url.startsWith("/") ? "" : "/") + url;
  }

  normalizeImageUrl(url) {
    if (!url) return "";
    if (url.startsWith("http://") || url.startsWith("https://")) return url;
    if (url.startsWith("//")) return "https:" + url;
    return this.absoluteUrl(url);
  }

  async request(slugOrUrl) {
    var url = this.absoluteUrl(slugOrUrl);
    var body = (await this.client.get(url, { "Connection": "close" })).body;
    return new Document(body);
  }

  getNextData(doc) {
    var scriptTag = doc.selectFirst("script#__NEXT_DATA__");
    if (!scriptTag || !scriptTag.text) return null;
    try {
      return JSON.parse(scriptTag.text);
    } catch (_) {
      return null;
    }
  }

  getPageProps(doc) {
    return this.getNextData(doc)?.props?.pageProps ?? {};
  }

  getStatusCode(status) {
    var normalized = (status || "").toLowerCase();
    if (normalized.includes("ongoing")) return 0;
    if (normalized.includes("completed")) return 1;
    if (normalized.includes("hiatus")) return 2;
    if (normalized.includes("dropped")) return 3;
    return 5;
  }

  buildSearchUrl({
    query = "",
    genres = [],
    status = "all",
    sort = "views",
    page = 1,
  } = {}) {
    var params = [];
    params.push("q=" + encodeURIComponent(query || ""));
    genres.forEach((genre) => {
      params.push("genre[]=" + encodeURIComponent((genre || "").toLowerCase()));
    });
    if (status) params.push("status=" + encodeURIComponent(status));
    if (sort) params.push("sort=" + encodeURIComponent(sort));
    params.push("page=" + encodeURIComponent(page.toString()));
    return "/search?" + params.join("&");
  }

  parseListItemsFromData(pageProps) {
    var candidates = [
      pageProps?.novels,
      pageProps?.mangas,
      pageProps?.results,
      pageProps?.items,
      pageProps?.data?.novels,
      pageProps?.data?.mangas,
      pageProps?.data?.results,
    ];
    for (var candidate of candidates) {
      if (!Array.isArray(candidate) || candidate.length === 0) continue;
      var list = [];
      candidate.forEach((item) => {
        var link =
          item?.url ||
          item?.link ||
          (item?.slug ? "/" + item.slug : "");
        var name = item?.name || item?.title || "";
        if (!link || !name) return;
        list.push({
          name: name,
          link: this.absoluteUrl(link),
          imageUrl: this.normalizeImageUrl(
            item?.cover || item?.thumbnail || item?.image || item?.poster || "",
          ),
        });
      });
      if (list.length > 0) return list;
    }
    return [];
  }

  parseListItemsFromDom(doc) {
    var list = [];
    doc.select("div.flex.flex-col.h-full").forEach((item) => {
      var linkElement = item.selectFirst("a.absolute.inset-0.z-0");
      var titleElement = item.selectFirst("a.link-hover");
      var imageElement = item.selectFirst("a.absolute.inset-0.z-0 img");
      var link = linkElement?.getHref || titleElement?.getHref || "";
      var name = titleElement?.text?.trim() || linkElement?.attr("title") || "";
      if (!link || !name) return;
      list.push({
        name: name,
        link: this.absoluteUrl(link),
        imageUrl: this.normalizeImageUrl(
          imageElement?.getSrc || imageElement?.attr("src") || imageElement?.attr("data-src") || "",
        ),
      });
    });
    return list;
  }

  detectHasNextPage(doc, currentPage) {
    var nextPatterns = [
      "a[rel=next]",
      "a[aria-label=Next]",
      "a[title=Next]",
    ];
    for (var selector of nextPatterns) {
      if (doc.selectFirst(selector)) return true;
    }

    var anchors = doc.select("a");
    for (var anchor of anchors) {
      var href = anchor.getHref || "";
      var text = (anchor.text || "").trim().toLowerCase();
      if (text === "next" || text === "›" || text === "»") return true;
      if (href.includes("page=" + (currentPage + 1).toString())) return true;
    }
    return false;
  }

  async searchPage({
    query = "",
    genres = [],
    status = "all",
    sort = "views",
    page = 1,
  } = {}) {
    var doc = await this.request(
      this.buildSearchUrl({ query, genres, status, sort, page }),
    );
    var pageProps = this.getPageProps(doc);
    var list = this.parseListItemsFromData(pageProps);
    if (list.length === 0) {
      list = this.parseListItemsFromDom(doc);
    }
    var hasNextPage = this.detectHasNextPage(doc, page);
    return { list, hasNextPage };
  }

  async getPopular(page) {
    return await this.searchPage({ sort: "popular", page: page });
  }

  async getLatestUpdates(page) {
    return await this.searchPage({ sort: "latest", page: page });
  }

  async search(query, page, filters) {
    function checkBox(state) {
      var rd = [];
      state.forEach((item) => {
        if (item.state) rd.push(item.value);
      });
      return rd;
    }
    function selectFilter(filter) {
      return filter.values[filter.state].value;
    }

    var hasFilters = Array.isArray(filters) && filters.length !== 0;
    var genres = hasFilters ? checkBox(filters[0].state) : [];
    var status = hasFilters ? selectFilter(filters[1]) : "all";
    var sort = hasFilters ? selectFilter(filters[2]) : "views";

    return await this.searchPage({ query, genres, status, sort, page });
  }

  extractSummaryText(summaryHtml, fallbackText) {
    if (summaryHtml) {
      try {
        var summaryDoc = new Document("<div>" + summaryHtml + "</div>");
        var summaryText = summaryDoc.selectFirst("div")?.text?.trim() || "";
        if (summaryText) return summaryText;
      } catch (_) {}
    }
    return fallbackText || "";
  }

  buildChaptersFromJson(manga) {
    var chapters = [];
    var chapterItems = Array.isArray(manga?.chapters) ? manga.chapters.slice() : [];
    var firstChapterUrl = manga?.firstChapter?.url || "";
    if (
      chapterItems.length > 1 &&
      firstChapterUrl &&
      chapterItems[0]?.url !== firstChapterUrl &&
      chapterItems[chapterItems.length - 1]?.url === firstChapterUrl
    ) {
      chapterItems.reverse();
    }
    chapterItems.forEach((item) => {
      var link = item?.url || "";
      var name = item?.name || "Chapter";
      if (!link) return;
      var updatedAt = item?.updatedAt || item?.date || "";
      chapters.push({
        name: name,
        url: this.absoluteUrl(link),
        dateUpload: updatedAt ? new Date(updatedAt).valueOf().toString() : "",
      });
    });
    return chapters;
  }

  buildChaptersFromDom(doc) {
    var chapters = [];
    doc.select("div.MangaDetails_chapterList__RPlPr a").forEach((item) => {
      var link = item.getHref || "";
      var name = item.selectFirst("h4")?.text?.trim() || item.text?.trim() || "Chapter";
      var dateText = item.selectFirst("span")?.text?.trim() || "";
      chapters.push({
        name: name,
        url: this.absoluteUrl(link),
        dateUpload: dateText ? new Date(dateText).valueOf().toString() : "",
      });
    });
    return chapters;
  }

  async getDetail(url) {
    var link = this.absoluteUrl(url);
    var doc = await this.request(link);
    var pageProps = this.getPageProps(doc);
    var manga = pageProps?.initialManga || pageProps?.manga || {};

    var name = manga?.name || doc.selectFirst("h1")?.text?.trim() || "NovelBuddy";
    var imageUrl = this.normalizeImageUrl(
      manga?.cover ||
        manga?.image ||
        doc.selectFirst("a.group img")?.getSrc ||
        doc.selectFirst("a.group img")?.attr("src") ||
        "",
    );
    var statusText = manga?.status || "";
    if (!statusText) {
      doc.select("div.MangaDetails_statItem__Ore65").forEach((item) => {
        var text = (item.text || "").trim();
        if (!statusText && (text.includes("OnGoing") || text.includes("Completed"))) {
          statusText = text;
        }
      });
    }

    var genre = [];
    (Array.isArray(manga?.genres) ? manga.genres : []).forEach((entry) => {
      if (entry?.name) genre.push(entry.name);
    });
    if (genre.length === 0) {
      doc.select("a.badge.badge-outline").forEach((entry) => {
        var value = entry.text?.trim() || "";
        if (value) genre.push(value);
      });
    }

    var author = "";
    if (Array.isArray(manga?.authors) && manga.authors.length > 0) {
      author = manga.authors.map((entry) => entry?.name || "").filter(Boolean).join(", ");
    }

    var description = this.extractSummaryText(
      manga?.summary || "",
      doc.selectFirst("div.MangaDetails_descriptionCard__a9qhD")?.text?.trim() || "",
    );

    var chapters = this.buildChaptersFromJson(manga);
    if (chapters.length === 0) {
      chapters = this.buildChaptersFromDom(doc);
    }

    return {
      name,
      imageUrl,
      description,
      link,
      status: this.getStatusCode(statusText),
      genre,
      author,
      chapters,
    };
  }

  async getHtmlContent(name, url) {
    var doc = await this.request(url);
    var pageProps = this.getPageProps(doc);
    var chapter = pageProps?.initialChapter || pageProps?.chapter || {};
    var content = chapter?.content || "";
    if (!content) {
      content =
        doc.selectFirst("div.novel-tts-content")?.html ||
        doc.selectFirst("div.content-inner")?.html ||
        "";
    }
    return this.cleanHtmlContent(content, chapter?.name || name || "");
  }

  async cleanHtmlContent(html, title = "") {
    var cleaned = (html || "")
      .replace(/<script[\s\S]*?<\/script>/gi, "")
      .replace(/<style[\s\S]*?<\/style>/gi, "")
      .replace(/<div[^>]*text-align:center[^>]*>[\s\S]*?<\/div>/gi, "")
      .trim();
    if (!cleaned) return "";
    if (!title) return cleaned;
    return "<h2>" + title + "</h2><hr><br>" + cleaned;
  }

  getFilterList() {
    function formateState(type_name, items, values) {
      var state = [];
      for (var i = 0; i < items.length; i++) {
        state.push({ type_name: type_name, name: items[i], value: values[i] });
      }
      return state;
    }

    var filters = [];
    var items = [];
    var values = [];

    // Genres
    items = [
      "Action",
      "Action Adventure",
      "ActionAdventure",
      "Adult",
      "Adventcure",
      "Adventure",
      "Adventurer",
      "Anime u0026 Comics",
      "Bender",
      "Booku0026Literature",
      "Chinese",
      "Comed",
      "Comedy",
      "Cultivation",
      "Drama",
      "dventure",
      "Eastern",
      "Ecchi",
      "Ecchi Fantasy",
      "Fan-Fiction",
      "Fanfiction",
      "Fantas",
      "Fantasy",
      "FantasyAction",
      "Game",
      "Games",
      "Gender",
      "Gender Bender",
      "Harem",
      "HaremAction",
      "Haremv",
      "Historica",
      "Historical",
      "History",
      "Horror",
      "Isekai",
      "Josei",
      "Light Novel",
      "Litrpg",
      "Lolicon",
      "Magic",
      "Martial",
      "Martial Arts",
      "Mature",
      "Mecha",
      "Military",
      "Modern Life",
      "Movies",
      "Myster",
      "Mystery",
      "Mystery.Adventure",
      "Psychologic",
      "Psychological",
      "Reincarnatio",
      "Reincarnation",
      "Romanc",
      "Romance",
      "Romance.Adventure",
      "Romance.Harem",
      "Romance.Smut",
      "RomanceAction",
      "Romancem",
      "School Life",
      "Sci-fi",
      "Seinen",
      "Seinen Wuxia",
      "Shoujo",
      "Shoujo Ai",
      "Shounen",
      "Shounen Ai",
      "Slice of Lif",
      "Slice Of Life",
      "Slice of Lifel",
      "Smut",
      "Sports",
      "Superna",
      "Supernatural",
      "System",
      "Thriller",
      "Tragedy",
      "Urban",
      "Urban Life",
      "Wuxia",
      "Xianxia",
      "Xuanhuan",
      "Yaoi",
      "Yuri",
    ];

    values = [
      "action",
      "action-adventure",
      "actionadventure",
      "adult",
      "adventcure",
      "adventure",
      "adventurer",
      "anime-u0026-comics",
      "bender",
      "booku0026literature",
      "chinese",
      "comed",
      "comedy",
      "cultivation",
      "drama",
      "dventure",
      "eastern",
      "ecchi",
      "ecchi-fantasy",
      "fan-fiction",
      "fanfiction",
      "fantas",
      "fantasy",
      "fantasyaction",
      "game",
      "games",
      "gender",
      "gender-bender",
      "harem",
      "haremaction",
      "haremv",
      "historica",
      "historical",
      "history",
      "horror",
      "isekai",
      "josei",
      "light-novel",
      "litrpg",
      "lolicon",
      "magic",
      "martial",
      "martial-arts",
      "mature",
      "mecha",
      "military",
      "modern-life",
      "movies",
      "myster",
      "mystery",
      "mystery-adventure",
      "psychologic",
      "psychological",
      "reincarnatio",
      "reincarnation",
      "romanc",
      "romance",
      "romance-adventure",
      "romance-harem",
      "romance-smut",
      "romanceaction",
      "romancem",
      "school-life",
      "sci-fi",
      "seinen",
      "seinen-wuxia",
      "shoujo",
      "shoujo-ai",
      "shounen",
      "shounen-ai",
      "slice-of-lif",
      "slice-of-life",
      "slice-of-lifel",
      "smut",
      "sports",
      "superna",
      "supernatural",
      "system",
      "thriller",
      "tragedy",
      "urban",
      "urban-life",
      "wuxia",
      "xianxia",
      "xuanhuan",
      "yaoi",
      "yuri",
    ];
    filters.push({
      type_name: "GroupFilter",
      name: "Genres",
      state: formateState("CheckBox", items, values),
    });

    // Status
    items = ["All", "Ongoing", "Completed"];
    values = ["all", "ongoing", "completed"];
    filters.push({
      type_name: "SelectFilter",
      name: "Status",
      state: 0,
      values: formateState("SelectOption", items, values),
    });

    // Sort order
    items = ["Views", "Latest", "Popular", "Rating", "Chapters", "Name A-Z"];
    values = ["views", "latest", "popular", "rating", "chapters", "alphabetical"];
    filters.push({
      type_name: "SelectFilter",
      name: "Order by",
      state: 0,
      values: formateState("SelectOption", items, values),
    });

    return filters;
  }

  getSourcePreferences() {
    throw new Error("getSourcePreferences not implemented");
  }
}
