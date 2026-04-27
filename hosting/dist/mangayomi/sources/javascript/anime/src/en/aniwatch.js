// ============================================================
//  Aniwatch (aniwatchtv.to) – Mangayomi JavaScript Extension
//  Supports: Popular, Latest, Search, Detail, Episodes, Video
//  MegaCloud decryption ported from Aniwatch-Api (src1.js)
// ============================================================

const mangayomiSources = [{
  "name": "Aniwatch",
  "lang": "en",
  "baseUrl": "https://aniwatchtv.to",
  "apiUrl": "https://aniwatchtv.to",
  "iconUrl": "https://aniwatchtv.to/images/favicon.png",
  "typeSource": "single",
  "isManga": false,
  "itemType": 1,
  "version": "1.0.0",
  "dateFormat": "",
  "dateFormatLocale": "",
  "pkgPath": "sources/javascript/anime/src/en/aniwatch.js",
  "isNsfw": false,
  "hasCloudflare": true,
  "notes": "Requires Cloudflare bypass. Open aniwatchtv.to in Mangayomi webview first if blocked. MegaCloud decryption may break if the player script changes."
}];

// ─── MegaCloud Decryptor ─────────────────────────────────────
// Pure-JS AES-CBC decrypt matching Node.js crypto.createDecipheriv
// Key derivation: OpenSSL EVP_BytesToKey (MD5 x3 with salt)

function hexToBytes(hex) {
  const bytes = [];
  for (let i = 0; i < hex.length; i += 2) {
    bytes.push(parseInt(hex.slice(i, i + 2), 16));
  }
  return bytes;
}

function md5(inputBytes) {
  // RFC 1321 MD5 — compact implementation
  function safeAdd(x, y) {
    const lsw = (x & 0xffff) + (y & 0xffff);
    return ((x >> 16) + (y >> 16) + (lsw >> 16)) << 16 | (lsw & 0xffff);
  }
  function bitRotateLeft(num, cnt) { return num << cnt | num >>> (32 - cnt); }
  function md5cmn(q, a, b, x, s, t) { return safeAdd(bitRotateLeft(safeAdd(safeAdd(a, q), safeAdd(x, t)), s), b); }
  function md5ff(a, b, c, d, x, s, t) { return md5cmn(b & c | ~b & d, a, b, x, s, t); }
  function md5gg(a, b, c, d, x, s, t) { return md5cmn(b & d | c & ~d, a, b, x, s, t); }
  function md5hh(a, b, c, d, x, s, t) { return md5cmn(b ^ c ^ d, a, b, x, s, t); }
  function md5ii(a, b, c, d, x, s, t) { return md5cmn(c ^ (b | ~d), a, b, x, s, t); }

  const bytes = inputBytes.slice();
  const bitLen = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  // append length as 64-bit LE
  bytes.push(bitLen & 0xff, (bitLen >> 8) & 0xff, (bitLen >> 16) & 0xff, (bitLen >> 24) & 0xff, 0, 0, 0, 0);

  let a = 0x67452301, b = 0xefcdab89, c = 0x98badcfe, d = 0x10325476;
  for (let i = 0; i < bytes.length; i += 64) {
    const m = [];
    for (let j = 0; j < 16; j++) {
      m[j] = bytes[i + j*4] | (bytes[i + j*4+1] << 8) | (bytes[i + j*4+2] << 16) | (bytes[i + j*4+3] << 24);
    }
    let [aa, bb, cc, dd] = [a, b, c, d];
    a = md5ff(a,b,c,d,m[0],7,-680876936); d = md5ff(d,a,b,c,m[1],12,-389564586); c = md5ff(c,d,a,b,m[2],17,606105819); b = md5ff(b,c,d,a,m[3],22,-1044525330);
    a = md5ff(a,b,c,d,m[4],7,-176418897); d = md5ff(d,a,b,c,m[5],12,1200080426); c = md5ff(c,d,a,b,m[6],17,-1473231341); b = md5ff(b,c,d,a,m[7],22,-45705983);
    a = md5ff(a,b,c,d,m[8],7,1770035416); d = md5ff(d,a,b,c,m[9],12,-1958414417); c = md5ff(c,d,a,b,m[10],17,-42063); b = md5ff(b,c,d,a,m[11],22,-1990404162);
    a = md5ff(a,b,c,d,m[12],7,1804603682); d = md5ff(d,a,b,c,m[13],12,-40341101); c = md5ff(c,d,a,b,m[14],17,-1502002290); b = md5ff(b,c,d,a,m[15],22,1236535329);
    a = md5gg(a,b,c,d,m[1],5,-165796510); d = md5gg(d,a,b,c,m[6],9,-1069501632); c = md5gg(c,d,a,b,m[11],14,643717713); b = md5gg(b,c,d,a,m[0],20,-373897302);
    a = md5gg(a,b,c,d,m[5],5,-701558691); d = md5gg(d,a,b,c,m[10],9,38016083); c = md5gg(c,d,a,b,m[15],14,-660478335); b = md5gg(b,c,d,a,m[4],20,-405537848);
    a = md5gg(a,b,c,d,m[9],5,568446438); d = md5gg(d,a,b,c,m[14],9,-1019803690); c = md5gg(c,d,a,b,m[3],14,-187363961); b = md5gg(b,c,d,a,m[8],20,1163531501);
    a = md5gg(a,b,c,d,m[13],5,-1444681467); d = md5gg(d,a,b,c,m[2],9,-51403784); c = md5gg(c,d,a,b,m[7],14,1735328473); b = md5gg(b,c,d,a,m[12],20,-1926607734);
    a = md5hh(a,b,c,d,m[5],4,-378558); d = md5hh(d,a,b,c,m[8],11,-2022574463); c = md5hh(c,d,a,b,m[11],16,1839030562); b = md5hh(b,c,d,a,m[14],23,-35309556);
    a = md5hh(a,b,c,d,m[1],4,-1530992060); d = md5hh(d,a,b,c,m[4],11,1272893353); c = md5hh(c,d,a,b,m[7],16,-155497632); b = md5hh(b,c,d,a,m[10],23,-1094730640);
    a = md5hh(a,b,c,d,m[13],4,681279174); d = md5hh(d,a,b,c,m[0],11,-358537222); c = md5hh(c,d,a,b,m[3],16,-722521979); b = md5hh(b,c,d,a,m[6],23,76029189);
    a = md5hh(a,b,c,d,m[9],4,-640364487); d = md5hh(d,a,b,c,m[12],11,-421815835); c = md5hh(c,d,a,b,m[15],16,530742520); b = md5hh(b,c,d,a,m[2],23,-995338651);
    a = md5ii(a,b,c,d,m[0],6,-198630844); d = md5ii(d,a,b,c,m[7],10,1126891415); c = md5ii(c,d,a,b,m[14],15,-1416354905); b = md5ii(b,c,d,a,m[5],21,-57434055);
    a = md5ii(a,b,c,d,m[12],6,1700485571); d = md5ii(d,a,b,c,m[3],10,-1894986606); c = md5ii(c,d,a,b,m[10],15,-1051523); b = md5ii(b,c,d,a,m[1],21,-2054922799);
    a = md5ii(a,b,c,d,m[8],6,1873313359); d = md5ii(d,a,b,c,m[15],10,-30611744); c = md5ii(c,d,a,b,m[6],15,-1560198380); b = md5ii(b,c,d,a,m[13],21,1309151649);
    a = md5ii(a,b,c,d,m[4],6,-145523070); d = md5ii(d,a,b,c,m[11],10,-1120210379); c = md5ii(c,d,a,b,m[2],15,718787259); b = md5ii(b,c,d,a,m[9],21,-343485551);
    a = safeAdd(a, aa); b = safeAdd(b, bb); c = safeAdd(c, cc); d = safeAdd(d, dd);
  }

  const result = [a, b, c, d];
  const out = [];
  for (let v of result) {
    out.push(v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff);
  }
  return out;
}

function base64ToBytes(b64) {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  const lookup = {};
  for (let i = 0; i < chars.length; i++) lookup[chars[i]] = i;
  let bits = 0, value = 0, output = [];
  for (let c of b64) {
    if (c === "=") break;
    if (!(c in lookup)) continue;
    value = (value << 6) | lookup[c];
    bits += 6;
    if (bits >= 8) { bits -= 8; output.push((value >> bits) & 0xff); }
  }
  return output;
}

function aes256cbcDecrypt(cipherBytes, keyBytes, ivBytes) {
  // AES-256-CBC using pure-JS AES (PKCS#7 unpad)
  // This is a minimal but correct AES implementation
  const Nb = 4, Nr = 14, Nk = 8;
  const sBox = [0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16];
  const inv = new Array(256); for (let i = 0; i < 256; i++) inv[sBox[i]] = i;
  const xtime = b => (b << 1) ^ ((b & 0x80) ? 0x1b : 0);
  const mul = (a, b) => {
    let p = 0;
    for (let i = 0; i < 8; i++) { if (b & 1) p ^= a; const hb = a & 0x80; a = (a << 1) & 0xff; if (hb) a ^= 0x1b; b >>= 1; }
    return p;
  };

  // Key expansion
  const rcon = [0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36,0x6c,0xd8,0xab,0x4d,0x9a,0x2f,0x5e,0xbc,0x63,0xc6,0x97,0x35,0x6a,0xd4,0xb3,0x7d,0xfa,0xef,0xc5];
  const w = [];
  for (let i = 0; i < Nk; i++) {
    w.push([keyBytes[4*i], keyBytes[4*i+1], keyBytes[4*i+2], keyBytes[4*i+3]]);
  }
  for (let i = Nk; i < Nb * (Nr + 1); i++) {
    let temp = w[i-1].slice();
    if (i % Nk === 0) {
      temp = [sBox[temp[1]]^rcon[i/Nk-1], sBox[temp[2]], sBox[temp[3]], sBox[temp[0]]];
    } else if (Nk > 6 && i % Nk === 4) {
      temp = temp.map(b => sBox[b]);
    }
    w.push([w[i-Nk][0]^temp[0], w[i-Nk][1]^temp[1], w[i-Nk][2]^temp[2], w[i-Nk][3]^temp[3]]);
  }
  const rk = [];
  for (let r = 0; r <= Nr; r++) {
    rk.push(w.slice(r*4, r*4+4));
  }

  function decryptBlock(block) {
    let state = [];
    for (let c = 0; c < 4; c++) state.push([block[c], block[c+4], block[c+8], block[c+12]]);
    // add round key (last)
    for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) state[c][r] ^= rk[Nr][c][r];
    for (let round = Nr - 1; round >= 0; round--) {
      // InvShiftRows
      const tmp = state[0][3]; state[0][3] = state[0][2]; state[0][2] = state[0][1]; state[0][1] = state[0][0]; state[0][0] = tmp;
      const tmp2 = state[1][2]; state[1][2] = state[1][0]; state[1][0] = tmp2; const tmp3 = state[1][3]; state[1][3] = state[1][1]; state[1][1] = tmp3;
      const tmp4 = state[2][1]; state[2][1] = state[2][2]; state[2][2] = tmp4; const tmp5 = state[2][0]; state[2][0] = state[2][3]; state[2][3] = tmp5;
      const tmp6 = state[3][0]; state[3][0] = state[3][1]; state[3][1] = state[3][2]; state[3][2] = state[3][3]; state[3][3] = tmp6;
      // InvSubBytes
      for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) state[c][r] = inv[state[c][r]];
      // AddRoundKey
      for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) state[c][r] ^= rk[round][c][r];
      if (round > 0) {
        // InvMixColumns
        for (let c = 0; c < 4; c++) {
          const [s0, s1, s2, s3] = [state[c][0], state[c][1], state[c][2], state[c][3]];
          state[c][0] = mul(0x0e,s0)^mul(0x0b,s1)^mul(0x0d,s2)^mul(0x09,s3);
          state[c][1] = mul(0x09,s0)^mul(0x0e,s1)^mul(0x0b,s2)^mul(0x0d,s3);
          state[c][2] = mul(0x0d,s0)^mul(0x09,s1)^mul(0x0e,s2)^mul(0x0b,s3);
          state[c][3] = mul(0x0b,s0)^mul(0x0d,s1)^mul(0x09,s2)^mul(0x0e,s3);
        }
      }
    }
    const out = new Array(16);
    for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) out[c + r*4] = state[c][r];
    return out;
  }

  const plaintext = [];
  let prev = ivBytes.slice();
  for (let i = 0; i < cipherBytes.length; i += 16) {
    const block = cipherBytes.slice(i, i + 16);
    const dec = decryptBlock(block);
    for (let j = 0; j < 16; j++) plaintext.push(dec[j] ^ prev[j]);
    prev = block;
  }
  // PKCS#7 unpad
  const pad = plaintext[plaintext.length - 1];
  return plaintext.slice(0, plaintext.length - pad);
}

// OpenSSL EVP_BytesToKey for base64-encoded encrypted source (same as CryptoJS default)
function evpBytesToKey(password, salt) {
  const passBytes = typeof password === "string"
    ? password.split("").map(c => c.charCodeAt(0))
    : password;
  const d = [];
  let dk = [];
  while (dk.length < 48) {
    const toHash = d.length > 0 ? [...d[d.length - 1], ...passBytes, ...salt] : [...passBytes, ...salt];
    d.push(md5(toHash));
    dk = dk.concat(d[d.length - 1]);
  }
  return { key: dk.slice(0, 32), iv: dk.slice(32, 48) };
}

function megaCloudDecrypt(encryptedSource, secret) {
  const cypher = base64ToBytes(encryptedSource);
  // OpenSSL format: "Salted__" + 8 bytes salt + ciphertext
  if (cypher.slice(0, 8).map(b => String.fromCharCode(b)).join("") !== "Salted__") {
    throw new Error("Not an OpenSSL salted cipher");
  }
  const salt = cypher.slice(8, 16);
  const { key, iv } = evpBytesToKey(secret, salt);
  const cipherBytes = cypher.slice(16);
  const plainBytes = aes256cbcDecrypt(cipherBytes, key, iv);
  return plainBytes.map(b => String.fromCharCode(b)).join("");
}

// ─── MegaCloud extractor ─────────────────────────────────────
const MEGACLOUD_SCRIPT_URL = "https://megacloud.tv/js/player/a/prod/e1-player.min.js?v=";
const MEGACLOUD_SOURCES_URL = "https://megacloud.tv/embed-2/ajax/e-1/getSources?id=";

function extractMegaVariables(text) {
  const regex = /case\s*0x[0-9a-f]+:(?![^;]*=partKey)\s*\w+\s*=\s*(\w+)\s*,\s*\w+\s*=\s*(\w+);/g;
  const vars = [];
  let match;
  while ((match = regex.exec(text)) !== null) {
    try {
      const k1 = matchingKey(match[1], text);
      const k2 = matchingKey(match[2], text);
      vars.push([parseInt(k1, 16), parseInt(k2, 16)]);
    } catch (e) {}
  }
  return vars;
}

function matchingKey(value, script) {
  const regex = new RegExp("," + value + "=((?:0x)?([0-9a-fA-F]+))");
  const match = script.match(regex);
  if (match) return match[1].replace(/^0x/, "");
  throw new Error("Failed to find key: " + value);
}

function getSecretAndSource(encryptedString, values) {
  let secret = "";
  const arr = encryptedString.split("");
  let currentIndex = 0;
  for (const idx of values) {
    const start = idx[0] + currentIndex;
    const end = start + idx[1];
    for (let i = start; i < end; i++) { secret += encryptedString[i]; arr[i] = ""; }
    currentIndex += idx[1];
  }
  return { secret, encryptedSource: arr.join("") };
}

async function extractFromMegaCloud(videoUrl) {
  const client = new Client();
  
  // 1. Fetch the iframe HTML
  const iframeRes = await client.get(videoUrl, {
    "Accept": "*/*",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Referer": "https://aniwatchtv.to/"
  });
  const iframeHtml = iframeRes.body;
  if (!iframeHtml) throw new Error("Could not fetch MegaCloud iframe");

  // 2. Extract fileId
  let fileId = "";
  const videoTagMatch = iframeHtml.match(/data-id="([^"]+)"/);
  if (videoTagMatch) fileId = videoTagMatch[1];
  else fileId = videoUrl.split("/").pop().split("?")[0];

  // 3. Extract nonce
  let nonce = "";
  const nonceMatch = iframeHtml.match(/\b[a-zA-Z0-9]{48}\b/) || 
                     iframeHtml.match(/\b([a-zA-Z0-9]{16})\b.*?\b([a-zA-Z0-9]{16})\b.*?\b([a-zA-Z0-9]{16})\b/);
  if (nonceMatch) {
    if (nonceMatch.length === 4) {
      nonce = nonceMatch[1] + nonceMatch[2] + nonceMatch[3];
    } else {
      nonce = nonceMatch[0];
    }
  }

  // 4. Construct v3 sources URL
  // e.g. https://megacloud.tv/embed-2/v3/e-1/getSources?id=XXX&_k=YYY
  // Determine hostname from videoUrl
  const urlParts = videoUrl.split("/");
  const proto = videoUrl.startsWith("https") ? "https:" : "http:";
  const hostname = urlParts.length > 2 ? urlParts[2] : "megacloud.blog";
  const defaultDomain = `${proto}//${hostname}/`;

  let getSourcesUrl = `${defaultDomain}embed-2/ajax/e-1/getSources?id=${fileId}`;
  if (nonce) {
    getSourcesUrl = `${defaultDomain}embed-2/v3/e-1/getSources?id=${fileId}&_k=${nonce}`;
  }

  const srcsRes = await client.get(getSourcesUrl, {
    "Accept": "*/*",
    "X-Requested-With": "XMLHttpRequest",
    "Referer": defaultDomain,
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
  });

  const srcsData = JSON.parse(srcsRes.body);
  if (!srcsData || !srcsData.sources) throw new Error("No sources data for id: " + fileId);

  const encryptedString = srcsData.sources;

  // If already unencrypted array (V3 typically returns this directly)
  if (!srcsData.encrypted && Array.isArray(encryptedString)) {
    return srcsData;
  }

  // Fallback to old decipher method if encrypted (for older ajax/e-1)
  const scriptRes = await client.get(MEGACLOUD_SCRIPT_URL + Date.now());
  if (!scriptRes.body) throw new Error("Could not fetch MegaCloud player script");

  const vars = extractMegaVariables(scriptRes.body);
  if (!vars.length) throw new Error("MegaCloud variables not found — extractor may be outdated");

  const { secret, encryptedSource } = getSecretAndSource(encryptedString, vars);
  const decrypted = megaCloudDecrypt(encryptedSource, secret);
  srcsData.sources = JSON.parse(decrypted);
  return srcsData;
}

// ─── Main Extension ──────────────────────────────────────────

const BASE_URL = "https://aniwatchtv.to";
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

class DefaultExtension extends MProvider {
  get supportsLatest() { return true; }

  getHeaders(url) {
    return {
      "User-Agent": UA,
      "Referer": BASE_URL + "/",
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.9"
    };
  }

  getAjaxHeaders(url) {
    return {
      "User-Agent": UA,
      "X-Requested-With": "XMLHttpRequest",
      "Referer": url || BASE_URL
    };
  }

  parseAnimeCard(element) {
    const link = element.selectFirst("a")?.getHref;
    if (!link) return null;
    const name =
      element.selectFirst(".dynamic-name")?.text?.trim() ||
      element.selectFirst(".film-name")?.text?.trim() ||
      element.selectFirst("a")?.attr("title")?.trim();
    const img = element.selectFirst("img");
    const imageUrl =
      img?.attr("data-src") ||
      img?.attr("src") ||
      img?.getSrc;
    return { name, link: BASE_URL + link, imageUrl };
  }

  parseListPage(html) {
    const doc = new Document(html);
    const list = [];
    for (const el of doc.select(".flw-item")) {
      const card = this.parseAnimeCard(el);
      if (card && card.name) list.push(card);
    }
    const hasNextPage =
      doc.selectFirst(".pagination .active")?.nextSibling != null ||
      doc.selectFirst(".pagination li.active + li") != null;
    return { list, hasNextPage };
  }

  async getPopular(page) {
    const res = await new Client().get(
      `${BASE_URL}/most-popular?page=${page}`,
      this.getHeaders(BASE_URL)
    );
    return this.parseListPage(res.body);
  }

  async getLatestUpdates(page) {
    const res = await new Client().get(
      `${BASE_URL}/recently-updated?page=${page}`,
      this.getHeaders(BASE_URL)
    );
    return this.parseListPage(res.body);
  }

  async search(query, page, filters) {
    let url = `${BASE_URL}/search?keyword=${encodeURIComponent(query)}&page=${page}`;

    // Apply filters
    if (filters && filters.length > 0) {
      for (const f of filters) {
        if (f.type_name === "SelectFilter" && f.values && f.state != null) {
          const val = f.values[f.state]?.value;
          if (val) url += `&${f.key}=${encodeURIComponent(val)}`;
        } else if (f.type_name === "GroupFilter" && f.state) {
          for (const opt of f.state) {
            if (opt.state === true) url += `&${f.key}[]=${encodeURIComponent(opt.value)}`;
          }
        }
      }
    }

    const res = await new Client().get(url, this.getHeaders(BASE_URL));
    return this.parseListPage(res.body);
  }

  async getDetail(url) {
    const client = new Client();
    const res = await client.get(url, this.getHeaders(url));
    const doc = new Document(res.body);

    const name =
      doc.selectFirst(".film-name.dynamic-name")?.text?.trim() ||
      doc.selectFirst("h2.film-name")?.text?.trim() ||
      doc.selectFirst(".anisc-detail h2")?.text?.trim() || "";

    const imageUrl =
      doc.selectFirst(".film-poster-img")?.attr("src") ||
      doc.selectFirst(".film-poster img")?.getSrc;

    const description =
      doc.selectFirst(".film-description.m-hide .text")?.text?.trim() ||
      doc.selectFirst(".film-description .text")?.text?.trim() || "";

    // Genres / tags
    const genre = doc.select(".item-list.genres a, .item.genres a").map(el => el.text.trim());

    // Status
    const statusText = doc.selectFirst(".item.status .name")?.text?.trim()?.toLowerCase() || "";
    let status = 0;
    if (statusText.includes("finished") || statusText.includes("completed")) status = 1;
    else if (statusText.includes("not yet")) status = 5;
    else if (statusText.includes("hiatus")) status = 2;

    // Author / Studio
    const author = doc.select(".item.studios a").map(el => el.text.trim()).join(", ");

    // Anime ID: prefer data-id attribute on page (more reliable than URL regex)
    let animeId = "";
    const bodyWithId = doc.selectFirst("[data-id]");
    if (bodyWithId) {
      animeId = bodyWithId.attr("data-id") || "";
    }
    // Fallback: extract trailing numeric ID from URL
    if (!animeId || !/^\d+$/.test(animeId)) {
      animeId = url.replace(/.*-(\d+)\/?$/, "$1").split("?")[0];
    }
    if (!animeId || !/^\d+$/.test(animeId)) {
      return { name, imageUrl, description, genre, author, status, chapters: [] };
    }

    // Fetch episodes via AJAX
    const epRes = await client.get(
      `${BASE_URL}/ajax/v2/episode/list/${animeId}`,
      this.getAjaxHeaders(url)
    );
    const epData = JSON.parse(epRes.body);
    if (!epData.html) return { name, imageUrl, description, genre, author, status, chapters: [] };

    const epDoc = new Document(epData.html);
    const chapters = [];
    for (const ep of epDoc.select("a.ep-item, a.ssl-item")) {
      const epNum = ep.attr("data-number") || "";
      const epTitle = ep.attr("title") || ep.text?.trim() || "";
      let epHref = ep.getHref || ep.attr("href") || "";
      if (!epHref) continue;
      // Ensure absolute URL
      if (epHref.startsWith("/")) epHref = BASE_URL + epHref;
      chapters.push({
        name: `Episode ${epNum}${epTitle ? ": " + epTitle : ""}`.trim(),
        url: epHref
      });
    }
    chapters.reverse();

    return { name, imageUrl, description, genre, author, status, chapters };
  }

  async getVideoList(url) {
    const client = new Client();

    // Extract episode id from URL: /watch/anime-name-123?ep=456
    const epIdMatch = url.match(/[?&]ep=(\d+)/);
    if (!epIdMatch) throw new Error("Aniwatch: cannot extract episode id from " + url);
    const epId = epIdMatch[1];

    // Get available servers for this episode
    const serverRes = await client.get(
      `${BASE_URL}/ajax/v2/episode/servers?episodeId=${epId}`,
      this.getAjaxHeaders(url)
    );
    const serverData = JSON.parse(serverRes.body);
    if (!serverData.html) throw new Error("Aniwatch: no server data for ep " + epId);

    const serverDoc = new Document(serverData.html);
    const servers = serverDoc.select(".server-item");

    const videos = [];

    for (const server of servers) {
      const serverId = server.attr("data-server-id") || server.attr("data-id");
      const serverName = server.selectFirst("a")?.text?.trim() || "Unknown";
      const serverType = server.attr("data-type") || "sub"; // sub/dub

      if (!serverId) continue;

      try {
        // Resolve server link
        const srcRes = await client.get(
          `${BASE_URL}/ajax/v2/episode/sources?id=${serverId}`,
          this.getAjaxHeaders(url)
        );
        const srcData = JSON.parse(srcRes.body);
        const link = srcData.link;
        if (!link) continue;

        // Only handle MegaCloud (embed-2/e-1)
        if (!link.includes("megacloud.tv") && !link.includes("embed-2")) {
          // Try to add direct HLS if link looks like one
          if (link.endsWith(".m3u8")) {
            videos.push({
              url: link,
              originalUrl: link,
              quality: `${serverName} (${serverType})`,
              headers: null
            });
          }
          continue;
        }

        const megaData = await extractFromMegaCloud(link);
        if (!megaData || !megaData.sources) continue;

        for (const src of megaData.sources) {
          videos.push({
            url: src.file || src.url,
            originalUrl: src.file || src.url,
            quality: `${serverName} - ${src.type || "hls"} (${serverType})`,
            headers: null
          });
        }

        // Attach subtitles to all videos from this server (best-effort)
        if (megaData.tracks) {
          const subs = megaData.tracks.filter(t => t.kind === "captions");
          if (subs.length > 0 && videos.length > 0) {
            // Attach as label for now — subtitle support depends on Mangayomi version
            for (const sub of subs) {
              videos.push({
                url: sub.file,
                originalUrl: sub.file,
                quality: `[SUB] ${sub.label || "Unknown"} (${serverType})`,
                headers: null
              });
            }
          }
        }
      } catch (e) {
        // Skip failed servers, don't abort entirely
      }
    }

    if (videos.length === 0) throw new Error("Aniwatch: no playable sources found for ep " + epId);
    return videos;
  }

  getFilterList() {
    return [
      {
        type_name: "SelectFilter",
        key: "type",
        name: "Type",
        state: 0,
        values: [
          { type_name: "SelectOption", name: "All", value: "" },
          { type_name: "SelectOption", name: "Movie", value: "1" },
          { type_name: "SelectOption", name: "TV", value: "2" },
          { type_name: "SelectOption", name: "OVA", value: "3" },
          { type_name: "SelectOption", name: "ONA", value: "4" },
          { type_name: "SelectOption", name: "Special", value: "5" },
          { type_name: "SelectOption", name: "Music", value: "6" },
        ]
      },
      {
        type_name: "SelectFilter",
        key: "status",
        name: "Status",
        state: 0,
        values: [
          { type_name: "SelectOption", name: "All", value: "" },
          { type_name: "SelectOption", name: "Currently Airing", value: "1" },
          { type_name: "SelectOption", name: "Finished Airing", value: "2" },
          { type_name: "SelectOption", name: "Not yet aired", value: "3" },
        ]
      },
      {
        type_name: "SelectFilter",
        key: "rated",
        name: "Rating",
        state: 0,
        values: [
          { type_name: "SelectOption", name: "All", value: "" },
          { type_name: "SelectOption", name: "G", value: "g" },
          { type_name: "SelectOption", name: "PG", value: "pg" },
          { type_name: "SelectOption", name: "PG-13", value: "pg_13" },
          { type_name: "SelectOption", name: "R", value: "r" },
          { type_name: "SelectOption", name: "R+", value: "r+" },
          { type_name: "SelectOption", name: "Rx", value: "rx" },
        ]
      },
      {
        type_name: "SelectFilter",
        key: "score",
        name: "Score",
        state: 0,
        values: [
          { type_name: "SelectOption", name: "All", value: "" },
          { type_name: "SelectOption", name: "Appalling (1)", value: "1" },
          { type_name: "SelectOption", name: "Horrible (2)", value: "2" },
          { type_name: "SelectOption", name: "Very Bad (3)", value: "3" },
          { type_name: "SelectOption", name: "Bad (4)", value: "4" },
          { type_name: "SelectOption", name: "Average (5)", value: "5" },
          { type_name: "SelectOption", name: "Fine (6)", value: "6" },
          { type_name: "SelectOption", name: "Good (7)", value: "7" },
          { type_name: "SelectOption", name: "Very Good (8)", value: "8" },
          { type_name: "SelectOption", name: "Great (9)", value: "9" },
          { type_name: "SelectOption", name: "Masterpiece (10)", value: "10" },
        ]
      },
      {
        type_name: "SelectFilter",
        key: "season",
        name: "Season",
        state: 0,
        values: [
          { type_name: "SelectOption", name: "All", value: "" },
          { type_name: "SelectOption", name: "Spring", value: "spring" },
          { type_name: "SelectOption", name: "Summer", value: "summer" },
          { type_name: "SelectOption", name: "Fall", value: "fall" },
          { type_name: "SelectOption", name: "Winter", value: "winter" },
        ]
      },
      {
        type_name: "SelectFilter",
        key: "language",
        name: "Language",
        state: 0,
        values: [
          { type_name: "SelectOption", name: "All", value: "" },
          { type_name: "SelectOption", name: "Sub", value: "1" },
          { type_name: "SelectOption", name: "Dub", value: "2" },
          { type_name: "SelectOption", name: "Sub & Dub", value: "3" },
        ]
      },
      {
        type_name: "SelectFilter",
        key: "sort",
        name: "Sort By",
        state: 0,
        values: [
          { type_name: "SelectOption", name: "Default", value: "default" },
          { type_name: "SelectOption", name: "Recently Added", value: "recently_added" },
          { type_name: "SelectOption", name: "Recently Updated", value: "recently_updated" },
          { type_name: "SelectOption", name: "Score", value: "score" },
          { type_name: "SelectOption", name: "Name A-Z", value: "name_az" },
          { type_name: "SelectOption", name: "Released Date", value: "released_date" },
          { type_name: "SelectOption", name: "Most Watched", value: "most_watched" },
        ]
      },
    ];
  }

  getSourcePreferences() {
    return [];
  }
}
