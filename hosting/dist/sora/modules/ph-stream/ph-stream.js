const BASE_URL = "https://www.pornhub.com";
const API_ROOT = `${BASE_URL}/webmasters`;

const HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  Accept: "application/json,text/plain,*/*"
};

function viewKeyFromUrl(value) {
  const match = /(?:viewkey=|^)(ph[0-9a-f]+)/i.exec(String(value || ""));
  return match ? match[1] : "";
}

function officialVideoUrl(value) {
  if (!value) return "";
  if (String(value).startsWith("http://") || String(value).startsWith("https://")) return String(value);
  const viewKey = viewKeyFromUrl(value);
  return viewKey ? `${BASE_URL}/view_video.php?viewkey=${viewKey}` : "";
}

function videoKey(value) {
  try {
    const parsed = JSON.parse(value);
    return parsed.video_id || parsed.id || viewKeyFromUrl(parsed.url);
  } catch {
    return viewKeyFromUrl(value);
  }
}

function queryString(params) {
  const entries = [];
  for (const key of Object.keys(params)) {
    const value = params[key];
    if (value !== undefined && value !== null && value !== "") {
      entries.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    }
  }
  return entries.join("&");
}

async function fetchJson(path, params) {
  const suffix = queryString(params || {});
  const response = await fetchv2(`${API_ROOT}${path}${suffix ? `?${suffix}` : ""}`, HEADERS);
  if (typeof response.json === "function") return await response.json();
  const body = typeof response.text === "function" ? await response.text() : response.body || "{}";
  return JSON.parse(body);
}

function normalizeVideo(video) {
  const url = officialVideoUrl(video.url || video.video_id);
  return {
    title: video.title || "Untitled",
    image: video.default_thumb || video.thumb || "",
    href: url || JSON.stringify({ video_id: video.video_id || "" })
  };
}

function detailsDescription(video) {
  const tags = (video.tags || []).map((item) => item.tag_name).filter(Boolean).join(", ");
  const categories = (video.categories || []).map((item) => item.category).filter(Boolean).join(", ");
  const stars = (video.pornstars || []).map((item) => item.pornstar_name).filter(Boolean).join(", ");
  return [
    video.duration ? `Duration: ${video.duration}` : "",
    Number.isFinite(video.views) ? `Views: ${video.views}` : "",
    video.rating ? `Rating: ${video.rating}` : "",
    tags ? `Tags: ${tags}` : "",
    categories ? `Categories: ${categories}` : "",
    stars ? `Performers: ${stars}` : "",
    video.url ? `Official URL: ${video.url}` : ""
  ]
    .filter(Boolean)
    .join("\n");
}

async function searchResults(keyword) {
  try {
    const data = await fetchJson("/search", {
      search: keyword || "",
      page: 1,
      ordering: keyword ? undefined : "newest",
      thumbsize: "large"
    });
    return JSON.stringify((data.videos || []).map(normalizeVideo));
  } catch (err) {
    console.error("PH Stream search error:", err);
    return JSON.stringify([]);
  }
}

async function extractDetails(key) {
  try {
    const id = videoKey(key);
    if (!id) {
      return JSON.stringify([{ description: "Official web player link only.", aliases: "N/A", airdate: "N/A" }]);
    }
    const data = await fetchJson("/video_by_id", { id, thumbsize: "large" });
    const video = data.video || {};
    return JSON.stringify([
      {
        description: detailsDescription(video) || "Official web player link only.",
        aliases: video.title || "N/A",
        airdate: String(video.publish_date || "").split(" ")[0] || "N/A"
      }
    ]);
  } catch (err) {
    console.error("PH Stream detail error:", err);
    return JSON.stringify([{ description: "Error", aliases: "Error", airdate: "Error" }]);
  }
}

async function extractEpisodes(key) {
  const url = officialVideoUrl(key) || officialVideoUrl(videoKey(key));
  return JSON.stringify(url ? [{ href: url, number: 1 }] : []);
}

async function extractStreamUrl(key) {
  return null;
}
