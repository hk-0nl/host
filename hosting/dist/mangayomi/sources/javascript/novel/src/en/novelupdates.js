const DEFAULT_USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

const mangayomiSources = [{
  "name": "Novel Updates",
  "lang": "en",
  "baseUrl": "https://www.novelupdates.com",
  "apiUrl": "",
  "iconUrl": "https://www.novelupdates.com/favicon.ico",
  "typeSource": "single",
  "itemType": 2,
  "version": "0.0.8",
  "dateFormat": "",
  "dateFormatLocale": "",
  "pkgPath": "sources/javascript/novel/src/en/novelupdates.js",
  "isNsfw": false,
  "hasCloudflare": true,
  "notes": "Manual cookies may be required for Cloudflare/login."
}];

class DefaultExtension extends MProvider {
  get supportsLatest() {
    return true;
  }

  getHeaders(url) {
    return this.buildHeaders(url);
  }

  getBaseUrl() {
    const value = new SharedPreferences().getString(
      "domain_url",
      this.source.baseUrl,
    );
    return (value || this.source.baseUrl).replace(/\/+$/, "");
  }

  getUserAgent() {
    return new SharedPreferences().getString("user_agent", DEFAULT_USER_AGENT);
  }

  getCookieHeader() {
    return (new SharedPreferences().getString("cookie_header", "") || "").trim();
  }

  buildHeaders(url) {
    const baseUrl = this.getBaseUrl();
    const headers = {
      Referer: baseUrl,
      Origin: baseUrl,
      Connection: "keep-alive",
      Accept: "*/*",
      "Accept-Language": "*",
      "Accept-Encoding": "gzip, deflate",
      "Sec-Fetch-Mode": "cors",
      "User-Agent": this.getUserAgent(),
    };
    const cookie = this.getCookieHeader();
    if (cookie) {
      headers.Cookie = cookie;
    }
    return headers;
  }

  buildReaderHeaders() {
    return {
      Priority: "u=0, i",
      "User-Agent": this.getUserAgent(),
    };
  }

  getManualAuthMessage() {
    return "Novel Updates blocked the request. Open Novel Updates in Mangayomi webview and complete the challenge, or paste a valid cookie_header and matching user_agent in source settings.";
  }

  isChallengeBody(body) {
    const html = (body || "").toLowerCase();
    return (
      html.includes("just a moment") ||
      html.includes("__cf_chl_") ||
      html.includes("enable javascript and cookies to continue")
    );
  }

  async requestPage(url) {
    const res = await new Client().get(url, this.buildHeaders(url));
    if (res.statusCode === 403 || this.isChallengeBody(res.body)) {
      throw new Error(this.getManualAuthMessage());
    }
    return res;
  }

  async requestForm(url, body) {
    const headers = {
      "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
      ...this.buildHeaders(url),
    };
    const res = await new Client().post(url, headers, body);
    if (res.statusCode === 403 || this.isChallengeBody(res.body)) {
      throw new Error(this.getManualAuthMessage());
    }
    return res;
  }

  absoluteUrl(url) {
    if (!url) return this.getBaseUrl();
    if (url.startsWith("http://") || url.startsWith("https://")) return url;
    if (url.startsWith("//")) return `https:${url}`;
    return `${this.getBaseUrl()}${url.startsWith("/") ? "" : "/"}${url}`;
  }

  mangaListFromPage(res) {
    const doc = new Document(res.body);
    const mangaElements = doc.select("div.search_main_box_nu");
    const list = [];
    for (const element of mangaElements) {
      const linkElement = element.selectFirst(".search_title > a");
      const link = linkElement?.getHref;
      if (!link) continue;
      list.push({
        name: linkElement.text?.trim(),
        imageUrl: element.selectFirst("img")?.getSrc,
        link: this.absoluteUrl(link),
      });
    }
    const hasNextPage = doc.selectFirst("div.digg_pagination > a.next_page") != null;
    return { list, hasNextPage };
  }

  toStatus(status) {
    const normalized = (status || "").toLowerCase();
    if (normalized.includes("ongoing")) return 0;
    if (normalized.includes("completed")) return 1;
    if (normalized.includes("hiatus")) return 2;
    if (normalized.includes("dropped")) return 3;
    return 5;
  }

  async getPopular(page) {
    const res = await this.requestPage(
      `${this.getBaseUrl()}/series-ranking/?rank=popmonth&pg=${page}`,
    );
    return this.mangaListFromPage(res);
  }

  async getLatestUpdates(page) {
    const res = await this.requestPage(
      `${this.getBaseUrl()}/series-finder/?sf=1&sh=&sort=sdate&order=desc&pg=${page}`,
    );
    return this.mangaListFromPage(res);
  }

  async search(query, page, filters) {
    let url = `${this.getBaseUrl()}/series-finder/?sf=1&sh=${encodeURIComponent(query)}&pg=${page}`;

    if (filters?.length > 0) {
      if (filters[0].state.filter((f) => f.state === true).length > 0) {
        const values = filters[0].state
          .filter((f) => f.state === true)
          .map((f) => f.value)
          .join(",");
        url += `&nt=${values}`;
      }

      if (filters[1].state.filter((f) => f.state === true).length > 0) {
        const values = filters[1].state
          .filter((f) => f.state === true)
          .map((f) => f.value)
          .join(",");
        url += `&org=${values}`;
      }

      if (filters[2].state.filter((f) => f.state === 1 || f.state === 2).length > 0) {
        const including = filters[2].state
          .filter((f) => f.state === 1)
          .map((f) => f.value)
          .join(",");
        const excluding = filters[2].state
          .filter((f) => f.state === 2)
          .map((f) => f.value)
          .join(",");
        if (including.length > 0) url += `&gi=${including}`;
        if (excluding.length > 0) url += `&ge=${excluding}`;
      }

      if (filters[3].state.filter((f) => f.state === true).length > 0) {
        const values = filters[3].state
          .filter((f) => f.state === true)
          .map((f) => f.value)
          .join(",");
        url += `&ss=${values}`;
      }

      url += `&sort=${filters[4].values[filters[4].state].value}`;
      url += `&order=${filters[5].values[filters[5].state].value}`;
    }

    const res = await this.requestPage(url);
    return this.mangaListFromPage(res);
  }

  async getDetail(url) {
    const res = await this.requestPage(this.absoluteUrl(url));
    const doc = new Document(res.body);
    const imageUrl = doc.selectFirst(".wpb_wrapper img")?.getSrc;
    const type = doc.selectFirst("#showtype")?.text?.trim() || "";
    const description =
      `${doc.selectFirst("#editdescription")?.text?.trim() || ""}\n\nType: ${type}`.trim();
    const author = doc.select("#authtag").map((el) => el.text.trim()).join(", ");
    const artist = doc.select("#artiststag").map((el) => el.text.trim()).join(", ");
    const status = this.toStatus(doc.selectFirst("#editstatus")?.text?.trim() || "");
    const genre = doc.select("#seriesgenre > a").map((el) => el.text.trim());
    const novelId = doc.selectFirst("input#mypostid")?.attr("value");

    if (!novelId) {
      throw new Error("Novel Updates detail page did not expose a novel id.");
    }

    const chapterRes = await this.requestForm(
      `${this.getBaseUrl()}/wp-admin/admin-ajax.php`,
      {
        action: "nd_getchapters",
        mygrr: "0",
        mypostid: novelId,
      },
    );
    const chapterDoc = new Document(chapterRes.body);
    const nameReplacements = {
      v: "Volume ",
      c: " Chapter ",
      part: "Part ",
      ss: "SS",
    };

    const chapters = [];
    for (const el of chapterDoc.select("li.sp_li_chp")) {
      let chapterName = el.selectFirst("span")?.text || "Chapter";
      for (const name in nameReplacements) {
        chapterName = chapterName.replace(name, nameReplacements[name]);
      }
      const anchors = el.select("a");
      const chapterAnchor = anchors.length > 1 ? anchors[1] : anchors[0];
      const chapterUrl = chapterAnchor?.getHref;
      if (!chapterUrl) continue;
      chapters.push({
        name: chapterName.replace(/\b\w/g, (letter) => letter.toUpperCase()).trim(),
        url: this.absoluteUrl(chapterUrl),
        dateUpload: String(Date.now()),
        scanlator: null,
      });
    }

    return {
      imageUrl,
      description,
      genre,
      author,
      artist,
      status,
      chapters,
    };
  }

  async getHtmlContent(name, url) {
    const res = await new Client().get(this.absoluteUrl(url), this.buildReaderHeaders());
    return this.cleanHtmlContent(res.body);
  }

  pickFirstText(doc, selectors) {
    for (const selector of selectors) {
      const value = doc.selectFirst(selector)?.text?.trim();
      if (value) return value;
    }
    return "";
  }

  pickFirstHtml(doc, selectors) {
    for (const selector of selectors) {
      const value = doc.selectFirst(selector)?.innerHtml;
      if (value) return value;
    }
    return "";
  }

  async cleanHtmlContent(html) {
    const doc = new Document(html);
    const title = this.pickFirstText(doc, [
      ".chapter-title",
      ".chapter__title",
      ".entry-title",
      ".entry-title-main",
      ".sp-title",
      ".title-content",
      "#chapter-title",
      "#chapter-heading",
      "head title",
      "h1",
    ]);
    const content = this.pickFirstHtml(doc, [
      ".chp_raw",
      ".chapter-content",
      ".chapter__content",
      ".entry-content",
      ".post-body",
      ".content",
      ".reader-content",
      ".rdminimal",
      "#chapter-content",
      "#content",
      ".main-content",
      "article.post",
      "main article",
    ]);

    if (!content) {
      return "<p>Failed to extract chapter content automatically.</p>";
    }

    return `<h2>${title}</h2><hr><br>${content}`;
  }

  getFilterList() {
    return [
      {
        type_name: "GroupFilter",
        name: "Novel Type",
        state: [
          { type_name: "CheckBox", name: "Web Novel", value: "2444" },
          { type_name: "CheckBox", name: "Light Novel", value: "2443" },
          { type_name: "CheckBox", name: "Published Novel", value: "26874" },
        ],
      },
      {
        type_name: "GroupFilter",
        name: "Original Language",
        state: [
          { type_name: "CheckBox", name: "Chinese", value: "495" },
          { type_name: "CheckBox", name: "Filipino", value: "9181" },
          { type_name: "CheckBox", name: "Indonesian", value: "9179" },
          { type_name: "CheckBox", name: "Japanese", value: "496" },
          { type_name: "CheckBox", name: "Khmer", value: "18657" },
          { type_name: "CheckBox", name: "Korean", value: "497" },
          { type_name: "CheckBox", name: "Malaysian", value: "9183" },
          { type_name: "CheckBox", name: "Thai", value: "9954" },
          { type_name: "CheckBox", name: "Vietnamese", value: "9177" },
        ],
      },
      {
        type_name: "GroupFilter",
        name: "Genre",
        state: [
          { type_name: "TriState", name: "Action", value: "8" },
          { type_name: "TriState", name: "Adventure", value: "13" },
          { type_name: "TriState", name: "Comedy", value: "17" },
          { type_name: "TriState", name: "Drama", value: "9" },
          { type_name: "TriState", name: "Ecchi", value: "292" },
          { type_name: "TriState", name: "Fantasy", value: "5" },
          { type_name: "TriState", name: "Gender Bender", value: "168" },
          { type_name: "TriState", name: "Harem", value: "3" },
          { type_name: "TriState", name: "Horror", value: "343" },
          { type_name: "TriState", name: "Josei", value: "324" },
          { type_name: "TriState", name: "Martial Arts", value: "14" },
          { type_name: "TriState", name: "Mature", value: "4" },
          { type_name: "TriState", name: "Mecha", value: "10" },
          { type_name: "TriState", name: "Mystery", value: "245" },
          { type_name: "TriState", name: "Psychological", value: "486" },
          { type_name: "TriState", name: "Romance", value: "15" },
          { type_name: "TriState", name: "School", value: "6" },
          { type_name: "TriState", name: "Sci-Fi", value: "11" },
          { type_name: "TriState", name: "Seinen", value: "18" },
          { type_name: "TriState", name: "Shoujo", value: "157" },
          { type_name: "TriState", name: "Shoujo Ai", value: "851" },
          { type_name: "TriState", name: "Shounen", value: "12" },
          { type_name: "TriState", name: "Shounen Ai", value: "1692" },
          { type_name: "TriState", name: "Slice of Life", value: "7" },
          { type_name: "TriState", name: "Smut", value: "281" },
          { type_name: "TriState", name: "Sports", value: "1357" },
          { type_name: "TriState", name: "Supernatural", value: "16" },
          { type_name: "TriState", name: "Tragedy", value: "132" },
          { type_name: "TriState", name: "Wuxia", value: "479" },
          { type_name: "TriState", name: "Xianxia", value: "480" },
          { type_name: "TriState", name: "Xuanhuan", value: "3954" },
          { type_name: "TriState", name: "Yaoi", value: "560" },
          { type_name: "TriState", name: "Yuri", value: "922" },
        ],
      },
      {
        type_name: "GroupFilter",
        name: "Status",
        state: [
          { type_name: "CheckBox", name: "All", value: "" },
          { type_name: "CheckBox", name: "Completed", value: "2" },
          { type_name: "CheckBox", name: "Ongoing", value: "3" },
          { type_name: "CheckBox", name: "Hiatus", value: "4" },
        ],
      },
      {
        type_name: "SelectFilter",
        type: "sort",
        name: "Sort",
        state: 0,
        values: [
          { type_name: "SelectOption", name: "Last Updated", value: "sdate" },
          { type_name: "SelectOption", name: "Rating", value: "srate" },
          { type_name: "SelectOption", name: "Rank", value: "srank" },
          { type_name: "SelectOption", name: "Reviews", value: "sreview" },
          { type_name: "SelectOption", name: "Chapters", value: "srel" },
          { type_name: "SelectOption", name: "Title", value: "abc" },
          { type_name: "SelectOption", name: "Readers", value: "sread" },
          { type_name: "SelectOption", name: "Frequency", value: "sfrel" },
        ],
      },
      {
        type_name: "SelectFilter",
        name: "Order",
        state: 0,
        values: [
          { type_name: "SelectOption", name: "Descending", value: "desc" },
          { type_name: "SelectOption", name: "Ascending", value: "asc" },
        ],
      },
    ];
  }

  getSourcePreferences() {
    const prefs = new SharedPreferences();
    const baseUrl = prefs.getString("domain_url", this.source.baseUrl) || this.source.baseUrl;
    const cookie = prefs.getString("cookie_header", "") || "";
    const userAgent = prefs.getString("user_agent", DEFAULT_USER_AGENT) || DEFAULT_USER_AGENT;
    return [
      {
        key: "domain_url",
        editTextPreference: {
          title: "Base URL",
          summary: "Use this only if Novel Updates moves to a new domain.",
          value: baseUrl,
          dialogTitle: "Novel Updates base URL",
          dialogMessage: "Enter the full site URL, including https://",
          text: baseUrl,
        },
      },
      {
        key: "cookie_header",
        editTextPreference: {
          title: "Cookie header",
          summary: "Optional but often required. Paste a Cookie header from a browser session that already passed Cloudflare/login.",
          value: cookie,
          dialogTitle: "Cookie header",
          dialogMessage: "Paste the full Cookie header value from a browser session that can open Novel Updates.",
          text: cookie,
        },
      },
      {
        key: "user_agent",
        editTextPreference: {
          title: "User-Agent",
          summary: "Optional. Match this to the browser session paired with your cookie.",
          value: userAgent,
          dialogTitle: "User-Agent",
          dialogMessage: "Paste the User-Agent value used by the browser session paired with your cookie.",
          text: userAgent,
        },
      },
    ];
  }
}
