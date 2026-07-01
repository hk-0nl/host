const BASE_URL = "https://vivamaxph.com";

const HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
};

function absoluteUrl(url) {
  if (!url) return "";
  if (url.startsWith("http://") || url.startsWith("https://")) return url;
  return BASE_URL + (url.startsWith("/") ? "" : "/") + url;
}

function decodeHtml(value) {
  return String(value || "")
    .replace(/&amp;/g, "&")
    .replace(/&#038;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .trim();
}

function attr(fragment, name) {
  const pattern = new RegExp(`${name}\\s*=\\s*(["'])([\\s\\S]*?)\\1`, "i");
  const match = pattern.exec(fragment || "");
  return match ? decodeHtml(match[2]) : "";
}

function text(fragment) {
  return decodeHtml(String(fragment || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " "));
}

async function fetchText(url) {
  const response = await fetchv2(url, HEADERS);
  if (typeof response.text === "function") return await response.text();
  return response.body || "";
}

function parseArticleResults(html) {
  const results = [];
  const articlePattern = /<article\b[\s\S]*?<\/article>/gi;
  const articles = html.match(articlePattern) || [];

  for (const article of articles) {
    const anchor = /<a\b[\s\S]*?<\/a>/i.exec(article)?.[0] || "";
    const image = /<img\b[^>]*>/i.exec(anchor)?.[0] || /<img\b[^>]*>/i.exec(article)?.[0] || "";
    const title = attr(anchor, "title") || attr(image, "alt") || text(anchor);
    const href = absoluteUrl(attr(anchor, "href"));
    const poster = absoluteUrl(attr(image, "data-src") || attr(image, "src"));

    if (title && href) {
      results.push({ title, image: poster, href });
    }
  }

  return results;
}

function meta(html, property) {
  const pattern = new RegExp(`<meta[^>]+property=["']${property}["'][^>]*>`, "i");
  const tag = pattern.exec(html)?.[0] || "";
  return attr(tag, "content");
}

async function searchResults(keyword) {
  try {
    const url = keyword
      ? `${BASE_URL}/?s=${encodeURIComponent(keyword)}`
      : `${BASE_URL}/page/1/?filter=latest`;
    const html = await fetchText(url);
    return JSON.stringify(parseArticleResults(html));
  } catch (err) {
    console.error("VIVAMAXph search error:", err);
    return JSON.stringify([]);
  }
}

async function extractDetails(key) {
  try {
    const html = await fetchText(absoluteUrl(key));
    const description =
      meta(html, "og:description") ||
      text(/<div[^>]+class=["'][^"']*entry-content[^"']*["'][\s\S]*?<\/div>/i.exec(html)?.[0] || "");
    const airdate =
      attr(/<time\b[^>]*>/i.exec(html)?.[0] || "", "datetime").split("T")[0] || "N/A";

    return JSON.stringify([
      {
        description: description || "N/A",
        aliases: meta(html, "og:title") || "N/A",
        airdate: airdate || "N/A"
      }
    ]);
  } catch (err) {
    console.error("VIVAMAXph detail error:", err);
    return JSON.stringify([{ description: "Error", aliases: "Error", airdate: "Error" }]);
  }
}

async function extractEpisodes(key) {
  return JSON.stringify([{ href: absoluteUrl(key), number: 1 }]);
}

async function extractStreamUrl(key) {
  try {
    const html = await fetchText(absoluteUrl(key));
    const iframeTag = /<iframe\b[^>]*>/i.exec(html)?.[0] || "";
    const iframeUrl = absoluteUrl(attr(iframeTag, "src"));
    return iframeUrl || null;
  } catch (err) {
    console.error("VIVAMAXph stream extraction error:", err);
    return null;
  }
}
