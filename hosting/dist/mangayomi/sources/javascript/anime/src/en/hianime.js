const source = {
    name: "HiAnime",
    lang: "en",
    id: "90909091",
    baseUrl: "https://hianime.to",
    iconUrl: "https://hianime.to/images/favicon.png",
    type: 1, // Anime
    isNsfw: false,
    version: "1.0.0",
    dateFormat: "MM/dd/yyyy",
    dateFormatLocale: "en"
};

class MegaCloud {
    constructor(client) {
        this.megacloud = {
            script: "https://megacloud.tv/js/player/a/prod/e1-player.min.js?v=",
            sources: "https://megacloud.tv/embed-2/ajax/e-1/getSources?id=",
        };
        this.client = client;
    }

    async extract(videoUrlText) {
        const videoId = videoUrlText.split("/").pop().split("?")[0];
        const srcsDataObj = JSON.parse(new Client().get(this.megacloud.sources + (videoId || ""), {
            "Accept": "*/*",
            "X-Requested-With": "XMLHttpRequest",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Referer": videoUrlText
        }).body);

        if (!srcsDataObj || !srcsDataObj.sources) {
            throw new Error("Url may have an invalid video id");
        }

        const encryptedString = srcsDataObj.sources;
        if (!srcsDataObj.encrypted && Array.isArray(encryptedString)) {
            return srcsDataObj;
        }

        const scriptRes = new Client().get(this.megacloud.script + Date.now().toString());
        const text = scriptRes.body;
        if (!text) {
            throw new Error("Couldn't fetch script to decrypt resource");
        }

        const vars = this.extractVariables(text);
        if (!vars.length) {
            throw new Error("Can't find variables. Perhaps the extractor is outdated.");
        }

        const secretData = this.getSecret(encryptedString, vars);
        const secret = secretData.secret;
        const encryptedSource = secretData.encryptedSource;
        
        const decryptedStr = CryptoJS.AES.decrypt(encryptedSource, secret).toString(CryptoJS.enc.Utf8);
        const sources = JSON.parse(decryptedStr);
        srcsDataObj.sources = sources;
        return srcsDataObj;
    }

    extractVariables(text) {
        const regex = /case\s*0x[0-9a-f]+:(?![^;]*=partKey)\s*\w+\s*=\s*(\w+)\s*,\s*\w+\s*=\s*(\w+);/g;
        let vars = [];
        let match;
        while ((match = regex.exec(text)) !== null) {
            const matchKey1 = this.matchingKey(match[1], text);
            const matchKey2 = this.matchingKey(match[2], text);
            try {
                vars.push([parseInt(matchKey1, 16), parseInt(matchKey2, 16)]);
            } catch (e) { }
        }
        return vars;
    }

    getSecret(encryptedString, values) {
        let secret = "";
        let encryptedSourceArray = encryptedString.split("");
        let currentIndex = 0;

        for (let i = 0; i < values.length; i++) {
            const index = values[i];
            const start = index[0] + currentIndex;
            const end = start + index[1];

            for (let j = start; j < end; j++) {
                secret += encryptedString[j];
                encryptedSourceArray[j] = "";
            }
            currentIndex += index[1];
        }

        return { secret: secret, encryptedSource: encryptedSourceArray.join("") };
    }

    matchingKey(value, script) {
        const regex = new RegExp("," + value + "=((?:0x)?([0-9a-fA-F]+))");
        const match = script.match(regex);
        if (match) {
            return match[1].replace(/^0x/, "");
        } else {
            throw new Error("Failed to match the key");
        }
    }
}

const mangayomiSources = [{
    "name": "HiAnime",
    "lang": "en",
    "baseUrl": "https://hianime.to",
    "apiUrl": "",
    "iconUrl": "https://hianime.to/images/favicon.png",
    "typeSource": "single",
    "itemType": 1,
    "version": "1.0.0",
    "pkgPath": "anime/src/en/hianime.js",
    "language": "en",
    "isNsfw": false,
    "hasCloudflare": false,
    "sourceCodeUrl": "https://raw.githubusercontent.com/hk-0nl/host/main/hosting/dist/mangayomi/anime/src/en/hianime.js"
}];
class DefaultExtension extends MProvider {
    getHeaders(url) {
        return {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        };
    }

    async getPopular(page) {
        const res = new Client().get(source.baseUrl + "/home");
        const doc = new Document(res.body);
        const elements = doc.select("#anime-trending .flw-item");
        let list = [];
        for (let element of elements) {
            list.push({
                name: element.selectFirst(".dynamic-name") ? element.selectFirst(".dynamic-name").text.trim() : element.selectFirst(".film-name").text.trim(),
                link: source.baseUrl + element.selectFirst("a").attr("href"),
                imageUrl: element.selectFirst("img").attr("data-src")
            });
        }
        return { list: list, hasNextPage: false };
    }

    async getLatestUpdates(page) {
        const res = new Client().get(source.baseUrl + "/recently-updated?page=" + page);
        const doc = new Document(res.body);
        const elements = doc.select(".film_list-wrap .flw-item");
        let list = [];
        for (let element of elements) {
            list.push({
                 name: element.selectFirst(".dynamic-name") ? element.selectFirst(".dynamic-name").text.trim() : element.selectFirst(".film-name").text.trim(),
                 link: source.baseUrl + element.selectFirst("a").attr("href"),
                 imageUrl: element.selectFirst("img").attr("data-src")
            });
        }
        return { list: list, hasNextPage: elements.length > 0 };
    }

    async search(query, page, filters) {
        const res = new Client().get(source.baseUrl + "/search?keyword=" + encodeURIComponent(query) + "&page=" + page);
        const doc = new Document(res.body);
        const elements = doc.select(".film_list-wrap .flw-item");
        let list = [];
        for (let element of elements) {
            list.push({
                 name: element.selectFirst(".dynamic-name") ? element.selectFirst(".dynamic-name").text.trim() : element.selectFirst(".film-name").text.trim(),
                 link: source.baseUrl + element.selectFirst("a").attr("href"),
                 imageUrl: element.selectFirst("img").attr("data-src")
            });
        }
        return { list: list, hasNextPage: elements.length > 0 };
    }

    async getDetail(url) {
        const res = new Client().get(url);
        const doc = new Document(res.body);
        const description = doc.selectFirst(".film-description.m-hide .text") ? doc.selectFirst(".film-description.m-hide .text").text.trim() : "";
        
        let animeId = url.split("-").pop().split("?")[0];
        
        const epData = JSON.parse(new Client().get(source.baseUrl + "/ajax/v2/episode/list/" + animeId).body);
        const epDoc = new Document(epData.html);
        const eps = epDoc.select(".ep-item");
        let chapters = [];
        for (let ep of eps) {
            chapters.push({
                name: "Episode " + ep.attr("data-number") + ": " + (ep.attr("title").trim() || ""),
                url: source.baseUrl + ep.attr("href")
            });
        }
        chapters.reverse();

        return {
            name: doc.selectFirst(".film-name.dynamic-name") ? doc.selectFirst(".film-name.dynamic-name").text.trim() : (doc.selectFirst("h2.film-name") ? doc.selectFirst("h2.film-name").text.trim() : ""),
            imageUrl: doc.selectFirst(".film-poster-img") ? doc.selectFirst(".film-poster-img").attr("src") : "",
            description: description,
            status: 0,
            author: "",
            chapters: chapters
        };
    }

    async getVideoList(url) {
        const epId = url.split("?ep=").pop();
        const serverDataObj = JSON.parse(new Client().get(source.baseUrl + "/ajax/v2/episode/sources?id=" + epId).body);
        const link = serverDataObj.link;
        if (!link) throw new Error("No server link found");

        const serhash = link.split('/e-1/')[1].split('?')[0];
        const megacloudUrl = "https://megacloud.tv/embed-2/e-1/" + serhash + "?k=1";
        
        const mc = new MegaCloud(new Client());
        const data = await mc.extract(megacloudUrl);
        
        let videos = [];
        if (data && data.sources) {
            for (let src of data.sources) {
                videos.push({
                    url: src.url,
                    originalUrl: src.url,
                    quality: "MegaCloud " + src.type,
                    headers: null
                });
            }
        }
        
        if(data && data.tracks && videos.length > 0) {
             let subtitles = [];
             for(let track of data.tracks) {
                 if(track.kind === "captions") {
                      subtitles.push({
                           file: track.file,
                           label: track.label
                      });
                 }
             }
             if(subtitles.length > 0) videos[0].subtitles = subtitles;
        }

        return videos;
    }
}
