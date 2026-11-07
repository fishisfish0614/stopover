document.querySelectorAll("#styles button").forEach(b=>b.onclick=()=>{ if(b.dataset.s!==current) build(b.dataset.s); });

$("#srchbtn").onclick=openSearch;
$("#chatbtn").onclick=openChat;
$("#bellbtn").onclick=openBell;
$("#dice").onclick=()=>{ const p=$("#dicepop"); p.hidden=!p.hidden; };
document.querySelectorAll("#dicepop [data-scope]").forEach(b=>b.onclick=()=>rollDice(b.dataset.scope));

// 电脑上捏合触控板或 Ctrl+滚轮，浏览器默认会把整页放大（卡片撑爆、地球糊成一片海）。拦下来只缩放地球
function zoomGlobe(f){ if(!world) return; const p=world.pointOfView(); world.pointOfView({lat:p.lat,lng:p.lng,altitude:Math.max(STYLES[current]?.minAlt??.05,Math.min(6,p.altitude*f))}); }
const inUI=t=>t?.closest?.(".card,.layer,.top,.side");
addEventListener("wheel",e=>{ if(!e.ctrlKey) return; e.preventDefault(); if(!inUI(e.target)) zoomGlobe(Math.exp(Math.max(-50,Math.min(50,e.deltaY))*.004)); },{passive:false});
let _gs=1;   // Mac Safari 的捏合走 gesture 事件
addEventListener("gesturestart",e=>{ e.preventDefault(); _gs=e.scale||1; });
addEventListener("gesturechange",e=>{ e.preventDefault(); if(!inUI(e.target)&&e.scale) zoomGlobe(_gs/e.scale); _gs=e.scale; });
addEventListener("gestureend",e=>e.preventDefault());
addEventListener("resize",()=>{ world&&world.width(innerWidth).height(innerHeight); if(selId){document.body.classList.toggle("open-side",wide());document.body.classList.toggle("open-sheet",!wide());} });
addEventListener("keydown",e=>{ if(e.key!=="Escape") return; const open=[...document.querySelectorAll(".layer")].reverse().find(x=>!x.hidden); if(open){ open.querySelector(".x")?.click(); if(!open.hidden) open.hidden=true; return; } if(selId) closeCard(); });   // Esc 先关最上面那层

(async()=>{
  // 城市表：有资料的城市 + 能点但还没资料的 Natural Earth 城市
  try{
    const d=await getJSON("data/cities.json");
    for(const x of d.cities){ const c={id:x.id,name:x.n,en:x.e,country:x.c,lat:x.la,lng:x.lo,has:1}; CITIES.push(c); byId[c.id]=c; IDX[c.id]=x; }
    COUNTRY_ZH=d.cz||{};
    for(const [name,en,lat,lng,country] of d.extra){ const c={id:"n_"+en+"_"+lat,name,en,lat,lng,country}; CITIES.push(c); byId[c.id]=c; }
  }catch(e){ toast("城市表没加载上，刷新一下试试"); }
  try{ await loadState(); }catch(e){ toast("打卡记录没加载上，刷新一下试试"); }
  renderSide();
  let start="marble"; try{start=localStorage.getItem("jt-style2")||"marble"}catch(e){}
  if(!STYLES[start]) start="marble";
  if(typeof Globe==="undefined"){ $("#globe").innerHTML='<p style="padding:120px 16px;color:var(--muted)">地球库没加载上，刷新一下试试。</p>'; return; }
  await build(start);
  initPush();
  // 深链：?city=<id> 或 #city=<id>（推送、聊天卡片点进来）
  const q=new URLSearchParams(location.search).get("city") || new URLSearchParams(location.hash.slice(1)).get("city");
  if(q && byId[q]){ await loadCity(q); openCity(q); }
})();
