/* ============================================================
   Homzy shared front-end runtime.
   - Language (AR/EN, RTL) toggle, persisted.
   - Client/Broker mode toggle, fixed in the header, persisted,
     switches the whole site (nav + .only-client/.only-broker).
   - Injects the shared header, footer and AI chat widget.
   - Chat: project-aware context, localStorage persistence, and
     a hook that saves the conversation (lead) to Supabase.
   ============================================================ */
(function(){
const SB_URL='https://ceoqtkbpdxnkuptnnwjg.supabase.co';
const SB_KEY='sb_publishable_akQqDzkDbBhYJP0q6Z4Dtg_xjQh_Xfb';

const HZ = window.HZ = {
  lang: localStorage.getItem('hz_lang') || 'ar',
  mode: localStorage.getItem('hz_mode') || 'client',
  // Broker's WhatsApp number (digits only, intl format e.g. 2010xxxxxxxx).
  // Shown ONLY on resale units. Leave '' to hide the WhatsApp button.
  brokerWhatsApp: '',
};

/* ---------- Supabase helper ---------- */
HZ.sb = async function(path, opts){
  const r = await fetch(SB_URL+'/rest/v1'+path, Object.assign({
    headers:{apikey:SB_KEY, Authorization:'Bearer '+SB_KEY}
  }, opts||{}));
  if(!r.ok) throw new Error('sb '+r.status);
  const txt = await r.text();
  return txt ? JSON.parse(txt) : null;
};
HZ.esc = s => (s==null?'':''+s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

// Call a Postgres function (RPC). HZ.sb replaces the whole headers object, so
// RPC needs its own POST helper that keeps the auth headers + JSON content-type.
HZ.rpc = async function(fn, args){
  const r = await fetch(SB_URL+'/rest/v1/rpc/'+fn, {
    method:'POST',
    headers:{apikey:SB_KEY, Authorization:'Bearer '+SB_KEY, 'Content-Type':'application/json'},
    body: JSON.stringify(args||{})
  });
  if(!r.ok) throw new Error('rpc '+r.status);
  const txt = await r.text();
  return txt ? JSON.parse(txt) : null;
};

// Shared area-normalization KEY: folds near-duplicate area names to one bucket
// so the Areas page and the browse filter agree (e.g. "New Zayed"/"Zayed",
// "6th of October"/"6 October", "El Maadi"/"Maadi", "New Heliopolis"/"Heliopolis").
// Strips ordinals + the "of/el/al/new" filler words, lowercases, collapses spaces.
HZ.normArea = a => (a||'').toLowerCase()
  .replace(/[^a-z0-9؀-ۿ ]/g,'')
  .replace(/(\d)(st|nd|rd|th)/g,'$1')
  .replace(/\b(of|el|al|new)\b/g,'')
  // fold obvious transliteration twins of the same place
  .replace(/\bnaser\b/g,'nasr')
  .replace(/\bmokatam\b/g,'mokattam')
  .replace(/\b(sedr|sudar)\b/g,'sudr')
  .replace(/\s+/g,' ').trim();

/* ---------- i18n ---------- */
const T = {
  home:{ar:'الرئيسية',en:'Home'}, features:{ar:'المميزات',en:'Features'},
  areas:{ar:'المناطق',en:'Areas'}, browse:{ar:'تصفّح المشاريع',en:'Browse projects'},
  app:{ar:'التطبيق',en:'App'}, brokerTools:{ar:'أدوات البروكر',en:'Broker tools'},
  listUnit:{ar:'اعرض وحدتك',en:'List your unit'}, client:{ar:'عميل',en:'Client'}, broker:{ar:'بروكر',en:'Broker'},
  advisor:{ar:'مستشارك العقاري',en:'Your property advisor'},
  footTagline:{ar:'مستشارك العقاري الذكي في مصر — بالعربي والإنجليزي، مبني على داتا حقيقية.',en:'Your smart real-estate advisor in Egypt — bilingual, grounded in real data.'},
  platform:{ar:'المنصة',en:'Platform'}, forBrokers:{ar:'للبروكرز',en:'For brokers'},
  admin:{ar:'لوحة الإدارة',en:'Admin'}, join:{ar:'انضم كبروكر',en:'Join as broker'},
  disclaimer:{ar:'Homzy ممكن يغلط — راجع المعلومات المهمة قبل أي قرار.',en:'Homzy can make mistakes — verify important info before deciding.'},
  chatAbout:{ar:'بنتكلم عن',en:'Talking about'}, newChat:{ar:'محادثة جديدة',en:'New chat'}, close:{ar:'إغلاق',en:'Close'},
  leads:{ar:'الليدز',en:'Leads'},
};
HZ.t = k => (T[k]||{})[HZ.lang] || k;

HZ.applyLang = function(){
  document.documentElement.lang = HZ.lang;
  document.documentElement.dir = HZ.lang==='ar' ? 'rtl' : 'ltr';
  document.querySelectorAll('[data-ar]').forEach(el=>{
    const v = el.getAttribute('data-'+HZ.lang); if(v==null) return;
    if(el.tagName==='OPTION') el.textContent = v; else el.innerHTML = v;
  });
  document.querySelectorAll('[data-ph-ar]').forEach(el=>{ el.placeholder = el.getAttribute('data-ph-'+HZ.lang) || ''; });
  const lb = document.getElementById('hzLang'); if(lb) lb.textContent = HZ.lang==='ar' ? 'EN' : 'ع';
  buildNavLinks(); refreshTabbar(); setAuthBtn();
  document.dispatchEvent(new CustomEvent('hz:lang', {detail:HZ.lang}));
};
HZ.toggleLang = function(){ HZ.lang = HZ.lang==='ar'?'en':'ar'; localStorage.setItem('hz_lang',HZ.lang); HZ.applyLang(); };

/* ---------- Client / Broker mode ---------- */
HZ.setMode = function(m){
  HZ.mode = m; localStorage.setItem('hz_mode', m);
  document.body.setAttribute('data-mode', m);
  const seg = document.getElementById('hzMode');
  if(seg){ seg.querySelectorAll('button').forEach(b=>b.classList.toggle('on', b.dataset.m===m)); }
  buildNavLinks();
  document.dispatchEvent(new CustomEvent('hz:mode', {detail:m}));
};

/* ---------- Header / nav ---------- */
const NAV = {
  client:[['/','home'],['/features','features'],['/areas','areas'],['/app','browse'],['/download','app']],
  broker:[['/','home'],['/leads','leads'],['/brokers','brokerTools'],['/app','browse'],['/download','app']],
};
function navHTML(){
  const links = NAV[HZ.mode]||NAV.client;
  const path = location.pathname;
  return links.map(([href,key])=>{
    const active = (href===path) || (href!=='/' && path.startsWith(href.split('?')[0]) && href.split('?')[0]!=='/');
    return `<a href="${href}" class="${active?'active':''}">${HZ.t(key)}</a>`;
  }).join('');
}
function buildNavLinks(){
  const l=document.getElementById('hzLinks'); if(l) l.innerHTML=navHTML();
  const m=document.getElementById('hzMobile'); if(m) m.innerHTML=navHTML();
}
const LOGO=`<svg class="mk" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg"><rect width="64" height="64" rx="16" fill="#0B1D36"/><path d="M15 51V29L32 15l17 14v22" stroke="#fff" stroke-width="4.5" fill="none" stroke-linejoin="round" stroke-linecap="round"/><rect x="26.5" y="33" width="11" height="11" rx="2.4" fill="#0B5563"/></svg>`;

function buildHeader(){
  const host=document.getElementById('hz-header'); if(!host) return;
  host.innerHTML=`
  <header class="hz-nav" id="hzNav">
    <div class="wrap hz-nav-in">
      <a href="/" class="hz-logo"><span>${LOGO}</span><span class="nm">Hom<b>zy</b></span></a>
      <nav class="hz-links" id="hzLinks"></nav>
      <div class="hz-nav-cta">
        <div class="hz-mode" id="hzMode" title="Client / Broker">
          <button class="c" data-m="client" onclick="HZ.setMode('client')">${HZ.t('client')}</button>
          <button class="b" data-m="broker" onclick="HZ.setMode('broker')">${HZ.t('broker')}</button>
        </div>
        <button class="hz-lang" id="hzLang" onclick="HZ.toggleLang()">EN</button>
        <button class="hz-auth" id="hzAuth" onclick="HZ.authAction()"></button>
        <button class="hz-menu-btn" onclick="document.getElementById('hzMobile').classList.toggle('open')" aria-label="menu">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M4 7h16M4 12h16M4 17h16" stroke="#0B1D36" stroke-width="2" stroke-linecap="round"/></svg>
        </button>
      </div>
    </div>
    <div class="hz-mobile" id="hzMobile"></div>
  </header>`;
  addEventListener('scroll',()=>{ const n=document.getElementById('hzNav'); if(n) n.classList.toggle('scrolled', scrollY>8); });
  document.getElementById('hzMobile').addEventListener('click',e=>{ if(e.target.tagName==='A') document.getElementById('hzMobile').classList.remove('open'); });
}
// ---- client auth state (login gate) ----
// A logged-in visitor has a Supabase session token in localStorage. We don't
// need supabase-js here: logout just clears that token and the head-guard on
// protected pages sends the user back to /login.
HZ.isLoggedIn = function(){
  try{
    const k=Object.keys(localStorage).find(x=>/sb-.*-auth-token/.test(x));
    const t=k?JSON.parse(localStorage.getItem(k)):null;
    return !!(t&&t.access_token&&(!t.expires_at||t.expires_at*1000>Date.now()));
  }catch(e){ return false; }
};
HZ.logout = function(){
  try{ Object.keys(localStorage).filter(x=>/sb-.*-auth-token/.test(x)).forEach(x=>localStorage.removeItem(x)); }catch(e){}
  location.href='/';
};
HZ.authAction = function(){
  if(HZ.isLoggedIn()) HZ.logout();
  else location.href='/login?next='+encodeURIComponent(location.pathname+location.search);
};
function setAuthBtn(){
  const b=document.getElementById('hzAuth'); if(!b) return;
  const inn=HZ.isLoggedIn();
  b.textContent = inn ? (HZ.lang==='ar'?'خروج':'Log out') : (HZ.lang==='ar'?'دخول':'Log in');
  b.classList.toggle('out', inn);
}
HZ.refreshAuthBtn = setAuthBtn;

function buildFooter(){
  const host=document.getElementById('hz-footer'); if(!host) return;
  host.innerHTML=`
  <footer class="hz-foot">
    <div class="wrap">
      <div class="hz-foot-grid">
        <div class="hz-foot-brand">
          <a href="/" class="hz-logo" style="color:#fff"><span>${LOGO}</span><span class="nm">Hom<b style="color:var(--teal-on-navy)">zy</b></span></a>
          <p>${HZ.t('footTagline')}</p>
        </div>
        <div class="hz-foot-col">
          <h4>${HZ.t('platform')}</h4>
          <a href="/features">${HZ.t('features')}</a><a href="/areas">${HZ.t('areas')}</a>
          <a href="/app">${HZ.t('browse')}</a><a href="/download">${HZ.t('app')}</a>
        </div>
        <div class="hz-foot-col">
          <h4>${HZ.t('forBrokers')}</h4>
          <a href="/leads?register=1">${HZ.t('join')}</a><a href="/brokers">${HZ.t('brokerTools')}</a><a href="/leads">${HZ.t('leads')}</a>
        </div>
      </div>
      <div class="hz-foot-bottom"><span>© ${new Date().getFullYear()} Homzy</span><span>${HZ.t('disclaimer')}</span></div>
    </div>
  </footer>`;
}

/* ---------- Mobile bottom tab bar + "More" sheet ---------- */
const ICON={
  home:'<svg viewBox="0 0 24 24" fill="none"><path d="M3 10.5 12 3l9 7.5V21H4a1 1 0 0 1-1-1z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>',
  browse:'<svg viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="7" height="7" rx="1.6" stroke="currentColor" stroke-width="1.8"/><rect x="14" y="3" width="7" height="7" rx="1.6" stroke="currentColor" stroke-width="1.8"/><rect x="3" y="14" width="7" height="7" rx="1.6" stroke="currentColor" stroke-width="1.8"/><rect x="14" y="14" width="7" height="7" rx="1.6" stroke="currentColor" stroke-width="1.8"/></svg>',
  chat:'<svg viewBox="0 0 24 24" fill="none"><path d="M4 5h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9l-5 4V6a1 1 0 0 1 1-1Z" fill="currentColor"/></svg>',
  areas:'<svg viewBox="0 0 24 24" fill="none"><path d="M12 21s7-6.3 7-11a7 7 0 1 0-14 0c0 4.7 7 11 7 11Z" stroke="currentColor" stroke-width="1.8"/><circle cx="12" cy="10" r="2.4" stroke="currentColor" stroke-width="1.8"/></svg>',
  more:'<svg viewBox="0 0 24 24" fill="none"><circle cx="5" cy="12" r="1.7" fill="currentColor"/><circle cx="12" cy="12" r="1.7" fill="currentColor"/><circle cx="19" cy="12" r="1.7" fill="currentColor"/></svg>',
};
const TAB_T={home:{ar:'الرئيسية',en:'Home'},browse:{ar:'تصفّح',en:'Browse'},chat:{ar:'الشات',en:'Chat'},areas:{ar:'المناطق',en:'Areas'},more:{ar:'المزيد',en:'More'}};
function tt(k){return TAB_T[k][HZ.lang];}
function buildTabbar(){
  if(document.getElementById('hzTabbar')) return;
  const path=location.pathname;
  const act=(k)=> (k==='home'&&path==='/')||(k==='browse'&&/^\/(app|browse|projects)/.test(path))||(k==='areas'&&path==='/areas') ? 'on':'';
  const bar=document.createElement('nav'); bar.className='hz-tabbar'; bar.id='hzTabbar';
  bar.innerHTML=`
    <a href="/" class="${act('home')}">${ICON.home}<span>${tt('home')}</span></a>
    <a href="/app" class="${act('browse')}">${ICON.browse}<span>${tt('browse')}</span></a>
    <button class="tb-chat" onclick="HZ.openChat()"><span class="tb-chat-ic">${ICON.chat}</span><span>${tt('chat')}</span></button>
    <a href="/areas" class="${act('areas')}">${ICON.areas}<span>${tt('areas')}</span></a>
    <button onclick="HZ.toggleMore()">${ICON.more}<span>${tt('more')}</span></button>`;
  document.body.appendChild(bar);
  // "More" sheet
  const bk=document.createElement('div'); bk.className='hz-sheet-bk'; bk.id='hzSheetBk'; bk.onclick=()=>HZ.toggleMore();
  const sheet=document.createElement('div'); sheet.className='hz-sheet'; sheet.id='hzSheet';
  sheet.innerHTML=`<div class="handle"></div>
    <a href="/features"><span class="ic">✨</span><span>${HZ.t('features')}</span></a>
    <a href="/leads"><span class="ic">🎯</span><span>${HZ.t('leads')}</span></a>
    <a href="/brokers"><span class="ic">🧰</span><span>${HZ.t('forBrokers')}</span></a>
    <a href="/download"><span class="ic">📱</span><span>${HZ.t('app')}</span></a>
    <a href="/admin"><span class="ic">⚙️</span><span>${HZ.t('admin')}</span></a>`;
  document.body.appendChild(bk); document.body.appendChild(sheet);
}
HZ.toggleMore=function(){
  const s=document.getElementById('hzSheet'), b=document.getElementById('hzSheetBk');
  if(!s) return; const open=s.classList.toggle('open'); b.classList.toggle('open',open);
};
function refreshTabbar(){ const b=document.getElementById('hzTabbar'); if(b){ b.remove(); const s=document.getElementById('hzSheet'); if(s)s.remove(); const bk=document.getElementById('hzSheetBk'); if(bk)bk.remove(); buildTabbar(); } }

/* ============================================================
   Chat widget — project-aware, persisted, lead-capturing.
   ============================================================ */
const CHAT_KEY='hz_chat_v1';
let chat = loadChat();
function loadChat(){
  try{ return JSON.parse(localStorage.getItem(CHAT_KEY)) || null; }catch(e){ return null; }
  }
function newChatState(){
  return { sessionId:'web-'+Math.random().toString(36).slice(2), history:[], context:null, lead:{}, greeted:false };
}
function saveChat(){ try{ localStorage.setItem(CHAT_KEY, JSON.stringify(chat)); }catch(e){} HZ.saveLead && HZ.saveLead(); }

const isAr = x => /[؀-ۿ]/.test(x||'');

function buildChat(){
  if(document.getElementById('hzChatPanel')) return;
  const fab=document.createElement('button');
  fab.className='chat-fab'; fab.id='hzChatFab'; fab.setAttribute('aria-label','chat');
  fab.innerHTML=`<svg viewBox="0 0 24 24" fill="none"><path d="M4 5h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9l-5 4V6a1 1 0 0 1 1-1Z" fill="#fff"/><circle cx="9" cy="11" r="1.3" fill="#0B5563"/><circle cx="13" cy="11" r="1.3" fill="#0B5563"/><circle cx="17" cy="11" r="1.3" fill="#0B5563"/></svg>`;
  fab.onclick=()=>HZ.toggleChat();
  const panel=document.createElement('div');
  panel.className='chat-panel'; panel.id='hzChatPanel'; panel.dir=HZ.lang==='ar'?'rtl':'ltr';
  panel.innerHTML=`
    <div class="cp-head">
      <div class="a"><svg width="22" height="22" viewBox="0 0 64 64"><path d="M17 47V31l15-12 15 12v16" stroke="#0B1D36" stroke-width="5" fill="none" stroke-linejoin="round" stroke-linecap="round"/><rect x="27" y="34" width="10" height="10" rx="2" fill="#0B5563"/></svg></div>
      <div><div class="nm">Homzy</div><div class="sub" id="hzCpSub"></div></div>
      <div class="btns">
        <button class="ic" id="hzCpNew" title="new">✎</button>
        <button class="ic" id="hzCpClose" title="close">×</button>
      </div>
    </div>
    <div class="cp-ctx" id="hzCpCtx"></div>
    <div class="cp-log" id="hzCpLog"></div>
    <div class="cp-chips" id="hzCpChips"></div>
    <form class="cp-form" id="hzCpForm"><input id="hzCpInput" autocomplete="off"/><button type="submit" id="hzCpSend"><svg width="18" height="18" viewBox="0 0 24 24"><path d="M3.4 20.4 21 12 3.4 3.6 3.4 10.2 15 12 3.4 13.8Z" fill="currentColor"/></svg></button></form>`;
  document.body.appendChild(fab); document.body.appendChild(panel);
  document.getElementById('hzCpClose').onclick=()=>HZ.toggleChat();
  document.getElementById('hzCpNew').onclick=()=>{ chat=newChatState(); saveChat(); renderChat(); seedGreeting(); };
  document.getElementById('hzCpForm').addEventListener('submit',e=>{e.preventDefault(); sendMsg(document.getElementById('hzCpInput').value);});
  document.getElementById('hzCpSub').textContent=HZ.t('advisor');
}

function ctxLabel(){
  if(!chat.context) return '';
  const c=chat.context;
  return (HZ.t('chatAbout'))+': '+ (c.name||'') + (c.area?(' · '+c.area):'');
}
function renderCtx(){
  const el=document.getElementById('hzCpCtx'); if(!el) return;
  if(chat.context){ el.textContent='📍 '+ctxLabel(); el.classList.add('show'); }
  else{ el.classList.remove('show'); el.textContent=''; }
}
function addMsg(text,who){
  const log=document.getElementById('hzCpLog');
  const d=document.createElement('div'); d.className='msg '+who;
  d.style.direction=isAr(text)?'rtl':'ltr'; d.style.textAlign=isAr(text)?'right':'left';
  d.textContent=text; log.appendChild(d); log.scrollTop=log.scrollHeight; return d;
}
function addRec(rec){
  const ar=HZ.lang==='ar', log=document.getElementById('hzCpLog');
  const price=ar?(rec.price_ar||rec.price_en||''):(rec.price_en||rec.price_ar||'');
  const isResale=rec.market==='resale';
  const market=isResale?(ar?'RESALE · جاهزة':'RESALE · ready'):(ar?'PRIMARY · من المطوّر':'PRIMARY · new launch');
  const name=ar?(rec.compound_ar||rec.compound||''):(rec.compound||rec.compound_ar||'');
  const area=ar?(rec.area_ar||rec.area||''):(rec.area||rec.area_ar||'');
  const beds=rec.bedrooms!=null?`<span>${rec.bedrooms} ${ar?'غرف':'BR'}</span>`:'';
  const size=rec.size_sqm?`<span>${rec.size_sqm} ${ar?'م²':'m²'}</span>`:'';
  const dev=rec.developer?`<span>${HZ.esc(rec.developer)}</span>`:'';
  // WhatsApp only for resale (per product decision); primary → advisor keeps talking.
  let wa='';
  if(isResale){
    const num=(''+(rec.phone||HZ.brokerWhatsApp||'')).replace(/[^0-9]/g,'');
    if(num) wa=`<a class="wa" target="_blank" rel="noopener" href="https://wa.me/${num}?text=${encodeURIComponent((ar?'مهتم بـ ':'Interested in ')+name+' — Homzy')}">🟢 ${ar?'واتساب':'WhatsApp'}</a>`;
  }
  const d=document.createElement('div'); d.className='rec-card'; d.dir=ar?'rtl':'ltr';
  d.innerHTML=`<span class="badge">${market}</span><div class="t">${HZ.esc(name)}</div>${area?`<div class="a">${HZ.esc(area)}</div>`:''}${price?`<div class="pr">${HZ.esc(price)}</div>`:''}<div class="meta">${beds}${size}${dev}</div>${wa}`;
  log.appendChild(d); log.scrollTop=log.scrollHeight;
}
function typing(){
  const log=document.getElementById('hzCpLog');
  const t=document.createElement('div'); t.className='typing'; t.innerHTML='<i></i><i></i><i></i>';
  log.appendChild(t); log.scrollTop=log.scrollHeight; return t;
}
function renderChips(){
  const box=document.getElementById('hzCpChips'); if(!box) return; box.innerHTML='';
  if(chat.history.length>0) return; // only show on a fresh chat
  const chips = HZ.lang==='ar'
    ? [['🔑','عايز أشتري'],['🏠','عايز أأجّر'],['📍','مشاريع في التجمع الخامس']]
    : [['🔑','I want to buy'],['🏠','I want to rent'],['📍','Projects in New Cairo']];
  chips.forEach(([ic,txt])=>{ const b=document.createElement('button'); b.textContent=ic+' '+txt; b.onclick=()=>sendMsg(txt); box.appendChild(b); });
}
function renderChat(){
  const log=document.getElementById('hzCpLog'); if(!log) return; log.innerHTML='';
  chat.history.forEach(m=> addMsg(m.content, m.role==='user'?'me':'bot'));
  renderCtx(); renderChips();
}
function seedGreeting(){
  if(chat.greeted || chat.history.length) return;
  chat.greeted=true;
  const g = HZ.lang==='ar'
    ? 'أهلاً بيك! أنا Homzy، مستشارك العقاري 👋 عشان أوصلك لأنسب وحدة بالظبط، هسألك كام سؤال سريع — بتدوّر على إيجار ولا تمليك؟'
    : "Hi! I'm Homzy, your property advisor 👋 To find the perfect fit, I'll ask you a few quick questions — are you looking to rent or buy?";
  addMsg(g,'bot');
  renderChips();
}

async function sendMsg(text){
  text=(text||'').trim(); if(!text) return;
  const input=document.getElementById('hzCpInput'), send=document.getElementById('hzCpSend');
  document.getElementById('hzCpChips').innerHTML='';
  addMsg(text,'me'); chat.history.push({role:'user',content:text});
  captureLead(text);
  input.value=''; send.disabled=true; saveChat();
  const t=typing();
  const body={ session_id:chat.sessionId, message:text, history:chat.history };
  if(chat.context) body.context = chat.context;
  const finish=(reply,done)=>{
    chat.history.push({role:'assistant',content:reply});
    if(done){
      if(done.requirements) chat.req=done.requirements;
      const rec=(done.recommendations&&done.recommendations[0])||done.recommendation;
      if(rec) addRec(rec);
    }
    saveChat();
  };
  try{
    const r=await fetch('/api/chat/stream',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
    if(!r.ok||!r.body) throw new Error('no stream');
    const reader=r.body.getReader(), dec=new TextDecoder();
    let buf='', reply='', bubble=null, done=null;
    for(;;){
      const {value,done:d}=await reader.read(); if(d) break;
      buf+=dec.decode(value,{stream:true});
      let nl;
      while((nl=buf.indexOf('\n'))>=0){
        const line=buf.slice(0,nl).trim(); buf=buf.slice(nl+1);
        if(!line) continue;
        let evt; try{ evt=JSON.parse(line); }catch(e){ continue; }
        if(evt.type==='token'){
          if(!bubble){ if(t.parentNode)t.remove(); bubble=addMsg('','bot'); }
          reply+=evt.text; bubble.textContent=reply;
          bubble.style.direction=isAr(reply)?'rtl':'ltr'; bubble.style.textAlign=isAr(reply)?'right':'left';
          const log=document.getElementById('hzCpLog'); log.scrollTop=log.scrollHeight;
        } else if(evt.type==='done'){ done=evt; }
      }
    }
    if(t.parentNode) t.remove();
    if(reply===''){ throw new Error('empty stream'); }   // fall back below
    finish(reply, done);
  }catch(e){
    // Fallback to the non-streaming endpoint (e.g. host buffered the stream).
    try{
      const r2=await fetch('/api/chat',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
      const data=await r2.json(); if(t.parentNode) t.remove();
      const reply=data.reply||'(no reply)'; addMsg(reply,'bot'); finish(reply, data);
    }catch(e2){
      if(t.parentNode) t.remove();
      addMsg(HZ.lang==='ar'?'في مشكلة في الاتصال — حاول تاني بعد شوية.':'Connection issue — please try again.','bot');
    }
  }finally{ send.disabled=false; input.focus(); }
}

/* Heuristic lead capture from the client's own messages. */
function captureLead(text){
  const phone=(text.match(/(\+?2?01[0-9]{9})|(\b01[0-9]{9}\b)/)||[])[0];
  if(phone) chat.lead.phone=phone.replace(/\s/g,'');
  const nmeq=text.match(/(?:اسمي|انا اسمي|أنا اسمي|my name is|i am|i'm)\s+([^\d,،.\n]{2,30})/i);
  if(nmeq && !chat.lead.name){
    // stop before "and my number / phone" style tails.
    let nm=nmeq[1].trim().replace(/\s*(و?رقمي?|و?نمبر|ومعا?يا|and my|number|phone).*$/i,'').trim();
    if(nm.length>=2) chat.lead.name=nm;
  }
}

HZ.openChat = function(opts){
  opts=opts||{};
  // The advisor is a gated feature too — send guests to log in first, then come
  // straight back (the homepage is the only place a guest can be).
  if(!HZ.isLoggedIn()){ location.href='/login?next='+encodeURIComponent(location.pathname+location.search); return; }
  buildChat();
  // A project context resets to a focused conversation about that project.
  if(opts.context){
    chat.context=opts.context;
    // if starting fresh or switching project, seed a project-scoped opener
    const c=opts.context;
    if(chat.context) chat.greeted=true;
  }
  const panel=document.getElementById('hzChatPanel'), fab=document.getElementById('hzChatFab');
  panel.classList.add('open'); fab.style.display='none'; panel.dir=HZ.lang==='ar'?'rtl':'ltr';
  document.getElementById('hzCpSub').textContent=HZ.t('advisor');
  renderChat();
  if(!chat.history.length && !opts.context) seedGreeting();
  saveChat();
  const doPrefill = opts.prefill || (opts.context ? projectOpener(opts.context) : null);
  if(doPrefill && !opts._silent){ setTimeout(()=>sendMsg(doPrefill), 250); }
  else document.getElementById('hzCpInput').focus();
};
function projectOpener(c){
  return HZ.lang==='ar'
    ? `أنا مهتم بمشروع «${c.name}»${c.area?(' في '+c.area):''}. ممكن تفاصيله وتساعدني أعرف لو مناسب ليا؟`
    : `I'm interested in "${c.name}"${c.area?(' in '+c.area):''}. Can you tell me about it and whether it fits me?`;
}
HZ.toggleChat = function(){
  buildChat();
  const panel=document.getElementById('hzChatPanel'), fab=document.getElementById('hzChatFab');
  if(panel.classList.contains('open')){ panel.classList.remove('open'); fab.style.display='flex'; }
  else HZ.openChat();
};

/* Lead persistence to Supabase (best-effort; table added server-side). */
let leadTimer=null;
HZ.saveLead=function(){
  if(!chat || chat.history.length<2) return;
  clearTimeout(leadTimer);
  leadTimer=setTimeout(async ()=>{
    try{
      await HZ.sb('/rpc/upsert_web_lead',{
        method:'POST',
        headers:{apikey:SB_KEY,Authorization:'Bearer '+SB_KEY,'Content-Type':'application/json'},
        body:JSON.stringify({
          p_session_id: chat.sessionId,
          p_name: chat.lead.name||null,
          p_phone: chat.lead.phone||null,
          p_context: chat.context ? (chat.context.name+(chat.context.area?(' · '+chat.context.area):'')) : null,
          p_messages: chat.history,
          p_lang: HZ.lang,
          p_req: chat.req || null
        })
      });
    }catch(e){ /* best-effort; ignore */ }
  }, 1500);
};

/* ---------- broker-account gate ----------
   The client/broker switch shows ONLY for a signed-in broker account. We read
   the Supabase session token (stored by supabase-js on the /leads page) and
   check profiles.role — no second GoTrue client needed. */
async function checkBrokerAccount(){
  try{
    const key=Object.keys(localStorage).find(k=>/sb-.*-auth-token/.test(k));
    const tok=key?JSON.parse(localStorage.getItem(key)):null;
    const jwt=tok&&tok.access_token, uid=tok&&tok.user&&tok.user.id;
    if(!jwt||!uid) return notBroker();
    const r=await fetch(SB_URL+'/rest/v1/profiles?select=role&id=eq.'+uid,
      {headers:{apikey:SB_KEY, Authorization:'Bearer '+jwt}});
    if(!r.ok) return notBroker();
    const rows=await r.json();
    if(rows&&rows[0]&&rows[0].role==='broker'){ document.body.classList.add('hz-broker'); HZ.isBroker=true; }
    else notBroker();
  }catch(e){ notBroker(); }
}
function notBroker(){ document.body.classList.remove('hz-broker'); HZ.isBroker=false; if(HZ.mode!=='client') HZ.setMode('client'); }

/* ---------- boot ---------- */
function boot(){
  if(!chat) chat=newChatState();
  document.body.setAttribute('data-mode', HZ.mode);
  buildHeader(); buildFooter(); buildChat(); buildTabbar();
  HZ.setMode(HZ.mode);
  HZ.applyLang();
  checkBrokerAccount();
}
if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot); else boot();
})();
