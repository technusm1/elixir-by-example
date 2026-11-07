// elixirbyexample.com edge worker.
//
// Runs in front of every request to:
//   1. set security and cross-origin isolation headers (Popcorn needs
//      SharedArrayBuffer, which needs COOP/COEP),
//   2. serve Popcorn's large runtime archives pre-compressed with Brotli,
//   3. redirect URLs from the old Jekyll site,
//   4. count requests in D1, including AI agents and tools, which never run JS.
//
// Privacy: no cookies, no IP addresses, no visitor ids. Only path, coarse client
// class, referrer host, country and device class are stored.

const SITE_HOST = "elixirbyexample.com";
const MAX_FIELD = 300;

// Old Jekyll permalinks (/:basename) → new pages. Anything else old goes home.
const OLD_PAGES = {
  "your-first-elixir-code": "/core/hello-world",
  "basic-types": "/core/values",
  "basic-operators": "/core/values",
  "functions": "/core/functions",
  "modules": "/core/modules",
  "pattern-matching-and-guards": "/core/pattern-matching",
  "sigils": "/core/sigils",
  "pipe-operator": "/core/pipe-operator",
  "collections": "/core/lists-and-tuples",
  "structs": "/core/structs",
  "protocols": "/core/protocols",
  "error-handling": "/core/errors",
  "strings": "/core/strings",
  "stream-and-enum-modules": "/core/enum",
  "processes-and-ipc": "/otp/processes",
  "genserver": "/otp/genserver",
  "task": "/otp/task",
  "agent": "/otp/agent",
  "supervisors": "/otp/supervisors",
  "ets": "/otp/ets",
};
const OLD_OTHER = new Set([
  "introduction-to-elixir", "iex-introduction", "concepts", "date-and-time", "file-io",
  "mix-introduction", "iex-and-mix-in-depth", "mnesia", "metaprogramming",
  "distributed-applications", "integrating-other-languages", "testing", "benchmarking",
  "profiling", "telemetry", "property-based-testing", "code-improvement-with-3rd-party-tools",
  "sql-and-ecto", "phoenix", "genstage", "flow", "broadway", "behaviours",
]);

// Order matters: first match wins.
const AGENTS = [
  ["Claude-User", "agent"], ["Claude-SearchBot", "agent"], ["ClaudeBot", "crawler"],
  ["Claude-Code", "agent"], ["anthropic-ai", "crawler"],
  ["ChatGPT-User", "agent"], ["OAI-SearchBot", "agent"], ["GPTBot", "crawler"],
  ["Perplexity-User", "agent"], ["PerplexityBot", "crawler"],
  ["MistralAI-User", "agent"], ["DuckAssistBot", "agent"], ["Google-CloudVertexBot", "agent"],
  ["Gemini-Deep-Research", "agent"], ["cohere-ai", "crawler"], ["meta-externalagent", "crawler"],
  ["CCBot", "crawler"], ["Bytespider", "crawler"], ["Amazonbot", "crawler"],
  ["Applebot", "crawler"], ["Googlebot", "crawler"], ["bingbot", "crawler"],
  ["DuckDuckBot", "crawler"], ["YandexBot", "crawler"], ["Baiduspider", "crawler"],
  ["curl", "tool"], ["Wget", "tool"], ["python-requests", "tool"], ["python-httpx", "tool"],
  ["aiohttp", "tool"], ["axios", "tool"], ["node-fetch", "tool"], ["undici", "tool"],
  ["Go-http-client", "tool"], ["Req/", "tool"], ["Mint/", "tool"], ["Finch", "tool"],
  ["HTTPoison", "tool"],
];
const GENERIC_BOT = /bot|crawl|spider|slurp|preview|headless|lighthouse|monitor|scan/i;

const SECURITY_HEADERS = {
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Embedder-Policy": "require-corp",
  "Cross-Origin-Resource-Policy": "same-origin",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  // 'unsafe-eval' and 'wasm-unsafe-eval' are required by Popcorn (BEAM in Wasm).
  "Content-Security-Policy": [
    "default-src 'self'",
    "script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data:",
    "connect-src 'self'",
    "worker-src 'self' blob:",
    "object-src 'none'",
    "base-uri 'none'",
    "frame-ancestors 'none'",
  ].join("; "),
};

const HASHED = /\.[a-f0-9]{64}\.(tar|boot)$/;
const POPCORN_PRECOMPRESSED = /^\/popcorn\/.*\.(tar|wasm|mjs)$/;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.hostname === `www.${SITE_HOST}`) {
      url.hostname = SITE_HOST;
      return Response.redirect(url.toString(), 301);
    }

    if (url.pathname === "/a") return beacon(request, env, ctx);

    const redirect = oldUrl(url.pathname);
    if (redirect) return Response.redirect(new URL(redirect, url.origin).toString(), 301);

    let response =
      POPCORN_PRECOMPRESSED.test(url.pathname) && acceptsBrotli(request)
        ? await brotli(request, env, url)
        : await env.ASSETS.fetch(request);

    response = withHeaders(response, url.pathname);

    if (request.method === "GET") {
      const kind = classifyRequest(url.pathname, response.status);
      if (kind) ctx.waitUntil(record(env, request, kind, url.pathname));
    }

    return response;
  },
};

function oldUrl(pathname) {
  const slug = pathname.replace(/^\/+|\/+$/g, "").replace(/\.html$/, "");
  if (slug.includes("/")) return null;
  if (OLD_PAGES[slug]) return OLD_PAGES[slug];
  if (OLD_OTHER.has(slug)) return "/";
  return null;
}

function acceptsBrotli(request) {
  return /\bbr\b/.test(request.headers.get("Accept-Encoding") || "");
}

// Serve `<file>.br` with the original file's content type. `encodeBody: "manual"`
// tells the runtime the body is already encoded, so it isn't compressed twice.
async function brotli(request, env, url) {
  const compressedUrl = new URL(url.pathname + ".br", url.origin);
  const asset = await env.ASSETS.fetch(new Request(compressedUrl, request));
  if (!asset.ok) return env.ASSETS.fetch(request);

  const headers = new Headers(asset.headers);
  headers.set("Content-Encoding", "br");
  headers.set("Content-Type", contentType(url.pathname));
  headers.set("Vary", "Accept-Encoding");
  headers.delete("Content-Length");
  return new Response(asset.body, { status: 200, headers, encodeBody: "manual" });
}

function contentType(pathname) {
  if (pathname.endsWith(".wasm")) return "application/wasm";
  if (pathname.endsWith(".mjs")) return "text/javascript; charset=utf-8";
  return "application/x-tar";
}

function withHeaders(asset, pathname) {
  const response = new Response(asset.body, asset);
  const h = response.headers;
  for (const [name, value] of Object.entries(SECURITY_HEADERS)) h.set(name, value);

  if (pathname.endsWith(".exs") || pathname.endsWith(".txt")) {
    // Plain sources and llms.txt are meant to be fetched by anyone, including
    // agents and tools running in other origins.
    h.set("Content-Type", "text/plain; charset=utf-8");
    h.set("Access-Control-Allow-Origin", "*");
    h.set("Cross-Origin-Resource-Policy", "cross-origin");
  }

  if (HASHED.test(pathname)) {
    h.set("Cache-Control", "public, max-age=31536000, immutable");
  } else if (pathname.startsWith("/popcorn/")) {
    h.set("Cache-Control", "public, max-age=3600, must-revalidate");
  }
  return response;
}

function classifyRequest(pathname, status) {
  if (status === 404) return "notfound";
  if (status !== 200) return null;
  if (pathname.endsWith(".exs")) return "raw";
  if (pathname === "/llms.txt" || pathname === "/llms-full.txt") return "llms";
  if (pathname === "/" || !/\.[a-z0-9]+$/i.test(pathname)) return "page";
  return null; // assets: css, js, popcorn runtime, favicon, sitemap...
}

// POST /a  {"e":"run","p":"/core/maps"}  sent by run.js when a reader runs code.
async function beacon(request, env, ctx) {
  if (request.method !== "POST") {
    return new Response(null, { status: 405, headers: { Allow: "POST" } });
  }
  const body = await request.text();
  if (body.length > 1024) return new Response(null, { status: 413 });

  let data;
  try {
    data = JSON.parse(body);
  } catch {
    return new Response(null, { status: 400 });
  }
  if (data.e === "run" && typeof data.p === "string" && data.p.startsWith("/")) {
    ctx.waitUntil(record(env, request, "run", data.p));
  }
  return new Response(null, { status: 204 });
}

function classifyClient(ua) {
  if (!ua) return ["tool", "unknown"];
  for (const [needle, client] of AGENTS) {
    if (ua.includes(needle)) return [client, needle.replace(/\/$/, "")];
  }
  if (GENERIC_BOT.test(ua)) return ["crawler", "other"];
  return ["human", null];
}

async function record(env, request, kind, path) {
  const ua = request.headers.get("User-Agent") || "";
  const [client, agent] = classifyClient(ua);
  try {
    await env.DB.prepare(
      "INSERT INTO hits (ts, kind, path, client, agent, ref, country, device) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    )
      .bind(
        Math.floor(Date.now() / 1000),
        kind,
        clip(path),
        client,
        agent,
        refHost(request.headers.get("Referer")),
        request.cf?.country || null,
        client === "human" ? device(ua) : null,
      )
      .run();
  } catch (err) {
    console.error("analytics insert failed", err);
  }
}

function refHost(referer) {
  if (!referer) return "";
  try {
    const host = new URL(referer).hostname;
    return host === SITE_HOST ? "" : clip(host);
  } catch {
    return "";
  }
}

function device(ua) {
  if (/iPad|Tablet/i.test(ua)) return "tablet";
  if (/Mobi|iPhone|Android/i.test(ua)) return "phone";
  return "desktop";
}

function clip(value) {
  return typeof value === "string" ? value.slice(0, MAX_FIELD) : null;
}
