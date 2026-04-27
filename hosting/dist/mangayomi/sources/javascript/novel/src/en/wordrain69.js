const DEFAULT_USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

const mangayomiSources = [{
  "name": "Wordrain69",
  "lang": "en",
  "baseUrl": "https://wordrain69.com",
  "apiUrl": "",
  "iconUrl": "https://wordrain69.com/favicon.ico",
  "typeSource": "single",
  "itemType": 2,
  "version": "0.0.8",
  "dateFormat": "",
  "dateFormatLocale": "",
  "pkgPath": "sources/javascript/novel/src/en/wordrain69.js",
  "isNsfw": false,
  "hasCloudflare": true,
  "notes": "Premium chapters require manual cookies. Cloudflare is enabled."
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
      Referer: `${baseUrl}/`,
      Origin: baseUrl,
      Connection: "keep-alive",
      "User-Agent": this.getUserAgent(),
    };
    const cookie = this.getCookieHeader();
    if (cookie) {
      headers.Cookie = cookie;
    }
    return headers;
  }

  absoluteUrl(url) {
    if (!url) return this.getBaseUrl();
    if (url.startsWith("http://") || url.startsWith("https://")) return url;
    return `${this.getBaseUrl()}${url.startsWith("/") ? "" : "/"}${url}`;
  }

  buildLibraryUrl(order, page) {
    const pageSegment = page > 1 ? `page/${page}/` : "";
    return `${this.getBaseUrl()}/manga/${pageSegment}?m_orderby=${order}`;
  }

  buildSearchUrl(query, page) {
    let url =
      `${this.getBaseUrl()}/?s=${encodeURIComponent(query)}&post_type=wp-manga`;
    if (page > 1) {
      url += `&paged=${page}`;
    }
    return url;
  }

  parseImage(element) {
    const image = element?.selectFirst("img");
    return (
      image?.attr("data-src") ||
      image?.attr("data-lazy-src") ||
      image?.attr("data-srcset")?.split(" ")[0] ||
      image?.getSrc ||
      null
    );
  }

  mangaListFromPage(res) {
    const doc = new Document(res.body);
    const seen = new Set();
    const list = [];

    // Layout 1: /manga/ browse pages
    for (const element of doc.select("div.page-item-detail, div.c-tabs-item__content")) {
      // Try browse-page link first (.post-title a or .item-thumb a)
      let linkEl =
        element.selectFirst(".post-title a") ||
        element.selectFirst(".item-thumb a") ||
        element.selectFirst(".tab-thumb a");
      const link = linkEl?.getHref;
      if (!link || seen.has(link)) continue;
      seen.add(link);
      const name =
        linkEl?.attr("title") ||
        linkEl?.text?.trim() ||
        element.selectFirst(".post-title")?.text?.trim();
      const img = element.selectFirst("img");
      const imageUrl =
        img?.attr("data-src") ||
        img?.attr("data-lazy-src") ||
        img?.attr("data-srcset")?.split(" ")[0] ||
        img?.getSrc ||
        null;
      list.push({ name, imageUrl, link: this.absoluteUrl(link) });
    }

    const hasNextPage =
      doc.selectFirst(".nav-links .next") != null ||
      doc.selectFirst(".wp-pagenavi .nextpostslink") != null ||
      doc.selectFirst("a.next.page-numbers") != null;
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

  parseDate(date) {
    if (!date) return null;
    const parsed = Date.parse(date);
    if (Number.isNaN(parsed)) return null;
    return String(parsed);
  }

  async getPopular(page) {
    const res = await new Client().get(
      this.buildLibraryUrl("views", page),
      this.buildHeaders(this.getBaseUrl()),
    );
    return this.mangaListFromPage(res);
  }

  async getLatestUpdates(page) {
    const res = await new Client().get(
      this.buildLibraryUrl("latest", page),
      this.buildHeaders(this.getBaseUrl()),
    );
    return this.mangaListFromPage(res);
  }

  async search(query, page, filters) {
    const res = await new Client().get(
      this.buildSearchUrl(query, page),
      this.buildHeaders(this.getBaseUrl()),
    );
    return this.mangaListFromPage(res);
  }

  async getDetail(url) {
    const client = new Client();
    const res = await client.get(this.absoluteUrl(url), this.buildHeaders(url));
    const doc = new Document(res.body);
    const image = doc.selectFirst("div.summary_image img");
    const imageUrl =
      image?.attr("data-src") ||
      image?.attr("data-lazy-src") ||
      image?.getSrc ||
      null;
    const description =
      doc.selectFirst("div.summary__content")?.text?.trim() || "";
    const author = doc.select("div.author-content a").map((el) => el.text.trim()).join(", ");
    const artist = doc.select("div.artist-content a").map((el) => el.text.trim()).join(", ");
    const status = this.toStatus(
      doc.selectFirst("div.post-status div.summary-content")?.text?.trim() || "",
    );

    const genre = [];
    for (const selector of [
      "div.genres-content a",
      "div.tags-content a",
    ]) {
      for (const el of doc.select(selector)) {
        const value = el.text?.trim();
        if (value && !genre.includes(value)) {
          genre.push(value);
        }
      }
    }

    const chapters = [];
    const seen = new Set();
    const chapterElements = doc.select(
      "li.wp-manga-chapter, div.listing-chapters_wrap li, ul.main.version-chap li",
    );
    for (const el of chapterElements) {
      const anchor = el.selectFirst("a");
      const chapterUrl = anchor?.getHref;
      if (!chapterUrl || seen.has(chapterUrl)) continue;
      seen.add(chapterUrl);
      chapters.push({
        name: anchor.text?.trim() || "Chapter",
        url: this.absoluteUrl(chapterUrl),
        dateUpload: this.parseDate(
          el.selectFirst(".chapter-release-date")?.text?.trim(),
        ),
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

  pageRequiresLogin(html) {
    const doc = new Document(html);
    const content = doc.selectFirst(".reading-content");
    const loginMessage =
      doc.selectFirst(".message-login")?.text?.toLowerCase() || "";
    return !content && (
      loginMessage.includes("login") ||
      doc.selectFirst(".g-recaptcha") != null
    );
  }

  async getHtmlContent(name, url) {
    const client = new Client();
    const res = await client.get(this.absoluteUrl(url), this.buildHeaders(url));
    if (this.pageRequiresLogin(res.body)) {
      throw new Error(
        "Wordrain69 premium chapter requires login. Set cookie_header and user_agent in source settings if you have access.",
      );
    }
    return this.cleanHtmlContent(res.body);
  }

  async cleanHtmlContent(html) {
    const doc = new Document(html);
    const title = doc.selectFirst("#chapter-heading")?.text?.trim() ||
                  doc.selectFirst(".wp-manga-chapter-img")?.attr("title") || "";

    // Wordrain serves novel text inside .entry-content p elements
    // .reading-content may only appear in an inline CSS block, not as a real DOM node
    let content = "";
    const readingDiv = doc.selectFirst(".reading-content");
    if (readingDiv) {
      content = readingDiv.innerHtml || "";
    }
    if (!content) {
      // Collect individual paragraphs from .entry-content to avoid picking up scripts
      const paras = doc.select(".entry-content p");
      if (paras.length > 0) {
        content = paras.map(p => p.outerHtml || `<p>${p.text}</p>`).join("\n");
      } else {
        content = doc.selectFirst(".entry-content")?.innerHtml || "";
      }
    }
    if (!content) {
      throw new Error("Wordrain69 chapter content was empty.");
    }
    return `<h2>${title}</h2><hr><br>${content}`;
  }

  getFilterList() {
    return [];
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
          summary: "Change this if Wordrain moves to a new domain.",
          value: baseUrl,
          dialogTitle: "Wordrain base URL",
          dialogMessage: "Enter the full site URL, including https://",
          text: baseUrl,
        },
      },
      {
        key: "cookie_header",
        editTextPreference: {
          title: "Cookie header",
          summary: "Optional. Paste a logged-in browser Cookie header to unlock premium chapters you already have access to.",
          value: cookie,
          dialogTitle: "Cookie header",
          dialogMessage: "Paste the full Cookie header value from a logged-in browser session.",
          text: cookie,
        },
      },
      {
        key: "user_agent",
        editTextPreference: {
          title: "User-Agent",
          summary: "Optional. Use the same User-Agent as the browser session paired with your cookie.",
          value: userAgent,
          dialogTitle: "User-Agent",
          dialogMessage: "Paste the User-Agent value used by the browser session paired with your cookie.",
          text: userAgent,
        },
      },
    ];
  }
}
