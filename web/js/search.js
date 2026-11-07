// ---------- 摇骰子：地球转起来，停在一座城 ----------
function rollDice(scope){
  const visited=new Set(state.ck.map(v=>v.city));
  let pool = scope==="star" ? state.wish.map(w=>w.id) : Object.keys(IDX).filter(id=>byId[id] && (scope!=="new" || !visited.has(id)));
  pool=pool.filter(id=>byId[id] && id!==selId); if(!pool.length) return toast("这个范围里没有可以骰的城市");
  const pick=pool[Math.floor(Math.random()*pool.length)], c=byId[pick];
  $("#dicepop").hidden=true; if(selId) closeCard();
  const tk=$("#ticker"); tk.hidden=false; let n=0;
  const show=x=>{ tk.innerHTML=`<b>${esc(x.name)}</b><i>${esc(x.en||"")}</i>`; };
  const tm=setInterval(()=>{ show(byId[pool[Math.floor(Math.random()*pool.length)]]); if(++n>16){ clearInterval(tm); show(c); } },90);
  const p=world.pointOfView(); stopSpin();
  world.pointOfView({lat:p.lat*.3, lng:p.lng+200, altitude:2.6}, reduced?0:900);
  setTimeout(()=>world.pointOfView({lat:c.lat,lng:c.lng,altitude:2.1}, reduced?0:1100), reduced?0:900);

  setTimeout(async()=>{ tk.hidden=true; await loadCity(pick); openCity(pick); }, reduced?300:2200);
}

// ---------- 搜索：直接搜（中文/英文/不带重音）或按国家找 ----------
let COUNTRY_ZH = {};
const fold = s => String(s||"").normalize("NFKD").replace(/[̀-ͯ]/g,"").replace(/ł/g,"l").replace(/ø/g,"o").replace(/æ/g,"ae").replace(/ß/g,"ss").toLowerCase().replace(/[\s\-'’.]/g,"");
const czh = en => COUNTRY_ZH[en] || en || "其他";
let srch = {q:"", country:null, pick:null};   // pick=城市id：正在给这座城选出发地，点城市=选它
function openSearch(){ const el=$("#search"); el.hidden=false; renderSearch(); setTimeout(()=>el.querySelector("input")?.focus(),50); }
function closeSearch(){ $("#search").hidden=true; srch.pick=null; }
function cityRow(c){ return `<button class="sr" data-city="${esc(c.id)}"><span class="srn">${esc(c.name)}</span><span class="sre">${esc(c.en)}</span>${c.has?`<span class="srh">有资料</span>`:""}</button>`; }
// 地图上压根没有的地方（小镇、村子）：去维基数据找，带说明让人挑，加进地图
function placeHTML(q){
  const P=srch.places&&srch.places.q===q?srch.places:null;
  if(!P) return `<button class="sr addplace" data-findplace><span class="srn">找不到？在地图上加上「${esc(q)}」</span><span class="sre">去维基数据里找这个地方</span></button>`;
  if(P.loading) return `<p class="hint pl">正在维基数据里找「${esc(q)}」…</p>`;
  if(P.err) return `<p class="hint pl">${esc(P.err)}</p>`;
  if(!P.items.length) return `<p class="hint pl">维基数据里也没找到「${esc(q)}」。换个写法试试，比如加上「县」「镇」，或者用英文名。</p>`;
  return `<div class="sg2">在地图上加上哪一个？</div>`+P.items.map(it=> it.exists
    ? `<button class="sr" data-city="${esc(it.exists)}"><span class="srn">${esc(it.name)}</span><span class="sre">地图上已经有了：${esc(it.exists_name||"就在附近")}</span></button>`
    : `<button class="sr" data-qid="${esc(it.qid)}"><span class="srn">${esc(it.name)}</span><span class="sre">${esc([it.desc, czh(it.country)].filter(Boolean).join(" · "))}</span><span class="srh soft">加上</span></button>`).join("");
}
function renderSearch(){
  const el=$("#search"), q=srch.q.trim(), fq=fold(q);
  let body="";
  if(q){
    const hitC=CITIES.filter(c=>c.name.includes(q)||fold(c.en).includes(fq));
    hitC.sort((a,b)=>(b.has?1:0)-(a.has?1:0) || (a.name.startsWith(q)||fold(a.en).startsWith(fq)?0:1)-(b.name.startsWith(q)||fold(b.en).startsWith(fq)?0:1));
    const hitN=[...new Set(CITIES.map(c=>c.country))].filter(n=>n && (czh(n).includes(q)||fold(n).includes(fq)));
    body = (hitN.length?`<div class="sg2">国家</div>${hitN.slice(0,6).map(n=>`<button class="sr" data-country="${esc(n)}"><span class="srn">${esc(czh(n))}</span><span class="sre">${esc(n)}</span><span class="srh soft">${CITIES.filter(c=>c.country===n).length} 座 ›</span></button>`).join("")}`:"")
         + (hitC.length?`<div class="sg2">城市</div>${hitC.slice(0,40).map(cityRow).join("")}`:"")
         || `<p class="empty">没找到「${esc(q)}」。可以试试英文名，或者换个写法。</p>`;
    body += placeHTML(q);
  } else if(srch.country){
    const list=CITIES.filter(c=>c.country===srch.country).sort((a,b)=>(b.has?1:0)-(a.has?1:0)||a.name.localeCompare(b.name,"zh"));
    body=`<button class="lk back" data-back>‹ 所有国家</button><div class="sg2">${esc(czh(srch.country))} · ${list.length} 座</div>${list.map(cityRow).join("")}`;
  } else if(srch.tab==="been"){   // 去过的：按国家分组（手机上看不到电脑端的航段栏）
    const cnt={}; state.ck.forEach(x=>{ if(byId[x.city]) cnt[x.city]=(cnt[x.city]||0)+1; });
    const g={}; Object.keys(cnt).forEach(id=>(g[byId[id].country||""]=g[byId[id].country||""]||[]).push(id));
    const gs=Object.keys(g).sort((a,b)=>g[b].length-g[a].length);
    body = gs.length ? `<div class="sg2">来过 ${Object.keys(cnt).length} 座城 · ${state.ck.length} 次</div>`+gs.map(n=>`<div class="sg3">${esc(czh(n))} <i>${g[n].length}</i></div><div class="cityrow">${g[n].map(id=>`<button class="chip" data-city="${esc(id)}">${esc(byId[id].name)}${cnt[id]>1?`<i>${cnt[id]} 次</i>`:""}</button>`).join("")}</div>`).join("")
      : `<p class="empty">还没打过卡。点开一座城，在「我的经停」里点「来过」。</p>`;
  } else if(srch.tab==="wish"){   // 想去的：两个人的星星
    const by={}; (state.wish||[]).forEach(w=>{ if(byId[w.id]) (by[w.id]=by[w.id]||{})[w.by]=w.note; });
    const grp=[["都想去",id=>Object.keys(by[id]).length===2],[NAME("me")+"想去",id=>Object.keys(by[id]).join()==="me"],[NAME("partner")+"想去",id=>Object.keys(by[id]).join()==="partner"]];
    body = Object.keys(by).length ? grp.map(([t,f])=>{ const ids=Object.keys(by).filter(f); return ids.length?`<div class="sg3">${t} <i>${ids.length}</i></div>${ids.map(id=>`<button class="sr" data-city="${esc(id)}"><span class="srn">${esc(byId[id].name)}</span><span class="sre">${esc(Object.values(by[id]).filter(Boolean).join(" / "))}</span></button>`).join("")}`:""; }).join("")
      : `<p class="empty">还没有星星。点开一座城，在「想去」里点亮。</p>`;
  } else {
    const cnt={}; for(const c of CITIES){ if(c.country) (cnt[c.country]=cnt[c.country]||{n:0,h:0}), cnt[c.country].n++, c.has&&cnt[c.country].h++; }
    const ns=Object.keys(cnt).sort((a,b)=>cnt[b].h-cnt[a].h||cnt[b].n-cnt[a].n);
    body=`<div class="sg2">按国家找 · ${ns.length} 个国家</div><div class="cgrid">${ns.map(n=>`<button class="cc" data-country="${esc(n)}"><b>${esc(czh(n))}</b><i>${cnt[n].h?cnt[n].h+" 座有资料":cnt[n].n+" 座"}</i></button>`).join("")}</div>`;
  }
  el.innerHTML=`<div class="shin srch"><div class="sbar"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="m15 15 5 5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
      <label for="sq" class="vh-only">搜索城市或国家</label><input id="sq" type="search" value="${esc(srch.q)}" placeholder="${srch.pick?`搜城市，比如 ${esc(byId[defOriginOf(srch.pick.city)]?.name||"巴黎")}`:"搜城市或国家，中文英文都行"}" autocomplete="off" enterkeyhint="search">
      <button class="x" aria-label="关闭搜索">×</button></div>${!q&&!srch.country?`<div class="stabs" role="tablist">${[["",`按国家找`],["been",`去过的`],["wish",`想去的`]].map(([k,t])=>`<button role="tab" aria-selected="${(srch.tab||"")===k}" class="${(srch.tab||"")===k?"on":""}" data-tab="${k}">${t}</button>`).join("")}</div>`:""}${srch.pick&&byId[srch.pick.city]?`<p class="sg2 pickhint">${srch.pick.field==="dest"?`选终点 · 从${esc(byId[srch.pick.city].name)}回到哪儿`:`选出发地 · 去${esc(byId[srch.pick.city].name)}`}</p>`:""}<div class="sres">${body}</div></div>`;
  const inp=el.querySelector("input");
  inp.oninput=()=>{ srch.q=inp.value; srch.country=null; const pos=inp.selectionStart; renderSearch(); const i2=$("#search input"); i2.focus(); i2.setSelectionRange(pos,pos); };
  inp.onkeydown=e=>{ if(e.key==="Enter"){ const first=el.querySelector("[data-city]"); first&&first.click(); } };
  el.querySelector(".x").onclick=closeSearch;
  el.onclick=e=>{ if(e.target===el) closeSearch(); };
  el.querySelector("[data-back]")?.addEventListener("click",()=>{ srch.country=null; renderSearch(); });
  el.querySelector("[data-findplace]")?.addEventListener("click",async()=>{ const q0=srch.q.trim(); srch.places={q:q0,loading:true}; renderSearch();
    try{ const r=await getJSON("api/place/search?q="+encodeURIComponent(q0)); srch.places={q:q0,items:r.items||[]}; }
    catch(e){ srch.places={q:q0,err:"维基数据没连上，过一会儿再试"}; } if(!$("#search").hidden) renderSearch(); });
  el.querySelectorAll("[data-qid]").forEach(b=>b.onclick=async()=>{ b.disabled=true;
    try{ const r=await api("POST","place",{qid:b.dataset.qid}); const [name,en,lat,lng,country]=r.city;
      if(!byId[r.id]){ const c={id:r.id,name,en,lat,lng,country}; CITIES.push(c); byId[r.id]=c; }
      const to=srch.pick; srch.places=null; closeSearch(); toast(`「${name}」加到地图上了`);
      if(to) return to.field==="dest" ? setDest(to.city,r.id,to.trip) : setOrigin(to.city,r.id,to.trip);
      if(selId) selId=null; openCity(r.id);
    }catch(e){ toast("没加上："+e.message); b.disabled=false; } });
  el.querySelectorAll("[data-tab]").forEach(b=>b.onclick=()=>{ srch.tab=b.dataset.tab; renderSearch(); el.querySelector(".sres").scrollTop=0; });
  el.querySelectorAll("[data-country]").forEach(b=>b.onclick=()=>{ srch.country=b.dataset.country; srch.q=""; renderSearch(); el.querySelector(".sres").scrollTop=0; });
  el.querySelectorAll("[data-city]").forEach(b=>b.onclick=()=>{ const to=srch.pick; closeSearch(); if(to) return to.field==="dest" ? setDest(to.city,b.dataset.city,to.trip) : setOrigin(to.city,b.dataset.city,to.trip); if(selId) selId=null; openCity(b.dataset.city); });
}

let tt; function toast(m){const t=$("#toast");t.textContent=m;t.hidden=false;clearTimeout(tt);tt=setTimeout(()=>t.hidden=true,2400)}

