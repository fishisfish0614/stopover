// ---------- 「这一次」活页夹（数值和 ios/Stopover/Binder.swift 一致）----------
// 合上（每次进来都是合上）：票 + 磨砂文件夹（头 5 张探出来）+ 加一页 / GATE / TA 说，一屏放下。
// 点文件夹：前盖绕底边往下翻，纸一张张飞成竖条铺满；右上「合上」倒放回去。
// 竖条左右滑；按住一条往上拖过 110 = 把这页抽出来，长成海报内页（照片）或字纸（随记）。点一下也能抽。
// 网页没有 Vision：窄条不按人脸对齐，一律居中
const BK = {tabW:30, tabH:96, narrowW:46, coverW:78, minW:66, topGap:14, pull:110, tabFolder:22,
  tones:[["#A89F8F","#24221F"],["#E4DCC8","#2B2A28"],["#8E97A3","#14181D"],["#B08F63","#24190D"],["#34322E","#E6E2DA"],["#8A8A76","#191A12"]],
  note:["#F3EFE3","#1F2A38"], night:"#1F2A38", nightInk:"#E6E2DA", paper:"#E6E2DA", ink:"#1F2A38", dune:"#D8CBB2", harbor:"#3F5F86"};
const BD_ENTRY = {add:["#D8CBB2","#1F2A38"], gate:["#3F5F86","#E6E2DA"], talk:["#1F2A38","#E6E2DA"]};

// 纸纹：一小块随机细点平铺（同 Binder.swift 的 grain），只铺纸，不盖照片
(function(){ const n=90, c=document.createElement("canvas"); c.width=c.height=n; const x=c.getContext("2d");
  for(let i=0;i<520;i++){ x.fillStyle=`rgba(${Math.random()<.5?"0,0,0":"255,255,255"},${(.03+Math.random()*.06).toFixed(3)})`; x.fillRect(Math.random()*n|0, Math.random()*n|0, 1, 1+Math.random()*1.5); }
  document.documentElement.style.setProperty("--grain", `url(${c.toDataURL()})`); })();

function bdInsets(){ const p=document.createElement("div");
  p.style.cssText="position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top,0px) 0 env(safe-area-inset-bottom,0px)";
  document.body.appendChild(p); const cs=getComputedStyle(p), r={top:parseFloat(cs.paddingTop)||0, bottom:parseFloat(cs.paddingBottom)||0}; p.remove(); return r; }

// 按拍摄时间排、跨天才分章；随记写的时间落在哪天就夹进哪天，落不进的（事后补的）放最前面
function bdLeaves(t){
  const ps=photosOf(t.id).slice().sort((a,b)=>(a.taken??Infinity)-(b.taken??Infinity)||a.id-b.id);
  const dayOf=ts=>{ const d=new Date(ts*1000); d.setHours(0,0,0,0); return +d; };
  const days=[...new Set(ps.filter(p=>p.taken).map(p=>dayOf(p.taken)))].sort((a,b)=>a-b);
  const di=ts=>{ const i=days.indexOf(dayOf(ts)); return i<0?null:i; };
  const B=Array.from({length:Math.max(1,days.length)},()=>[]);
  ps.forEach((p,i)=>B[(p.taken?di(p.taken):null) ?? B.length-1].push({t:p.taken??Infinity, l:{id:"p"+p.id, kind:"photo", p, fig:i+1}}));
  const loose=[];
  notesOf(t.id).slice().sort((a,b)=>a.created-b.created).forEach(n=>{ const l={id:"n"+n.id, kind:"note", n}, b=di(n.created); b===null?loose.push(l):B[b].push({t:n.created, l}); });
  const en=(byId[t.city]?.en||"").toUpperCase(), k=ps.length;
  const out=[{id:"cover", kind:"cover", title:en, range:k?`_01–${String(k).padStart(2,"0")}`:"", sub:k?`${k} FIG${k===1?"":"S"}${days.length>1?` · ${days.length} DAYS`:""}`:"NO FIGS YET"}, ...loose];
  B.forEach((b,i)=>{ if(days.length>1){ const d=new Date(days[i]); out.push({id:"day"+(i+1), kind:"day", n:i+1, date:`${d.getMonth()+1}.${d.getDate()}`}); }
    out.push(...b.sort((x,y)=>(x.t-y.t)||0).map(x=>x.l)); });
  return {leaves:out, days};
}
const bdTab = l => l.kind==="photo"||l.kind==="note";

function bdWidths(ls, W){
  // 封面后面紧跟带标签的页（没分天）：封面加宽一个标签，不然城名被盖住
  const cover=BK.coverW+(ls.length>1&&bdTab(ls[1])?BK.tabW:0);
  let fixed=0, n=0; ls.forEach(l=>{ if(bdTab(l)) n++; else fixed+=l.kind==="cover"?cover:BK.narrowW; });
  const flex=n?Math.max(BK.minW,(W-fixed)/n):0;
  return ls.map(l=>bdTab(l)?flex:l.kind==="cover"?cover:BK.narrowW);
}
// 每天从头排：分隔页后面第一个标签总在最上面，不会盖住 DAY 字
function bdTabSeq(ls){ let n=0; return ls.map(l=>{ if(l.kind==="day") n=0; return bdTab(l)?n++:0; }); }
const bdTabY = (k,H) => 18 + (k%5)*Math.max(40,(H-BK.tabH-60)/4);

function bdLayout(W, H, ins, ticketH){
  const eH=SH()?54*2+10:54, eTop=H-ins.bottom-16-eH, top=ticketH+40, room=eTop-18-top, h=Math.max(170,Math.min(room,310));
  const back={x:24, y:top+Math.max(0,room-h)/2, w:W-48, h};
  // 后片比照片矮：照片要高出后片一截；卡片只伸进前片一点（玻璃里透的要是光晕，垫着深色纸会发灰）
  return {back, shell:{x:back.x, y:back.y+h*.22, w:back.w, h:h*.78}, frontH:h*.66, eTop, card:{w:Math.min(W*.27,108), h:h*.6}};
}
// 文件夹后片：左上角一个胖标签，和身子接的地方是弧的（坐标含标签高）
function bdBackPath(w, h){ const c=22, th=BK.tabFolder, tw=Math.min(120,w*.4);
  return `M0 ${h-c}L0 14Q0 0 14 0L${tw-10} 0C${tw+4} 0 ${tw+4} ${th} ${tw+18} ${th}L${w-c} ${th}Q${w} ${th} ${w} ${th+c}L${w} ${h-c}Q${w} ${h} ${w-c} ${h}L${c} ${h}Q0 ${h} 0 ${h-c}Z`; }

// 海报底色：缩到 28×28，按色相分 14 桶、鲜艳的权重大，取最重那桶压成能托住浅色字的深色。不求平均——平均出来一张一个灰
const bdTones={};
function hsv2hex(h,s,v){ const f=n=>{ const k=(n+h*6)%6; return v-v*s*Math.max(0,Math.min(k,4-k,1)); }; return "#"+[f(5),f(3),f(1)].map(x=>Math.round(x*255).toString(16).padStart(2,"0")).join(""); }
function bdTone(pid, img){
  if(bdTones[pid]) return bdTones[pid];
  try{ const n=28, c=document.createElement("canvas"); c.width=c.height=n; const x=c.getContext("2d",{willReadFrequently:true}); x.drawImage(img,0,0,n,n);
    const d=x.getImageData(0,0,n,n).data, bins=14, Wt=Array(bins).fill(0), Ss=Array(bins).fill(0), HX=Array(bins).fill(0), HY=Array(bins).fill(0);
    for(let i=0;i<n*n;i++){ const r=d[i*4]/255, g=d[i*4+1]/255, b=d[i*4+2]/255, mx=Math.max(r,g,b), dd=mx-Math.min(r,g,b), s=mx?dd/mx:0;
      if(!(s>.14&&mx>.12)) continue;
      let h=!dd?0 : mx===r?((g-b)/dd)%6 : mx===g?(b-r)/dd+2 : (r-g)/dd+4; h/=6; if(h<0) h+=1;
      const w=s*mx, k=Math.min(bins-1,Math.floor(h*bins)); Wt[k]+=w; Ss[k]+=s*w; HX[k]+=Math.cos(h*2*Math.PI)*w; HY[k]+=Math.sin(h*2*Math.PI)*w; }
    let top=0; Wt.forEach((w,i)=>{ if(w>Wt[top]) top=i; });
    if(Wt[top]<=1) return bdTones[pid]=hsv2hex(.08,.16,.27);
    let h=Math.atan2(HY[top],HX[top])/(2*Math.PI); if(h<0) h+=1;
    return bdTones[pid]=hsv2hex(h, Math.min(.62,Math.max(.3,Ss[top]/Wt[top])), .33);
  }catch(e){ return null; }
}
// 超宽黑体（Archivo 125%）量字：宽用 DOM 量，字母高度按字体度量（字号无关，量一次）
function bdMeasure(text){ let s=$("#bdmeasure"); if(!s){ s=document.createElement("span"); s.id="bdmeasure"; s.className="bx"; s.setAttribute("aria-hidden","true"); document.body.appendChild(s); }
  s.textContent=text; return s.getBoundingClientRect().width/100; }
let bdM=null;
function bdMetrics(){ if(bdM) return bdM; const c=document.createElement("canvas").getContext("2d"); c.font='900 100px "Archivo"'; const m=c.measureText("H");
  return bdM={cap:(m.actualBoundingBoxAscent||70)/100, asc:(m.fontBoundingBoxAscent||94)/100, desc:(m.fontBoundingBoxDescent||22)/100}; }
const bdFont = document.fonts ? document.fonts.load('900 100px "Archivo"').catch(()=>{}) : Promise.resolve();

const bdClock = ts => { if(!ts) return ""; const d=new Date(ts*1000); return `${String(d.getHours()).padStart(2,"0")}:${String(d.getMinutes()).padStart(2,"0")}`; };
const bdImg = (pid,w) => `api/photo/img/${pid}?w=${w}`;

// ---------- 一条纸 ----------
function bdStripHTML(l, i, ty, coverFs){
  const tone=l.kind==="note"?BK.note:BK.tones[i%BK.tones.length];
  const tab=(a,b)=>`<div class="bs-tab" style="top:${ty}px"><span><b>${a}</b>${b?`<i>${b}</i>`:""}</span></div>`;
  let inner="", extra="";
  if(l.kind==="cover"){ inner=`<div class="bs-cv"><span class="bx" style="font-size:${coverFs}px">${esc(l.title+l.range)}</span></div><div class="bs-cs"><span>${esc(l.sub)}</span></div>`; }
  else if(l.kind==="day"){ inner=`<div class="bs-dv"><span><b>DAY ${l.n}</b><i>${l.date}</i></span></div>`; }
  else if(l.kind==="photo"){ inner=`<div class="bs-ph"><img src="${bdImg(l.p.id,600)}" data-pid="${l.p.id}" alt="" decoding="async"></div>`; extra=tab(`FIG.${String(l.fig).padStart(2,"0")}`, bdClock(l.p.taken)); }
  else { inner=`<div class="bs-nc">${[...l.n.text.replace(/\s+/g,"")].slice(0,40).map(ch=>`<span>${esc(ch)}</span>`).join("")}</div>`; extra=tab("NOTE","随记"); }
  const st=l.kind==="cover"?BK.tones[0]:l.kind==="day"?[BK.night,BK.nightInk]:tone;
  return `<div class="bs ${l.kind}" data-i="${i}" data-leaf="${l.id}" style="--pp:${st[0]};--pi:${st[1]};z-index:${i+1}"><div class="bs-paper">${inner}</div>${extra}</div>`;
}

// ---------- 整页 ----------
function bdOpen(tid, opt={}){
  const t=state.ck.find(x=>x.id===tid), el=$("#trip"), S=tp[tid]||(tp[tid]={});
  const ts=tripsOf(t.city), n=ts.findIndex(x=>x.id===tid)+1, ps=photosOf(tid), ns=notesOf(tid);
  if(opt.leaf){ S.bopen=1; S.bx=0; S.leaf=null; }
  const {leaves:L, days}=bdLeaves(t);
  if(S.leaf && !BD_ENTRY[S.leaf] && !L.some(l=>l.id===S.leaf)) S.leaf=null;   // 抽出来的这张被取下了，插回去
  el.hidden=false; el.dataset.tid=tid; el.classList.add("bmode");
  const talk=cmtsOf("trip:"+tid).length, editing=S.edit||S.pick||S.dpick;
  const ico={plus:`<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M8 2.5v11M2.5 8h11" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>`,
    plane:`<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M14 2 6.6 9.4M14 2 9.4 14l-2.8-4.6L2 6.6Z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg>`,
    talk:`<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 3h10a1.5 1.5 0 0 1 1.5 1.5v5A1.5 1.5 0 0 1 13 11H7l-3.5 2.6V11H3a1.5 1.5 0 0 1-1.5-1.5v-5A1.5 1.5 0 0 1 3 3Z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg>`};
  el.innerHTML=`<div class="shin tp binder"><div class="bd ${editing?"editing":""}">
    <div class="bd-aura" aria-hidden="true"><div class="bd-glow"><i></i></div><div class="bd-col"><div></div></div></div>
    <div class="bd-back" aria-hidden="true"></div><svg class="bd-backline" aria-hidden="true"><defs><linearGradient id="bdbl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".95"/><stop offset="1" stop-color="#fff" stop-opacity=".25"/></linearGradient></defs><path fill="none" stroke="url(#bdbl)" stroke-width="1"/></svg>
    <div class="bd-rail" aria-label="这一次的竖条，左右滑，往上拖抽出一页"><div class="bd-rw"></div></div>
    <div class="bd-front" aria-hidden="true"><b class="bx"></b><span></span></div>
    <button class="bd-hit" aria-label="打开文件夹"></button>
    <div class="bd-ent">
      <div class="bd-er ${SH()?"":"solo"}"><button class="bd-e" data-ent="add" style="--ep:${BD_ENTRY.add[0]};--ei:${BD_ENTRY.add[1]}">${ico.plus}<span>加一页</span></button>
        ${SH()?`<button class="bd-e mono" data-ent="gate" style="--ep:${BD_ENTRY.gate[0]};--ei:${BD_ENTRY.gate[1]}">${ico.plane}<span>GATE</span></button>`:""}</div>
      ${SH()?`<button class="bd-e" data-ent="talk" style="--ep:${BD_ENTRY.talk[0]};--ei:${BD_ENTRY.talk[1]}">${ico.talk}<span>${esc(PT())}说${talk?` · ${talk}`:""}</span></button>`:""}
    </div>
    <div class="bd-tk">${tripPassHTML(t, n, S, "binder")}</div>
    ${editing?`<div class="bd-form">${S.edit?tripForm(t):""}${S.pick?originChips(t.city, t.origin||null):""}${S.dpick?destChips(t.city, t.dest||null):""}</div>`:""}
    <div class="bd-band" aria-hidden="true"></div>
    <button class="bd-shut"><svg viewBox="0 0 12 12" aria-hidden="true"><path d="m2.5 7.5 3.5-3.5 3.5 3.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>合上</button>
  </div></div>`;
  const stage=el.querySelector(".bd"), rail=stage.querySelector(".bd-rail");
  const W=stage.clientWidth, H=stage.clientHeight, ins=bdInsets(), tk=stage.querySelector(".bd-tk");
  const ticketH=tk.offsetHeight, lay=bdLayout(W,H,ins,ticketH), openH=H-ins.top-BK.topGap;
  const ws=bdWidths(L,W), xs=[]; ws.reduce((x,w)=>(xs.push(x),x+w),0);
  const seq=bdTabSeq(L), total=xs.length?xs[xs.length-1]+ws[ws.length-1]:0;
  const fan=[...L.filter(l=>l.kind==="photo"), ...L.filter(l=>l.kind==="note")].slice(0,5).map(l=>l.id);
  const ctx={el, t, S, L, days, ws, xs, seq, W, H, ins, lay, openH, fan, stage, rail, tid, total, active:null};
  el._bd=ctx;
  stage.style.setProperty("--tkUp", `${-(ticketH-10-ins.top)}px`);
  stage.style.setProperty("--sat", ins.top+"px"); stage.style.setProperty("--sab", ins.bottom+"px");
  // 文件夹几块的位置
  const {back, shell, frontH, card}=lay, bh=shell.h+BK.tabFolder, path=bdBackPath(shell.w, bh);
  const place=(q,x,y,w,h)=>{ const e=stage.querySelector(q); Object.assign(e.style,{left:x+"px",top:y+"px",width:w+"px",height:h+"px"}); return e; };
  const aura=place(".bd-aura", shell.x, shell.y-BK.tabFolder, shell.w, bh);
  aura.querySelectorAll(".bd-glow i,.bd-col").forEach(e=>e.style.clipPath=`path("${path}")`);
  aura.querySelector(".bd-col div").innerHTML=ps.length?L.filter(l=>l.kind==="photo").slice(0,4).map(l=>`<img src="${bdImg(l.p.id,600)}" alt="">`).join(""):"";
  place(".bd-back", shell.x, shell.y-BK.tabFolder, shell.w, bh).style.clipPath=`path("${path}")`;
  const bl=place(".bd-backline", shell.x, shell.y-BK.tabFolder, shell.w, bh); bl.setAttribute("viewBox",`0 0 ${shell.w} ${bh}`); bl.querySelector("path").setAttribute("d",path);
  const front=place(".bd-front", back.x, back.y+back.h-frontH, back.w, frontH);
  const en=(byId[t.city]?.en||"").toUpperCase(), fw=bdMeasure(en)*34;
  front.querySelector("b").textContent=en; front.querySelector("b").style.fontSize=Math.max(17,Math.min(34,34*(back.w-40)/Math.max(1,fw)))+"px";
  const nd=L.filter(l=>l.kind==="day").length;
  front.querySelector("span").textContent=[ps.length?`${ps.length} 张`:"", ns.length?`${ns.length} 段`:"", nd>1?`${nd} 天`:""].filter(Boolean).join(" · ")||"还是空的";
  place(".bd-hit", back.x, back.y-4, back.w, back.h+4);
  stage.querySelector(".bd-ent").style.top=lay.eTop+"px";
  stage.querySelector(".bd-band").style.height=Math.max(0,ins.top-6)+"px";
  // 竖条
  const coverLen=Math.max(10,openH-150-16), cfw=bdMeasure(en+(L[0].range||""))*40;
  const coverFs=Math.max(18,Math.min(40,40*coverLen/Math.max(1,cfw)));
  rail.querySelector(".bd-rw").style.width=total+"px";
  rail.insertAdjacentHTML("beforeend", L.map((l,i)=>bdStripHTML(l,i,bdTabY(seq[i],openH),coverFs)).join(""));
  ctx.strips=[...rail.querySelectorAll(".bs")];
  ctx.strips.forEach((s,i)=>{ s.style.left=xs[i]+"px"; s.style.top=(ins.top+BK.topGap)+"px"; });
  rail.querySelectorAll(".bs-ph img").forEach(img=>{ const f=()=>bdTone(+img.dataset.pid, img); img.complete&&img.naturalWidth?f():img.addEventListener("load",f,{once:true}); });
  // 照片少、竖条宽的时候 600 会糊，换大图
  ctx.strips.forEach((s,i)=>{ if(ws[i]>110) s.querySelector(".bs-ph img")?.setAttribute("src", bdImg(L[i].p.id,1600)); });
  bdPose(ctx, !!S.bopen, {instant:true});
  if(S.bopen){ stage.classList.add("open","real","instant"); rail.scrollLeft=S.bx||0; requestAnimationFrame(()=>stage.classList.remove("instant")); }
  bdWire(ctx);
  if(S.leaf) bdSheet(ctx, S.leaf, {settled:true});
  else if(opt.leaf) setTimeout(()=>bdFocus(ctx, opt.leaf), 350);
}

// 合上 = 扇形卡片，打开 = 竖条。s = 合上那一刻滑到的位置（从那儿收回去）
function bdPose(ctx, open, {instant=false, s=0}={}){
  const {L, ws, xs, W, ins, lay, openH, fan, strips}=ctx, {card, back}=lay;
  const vis=i=>fan.includes(L[i].id) || (xs[i]-s<W && xs[i]+ws[i]-s>-BK.tabW);
  const items=L.map((_,i)=>i).filter(vis), spread=Math.min(38,(back.w-card.w)/Math.max(1,fan.length-1));
  strips.forEach((el,i)=>{
    const rank=items.indexOf(i), slot=fan.indexOf(L[i].id), o=slot<0?0:slot-(fan.length-1)/2;
    el.style.transition=instant||rank<0?"none":"";
    el.style.transitionDelay=rank<0?"0s":(open ? .05+rank*.02 : (items.length-1-rank)*.014)+"s";
    if(open){ Object.assign(el.style,{width:ws[i]+"px", height:openH+"px", transform:"none", opacity:1}); el.classList.remove("fan"); }
    else { const x=W/2+o*spread-card.w/2, y=back.y-4+Math.abs(o)*9;
      Object.assign(el.style,{width:card.w+"px", height:card.h+"px", transform:`translate(${x-xs[i]+s}px,${y-(ins.top+BK.topGap)}px) rotate(${o*5.5}deg)`, opacity:slot<0?0:1});
      el.classList.add("fan"); }
  });
  if(instant) void ctx.rail.offsetWidth;
}

function bdTapFolder(ctx){
  const {S, stage, rail, t}=ctx;
  if(ctx.active||S.bopen) return;
  if(!photosOf(t.id).length && !notesOf(t.id).length){ const f=stage.querySelector(".bd-front"); return bdSheet(ctx,"add",{from:bdRect(ctx,f)}); }
  S.bopen=1; S.bx=0; rail.scrollLeft=0; stage.classList.add("open");
  bdPose(ctx, true);
  const tok=ctx.tok=(ctx.tok||0)+1;
  // 最后一张落定才放开滑动
  setTimeout(()=>{ if(tok===ctx.tok && S.bopen) stage.classList.add("real"); }, 760);
}
function bdCloseFolder(ctx){
  const {S, stage, rail}=ctx;
  if(!S.bopen||ctx.active) return;
  const s=rail.scrollLeft; S.bopen=0; ctx.tok=(ctx.tok||0)+1; const tok=ctx.tok;
  stage.classList.remove("real","open");
  bdPose(ctx, false, {s});
  setTimeout(()=>{ if(tok!==ctx.tok) return; rail.scrollLeft=0; bdPose(ctx, false, {instant:true}); }, 700);
}
function bdRect(ctx, el){ const a=ctx.stage.getBoundingClientRect(), b=el.getBoundingClientRect(); return {x:b.left-a.left, y:b.top-a.top, w:b.width, h:b.height}; }

// ---------- 手势：竖条上往上拖 = 抽页；左右滑留给滚动 ----------
function bdWire(ctx){
  const {el, S, stage, rail, t}=ctx;
  stage.querySelector(".bd-hit").onclick=()=>bdTapFolder(ctx);
  stage.querySelector(".bd-shut").onclick=()=>bdCloseFolder(ctx);
  stage.querySelectorAll("[data-ent]").forEach(b=>b.onclick=()=>{ if(!ctx.active) bdSheet(ctx, b.dataset.ent, {from:bdRect(ctx,b)}); });
  rail.addEventListener("scroll",()=>{ S.bx=rail.scrollLeft; },{passive:true});
  // 外面几层都是 overflow:hidden，但聚焦输入框时浏览器照样会把它们滚上去（键盘会把整页顶起来，底下露出纸）
  [stage, stage.parentElement].forEach(x=>x.addEventListener("scroll",()=>{ if(x.scrollTop||x.scrollLeft){ x.scrollTop=0; x.scrollLeft=0; } }));
  // 外层的「往下拖关掉整页」别抢竖条和抽出来那页的手势
  ["touchstart"].forEach(ev=>{ rail.addEventListener(ev,e=>e.stopPropagation(),{passive:true}); });
  let g=null;
  rail.addEventListener("pointerdown",e=>{ if(!S.bopen||ctx.active||e.button>0) return; const s=e.target.closest(".bs"); if(!s) return;
    g={i:+s.dataset.i, x:e.clientX, y:e.clientY, t:e.timeStamp, ly:e.clientY, lt:e.timeStamp, vy:0, pull:false, moved:false, id:e.pointerId}; });
  rail.addEventListener("pointermove",e=>{ if(!g||e.pointerId!==g.id) return; const dx=e.clientX-g.x, dy=e.clientY-g.y;
    if(Math.abs(dx)>8||Math.abs(dy)>8) g.moved=true;
    if(!g.pull){
      if(!g.moved) return;
      if(dy<0 && Math.abs(dy)>Math.abs(dx)*1.15 && bdTab(ctx.L[g.i])){ g.pull=true; try{ rail.setPointerCapture(e.pointerId); }catch(_){}
        bdSheet(ctx, ctx.L[g.i].id, {from:bdRect(ctx, ctx.strips[g.i]), pulling:true, i:g.i}); }
      else { g=null; return; }
    }
    // 越往上越沉：纸从夹子里往外蹭的阻力
    const up=Math.max(0,-dy), py=up<BK.pull?up:BK.pull+(up-BK.pull)*.55;
    const dt=e.timeStamp-g.lt; if(dt>0){ g.vy=(e.clientY-g.ly)/dt; g.ly=e.clientY; g.lt=e.timeStamp; }
    if(ctx.active) ctx.active.sh.style.transform=`translateY(${-py}px)`;
    g.py=py; });
  const end=e=>{ if(!g||e.pointerId!==g.id) return; const G=g; g=null;
    if(G.pull){ if(G.py>BK.pull||G.vy<-.9) bdGrow(ctx); else bdShrink(ctx); return; }
    if(!G.moved && e.type==="pointerup" && bdTab(ctx.L[G.i])) bdSheet(ctx, ctx.L[G.i].id, {from:bdRect(ctx, ctx.strips[G.i]), i:G.i}); };
  rail.addEventListener("pointerup",end); rail.addEventListener("pointercancel",end);
  // 票上的按钮：改日期 / 出发地 / 终点 / 网格
  wireTripPass(el, t, ctx.S);
  if(!bdOpen._esc){ bdOpen._esc=1;
    addEventListener("keydown",e=>{ const c=$("#trip")._bd; if(e.key!=="Escape"||$("#trip").hidden||!c||!$("#lb").hidden||!$("#sheet").hidden) return;
      if(c.active){ e.stopImmediatePropagation(); bdShrink(c); } else if(c.S.bopen){ e.stopImmediatePropagation(); bdCloseFolder(c); } },true);
    addEventListener("resize",()=>{ const c=$("#trip")._bd; if(!$("#trip").hidden&&c&&$("#trip").classList.contains("bmode")&&!bdTyping()) bdOpen(c.tid); }); }
}

// 从往来跳来的：先把文件夹打开（不动画），再从竖条上抽出那一页，和手动抽走同一条路
function bdFocus(ctx, id){
  const i=ctx.L.findIndex(l=>l.id===id); if(i<0||ctx.active) return;
  const r=bdRect(ctx, ctx.strips[i]);
  // 滑到屏幕外的那条：从屏幕边上长出来，别从看不见的地方飞进来
  if(r.x>ctx.W-r.w) r.x=ctx.W-r.w;
  bdSheet(ctx, id, {from:r, i});
}

// ---------- 抽出来的那页 ----------
function bdImgH(ctx, p){ const img=ctx.rail.querySelector(`.bs-ph img[data-pid="${p.id}"]`);
  const iw=p.w||img?.naturalWidth, ih=p.h||img?.naturalHeight;
  return iw&&ih ? Math.min(ctx.W*ih/iw, ctx.H*.68) : ctx.H*.55; }

// 键盘：iOS 不缩布局视口只缩可视视口，还会把整层往上推。打字时让 #trip 贴住可视视口（顶 = offsetTop，高 = 键盘上面那截），
// 内页自己滚到输入框，外面几层不许动
const bdTyping = () => { const a=document.activeElement; return !!a && $("#trip").contains(a) && /^(INPUT|TEXTAREA)$/.test(a.tagName); };
function bdKb(){ const el=$("#trip"), vv=window.visualViewport;
  if(vv && !el.hidden && el.classList.contains("bmode") && bdTyping()){ el.style.top=vv.offsetTop+"px"; el.style.height=vv.height+"px"; el.style.bottom="auto"; }
  else { el.style.top=el.style.height=el.style.bottom=""; }
  el.querySelectorAll(".shin.binder,.bd,.bd-sh").forEach(x=>{ x.scrollTop=0; x.scrollLeft=0; }); }
if(window.visualViewport){ visualViewport.addEventListener("resize",bdKb); visualViewport.addEventListener("scroll",bdKb); }
document.addEventListener("focusin",()=>setTimeout(bdKb,0)); document.addEventListener("focusout",()=>setTimeout(bdKb,60));
// 只滚内页，把输入框挪到可见区域的下沿上面一点
function bdReveal(sc, el){ const a=sc.getBoundingClientRect(), b=el.getBoundingClientRect(), d=b.bottom-(a.bottom-16);
  if(d>0) sc.scrollTo({top:sc.scrollTop+d, behavior:"smooth"}); else if(b.top<a.top+60) sc.scrollTo({top:sc.scrollTop+b.top-a.top-60, behavior:"smooth"}); }

function bdSheet(ctx, id, {from, pulling=false, settled=false, i}={}){
  const {S, stage, W, H}=ctx;
  const leaf=BD_ENTRY[id]?{id, kind:id}:ctx.L.find(l=>l.id===id); if(!leaf) return;
  const idx=i??ctx.L.indexOf(leaf);
  const tone=leaf.kind==="note"?BK.note : BD_ENTRY[id] ? BD_ENTRY[id] : BK.tones[idx%BK.tones.length];
  const src=from || bdSrc(ctx, leaf);
  const sh=document.createElement("div"); sh.className="bd-sh"; stage.appendChild(sh);
  sh.addEventListener("touchstart",e=>e.stopPropagation(),{passive:true});
  ctx.active={leaf, src, tone, sh, idx, ty: idx>=0&&bdTab(leaf)?bdTabY(ctx.seq[idx],ctx.openH):0};
  bdMark(ctx, true);
  if(settled){ S.leaf=id; bdSettle(ctx, {instant:true}); return; }
  bdMorph(ctx, 0);
  if(!pulling) requestAnimationFrame(()=>requestAnimationFrame(()=>bdGrow(ctx)));
}
function bdSrc(ctx, leaf){ const i=ctx.L.indexOf(leaf); if(i>=0) return bdRect(ctx, ctx.strips[i]);
  const b=ctx.stage.querySelector(`[data-ent="${leaf.id}"]`); return b?bdRect(ctx,b):{x:0,y:ctx.H,w:ctx.W,h:60}; }
function bdMark(ctx, on){ const a=ctx.active; if(!a) return; const i=ctx.L.indexOf(a.leaf);
  if(i>=0) ctx.strips[i].classList.toggle("act",on); ctx.stage.querySelector(`[data-ent="${a.leaf.id}"]`)?.classList.toggle("act",on); }

// k=0 还是窄条，k=1 铺满（抽的过程：窄条跟手往上走，松手后长成整页）
function bdMorph(ctx, k){
  const {W, H, active:a}=ctx, s=a.src, L=(x,y)=>x+(y-x)*k, sh=a.sh, leaf=a.leaf;
  const photo=leaf.kind==="photo", pid=photo&&leaf.p.id, tone=photo&&bdTones[pid];
  if(!sh._m){ sh.classList.remove("settled"); sh.innerHTML=`<div class="bm" style="--pp:${a.tone[0]}">
      <i class="bm-bg ${photo?"tone":"page"}" style="${photo?`background-color:${tone||BK.night}`:""}"></i>
      ${photo?`<div class="bm-ph"><img src="${bdImg(pid,600)}" alt=""></div>`:""}
      ${leaf.kind==="note"?`<div class="bs-nc">${[...leaf.n.text.replace(/\s+/g,"")].slice(0,40).map(ch=>`<span>${esc(ch)}</span>`).join("")}</div>`:""}
    </div>${bdTab(leaf)?`<div class="bs-tab" style="top:${a.ty}px;--pp:${a.tone[0]};--pi:${a.tone[1]}"><span><b>${photo?`FIG.${String(leaf.fig).padStart(2,"0")}`:"NOTE"}</b><i>${photo?bdClock(leaf.p.taken):"随记"}</i></span></div>`:""}`; sh._m=1; }
  Object.assign(sh.style,{left:L(s.x,0)+"px", top:L(s.y,0)+"px", width:L(s.w,W)+"px", height:L(s.h,H)+"px", borderRadius:`${9*(1-k)}px ${9*(1-k)}px 0 0`});
  sh.querySelector(".bm-bg").style.opacity=k;
  const ph=sh.querySelector(".bm-ph"); if(ph) Object.assign(ph.style,{left:L(7,0)+"px", top:L(14,0)+"px", width:L(s.w-14,W)+"px", height:L(s.h-44,bdImgH(ctx,leaf.p))+"px"});
  const nc=sh.querySelector(".bm .bs-nc"); if(nc) nc.style.opacity=1-k;
  const tb=sh.querySelector(".bs-tab"); if(tb) tb.style.opacity=Math.max(0,1-k*3);
}
function bdGrow(ctx){
  const a=ctx.active; if(!a) return; const sh=a.sh;
  sh.classList.add("anim"); sh.style.transform="";
  bdMorph(ctx, 1);
  const tok=a.tok=(a.tok||0)+1;
  // 落定才换成能滚的内页；保险：回调 1.1 秒没来就直接显示
  const done=()=>{ if(ctx.active!==a||a.tok!==tok||a.settled) return; ctx.S.leaf=a.leaf.id; bdSettle(ctx); };
  sh.addEventListener("transitionend",function f(e){ if(e.target===sh&&e.propertyName==="width"){ sh.removeEventListener("transitionend",f); done(); } });
  setTimeout(done, 1100);
}
function bdShrink(ctx){
  const a=ctx.active; if(!a) return; const sh=a.sh;
  const grown=a.settled; a.settled=false; a.tok=(a.tok||0)+1; ctx.S.leaf=null; ctx.S.nedit=0; ctx.S.addNote=0;
  if(grown){ sh._m=0; sh.classList.remove("anim"); bdMorph(ctx, 1); void sh.offsetWidth; }
  sh.classList.add("anim","back"); sh.style.transform=""; bdMorph(ctx, 0);
  setTimeout(()=>{ if(ctx.active!==a) return; bdMark(ctx,false); sh.remove(); ctx.active=null; }, 460);
}

// 落定：换成能滚的内页，字淡入
function bdSettle(ctx, {instant=false}={}){
  const a=ctx.active; a.settled=true; const sh=a.sh; sh._m=0;
  Object.assign(sh.style,{left:0, top:0, width:"100%", height:"100%", borderRadius:0, transform:""});   // 百分比：键盘起来时跟着层一起变矮
  sh.classList.remove("anim","back"); sh.classList.add("settled");
  bdPage(ctx);
  if(instant) sh.querySelector(".bdp").classList.add("in");
  else requestAnimationFrame(()=>sh.querySelector(".bdp")?.classList.add("in"));
}

const bdReply={};
function bdPage(ctx){
  const a=ctx.active, {t, S, W, H, ins}=ctx, leaf=a.leaf, old=a.sh.querySelector(".bp-sc")?.scrollTop||0, wasIn=!!a.sh.querySelector(".bdp.in");
  let body="", cls="page", style="";
  const foot=poster=>`<div class="bp-foot bp-t"><button class="bp-back" data-bp="back">插回去</button>${poster||`<div class="bp-en">${esc((byId[t.city]?.en||"").toUpperCase())}</div>`}</div>`;
  if(leaf.kind==="photo"){
    const p=(state.photos||[]).find(x=>x.id===leaf.p.id)||leaf.p, tone=bdTones[p.id]||BK.night, imgH=bdImgH(ctx,p), cap=(p.caption||"").trim();
    const short=cap&&[...cap].length<=16&&!cap.includes("\n"), long=[...cap].length>90, name=(byId[t.city]?.en||"").toUpperCase();
    const M=bdMetrics(), nameW=W-28, fs=Math.min(132, nameW/Math.max(.01,bdMeasure(name))), capH=fs*M.cap, base=fs*(1+M.asc-M.desc)/2;
    const total=photosOf(t.id).length, c=byId[t.city], dayN=ctx.days.length>1&&p.taken?ctx.days.indexOf((d=>(d.setHours(0,0,0,0),+d))(new Date(p.taken*1000)))+1:0;
    const dd=p.taken?new Date(p.taken*1000):null, free=H-imgH-300, num=Math.min(280,Math.max(190,free));
    cls="poster"; style=`--tone:${tone}`;
    body=`<div class="bp-photo" style="height:${imgH}px"><img src="${bdImg(p.id,600)}" alt="${esc(cap)}"><img class="hi" src="${bdImg(p.id,1600)}" alt="" onload="this.classList.add('on')"><i class="bp-fade bp-t" style="height:${Math.min(190,imgH*.36)}px"></i></div>
      <div class="bp-name bp-t" style="height:${capH}px;margin-top:${-capH/2}px"><span class="bx" style="font-size:${fs}px;transform:translateY(${capH-base}px)">${esc(name)}</span></div>
      <div class="bp-body bp-t"><div class="bp-fig"><span>FIG. ${String(leaf.fig).padStart(2,"0")} / ${String(total).padStart(2,"0")}</span><button class="lk" data-bp="edit">${cap?"改这张":"写配文"}</button></div>
        ${short?`<p class="bp-cap short">${esc(cap)}</p>`:long?bdDrop(cap,"bp-cap"):cap?`<p class="bp-cap mid">${esc(cap)}</p>`:""}
        ${bdThreads("photo", p.id, "这张照片", true)}</div>
      ${foot(`<div class="bp-cells"><span><i>${dayN?`DAY ${dayN}`:"DATE"}</i><b>${dd?`${dd.getMonth()+1}.${dd.getDate()}`:"——"}</b></span><span><i>TIME</i><b>${bdClock(p.taken)||"——"}</b></span><span class="w"><i>WHERE</i><b>${c?`${fLat(c.lat)} ${fLng(c.lng)}`:"——"}</b></span></div>`)}
      <b class="bp-num bx" style="font-size:${num}px;bottom:${ins.bottom+40}px">${String(leaf.fig).padStart(2,"0")}</b>`;
  } else if(leaf.kind==="note"){
    const n=(state.notes||[]).find(x=>x.id===leaf.n.id)||leaf.n, d=new Date(n.created*1000);
    body=`<div class="bp-plain bp-t" style="padding-top:${ins.top+64}px"><p class="bp-kick">NOTE · ${d.getMonth()+1}.${d.getDate()} ${bdClock(n.created)}</p>
      ${S.nedit?`<form class="nf bp-nf" data-nid="${n.id}"><label class="vh-only" for="bpn">改随记</label><textarea id="bpn" name="text" rows="8" maxlength="5000">${esc(n.text)}</textarea>
          <div class="ckacts"><button class="pill solid">保存</button><button type="button" class="lk" data-bp="nx">先不改</button><button type="button" class="lk warn" data-bp="ndel">删掉这段</button></div></form>`
        : `${bdDrop(n.text,"bp-note")}<div class="bp-acts">${SH()?`<button class="lk" data-bp="nshare">递这段</button>`:""}<button class="lk" data-bp="ned">改</button></div>`}
      ${bdThreads("note", n.id, "这段随记", false)}</div>${foot()}`;
  } else {
    const kick={add:"ADD A LEAF", gate:"GATE", talk:"COMMENTS"}[leaf.kind], title={add:"再夹一页", gate:`递给${esc(PT())}`, talk:`${esc(PT())}说`}[leaf.kind];
    let inner="";
    if(leaf.kind==="add") inner=S.addNote?`<form class="nf bp-nf" data-new="1"><label class="vh-only" for="bpnew">写一段随记</label><textarea id="bpnew" name="text" rows="8" maxlength="5000" placeholder="这一趟，想记下点什么…长短都行"></textarea>
        <div class="ckacts"><button class="pill solid">记下</button><button type="button" class="lk" data-bp="addx">先不写</button></div></form>`
      : `<button class="bp-add" data-bp="note"><b>写一段</b><span>夹一张字纸</span></button><button class="bp-add" data-bp="photo"><b>加照片</b><span>从手机 / 电脑选</span></button>`;
    else if(leaf.kind==="gate") inner=gateHTML(t, S, true);
    else inner=cmtBlock("trip:"+t.id)||`<p class="hint">这张票上${esc(PT())}还没说什么。</p>`;
    body=`<div class="bp-plain bp-t" style="padding-top:${ins.top+64}px"><p class="bp-kick">${kick}</p><h3 class="bp-h">${title}</h3>${inner}</div>${foot()}`;
  }
  a.sh.innerHTML=`<div class="bdp ${cls} ${wasIn?"in":""}" style="${style}"><div class="bp-sc"><div class="bp-in" style="min-height:${H}px">${body}</div></div><button class="bp-x" data-bp="back" aria-label="插回去">×</button></div>`;
  const sc=a.sh.querySelector(".bp-sc"); sc.scrollTop=old;
  bdWirePage(ctx, sc);
}

// 长段：首字放大，字绕着走
function bdDrop(text, cls){ const s=[...String(text||"").trim()]; if(!s.length) return "";
  const ps=s.slice(1).join("").split(/\n+/).filter(Boolean);
  return `<div class="bp-drop ${cls}"><span class="dc">${esc(s[0])}</span>${ps.map((p,i)=>`<p>${esc(p)}</p>`).join("")||"<p></p>"}</div>`; }

// 这张照片 / 这段随记的对话：每次递它出去单独一组，直接在它下面说的另成一组。一条都没有就不画；features.share=false 不画
function bdThreads(type, id, label, poster){
  if(!SH()) return "";
  const cm=state.cmts||[], byC=Object.fromEntries(cm.map(c=>[c.id,c]));
  const shares=(state.shares||[]).filter(s=>s.items.some(it=>it.type===type&&it.id===id)).sort((a,b)=>b.created-a.created);
  const loose=cm.filter(c=>c.target===`${type}:${id}`).sort((a,b)=>a.created-b.created);
  const line=(who,text,m)=>`<div class="bt-l ${who==="partner"?"pt":"me"}"><p><b>${esc(NAME(who))}</b>${m?.reply_to&&byC[m.reply_to]?`<span class="rp">回复 ${esc(NAME(byC[m.reply_to].who))}</span>`:""}${esc(text)}</p>
    ${m?`<div class="bt-m"><span>${ago(m.created)}</span>${m.who!=="me"?`<button class="lk" data-btr="${m.id}">回复</button>`:`<button class="lk" data-btd="${m.id}">删</button>`}</div>`:""}</div>`;
  const group=(key, s, msgs)=>{ const R=bdReply[key]&&byC[bdReply[key]], me=s&&s.who!=="partner";
    return `<div class="bt ${poster?"on-poster":""}" data-k="${key}">${s?`<div class="bt-h"><span class="tg-k">${me?`你递给${esc(PT())}`:`${esc(PT())}递给你`}</span><b>${esc(s.items.length>1?`${s.items.length} 样`:label)}</b><span class="tg-t">${ago(s.created)}${me&&s.status==="pending"?" · 待送达":""}</span></div>${s.note?line(s.who,s.note):""}`
        : `<div class="bt-h"><span class="tg-k">在这下面说的</span></div>`}
      ${msgs.map(m=>line(m.who,m.text,m)).join("")}
      <form class="bt-f" data-k="${key}">${R?`<span class="cmr">回复 ${esc(NAME(R.who))}：「${esc(R.text.slice(0,20))}${R.text.length>20?"…":""}」<button type="button" class="lk" data-btx="${key}">不回了</button></span>`:""}
        <label class="vh-only">回复这一组</label><input name="text" maxlength="2000" placeholder="${R?`回复 ${esc(NAME(R.who))}…`:s?"回复这次…":"接着说…"}" autocomplete="off" enterkeyhint="send"><button class="bt-go">发</button></form></div>`; };
  const gs=[...shares.map(s=>group("share:"+s.id, s, cm.filter(c=>c.target==="share:"+s.id).sort((a,b)=>a.created-b.created))), ...(loose.length?[group(`${type}:${id}`, null, loose)]:[])];
  return gs.length?`<div class="bts">${gs.join("")}</div>`:"";
}

function bdWirePage(ctx, sc){
  const a=ctx.active, {t, S}=ctx, root=a.sh, leaf=a.leaf, refresh=async()=>{ await loadState(); if(ctx.active===a) bdPage(ctx); };
  // 页顶再往下拉 = 插回去
  let y0=null; sc.addEventListener("touchstart",e=>{ y0=sc.scrollTop<=0?e.touches[0].clientY:null; },{passive:true});
  sc.addEventListener("touchmove",e=>{ if(y0!==null && e.touches[0].clientY-y0>90 && sc.scrollTop<=0){ y0=null; bdShrink(ctx); } },{passive:true});
  sc.addEventListener("scroll",()=>{ if(sc.scrollTop<-90) bdShrink(ctx); },{passive:true});
  root.querySelectorAll("[data-bp]").forEach(b=>b.onclick=async()=>{ const k=b.dataset.bp;
    if(k==="back") bdShrink(ctx);
    else if(k==="edit") openPh(leaf.p.id);
    else if(k==="ned"){ S.nedit=1; bdPage(ctx); setTimeout(()=>root.querySelector("#bpn")?.focus(),50); }
    else if(k==="nx"){ S.nedit=0; bdPage(ctx); }
    else if(k==="ndel"){ if(!b._c){ b._c=1; b.textContent="确认删？"; return; }
      try{ await api("DELETE","note/"+leaf.n.id); await loadState(); S.nedit=0; S.leaf=null; rerender(); bdOpen(t.id); toast("删掉了"); }catch(e){ toast("没删成："+e.message); } }
    else if(k==="nshare"){ b.disabled=true; try{ await api("POST","share",{items:[{type:"note",id:leaf.n.id}], note:""}); toast(`这段递出了，${SOON()}`); await refresh(); }catch(e){ toast("没递出去："+e.message); b.disabled=false; } }
    else if(k==="note"){ S.addNote=1; bdPage(ctx); setTimeout(()=>root.querySelector("#bpnew")?.focus(),50); }
    else if(k==="addx"){ S.addNote=0; bdPage(ctx); }
    else if(k==="photo"){ bdShrink(ctx); setTimeout(()=>openAddPhoto(t.id), 300); }
  });
  root.querySelectorAll("form.bp-nf").forEach(f=>f.onsubmit=async e=>{ e.preventDefault(); const text=f.text.value.trim(); if(!text) return toast("还没写呢");
    try{ if(f.dataset.new) await api("POST",`trip/${t.id}/note`,{text}); else await api("PUT","note/"+f.dataset.nid,{text});
      await loadState(); S.addNote=0; S.nedit=0; rerender(); toast("记下了 ✓"); if(f.dataset.new){ S.leaf=null; bdOpen(t.id); } else bdPage(ctx); }catch(err){ toast("没存上："+err.message); } });
  // 对话
  root.querySelectorAll("[data-btr]").forEach(b=>b.onclick=()=>{ const k=b.closest(".bt").dataset.k; bdReply[k]=+b.dataset.btr; bdPage(ctx); setTimeout(()=>root.querySelector(`form.bt-f[data-k="${k}"] input`)?.focus(),50); });
  root.querySelectorAll("[data-btx]").forEach(b=>b.onclick=()=>{ delete bdReply[b.dataset.btx]; bdPage(ctx); });
  root.querySelectorAll("[data-btd]").forEach(b=>b.onclick=async()=>{ if(!b._c){ b._c=1; b.textContent="确认删？"; return; }
    try{ await api("DELETE","comment/"+b.dataset.btd); await refresh(); }catch(e){ toast("没删成："+e.message); } });
  root.querySelectorAll("form.bt-f").forEach(f=>{ f.onsubmit=async e=>{ e.preventDefault(); const text=f.text.value.trim(); if(!text) return; const k=f.dataset.k;
      // 递送组一律挂 share:<id>；平时组回某条就挂那条的 target
      const r=bdReply[k]&&(state.cmts||[]).find(c=>c.id===bdReply[k]), target=k.startsWith("share:")?k:(r?.target||k);
      f.querySelector(".bt-go").disabled=true;
      try{ await api("POST","comment",{target, text, reply_to:bdReply[k]||null}); delete bdReply[k]; await refresh(); toast(`回好了，${PT()}那边会收到`); }
      catch(err){ toast("没发出去："+err.message); f.querySelector(".bt-go").disabled=false; } };
    f.querySelector("input").addEventListener("focus",()=>setTimeout(()=>bdReveal(sc, f),350)); });
  root.querySelectorAll("textarea").forEach(x=>x.addEventListener("focus",()=>setTimeout(()=>bdReveal(sc, x),350)));
  // 票的评论 / GATE 页
  if(leaf.kind==="talk") wireCmts(root, ()=>{ if(ctx.active===a) bdPage(ctx); });
  if(leaf.kind==="gate") wireGate(root, t, S, ()=>{ if(ctx.active===a) bdPage(ctx); });
}

// 手机上活页夹整屏盖住地球：地球先停画，开合和抽页的动画才跟得上；关掉或换回网格再接着转
new MutationObserver(()=>{ const el=$("#trip"), cover=!el.hidden && el.classList.contains("bmode") && !wide();
  if(!world) return; if(cover && !bdOpen._paused){ world.pauseAnimation?.(); bdOpen._paused=1; } else if(!cover && bdOpen._paused){ world.resumeAnimation?.(); bdOpen._paused=0; } })
  .observe($("#trip"), {attributes:true, attributeFilter:["hidden","class"]});
