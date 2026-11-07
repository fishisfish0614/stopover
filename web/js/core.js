async function getJSON(url){
  const r = await fetch(url);
  if(!r.ok) throw new Error(r.status);
  return r.json();
}
let TAGS = ["美食","风景","名胜","艺术品","个人照片"];   // 照片标签，以 /api/config 下发的为准
// 网页的使用者就是 me；partner（同行的人，常常是 AI 伴侣）带钥匙走 /mcp 或 cli/stopover.py，这里显示它的星星、留言和递来的东西
let state = {ck:[], wish:[], photos:[], notes:[], cmts:[], shares:[], cfg:{me:"我", partner:"TA", default_origin:{}, domestic_countries:[], clocks:[], features:{}}};
const NAME = by => (by==="partner" ? state.cfg.partner : state.cfg.me) || by;
const SH = () => !!state.cfg.features?.share;          // 递送 / 对话 / 收件箱 / 通知：配置 features.share=false 时一概不出现
const PT = () => NAME("partner");
const PLANE='<svg aria-hidden="true" viewBox="0 0 24 24" class="plane"><path d="M21 3 3 10.5l7 2.5 2.5 7L21 3Z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="m10 13 4-4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>';
async function api(method, path, body){
  const r = await fetch("api/"+path, {method, headers:body?{"Content-Type":"application/json"}:{}, body:body?JSON.stringify(body):undefined});
  if(!r.ok){ let m=r.status; try{ m=(await r.json()).detail||m }catch(e){} throw new Error(m); }
  return r.json();
}
async function loadState(){
  const d=await getJSON("api/state");
  state.ck=d.checkins||[];
  state.wish=(d.wishes||[]).map(w=>({id:w.city,by:w.by,note:w.note||"",created:w.created||0}));
  state.photos=d.photos||[]; state.notes=d.notes||[]; state.cmts=d.comments||[]; state.shares=d.shares||[];
  if(d.config){ state.cfg={...state.cfg, ...d.config}; if(d.config.tags?.length) TAGS=d.config.tags; applyNames(); }
  if(world) updateSun();
}
const CITIES = [];            // {id,name,en,country,lat,lng,has}，启动时从 data/cities.json 填
const byId = {};
const home = () => state.cfg.home || {};
let IDX = {}, DATA = {};   // IDX=有资料城市的索引（bbox/档位）；DATA=已加载的城市页（点开时按需取）

const $ = s=>document.querySelector(s);
const esc = s=>String(s??"").replace(/[&<>"]/g,m=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[m]));
const R = Math.PI/180;
const km=(a,b)=>{const d=Math.sin((b.lat-a.lat)*R/2)**2+Math.cos(a.lat*R)*Math.cos(b.lat*R)*Math.sin((b.lng-a.lng)*R/2)**2;return Math.round(12742*Math.asin(Math.sqrt(d)))};
const fLat=v=>Math.abs(v).toFixed(2)+"°"+(v>=0?"N":"S"), fLng=v=>Math.abs(v).toFixed(2)+"°"+(v>=0?"E":"W");
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
const wide = ()=>innerWidth>=900;

// 想去：谁点的星（me / partner），两人都点了 = both
function wishKind(id){ const by=new Set(state.wish.filter(w=>w.id===id).map(w=>w.by)); return by.size>1?"both":[...by][0]; }
const ckOf = id => state.ck.find(x=>x.city===id);
const tripsOf = id => state.ck.filter(x=>x.city===id);   // 一座城可以来很多次：每次一条，各自的出发地
// 默认出发地：domestic_countries 里的国家用 domestic，其余用 abroad
const defOriginOf = id => { const o=state.cfg.default_origin||{}; return (state.cfg.domestic_countries||[]).includes(byId[id]?.country) ? o.domestic : o.abroad; };
// 图例和标题里的名字跟着配置走
function applyNames(){
  const me=state.cfg.me||"我", pt=state.cfg.partner||"TA";
  const a=$("#lg-me"), b=$("#lg-pt"); if(a) a.textContent=me+"想去"; if(b) b.textContent=pt+"想去";
}
function legs(){
  // 红线不按时间，按「从哪儿出发」连：每次打卡从它的出发地连过来（没有出发地 = 它自己就是起点）
  const out=[], seen=new Set();
  // 终点：这一次从这座城回到哪儿，多画一段 城→终点
  for(const x of state.ck){ const a=byId[x.city], b=byId[x.dest]; if(!a||!b||seen.has(x.city+">"+x.dest)) continue; seen.add(x.city+">"+x.dest);
    out.push({startLat:a.lat,startLng:a.lng,endLat:b.lat,endLng:b.lng,km:km(a,b),city:x.dest,origin:x.city,back:1}); }
  for(const x of state.ck){ const a=byId[x.origin], b=byId[x.city]; if(!a||!b||seen.has(x.origin+">"+x.city)) continue; seen.add(x.origin+">"+x.city);
    out.push({startLat:a.lat,startLng:a.lng,endLat:b.lat,endLng:b.lng,km:km(a,b),city:x.city,origin:x.origin}); }
  return {out};
}
// 侧栏顺序：从起点往下一串一串排（A → B → C），同一出发地按打卡先后
function ckTree(){
  const have=new Set(state.ck.map(x=>x.city)), kids={}, roots=[];
  for(const x of state.ck){ if(!byId[x.city]) continue; (x.origin&&have.has(x.origin)) ? (kids[x.origin]=kids[x.origin]||[]).push(x) : roots.push(x); }
  const out=[], done=new Set(), opened=new Set(), walk=(x,d)=>{ if(done.has(x.id)) return; done.add(x.id); out.push({...x,d});
    if(opened.has(x.city)) return; opened.add(x.city); (kids[x.city]||[]).forEach(k=>walk(k,d+1)); };
  roots.forEach(r=>walk(r,0)); state.ck.forEach(x=>byId[x.city]&&walk(x,0));
  return out;
}
function renderSide(){
  const {out}=legs(), cities=new Set(state.ck.map(x=>x.city)), v=ckTree();
  $("#stat").textContent=`已经停 ${cities.size} 城 · 想去 ${state.wish.filter(w=>!cities.has(w.id)).length} 城`;
  $("#total").textContent=out.reduce((s,l)=>s+l.km,0).toLocaleString("zh-CN")+" KM";
  $("#log").innerHTML=v.map((x,i)=>`<li tabindex="0" data-id="${x.city}" data-k="${x.id}"><span class="n">${String(i+1).padStart(2,"0")}</span><span style="padding-left:${Math.min(x.d,4)*10}px">${x.d?"↳ ":""}${esc(byId[x.city].name)}</span><span class="d">${byId[x.origin]?"从 "+esc(byId[x.origin].name):"起点"}${byId[x.dest]?" · 回 "+esc(byId[x.dest].name):""}</span></li>`).join("");
  $("#log").querySelectorAll("li").forEach(li=>{li.onclick=()=>openCity(li.dataset.id);li.onkeydown=e=>{if(e.key==="Enter")openCity(li.dataset.id)}});
  // 往来：两个人递过的都在；partner 递来、没点开过的算未读（红点）
  const n=(state.shares||[]).filter(x=>x.who==="partner"&&!x.read_at).length;
  $("#chatbtn").hidden=!SH()||(!(state.shares||[]).length && !state.wish.some(w=>w.by==="partner")); $("#chatN").textContent=n||""; $("#chatN").hidden=!n;
  $("#chatbtn").setAttribute("aria-label", `往来${n?`，${PT()}递来的 ${n} 样没看`:""}`);
  renderBell();
}

// 去过：一颗红圆点（淡光晕），选中时外圈泛一圈涟漪；拉远时整体缩小（--pz）
const PIN=`<svg viewBox="-10 -10 20 20"><circle class="hl" r="4" fill="none" stroke="var(--pin)" stroke-width="1.1"/><circle class="hl h2" r="4" fill="none" stroke="var(--pin)" stroke-width="1.1"/><g class="dot"><circle r="4" fill="url(#gPin)" opacity=".55"/><circle class="core" r="1.9" fill="var(--pin)"/></g></svg>`;
// 想去：四角星 + 呼吸光晕，每颗星闪的节奏错开
const SP="M0-9C.8-1.5 1.5-.8 9 0 1.5.8.8 1.5 0 9-.8 1.5-1.5.8-9 0-1.5-.8-.8-1.5 0-9Z";
const starSvg=(col,glow)=>`<svg viewBox="-16 -16 32 32"><circle class="gl" r="15" fill="url(#${glow})"/><g class="sp"><path d="${SP}" fill="var(${col})"/><circle r="1.3" fill="#fff"/></g></svg>`;
const STAR_ME=starSvg("--star","gStar"), STAR_PT=starSvg("--star2","gStar2");
// 双星：一金一蓝挨着，交错着闪
const STAR_BOTH=`<svg viewBox="-20 -16 40 32"><g transform="translate(-6,2)"><circle class="gl" r="12" fill="url(#gStar)"/><g class="sp"><path d="${SP}" fill="var(--star)" transform="scale(.8)"/><circle r="1.1" fill="#fff"/></g></g><g transform="translate(6,-3)"><circle class="gl gl2" r="12" fill="url(#gStar2)"/><g class="sp sp2"><path d="${SP}" fill="var(--star2)" transform="scale(.8)"/><circle r="1.1" fill="#fff"/></g></g></svg>`;
// 放大到一定程度：屏幕范围内有资料的城市显示名字（名城优先，最多 40 个），点名字打开
let nameLabels=[], ptsOn=true;
function updateNames(){
  if(!world) return;
  const p=world.pointOfView(), alt=p.altitude;
  // 放大后，按地面算大小的淡点会变成大圆盘：这时收起，改由名字旁的小圆点标位置
  const wantPts = alt>=.9;
  if(wantPts!==ptsOn){ ptsOn=wantPts; world.pointsData(wantPts?CITIES.filter(c=>c.has):[]); }
  let out=[], pinShow=[];
  if(alt<.9){
    const r=Math.max(80, alt*3600);   // 屏幕大致能看到的半径（公里）
    const taken=new Set([...state.ck.map(v=>v.city),...state.wish.map(w=>w.id)]);
    const cand=CITIES.filter(c=>c.has && !taken.has(c.id) && km(p,c)<r)
      .sort((a,b)=>(IDX[a.id]?.t==="p"?0:1)-(IDX[b.id]?.t==="p"?0:1) || km(p,a)-km(p,b)).slice(0,160);
    // 避让：名气高的先放，后面的和已放的名字重叠就先不显示，放得更大时自然会露出来
    const placed=[], W=innerWidth, H=innerHeight;
    const hub=new Set(state.ck.map(x=>x.origin).filter(Boolean));
    // 来过的城先占位、名字常显；出发地优先，互相重叠的先让给离中心近的
    for(const x of [...state.ck].map(x=>byId[x.city]).filter(x=>x&&km(p,x)<r).sort((a,b)=>(hub.has(b.id)-hub.has(a.id))||km(p,a)-km(p,b))){
      const sc=world.getScreenCoords(x.lat,x.lng,0); if(!sc||sc.x<0||sc.x>W||sc.y<0||sc.y>H) continue;
      const w=x.name.length*13+12, h=20, lx=sc.x+8, ly=sc.y-26;
      placed.push({x:sc.x-6,y:sc.y-6,w:12,h:12});    // 红点本身也占地方，普通城名别压上去
      if(placed.some(q=>lx<q.x+q.w && lx+w>q.x && ly<q.y+q.h && ly+h>q.y)) continue;
      placed.push({x:lx,y:ly,w,h}); pinShow.push(x.id);
    }
    for(const c of cand){
      const sc=world.getScreenCoords(c.lat,c.lng,0); if(!sc) continue;
      const w=c.name.length*13+12, h=20, x=sc.x-w/2, y=sc.y-30;
      if(sc.x<0||sc.x>W||sc.y<0||sc.y>H) continue;
      if(placed.some(q=>x<q.x+q.w && x+w>q.x && y<q.y+q.h && y+h>q.y)) continue;
      placed.push({x,y,w,h}); out.push({...c,t:"name"});
      if(out.length>=40) break;
    }
  }
  const key=out.map(c=>c.id).join()+"|"+pinShow.join();
  if(key!==nameLabels.key){ nameLabels=out; nameLabels.key=key; nameLabels.pins=new Set(pinShow); world.htmlElementsData(markers()); }
}
let _nt; const scheduleNames=()=>{ clearTimeout(_nt); _nt=setTimeout(updateNames,180); };
