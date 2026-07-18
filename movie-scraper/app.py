"""
Soap2Day browser — Flask API with built-in frontend.
Install: pip install -r requirements.txt
Run:     python app.py
Open:    http://localhost:8080
"""

import logging
import os
import re
from functools import wraps
from urllib.parse import urlparse, urljoin

import flask
import requests as req_lib
import soap2day

app = flask.Flask(__name__)

ALLOWED_EMBED_HOSTS = frozenset({
    "vidapi.xyz", "videasy.net", "vidking.net", "moviesapi.to",
    "share.cdnm.ink", "multiembed.mov", "vidfast.pro",
    "vsembed.su", "embedmaster.link", "nontongo.win",
})


# ---------------------------------------------------------------------------
# API endpoints
# ---------------------------------------------------------------------------


def _json_or_error(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            result = fn(*args, **kwargs)
            return flask.jsonify(result)
        except Exception:
            app.logger.exception("Soap2Day scraper request failed")
            return flask.jsonify({"error": "The source request failed."}), 502
    return wrapper


@app.after_request
def add_security_headers(response):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    return response


@app.route("/api/health")
def api_health():
    return {"status": "ok"}


@app.route("/api/search")
@_json_or_error
def api_search():
    q = flask.request.args.get("q", "").strip()
    if not q:
        return []
    return _search_result_list(soap2day.search(q))


@app.route("/api/movies")
@_json_or_error
def api_movies():
    page = int(flask.request.args.get("page", "1"))
    return _paginated_result(soap2day.movies(page), page, 464)


@app.route("/api/tv")
@_json_or_error
def api_tv():
    page = int(flask.request.args.get("page", "1"))
    return _paginated_result(soap2day.tv_shows(page), page, 100)


@app.route("/api/trending/movies")
@_json_or_error
def api_trending_movies():
    return _search_result_list(soap2day.trending_movies())


@app.route("/api/trending/tv")
@_json_or_error
def api_trending_tv():
    return _search_result_list(soap2day.trending_tv())


@app.route("/api/popular/movies")
@_json_or_error
def api_popular_movies():
    return _search_result_list(soap2day.popular_movies())


@app.route("/api/popular/tv")
@_json_or_error
def api_popular_tv():
    return _search_result_list(soap2day.popular_tv())


@app.route("/api/genre/<genre_slug>")
@_json_or_error
def api_genre(genre_slug):
    page = int(flask.request.args.get("page", "1"))
    return _search_result_list(soap2day.by_genre(genre_slug, page))


@app.route("/api/year/<year>")
@_json_or_error
def api_year(year):
    page = int(flask.request.args.get("page", "1"))
    return _search_result_list(soap2day.by_release_year(year, page))


@app.route("/api/episodes")
@_json_or_error
def api_episodes():
    page = int(flask.request.args.get("page", "1"))
    return _search_result_list(soap2day.episodes_listing(page))


@app.route("/api/show/<path:slug>")
@_json_or_error
def api_show(slug):
    detail = soap2day.show_detail(slug)
    if not detail:
        return {"error": "Not found"}, 404
    result = detail.__dict__.copy()
    result["streams"] = _stream_list_for_api(detail.streams)
    return result


@app.route("/api/show/<path:slug>/episodes")
@_json_or_error
def api_show_episodes(slug):
    eps = soap2day.series_episodes(slug)
    return [e.__dict__ for e in eps]


@app.route("/proxy/embed")
def proxy_embed():
    """Proxy an embed iframe for display."""
    target = flask.request.args.get("url", "")
    if not target:
        return "No URL provided", 400
    return flask.redirect(target)


@app.route("/proxy/hls")
def proxy_hls():
    """Proxy HLS playlist and TS segments to bypass CORS."""
    target = flask.request.args.get("url", "")
    if not target or not target.startswith("https://"):
        return "Invalid URL", 400

    try:
        resp = req_lib.get(target, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Accept": "*/*",
            "Origin": "https://play.xpass.top",
            "Referer": "https://play.xpass.top/",
        }, stream=True, timeout=30)
    except Exception as e:
        app.logger.exception("HLS proxy fetch failed")
        return f"Upstream error: {e}", 502

    content_type = resp.headers.get("Content-Type", "application/octet-stream")
    is_m3u8 = ".m3u8" in target or "mpegurl" in content_type or "x-mpegURL" in content_type

    if is_m3u8:
        body = resp.text
        # Rewrite relative .m3u8/.ts/.aac URLs through proxy
        base = target.rsplit("/", 1)[0]
        proxy_base = flask.request.url_root.rstrip("/") + "/proxy/hls?url="
        body = re.sub(
            r'^([^#\s][^\s]*\.(?:m3u8|ts|aac|mp4))',
            lambda m: proxy_base + urljoin(base + "/", m.group(1)),
            body, flags=re.MULTILINE
        )
        rv = flask.Response(body, content_type=content_type)
        rv.headers["Access-Control-Allow-Origin"] = "*"
        return rv

    def generate():
        try:
            for chunk in resp.iter_content(chunk_size=65536):
                if chunk:
                    yield chunk
        finally:
            resp.close()

    rv = flask.Response(flask.stream_with_context(generate()), content_type=content_type)
    rv.headers["Access-Control-Allow-Origin"] = "*"
    rv.headers["Cache-Control"] = "public, max-age=3600"
    return rv


# ---------------------------------------------------------------------------
# Helper serialization
# ---------------------------------------------------------------------------


def _search_result_list(results: list[soap2day.SearchResult]) -> list[dict]:
    return [r.__dict__ for r in results]


def _paginated_result(results: list[soap2day.SearchResult], page: int, total: int) -> dict:
    return {
        "page": page,
        "total_pages": total,
        "results": [r.__dict__ for r in results],
    }


def _stream_list_for_api(streams: list[soap2day.StreamServer]) -> list[dict]:
    result = []
    for s in streams:
        d = s.__dict__.copy()
        url = d.get("embed_url", "")
        is_hls = (
            ".m3u8" in url or
            "1x2.space" in url or
            "greenplanetstore" in url or
            "workers.dev" in url or
            "tik." in url or
            "vip." in url or
            url.endswith(".txt")
        )
        d["is_hls"] = is_hls
        if is_hls:
            d["proxy_url"] = f"/proxy/hls?url={url}"
        result.append(d)
    return result


# ---------------------------------------------------------------------------
# Frontend (SPA)
# ---------------------------------------------------------------------------

INDEX = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Soap2Day Browser</title>
<style>
:root {
  --bg: #0a0a10; --surface: #141420; --border: #26263a;
  --text: #e0e0ec; --muted: #7a7a90; --accent: #7c3aed;
  --accent-dim: #7c3aed22; --green: #22c55e; --orange: #f59e0b;
  --radius: 10px;
}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Inter,sans-serif;background:var(--bg);color:var(--text);height:100vh;overflow:hidden;display:flex}
a{color:var(--accent);text-decoration:none}

#sidebar{width:360px;min-width:320px;display:flex;flex-direction:column;border-right:1px solid var(--border);background:var(--surface)}
#tabs{display:flex;border-bottom:1px solid var(--border)}
#tabs button{flex:1;background:none;border:none;color:var(--muted);padding:10px;cursor:pointer;font-size:13px;font-weight:600;transition:.15s}
#tabs button:hover,#tabs button.active{color:var(--accent);border-bottom:2px solid var(--accent);margin-bottom:-1px}
#search-bar{display:flex;align-items:center;gap:8px;padding:10px 14px;border-bottom:1px solid var(--border)}
#search-bar input{flex:1;background:var(--bg);border:1px solid var(--border);color:var(--text);padding:8px 12px;border-radius:8px;font-size:13px;outline:none}
#search-bar input:focus{border-color:var(--accent)}
#results{flex:1;overflow-y:auto;padding:6px}
.card{display:flex;gap:10px;padding:8px;border-radius:var(--radius);cursor:pointer;transition:background .15s;margin-bottom:2px}
.card:hover{background:var(--accent-dim)}
.card img{width:48px;height:68px;border-radius:6px;object-fit:cover;background:var(--border);flex-shrink:0}
.card-info{flex:1;min-width:0}
.card-info .title{font-size:13px;font-weight:600;line-height:1.3;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.card-info .sub{font-size:11px;color:var(--muted);margin-top:2px}
.card .rating{font-size:11px;font-weight:700;color:var(--green);margin-top:2px}
.card .rating.mid{color:var(--orange)}

#main{flex:1;display:flex;flex-direction:column;overflow:hidden}
#player-wrap{background:#000;flex-shrink:0;display:none;position:relative}
#player-wrap.visible{display:block}
#player-wrap iframe{width:100%;height:440px;border:0;display:block}
#player-tabs{display:flex;gap:4px;padding:6px 14px;background:var(--surface);border-bottom:1px solid var(--border);overflow-x:auto;display:none}
#player-bar.visible #player-tabs{display:flex}
#player-tabs button{background:var(--bg);border:1px solid var(--border);color:var(--muted);padding:4px 12px;border-radius:6px;font-size:12px;cursor:pointer;white-space:nowrap;transition:.15s}
#player-tabs button:hover,#player-tabs button.active{border-color:var(--accent);color:var(--text)}
#player-extlink{display:block;padding:6px 14px;font-size:12px;color:var(--accent);text-align:center;border-bottom:1px solid var(--border);background:var(--surface)}
#player-extlink:hover{text-decoration:underline}
#detail{flex:1;overflow-y:auto;padding:20px 28px}
#detail .hero{display:flex;gap:20px;margin-bottom:16px}
#detail .hero img{width:130px;height:190px;border-radius:var(--radius);object-fit:cover;background:var(--border)}
#detail .hero h2{font-size:20px;margin-bottom:6px}
#detail .hero .meta{font-size:12px;color:var(--muted);margin-bottom:2px}
#detail .hero .desc{font-size:13px;color:var(--muted);line-height:1.5;margin-top:8px;max-height:120px;overflow-y:auto}
#detail .ratings{display:flex;gap:16px;margin-bottom:16px}
#detail .ratings .r{text-align:center}
#detail .ratings .r .val{font-size:18px;font-weight:700}
#detail .ratings .r .lbl{font-size:10px;color:var(--muted);text-transform:uppercase}
.chips{display:flex;flex-wrap:wrap;gap:4px;margin-bottom:12px}
.chip{font-size:11px;padding:3px 8px;border-radius:4px;background:var(--accent-dim);color:var(--accent)}
.placeholder{display:flex;align-items:center;justify-content:center;height:100%;color:var(--muted);font-size:14px;text-align:center}
.loading{color:var(--muted);padding:20px;text-align:center}
.episodes{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:6px}
.ep-btn{background:var(--surface);border:1px solid var(--border);color:var(--text);padding:8px 12px;border-radius:6px;font-size:12px;cursor:pointer;text-align:left;transition:.15s}
.ep-btn:hover{border-color:var(--accent);background:var(--accent-dim)}
</style>
<script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
</head>
<body>

<div id="sidebar">
  <div id="tabs">
    <button data-tab="movies" class="active">Movies</button>
    <button data-tab="tv">TV Shows</button>
    <button data-tab="trending">Trending</button>
  </div>
  <div id="search-bar">
    <input id="search-input" type="text" placeholder="Search movies & TV..." autocomplete="off">
  </div>
  <div id="results"><div class="loading">Loading movies...</div></div>
</div>

<div id="main">
  <div id="player-wrap">
    <iframe id="player-frame" allowfullscreen allow="autoplay; encrypted-media; picture-in-picture"></iframe>
    <video id="player-video" controls playsinline crossorigin="anonymous" style="display:none;width:100%;height:440px"></video>
  </div>
  <div id="subtitle-bar" style="display:none;padding:4px 14px;background:var(--surface);border-bottom:1px solid var(--border);font-size:12px;color:var(--muted);gap:6px;align-items:center;flex-wrap:wrap">
    <span>Subtitles:</span>
    <select id="subtitle-select" style="background:var(--bg);border:1px solid var(--border);color:var(--text);padding:2px 6px;border-radius:4px;font-size:11px"></select>
    <a id="subtitle-extlink" href="#" target="_blank" rel="noopener" style="color:var(--accent);font-size:11px;margin-left:auto;display:none">Open with subtitles →</a>
  </div>
  <div id="player-bar">
    <div id="player-tabs"></div>
    <a id="player-extlink" href="#" target="_blank" rel="noopener" style="display:none">Open in new tab (adblock works)</a>
  </div>
  <div id="detail">
    <div class="placeholder">Select a title from the left to view details</div>
  </div>
</div>

<script>
const $=s=>document.querySelector(s);const $$=s=>document.querySelectorAll(s);
let currentShow=null,currentStreams=[],activeServer=0,currentEmbedUrls=[];
let currentTab='movies',currentPage=1,totalPages=1,hlsInstance=null;
async function api(path){const r=await fetch(path);return r.json()}

function esc(s){return(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}

function renderCards(items,container,append){
  if(!append)container.innerHTML='';
  if(!items.length&&!append){container.innerHTML='<div class="loading">No results</div>';return}
  var html=items.map(item=>`
    <div class="card" data-url="${esc(item.url||'')}" data-title="${esc(item.title)}">
      <img src="${item.image_url||''}" loading="lazy" onerror="this.style.display='none'">
      <div class="card-info">
        <div class="title">${esc(item.title)}</div>
        ${item.runtime?`<div class="sub">${esc(item.runtime)} ${item.quality||''}</div>`:''}
        ${item.imdb_rating?`<div class="rating ${parseFloat(item.imdb_rating)<7?'mid':''}">IMDb ${item.imdb_rating}</div>`:''}
      </div>
    </div>`).join('');
  container.insertAdjacentHTML('beforeend',html);
  container.querySelectorAll('.card:not([data-bound])').forEach(card=>{
    card.dataset.bound='1';
    card.addEventListener('click',()=>{
      const slug=card.dataset.url.replace(/^https?:\/\/[^/]+\//,'').replace(/\/$/,'');
      loadShow(slug);
    });
  });
}

async function loadShow(slug){
  $('#detail').innerHTML='<div class="loading">Loading...</div>';
  $('#player-frame').src='';$('#player-frame').style.display='none';
  $('#player-video').style.display='none';$('#player-video').src='';
  if(hlsInstance){hlsInstance.destroy();hlsInstance=null;}
  $('#player-wrap').classList.remove('visible');
  $('#player-bar').classList.remove('visible');$('#player-tabs').innerHTML='';
  $('#player-extlink').style.display='none';$('#player-extlink').href='#';
  try{
    const show=await api('/api/show/'+slug);
    if(show.error){$('#detail').innerHTML='<div class="placeholder">Not found</div>';return}
    currentShow=show;currentStreams=show.streams||[];activeServer=0;
    renderDetail(show);
    if(currentStreams.length>0)playServer(0);
  }catch(e){$('#detail').innerHTML='<div class="placeholder">Failed to load</div>'}
}

function renderDetail(show){
  const ratings=`
    ${show.imdb_rating?`<div class="r"><div class="val" style="color:${parseFloat(show.imdb_rating)>=7?'var(--green)':'var(--orange)'}">${show.imdb_rating}</div><div class="lbl">IMDb</div></div>`:''}
    ${show.tmdb_rating?`<div class="r"><div class="val" style="color:var(--orange)">${show.tmdb_rating}</div><div class="lbl">TMDb</div></div>`:''}
    ${show.rotten_tomatoes?`<div class="r"><div class="val" style="color:var(--green)">${show.rotten_tomatoes}%</div><div class="lbl">RT</div></div>`:''}
    ${show.metacritic?`<div class="r"><div class="val" style="color:var(--orange)">${show.metacritic}</div><div class="lbl">Meta</div></div>`:''}
  `;
  const chips=[...(show.genres||[])].map(g=>`<span class="chip">${esc(g)}</span>`).join('');
  const meta=`${show.duration||''} &middot; ${show.release_year||''} ${show.country?'&middot; '+esc(show.country):''}`;
  $('#detail').innerHTML=`
    <div class="hero">
      <img src="${show.image_url||''}" onerror="this.style.display='none'">
      <div>
        <h2>${esc(show.title)}</h2>
        ${show.director?`<div class="meta">Directed by ${esc(show.director)}</div>`:''}
        <div class="meta">${meta}</div>
        ${show.actors.length?`<div class="meta">Starring: ${show.actors.slice(0,5).map(esc).join(', ')}</div>`:''}
        ${show.description?`<div class="desc">${esc(show.description)}</div>`:''}
      </div>
    </div>
    <div class="ratings">${ratings}</div>
    <div class="chips">${chips}</div>
  `;
  renderServerTabs();
}

function renderServerTabs(){
  if(!currentStreams.length){$('#player-bar').classList.remove('visible');return}
  $('#player-tabs').innerHTML=currentStreams.map((s,i)=>`
    <button data-idx="${i}" data-url="${esc(s.embed_url||'')}" data-hls="${s.is_hls||''}" class="${i===activeServer?'active':''}">${esc(s.is_hls?'🎬 ':'')}${esc(s.label||'Server '+(i+1))} ${esc(s.is_hls?'(HLS)':'('+(s.quality||'HD')+')')}</button>
  `).join('');
  $('#player-bar').classList.add('visible');
  $('#player-tabs').querySelectorAll('button').forEach(btn=>{
    btn.addEventListener('click',()=>{
      if(btn.dataset.hls==='true'){
        activeServer=parseInt(btn.dataset.idx);
        $('#player-tabs').querySelectorAll('button').forEach((b,i)=>b.classList.toggle('active',i===activeServer));
        playServer(parseInt(btn.dataset.idx));
      }else{
        activeServer=parseInt(btn.dataset.idx);
        $('#player-tabs').querySelectorAll('button').forEach((b,i)=>b.classList.toggle('active',i===activeServer));
        playServer(parseInt(btn.dataset.idx));
      }
    });
    btn.addEventListener('contextmenu',(e)=>{
      e.preventDefault();
      var url=btn.dataset.url;
      if(url)window.open(url,'_blank');
    });
  });
  $('#player-extlink').style.display='block';
  $('#player-extlink').href=currentStreams[0].embed_url||'#';
}

function playServer(idx){
  activeServer=idx;
  if(!currentStreams[idx]||!currentStreams[idx].embed_url)return;
  var s=currentStreams[idx];
  $('#player-tabs').querySelectorAll('button').forEach((b,i)=>b.classList.toggle('active',i===idx));
  $('#player-extlink').href=s.embed_url||'#';
  $('#player-extlink').style.display='block';
  $('#subtitle-bar').style.display='none';$('#subtitle-select').innerHTML='';
  $('#subtitle-extlink').style.display='none';

  if(s.is_hls){
    $('#player-frame').style.display='none';$('#player-frame').src='';
    var v=$('#player-video');v.style.display='block';
    $('#player-wrap').classList.add('visible');
    // Show 2embed link for subtitles
    var subSrc=currentStreams.find(function(x){return x.label&&x.label.indexOf('2Embed')>=0});
    if(subSrc){$('#subtitle-extlink').href=subSrc.embed_url;$('#subtitle-extlink').style.display='inline'}
    if(window.Hls&&Hls.isSupported()){
      if(hlsInstance)hlsInstance.destroy();
      hlsInstance=new Hls({enableWorker:false});
      hlsInstance.loadSource(s.proxy_url||s.embed_url);
      hlsInstance.attachMedia(v);
      hlsInstance.on(Hls.Events.MANIFEST_PARSED,function(){
        var tracks=hlsInstance.subtitleTracks;
        if(tracks.length>0){
          $('#subtitle-bar').style.display='flex';
          tracks.forEach(function(t,i){
            var opt=document.createElement('option');
            opt.value=i;opt.textContent=t.name||t.lang||'Track '+(i+1);
            $('#subtitle-select').appendChild(opt);
          });
          $('#subtitle-select').onchange=function(){
            hlsInstance.subtitleTrack=parseInt(this.value);
          };
        }
      });
    }else if(v.canPlayType('application/vnd.apple.mpegurl')){
      v.src=s.proxy_url||s.embed_url;
    }
  }else{
    if(hlsInstance){hlsInstance.destroy();hlsInstance=null;}
    $('#player-video').style.display='none';$('#player-video').src='';
    $('#player-frame').style.display='block';
    $('#player-frame').src=s.embed_url;
    $('#player-wrap').classList.add('visible');
    // If not already a subtitle-capable embed, show link
    if(s.label.indexOf('2Embed')<0&&s.label.indexOf('VidCore')<0&&s.label.indexOf('VidNest')<0){
      var subSrc=currentStreams.find(function(x){return x.label&&x.label.indexOf('2Embed')>=0});
      if(subSrc){$('#subtitle-extlink').href=subSrc.embed_url;$('#subtitle-extlink').style.display='inline'}
    }
  }
}

async function loadTab(tab){
  currentTab=tab;currentPage=1;totalPages=1;
  $('#search-input').value='';
  $$('#tabs button').forEach(b=>b.classList.toggle('active',b.dataset.tab===tab));
  $('#results').innerHTML='<div class="loading">Loading...</div>';
  if(tab==='trending'){
    try{
      const m=await api('/api/trending/movies');
      const t=await api('/api/trending/tv');
      $('#results').innerHTML='';
      renderCards([...m,...t],$('#results'),false);
    }catch(e){}
  }else{
    try{
      const url=tab==='movies'?'/api/movies?page=1':'/api/tv?page=1';
      const data=await api(url);
      totalPages=data.total_pages||1;currentPage=1;
      renderCards(data.results||data,$('#results'),false);
      if(currentPage<totalPages)addLoadMore();
    }catch(e){$('#results').innerHTML='<div class="loading">Failed to load</div>'}
  }
}

function addLoadMore(){
  var btn=document.createElement('button');
  btn.textContent='Load More ('+currentPage+'/'+totalPages+')';
  btn.style.cssText='display:block;width:100%;margin:10px 0;padding:10px;background:var(--surface);border:1px solid var(--border);color:var(--accent);border-radius:8px;cursor:pointer;font-size:13px';
  btn.onclick=async function(){
    btn.textContent='Loading...';btn.disabled=true;
    try{
      var url=currentTab==='movies'?'/api/movies?page='+(currentPage+1):'/api/tv?page='+(currentPage+1);
      var data=await api(url);
      currentPage=data.page;totalPages=data.total_pages||totalPages;
      renderCards(data.results||data,$('#results'),true);
      if(currentPage<totalPages){btn.textContent='Load More ('+currentPage+'/'+totalPages+')';btn.disabled=false;}
      else btn.remove();
    }catch(e){btn.textContent='Retry';btn.disabled=false;}
  };
  $('#results').appendChild(btn);
}

let searchTimer=null;
$('#search-input').addEventListener('input',()=>{
  clearTimeout(searchTimer);
  searchTimer=setTimeout(async()=>{
    const q=$('#search-input').value.trim();
    if(q.length<2){loadTab(currentTab);return}
    try{const items=await api('/api/search?q='+encodeURIComponent(q));renderCards(items,$('#results'),false)}catch(e){}
  },400);
});

$$('#tabs button').forEach(b=>b.addEventListener('click',()=>loadTab(b.dataset.tab)));
loadTab('movies');
</script>
</body>
</html>"""


@app.route("/")
def index():
    return flask.Response(INDEX, mimetype="text/html")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    logging.basicConfig(level=logging.INFO)
    print(f"🎬 Soap2Day Browser — http://localhost:{port}")
    app.run(host="0.0.0.0", port=port, debug=False, threaded=True)
