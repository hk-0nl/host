const BASE_ROOT = "https://123av.com";
const BASE_URL = `${BASE_ROOT}/en`;

const HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
};

function absoluteUrl(url) {
  if (!url) return "";
  if (url.startsWith("http://") || url.startsWith("https://")) return url;
  if (url.startsWith("/")) return BASE_URL + url;
  return `${BASE_URL}/${url}`;
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

function parseBoxItems(html) {
  const results = [];
  const boxes = html.match(/<div\b[^>]*class=["'][^"']*box-item[^"']*["'][\s\S]*?<\/div>\s*<\/div>/gi) || [];

  for (const box of boxes) {
    const imageTag = /<img\b[^>]*>/i.exec(box)?.[0] || "";
    const detail = /<div\b[^>]*class=["'][^"']*detail[^"']*["'][\s\S]*?<\/div>/i.exec(box)?.[0] || box;
    const anchor = /<a\b[\s\S]*?<\/a>/i.exec(detail)?.[0] || "";
    const title = text(anchor) || attr(anchor, "title") || attr(imageTag, "alt");
    const href = absoluteUrl(attr(anchor, "href"));
    const image = absoluteUrl(attr(imageTag, "data-src") || attr(imageTag, "src"));

    if (title && href) {
      results.push({ title, image, href });
    }
  }

  return results;
}

function playerId(html) {
  const scope = attr(/<div\b[^>]*v-scope=["'][^"']*["'][^>]*>/i.exec(html)?.[0] || "", "v-scope");
  const match = /:\s*([0-9]+)\s*,/.exec(scope);
  return match ? match[1] : "";
}

function detailDate(html) {
  const details = html.match(/<div\b[^>]*class=["'][^"']*detail-item[^"']*["'][\s\S]*?<\/div>/gi) || [];
  for (const item of details) {
    const value = text(item);
    const match = /\b(20[0-9]{2}-[01][0-9]-[0-3][0-9])\b/.exec(value);
    if (match) return match[1];
  }
  return "N/A";
}

function description(html) {
  return text(/<div\b[^>]*class=["'][^"']*description[^"']*["'][\s\S]*?<\/div>/i.exec(html)?.[0] || "");
}

async function searchResults(keyword) {
  try {
    const url = keyword
      ? `${BASE_URL}/search?keyword=${encodeURIComponent(keyword)}`
      : `${BASE_URL}/dm5/new-release?page=1`;
    const html = await fetchText(url);
    return JSON.stringify(parseBoxItems(html));
  } catch (err) {
    console.error("123AV search error:", err);
    return JSON.stringify([]);
  }
}

async function extractDetails(key) {
  try {
    const html = await fetchText(absoluteUrl(key));
    const title = text(/<h1\b[\s\S]*?<\/h1>/i.exec(html)?.[0] || "");
    return JSON.stringify([
      {
        description: description(html) || "N/A",
        aliases: title || "N/A",
        airdate: detailDate(html)
      }
    ]);
  } catch (err) {
    console.error("123AV detail error:", err);
    return JSON.stringify([{ description: "Error", aliases: "Error", airdate: "Error" }]);
  }
}

async function extractEpisodes(key) {
  try {
    const html = await fetchText(absoluteUrl(key));
    const id = playerId(html);
    if (!id) return JSON.stringify([{ href: absoluteUrl(key), number: 1 }]);

    const response = await fetchText(`${BASE_URL}/ajax/v/${id}/videos`);
    const data = JSON.parse(response);
    const watch = data?.result?.watch || [];
    const episodes = watch.map((item, index) => ({
      href: item.url,
      number: index + 1
    }));

    return JSON.stringify(episodes.length ? episodes : [{ href: absoluteUrl(key), number: 1 }]);
  } catch (err) {
    console.error("123AV episode error:", err);
    return JSON.stringify([]);
  }
}

function streamFromPlayerScope(html) {
  const scope = attr(/<div\b[^>]*id=["']player["'][^>]*>/i.exec(html)?.[0] || "", "v-scope");
  const match = /stream["']?\s*:\s*["']([^"']+)["']/.exec(scope);
  return match ? decodeHtml(match[1]) : "";
}

async function extractStreamUrl(key) {
  try {
    const html = await fetchText(absoluteUrl(key));
    return streamFromPlayerScope(html) || null;
  } catch (err) {
    console.error("123AV stream extraction error:", err);
    return null;
  }
}
