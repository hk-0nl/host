# Sora Modules

Modules install individually by raw JSON URL.

Current modules:

- AnimePahe Paul 1.0.7: install `modules/animepahe/paul/animepahe_paul.json` individually. This is the user's requested Paul module, separate from the standard version below. Request failures no longer masquerade as Error titles or episode zero. Device testing confirms the blank Shirox verification window/two-attempt problem remains. Supplied logs confirm a separate thumbnail-CDN challenge, but do not establish the main API verification outcome. Native session handling is preserved; these error-list fixes do not claim to repair session capture.
- AnimePahe 1.2.8: Shirox 1.0.6 WebView-cookie maintenance candidate. It requests the persistent WebView fetch engine and bounds episode-page concurrency. Device verification is still required because the provider blocks direct workstation requests with Cloudflare.
- PH Stream: search/details metadata only. Direct streams are not implemented.
