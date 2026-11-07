// ---------- 往来：两个人递过的都在（全部 / 我递的 / TA 递的），partner 加的想去也折进来（只读）----------
// 点一条 = 标已读 + 打开那座城；景点弹那张景点、菜展开那道菜；照片 / 随记 / 票直接进那一次，照片和随记那页从文件夹里抽出来
function itemName(it){ const cid=cityOfItem(it), c=byId[cid]; if(!c) return "";
  if(it.type==="city") return c.name;
  if(it.type==="photo") return `${c.name}的一张照片`;
  if(it.type==="note") return `${c.name}的一段话`;
  if(it.type==="trip"){ const n=tripsOf(cid).findIndex(x=>x.id===it.id)+1; return `${c.name} · 第 ${n} 次`; }
  const arr=DATA[cid]?.[it.type==="sight"?"sights":"foods"]; return `${c.name} · ${arr?.[it.i]?.name || (it.type==="sight"?"一个景点":"一道菜")}`; }
let wl="";   // "" 全部 / "me" / "partner"
async function openChat(){
  const ch=$("#chat");
  const wishes=state.wish.filter(w=>w.by==="partner").map((w,i)=>({id:-(i+1), who:"partner", items:[{type:"city", city:w.id}], note:w.note, created:w.created, read_at:w.created, wish:1}));
  const all=[...(state.shares||[]), ...wishes].sort((a,b)=>b.created-a.created);
  const unread=(state.shares||[]).filter(x=>x.who==="partner"&&!x.read_at).length;
  if(ch.hidden && unread) wl="partner";
  await Promise.all([...new Set(all.flatMap(x=>x.items.filter(it=>it.type==="sight"||it.type==="food").map(it=>it.city)))].map(id=>IDX[id]&&DATA[id]===undefined?loadCity(id):0));
  const list=wl?all.filter(x=>x.who===wl):all;
  const kinds={city:"一座城", sight:"一个景点", food:"一道菜", trip:"一张票", photo:"一张照片", note:"一段话"};
  ch.hidden=false;
  ch.innerHTML=`<div class="shin ap inbox"><div class="aph"><b>往来</b><nav class="wlf" aria-label="谁递的">${[["","全部"],["me",`${NAME("me")}递的`],["partner",`${PT()}递的`]].map(([k,l])=>`<button class="${wl===k?"on":""}" data-wl="${k}" aria-pressed="${wl===k}">${l}${k==="partner"&&unread?`<i class="ibd" aria-label="有没看过的"></i>`:""}</button>`).join("")}</nav><button class="x" aria-label="关闭">×</button></div>
    ${list.map(x=>{ const it=x.items[0], mine=x.who!=="partner", kind=x.wish?"想和你去":(x.items.length>1?`${x.items.length} 样 · `:"")+(kinds[it?.type]||"一样东西");
      return `<button class="ib ${mine||x.read_at?"":"new"}" data-sid="${x.id}">
      <span class="tk-l">${esc(NAME(x.who))}递的 · ${kind} · ${ago(x.created)}</span>
      <b>${esc((it&&itemName(it))||kind)}</b>${x.note?`<span class="ibn">“${esc(x.note)}”</span>`:""}${mine||x.read_at?"":`<i class="ibd" aria-label="没看过"></i>`}</button>`; }).join("") || `<p class="hint">${wl==="partner"?`${esc(PT())}还没递过东西。`:"还没有往来。"}</p>`}</div>`;
  const close=()=>{ ch.hidden=true; ch.innerHTML=""; };
  ch.querySelector(".x").onclick=close; ch.onclick=e=>{ if(e.target===ch) close(); };
  ch.querySelectorAll("[data-wl]").forEach(b=>b.onclick=()=>{ wl=b.dataset.wl; openChat(); });
  ch.querySelectorAll(".ib").forEach(b=>b.onclick=async()=>{ const x=all.find(y=>y.id===+b.dataset.sid), it=x?.items[0], city=it&&cityOfItem(it);
    if(!city) return toast("这一样已经取下了");
    if(x.who==="partner" && x.id>0 && !x.read_at){ try{ await api("PUT",`share/${x.id}/read`); await loadState(); renderSide(); }catch(e){} }
    close(); if(selId) selId=null; await loadCity(city); openCity(city);
    if(it.type==="sight") setTimeout(()=>{ const el=document.querySelector(`[data-sight="${it.i}"]`); el&&sightSheet(city,it.i,el); },900);
    if(it.type==="food") setTimeout(()=>{ const u=ui[city]; if(u){ u.food[it.i]=1; rerender(); } document.querySelector(`[data-food="${it.i}"]`)?.scrollIntoView({behavior:"smooth",block:"center"}); },900);
    // 照片 / 随记 / 票：不走撕票，直接进那一次；照片和随记再从文件夹里抽出那一页（先打开，再抽）
    const tid = it.type==="trip" ? it.id : it.type==="photo" ? (state.photos||[]).find(p=>p.id===it.id)?.trip_id : it.type==="note" ? (state.notes||[]).find(n=>n.id===it.id)?.trip_id : null;
    if(tid) openTrip(tid, it.type==="trip"?{}:{leaf:(it.type==="photo"?"p":"n")+it.id}); });
}

// ---------- 通知：Web Push（sw.js 只管 push 和点开，不做离线缓存）----------
const IOS = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform==="MacIntel" && navigator.maxTouchPoints>1);
const STANDALONE = matchMedia("(display-mode: standalone)").matches || navigator.standalone===true;
const PUSH_OK = () => "serviceWorker" in navigator && "PushManager" in window && "Notification" in window && window.isSecureContext;
let pushSub=null;
async function swReg(){ try{ return await navigator.serviceWorker.register("sw.js"); }catch(e){ return null; } }
async function initPush(){
  if(!SH()||!state.cfg.features?.push_web||!PUSH_OK()) return renderBell();
  const reg=await swReg(); try{ pushSub=reg&&await reg.pushManager.getSubscription(); }catch(e){ pushSub=null; }
  renderBell();
}
function renderBell(){
  const b=$("#bellbtn"); if(!b) return;
  b.hidden=!(SH() && state.cfg.features?.push_web && (PUSH_OK() || (IOS && !STANDALONE)));
  b.classList.toggle("on", !!pushSub); b.setAttribute("aria-label", pushSub?"通知已开启":"开启通知");
}
const u8 = s => { const p="=".repeat((4-s.length%4)%4), b=atob((s+p).replace(/-/g,"+").replace(/_/g,"/")); return Uint8Array.from(b,c=>c.charCodeAt(0)); };
function openBell(){
  const sh=$("#sheet"), P=esc(PT()); sh.hidden=false;
  const need=IOS&&!STANDALONE&&!PUSH_OK();
  sh.innerHTML=`<div class="shin ap ntf"><div class="aph"><b>通知</b><button class="x" aria-label="关闭">×</button></div>
    <p class="hint">${P}留言、递东西给你、点亮星星的时候，这台设备会响一下。</p>
    ${need?`<button class="pill solid" disabled>开启通知</button><p class="hint">iPhone / iPad：先在 Safari 里点「分享 → 添加到主屏幕」，从主屏幕打开经停，再回到这里开启。</p>`
      : pushSub?`<p class="hint">✓ 这台设备已经开启了。</p><button class="pill soft warn" data-off>关掉这台设备的通知</button>`
      : `<button class="pill solid" data-on>开启通知</button>${IOS?`<p class="hint">iPhone / iPad 要从主屏幕打开才收得到。</p>`:""}`}</div>`;
  const close=()=>{ sh.hidden=true; sh.innerHTML=""; };
  sh.querySelector(".x").onclick=close; sh.onclick=e=>{ if(e.target===sh) close(); };
  sh.querySelector("[data-on]")?.addEventListener("click",async e=>{ const b=e.currentTarget; b.disabled=true;
    try{
      if(await Notification.requestPermission()!=="granted") throw new Error("没有允许通知（可以在浏览器设置里改）");
      const reg=await swReg(); if(!reg) throw new Error("service worker 没注册上"); await navigator.serviceWorker.ready;
      const k=await getJSON("api/push/vapid"); if(!k.ok) throw new Error(k.reason||"服务器没开 Web Push");
      pushSub=await reg.pushManager.subscribe({userVisibleOnly:true, applicationServerKey:u8(k.publicKey)});
      await api("POST","push/web",{subscription:pushSub.toJSON()}); renderBell(); openBell(); toast("通知开启了");
    }catch(err){ toast("没开成："+err.message); b.disabled=false; } });
  sh.querySelector("[data-off]")?.addEventListener("click",async()=>{
    try{ const ep=pushSub.endpoint; await pushSub.unsubscribe(); pushSub=null; await api("DELETE","push/web",{endpoint:ep}); }catch(e){}
    renderBell(); openBell(); toast("这台设备不再收通知"); });
}
// 点开通知 → 打开那座城（页面开着时 sw.js 发消息过来；没开时带 ?city= 打开）
if("serviceWorker" in navigator) navigator.serviceWorker.addEventListener("message",async e=>{ const d=e.data||{}; if(d.type!=="open"||!d.city) return;
  try{ await loadState(); renderSide(); refreshLayers(); }catch(err){} if(byId[d.city]){ if(selId) selId=null; await loadCity(d.city); openCity(d.city); } });

