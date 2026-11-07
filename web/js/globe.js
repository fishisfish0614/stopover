function markers(){
  const out=[...nameLabels], seen=new Set();
  for(const v of state.ck){ if(seen.has(v.city)||!byId[v.city]) continue; seen.add(v.city); out.push({...byId[v.city],t:"pin",sl:nameLabels.pins?.has(v.city)}); }
  for(const w of state.wish){ if(seen.has(w.id)||!byId[w.id]) continue; seen.add(w.id); out.push({...byId[w.id],t:"star",w:wishKind(w.id)}); }
  return out;
}

// 地图瓦片：像手机地图那样越放大越细。蓝石 = NASA Blue Marble，夜航 = NASA Black Marble，都是 GIBS 瓦片（最大 z=8）。
// 地址带 ?notiles（离线）或地球库不支持瓦片时，用 tex/ 下的整张本地贴图。旧图是矢量国界，放大本来就不糊
const NO_TILES = new URLSearchParams(location.search).has("notiles");
const GIBS="https://gibs.earthdata.nasa.gov/wmts/epsg3857/best";
const STYLES={
  marble:{tiles:(x,y,l)=>`${GIBS}/BlueMarble_ShadedRelief_Bathymetry/default/GoogleMapsCompatible_Level8/${l}/${y}/${x}.jpeg`, maxL:8, img:"tex/earth-blue-marble.jpg",
          bg:"tex/night-sky.png",atm:"#8cc4ff",atmAlt:.16,outline:"#ffffff",minAlt:.04, credit:"影像：NASA Blue Marble / GIBS"},
  night:{tiles:(x,y,l)=>`${GIBS}/VIIRS_Black_Marble/default/2016-01-01/GoogleMapsCompatible_Level8/${l}/${y}/${x}.png`, maxL:8, img:"tex/earth-night.jpg",
          bgColor:"#030407",atm:"#ffcf8a",atmAlt:.12,outline:"#ffd89a",minAlt:.04, credit:"夜光影像：NASA Black Marble / GIBS"},
  paper:{bgColor:"#E6E2DA",sea:"#dfe6ea",land:"#ddd2bb",stroke:"#3F5F86",outline:"#b3261e",minAlt:.06, credit:"国界：Natural Earth"},
};
let world=null,countries=null,current=null,selId=null,glow=null,THREE=null;
// 航线发光层：每条航段一根管子，着色器按"中心亮、往外平滑衰减"上色，叠加混合，像雾里的光柱。
// 管子的粗细在顶点着色器里按到相机的距离放大，所以光晕在屏幕上始终是固定的几像素宽，缩放不会变粗方块。
const GLOW_VS=`
attribute vec3 aPrev, aNext; attribute float aSide, aU;
uniform float uWidth;
varying float vU, vS, vFade;
void main(){
  vec3 c = (modelMatrix*vec4(position,1.)).xyz, pr = (modelMatrix*vec4(aPrev,1.)).xyz, nx = (modelMatrix*vec4(aNext,1.)).xyz;
  vec3 view = normalize(cameraPosition - c);
  vec3 tan = normalize(nx - pr);
  vec3 side = normalize(cross(tan, view));
  float d = distance(cameraPosition, c);
  vec3 wp = c + side*aSide*uWidth*d + view*uWidth*d*1.2;   // 横向撑开成正对屏幕的光带；再朝相机挪一点，免得被地表挡住
  vU = aU; vS = aSide;
  vFade = smoothstep(.04, .35, dot(normalize(c), view));   // 越接近地球边缘越淡，像被大气吃掉
  gl_Position = projectionMatrix*viewMatrix*vec4(wp,1.);
}`;
const GLOW_FS=`
uniform vec3 uColor; uniform float uTime, uT, uPh, uHead, uTail, uBase, uCore, uComet, uWhite, uStitch, uAdd, uEnd;
varying float vU, vS, vFade;
float ease(float x){ return x<.5 ? 4.*x*x*x : 1.-pow(-2.*x+2.,3.)/2.; }
void main(){
  float r = abs(vS);                                           // 0=中心，1=光带边缘
  float core = exp(-pow(r/.11, 2.));                           // 极细的亮芯
  float halo = exp(-pow(r/.22, 2.))*.5 + exp(-pow(r/.6, 2.))*.2;  // 两层高斯叠出的雾光，边缘自然归零
  float h = ease(fract(uTime/uT + uPh));
  float dx = vU - h;
  float c = dx < 0. ? exp(dx/uTail) : exp(-dx*dx/(uHead*uHead));
  c *= smoothstep(0., .1, h) * (1. - smoothstep(.9, 1., h));
  float st = uStitch > 0. ? step(.45, fract(vU*uStitch)) : 1.;
  float ends = smoothstep(0., uEnd, vU) * (1. - smoothstep(1.-uEnd, 1., vU));   // 两头只在最后约 1 公里淡出，放大后线头仍贴着红点
  float I = (core*(uCore*st + c*1.4) + halo*(uBase + c*uComet)) * ends * vFade;
  vec3 col = mix(uColor, vec3(1.), clamp(core*uWhite*(.3 + c), 0., 1.));
  if(uAdd > .5) gl_FragColor = vec4(col*I, 1.);
  else gl_FragColor = vec4(col, clamp(I, 0., 1.));
}`;
const GLOW_STYLE={
  marble:{width:.008,base:.42,core:.95,comet:.95,white:.5,add:1},
  night:{width:.0095,base:.45,core:.95,comet:1.1,white:.55,add:1},
  paper:{width:.006,base:.25,core:1,comet:.45,white:0,add:0},
};
async function loadThree(){ if(!THREE){ try{ THREE=await import("https://cdn.jsdelivr.net/npm/three@0.185.0/+esm"); }catch(e){ THREE=null; } } return THREE; }
function buildGlow(){
  if(glow){ world.scene().remove(glow.group); glow.group.traverse(o=>{o.geometry?.dispose();o.material?.dispose()}); glow=null; }
  if(!THREE) return;
  const G=GLOW_STYLE[current], col=new THREE.Color(css("--arc")), group=new THREE.Group(), mats=[];
  legs().out.forEach((l,i)=>{
    const a=new THREE.Vector3().setFromSphericalCoords(1,(90-l.startLat)*R,l.startLng*R), b=new THREE.Vector3().setFromSphericalCoords(1,(90-l.endLat)*R,l.endLng*R);
    const om=a.angleTo(b), hgt=Math.max(.004,.08*om), pts=[];   // 贴地微拱：1000 公里的航段只拱起约 80 公里
    for(let k=0;k<=64;k++){ const t=k/64, s1=Math.sin((1-t)*om)/Math.sin(om), s2=Math.sin(t*om)/Math.sin(om);
      const v=a.clone().multiplyScalar(s1).add(b.clone().multiplyScalar(s2)).normalize();
      const lat=90-Math.acos(v.y)/R, lng=Math.atan2(v.x,v.z)/R, c=world.getCoords(lat,lng,(hgt+.002)*Math.sin(Math.PI*t));   // 两端贴地：整条抬高的话，放大后视差会让线头偏离红点
      pts.push(new THREE.Vector3(c.x,c.y,c.z)); }
    const curve=new THREE.CatmullRomCurve3(pts), N=180, P=curve.getSpacedPoints(N);
    const pos=[],prev=[],next=[],side=[],uu=[],idx=[];
    P.forEach((q,k)=>{ const qp=P[Math.max(0,k-1)], qn=P[Math.min(N,k+1)];
      for(const sd of [-1,1]){ pos.push(q.x,q.y,q.z); prev.push(qp.x,qp.y,qp.z); next.push(qn.x,qn.y,qn.z); side.push(sd); uu.push(k/N); }
      if(k<N){ const o=k*2; idx.push(o,o+1,o+2, o+1,o+3,o+2); } });
    const geo=new THREE.BufferGeometry();
    geo.setAttribute("position",new THREE.Float32BufferAttribute(pos,3)); geo.setAttribute("aPrev",new THREE.Float32BufferAttribute(prev,3));
    geo.setAttribute("aNext",new THREE.Float32BufferAttribute(next,3)); geo.setAttribute("aSide",new THREE.Float32BufferAttribute(side,1));
    geo.setAttribute("aU",new THREE.Float32BufferAttribute(uu,1)); geo.setIndex(idx);
    const m=new THREE.ShaderMaterial({vertexShader:GLOW_VS,fragmentShader:GLOW_FS,transparent:true,depthWrite:false,
      blending:G.add?THREE.AdditiveBlending:THREE.NormalBlending,side:THREE.DoubleSide,
      uniforms:{uWidth:{value:G.width},uColor:{value:col},uTime:{value:0},uT:{value:Math.max(3.8,l.km*.008)},uPh:{value:(i*.37)%1},
        uHead:{value:Math.min(.06,18/l.km)},uTail:{value:Math.min(.25,100/l.km)},uBase:{value:G.base},uCore:{value:G.core},uComet:{value:reduced?0:G.comet},
        uWhite:{value:G.white},uEnd:{value:Math.min(.012,1/l.km)},uStitch:{value:current==="paper"?l.km/14:0},uAdd:{value:G.add}}});
    mats.push(m); {const me=new THREE.Mesh(geo,m); me.frustumCulled=false; me.renderOrder=1000; group.add(me);}   // 画在晨昏层之后，夜里的航线照样亮
  });
  world.scene().add(group); glow={group,mats};
}
(function tick(t){ if(glow&&!reduced) glow.mats.forEach(m=>m.uniforms.uTime.value=t/1000); requestAnimationFrame(tick); })(0);
const css=n=>getComputedStyle(document.documentElement).getPropertyValue(n).trim();

function outlinePaths(id){
  const o=DATA[id]?.outline; if(!o) return [];
  const polys=o.type==="Polygon"?[o.coordinates]:o.coordinates;
  return polys.map(p=>p[0].map(([lng,lat])=>[lat,lng]));
}
let buildSeq=0;
async function build(key){
  const my=++buildSeq;   // 连点切换风格时，旧的那次构建还没跑完就作废，免得两次撞在一起互相顶掉
  current=key; document.documentElement.dataset.style=key;
  document.querySelectorAll("#styles button").forEach(b=>b.setAttribute("aria-pressed",b.dataset.s===key));
  try{localStorage.setItem("jt-style2",key)}catch(e){}
  const S=STYLES[key];
  const pov=world?world.pointOfView():{lat:home().lat??30,lng:home().lng??10,altitude:innerWidth<700?2.9:2.1};
  if(world){world.pauseAnimation?.();world._destructor?.();}
  const el=$("#globe"); el.innerHTML="";
  const paper = key==="paper";
  if(paper) await loadThree();
  if(my!==buildSeq) return;
  const g=Globe({animateIn:false})(el).width(innerWidth).height(innerHeight).backgroundColor(paper?"rgba(0,0,0,0)":(S.bgColor||"#000")).showAtmosphere(!!S.atm);
  if(S.atm) g.atmosphereColor(S.atm).atmosphereAltitude(S.atmAlt);
  if(S.bg) g.backgroundImageUrl(S.bg);
  if(S.tiles && !NO_TILES && typeof g.globeTileEngineUrl==="function") g.globeTileEngineUrl(S.tiles).globeTileEngineMaxLevel(S.maxL);
  else if(S.img) g.globeImageUrl(S.img);
  else if(paper && THREE) g.globeMaterial(engraveMat("sea"));
  else { const m=g.globeMaterial(); m.color.set(S.sea); }
  $("#credit").textContent=S.credit||"";
  const click=c=>{if(c) pickNear(c.lat,c.lng)};
  g.onGlobeClick(click);
  if(key==="paper"){
    if(!countries) countries=await getJSON("countries50.json");   // 1:50m 国界，放大后海岸线也细
    if(my!==buildSeq){ g._destructor?.(); return; }
    g.polygonsData(countries.features).polygonSideColor(()=>"rgba(0,0,0,0)").polygonStrokeColor(()=>"rgba(63,95,134,.8)").polygonAltitude(.003).onPolygonClick((p,e,c)=>click(c));
    if(THREE){ const land=engraveMat("land"); g.polygonCapMaterial(()=>land); } else g.polygonCapColor(()=>S.land);
  }
  // 航线：自己画的发光管（见 buildGlow）；three.js 加载不上时退回地球库自带的一根细线
  const hasThree=await loadThree();
  if(my!==buildSeq){ g._destructor?.(); return; }
  if(!hasThree){ const arcC=css("--arc"); g.arcsData(legs().out).arcColor(()=>arcC).arcStroke(null).arcAltitudeAutoScale(.28); }
  // 有资料的城市：很淡的小点，点开就是长卷
  g.pointsData(CITIES.filter(c=>c.has)).pointLat("lat").pointLng("lng").pointAltitude(.001).pointRadius(key==="paper"?.09:.11)
   .pointColor(()=>key==="paper"?"rgba(63,95,134,.4)":"rgba(255,255,255,.38)").pointsMerge(false).onPointClick(c=>openCity(c.id)).pointLabel(c=>c.name);
  // 城市轮廓
  g.pathsData(selId?outlinePaths(selId):[]).pathPoints(d=>d).pathPointLat(p=>p[0]).pathPointLng(p=>p[1]).pathColor(()=>S.outline).pathStroke(key==="paper"?1.6:1.4).pathPointAlt(key==="paper"?.006:.0015).pathTransitionDuration(0);
  g.htmlElementsData(markers()).htmlAltitude(0).htmlElement(d=>{
    const w=document.createElement("div"); w.className="mkw";
    w.innerHTML=`<div class="mk ${d.t}${d.sl?" sl":""}${d.id===selId?" on":""}" style="--dl:-${(Math.abs(d.lat*7.3+d.lng*3.1)%2.8).toFixed(2)}s" data-id="${d.id}" role="button" aria-label="${esc(d.name)}">${d.t==="name"?'<i class="nd"></i>':d.t==="pin"?PIN:(d.w==="both"?STAR_BOTH:d.w==="partner"?STAR_PT:STAR_ME)}<span class="lb">${esc(d.name)}</span></div>`;
    w.firstChild.onclick=ev=>{ev.stopPropagation();openCity(d.id)}; return w;});
  if(typeof g.htmlElementVisibilityModifier==="function") g.htmlElementVisibilityModifier((e,vis)=>{e.style.visibility=vis?"visible":"hidden"});
  g.pointOfView(pov,0);
  const ctr=g.controls(); ctr.autoRotate=!reduced&&!selId; ctr.autoRotateSpeed=.3;
  ctr.addEventListener("change", scheduleNames);
  // 红点随远近缩放：看整个地球时 0.7 倍，放大到城市级回到 1 倍，免得欧洲挤成一团
  const pz=()=>{ const a=g.pointOfView().altitude; document.body.style.setProperty("--pz", Math.max(.7,Math.min(1,1.15-a*.2)).toFixed(2));
    if(term) term.material.uniforms.uFar.value=Math.max(0,Math.min(1,(a-.25)/.65)); };   // 高度 .25 以下灯光全灭，.9 以上全亮
  ctr.addEventListener("change", pz); pz();
  ctr.addEventListener("change", updateEngraveScale);
  ptsOn=true; nameLabels=[]; nameLabels.key=""; setTimeout(updateNames,300);
  el.addEventListener("pointerdown",()=>{ctr.autoRotate=false},{once:true});
  world=g; buildGlow(); buildTerminator(); if(paper){ buildGraticule(); ENGRAVE_SCALE.done=0; setTimeout(updateEngraveScale,500); }
}

// ---------- 铜版画：用球面经纬度算排线，排线跟着地球转；缩小时按 fwidth 淡成灰调，避免摩尔纹 ----------
const ENGRAVE_VS=`varying vec3 vP; void main(){ vP=position; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.); }`;
const ENGRAVE_FS=`
uniform vec3 uPaper, uInk; uniform float uKind, uScale;
varying vec3 vP;
float lines(float v, float w){   // 发丝线：线宽固定约 1.2 像素（像刻刀划的），不随线距变粗；太密时退成平均灰度
  float fw=max(fwidth(v),1e-4); float dv=min(fract(v),1.-fract(v));
  float l=1.-smoothstep(fw*.35, fw*1.15, dv);
  return mix(l, min(1., fw*1.5), smoothstep(.22,.5,fw)); }
void main(){
  vec3 n=normalize(vP); float lat=degrees(asin(n.y)), lng=degrees(atan(n.x,n.z));
  float ink;
  if(uKind<.5){ ink = lines((lat*.7+lng*.7)*.72*uScale, .09)*.42; }      // 陆地：45° 斜排线（发丝线）
  else { ink = lines(lat*.55*uScale, .06)*.22; }                            // 海：顺着纬线的细水纹
  gl_FragColor=vec4(mix(uPaper, uInk, ink), 1.);
}`;
// 排线密度：每放大一倍密一倍（按 2 的幂取整，避免缩放时一直抖），屏幕上的线距大致不变
const ENGRAVE_SCALE={value:1};
function updateEngraveScale(){ if(!world||current!=="paper") return; const a=world.pointOfView().altitude;
  const v=Math.max(1,Math.min(64,Math.pow(2,Math.round(Math.log2(1.0/Math.max(a,.02))))));
  if(v===ENGRAVE_SCALE.value && ENGRAVE_SCALE.done) return; ENGRAVE_SCALE.value=v; ENGRAVE_SCALE.done=1;
  // 地球库会给每个国家复制一份材质（参数也跟着拷成副本），所以逐个找出来改
  world.scene().traverse(o=>{ const u=o.material?.uniforms; if(u?.uScale) u.uScale.value=v; }); }
function engraveMat(kind){
  return new THREE.ShaderMaterial({vertexShader:ENGRAVE_VS, fragmentShader:ENGRAVE_FS, extensions:{derivatives:true},
    uniforms:{uPaper:{value:new THREE.Color(kind==="land"?"#ddd2bb":"#dfe6ea")}, uInk:{value:new THREE.Color(kind==="land"?"#3F5F86":"#6F9FC8")}, uKind:{value:kind==="land"?0:1}, uScale:ENGRAVE_SCALE}});
}
let grat=null;
function buildGraticule(){
  if(!THREE||!world) return;
  const R=world.getGlobeRadius()*1.0035, pts=[], P=(la,lo)=>{ const c=world.getCoords(la,lo,.0035); return [c.x,c.y,c.z]; };
  for(let lo=-180; lo<180; lo+=30) for(let la=-80; la<80; la+=2) pts.push(...P(la,lo),...P(la+2,lo));
  for(let la=-60; la<=60; la+=30) for(let lo=-180; lo<180; lo+=2) pts.push(...P(la,lo),...P(la,lo+2));
  const geo=new THREE.BufferGeometry(); geo.setAttribute("position",new THREE.Float32BufferAttribute(pts,3));
  grat=new THREE.LineSegments(geo,new THREE.LineBasicMaterial({color:0x3F5F86,transparent:true,opacity:.16,depthWrite:false}));
  world.scene().add(grat);
}

// ---------- 晨昏线：按此刻太阳直射点算昼夜，每分钟更新 ----------
function subsolar(t=Date.now()){
  const d=t/864e5+2440587.5-2451545.0, rad=Math.PI/180;
  const g=(357.529+.98560028*d)*rad, q=280.459+.98564736*d;
  const L=(q+1.915*Math.sin(g)+.020*Math.sin(2*g))*rad, e=(23.439-.00000036*d)*rad;
  const ra=Math.atan2(Math.cos(e)*Math.sin(L),Math.cos(L))/rad, dec=Math.asin(Math.sin(e)*Math.sin(L))/rad;
  const gmst=(280.46061837+360.98564736629*d)%360;
  let lng=ra-gmst; lng=((lng+540)%360)-180;
  return {lat:dec,lng};
}
const TERM_VS=`varying vec3 vP; void main(){ vP=position; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.); }`;
const TERM_FS=`
uniform vec3 uSun, uLine, uNight; uniform float uStyle, uScale, uFar; uniform sampler2D uLights;
varying vec3 vP;
void main(){
  vec3 n=normalize(vP); float d=dot(n,uSun);
  float night=1.-smoothstep(-.10,.04,d), line=exp(-pow(d/.008,2.));   // smoothstep 的两个边界不能反着写（GLSL 未定义，有的显卡直接给 0）
  vec4 c=vec4(0.);
  if(uStyle<.5){            // 蓝石：像从太空看真实地球——没有线，宽而柔的暮光过渡 + 很淡的余晖 + 夜里亮起城市灯光
    float nt=1.-smoothstep(-.28,.07,d);                         // 暮光很宽：天是慢慢黑下来的
    float glow=exp(-pow((d+.05)/.09,2.))*.16;                   // 日落余晖，只是一层很淡的暖色
    float lat=degrees(asin(n.y)), lng=degrees(atan(n.x,n.z));
    vec3 L=texture2D(uLights, vec2((lng+180.)/360., (lat+90.)/180.)).rgb;
    float lum=dot(L,vec3(.3,.5,.2))*smoothstep(.05,.6,nt)*uFar; // 灯光只在真正入夜后亮；放大后灯光贴图会糊成白雾，按远近淡出
    vec3 col=mix(uNight, vec3(1.,.62,.35), glow/(nt*.74+glow+1e-4));
    col=mix(col, L*1.5, clamp(lum*2.4,0.,1.));
    c=vec4(col, clamp((nt*.74+glow)*mix(.35,1.,uFar)+lum*1.2,0.,.95));   // 放大到城市级，夜色也只留薄薄一层，地图要看得清
  } else if(uStyle<1.5){    // 夜航：白天那半边压暗灯光，分界一条金线
    c=vec4(vec3(.02,.05,.12), (1.-night)*.62); c=mix(c, vec4(uLine,.7), line*.85);
  } else {                  // 旧图：夜半边交叉排线，分界一条墨线
    float lat=degrees(asin(n.y)), lng=degrees(atan(n.x,n.z)), v=(lat*.7-lng*.7)*1.6*uScale, fw=fwidth(v);
    float h=1.-smoothstep(.12-fw,.12+fw,.5-abs(fract(v)-.5)); h=mix(h,.24,smoothstep(.25,.6,fw));
    c=vec4(uNight, h*night*.55); c=mix(c, vec4(uLine,.75), line);
  }
  gl_FragColor=c;
}`;
let term=null, LIGHTS=null;   // 蓝石夜半边的城市灯光（复用夜航的灯光贴图）
function buildTerminator(){
  term=null;
  if(!THREE||!world) return;
  if(current!=="marble"){ updateSun(); return; }   // 只有蓝石有晨昏线：夜航本来就是"全世界的夜"，旧图的夜半边排线太花
  const st=current==="marble"?0:current==="night"?1:2;
  const R=world.getGlobeRadius()*1.0045;   // 瓦片地图画得比球面略高，晨昏层要再高一点才不被挡住
  // 瓦片在深度上会压住它（只在球边缘露出一点）→ 不做深度检测；只画朝镜头的正面，不会透到背面
  const mat=new THREE.ShaderMaterial({vertexShader:TERM_VS, fragmentShader:TERM_FS, transparent:true, depthWrite:false, depthTest:false, extensions:{derivatives:true},
    uniforms:{uSun:{value:new THREE.Vector3(1,0,0)}, uStyle:{value:st}, uFar:{value:Math.max(0,Math.min(1,(world.pointOfView().altitude-.25)/.65))}, uScale:{value:ENGRAVE_SCALE.value},
      uLine:{value:new THREE.Color(st===0?"#ffd9a0":st===1?"#f2c46a":"#3b2a1a")}, uNight:{value:new THREE.Color(st===2?"#3b2a1a":"#030712")},
      uLights:{value:LIGHTS||(LIGHTS=new THREE.TextureLoader().load("tex/earth-night.jpg"))}}});
  term=new THREE.Mesh(new THREE.SphereGeometry(R,96,64),mat); term.renderOrder=999;   // 瓦片带淡入、算半透明，会画在后面盖住晨昏层；排到最后画
  world.scene().add(term); updateSun();
}
function updateSun(){
  if(!world) return;
  const s=subsolar(), c=world.getCoords(s.lat,s.lng,0);
  term?.material.uniforms.uSun.value.set(c.x,c.y,c.z).normalize();
  const fmt=tz=>new Intl.DateTimeFormat("zh-CN",{timeZone:tz,hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date());
  const day=(lat,lng)=>{ const v=world.getCoords(lat,lng,0); return v.x*c.x+v.y*c.y+v.z*c.z>0; };
  // 时钟来自配置 clocks：[{label, tz, lat?, lng?}]；时区和家一样的钟用家的坐标判断昼夜，没坐标的不画日月
  const H=home(), clocks=state.cfg.clocks||[];
  const parts=clocks.map(k=>{ let t; try{ t=fmt(k.tz||undefined); }catch(e){ return ""; }
    const ll = k.lat!=null&&k.lng!=null ? k : (k.tz&&k.tz===H.tz&&H.lat!=null ? H : null);
    return `${esc(k.label||k.tz||"")} ${t}${ll?(day(ll.lat,ll.lng)?"☀︎":"☾"):""}`; }).filter(Boolean);
  $("#now").innerHTML = parts.length ? "此刻 · "+parts.join(" · ") : "";
}
setInterval(updateSun,60000);
function refreshLayers(){
  if(THREE) buildGlow(); else world.arcsData(legs().out); world.htmlElementsData(markers());
  world.pathsData(selId?outlinePaths(selId):[]); renderSide();
}
function pickNear(lat,lng){
  const alt=world.pointOfView().altitude, lim=Math.max(60,alt*500);
  let best=null,bd=1e9; for(const c of CITIES){const d=km({lat,lng},c); if(d<bd){bd=d;best=c}}
  if(best&&bd<lim) openCity(best.id); else if(selId) closeCard(); else toast("这里附近没有收录的城市");
}
// 停住自转：光关 autoRotate 不够，阻尼里还存着转动的惯性，镜头飞到城市后会接着慢慢滑走（放得越近越明显）
// 8 秒没碰页面、卡片和弹层都关着 → 恢复自转；一碰就停
let lastTouch=Date.now();
["pointerdown","wheel","touchstart","keydown"].forEach(ev=>addEventListener(ev,()=>{ lastTouch=Date.now(); if(world&&!reduced) world.controls().autoRotate=false; },{passive:true,capture:true}));
// 看城 / 弹层开着 / 切到后台的时间不算：回到地球才重新数，不然一退出来地球马上转
setInterval(()=>{ if(!world||reduced) return;
  if(selId || document.hidden || [...document.querySelectorAll(".layer")].some(x=>!x.hidden)){ lastTouch=Date.now(); return; }
  if(Date.now()-lastTouch>8000 && !world.controls().autoRotate) world.controls().autoRotate=true; },1000);
document.addEventListener("visibilitychange",()=>{ lastTouch=Date.now(); });
function stopSpin(){ const c=world.controls(); c.autoRotate=false; const d=c.enableDamping; c.enableDamping=false; c.update(); c.enableDamping=d; }
function zoomFor(id){
  const b=IDX[id]?.b; let alt=.32;
  if(b){const span=Math.max(km({lat:b[0],lng:b[2]},{lat:b[1],lng:b[2]}),km({lat:b[0],lng:b[2]},{lat:b[0],lng:b[3]})); alt=Math.min(.45,Math.max(STYLES[current]?.minAlt??.12,span/600));}
  return alt;
}
function silhouette(id){
  const o=DATA[id]?.outline; if(!o) return "";
  const polys=o.type==="Polygon"?[o.coordinates]:o.coordinates;
  const pts=polys.flatMap(p=>p[0]); const lat0=pts.reduce((s,p)=>s+p[1],0)/pts.length, k=Math.cos(lat0*R);
  const xs=pts.map(p=>p[0]*k), ys=pts.map(p=>-p[1]);
  const x0=Math.min(...xs),x1=Math.max(...xs),y0=Math.min(...ys),y1=Math.max(...ys),s=Math.max(x1-x0,y1-y0)||1;
  const ox=(s-(x1-x0))/s*50, oy=(s-(y1-y0))/s*50;
  const d=polys.map(p=>"M"+p[0].map(([lng,lat])=>((lng*k-x0)/s*100+ox).toFixed(1)+","+((-lat-y0)/s*100+oy).toFixed(1)).join("L")+"Z").join("");
  return `<svg class="sil" viewBox="-4 -4 108 108" aria-label="城市轮廓"><path d="${d}"/></svg>`;
}

