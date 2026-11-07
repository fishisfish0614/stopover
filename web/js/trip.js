// ---------- 登机牌：纯文字票面，备注印在票上，随记和照片在「这一次」里 ----------
// 三字码：取英文名第一个词的前三个字母（Kyōto→KYO、Lisboa→LIS），没有就用 ···
const code3 = id => { const e=fold((byId[id]?.en||"").split(/[\s,\-]+/)[0]).replace(/[^a-z]/g,""); return e ? e.slice(0,3).toUpperCase() : "···"; };
const notesOf = tid => (state.notes||[]).filter(n=>n.trip_id===tid);
const photosOf = tid => (state.photos||[]).filter(p=>p.trip_id===tid);
const tno = t => String(state.ck.findIndex(x=>x.id===t.id)+1).padStart(3,"0");
function routeHTML(t){
  const o=byId[t.origin], c=byId[t.city], d=byId[t.dest];
  if(d) return `<div class="tk-route three">${o?`<div class="tk-code">${code3(t.origin)}<small>${esc(o.name)}</small></div><div class="tk-dash"></div>`:""}<div class="tk-code tk-here">${code3(t.city)}<small>${esc(c.name)}</small></div><div class="tk-dash"></div><div class="tk-code">${code3(t.dest)}<small>回到${esc(d.name)}</small></div></div>`;
  return `<div class="tk-route">${o?`<div class="tk-code">${code3(t.origin)}<small>${esc(o.name)}</small></div><div class="tk-dash"></div>`:`<div class="tk-code tk-start">起点<small>就从这里出发</small></div><div class="tk-dash"></div>`}<div class="tk-code">${code3(t.city)}<small>${esc(c.name)}</small></div></div>`;
}
function ticketHTML(t, i, n){
  const c=byId[t.city], o=byId[t.origin], ps=photosOf(t.id), ns=notesOf(t.id), blank=!t.date_start&&!t.remark&&!ps.length&&!ns.length;
  return `<button class="tk ${blank?"dim":""} ${t.remark?"foot":""}" data-trip="${t.id}" aria-label="${esc(c.name)}第 ${i+1} 次，点开">
    <span class="tk-row"><span class="tk-main">
      <span class="tk-air"><span class="tk-l">STOPOVER · 经停</span><span class="tk-l">NO. ${tno(t)}</span></span>
      ${routeHTML(t)}
      <span class="tk-meta"><span><span class="tk-l">DATE</span><span class="tk-v">${t.date_start?esc(fmtTD(t)):"——"}</span></span>
        ${ps.length?`<span><span class="tk-l">PHOTOS</span><span class="tk-v">${ps.length}</span></span>`:""}
        ${ns.length?`<span><span class="tk-l">NOTES</span><span class="tk-v">${ns.length}</span></span>`:""}
        ${o?`<span><span class="tk-l">KM</span><span class="tk-v">${km(o,c).toLocaleString("en-US")}</span></span>`:""}</span>
    </span><span class="tk-stub"><span><span class="tk-l">SEAT</span><span class="tk-seat">${String(i+1).padStart(2,"0")}</span></span><span class="tk-hint">撕开 ↘</span><span class="tk-bc"></span></span></span>
    ${t.remark?`<span class="tk-rem"><span class="tk-l">REMARKS · 备注</span><span class="tk-rp">${esc(t.remark)}</span></span>`:""}
  </button>`;
}
const fmtTD = t => { const f=d=>d.replace(/-/g,"."); return t.date_end&&t.date_end!==t.date_start ? `${f(t.date_start)} – ${f(t.date_end)}` : f(t.date_start); };
const ago = ts => { const d=new Date(ts*1000); return `${d.getMonth()+1}.${d.getDate()} ${String(d.getHours()).padStart(2,"0")}:${String(d.getMinutes()).padStart(2,"0")}`; };
function tripForm(t){
  return `<form class="tf" data-trip="${t.id}"><p class="ckq">日期记得就写，不记得就空着</p>
    <div class="tfr"><label><span>从</span><input name="date_start" value="${esc(t.date_start||"")}" placeholder="2019.8.3" autocomplete="off" inputmode="text"></label>
    <label><span>到</span><input name="date_end" value="${esc(t.date_end||"")}" placeholder="选填" autocomplete="off"></label></div>
    <p class="hint tfh">只记得年或月也行：2019、2019.8</p><label class="tfl" for="tr-${t.id}">票面备注 · 一句话，印在登机牌上（可以空着）</label><input id="tr-${t.id}" name="remark" maxlength="60" value="${esc(t.remark||"")}" placeholder="比如：第一次见到海" autocomplete="off">
    <div class="ckacts"><button class="pill solid">保存</button><button type="button" class="lk" data-tf-cancel>先不了</button></div><p class="tferr" role="alert" hidden></p></form>`;
}
// ---------- 我们的对话：按递送分组（每次递送是单独的一组）+「平时说的」（城市 / 某一次 / 照片 / 随记下的话）----------
const cmtsOf = t => (state.cmts||[]).filter(c=>c.target===t);
function cityOfItem(it){ if(it.city) return it.city;
  if(it.type==="trip") return state.ck.find(t=>t.id===it.id)?.city;
  if(it.type==="photo"){ const p=(state.photos||[]).find(x=>x.id===it.id); return p&&state.ck.find(t=>t.id===p.trip_id)?.city; }
  if(it.type==="note"){ const n=(state.notes||[]).find(x=>x.id===it.id); return n&&state.ck.find(t=>t.id===n.trip_id)?.city; } }
function cityOfTgt(t){ const [k,v]=t.split(":"); if(k==="city") return v;
  if(k==="share"){ const x=(state.shares||[]).find(s=>s.id===+v); return x&&cityOfItem(x.items[0]); }
  return cityOfItem({type:k,id:+v}); }
function whatOf(items){ const k={}; items.forEach(it=>k[it.type]=(k[it.type]||0)+1);
  if(k.trip) return "整张票"; if(k.city) return "这座城";
  if(k.sight||k.food){ const it=items[0], arr=DATA[it.city]?.[it.type==="sight"?"sights":"foods"]; return `${it.type==="sight"?"景点":"美食"}「${arr?.[it.i]?.name||""}」`; }
  return [k.note?`${k.note} 段随记`:"", k.photo?`${k.photo} 张照片`:""].filter(Boolean).join(" + "); }
function whereOf(t, id){ const [k,v]=t.split(":"); if(k==="city") return "";
  const tid = k==="trip"?+v : k==="photo"?(state.photos||[]).find(x=>x.id===+v)?.trip_id : (state.notes||[]).find(x=>x.id===+v)?.trip_id;
  const n=tripsOf(id).findIndex(x=>x.id===tid)+1; return n?`在第 ${n} 次${k==="photo"?"的照片":k==="note"?"的随记":""}下`:""; }
const thr={};   // 组 key（share:N 或 city:ID）→ {reply: 评论 id}
function threadHTML(id){
  const cm=state.cmts||[], byC=Object.fromEntries(cm.map(x=>[x.id,x])), groups=[];
  (state.shares||[]).forEach(x=>{ if(!x.items.some(it=>cityOfItem(it)===id)) return;
    const msgs=cm.filter(m=>m.target==="share:"+x.id);
    groups.push({key:"share:"+x.id, share:x, msgs, last:Math.max(x.created,...msgs.map(m=>m.created))}); });
  const loose=cm.filter(m=>!m.target.startsWith("share:") && cityOfTgt(m.target)===id);
  if(loose.length) groups.push({key:"city:"+id, msgs:loose, last:Math.max(...loose.map(m=>m.created))});
  if(!groups.length) return "";
  groups.sort((a,b)=>b.last-a.last);
  const line=(m,key)=>{ const w=key.startsWith("city:")?whereOf(m.target,id):"";
    return `<div class="cmi ${m.who==="partner"?"pt":"me"}"><p><b>${esc(NAME(m.who))}</b>${m.reply_to&&byC[m.reply_to]?`<span class="rp">回复${esc(NAME(byC[m.reply_to].who))}</span>`:""}${w?`<span class="rp">${w}</span>`:""}${esc(m.text)}</p>
      <div class="cmm"><span>${ago(m.created)}</span>${m.who!=="me"?`<button class="lk" data-threply="${m.id}" data-tk="${key}">回复</button>`:`<button class="lk" data-cmdel="${m.id}">删</button>`}</div></div>`; };
  return `<section class="ls ck thread"><div class="sh"><b>我们的对话</b><i>${groups.length} 组</i></div>
    ${groups.map(g=>{ const R=thr[g.key]?.reply&&byC[thr[g.key].reply], x=g.share, me=x&&x.who==="me";
      const head = x ? `<div class="tg-h"><span class="tg-k">${me?`你递给${esc(PT())}`:`${esc(PT())}递给你`}</span><b>${esc(whatOf(x.items.filter(it=>cityOfItem(it)===id)))}</b><span class="tg-t">${ago(x.created)}${me&&x.status==="pending"?" · 待送达":""}</span></div>
          ${x.note?`<div class="cmi ${me?"me":"pt"}"><p><b>${esc(NAME(x.who))}</b>${esc(x.note)}</p></div>`:""}`
        : `<div class="tg-h"><span class="tg-k">平时说的</span></div>`;
      return `<div class="cm tgrp">${head}${g.msgs.map(m=>line(m,g.key)).join("")}
        <form class="thf" data-tk="${g.key}">${R?`<span class="cmr">回复${esc(NAME(R.who))}：「${esc(R.text.slice(0,20))}${R.text.length>20?"…":""}」<button type="button" class="lk" data-thx="${g.key}">不回了</button></span>`:""}
          <label class="vh-only" for="thf-${esc(g.key)}">回复这一组</label><input id="thf-${esc(g.key)}" name="text" maxlength="2000" placeholder="${R?`回复${esc(NAME(R.who))}…`:x?"回复这次…":"接着说…"}" autocomplete="off" enterkeyhint="send"><button class="pill soft">发</button></form></div>`; }).join("")}
  </section>`;
}
// 挂在某一次 / 照片 / 随记下的话：只有有人说过才出现；每条下面可以「回复」，点了才出输入框
const cmtReply={};
function cmtBlock(target){
  if(!SH()) return "";
  const cs=cmtsOf(target); if(!cs.length) return "";
  const by=Object.fromEntries((state.cmts||[]).map(c=>[c.id,c])), r=cmtReply[target] && by[cmtReply[target]];
  return `<div class="tpc"><b class="tpcl">${esc(PT())}说</b><div class="cm">${cs.map(c=>`<div class="cmi ${c.who==="partner"?"pt":"me"}"><p><b>${esc(NAME(c.who))}</b>${c.reply_to&&by[c.reply_to]?`<span class="rp">回复${esc(NAME(by[c.reply_to].who))}</span>`:""}${esc(c.text)}</p>
      <div class="cmm"><span>${ago(c.created)}</span>${c.who!=="me"?`<button class="lk" data-reply="${c.id}" data-t="${esc(target)}">回复</button>`:`<button class="lk" data-cmdel="${c.id}">删</button>`}</div></div>`).join("")}
    ${r?`<form class="cmf" data-t="${esc(target)}"><span class="cmr">回复${esc(NAME(r.who))}：<button type="button" class="lk" data-cmr-x="${esc(target)}">不回了</button></span>
      <label class="vh-only" for="cmf-${esc(target)}">回复</label><input id="cmf-${esc(target)}" name="text" maxlength="2000" placeholder="回复${esc(NAME(r.who))}…" autocomplete="off" enterkeyhint="send"><button class="pill soft">发</button></form>`:""}</div></div>`;
}
function wireCmts(root, after){
  root.querySelectorAll("[data-reply]").forEach(b=>b.onclick=()=>{ cmtReply[b.dataset.t]=+b.dataset.reply; after(); setTimeout(()=>root.querySelector(`form.cmf[data-t="${b.dataset.t}"] input`)?.focus(),50); });
  root.querySelectorAll("[data-cmr-x]").forEach(b=>b.onclick=()=>{ delete cmtReply[b.dataset.cmrX]; after(); });
  root.querySelectorAll("[data-cmdel]").forEach(b=>b.onclick=async()=>{ if(!b._c){ b._c=1; b.textContent="确认删？"; return; }
    try{ await api("DELETE","comment/"+b.dataset.cmdel); await loadState(); after(); }catch(e){ toast("没删成："+e.message); } });
  root.querySelectorAll("form.cmf").forEach(f=>f.onsubmit=async e=>{ e.preventDefault(); const text=f.text.value.trim(); if(!text) return; const t=f.dataset.t;
    try{ await api("POST","comment",{target:t, text, reply_to:cmtReply[t]||null}); delete cmtReply[t]; await loadState(); after(); toast(`回好了，${PT()}那边会收到`); }
    catch(e){ toast("没发出去："+e.message); } });
}
const SOON = () => `过一会儿会送到${PT()}那`;
// ---------- 「这一次」整页：登机牌（备注印在票上）+ 撕口 + 随记（多段）+ 照片 + 登机口（递整张 / 挑几段几张）----------
const tp={};   // tid -> {edit, pick, dpick, sel:{n:Set,p:Set}|null, nadd, ned, off, gate}
// 票面（活页夹和网格共用）：右上角能在两种样子之间切（和 iOS 一样）
function tripPassHTML(t, n, S, mode){
  const c=byId[t.city], o=byId[t.origin];
  const icon=mode==="binder"
    ? `<svg viewBox="0 0 18 18" aria-hidden="true">${[3,9,15].flatMap(y=>[3,9,15].map(x=>`<rect x="${x-2.2}" y="${y-2.2}" width="4.4" height="4.4" rx="1.2" fill="none" stroke="currentColor" stroke-width="1.3"/>`)).join("")}</svg>`
    : `<svg viewBox="0 0 18 18" aria-hidden="true"><path d="M2.5 5.5V14a1.5 1.5 0 0 0 1.5 1.5h10a1.5 1.5 0 0 0 1.5-1.5V7a1.5 1.5 0 0 0-1.5-1.5H8.6L7 3.5H4A1.5 1.5 0 0 0 2.5 5Z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg>`;
  return `<div class="tbp">
      <div class="tk-air"><span class="tk-l">BOARDING PASS · 第 ${n} 次</span><span class="tk-btns"><button class="tk-mode" data-tp="mode" aria-label="${mode==="binder"?"换成网格":"换成活页夹"}">${icon}</button><button class="x" aria-label="关闭">×</button></span></div>
      ${routeHTML(t)}
      <div class="tbp-grid"><span><span class="tk-l">DATE</span><span class="tk-v">${t.date_start?esc(fmtTD(t)):"——"}</span></span>
        <span><span class="tk-l">DISTANCE</span><span class="tk-v">${o?km(o,c).toLocaleString("en-US")+" km":"——"}</span></span>
        <span><span class="tk-l">SEAT</span><span class="tk-v">${String(n).padStart(2,"0")}</span></span></div>
      ${t.remark?`<div class="tbp-rem"><span class="tk-l">REMARKS · 备注</span><p>${esc(t.remark)}</p></div>`:""}
      ${S.edit||S.pick||S.dpick?"":`<div class="tbp-edit"><button class="lk" data-tp="edit">${t.remark?"改日期和备注":t.date_start?"加一句备注":"补日期 · 加一句备注"}</button><button class="lk" data-tp="pick">改出发地</button><button class="lk" data-tp="dpick">${t.dest?"改终点":"加终点"}</button></div>`}
    </div>`;
}
// 票上的：关闭 / 切样子 / 改日期备注 / 出发地 / 终点
function wireTripPass(el, t, S){
  const tid=t.id, again=()=>{ if(!el.hidden && +el.dataset.tid===tid) openTrip(tid); }, close=()=>{ el.hidden=true; el.innerHTML=""; el._bd=null; delete tp[tid]; rerender(); };
  el.querySelector(".tbp .x").onclick=close; el.onclick=e=>{ if(e.target===el) close(); };
  el.querySelectorAll(".tbp [data-tp]").forEach(b=>b.onclick=()=>{ const a=b.dataset.tp;
    if(a==="mode"){ S.grid=!S.grid; S.bopen=0; S.leaf=null; again(); }
    else if(a==="edit"){ S.edit=1; again(); setTimeout(()=>el.querySelector("form.tf input")?.focus(),50); }
    else if(a==="pick"){ S.pick=1; again(); }
    else if(a==="dpick"){ S.dpick=1; again(); } });
  // 改日期和备注：日期先翻成服务端认的写法，看不懂就在表单里说
  el.querySelector("[data-tf-cancel]")?.addEventListener("click",()=>{ S.edit=0; again(); });
  const tf=el.querySelector("form.tf"); if(tf) tf.onsubmit=async e=>{ e.preventDefault();
    const er=tf.querySelector(".tferr"), from=normDate(tf.date_start.value), to=normDate(tf.date_end.value);
    if(from===null||to===null){ er.textContent="这个日期我看不懂，写成 2019.8.3 这样试试"; er.hidden=false; return; }
    const btn=tf.querySelector(".pill.solid"); btn.disabled=true;
    try{ await api("PUT","trip/"+tid,{date_start:from, date_end:to, remark:tf.remark.value.trim()}); await loadState(); S.edit=0; again(); rerender(); toast("记下了 ✓"); }
    catch(err){ er.textContent="没存上："+err.message; er.hidden=false; btn.disabled=false; } };
  el.querySelectorAll("[data-origin]").forEach(b=>b.onclick=async()=>{ await setOrigin(t.city, b.dataset.origin, tid); S.pick=0; again(); });
  el.querySelector("[data-origin-search]")?.addEventListener("click",()=>{ S.pick=0; srch.pick={city:t.city,trip:tid}; srch.q=""; srch.country=null; openSearch(); });
  el.querySelector("[data-ck-cancelpick]")?.addEventListener("click",()=>{ S.pick=0; again(); });
  el.querySelectorAll("[data-dest]").forEach(b=>b.onclick=async()=>{ S.dpick=0; await setDest(t.city, b.dataset.dest||null, tid); });
  el.querySelector("[data-dest-search]")?.addEventListener("click",()=>{ S.dpick=0; srch.pick={city:t.city,trip:tid,field:"dest"}; srch.q=""; srch.country=null; openSearch(); });
  el.querySelector("[data-dest-x]")?.addEventListener("click",()=>{ S.dpick=0; again(); });
}
// 日期：2019 / 2019.8 / 2019.8.3 / 2019-8-3 / 2019年8月3日 / 20190803 都认，统一成 2019-08-03；空 = ""，看不懂 = null
function normDate(raw){
  let s=String(raw||"").trim(); if(!s) return "";
  if(/^\d{8}$/.test(s)) s=`${s.slice(0,4)}-${s.slice(4,6)}-${s.slice(6)}`;
  const p=s.split(/[.。．\/／\-－—–年月日\s]+/).filter(Boolean);
  if(p.length<1||p.length>3||p[0].length!==4||!p.every(x=>/^\d+$/.test(x))) return null;
  const [y,m,d]=p.map(Number);
  if(p.length>=2&&!(m>=1&&m<=12)) return null;
  if(p.length===3){ const dt=new Date(Date.UTC(y,m-1,d)); if(!(d>=1&&d<=31)||dt.getUTCMonth()!==m-1||dt.getUTCDate()!==d) return null; }
  return [String(y).padStart(4,"0"), ...p.slice(1).map(x=>String(+x).padStart(2,"0"))].join("-");
}
// GATE：递整张票 / 挑几段几张 + 待送达（expanded = 活页夹里的 GATE 页，直接摊开）
function gateHTML(t, S, expanded){
  if(!SH()) return "";
  const tid=t.id, P=esc(PT()), ps=photosOf(tid), ns=notesOf(tid);
  const mine=it=>(it.type==="trip"&&it.id===tid)||(it.type==="photo"&&ps.some(p=>p.id===it.id))||(it.type==="note"&&ns.some(x=>x.id===it.id));
  const pend=(state.shares||[]).filter(x=>x.who==="me" && x.status==="pending" && x.items.some(mine));
  const what=x=>{ const k={trip:0,note:0,photo:0}; x.items.filter(mine).forEach(it=>k[it.type]++); return [k.trip?"整张票":"", k.note?`${k.note} 段随记`:"", k.photo?`${k.photo} 张照片`:""].filter(Boolean).join(" + "); };
  return (S.gate||expanded?`<div class="gatebox"><button class="gate" data-gt="whole"><span><span class="tk-l">GATE · 递给${P}</span><b>递整张票</b><small>备注、${ns.length} 段随记、${ps.length} 张照片一起</small></span><i>→</i></button>
          ${ns.length+ps.length?`<button class="gate soft" data-gt="sel"><span><span class="tk-l">GATE · 递给${P}</span><b>挑几段、几张</b></span><i>→</i></button>`:""}${expanded?"":`<button class="lk" data-gt="gatex">先不递</button>`}</div>`
      : `<button class="gate" data-gt="gate"><span><span class="tk-l">GATE · 递给${P}</span><b>${ns.length+ps.length?"递整张票，或挑几段、几张":"把这张票递过去"}</b></span><i>→</i></button>`)
    + (pend.length?`<div class="pend">${pend.map(x=>`<p><span>待送达 · ${what(x)}${x.note?` · “${esc(x.note)}”`:""}</span><button class="lk" data-unshare="${x.id}">撤回</button></p>`).join("")}<p class="hint">一小会儿里连着递的会合成一条送过去；送到之前都能撤回。</p></div>`:"");
}
function wireGate(root, t, S, after){
  const tid=t.id;
  root.querySelectorAll("[data-gt]").forEach(b=>b.onclick=async()=>{ const a=b.dataset.gt;
    if(a==="gate"){ S.gate=1; after(); }
    else if(a==="gatex"){ S.gate=0; after(); }
    else if(a==="sel"){ S.gate=0; S.bopen=0; S.leaf=null; S.sel={n:new Set(),p:new Set()}; openTrip(tid); }
    else if(a==="whole"){ b.disabled=true; try{ await api("POST","share",{items:[{type:"trip",id:tid}], note:""}); await loadState(); S.gate=0; after(); toast(`整张票递出了，${SOON()}`); }catch(e){ b.disabled=false; toast("没递出去："+e.message); } } });
  root.querySelectorAll("[data-unshare]").forEach(b=>b.onclick=async()=>{ try{ const r=await api("DELETE","share/"+b.dataset.unshare); await loadState(); after(); rerender(); toast(r.removed?"撤回了":"已经送出去了，撤不回"); }catch(e){ toast("没撤回："+e.message); } });
}
// 「这一次」：默认是活页夹（binder.js）；票右上角切到老的网格，「挑几段、几张」也走网格
function openTrip(tid, opt={}){
  const t=state.ck.find(x=>x.id===tid), el=$("#trip"); if(!t){ el.hidden=true; return; }
  const S=tp[tid]||(tp[tid]={});
  if(opt.leaf){ S.grid=0; S.sel=null; }
  if(!SH()) S.sel=null;
  if(!S.grid && !S.sel) return bdOpen(tid, opt);
  el.classList.remove("bmode"); el._bd=null;
  const ts=tripsOf(t.city), n=ts.findIndex(x=>x.id===tid)+1, ps=photosOf(tid), ns=notesOf(tid);
  el.hidden=false; el.dataset.tid=tid;
  const sh=SH(), P=esc(PT()), sel=S.sel, nsel=sel?sel.n.size+sel.p.size:0;
  el.innerHTML=`<div class="shin tp bpage">
    ${tripPassHTML(t, n, S, "grid")}
    <div class="tear"></div>
    ${S.edit?tripForm(t):""}${S.pick?originChips(t.city, t.origin||null):""}${S.dpick?destChips(t.city, t.dest||null):""}
    ${sel?`<div class="selbar"><span>${nsel?`选了 ${[sel.n.size?sel.n.size+" 段":"",sel.p.size?sel.p.size+" 张":""].filter(Boolean).join("、")}`:"点随记或照片，选要递的"}</span><button class="lk" data-tp="all">${nsel===ns.length+ps.length?"全不选":"全选"}</button><button class="lk" data-tp="selx">取消</button></div>`:""}
    <div class="sh2"><b>随记</b><span>${ns.length?ns.length+" 段":"还没有"}</span></div>
    ${ns.map(x=> S.ned===x.id ? `<form class="nf" data-nid="${x.id}"><label class="vh-only" for="nt-${x.id}">改随记</label><textarea id="nt-${x.id}" name="text" rows="5" maxlength="5000">${esc(x.text)}</textarea>
        <div class="ckacts"><button class="pill solid">保存</button><button type="button" class="lk" data-ned-x>先不改</button><button type="button" class="lk warn" data-ndel="${x.id}">删掉这段</button></div></form>`
      : `<div class="nt ${sel?"selable":""} ${sel?.n.has(x.id)?"on":""}" ${sel?`data-nsel="${x.id}" role="button" tabindex="0"`:""}>${sel?`<i class="ck2">${sel.n.has(x.id)?"✓":""}</i>`:""}<p>${esc(x.text)}</p>
        ${sel?"":`<div class="nm"><span>${ago(x.updated||x.created)} 记</span>${sh?`<button class="lk" data-nshare="${x.id}">递这段</button>`:""}<button class="lk" data-ned="${x.id}">改</button></div>`}
        ${sel?"":cmtBlock("note:"+x.id)}</div>`).join("")}
    ${sel?"":S.nadd?`<form class="nf" data-new="1"><label class="vh-only" for="ntnew">写一段随记</label><textarea id="ntnew" name="text" rows="5" maxlength="5000" placeholder="这一趟，想记下点什么…长短都行"></textarea>
        <div class="ckacts"><button class="pill solid">记下</button><button type="button" class="lk" data-nadd-x>先不写</button></div></form>`
      : `<button class="addsm" data-tp="nadd">＋ 写一段</button>`}
    <div class="sh2"><b>照片</b><span>${ps.length?ps.length+" 张 · 点开看大图":"还没有"}</span></div>
    ${ps.length?`<div class="pgrid tpg ${sel?"selecting":""}">${ps.map(p=>`<button class="pth ${sel?.p.has(p.id)?"on":""}" data-ph="${p.id}" aria-label="${sel?"选择":"看"}照片${p.caption?"："+esc(p.caption):""}"><img src="api/photo/img/${p.id}?w=600" loading="lazy" alt="">${p.caption?`<span class="pcap">${esc(p.caption)}</span>`:""}${sh&&cmtsOf("photo:"+p.id).length?`<i class="pcn">${cmtsOf("photo:"+p.id).length}</i>`:""}${sel?`<i class="ck2">${sel.p.has(p.id)?"✓":""}</i>`:""}</button>`).join("")}
      ${sel?"":`<button class="pth add" data-addph="${tid}"><b>＋</b><span>加照片</span></button>`}</div>`
      : sel?"":`<button class="addsm" data-addph="${tid}">＋ 加照片</button><p class="hint">不放照片也行，有随记就够了。</p>`}
    ${sel?`<div class="sendbox"><label class="vh-only" for="tpnote">附一句话</label><input id="tpnote" class="aptags" maxlength="500" placeholder="附一句话给${P}（选填）" autocomplete="off">
        <button class="gate" data-tp="send" ${nsel?"":"disabled"}><span><span class="tk-l">GATE · 递给${P}</span><b>递出${nsel?` ${nsel} 样`:""}</b></span><i>→</i></button></div>`
      : gateHTML(t, S, false)}
    ${cmtBlock("trip:"+tid)}
    <div class="tpdel"><button class="lk warn" data-tp="off">${S.off?(ps.length||ns.length?"随记和照片也会一起取下，再点一次确认":"再点一次确认"):ts.length>1?"删掉这一次":"取消来过"}</button></div>
  </div>`;
  const again=()=>{ if(!el.hidden && +el.dataset.tid===tid) openTrip(tid); };   // 异步回来时这一层可能已经关了，别把它又打开
  const share=async(items, note, msg)=>{ try{ await api("POST","share",{items, note}); await loadState(); S.sel=null; S.gate=0; again(); rerender(); toast(msg); }catch(e){ toast("没递出去："+e.message); } };
  wireTripPass(el, t, S);
  wireGate(el, t, S, again);
  el.querySelectorAll(".shin > [data-tp], .selbar [data-tp], .sendbox [data-tp], .tpdel [data-tp]").forEach(b=>b.onclick=async()=>{ const a=b.dataset.tp;
    if(a==="nadd"){ S.nadd=1; again(); setTimeout(()=>el.querySelector("#ntnew")?.focus(),50); }
    else if(a==="selx"){ S.sel=null; again(); }
    else if(a==="all"){ const full=S.sel.n.size+S.sel.p.size===ns.length+ps.length; S.sel={n:new Set(full?[]:ns.map(x=>x.id)), p:new Set(full?[]:ps.map(p=>p.id))}; again(); }
    else if(a==="send"){ b.disabled=true; const k=S.sel.n.size+S.sel.p.size;
      share([...[...S.sel.n].map(id=>({type:"note",id})), ...[...S.sel.p].map(id=>({type:"photo",id}))], el.querySelector("#tpnote").value.trim(), `递出 ${k} 样，${SOON()}`); }
    else if(a==="off"){ if(!S.off){ S.off=1; again(); setTimeout(()=>{ if(S.off&&!el.hidden){ S.off=0; again(); } },4000); return; }
      el.hidden=true; el.innerHTML=""; delete tp[tid]; uncheck(t.city, tid); }
  });
  el.querySelectorAll("[data-ph]").forEach(b=>b.onclick=()=>{ const pid=+b.dataset.ph;
    if(S.sel){ S.sel.p.has(pid)?S.sel.p.delete(pid):S.sel.p.add(pid); again(); } else openPh(pid); });
  el.querySelectorAll("[data-nsel]").forEach(b=>{ const f=()=>{ const id=+b.dataset.nsel; S.sel.n.has(id)?S.sel.n.delete(id):S.sel.n.add(id); again(); }; b.onclick=f; b.onkeydown=e=>{ if(e.key==="Enter"||e.key===" "){ e.preventDefault(); f(); } }; });
  el.querySelectorAll("[data-addph]").forEach(b=>b.onclick=()=>openAddPhoto(tid));
  // 随记：写 / 改 / 删 / 递这段
  el.querySelector("[data-nadd-x]")?.addEventListener("click",()=>{ S.nadd=0; again(); });
  el.querySelector("[data-ned-x]")?.addEventListener("click",()=>{ S.ned=0; again(); });
  el.querySelectorAll("[data-ned]").forEach(b=>b.onclick=()=>{ S.ned=+b.dataset.ned; again(); setTimeout(()=>el.querySelector("form.nf textarea")?.focus(),50); });
  el.querySelectorAll("[data-ndel]").forEach(b=>b.onclick=async()=>{ if(!b._c){ b._c=1; b.textContent="确认删？"; return; }
    try{ await api("DELETE","note/"+b.dataset.ndel); await loadState(); S.ned=0; again(); rerender(); toast("删掉了"); }catch(e){ toast("没删成："+e.message); } });
  el.querySelectorAll("[data-nshare]").forEach(b=>b.onclick=()=>share([{type:"note",id:+b.dataset.nshare}], "", `这段递出了，${SOON()}`));
  el.querySelectorAll("form.nf").forEach(f=>f.onsubmit=async e=>{ e.preventDefault(); const text=f.text.value.trim(); if(!text) return toast("还没写呢");
    try{ if(f.dataset.new) await api("POST",`trip/${tid}/note`,{text}); else await api("PUT","note/"+f.dataset.nid,{text});
      await loadState(); S.nadd=0; S.ned=0; again(); rerender(); toast("记下了 ✓"); }catch(err){ toast("没存上："+err.message); } });
  wireCmts(el, again);
}
document.querySelectorAll("#trip,#sheet,#chat").forEach(L=>{ new MutationObserver(()=>{ const sh=L.querySelector(".shin"); if(sh&&!sh._drag){ sh._drag=1; sheetDrag(sh,{onClose:()=>L.querySelector(".x")?.click()}); } }).observe(L,{childList:true}); });
// ---------- 撕存根进「这一次」（撕的质感参考 github.com/jal-co/boarding-pass 的 tear.ts）----------
// 票身和存根各自用 clip-path 裁出形状：虚线两端是真的半圆缺口（不是盖两个圆）。
// 撕 = 进度 p 从上往下推：p 以上的纸桥断开，断口按每段穿孔随机错开（票身和存根互补），p 以下还是直的穿孔线；
// 存根绕左下角跟着掀开几度，缝从上往下张开。撕到底：轻震 → 存根跟手 → 松手往右下掉、淡出 → 「这一次」从下面升起。
const TK={NOTCH:8, PITCH:9, CUT:5, AMP:2.4, SWING:7, DIST:95};
function tkProfile(seed,h){
  let s=(seed*2654435761)>>>0; const rnd=()=>{ s=(s+0x6d2b79f5)>>>0; let t=s; t=Math.imul(t^(t>>>15),t|1); t^=t+Math.imul(t^(t>>>7),t|61); return ((t^(t>>>14))>>>0)/4294967296; };
  const nib={}; return Array.from({length:Math.ceil(h)+1},(_,y)=>{ const per=Math.floor((y-6)/TK.PITCH), w=y-6-per*TK.PITCH; if(w<TK.CUT) return 0; if(nib[per]===undefined) nib[per]=(rnd()-.5)*2; return nib[per]; });
}
const tkArc=(cx,cy,a0,a1)=>Array.from({length:7},(_,i)=>{ const a=a0+(a1-a0)*i/6; return `${(cx+Math.cos(a)*TK.NOTCH).toFixed(1)}px ${(cy+Math.sin(a)*TK.NOTCH).toFixed(1)}px`; });
function tkShape(tk, p){
  const main=tk.querySelector(".tk-main"), stub=tk.querySelector(".tk-stub"); if(!main||!stub) return;
  const w=main.offsetWidth, sw=stub.offsetWidth, h=main.offsetHeight, foot=tk.classList.contains("foot"), N=TK.NOTCH;
  if(!tk._prof||tk._prof.length<h+1) tk._prof=tkProfile(+tk.dataset.trip||1, h);
  const front=p*h, eb=[], es=[];
  for(let y=N; y<=h-(foot?0:N); y+=1){ const o=y<=front? tk._prof[y]*TK.AMP : 0; eb.push(`${(w+o).toFixed(1)}px ${y}px`); es.push(`${o.toFixed(1)}px ${y}px`); }
  main.style.clipPath=`polygon(0px 0px, ${tkArc(w,0,Math.PI,Math.PI/2).join(",")}, ${eb.join(",")}, ${foot?`${w}px ${h}px`:tkArc(w,h,-Math.PI/2,-Math.PI).join(",")}, 0px ${h}px)`;
  stub.style.clipPath=`polygon(${sw}px 0px, ${tkArc(0,0,0,Math.PI/2).join(",")}, ${es.join(",")}, ${foot?`0px ${h}px`:tkArc(0,h,-Math.PI/2,0).join(",")}, ${sw}px ${h}px)`;
}
function tearable(tk){
  const tid=+tk.dataset.trip, stub=tk.querySelector(".tk-stub");
  const go=()=>{ const el=$("#trip"); el.classList.add("rise"); openTrip(tid); setTimeout(()=>el.classList.remove("rise"),600); };
  requestAnimationFrame(()=>tkShape(tk,0)); new ResizeObserver(()=>{ if(!tk._p) tkShape(tk,0); }).observe(tk);
  if(reduced){ tk.onclick=go; return; }
  let p=0, hand={x:0,y:0}, raf=0, done=false;
  const paint=()=>{ raf=0; tkShape(tk,p); tk._p=p;
    stub.style.transform=`translate(${hand.x}px,${hand.y}px) rotate(${(TK.SWING*p).toFixed(2)}deg)`; tk.style.setProperty("--stubLift",p.toFixed(2)); };
  const set=v=>{ p=v; if(!raf) raf=requestAnimationFrame(paint); };
  const lift=()=>{ document.querySelectorAll(".tk.lift").forEach(x=>x!==tk&&x.classList.remove("lift")); tk.classList.add("lift"); };
  const buzz=()=>{ try{ navigator.vibrate&&navigator.vibrate(18); }catch(e){} };
  const fall=()=>{ if(done) return; done=true; tk.classList.add("tearing");
    stub.style.transition="transform .55s cubic-bezier(.5,0,.8,.6), opacity .55s ease-in";
    stub.style.transform=`translate(${hand.x+26}px,${hand.y+150}px) rotate(34deg)`; stub.style.opacity="0";
    setTimeout(go,380);
    setTimeout(()=>{ done=false; p=0; hand={x:0,y:0}; tk._p=0; stub.style.transition=""; stub.style.opacity=""; stub.style.transform=""; tk.classList.remove("tearing","lift"); tkShape(tk,0); },1300); };
  const tween=(to,ms,then)=>{ const from=p, t0=performance.now(); const step=t=>{ const k=Math.min(1,(t-t0)/ms), e=1-Math.pow(1-k,3); set(from+(to-from)*e); if(k<1) requestAnimationFrame(step); else then&&then(); }; requestAnimationFrame(step); };
  const autoTear=()=>{ lift(); tween(1,420,()=>{ buzz(); fall(); }); };   // 轻点：自己从上往下撕开
  let g=null;
  stub.addEventListener("pointerdown",e=>{ if(done) return; e.stopPropagation(); lift(); stub.setPointerCapture(e.pointerId); g={x:e.clientX,y:e.clientY,peak:p,moved:false,ax:null,ay:null}; });
  stub.addEventListener("pointermove",e=>{ if(!g) return; const dx=e.clientX-g.x, dy=e.clientY-g.y; if(Math.abs(dx)+Math.abs(dy)>5) g.moved=true;
    if(g.ax===null){ const d=Math.max(0,dx*.65+dy*.35-4), n=Math.min(1,Math.max(g.peak,d/TK.DIST)); g.peak=n; set(n);
      if(n>=1){ g.ax=e.clientX; g.ay=e.clientY; buzz(); } }                 // 撕到底：轻震，之后存根跟手
    else { hand={x:e.clientX-g.ax, y:e.clientY-g.ay}; set(1); } });
  const end=e=>{ if(!g) return; const st=g; g=null; e.stopPropagation();
    if(!st.moved) return autoTear();
    if(p>=1) return fall();
    tween(0,260); };                                                          // 没撕到底：纸桥还连着，弹回去
  stub.addEventListener("pointerup",end); stub.addEventListener("pointercancel",end);
  stub.addEventListener("click",e=>{ e.stopPropagation(); e.preventDefault(); });
  tk.onclick=()=>{ if(done) return; tk.classList.contains("lift") ? autoTear() : lift(); };
  tk.onkeydown=e=>{ if(e.key==="Enter"||e.key===" "){ e.preventDefault(); tk.classList.contains("lift")?autoTear():lift(); } };
}
addEventListener("pointerdown",e=>{ if(!e.target.closest(".tk")) document.querySelectorAll(".tk.lift:not(.tearing)").forEach(x=>x.classList.remove("lift")); },true);
const tripOpen = () => { const el=$("#trip"); return !el.hidden && +el.dataset.tid; };
// 加照片：从手机 / 电脑选。先算 sha256 问服务器哪些传过（同一张只存一份），再逐张上传
function openAddPhoto(tid){
  const t=state.ck.find(x=>x.id===tid), c=byId[t.city], sh=$("#sheet"); sh.hidden=false;
  sh.innerHTML=`<div class="shin ap"><div class="aph"><b>给${esc(c.name)}这一次加照片</b><button class="x" aria-label="关闭">×</button></div>
    <div class="apsrc"><label class="apb"><input type="file" accept="image/*" multiple hidden><b>从手机 / 电脑选</b><i>可以多选；传过的照片不会再存一份</i></label></div><div class="apbody"></div></div>`;
  const close=()=>{ sh.hidden=true; sh.innerHTML=""; };
  sh.querySelector(".x").onclick=close; sh.onclick=e=>{ if(e.target===sh) close(); };
  sh.querySelector("input[type=file]").onchange=e=>{ if(e.target.files.length) localFlow(sh, t, [...e.target.files], close); };
}
async function sha256Of(f){ const b=await crypto.subtle.digest("SHA-256", await f.arrayBuffer()); return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join(""); }
// 一次传多张：每张一行写自己的配文，传完再 PUT（upload 回 photo.id）
async function localFlow(sh, t, files, close){
  const body=sh.querySelector(".apbody"); sh.querySelector(".apsrc").hidden=true;
  body.innerHTML=`<p class="hint">正在比对指纹，看看哪些已经传过…</p>`;
  const items=[]; for(const f of files.slice(0,30)) items.push({f, sha:crypto.subtle?await sha256Of(f):"", url:URL.createObjectURL(f)});
  let hits={}; try{ hits=(await api("POST","photo/check",{sha256:items.map(x=>x.sha).filter(Boolean)})).hits||{}; }catch(e){}
  items.forEach(x=>x.hit=!!hits[x.sha]);
  body.innerHTML=`<div class="apl rows">${items.map((x,i)=>`<div class="api" data-i="${i}"><img src="${x.url}" alt=""><div class="apf">
        <span class="${x.hit?"old":"new"}">${x.hit?"传过了":"新照片"}</span>
        <label class="vh-only" for="apc${i}">第 ${i+1} 张的配文</label><input id="apc${i}" class="apcap" maxlength="1000" placeholder="配文（选填）" autocomplete="off"></div></div>`).join("")}</div>
    ${items.every(x=>x.hit)?`<p class="hint">这些照片都传过了，直接挂上，不会再存一份。</p>`:""}
    <button class="pill solid apgo">挂上 ${items.length} 张</button><p class="hint approg" hidden></p>`;
  body.querySelector(".apgo").onclick=async e=>{ const btn=e.currentTarget; btn.disabled=true; const pr=body.querySelector(".approg"); pr.hidden=false;
    let ok=0, dup=0, capFail=0;
    for(const [i,x] of items.entries()){ pr.textContent=`${x.hit?"挂上":"上传"}第 ${i+1} / ${items.length} 张…`;
      const cap=body.querySelector(`.api[data-i="${i}"] .apcap`).value.trim();
      try{
        const fd=new FormData(); fd.append("file",x.f,x.f.name);
        const r=await fetch(`api/trip/${t.id}/upload`,{method:"POST",body:fd});
        if(!r.ok) throw new Error((await r.json().catch(()=>({}))).detail||r.status);
        const j=await r.json(); if(j.dedup) dup++;
        ok++;
        if(cap&&j.photo?.id){ try{ await api("PUT","photo/"+j.photo.id,{caption:cap}); }catch(err){ capFail++; } }
      }catch(err){ toast(`第 ${i+1} 张没传上：${err.message}`); }
    }
    items.forEach(x=>URL.revokeObjectURL(x.url));
    await loadState(); close(); rerender(); if(tripOpen()) openTrip(tripOpen());
    toast(`挂上 ${ok} 张${dup?`（${dup} 张以前传过，没重复存）`:""}${capFail?`，${capFail} 张配文没存上`:""}`);
  };
}
// 看照片：大图 + 配文（保存 → 已记下 ✓）+ 单选标签 + 只递这一张 + 留言 + 取下
function openPh(pid, opt={}){
  const p=(state.photos||[]).find(x=>x.id===pid); if(!p) return;
  const t=state.ck.find(x=>x.id===p.trip_id), ts=tripsOf(t.city), n=ts.findIndex(x=>x.id===t.id)+1, lb=$("#lb"), sh=SH(), P=esc(PT());
  const pend=sh&&(state.shares||[]).find(x=>x.who==="me" && x.status==="pending" && x.items.length===1 && x.items[0].type==="photo" && x.items[0].id===pid);
  lb.hidden=false; lb.dataset.pid=pid;
  lb.innerHTML=`<div class="lbin phv"><button class="x" aria-label="关闭">×</button><img class="phimg" src="api/photo/img/${pid}?w=1600" alt="${esc(p.caption||"")}">
    <div class="lbt"><div class="phstrip"><span class="phr">${t.origin&&byId[t.origin]?`${code3(t.origin)} <i>→</i> `:""}${code3(t.city)}</span><span class="tk-l">SEAT ${String(n).padStart(2,"0")}${t.date_start?` · ${esc(fmtTD(t))}`:""}</span></div>
    <label class="vh-only" for="phcap">配文</label><textarea id="phcap" class="phcap" rows="3" maxlength="1000" placeholder="给这张写段配文…">${esc(p.caption||"")}</textarea>
    <div class="capbar"><span class="capst">${p.caption?"✓ 已记下":""}</span><button class="pill soft" data-capsave hidden>保存配文</button></div>
    <div class="tagbar">${TAGS.map(x=>`<button class="tg ${p.tag===x?"on":""}" data-ptag="${esc(x)}">${esc(x)}</button>`).join("")}</div>
    ${!sh?"": opt.send?`<div class="sendbox"><label class="vh-only" for="phnote">附一句话</label><input id="phnote" class="aptags" maxlength="500" placeholder="附一句话给${P}（选填）" autocomplete="off">
        <button class="gate" data-phsend><span><span class="tk-l">GATE · 递给${P}</span><b>递出这一张</b></span><i>→</i></button><button class="lk" data-phsendx>先不递</button></div>`
      : pend?`<div class="pend"><p><span>这张在路上${pend.note?` · “${esc(pend.note)}”`:""}</span><button class="lk" data-unshare="${pend.id}">撤回</button></p></div>`
      : `<button class="gate" data-phshare><span><span class="tk-l">GATE · 递给${P}</span><b>只递这一张</b></span><i>→</i></button>`}
    ${cmtBlock("photo:"+pid)}
    <div class="tpdel"><button class="lk warn" data-phdel>取下这张</button></div></div></div>`;
  const close=()=>{ lb.hidden=true; lb.dataset.pid=""; lb.innerHTML=""; rerender(); if(tripOpen()) openTrip(tripOpen()); };
  lb.querySelector(".x").onclick=close; lb.onclick=e=>{ if(e.target===lb) close(); };
  const cap=lb.querySelector(".phcap"), st=lb.querySelector(".capst"), sv=lb.querySelector("[data-capsave]");
  cap.oninput=()=>{ const dirty=cap.value.trim()!==(p.caption||""); sv.hidden=!dirty; st.textContent=dirty?"还没保存":(p.caption?"✓ 已记下":""); st.classList.toggle("dirty",dirty); };
  const saveCap=async()=>{ const v=cap.value.trim(); if(v===(p.caption||"")) return;
    sv.disabled=true; st.textContent="保存中…";
    try{ await api("PUT","photo/"+pid,{caption:v}); p.caption=v; sv.hidden=true; st.classList.remove("dirty"); st.textContent=v?"✓ 已记下":"配文清空了"; st.classList.add("pop"); setTimeout(()=>st.classList.remove("pop"),600); }
    catch(e){ st.textContent="没存上，再点一次保存"; } sv.disabled=false; };
  sv.onclick=saveCap;
  lb.querySelectorAll("[data-ptag]").forEach(b=>b.onclick=async()=>{ const v=p.tag===b.dataset.ptag?null:b.dataset.ptag;
    try{ await api("PUT","photo/"+pid,{tag:v}); p.tag=v; lb.querySelectorAll("[data-ptag]").forEach(x=>x.classList.toggle("on",x.dataset.ptag===v)); toast(v?`标成「${v}」✓`:"标签去掉了"); }catch(e){ toast("没存上："+e.message); } });
  lb.querySelector("[data-phshare]")?.addEventListener("click",async()=>{ await saveCap(); openPh(pid,{send:1}); setTimeout(()=>lb.querySelector("#phnote")?.focus(),50); });
  lb.querySelector("[data-phsendx]")?.addEventListener("click",()=>openPh(pid));
  lb.querySelector("[data-phsend]")?.addEventListener("click",async e=>{ e.currentTarget.disabled=true;
    try{ await saveCap(); await api("POST","share",{items:[{type:"photo",id:pid}], note:lb.querySelector("#phnote").value.trim()}); await loadState(); if(!lb.hidden&&+lb.dataset.pid===pid) openPh(pid); toast(`递出了，${SOON()}`); }
    catch(err){ toast("没递出去："+err.message); } });
  lb.querySelectorAll("[data-unshare]").forEach(b=>b.onclick=async()=>{ try{ const r=await api("DELETE","share/"+b.dataset.unshare); await loadState(); if(!lb.hidden&&+lb.dataset.pid===pid) openPh(pid); toast(r.removed?"撤回了":"已经送出去了，撤不回"); }catch(e){ toast("没撤回："+e.message); } });
  const del=lb.querySelector("[data-phdel]");
  del.onclick=async()=>{ if(!del._c){ del._c=1; del.textContent="确认取下？"; return; }
    try{ await api("DELETE","photo/"+pid); await loadState(); close(); toast("取下了"); }catch(e){ toast("没取下："+e.message); } };
  wireCmts(lb, ()=>{ if(!lb.hidden && +lb.dataset.pid===pid) openPh(pid); });
}
// 递城市 / 某个景点 / 某道菜：纸飞机 → 一个小面板（附不附图、附一句话）→ 进「待送达」
async function shareThing(id, what){
  const [k,i]=what.split(":"), item = k==="city" ? {type:"city",city:id} : {type:k,city:id,i:+i};
  const name = k==="city" ? byId[id].name : (DATA[id]?.[k==="sight"?"sights":"foods"]?.[+i]?.name||"");
  const sh=$("#sheet"), P=esc(PT()); sh.hidden=false;   // 自己旅行的照片一定附图；城市/景点/美食由你选附不附图
  sh.innerHTML=`<div class="shin ap"><div class="aph"><b>把「${esc(name)}」递给${P}</b><button class="x" aria-label="关闭">×</button></div>
    <label class="apalb"><input type="checkbox" name="img" checked><span>附上图片<i>附了${P}直接看到；不附就只给一句怎么取图</i></span></label>
    <label class="vh-only" for="shnote">附一句话</label><input id="shnote" class="aptags" maxlength="500" placeholder="附一句话（选填）" autocomplete="off">
    <button class="gate" data-go><span><span class="tk-l">GATE · 递给${P}</span><b>递出</b></span><i>→</i></button></div>`;
  const close=()=>{ sh.hidden=true; sh.innerHTML=""; };
  sh.querySelector(".x").onclick=close; sh.onclick=e=>{ if(e.target===sh) close(); };
  sh.querySelector("[data-go]").onclick=async e=>{ const b=e.currentTarget; b.disabled=true;
    try{ await api("POST","share",{items:[item], note:sh.querySelector("#shnote").value.trim(), img:sh.querySelector("[name=img]").checked}); await loadState(); close(); rerender(); toast(`把「${name}」递出了，${SOON()}`); }
    catch(err){ toast("没递出去："+err.message); b.disabled=false; } };
}
// pick：「new」= 新记一次；数字 = 改那一次的出发地
async function setOrigin(id, origin, pick){
  pick = pick ?? ui[id]?.pick;
  try{ const r = pick==="new"||pick==null ? await api("POST","checkin/"+encodeURIComponent(id), origin===undefined?{}:{origin})
                                          : await api("PUT","trip/"+pick, {origin});
    await loadState(); if(ui[id]) ui[id].pick=0;
    refreshLayers(); renderSide(); rerender(); if(tripOpen()) openTrip(tripOpen());
    const o=byId[r.checkin.origin], n=tripsOf(id).length;
    toast(pick!=="new"&&pick!=null ? (o?`改好了：从${o.name}出发`:"改好了：这次不连线") : (o?`打卡！${n>1?`第 ${n} 次，`:""}红线从${o.name}连过来了`:`打卡！${n>1?`第 ${n} 次`:""}`));
  }catch(e){ toast("没存上："+e.message); }
}
async function uncheck(id, tid){
  try{ const r=await api("DELETE","trip/"+tid); await loadState();
    refreshLayers(); renderSide(); rerender();
    toast(r.reset_children?.length?`取消了；从这里出发的${r.reset_children.map(x=>byId[x]?.name||x).join("、")}改回默认出发地`:"删掉了");
  }catch(e){ toast("没删成："+e.message); }
}
function sightSheet(id,i,from){
  const x=DATA[id].sights[i], lb=$("#lb"); lb.hidden=false; lb.classList.add("sheet-in");
  lb.innerHTML=`<div class="lbin ls-sheet"><button class="x" aria-label="关闭">×</button>${x.img?img(x.img,x.name,"sh-img"):""}
    <div class="lbt"><b class="st">${esc(x.name)}</b><i class="so">${x.orig&&x.orig!==x.name?esc(x.orig):""}</i><p class="bp">${esc(x.intro)}</p>
    ${x.src||SH()?`<div class="va">${x.src?`<a class="lk" href="${esc(x.src)}" target="_blank" rel="noopener">维基原条目 ↗</a>`:""}${SH()?`<button class="pill solid" data-share="sight:${i}">${PLANE}<span>递给${esc(PT())}</span></button>`:""}</div>`:""}</div></div>`;
  const big=lb.querySelector(".sh-img"), small=from?.querySelector("img");
  // FLIP：大图先摆到小卡片的位置，再动画回到自己的位置
  const flip=(reverse)=>{
    if(reduced||!big||!small) return Promise.resolve();
    const a=small.getBoundingClientRect(), b=big.getBoundingClientRect(); if(!b.width||!a.width) return Promise.resolve();
    const t=`translate(${a.left-b.left}px,${a.top-b.top}px) scale(${a.width/b.width},${a.height/b.height})`;
    big.style.transformOrigin="0 0";
    const frames=reverse?[{transform:"none"},{transform:t}]:[{transform:t},{transform:"none"}];
    return big.animate(frames,{duration:reverse?320:460,easing:"cubic-bezier(.2,.8,.2,1)",fill:"both"}).finished;
  };
  if(big && !big.complete) big.addEventListener("load",()=>flip(false),{once:true}); else flip(false);
  const close=async()=>{ lb.classList.remove("sheet-in"); lb.classList.add("sheet-out"); await flip(true).catch(()=>{}); lb.hidden=true; lb.classList.remove("sheet-out"); };
  lb.querySelector(".x").onclick=close;
  lb.onclick=e=>{ if(e.target===lb) close(); };
  lb.querySelector("[data-share]")?.addEventListener("click",()=>shareThing(id, "sight:"+i));
}

function openCity(id, opt={}){
  const c=byId[id]; if(!c) return;
  const first = selId!==id; selId=id;
  if(!IDX[id] && !GEN[id]){ GEN[id]={status:"checking"}; getJSON(`api/city/${encodeURIComponent(id)}/gen`).then(r=>{ GEN[id]=r; if(r.status==="running") pollGen(id); if(r.status==="done") pollGen(id); if(selId===id) rerender(); }).catch(()=>{ delete GEN[id]; }); }
  if(IDX[id] && DATA[id]===undefined){ loadCity(id).then(()=>{ if(selId===id){ world.pathsData(outlinePaths(id)); openCity(id,{stay:1,keep:1}); } }); }
  document.querySelectorAll(".mk").forEach(m=>m.classList.toggle("on",m.dataset.id===id));
  if(first && !opt.stay){ stopSpin(); world.pathsData(outlinePaths(id)); world.pointOfView({lat:c.lat,lng:c.lng,altitude:zoomFor(id)},1400); }
  const card=$("#card"), top=card.scrollTop; card.innerHTML=cardHTML(id); card.classList.add("show");
  card.scrollTop = opt.keep ? top : 0;
  if(first){ document.body.classList.toggle("open-side",wide()); document.body.classList.toggle("open-sheet",!wide()); document.body.classList.remove("full"); }
  wireCard(card,id);
}
function wireCard(card,id){
  const u=ui[id], re=()=>openCity(id,{stay:1,keep:1});
  card.querySelector(".x")?.addEventListener("click",closeCard);
  card.querySelector(".grab")?.addEventListener("click",()=>document.body.classList.toggle("full"));
  card.querySelectorAll("[data-era]").forEach(b=>b.onclick=()=>{ u.open[b.dataset.era]=!u.open[b.dataset.era]; re(); });
  card.querySelector("[data-more]")?.addEventListener("click",()=>{ u.more=!u.more; re(); });
  card.querySelectorAll("[data-food]").forEach(b=>b.onclick=()=>{ u.food[b.dataset.food]=!u.food[b.dataset.food]; re(); });
  card.querySelectorAll(".tk[data-trip]").forEach(tearable);
  card.querySelectorAll("[data-share]").forEach(b=>b.onclick=()=>shareThing(id, b.dataset.share));
  // 对话组：递送那组回在 share:N 下；「平时说的」回某条就沿用那条挂的地方，不然挂在城市下
  card.querySelectorAll("[data-threply]").forEach(b=>b.onclick=()=>{ thr[b.dataset.tk]={reply:+b.dataset.threply}; re(); setTimeout(()=>card.querySelector(`form.thf[data-tk="${b.dataset.tk}"] input`)?.focus(),50); });
  card.querySelectorAll("[data-thx]").forEach(b=>b.onclick=()=>{ thr[b.dataset.thx]={}; re(); });
  card.querySelectorAll("form.thf").forEach(f=>f.onsubmit=async e=>{ e.preventDefault(); const text=f.text.value.trim(); if(!text) return; const key=f.dataset.tk;
    const R=thr[key]?.reply&&(state.cmts||[]).find(c=>c.id===thr[key].reply);
    const target = key.startsWith("share:") ? key : (R ? R.target : key);
    try{ await api("POST","comment",{target, text, reply_to:R?R.id:null}); thr[key]={}; await loadState(); re(); toast(`发出去了，${PT()}那边会收到`); }
    catch(err){ toast("没发出去："+err.message); } });
  wireCmts(card, re);
  card.querySelector("[data-gen]")?.addEventListener("click",e=>{ e.currentTarget.disabled=true; startGen(id, card.querySelector("#genpro")?.checked); });
  card.querySelector("[data-wish-on]")?.addEventListener("click",()=>{ u.wishing=1; re(); setTimeout(()=>card.querySelector(".wf2 input")?.focus(),50); });
  card.querySelector("[data-wish-edit]")?.addEventListener("click",()=>{ u.wishing=1; re(); setTimeout(()=>card.querySelector(".wf2 input")?.focus(),50); });
  card.querySelector("[data-wish-cancel]")?.addEventListener("click",()=>{ u.wishing=0; re(); });
  const wf2=card.querySelector("form.wf2"); if(wf2) wf2.onsubmit=e=>{ e.preventDefault(); setWish(id, wf2.note.value.trim()); };
  const woff=card.querySelector("[data-wish-off]");
  if(woff) woff.onclick=()=>{ if(u.woff) return unwish(id); u.woff=1; re(); setTimeout(()=>{ if(u.woff){ u.woff=0; selId===id&&re(); } },4000); };
  card.querySelector("[data-ck-on]")?.addEventListener("click",()=>{ u.pick="new"; re(); });

  card.querySelector("[data-ck-cancelpick]")?.addEventListener("click",()=>{ u.pick=0; re(); });
  card.querySelectorAll("[data-origin]").forEach(b=>b.onclick=()=>setOrigin(id,b.dataset.origin));
  card.querySelector("[data-origin-search]")?.addEventListener("click",()=>{ srch.pick={city:id,trip:u.pick}; srch.q=""; srch.country=null; openSearch(); });

  const rail=card.querySelector("[data-rail]");
  if(rail) wireRail(card, rail, id, u);
}
// 景点轮播：浏览器原生横向滚动 + 吸附（手指拖到哪跟到哪，松手带惯性），滚动时按离中线的距离连续调整大小/亮度/视差
function wireRail(card, rail, id, u){
  const cards=[...rail.children], n=cards.length, cnt=card.querySelector(".sh .cnt"), dots=[...card.querySelectorAll(".dots button")];
  const arrL=card.querySelector(".arr.l"), arrR=card.querySelector(".arr.r");
  const step=()=>cards[1] ? cards[1].offsetLeft-cards[0].offsetLeft : rail.clientWidth;
  const idx=()=>Math.max(0,Math.min(n-1,Math.round(rail.scrollLeft/step())));
  const goTo=(i,smooth=true)=>rail.scrollTo({left:Math.max(0,Math.min(n-1,i))*step(), behavior: smooth&&!reduced?"smooth":"auto"});
  let raf=0;
  const paint=()=>{ raf=0;
    const mid=rail.scrollLeft+rail.clientWidth/2, st=step();
    cards.forEach(el=>{
      const d=(el.offsetLeft+el.offsetWidth/2-mid)/st, a=Math.min(1,Math.abs(d));
      if(!reduced){
        el.style.transform=`scale(${1-.07*a})`;
        el.style.filter=`brightness(${1-.32*a})`;
        const im=el.querySelector("img"); if(im) im.style.transform=`translate3d(${(-d*28).toFixed(1)}px,0,0) scale(1.12)`;
      }
    });
    const k=idx(); if(k!==u.si){ u.si=k; }
    if(cnt) cnt.textContent=`${String(k+1).padStart(2,"0")} / ${String(n).padStart(2,"0")}`;
    dots.forEach((b,i)=>b.classList.toggle("on",i===k));
    arrL.hidden=k===0; arrR.hidden=k===n-1;
  };
  rail.addEventListener("scroll",()=>{ if(!raf) raf=requestAnimationFrame(paint); },{passive:true});
  addEventListener("resize",()=>{ if(rail.isConnected) goTo(u.si,false); });
  arrL.onclick=e=>{ e.stopPropagation(); goTo(idx()-1); };
  arrR.onclick=e=>{ e.stopPropagation(); goTo(idx()+1); };
  dots.forEach((b,i)=>b.onclick=()=>goTo(i));
  cards.forEach((el,i)=>el.onclick=()=>{ if(i!==idx()) return goTo(i); sightSheet(id,i,el); });
  requestAnimationFrame(()=>{ goTo(u.si,false); paint(); });   // 回到上次看到的那张（卡片重绘后也不跳回第一张）
}
const rerender = () => selId && openCity(selId,{stay:1,keep:1});
// 竖屏：卡片往上滑就自动拉满
$("#card").addEventListener("scroll",e=>{ if(!wide() && e.target.scrollTop>40) document.body.classList.add("full"); });
// 手机上的卡片是真正的底部抽屉：在顶部往下拖 → 全屏先缩回半屏，半屏再往下拖就收起；往上拖 → 全屏
function sheetDrag(el, {onClose, half}){
  let y0=null, dy=0, drag=false;
  el.addEventListener("touchstart",e=>{ if(wide()||e.touches.length>1) return;
    if(el.scrollTop>0 && !e.target.closest(".grab")) return;   // 内容还没滚到顶时，手指是在滚内容
    y0=e.touches[0].clientY; dy=0; drag=false; },{passive:true});
  el.addEventListener("touchmove",e=>{ if(y0===null) return; dy=e.touches[0].clientY-y0;
    if(!drag){ if(Math.abs(dy)<8) return; if(dy<0 && el.scrollTop>0){ y0=null; return; } drag=true; el.style.transition="none"; }
    if(dy>0){ e.preventDefault(); el.style.transform=`translateY(${dy}px)`; } },{passive:false});
  el.addEventListener("touchend",()=>{ if(y0===null) return; y0=null; el.style.transition=""; el.style.transform="";
    if(!drag) return;
    if(dy>110){ if(half&&half.isFull()){ half.collapse(); } else onClose(); }
    else if(dy<-50 && half) half.expand(); });
}
sheetDrag($("#card"), {onClose:()=>closeCard(), half:{isFull:()=>document.body.classList.contains("full"), collapse:()=>{ document.body.classList.remove("full"); $("#card").scrollTop=0; }, expand:()=>document.body.classList.add("full")}});
function closeCard(){
  selId=null; $("#card").classList.remove("show"); document.body.classList.remove("open-side","open-sheet","full");
  document.querySelectorAll(".mk.on").forEach(m=>m.classList.remove("on"));
  world.pathsData([]); const p=world.pointOfView(); world.pointOfView({lat:p.lat,lng:p.lng,altitude:innerWidth<700?2.6:2},1200);
}


