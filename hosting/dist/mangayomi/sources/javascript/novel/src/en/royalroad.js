const mangayomiSources = [{
  "name": "Royal Road",
  "id": 2021112861,
  "baseUrl": "https://www.royalroad.com",
  "lang": "en",
  "typeSource": "single",
  "iconUrl": "https://www.royalroad.com/favicon.ico",
  "dateFormat": "",
  "dateFormatLocale": "",
  "isNsfw": false,
  "hasCloudflare": false,
  "sourceCodeUrl": "sources/javascript/novel/src/en/royalroad.js",
  "apiUrl": "",
  "version": "1.0.0",
  "isManga": false,
  "itemType": 2,
  "isFullData": false,
  "appMinVerReq": "0.5.0",
  "additionalParams": "",
  "sourceCodeLanguage": 1,
  "notes": "Web fiction platform. No auth required for public browsing."
}];

class DefaultExtension extends MProvider {
  get supportsLatest() {
    return true;
  }

  getHeaders() {
    return {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.5",
      "Connection": "close",
    };
  }

  absoluteUrl(url) {
    if (!url) return this.source.baseUrl;
    if (url.startsWith("http://") || url.startsWith("https://")) return url;
    return this.source.baseUrl + (url.startsWith("/") ? "" : "/") + url;
  }

  // Parse the fiction list from a best-rated/search/trending HTML page.
  // Items are .fiction-list-item rows.
  fictionListFromPage(doc) {
    const items = doc.select("div.fiction-list-item");
    const list = [];
    for (const el of items) {
      const anchor = el.selectFirst("h2.fiction-title a");
      if (!anchor) continue;
      const link = anchor.getHref;
      if (!link) continue;
      list.push({
        name: (anchor.text || "").trim(),
        imageUrl: el.selectFirst("figure img")?.getSrc || "",
        link: this.absoluteUrl(link),
      });
    }
    const hasNextPage = doc.selectFirst("ul.pagination li.next") != null ||
      doc.selectFirst("a[rel=next]") != null;
    return { list, hasNextPage };
  }

  async getPopular(page) {
    const url = this.source.baseUrl + "/fictions/best-rated?page=" + page;
    const res = await new Client().get(url, this.getHeaders());
    return this.fictionListFromPage(new Document(res.body));
  }

  async getLatestUpdates(page) {
    const url = this.source.baseUrl + "/fictions/latest-updates?page=" + page;
    const res = await new Client().get(url, this.getHeaders());
    return this.fictionListFromPage(new Document(res.body));
  }

  async search(query, page, filters) {
    // Use the search endpoint; RR search is HTML-rendered
    let url = this.source.baseUrl + "/fictions/search?title=" +
      encodeURIComponent(query) + "&page=" + page;

    if (filters && filters.length > 0 && filters[0].state) {
      // sort
      const sortFilter = filters[0];
      if (sortFilter.values && sortFilter.values[sortFilter.state]) {
        url += "&orderby=" + sortFilter.values[sortFilter.state].value;
      }
    }

    const res = await new Client().get(url, this.getHeaders());
    return this.fictionListFromPage(new Document(res.body));
  }

  toStatus(text) {
    const t = (text || "").toLowerCase();
    if (t.includes("ongoing") || t.includes("ongoing")) return 0;
    if (t.includes("completed") || t.includes("complete")) return 1;
    if (t.includes("hiatus")) return 2;
    if (t.includes("dropped")) return 3;
    return 5;
  }

  async getDetail(url) {
    const absUrl = this.absoluteUrl(url);
    const res = await new Client().get(absUrl, this.getHeaders());
    const doc = new Document(res.body);

    const imageUrl = doc.selectFirst(".cover-art-container img")?.getSrc ||
      doc.selectFirst("figure img")?.getSrc || "";

    // Author: first profile link inside the fiction header area
    const authorAnchor = doc.selectFirst(".fic-header a[href*='/profile/']") ||
      doc.selectFirst("a[href*='/profile/']");
    const author = (authorAnchor?.text || "").trim();

    // Description
    const descEl = doc.selectFirst(".description .hidden-content") ||
      doc.selectFirst(".description");
    const description = (descEl?.text || "").trim();

    // Genres
    const genreEls = doc.select("a[href*='/fictions/search?tagsAdd']");
    const genre = [];
    for (const el of genreEls) {
      const t = (el.text || "").trim();
      if (t) genre.push(t);
    }

    // Status — look for label containing "Completed" / "Ongoing" / "Hiatus"
    const labels = doc.select(".label");
    let statusText = "";
    for (const lbl of labels) {
      const t = (lbl.text || "").trim().toLowerCase();
      if (t.includes("completed") || t.includes("ongoing") || t.includes("hiatus") || t.includes("dropped")) {
        statusText = t;
        break;
      }
    }
    const status = this.toStatus(statusText);

    // Chapters — table#chapters tr (first row is thead)
    const rows = doc.select("table#chapters tr");
    const chapters = [];
    // rows[0] is header; chapter rows are rest, listed oldest→newest typically
    // We reverse to present newest first
    const chapterRows = [];
    for (let i = 1; i < rows.length; i++) {
      chapterRows.push(rows[i]);
    }
    chapterRows.reverse();

    for (const row of chapterRows) {
      const anchor = row.selectFirst("a");
      if (!anchor) continue;
      const chUrl = anchor.getHref;
      if (!chUrl) continue;
      const name = (anchor.text || "").trim();
      const timeEl = row.selectFirst("time");
      const dateStr = timeEl ? timeEl.attr("datetime") : "";
      const dateMs = dateStr ? String(new Date(dateStr).getTime()) : String(Date.now());
      chapters.push({
        name: name,
        url: this.absoluteUrl(chUrl),
        dateUpload: dateMs,
        scanlator: null,
      });
    }

    return {
      imageUrl,
      description,
      genre,
      author,
      artist: author,
      status,
      chapters,
    };
  }

  async getHtmlContent(name, url) {
    const res = await new Client().get(this.absoluteUrl(url), this.getHeaders());
    const doc = new Document(res.body);
    const title = (doc.selectFirst(".chapter-title")?.text ||
      doc.selectFirst("h1")?.text || name || "").trim();
    const contentEl = doc.selectFirst(".chapter-content") ||
      doc.selectFirst("#chapter-content") ||
      doc.selectFirst(".chapter__content");
    const content = contentEl ? contentEl.outerHtml : "<p>Failed to load chapter.</p>";
    return "<h2>" + title + "</h2><hr><br>" + content;
  }

  getFilterList() {
    return [
      {
        type_name: "SelectFilter",
        name: "Sort By",
        state: 0,
        values: [
          { type_name: "SelectOption", name: "Best Rated", value: "rating" },
          { type_name: "SelectOption", name: "Trending", value: "trending" },
          { type_name: "SelectOption", name: "Latest Updates", value: "last_update" },
          { type_name: "SelectOption", name: "Followers", value: "followers" },
          { type_name: "SelectOption", name: "Views", value: "views" },
        ],
      },
    ];
  }

  getSourcePreferences() {
    return [];
  }
}
