# Sora Modules

Modules install individually by raw JSON URL.

Current modules:

- AnimePahe Paul 1.0.8: install `modules/animepahe/paul/animepahe_paul.json` individually. This is the requested Paul module, separate from the standard version below. Requests and verification now use animepahe.pw directly, matching Shirox's initial-host clearance lookup rather than redirecting from .com. Legacy .com bookmarks remain usable. Cloudflare cookies stay app-managed rather than being duplicated in the module's Cookie header. Native verification and bounded request counts are preserved. Mocked regression tests pass; the white verification window and separate thumbnail-host challenge still need device confirmation. Rollback: `modules/animepahe/paul/releases/animepahe_paul-v1.0.7.json` pins the previous script to its exact commit.
- AnimePahe 1.2.8: Shirox 1.0.6 WebView-cookie maintenance candidate. It requests the persistent WebView fetch engine and bounds episode-page concurrency. Device verification is still required because the provider blocks direct workstation requests with Cloudflare.
- PH Stream: search/details metadata only. Direct streams are not implemented.
