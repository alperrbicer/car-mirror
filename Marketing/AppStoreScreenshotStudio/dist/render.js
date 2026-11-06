(function(){
'use strict';
const q=new URLSearchParams(location.search);
const slide=Number(document.body.dataset.slide||q.get('slide')||'1');
const lang=(window.MIRIVO_RENDER_OPTIONS&&window.MIRIVO_RENDER_OPTIONS.lang)||q.get('lang')||'tr-TR';
const device=((window.MIRIVO_RENDER_OPTIONS&&window.MIRIVO_RENDER_OPTIONS.device)||q.get('device'))==='ipad'?'ipad':'iphone';
const t=(window.MIRIVO_LOCALES[lang]||window.MIRIVO_LOCALES['tr-TR'])[slide-1];
document.documentElement.lang=lang;
if(!t){document.body.innerText='Missing translation for slide '+slide;return;}
const esc=s=>String(s).replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[ch]));
const screen=(name,sign='▣')=>{const src=(window.MIRIVO_ASSETS&&window.MIRIVO_ASSETS[name])||`assets/screens/${name}.png`;return `<div class="device-screen"><div class="screen-slot"><span class="slot-symbol">${sign}</span><span class="slot-label">SCREENSHOT SLOT</span><span class="slot-rule"></span></div><img class="actual-screenshot" data-screen="${name}" src="${src}" alt="Mirivo real app screenshot" onload="this.parentElement.classList.add('has-image')" onerror="this.parentElement.classList.remove('has-image')"></div>`};
const dev=(type,cls,name,sign)=>`<div class="device device-${type} ${cls}">${screen(name,sign)}<div class="glass-sheen"></div></div>`;
const e=(t.extra||{});
const x=k=>esc(e[k]||'');
const halo='<div class="light-floor"></div><div class="light-column"></div><div class="halo n1"></div><div class="halo n2"></div>';
// Screenshot 01 only: a layered, editable vehicle dashboard behind the CarPlay screen.
// No device screenshot is altered, and no other screenshot master uses these elements.
const carCockpit=`<div class="car-cockpit" aria-hidden="true">
  <div class="cockpit-upper"></div>
  <div class="cockpit-steering"><div class="wheel-rim"></div><div class="wheel-spoke"></div><div class="wheel-hub"></div></div>
  <div class="cockpit-console"><div class="cockpit-seam"></div>
    <div class="cockpit-vent vent-left"><i></i><i></i><i></i><i></i></div>
    <div class="cockpit-vent vent-right"><i></i><i></i><i></i><i></i></div>
    <div class="cockpit-climate"><span class="climate-knob"></span><span class="climate-light"></span><span class="climate-knob"></span></div>
    <span class="cockpit-hazard">△</span>
  </div>
</div>`;
// Only Screenshot 04: a readable, CSS-only vehicle interior behind the actual CarPlay screen.
const vehicleDashboard=`<div class="vehicle-dashboard" aria-hidden="true">
  <div class="dash-hood"></div><div class="dash-shell"></div><div class="dash-steering"></div>
  <div class="dash-vent left"><i></i><i></i><i></i></div>
  <div class="dash-vent right"><i></i><i></i><i></i></div>
  <div class="dash-climate"><i></i><b>△</b><i></i></div>
  <div class="dash-carplay-mark">CARPLAY</div>
</div>`;
const scenes={
1:`${halo}${dev('tv','d-tv','01-tv','▣')}${dev('phone','d-phone','01-phone','▥')}${dev('tablet','d-tablet','01-tablet','▦')}${carCockpit}${dev('car','d-car','01-car','▤')}`,
2:`${halo}<div class="ring"></div>${dev('phone','d-phone','02-phone','▥')}<div class="glass-card float1"><span class="source-icon">＋</span><div class="eyebrow" dir="auto">${x("source1")}</div><div class="main" dir="auto">${x("mediaSource")}</div><div class="muted" dir="auto">${x("ownContent")}</div></div><div class="glass-card float2"><span class="source-icon">≡</span><div class="eyebrow" dir="auto">${x("source2")}</div><div class="main" dir="auto">${x("manageLists")}</div></div><div class="glass-card float3"><span class="source-icon">✓</span><div class="eyebrow" dir="auto">${x("organized")}</div><div class="main" dir="auto">${x("allInOne")}</div></div>`,
3:`${halo}${dev('tv','d-tv','03-tv','▣')}<div class="cast-beam"></div>${dev('phone','d-phone','03-tv','▥')}<div class="glass-card cast-bubble"><span class="cast-icon">▣</span><div class="eyebrow" dir="auto">${x("largeScreen")}</div><div class="main" dir="auto">${x("roomToEnjoy")}</div></div>`,
4:`${halo}<div class="dashboard-halo"></div>${vehicleDashboard}${dev('car','d-car','04-car','▤')}${dev('phone','d-phone','04-car','▥')}<div class="glass-card park-note"><div class="park-icon">P</div><div class="eyebrow" dir="auto">${x("parkMode")}</div><div class="main" dir="auto">${x("onlyParked")}</div></div>`,
5:`${halo}<div class="orbit"></div>${dev('phone','d-phone first','05-library','▥')}<div class="glass-card lib-card"><div class="squares"><i></i><i></i><i></i></div><div class="eyebrow" dir="auto">${x("mediaCollection")}</div><div class="main" dir="auto">${x("organizedSpace")}</div></div>${dev('phone','d-phone second','05-detail','▥')}`,
6:`${halo}${dev('phone','d-phone','06-player','▶')}<div class="pause-circle"></div><div class="glass-card track-card"><div class="eyebrow" dir="auto">${x("playback")}</div><div class="main" dir="auto">${x("keepWatching")}</div><div class="track"><i></i></div><div class="track-labels"><span>00:42</span><span>01:08</span></div></div>`
};
let titleClass=t.title.length>2?'three':t.title.join('').length>30?'long':'';
const root=document.getElementById('artboard');
root.className=`artboard slide-${slide}${device==='ipad'?' ipad':''}`;
root.dataset.locale=lang;
root.innerHTML=`<div class="top-atmosphere"><div class="top-light-line"></div></div><div class="back-light-streaks" aria-hidden="true"></div><div class="vertical-grain"></div><div class="back-orb o1"></div><div class="back-orb o2"></div><div class="back-orb o3"></div>
<header class="header"><div class="brand" id="brand"><span class="brand-mark"><img id="real-logo" src="${(window.MIRIVO_ASSETS&&window.MIRIVO_ASSETS.logo)||'assets/MirivoMark.svg'}" alt="Mirivo original logo mark"><span class="brand-mark-fallback" aria-label="logo file missing">◇</span></span><span class="brand-text">Mirivo</span></div><div class="header-number"><span class="progress">${[1,2,3,4,5,6].map(i=>`<i class="${i===slide?'active':''}"></i>`).join('')}</span><span>${String(slide).padStart(2,'0')} / 06</span></div></header>
<div class="copy ${titleClass}"><div class="kicker" dir="auto">${esc(t.kicker)}</div><h1 class="headline">${t.title.map((line,i)=>`<span dir="auto" class="${i===t.title.length-1?'emph':''}">${esc(line)}</span>`).join('')}</h1><p class="subtitle" dir="auto">${esc(t.subtitle)}</p></div>
<div class="scene scene-${slide}">${scenes[slide]}</div><div class="bottom-meta"><div class="left" dir="auto">${esc(t.small)}</div><div class="right">MIRIVO / ${String(slide).padStart(2,'0')}</div></div>`;
const img=document.getElementById('real-logo');
img.onload=()=>document.getElementById('brand').classList.add('has-logo');
img.onerror=()=>document.getElementById('brand').classList.remove('has-logo');
const sz=device==='ipad'?{w:2752,h:2064}:{w:1320,h:2868};
function scale(){const vw=document.documentElement.clientWidth,vh=document.documentElement.clientHeight;const s=Math.min(vw/sz.w,vh/sz.h);root.style.transform=`translate(${(vw-sz.w*s)/2}px,${(vh-sz.h*s)/2}px) scale(${s})`;root.style.transformOrigin='0 0'}
window.addEventListener('resize',scale);scale();
document.title=`Mirivo — Screenshot ${String(slide).padStart(2,'0')} (${lang}, ${device})`;
window.MIRIVO_RENDER_READY=true;
})();
