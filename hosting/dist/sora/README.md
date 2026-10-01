# Sora Modules

Modules install individually by raw JSON URL.

Current modules:

- AnimePahe Paul 1.0.9: install `modules/animepahe/paul/animepahe_paul.json` individually. This is the requested Paul module, separate from the standard version below. This metadata-only update removes optional unreachable icon dependencies that Shirox waits for before saving an installation/update. A generic icon is expected until artwork is reliably hosted. Module identity and the 1.0.8 script are unchanged: requests/verification use animepahe.pw directly, legacy .com bookmarks work, Cloudflare cookies remain app-managed, and request counts stay bounded. Mocked installation/session/parser tests pass; phone install persistence, the white verification window and separate thumbnail-host challenge remain device gates. Rollback: `modules/animepahe/paul/releases/animepahe_paul-v1.0.7.json` pins the previous script and also omits unavailable artwork dependencies.
- AnimePahe 1.2.8: Shirox 1.0.6 WebView-cookie maintenance candidate. It requests the persistent WebView fetch engine and bounds episode-page concurrency. Device verification is still required because the provider blocks direct workstation requests with Cloudflare.
- PH Stream: search/details metadata only. Direct streams are not implemented.
