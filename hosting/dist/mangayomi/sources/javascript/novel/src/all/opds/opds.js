const mangayomiSources = [{
    "name": "OPDS Reader",
    "id": 3001000001,
    "baseUrl": "https://standardebooks.org/feeds/opds",
    "apiUrl": "",
    "iconUrl": "https://standardebooks.org/favicon.ico",
    "typeSource": "single",
    "itemType": 2,
    "lang": "all",
    "version": "0.0.1",
    "pkgPath": "novel/src/all/opds/opds.js",
    "isManga": false,
    "isNsfw": false,
    "hasCloudflare": false,
    "sourceCodeUrl": "sources/javascript/novel/src/all/opds/opds.js",
    "appMinVerReq": "0.5.0",
    "notes": "Generic OPDS catalog reader. Set the Base URL in source settings to any OPDS feed (Calibre, Komga, Kavita, Standard Ebooks, Internet Archive, etc.)."
}];

// ─── OPDS Mangayomi Extension ──────────────────────────────────────────────────
// OPDS (Open Publication Distribution System) is an Atom-based XML catalog
// format used by Calibre, Komga, Kavita, Standard Ebooks, Internet Archive,
// and many other self-hosted or public library systems.
//
// Feed structure:
//   Root feed  → <feed> with <entry> elements, each with:
//     <title>          — book/catalog title
//     <author><name>   — author name(s)
//     <summary>        — description
//     <link rel="http://opds-spec.org/image" href="...">         — cover
//     <link rel="http://opds-spec.org/acquisition" href="...">   — download
//     <link rel="subsection" href="...">                         — sub-catalog
//     <link rel="next" href="...">                               — next page
//
// Search:
//   Most OPDS feeds expose an OpenSearch description at the root
//   <link type="application/opensearchdescription+xml">.
//   As a safe universal fallback we append ?q=<query> or &q=<query>.
//
// User-configurable:
//   • domain_url — override the base OPDS feed URL (default: Standard Ebooks)
//   • max_results — number of entries to request per page (default: 20)

class DefaultExtension extends MProvider {
    constructor() {
        super();
        this.client = new Client();
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    _baseUrl() {
        const pref = new SharedPreferences().get("domain_url");
        const url  = (pref && pref.trim()) ? pref.trim() : this.source.baseUrl;
        return url.endsWith("/") ? url.slice(0, -1) : url;
    }

    _headers() {
        return {
            "User-Agent": "Mangayomi-OPDS/1.0",
            "Accept": "application/atom+xml, application/xml, text/xml, */*",
            "Connection": "close",
        };
    }

    async _fetch(url) {
        const res = await this.client.get(url, this._headers());
        return res.body;
    }

    // Parse an OPDS Atom XML body and return { entries, nextUrl }
    _parseFeed(xml) {
        const doc     = new Document(xml);
        const entries = doc.select("entry");
        const nextEl  = doc.selectFirst('link[rel="next"]');
        const nextUrl = nextEl ? nextEl.attr("href") : null;
        return { entries, nextUrl };
    }

    // Extract text content from the first matching selector, or ""
    _text(el, selector) {
        const found = el.selectFirst(selector);
        return found ? found.text.trim() : "";
    }

    // Extract href from the first matching selector, or ""
    _href(el, selector) {
        const found = el.selectFirst(selector);
        return found ? (found.attr("href") || "") : "";
    }

    // Resolve a potentially relative URL against the base feed URL
    _resolve(href) {
        if (!href) return "";
        if (href.startsWith("http://") || href.startsWith("https://")) return href;
        const base = this._baseUrl();
        return href.startsWith("/")
            ? new URL(base).origin + href
            : base + "/" + href;
    }

    // Convert an <entry> element into a manga/novel object
    _entryToItem(entry) {
        const title  = this._text(entry, "title");
        const author = this._text(entry, "author name");
        const summary= this._text(entry, "summary") || this._text(entry, "content");

        // Cover image — prefer OPDS thumbnail, fall back to full image
        const thumbEl = entry.selectFirst('link[rel="http://opds-spec.org/image/thumbnail"]')
                     || entry.selectFirst('link[rel="http://opds-spec.org/image"]');
        const imageUrl = thumbEl ? this._resolve(thumbEl.attr("href") || "") : "";

        // Acquisition link (epub preferred, then any acquisition)
        const epubEl = entry.selectFirst('link[rel="http://opds-spec.org/acquisition"][type="application/epub+zip"]')
                    || entry.selectFirst('link[rel="http://opds-spec.org/acquisition"]');
        const acqUrl = epubEl ? this._resolve(epubEl.attr("href") || "") : "";

        // Detail / alternate link
        const altEl  = entry.selectFirst('link[rel="alternate"]')
                    || entry.selectFirst('link[type="application/atom+xml"]');
        const detailUrl = altEl
            ? this._resolve(altEl.attr("href") || "")
            : acqUrl;

        const link = detailUrl || acqUrl;

        return { title, author, summary, imageUrl, link, acqUrl };
    }

    // ── MProvider API ─────────────────────────────────────────────────────────

    async getPopular(page) {
        const base = this._baseUrl();
        // Most OPDS root feeds list popular/featured entries directly;
        // a few use /new or /popular sub-catalogs — fall back to root.
        const url  = page === 1 ? base : base + "?page=" + page;
        const xml  = await this._fetch(url);
        const { entries, nextUrl } = this._parseFeed(xml);

        const list = entries
            .map(e => this._entryToItem(e))
            .filter(item => item.title && item.link);

        return { list, hasNextPage: !!nextUrl };
    }

    async getLatestUpdates(page) {
        // Try common "new" sub-catalog paths; fall back to popular
        const base    = this._baseUrl();
        const newPath = base.includes("?") ? base + "&sort=new" : base + "/new";
        let xml;
        try {
            xml = await this._fetch(page === 1 ? newPath : newPath + "?page=" + page);
        } catch (_) {
            xml = await this._fetch(page === 1 ? base : base + "?page=" + page);
        }
        const { entries, nextUrl } = this._parseFeed(xml);
        const list = entries
            .map(e => this._entryToItem(e))
            .filter(item => item.title && item.link);
        return { list, hasNextPage: !!nextUrl };
    }

    async search(query, page, filters) {
        if (!query || !query.trim()) return this.getPopular(page);

        const base     = this._baseUrl();
        const encoded  = encodeURIComponent(query.trim());
        const sep      = base.includes("?") ? "&" : "?";
        const url      = base + sep + "q=" + encoded + (page > 1 ? "&page=" + page : "");
        let xml;
        try {
            xml = await this._fetch(url);
        } catch (_) {
            // Search not supported — return popular
            return this.getPopular(page);
        }
        const { entries, nextUrl } = this._parseFeed(xml);
        const list = entries
            .map(e => this._entryToItem(e))
            .filter(item => item.title && item.link);
        return { list, hasNextPage: !!nextUrl };
    }

    async getDetail(url) {
        const xml = await this._fetch(url);
        const doc = new Document(xml);

        // The URL might point directly to an entry feed or a catalog page
        const entry = doc.selectFirst("entry");
        if (!entry) {
            // Catalog page — treat the first acquisition entry as the "detail"
            const { entries } = this._parseFeed(xml);
            const items = entries.map(e => this._entryToItem(e)).filter(i => i.acqUrl);
            const manga = {
                name:        doc.selectFirst("feed > title")?.text.trim() || "OPDS Catalog",
                author:      "",
                description: doc.selectFirst("feed > subtitle")?.text.trim() || "",
                imageUrl:    "",
                status:      0,
                genre:       [],
                chapters:    items.map((item, idx) => ({
                    name: item.title || ("Entry " + (idx + 1)),
                    url:  item.acqUrl || item.link,
                })),
            };
            return manga;
        }

        const item        = this._entryToItem(entry);
        const categories  = entry.select("category").map(c => c.attr("label") || c.attr("term") || "").filter(Boolean);

        // Build chapter list from all acquisition links in this entry
        const acqLinks = entry.select('link[rel="http://opds-spec.org/acquisition"]');
        const chapters = acqLinks.length > 0
            ? acqLinks.map(link => {
                const type  = link.attr("type") || "download";
                const title = link.attr("title") || type;
                return { name: title, url: this._resolve(link.attr("href") || "") };
              }).filter(c => c.url)
            : item.acqUrl
                ? [{ name: "Download", url: item.acqUrl }]
                : [];

        return {
            name:        item.title,
            author:      item.author,
            description: item.summary,
            imageUrl:    item.imageUrl,
            status:      0,
            genre:       categories,
            chapters,
        };
    }

    async getPageList(url) {
        // OPDS acquisition URLs are direct file downloads (epub/pdf/cbz).
        // Return the URL as a single "page" so Mangayomi's reader can open it.
        return [url];
    }

    getFilterList() {
        return [];
    }

    getSourcePreferences() {
        return [
            {
                "key": "domain_url",
                "editTextPreference": {
                    "title":         "OPDS Feed URL",
                    "summary":       "Base URL of your OPDS catalog (Calibre, Komga, Kavita, Standard Ebooks…)",
                    "value":         this.source.baseUrl,
                    "dialogTitle":   "OPDS Feed URL",
                    "dialogMessage": "Paste the root URL of any OPDS-compatible catalog.",
                }
            },
        ];
    }
}
