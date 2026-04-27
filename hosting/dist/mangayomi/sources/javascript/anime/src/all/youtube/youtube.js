class DefaultExtension extends MProvider {
    constructor() {
        super();
        this.client = new Client();
        this.invidiousApi = "https://invidious.nikkosphere.com";
        this.pipedApi = "https://api.piped.private.coffee";
    }

    async getPopular(page) {
        // Trending on Invidious
        const url = `${this.invidiousApi}/api/v1/trending?region=US`;
        const response = await this.client.get(url, {});
        return this.parseVideoList(response.body);
    }

    async getLatestUpdates(page) {
        return this.getPopular(page);
    }

    async search(query, page, filters) {
        const url = `${this.pipedApi}/search?q=${encodeURIComponent(query)}&filter=all`;
        const response = await this.client.get(url, {});
        const data = JSON.parse(response.body);
        
        let mangas = [];
        if (data && Array.isArray(data.items)) {
            for (const item of data.items) {
                if (item.type === "stream") {
                    const videoId = item.url ? item.url.replace("/watch?v=", "") : "";
                    mangas.push({
                        name: item.title || "YouTube Video",
                        imageUrl: item.thumbnail || "",
                        link: videoId
                    });
                }
            }
        }
        return {
            list: mangas,
            hasNextPage: false
        };
    }

    async getDetail(url) {
        const response = await this.client.get(`${this.invidiousApi}/api/v1/videos/${url}`, {});
        const data = JSON.parse(response.body);
        
        const manga = {
            name: data.title || "YouTube Video",
            imageUrl: data.videoThumbnails?.[0]?.url || "",
            description: data.description || "",
            author: data.author || "",
            status: 1, // Completed
            genre: data.genre ? [data.genre] : [],
        };

        // YouTube video is a single chapter
        manga.chapters = [{
            name: "Full Video",
            url: url
        }];

        return manga;
    }

    async getVideoList(url) {
        const response = await this.client.get(`${this.invidiousApi}/api/v1/videos/${url}`, {});
        const data = JSON.parse(response.body);
        
        const videos = [];
        if (data && Array.isArray(data.formatStreams) && data.formatStreams.length > 0) {
            for (const stream of data.formatStreams) {
                if (!stream.url) continue;
                videos.push({
                    url: stream.url,
                    originalUrl: stream.url,
                    quality: stream.qualityLabel || stream.resolution || "Unknown",
                    headers: {}
                });
            }
        }
        
        if (videos.length === 0) {
            videos.push({
                url: "https://error.org/",
                originalUrl: "https://error.org/",
                quality: "Error",
                headers: {}
            });
        }
        return videos;
    }

    parseVideoList(body) {
        const data = JSON.parse(body);
        let mangas = [];
        if (data && Array.isArray(data)) {
            for (const item of data) {
                mangas.push({
                    name: item.title || "YouTube Video",
                    imageUrl: item.videoThumbnails?.[0]?.url || "",
                    link: item.videoId
                });
            }
        }
        return {
            list: mangas,
            hasNextPage: false
        };
    }
}
