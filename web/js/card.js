// ---------- 没资料的城：现场整理一页（pipeline/citygen.py；默认快写，勾「认真写」用更好的模型）----------
const GEN={};   // id -> {stage,msg,status}
const GEN_STEPS=[["wiki","翻维基"],["write","写正文"],["images","配图"],["save","存下来"]];
function genHTML(id){
  const g=GEN[id];
  if(g&&g.status==="running"){ const i=GEN_STEPS.findIndex(x=>x[0]===g.stage);
    return `<section class="ls gen"><div class="sh"><b>资料</b><i>整理中</i></div>
      <ol class="gsteps">${GEN_STEPS.map(([k,t],j)=>`<li class="${j<i?"ok":j===i?"now":""}">${j<i?"✓":j===i?'<span class="spin"></span>':"·"} ${t}</li>`).join("")}</ol>
      <p class="hint">大约一分钟。可以先关掉卡片去看别的，好了会告诉你。</p></section>`; }
  return `<section class="ls gen"><div class="sh"><b>资料</b><i>Not yet</i></div>
    <p class="empty">这座城还没有资料。${g&&g.status==="error"?`<br><b class="gerr">${esc(g.msg||"没整理成")}</b>`:""}</p>
    <label class="apalb"><input type="checkbox" id="genpro"><span>认真写<i>用更好的模型，贵一点；不勾就是快写</i></span></label>
    <button class="pill solid" data-gen>整理这座城的资料</button><p class="hint">大约一分钟，整理好的会一直留着，以后点开就有。</p></section>`;
}
async function startGen(id, pro){
  try{ const r=await api("POST",`city/${encodeURIComponent(id)}/gen`,{pro}); GEN[id]=r; if(selId===id) rerender(); pollGen(id); }
  catch(e){ toast(e.message); }
}
async function pollGen(id){
  for(let k=0;k<120;k++){
    await new Promise(r=>setTimeout(r,2500));
    let r; try{ r=await getJSON(`api/city/${encodeURIComponent(id)}/gen`); }catch(e){ continue; }
    GEN[id]=r;
    if(r.status==="done"){
      if(!IDX[id]){ try{ const d=await getJSON("data/cities.json?t="+Date.now()); const e=d.cities.find(x=>x.id===id); if(e) IDX[id]=e; }catch(e){} }
      if(byId[id]) byId[id].has=1; DATA[id]=undefined; await loadCity(id);
      if(world&&ptsOn) world.pointsData(CITIES.filter(c=>c.has));
      toast(`${byId[id]?.name||""}的资料整理好了`); if(selId===id) openCity(id,{stay:1}); return;
    }
    if(selId===id) rerender();
    if(r.status==="error"||r.status==="none") return;
  }
}
async function loadCity(id){
  if(DATA[id]!==undefined || !IDX[id]) return DATA[id];
  try{ DATA[id]=await getJSON(`data/city/${id}.json`); }catch(e){ DATA[id]=null; }
  return DATA[id];
}
// ---------- 长卷卡片：版头大图 / 历史时间轴 / 文化 / 景点轮播 / 美食展开列表 / 想去 / 我的经停 ----------
const img = (x, alt="", cls="") => x?.u ? `<img class="${cls}" src="${esc(x.u)}" width="${x.w||""}" height="${x.h||""}" alt="${esc(alt)}" loading="lazy" decoding="async" onerror="this.closest('[data-img]')?.classList.add('noimg');this.remove()">` : "";
let ui = {};   // 每张卡片的展开/轮播状态
// 历史三段 → 时间轴三个节点：标签取段落里第一个年代，标题取第一句
function eraOf(p){
  const m = p.match(/(公元前\s*\d{1,4}\s*年|前\s*\d{1,2}\s*世纪|\d{1,2}\s*世纪(?:初|末|中叶|后期|前期)?|\d{3,4}\s*年代|\d{3,4}\s*年)/);
  const first = (p.split(/(?<=[。！？])/)[0]||p).trim();
  const short = first.length>34;   // 第一句太长就截成标题，正文给全段；否则标题=第一句，正文接着往下
  return { y: m ? m[1].replace(/\s+/g,"") : "—", h: short ? first.slice(0,32)+"…" : first, rest: short ? p : p.slice(first.length).trim() || p };
}
function cardHTML(id){
  const c=byId[id], D=DATA[id];
  const hero=D?.hero?.[0];
  const loc = (ckOf(id)?`● 来过${tripsOf(id).length>1?" "+tripsOf(id).length+" 次":""} · `:"") + `${fLat(c.lat)} · ${fLng(c.lng)}`;
  let h=`<button class="grab" aria-label="展开或收起"></button><button class="x float" aria-label="关闭">×</button>`;
  h+= hero ? `<header class="lh" data-img>${img(hero, c.name, "lh-img")}<div class="lh-fade"></div>
      <div class="lh-t"><span class="kick">${loc}</span><h2>${esc(c.name)}</h2><span class="orig">${esc(c.en)}${c.country?` · ${esc(c.country)}`:""}</span>${D?.dek?`<p class="dek">${esc(D.dek)}</p>`:""}</div></header>`
    : `<header class="lh plain"><div class="lh-t"><span class="kick">${loc}</span><div class="title"><h2>${esc(c.name)}</h2>${silhouette(id)}</div><span class="orig">${esc(c.en)}${c.country?` · ${esc(c.country)}`:""}</span>${D?.dek?`<p class="dek">${esc(D.dek)}</p>`:""}</div></header>`;
  if(D===undefined && IDX[id]) return h+`<section class="ls"><p class="empty">正在翻开这一页……</p></section>`;
  if(!D) return h+genHTML(id)+mineHTML(id);
  const u=ui[id]||(ui[id]={open:{0:1},more:0,si:0,food:{}});
  const paras=String(D.history||"").split(/\n+/).filter(Boolean).map(eraOf);
  const cult=String(D.culture||"").split(/\n+/).filter(Boolean);
  h+=`<section class="ls"><div class="sh"><b>历史</b><i>History · 点开</i></div><div class="tl">
    ${paras.map((e,i)=>`<div class="node ${u.open[i]?"on":""}"><span class="dot"></span>
      <button class="nb" data-era="${i}" aria-expanded="${!!u.open[i]}"><span class="ny">${esc(e.y)}</span><span class="nh">${esc(e.h)}</span><span class="ns">${u.open[i]?"−":"+"}</span></button>
      ${u.open[i]?`<p class="np">${esc(e.rest)}</p>`:""}</div>`).join("")}</div></section>`;
  if(cult.length||D.pull) h+=`<section class="ls"><div class="sh"><b>文化</b><i>Culture</i></div>
    ${D.pull?`<blockquote class="pull">“${esc(D.pull.replace(/^[“"]|[”"]$/g,""))}”</blockquote>`:""}
    ${cult[0]?`<p class="bp">${esc(cult[0])}</p>`:""}${u.more?cult.slice(1).map(p=>`<p class="bp">${esc(p)}</p>`).join(""):""}
    ${cult.length>1?`<button class="lk" data-more>${u.more?"收起":"读下去 ›"}</button>`:""}</section>`;
  const S=D.sights||[];
  if(S.length) h+=`<section class="ls wide"><div class="sh"><b>景点</b><i>To see · 左右滑</i><span class="cnt">${String(u.si+1).padStart(2,"0")} / ${String(S.length).padStart(2,"0")}</span></div>
    <div class="car" data-car><div class="rail" data-rail>
      ${S.map((x,i)=>`<button class="sc ${x.img?"":"noimg"}" data-sight="${i}" data-img aria-label="${esc(x.name)}，点开看介绍"><span class="sc-in">${img(x.img)}</span>
        <span class="sc-t"><b>${esc(x.name)}</b><i>${x.orig&&x.orig!==x.name?esc(x.orig):""}</i><em>点开看介绍 ›</em></span></button>`).join("")}</div>
      <button class="arr l" data-step="-1" aria-label="上一个">‹</button><button class="arr r" data-step="1" aria-label="下一个">›</button></div>
    <div class="dots">${S.map((x,i)=>`<button data-go="${i}" class="${i===u.si?"on":""}" aria-label="第 ${i+1} 个"></button>`).join("")}</div></section>`;
  const F=D.foods||[];
  if(F.length) h+=`<section class="ls"><div class="sh"><b>美食</b><i>To eat · 点开</i></div>
    ${F.map((f,i)=>`<div class="fd"><button class="fr" data-food="${i}" aria-expanded="${!!u.food[i]}">
        ${f.img?`<span class="ft" data-img>${img({...f.img}, "")}</span>`:`<span class="ft ph">${esc((f.orig||f.name).slice(0,1))}</span>`}
        <span class="fn"><b>${esc(f.name)}</b><i>${f.orig&&f.orig!==f.name?esc(f.orig):""}</i></span><span class="chev ${u.food[i]?"up":""}">⌄</span></button>
      ${u.food[i]?`<div class="fx" data-img>${img(f.img, f.name)}<div class="fxt"><b>${esc(f.name)}</b><i>${f.orig&&f.orig!==f.name?esc(f.orig):""}</i><p>${esc(f.intro)}</p>
        ${SH()?`<button class="pill soft" data-share="food:${i}">${PLANE}<span>递给${esc(PT())}</span></button>`:""}</div></div>`:""}</div>`).join("")}
    ${SH()?`<div class="seen"><i>看完了？</i><button class="pill soft" data-share="city">${PLANE}<span>把${esc(c.name)}递给${esc(PT())}</span></button></div>`:""}</section>`;
  if(!F.length && SH()) h+=`<section class="ls"><div class="seen"><i>看完了？</i><button class="pill soft" data-share="city">${PLANE}<span>把${esc(c.name)}递给${esc(PT())}</span></button></div></section>`;
  h+=mineHTML(id);
  const model=D.credit?.model;
  h+=`<footer class="colo">资料：Wikipedia · Wikivoyage（CC BY-SA）${model?`　整理：${esc(model)}`:""}<br>图片：Wikimedia Commons，点开景点可看原条目</footer>`;
  return h;
}

// 「来过」打卡：不要日期，只记从哪儿出发（红线从出发地连过来）。默认出发地见配置 default_origin
function originChips(id, cur){
  const def=defOriginOf(id), seen=new Set([id]), list=[];
  const add=(cid,tag)=>{ if(!cid||seen.has(cid)||!byId[cid]) return; seen.add(cid); list.push({cid,tag}); };
  add(def,"默认");
  add(cur,"现在");
  const c=byId[id]; state.ck.filter(x=>byId[x.city]).sort((a,b)=>km(byId[a.city],c)-km(byId[b.city],c)).forEach(x=>{ if(list.length<7) add(x.city,""); });   // 离得近的已打卡城：一趟玩下去，下一站多半从附近上一站出发
  return `<div class="ckpick"><p class="ckq">${cur===undefined?"这一次":"那一次"}从哪儿出发到${esc(byId[id].name)}？</p><div class="chips">
    ${list.map(o=>`<button class="chip ${o.cid===cur?"on":""}" data-origin="${esc(o.cid)}">${esc(byId[o.cid].name)}${o.tag?`<i>${o.tag}</i>`:""}</button>`).join("")}
    <button class="chip ghost" data-origin-search>搜别的城…</button>
    <button class="chip ghost" data-origin="${esc(id)}">不连线</button></div>
    <button class="lk" data-ck-cancelpick>先不了</button></div>`;
}
// 想去：me 的金星可点亮/改理由/取消；partner 的蓝星只显示（由后端接口写入）
function wishHTML(id, u){
  const mine=state.wish.find(w=>w.id===id&&w.by==="me"), pt=state.wish.find(w=>w.id===id&&w.by==="partner"), been=!!ckOf(id);
  let h=`<section class="ls ck wsec"><div class="sh"><b>想去</b><i>${mine&&pt?"都想去":mine||pt?"Wish":"Not yet"}</i></div>`;
  if(pt) h+=`<p class="wl pt"><span class="ws">★</span>${esc(NAME("partner"))}想去${pt.note?`<span class="wnote">“${esc(pt.note)}”</span>`:""}</p>`;
  if(u.wishing) h+=`<form class="wf2"><label class="vh-only" for="wnote-${esc(id)}">为什么想去</label><input id="wnote-${esc(id)}" name="note" maxlength="200" placeholder="为什么想去？可以不写" value="${esc(mine?.note||"")}" autocomplete="off">
      <div class="ckacts"><button class="pill star">${mine?"改好了":"点亮星星"}</button><button type="button" class="lk" data-wish-cancel>先不了</button></div></form>`;
  else if(mine) h+=`<p class="wl me"><span class="ws">★</span>${esc(NAME("me"))}想去${mine.note?`<span class="wnote">“${esc(mine.note)}”</span>`:""}</p>
      <div class="ckacts"><button class="pill soft" data-wish-edit>改理由</button><button class="pill soft warn" data-wish-off>${u.woff?"再点一次确认":"不想去了"}</button></div>`;
  else h+=`<button class="pill star" data-wish-on><span class="ws">★</span>${been?"还想再去":"想去"+esc(byId[id].name)}</button>`;
  return h+`</section>`;
}
async function setWish(id, note){
  try{ await api("PUT","wish/"+encodeURIComponent(id),{by:"me",note}); await loadState(); if(ui[id]) ui[id].wishing=0;
    refreshLayers(); renderSide(); rerender(); toast("点亮了一颗星"); }catch(e){ toast("没存上："+e.message); }
}
async function unwish(id){
  try{ await api("DELETE","wish/"+encodeURIComponent(id)+"?by=me"); await loadState(); if(ui[id]) ui[id].woff=0;
    refreshLayers(); renderSide(); rerender(); toast("星星收起来了"); }catch(e){ toast("没取消成："+e.message); }
}
function destChips(id, cur){
  const seen=new Set([id]), list=[], c=byId[id], o=state.cfg.default_origin||{};
  const add=(cid,tag)=>{ if(!cid||seen.has(cid)||!byId[cid]) return; seen.add(cid); list.push({cid,tag}); };
  add(cur,"现在"); add(defOriginOf(id),"家"); add(o.abroad,"家"); add(o.domestic,"家");
  state.ck.filter(x=>byId[x.city]).sort((a,b)=>km(byId[a.city],c)-km(byId[b.city],c)).forEach(x=>{ if(list.length<8) add(x.city,""); });
  return `<div class="ckpick"><p class="ckq">这一趟最后回到哪儿？</p><div class="chips">
    ${list.map(o=>`<button class="chip ${o.cid===cur?"on":""}" data-dest="${esc(o.cid)}">${esc(byId[o.cid].name)}${o.tag?`<i>${o.tag}</i>`:""}</button>`).join("")}
    <button class="chip ghost" data-dest-search>搜别的城…</button>${cur?`<button class="chip ghost" data-dest="">不设终点</button>`:""}</div>
    <button class="lk" data-dest-x>先不了</button></div>`;
}
async function setDest(city, dest, tid){
  try{ await api("PUT","trip/"+tid,{dest}); await loadState(); refreshLayers(); renderSide(); rerender(); if(tripOpen()) openTrip(tripOpen());
    toast(dest&&byId[dest]?`回到${byId[dest].name}，线连上了`:"终点去掉了"); }catch(e){ toast("没存上："+e.message); }
}
function mineHTML(id){
  const ts=tripsOf(id), u=ui[id]||(ui[id]={open:{0:1},more:0,si:0,food:{}}), c=byId[id];
  let h=wishHTML(id,u)+`<section class="ls ck"><div class="sh"><b>我的经停</b><i>${ts.length?(ts.length>1?`来过 ${ts.length} 次`:"来过"):"Not yet"}</i></div>`;
  ts.forEach((t,i)=>{ h+=ticketHTML(t, i, ts.length); });
  const kids=[...new Set(state.ck.filter(x=>x.origin===id&&byId[x.city]).map(x=>byId[x.city].name))];
  if(kids.length) h+=`<p class="cks">从这里出发去了：${kids.map(esc).join("、")}</p>`;
  h+= u.pick==="new" ? originChips(id)
    : ts.length ? `<button class="pill soft again" data-ck-on>＋ 又来了一次</button>`
    : `<button class="pill solid" data-ck-on>来过${esc(c.name)}</button><p class="cks">只是打个卡，不用写日期。点了选从哪儿出发，红线就从那儿连过来。来过几次就点几次。</p>`;
  return h+`</section>`+(SH()?threadHTML(id):"");
}
