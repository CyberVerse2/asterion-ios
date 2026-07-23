// ─── Watch Server ───────────────────────────────────────────────────
// Starts a local web app: search anime, browse episodes, watch streams.
//
//   npx tsx src/animepahe/watch-server.ts
//   open http://localhost:3456

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import {
  searchAnime,
  getAnimeDetail,
  listEpisodes,
  getStreamUrl,
} from "./index";

const PORT = parseInt(process.env["PORT"] ?? "3456", 10);

// ─── MIME ───────────────────────────────────────────────────────────

function mime(ext: string): string {
  const map: Record<string, string> = {
    ".html": "text/html",
    ".css":  "text/css",
    ".js":   "application/javascript",
    ".json": "application/json",
    ".png":  "image/png",
    ".jpg":  "image/jpeg",
    ".svg":  "image/svg+xml",
  };
  return map[ext] ?? "text/plain";
}

function json(res: http.ServerResponse, data: unknown, status = 200) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(data));
}

function error(res: http.ServerResponse, msg: string, status = 400) {
  json(res, { error: msg }, status);
}

// ─── Routes ─────────────────────────────────────────────────────────

async function handleAPI(req: http.IncomingMessage, res: http.ServerResponse) {
  const u = new URL(req.url ?? "/", `http://localhost:${PORT}`);
  const p = u.pathname;

  try {
    if (p === "/api/search") {
      const q = u.searchParams.get("q") ?? "";
      const page = parseInt(u.searchParams.get("page") ?? "1", 10);
      if (!q) return error(res, "Missing ?q=");
      const result = await searchAnime(q, page);
      return json(res, result);
    }

    if (p === "/api/anime") {
      const id = u.searchParams.get("id") ?? "";
      if (!id) return error(res, "Missing ?id=");
      const result = await getAnimeDetail(id);
      return json(res, result);
    }

    if (p === "/api/episodes") {
      const id = u.searchParams.get("id") ?? "";
      const page = parseInt(u.searchParams.get("page") ?? "1", 10);
      if (!id) return error(res, "Missing ?id=");
      const result = await listEpisodes(id, page);
      return json(res, result);
    }

    if (p === "/api/watch") {
      const id = u.searchParams.get("id") ?? "";
      const quality = u.searchParams.get("q") ?? "720p";
      if (!id) return error(res, "Missing ?id=");
      const result = await getStreamUrl(id, quality);
      return json(res, result);
    }

    if (p === "/api/set-cookie") {
      const cookie = u.searchParams.get("cookie") ?? "";
      if (!cookie) return error(res, "Missing ?cookie=");
      const { setCloudflareSession } = await import("./cf-bypass");
      setCloudflareSession({
        cfClearance: cookie,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        expiresAt: Date.now() + 25 * 60 * 1000,
      });
      fs.writeFileSync("/tmp/animepahe-cf-cookie.txt", JSON.stringify({ cookie, expires: Date.now() + 25 * 60 * 1000 }));
      return json(res, { ok: true, message: "Cookie saved. API is now live." });
    }

    if (p === "/api/health") {
      const hasCookie = require("fs").existsSync("/tmp/animepahe-cf-cookie.txt");
      return json(res, { ok: true, hasCookie });
    }

    return error(res, "Not found", 404);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    return error(res, msg, 500);
  }
}

// ─── Static Files ───────────────────────────────────────────────────

function serveStatic(res: http.ServerResponse, filePath: string) {
  try {
    const content = fs.readFileSync(filePath);
    const ext = path.extname(filePath);
    res.writeHead(200, { "Content-Type": mime(ext) });
    res.end(content);
  } catch {
    res.writeHead(404);
    res.end("Not found");
  }
}

// ─── Server ─────────────────────────────────────────────────────────

function serverHTML(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Asterion — AnimePahe Watch</title>
<style>
  :root { --bg:#0a0a0f; --surface:#13131f; --border:#1e1e30; --text:#e0e0e0; --muted:#777; --accent:#7c3aed; --accent2:#a78bfa; }
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif; background:var(--bg); color:var(--text); min-height:100vh; }
  .container { max-width:1200px; margin:0 auto; padding:24px 16px; }
  header { display:flex; align-items:center; gap:16px; margin-bottom:32px; flex-wrap:wrap; }
  header h1 { font-size:24px; font-weight:700; background:linear-gradient(135deg,var(--accent2),var(--accent)); -webkit-background-clip:text; -webkit-text-fill-color:transparent; }
  .search-bar { display:flex; gap:8px; flex:1; max-width:500px; }
  .search-bar input { flex:1; padding:10px 16px; border-radius:8px; border:1px solid var(--border); background:var(--surface); color:var(--text); font-size:14px; outline:none; }
  .search-bar input:focus { border-color:var(--accent); }
  .search-bar button { padding:10px 20px; border-radius:8px; border:none; background:var(--accent); color:#fff; font-size:14px; cursor:pointer; font-weight:600; }
  .search-bar button:hover { background:var(--accent2); }
  .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(160px,1fr)); gap:16px; }
  .card { background:var(--surface); border-radius:12px; overflow:hidden; cursor:pointer; transition:transform .15s,border-color .15s; border:1px solid var(--border); }
  .card:hover { transform:translateY(-2px); border-color:var(--accent); }
  .card img { width:100%; aspect-ratio:3/4; object-fit:cover; display:block; background:#1a1a2e; }
  .card .info { padding:10px 12px; }
  .card .title { font-size:13px; font-weight:600; line-height:1.3; display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
  .card .meta { font-size:11px; color:var(--muted); margin-top:4px; }
  .card .score { font-size:11px; color:var(--accent2); margin-top:2px; }
  .back-btn { display:inline-flex; align-items:center; gap:6px; padding:8px 16px; border-radius:8px; border:1px solid var(--border); background:var(--surface); color:var(--text); cursor:pointer; font-size:13px; margin-bottom:16px; }
  .back-btn:hover { border-color:var(--accent); }
  .detail-header { display:flex; gap:24px; margin-bottom:32px; flex-wrap:wrap; }
  .detail-header img { width:200px; border-radius:12px; }
  .detail-info { flex:1; min-width:280px; }
  .detail-info h2 { font-size:22px; margin-bottom:8px; }
  .detail-info p { font-size:13px; color:var(--muted); margin-bottom:6px; }
  .detail-info .synopsis { margin-top:12px; font-size:13px; line-height:1.6; color:var(--text); }
  .episode-list { display:flex; flex-direction:column; gap:4px; }
  .ep-row { display:flex; align-items:center; gap:12px; padding:10px 14px; border-radius:8px; background:var(--surface); cursor:pointer; border:1px solid transparent; transition:border-color .15s; }
  .ep-row:hover { border-color:var(--accent); }
  .ep-num { font-weight:700; font-size:14px; color:var(--accent2); min-width:50px; }
  .ep-info { flex:1; }
  .ep-title { font-size:13px; }
  .ep-meta { font-size:11px; color:var(--muted); }
  .player-wrap { position:relative; width:100%; max-width:960px; margin:0 auto; background:#000; border-radius:12px; overflow:hidden; }
  video { width:100%; display:block; }
  .loading { text-align:center; padding:60px 20px; color:var(--muted); }
  .empty { text-align:center; padding:60px 20px; color:var(--muted); font-size:14px; }
  .badge { display:inline-block; padding:2px 8px; border-radius:4px; font-size:10px; font-weight:600; }
  .badge-tv { background:var(--accent); color:#fff; }
  .badge-movie { background:#e11d48; color:#fff; }
  .error-banner { background:#3b0a0a; border:1px solid #661a1a; color:#fca5a5; padding:12px 16px; border-radius:8px; margin-bottom:16px; font-size:13px; }
  .pagination { display:flex; gap:8px; align-items:center; justify-content:center; margin-top:24px; }
  .pagination button { padding:6px 14px; border-radius:6px; border:1px solid var(--border); background:var(--surface); color:var(--text); cursor:pointer; font-size:13px; }
  .pagination button:disabled { opacity:0.4; cursor:default; }
  .pagination span { font-size:13px; color:var(--muted); }
</style>
</head>
<body>
<div class="container" id="app"></div>

<script>
// ─── Micro Framework ──────────────────────────────────────────
const $ = (sel, ctx) => (ctx||document).querySelector(sel);
const $$ = (sel, ctx) => [...(ctx||document).querySelectorAll(sel)];
const html = (s, ...v) => { const t=document.createElement('template'); t.innerHTML=String.raw(s,...v); return t.content.firstElementChild; };

// ─── State ────────────────────────────────────────────────────
let view = 'search';
let searchResults = null;
let currentAnime = null;
let currentEpisodes = null;
let episodePage = 1;

const API = (p) => fetch('/api'+p).then(r=>r.json());
const IMG = (p) => 'https://animepahe.pw' + p;

// ─── Router ───────────────────────────────────────────────────
function render() {
  const app = $('#app');
  app.innerHTML = '';
  try {
    if (view === 'search') renderSearch(app);
    else if (view === 'detail') renderDetail(app);
    else if (view === 'watch') renderWatch(app);
  } catch(e) { app.innerHTML = '<div class="error-banner">'+e.message+'</div>'; }
}

function pushView(v) { view = v; window.location.hash = v; render(); }

// ─── Search ───────────────────────────────────────────────────
async function doSearch(q) {
  const app = $('#app');
  app.innerHTML = '<div class="loading">Searching...</div>';
  const r = await API('/search?q='+encodeURIComponent(q));
  if (r.error) { app.innerHTML = '<div class="error-banner">'+r.error+'</div>'; return; }
  searchResults = r;
  render();
}

function renderSearch(app) {
  const h = html('<header><h1>Asterion</h1></header>');
  const bar = html('<div class="search-bar"><input placeholder="Search anime..." id="sq"><button id="sb">Search</button></div>');
  h.appendChild(bar);
  app.appendChild(h);

  $('#sb').onclick = () => doSearch($('#sq').value);
  $('#sq').onkeydown = (e) => { if (e.key==='Enter') doSearch($('#sq').value); };

  if (!searchResults || !searchResults.data) {
    const empty = html('<div class="empty">Search for an anime to get started</div>');
    app.appendChild(empty);
    return;
  }

  const grid = html('<div class="grid"></div>');
  for (const a of searchResults.data) {
    const card = html('<div class="card"><img loading="lazy"><div class="info"><div class="title"></div><div class="meta"></div><div class="score"></div></div></div>');
    $('img',card).src = IMG(a.poster);
    $('img',card).alt = a.title;
    $('.title',card).textContent = a.title;
    $('.meta',card).textContent = a.type + ' \u2022 ' + (a.episodes||'?') + ' eps';
    $('.score',card).textContent = '\u2605 ' + (a.score||'N/A');
    card.onclick = () => { currentAnime = a; pushView('detail'); };
    grid.appendChild(card);
  }
  app.appendChild(grid);

  // Pagination
  if (searchResults.last_page > 1) {
    const pg = html('<div class="pagination"></div>');
    const prev = html('<button>&larr; Prev</button>');
    prev.disabled = searchResults.current_page <= 1;
    prev.onclick = () => doSearch($('#sq').value, searchResults.current_page-1);
    const next = html('<button>Next &rarr;</button>');
    next.disabled = searchResults.current_page >= searchResults.last_page;
    next.onclick = () => doSearch($('#sq').value, searchResults.current_page+1);
    const info = html('<span>Page '+searchResults.current_page+'/'+searchResults.last_page+'</span>');
    pg.append(prev, info, next);
    app.appendChild(pg);
  }
}

// ─── Detail ──────────────────────────────────────────────────
async function loadDetail() {
  const app = $('#app');
  app.innerHTML = '<div class="loading">Loading...</div>';
  const r = await API('/anime?id='+encodeURIComponent(currentAnime.session));
  if (r.error || !r.data) { app.innerHTML = '<div class="error-banner">'+((r||{}).error||'Failed to load')+'</div>'; return; }
  // animepahe sometimes nests data differently
  currentAnime = typeof r.data === 'object' && r.data.title ? r.data : currentAnime;
  const eps = await API('/episodes?id='+encodeURIComponent(currentAnime.session)+'&page='+episodePage);
  if (eps.error) { app.innerHTML = '<div class="error-banner">'+eps.error+'</div>'; return; }
  currentEpisodes = eps;
  render();
}

function renderDetail(app) {
  const back = html('<button class="back-btn">&larr; Back to search</button>');
  back.onclick = () => { pushView('search'); };
  app.appendChild(back);

  const a = currentAnime;
  if (!a.session) { loadDetail(); return; }

  const header = html('<div class="detail-header"></div>');
  header.innerHTML = '<img src="'+IMG(a.poster||'')+'" onerror="this.src=\\'data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 200 300%22><rect fill=%22%2313131f%22 width=%22200%22 height=%22300%22/></svg>\\'">';

  const info = html('<div class="detail-info"></div>');
  const badgetype = a.type === 'Movie' ? 'badge-movie' : 'badge-tv';
  info.innerHTML =
    '<h2>'+a.title+'</h2>'+
    '<p><span class="badge '+badgetype+'">'+a.type+'</span> &nbsp; \u2605 '+(a.score||'N/A')+' &nbsp; \u2022 &nbsp; '+(a.episodes||'?')+' episodes</p>'+
    '<p>'+(a.status||'')+'</p>'+
    (a.synopsis ? '<p class="synopsis">'+(a.synopsis||'').slice(0,500)+'</p>' : '');
  header.appendChild(info);
  app.appendChild(header);

  if (!currentEpisodes) { loadDetail(); return; }
  if (currentEpisodes.error) {
    app.appendChild(html('<div class="error-banner">'+currentEpisodes.error+'</div>'));
    return;
  }

  const list = html('<div class="episode-list"></div>');
  for (const ep of (currentEpisodes.data||[])) {
    const row = html('<div class="ep-row"><span class="ep-num"></span><div class="ep-info"><div class="ep-title"></div><div class="ep-meta"></div></div></div>');
    $('.ep-num',row).textContent = 'Ep '+ep.episode;
    $('.ep-title',row).textContent = (ep.fansub||'') + ' \u2022 ' + (ep.audio||'');
    $('.ep-meta',row).textContent = (ep.duration||'') + (ep.aired ? ' \u2022 '+ep.aired : '');
    row.onclick = () => { currentEpisodes.currentEp = ep; pushView('watch'); };
    list.appendChild(row);
  }
  app.appendChild(list);

  if (currentEpisodes.last_page > 1) {
    const pg = html('<div class="pagination"></div>');
    const prev = html('<button>&larr;</button>');
    prev.disabled = currentEpisodes.current_page <= 1;
    prev.onclick = () => { episodePage--; loadDetail(); };
    const next = html('<button>&rarr;</button>');
    next.disabled = currentEpisodes.current_page >= currentEpisodes.last_page;
    next.onclick = () => { episodePage++; loadDetail(); };
    const info = html('<span>Page '+currentEpisodes.current_page+'/'+currentEpisodes.last_page+'</span>');
    pg.append(prev, info, next);
    app.appendChild(pg);
  }
}

// ─── Watch ────────────────────────────────────────────────────
async function loadWatch() {
  const app = $('#app');
  app.innerHTML = '<div class="loading">Loading stream...</div>';
  const id = currentEpisodes?.currentEp?.session;
  if (!id) { app.innerHTML = '<div class="error-banner">No episode selected</div>'; return; }
  const r = await API('/watch?id='+encodeURIComponent(id)+'&q=720p');
  if (typeof r === 'string') {
    renderWatchWithUrl(r);
  } else if (r.error) {
    app.innerHTML = '<div class="error-banner">'+r.error+'</div>';
  } else {
    app.innerHTML = '<div class="error-banner">Unexpected response</div>';
  }
}

function renderWatchWithUrl(url) {
  const app = $('#app');
  const back = html('<button class="back-btn">&larr; Back to episodes</button>');
  back.onclick = () => { pushView('detail'); };
  app.appendChild(back);

  const ep = currentEpisodes?.currentEp;
  const title = html('<h3 style="margin-bottom:16px">'+ (currentAnime?.title||'') + ' \u2014 Ep ' + (ep?.episode||'') + '</h3>');
  app.appendChild(title);

  const isHLS = url.endsWith('.m3u8') || url.includes('m3u8');
  const playerWrap = html('<div class="player-wrap"></div>');

  if (isHLS) {
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/hls.js@latest';
    script.onload = () => {
      const video = document.createElement('video');
      video.controls = true;
      video.autoplay = true;
      video.style.width = '100%';
      if (Hls.isSupported()) {
        const hls = new Hls({ enableWorker: false });
        hls.loadSource(url);
        hls.attachMedia(video);
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = url;
      }
      playerWrap.appendChild(video);
    };
    document.head.appendChild(script);
  } else {
    const video = html('<video controls autoplay style="width:100%"></video>');
    video.src = url;
    playerWrap.appendChild(video);
  }

  app.appendChild(playerWrap);
  app.appendChild(html('<p style="text-align:center;margin-top:12px;font-size:11px;color:var(--muted)">Stream URL: '+url+'</p>'));
}

function renderWatch(app) {
  if (!currentEpisodes?.currentEp) { pushView('detail'); return; }
  loadWatch();
}

// ─── Init ─────────────────────────────────────────────────────
render();
</script>
</body>
</html>`;
}

// ─── Setup Page (shown when no cookie cached) ──────────────────────

function SETUP_HTML(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Asterion — Setup</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif; background:#0a0a0f; color:#e0e0e0; min-height:100vh; display:flex; align-items:center; justify-content:center; }
  .card { background:#13131f; border:1px solid #1e1e30; border-radius:16px; padding:32px; max-width:520px; width:100%; margin:16px; }
  h1 { font-size:22px; background:linear-gradient(135deg,#a78bfa,#7c3aed); -webkit-background-clip:text; -webkit-text-fill-color:transparent; margin-bottom:8px; }
  .sub { color:#777; font-size:13px; margin-bottom:24px; }
  .step { margin-bottom:20px; }
  .step h3 { font-size:14px; color:#a78bfa; margin-bottom:6px; }
  .step p, .step code { font-size:13px; color:#aaa; line-height:1.6; }
  .step code { background:#1a1a2e; padding:2px 6px; border-radius:4px; color:#c4b5fd; font-size:12px; }
  .step a { color:#7c3aed; }
  .paste-area { width:100%; }
  .paste-area input { width:100%; padding:12px 16px; border-radius:8px; border:1px solid #1e1e30; background:#0a0a0f; color:#e0e0e0; font-size:13px; outline:none; font-family:monospace; }
  .paste-area input:focus { border-color:#7c3aed; }
  .paste-area button { width:100%; margin-top:8px; padding:12px; border-radius:8px; border:none; background:#7c3aed; color:#fff; font-size:14px; font-weight:600; cursor:pointer; }
  .paste-area button:hover { background:#a78bfa; }
  .status { margin-top:12px; font-size:13px; text-align:center; }
  .status-ok { color:#4ade80; }
  .status-err { color:#f87171; }
</style>
</head>
<body>
<div class="card">
  <h1>Asterion Watch</h1>
  <p class="sub">One-time setup — paste your Cloudflare cookie to unlock the API.</p>

  <div class="step">
    <h3>1. Open animepahe.pw in Chrome</h3>
    <p>Make sure you're already on the homepage (the Cloudflare check must have passed).</p>
  </div>

  <div class="step">
    <h3>2. Copy the cookie</h3>
    <p>Open DevTools (<code>Cmd+Opt+I</code>), go to <strong>Application</strong> → <strong>Cookies</strong> → <strong>animepahe.pw</strong>, and copy the value of <code>cf_clearance</code>.</p>
    <p style="margin-top:4px">Or paste this in the console:</p>
    <code style="display:block;margin-top:4px;padding:8px 12px;word-break:break-all">copy(document.cookie.split('; ').find(c=>c.startsWith('cf_clearance='))?.split('=')[1] || 'not found')</code>
  </div>

  <div class="step">
    <h3>3. Paste below</h3>
    <div class="paste-area">
      <input id="cookie-input" placeholder="Paste cf_clearance value here...">
      <button id="save-btn">Save & Continue</button>
      <div id="status"></div>
    </div>
  </div>
</div>

<script>
const inp = document.getElementById('cookie-input');
const btn = document.getElementById('save-btn');
const status = document.getElementById('status');

btn.onclick = async () => {
  const val = inp.value.trim();
  if (!val) { status.className='status status-err'; status.textContent='Please paste a cookie value'; return; }
  status.className='status'; status.textContent='Saving...';
  try {
    const r = await fetch('/api/set-cookie?cookie=' + encodeURIComponent(val));
    const d = await r.json();
    if (d.ok) { status.className='status status-ok'; status.textContent='Done! Reloading...'; setTimeout(()=>location.reload(),800); }
    else { status.className='status status-err'; status.textContent=d.error||'Failed'; }
  } catch(e) { status.className='status status-err'; status.textContent='Network error'; }
};
inp.onkeydown = (e) => { if(e.key==='Enter') btn.click(); };
</script>
</body>
</html>`;
}

const server = http.createServer(async (req, res) => {
  const u = req.url ?? "/";

  res.setHeader("Access-Control-Allow-Origin", "*");

  if (u.startsWith("/api/")) {
    return handleAPI(req, res);
  }

  // Show setup page if no cookie cached
  if (!fs.existsSync("/tmp/animepahe-cf-cookie.txt") && !u.includes("?")) {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(SETUP_HTML);
    return;
  }

  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(serverHTML());
});

// ─── Start ──────────────────────────────────────────────────────────

async function main() {
  server.listen(PORT, () => {
    console.log(`\n  Asterion Watch: http://localhost:${PORT}\n`);
    if (!fs.existsSync("/tmp/animepahe-cf-cookie.txt")) {
      console.log("  No cookie cached. Open the URL above to set up.\n");
    }
  });

  // Try auto-solve in background, but don't block
  import("./cf-browser").then(async ({ startCookieRefresh, browserFetch }) => {
    const { setGlobalFetch } = await import("./api");
    startCookieRefresh().then((ok) => {
      if (ok) {
        setGlobalFetch(browserFetch as unknown as typeof fetch);
        console.log("[watch-server] Auto cookie acquired.");
      }
    });
  });
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
