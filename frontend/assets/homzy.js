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

// The signed-in user's Supabase session (token + id), read from the token that
// supabase-js persists in localStorage. Null when logged out.
HZ.session = function(){
  try{
    const k = Object.keys(localStorage).find(x=>/sb-.*-auth-token/.test(x));
    const t = k ? JSON.parse(localStorage.getItem(k)) : null;
    if(t && t.access_token && (!t.expires_at || t.expires_at*1000 > Date.now()))
      return { token:t.access_token, uid:(t.user&&t.user.id)||null };
  }catch(e){}
  return null;
};
// PostgREST call carrying the USER's JWT (so RLS applies to their own rows).
HZ.sbAuth = async function(path, token, method, body, extra){
  const h = {apikey:SB_KEY, Authorization:'Bearer '+(token||SB_KEY), 'Content-Type':'application/json'};
  if(extra) Object.assign(h, extra);
  const r = await fetch(SB_URL+'/rest/v1'+path, {method:method||'GET', headers:h, body:body?JSON.stringify(body):undefined});
  if(!r.ok) throw new Error('sb '+r.status);
  const t = await r.text();
  return t ? JSON.parse(t) : null;
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
  sell:{ar:'اعرض وحدتك',en:'List your unit'}, clients:{ar:'عملائي',en:'My clients'},
  disclaimer:{ar:'Homzy ممكن يغلط — راجع المعلومات المهمة قبل أي قرار.',en:'Homzy can make mistakes — verify important info before deciding.'},
  chatAbout:{ar:'بنتكلم عن',en:'Talking about'}, newChat:{ar:'محادثة جديدة',en:'New chat'}, close:{ar:'إغلاق',en:'Close'},
  leads:{ar:'الليدز',en:'Leads'}, mylistings:{ar:'وحداتي',en:'My units'},
  stays:{ar:'إقامات Homzy',en:'Homzy Stays'},
  hosting:{ar:'الاستضافة',en:'Hosting'},
  pricing:{ar:'الباقات والأسعار',en:'Pricing'},
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
  buildNavLinks(); refreshTabbar();
  document.dispatchEvent(new CustomEvent('hz:mode', {detail:m}));
};

/* ---------- Header / nav ---------- */
const NAV = {
  client:[['/','home'],['/areas','areas'],['/stays','stays'],['/app','browse'],['/download','app']],
  broker:[['/','home'],['/clients','clients'],['/my-listings','mylistings'],['/host/properties','hosting'],['/app','browse']],
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
          <a href="/stays">${HZ.t('stays')}</a><a href="/features">${HZ.t('features')}</a>
          <a href="/areas">${HZ.t('areas')}</a><a href="/app">${HZ.t('browse')}</a><a href="/download">${HZ.t('app')}</a>
        </div>
        <div class="hz-foot-col">
          <h4>${HZ.t('forBrokers')}</h4>
          <a href="/sell">${HZ.t('sell')}</a><a href="/my-listings">${HZ.t('mylistings')}</a><a href="/leads">${HZ.t('leads')}</a><a href="/pricing">${HZ.t('pricing')}</a>
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
  stays:'<svg viewBox="0 0 24 24" fill="none"><path d="M3 18v-6a2 2 0 0 1 2-2h10a4 4 0 0 1 4 4v4M3 18h18M3 18v2m18-2v2M7 10V8a2 2 0 0 1 2-2h2" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  clients:'<svg viewBox="0 0 24 24" fill="none"><circle cx="9" cy="8" r="3.2" stroke="currentColor" stroke-width="1.8"/><path d="M3.5 20a5.5 5.5 0 0 1 11 0M16 6.2a3 3 0 0 1 0 5.6M17.5 20a5.5 5.5 0 0 0-2-4.2" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  mylistings:'<svg viewBox="0 0 24 24" fill="none"><rect x="4" y="3" width="16" height="18" rx="2" stroke="currentColor" stroke-width="1.8"/><path d="M8 8h8M8 12h8M8 16h5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  hosting:'<svg viewBox="0 0 24 24" fill="none"><circle cx="8" cy="15" r="3.6" stroke="currentColor" stroke-width="1.8"/><path d="M10.6 12.4 20 3M17 6l2 2M15 8l1.6 1.6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  more:'<svg viewBox="0 0 24 24" fill="none"><circle cx="5" cy="12" r="1.7" fill="currentColor"/><circle cx="12" cy="12" r="1.7" fill="currentColor"/><circle cx="19" cy="12" r="1.7" fill="currentColor"/></svg>',
};
const TAB_T={home:{ar:'الرئيسية',en:'Home'},browse:{ar:'تصفّح',en:'Browse'},chat:{ar:'الشات',en:'Chat'},areas:{ar:'المناطق',en:'Areas'},stays:{ar:'إقامات',en:'Stays'},hosting:{ar:'استضافة',en:'Hosting'},clients:{ar:'عملائي',en:'Clients'},mylistings:{ar:'وحداتي',en:'Units'},more:{ar:'المزيد',en:'More'}};
function tt(k){return (TAB_T[k]||{})[HZ.lang]||HZ.t(k);}
function tabActive(k){
  const path=location.pathname;
  if(k==='home') return path==='/';
  if(k==='browse') return /^\/(app|browse|projects)/.test(path);
  if(k==='stays') return /^\/(stays|my-stays)/.test(path);
  if(k==='hosting') return path.startsWith('/host');
  if(k==='clients') return path.startsWith('/clients');
  if(k==='mylistings') return path.startsWith('/my-listings');
  return false;
}
function buildTabbar(){
  if(document.getElementById('hzTabbar')) return;
  const broker = HZ.isBroker && HZ.mode==='broker';
  const link=(href,k)=>`<a href="${href}" class="${tabActive(k)?'on':''}">${ICON[k]||ICON.browse}<span>${tt(k)}</span></a>`;
  const bar=document.createElement('nav'); bar.className='hz-tabbar'; bar.id='hzTabbar';
  const left  = broker ? link('/','home')+link('/clients','clients') : link('/','home')+link('/app','browse');
  const right = broker ? link('/my-listings','mylistings') : link('/stays','stays');
  bar.innerHTML = left
    + `<button class="tb-chat" onclick="HZ.openChat()"><span class="tb-chat-ic">${ICON.chat}</span><span>${tt('chat')}</span></button>`
    + right
    + `<button onclick="HZ.toggleMore()">${ICON.more}<span>${tt('more')}</span></button>`;
  document.body.appendChild(bar);
  // "More" sheet — mode-aware so every destination is reachable on mobile
  const bk=document.createElement('div'); bk.className='hz-sheet-bk'; bk.id='hzSheetBk'; bk.onclick=()=>HZ.toggleMore();
  const sheet=document.createElement('div'); sheet.className='hz-sheet'; sheet.id='hzSheet';
  const items = broker
    ? [['/host/properties','🏠','hosting'],['/pricing','💎','pricing'],['/stays','🛎️','stays'],['/leads','🎯','leads'],['/app','🔍','browse'],['/areas','📍','areas'],['/admin','⚙️','admin']]
    : [['/areas','📍','areas'],['/features','✨','features'],['/leads','🎯','leads'],['/brokers','🧰','forBrokers'],['/download','📱','app'],['/admin','⚙️','admin']];
  sheet.innerHTML='<div class="handle"></div>'+items.map(([h,i,k])=>`<a href="${h}"><span class="ic">${i}</span><span>${HZ.t(k)}</span></a>`).join('');
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
    <form class="cp-form" id="hzCpForm"><button type="button" class="cp-mic" id="hzCpMic" title="صوت" aria-label="voice">🎤</button><input id="hzCpInput" autocomplete="off"/><button type="submit" id="hzCpSend"><svg width="18" height="18" viewBox="0 0 24 24"><path d="M3.4 20.4 21 12 3.4 3.6 3.4 10.2 15 12 3.4 13.8Z" fill="currentColor"/></svg></button></form>`;
  document.body.appendChild(fab); document.body.appendChild(panel);
  document.getElementById('hzCpClose').onclick=()=>HZ.toggleChat();
  document.getElementById('hzCpNew').onclick=()=>{ chat=newChatState(); saveChat(); renderChat(); seedGreeting(); };
  document.getElementById('hzCpForm').addEventListener('submit',e=>{e.preventDefault(); sendMsg(document.getElementById('hzCpInput').value);});
  document.getElementById('hzCpMic').onclick=toggleChatVoice;
  document.getElementById('hzCpSub').textContent=HZ.t('advisor');
}

/* ---------- Voice input for the chat (Web Speech API) ---------- */
let CHAT_REC=null, CHAT_VOICE_ON=false;
function chatMicUI(on){ const b=document.getElementById('hzCpMic'); if(b){ b.classList.toggle('rec',on); b.textContent=on?'⏹':'🎤'; } }
function toggleChatVoice(){
  if(CHAT_VOICE_ON){ CHAT_VOICE_ON=false; try{CHAT_REC&&CHAT_REC.stop();}catch(e){} return; }
  const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
  const input=document.getElementById('hzCpInput');
  if(!SR){ input.placeholder=HZ.lang==='ar'?'المتصفح ده مش بيدعم الصوت — جرّب Chrome':'Voice not supported — try Chrome'; return; }
  CHAT_REC=new SR(); CHAT_REC.lang=HZ.lang==='ar'?'ar-EG':'en-US'; CHAT_REC.interimResults=true; CHAT_REC.continuous=false;
  const base=input.value?input.value+' ':'';
  CHAT_REC.onresult=(e)=>{ let t=''; for(let i=0;i<e.results.length;i++) t+=e.results[i][0].transcript; input.value=base+t; };
  CHAT_REC.onerror=()=>{ CHAT_VOICE_ON=false; chatMicUI(false); };
  CHAT_REC.onend=()=>{ CHAT_VOICE_ON=false; chatMicUI(false); input.focus(); };
  try{ CHAT_REC.start(); CHAT_VOICE_ON=true; chatMicUI(true); }catch(e){ CHAT_VOICE_ON=false; chatMicUI(false); }
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
  // Broker sales tool: generate a branded PDF offer for the client.
  if(HZ.isBroker && HZ.mode==='broker'){
    const b=document.createElement('button'); b.className='rec-pdf';
    b.textContent='📄 '+(ar?'اعمل عرض PDF':'Make a PDF offer');
    b.onclick=()=>HZ.makeOffer(rec, b);
    d.appendChild(b);
  }
  log.appendChild(d);
  // Client sales-handoff CTA: offer to have a sales rep contact them (once).
  if(!(HZ.isBroker && HZ.mode==='broker') && !chat.contactRequested){
    const cb=document.createElement('button'); cb.className='rec-contact';
    cb.textContent=(HZ.lang==='ar'?'✅ عايز حد من المبيعات يتواصل معايا':'✅ Have a sales rep contact me');
    cb.onclick=()=>HZ.requestContact(cb);
    log.appendChild(cb);
  }
  log.scrollTop=log.scrollHeight;
}
HZ.requestContact = async function(btn){
  const ar=HZ.lang==='ar', s=HZ.session();
  if(!s){ location.href='/login?next='+encodeURIComponent(location.pathname); return; }
  if(btn){ btn.disabled=true; btn.textContent=ar?'بنبعت طلبك…':'Sending…'; }
  let prof={}; try{ prof=(await HZ.sbAuth('/profiles?select=full_name,phone&id=eq.'+s.uid, s.token))[0]||{}; }catch(e){}
  let name=prof.full_name||chat.lead.name||null;
  let phone=prof.phone||chat.lead.phone||null;
  if(!phone){
    phone=((prompt(ar?'اكتب رقم موبايلك عشان فريق المبيعات يتواصل معاك:':'Your phone so sales can reach you:')||'').trim())||null;
    if(!phone){ if(btn){ btn.disabled=false; btn.textContent=ar?'✅ عايز حد من المبيعات يتواصل معايا':'✅ Have a sales rep contact me'; } return; }
    chat.lead.phone=phone;
  }
  const ctx = chat.context ? (chat.context.name+(chat.context.area?(' · '+chat.context.area):'')) : null;
  const lastMsg=(chat.history.slice(-1)[0]||{}).content||'';
  const hdr={apikey:SB_KEY,Authorization:'Bearer '+SB_KEY,'Content-Type':'application/json'};
  try{ await HZ.sb('/rpc/upsert_web_lead',{method:'POST',headers:hdr,body:JSON.stringify({p_session_id:chat.sessionId,p_name:name,p_phone:phone,p_context:ctx,p_messages:chat.history,p_lang:HZ.lang,p_req:chat.req||null})}); }catch(e){}
  try{ await HZ.sb('/rpc/mark_web_lead_contact',{method:'POST',headers:hdr,body:JSON.stringify({p_session_id:chat.sessionId})}); }catch(e){}
  try{ await fetch('/api/lead-contact',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:s.token, context:ctx, message:lastMsg, lang:HZ.lang})}); }catch(e){}
  chat.contactRequested=true; saveChat();
  if(btn){ btn.textContent=ar?'✅ اتبعت — هنتواصل معاك':"✅ Sent — we'll contact you"; }
  addMsg(ar?'تمام! ✅ سجّلت طلبك، وفريق المبيعات هيتواصل معاك في أقرب وقت على رقمك المسجّل. تحب أساعدك في حاجة تانية؟':"Done! ✅ Our sales team will reach out shortly on your registered number. Anything else?",'bot');
};
async function _toDataURL(url){
  if(!url) return '';
  try{ const r=await fetch(url); if(!r.ok) return ''; const bl=await r.blob();
    return await new Promise(res=>{ const fr=new FileReader(); fr.onload=()=>res(fr.result); fr.onerror=()=>res(''); fr.readAsDataURL(bl); }); }
  catch(e){ return ''; }
}
HZ.loadHtml2pdf = function(){
  if(window.html2pdf) return Promise.resolve();
  return new Promise((res,rej)=>{ const s=document.createElement('script');
    s.src='https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.2/html2pdf.bundle.min.js';
    s.onload=res; s.onerror=rej; document.head.appendChild(s); });
};
HZ.makeOffer = async function(rec, btn, clientName){
  const ar=HZ.lang==='ar';
  if(!HZ.PLAN) await HZ.loadPlan();
  if(!HZ.hasFeature('branded_pdf')){
    if(confirm(ar?'عروض PDF بالبراند ميزة في باقة Pro. تحب تشوف الباقات وتبدأ تجربة مجانية؟':'Branded PDF offers are a Pro feature. See plans and start a free trial?')) location.href='/pricing';
    return;
  }
  const old = btn && btn.textContent; if(btn){ btn.disabled=true; btn.textContent=ar?'بيتجهّز…':'Preparing…'; }
  try{
    // broker profile (logo/name/phone)
    let prof={}; const s=HZ.session();
    if(s){ try{ prof=(await HZ.sbAuth('/profiles?select=full_name,company,phone,company_logo_url&id=eq.'+s.uid, s.token))[0]||{}; }catch(e){} }
    // AI advantages
    let adv=[];
    try{ const r=await fetch('/api/offer',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({unit:rec, language:HZ.lang})}); if(r.ok) adv=(await r.json()).advantages||[]; }catch(e){}
    const nameAr=rec.compound_ar||rec.compound||'';
    const nameEn=(rec.compound&&rec.compound!==nameAr)?rec.compound:'';
    const areaAr=rec.area_ar||rec.area||'';
    const areaEn=(rec.area&&rec.area!==areaAr)?rec.area:'';
    const price=rec.price_ar||rec.price_en||'';
    const company=prof.company||prof.full_name||'', phone=prof.phone||'';
    const [logo,cover]=await Promise.all([_toDataURL(prof.company_logo_url), _toDataURL(rec.cover_image)]);
    const fact=(l,v)=> v?`<div class="of-fact"><span>${l}</span><b>${HZ.esc(v)}</b></div>`:'';
    const CSS=`
      @page{size:A4;margin:0;}
      *{box-sizing:border-box;-webkit-print-color-adjust:exact;print-color-adjust:exact;}
      body{margin:0;font-family:"Cairo",Arial,sans-serif;color:#14212E;}
      .of-top{background:#0B1D36;color:#fff;padding:26px 34px;display:flex;align-items:center;gap:16px;}
      .of-top .lg{width:70px;height:70px;border-radius:12px;background:#fff center/contain no-repeat;flex:none;}
      .of-top .co{font-size:22px;font-weight:800;line-height:1.25;}
      .of-top .by{margin-inline-start:auto;text-align:end;font-size:12px;opacity:.85;}
      .of-title{padding:24px 34px 6px;} .of-title .k{color:#0B5563;font-weight:800;font-size:13px;letter-spacing:1px;}
      .of-title h1{font-size:30px;color:#0B1D36;margin:6px 0 2px;}
      .of-title .en{color:#0B5563;font-size:17px;font-family:"Poppins",Arial,sans-serif;font-weight:700;direction:ltr;}
      .of-title .loc{color:#66717F;font-size:15px;margin-top:5px;}
      .of-cover{height:250px;margin:14px 34px;border-radius:16px;background:#e9e2da center/cover no-repeat;}
      .of-price{margin:0 34px;color:#0B5563;font-weight:800;font-size:24px;}
      .of-facts{display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px;padding:16px 34px;}
      .of-fact{background:#F7F3EC;border:1px solid #E6DDCF;border-radius:12px;padding:11px 13px;}
      .of-fact span{display:block;color:#66717F;font-size:12px;} .of-fact b{color:#0B1D36;font-size:15px;}
      .of-adv{padding:8px 34px 18px;} .of-adv h2{font-size:18px;color:#0B1D36;margin:0 0 10px;}
      .of-adv ul{margin:0;padding:0;list-style:none;} .of-adv li{padding:8px 0;border-bottom:1px dashed #E6DDCF;font-size:15px;color:#40506a;}
      .of-adv li::before{content:'✔ ';color:#0B5563;font-weight:800;}
      .of-contact{margin:6px 34px 0;background:linear-gradient(135deg,#0B5563,#08414C);color:#fff;border-radius:16px;padding:20px 24px;display:flex;align-items:center;gap:16px;}
      .of-contact .who{flex:1;} .of-contact .nm{font-size:20px;font-weight:800;} .of-contact .lbl{font-size:12px;opacity:.85;}
      .of-contact .ph{font-size:26px;font-weight:800;direction:ltr;font-family:"Poppins",Arial,sans-serif;}
      .of-foot{padding:16px 34px 26px;color:#9aa;font-size:12px;text-align:center;}`;
    const BODY=`
      <div class="of-top">
        ${logo?`<div class="lg" style="background-image:url('${logo}')"></div>`:''}
        <div class="co">${HZ.esc(company||'عرض عقاري')}</div>
        <div class="by">مقدّم عبر<br><b>Homzy</b></div>
      </div>
      <div class="of-title">
        <div class="k">عرض عقاري · Property Offer</div>
        <h1>${HZ.esc(nameAr)}</h1>
        ${nameEn?`<div class="en">${HZ.esc(nameEn)}</div>`:''}
        ${(areaAr||areaEn)?`<div class="loc">${HZ.esc(areaAr)}${(areaAr&&areaEn)?' · ':''}${HZ.esc(areaEn)}</div>`:''}
        ${clientName?`<div class="loc" style="color:#0B5563;font-weight:800;margin-top:6px">عرض خاص لـ ${HZ.esc(clientName)}</div>`:''}
      </div>
      ${cover?`<div class="of-cover" style="background-image:url('${cover}')"></div>`:''}
      ${price?`<div class="of-price">${HZ.esc(price)}</div>`:''}
      <div class="of-facts">
        ${fact('المطوّر',rec.developer)}
        ${fact('الغرف',rec.bedrooms!=null?(rec.bedrooms+' غرف'):'')}
        ${fact('المساحة',rec.size_sqm?(rec.size_sqm+' م²'):'')}
        ${fact('المقدم',rec.down_payment)}
        ${fact('التقسيط',rec.installment_years?(rec.installment_years+' سنة'):'')}
        ${fact('التسليم',rec.delivery)}
      </div>
      ${adv.length?`<div class="of-adv"><h2>المزايا</h2><ul>${adv.map(a=>`<li>${HZ.esc(a)}</li>`).join('')}</ul></div>`:''}
      <div class="of-contact">
        <div class="who"><div class="lbl">للتواصل والمعاينة</div><div class="nm">${HZ.esc(company||'—')}</div></div>
        ${phone?`<div class="ph">${HZ.esc(phone)}</div>`:''}
      </div>
      <div class="of-foot">تم إنشاء هذا العرض عبر Homzy — homzy-ai.com · الأسعار والتفاصيل قابلة للتأكيد.</div>`;
    const docHtml='<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">'
      +'<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
      +'<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800;900&family=Poppins:wght@700;800&display=swap" rel="stylesheet">'
      +'<title>عرض Homzy</title><style>'+CSS+'</style></head><body>'+BODY+'</body></html>';
    // Print via a hidden iframe: the BROWSER renders Arabic natively (correct
    // letter-shaping + spacing, unlike html2canvas). Broker picks "Save as PDF".
    const ifr=document.createElement('iframe');
    ifr.style.cssText='position:fixed;right:0;bottom:0;width:0;height:0;border:0;';
    document.body.appendChild(ifr);
    const idoc=ifr.contentWindow.document; idoc.open(); idoc.write(docHtml); idoc.close();
    try{ await ifr.contentWindow.document.fonts.ready; }catch(e){}
    await new Promise(r=>setTimeout(r,450));
    ifr.contentWindow.focus(); ifr.contentWindow.print();
    ifr.contentWindow.onafterprint=()=>{ try{ifr.remove();}catch(e){} };
    setTimeout(()=>{ try{ifr.remove();}catch(e){} }, 120000);
  }catch(e){ alert(ar?'تعذّر إنشاء العرض، جرّب تاني.':'Could not create the offer.'); }
  finally{ if(btn){ btn.disabled=false; btn.textContent=old; } }
};
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
  const brokerMode = HZ.isBroker && HZ.mode==='broker';
  const g = brokerMode
    ? (HZ.lang==='ar'
        ? 'أهلاً كابتن 👋 أنا مساعد المبيعات بتاعك. قولّي عميلك عايز إيه (منطقة، ميزانية، عدد غرف) وأنا أرشّحلك أنسب وحدة، وأديك نقاط بيع تقنعه بيها — وفي الآخر أعملك عرض PDF باسمك تبعتهوله.'
        : "Hey captain 👋 I'm your sales assistant. Tell me what your client wants (area, budget, bedrooms) and I'll pick the best unit, give you selling points to close them, and generate a branded PDF offer to send.")
    : (HZ.lang==='ar'
        ? 'أهلاً بيك! أنا Homzy، مستشارك العقاري 👋 عشان أوصلك لأنسب وحدة بالظبط، هسألك كام سؤال سريع — بتدوّر على إيجار ولا تمليك؟'
        : "Hi! I'm Homzy, your property advisor 👋 To find the perfect fit, I'll ask you a few quick questions — are you looking to rent or buy?");
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
  if(HZ.isBroker && HZ.mode==='broker') body.mode='broker';   // sales-coach persona
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
    if(rows&&rows[0]&&rows[0].role==='broker'){ document.body.classList.add('hz-broker'); HZ.isBroker=true; refreshTabbar(); HZ.loadPlan(); }
    else notBroker();
  }catch(e){ notBroker(); }
}
function notBroker(){ document.body.classList.remove('hz-broker'); HZ.isBroker=false; if(HZ.mode!=='client') HZ.setMode('client'); }

/* ---------- Subscription plan (feature gating) ---------- */
HZ.PLAN = null; // plan_limits row for the signed-in user (or free defaults)
HZ.hasFeature = (f)=> !!(HZ.PLAN && HZ.PLAN.features && HZ.PLAN.features[f]);
HZ.loadPlan = async function(){
  const s = HZ.session();
  if(!s){ HZ.PLAN = {plan:'free', features:{}, max_listings:3, max_clients:25, leads_included:0}; return HZ.PLAN; }
  try{
    const cp = await HZ.rpc('current_plan', {p_uid:s.uid});   // scalar text
    const plan = (typeof cp==='string') ? cp : ((cp&&cp[0])||'free');
    const rows = await HZ.sb('/plan_limits?plan=eq.'+plan+'&select=*');
    HZ.PLAN = (rows&&rows[0]) ? rows[0] : {plan:'free', features:{}};
  }catch(e){ HZ.PLAN = {plan:'free', features:{}}; }
  document.dispatchEvent(new CustomEvent('hz:plan', {detail:HZ.PLAN}));
  return HZ.PLAN;
};

/* ---------- Paymob payments ---------- */
HZ.payEnabled = null;
HZ.checkPay = async function(){
  if(HZ.payEnabled!==null) return HZ.payEnabled;
  try{ const j = await (await fetch('/api/pay/config')).json(); HZ.payEnabled = !!j.enabled; }
  catch(e){ HZ.payEnabled = false; }
  return HZ.payEnabled;
};
// Start a hosted Paymob checkout for {kind: booking|subscription|wallet}. Redirects on success.
HZ.pay = async function(kind, ref){
  const s = HZ.session();
  if(!s){ location.href='/login?next='+encodeURIComponent(location.pathname); return {ok:false}; }
  let r;
  try{ r = await (await fetch('/api/pay/create',{method:'POST',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({token:s.token, kind, ref})})).json(); }
  catch(e){ r = {ok:false, error:'network'}; }
  if(r && r.ok && r.checkout_url){ location.href = r.checkout_url; return r; }
  return r || {ok:false};
};

/* Reveal-on-scroll for any .reveal element — global, so every page animates in
   (and pages without their own observer, e.g. /areas, don't get stuck hidden). */
HZ.initReveal = function(){
  try{
    const els = document.querySelectorAll('.reveal:not(.in)');
    if(!els.length) return;
    if(!('IntersectionObserver' in window)){ els.forEach(e=>e.classList.add('in')); return; }
    const io = new IntersectionObserver((ents)=>{
      ents.forEach(en=>{ if(en.isIntersecting){ en.target.classList.add('in'); io.unobserve(en.target); } });
    }, { threshold:0.08, rootMargin:'0px 0px -40px 0px' });
    els.forEach(e=>io.observe(e));
    // safety net: if anything is still hidden after 1.2s (observer missed it), show it
    setTimeout(()=>document.querySelectorAll('.reveal:not(.in)').forEach(e=>{
      if(e.getBoundingClientRect().top < innerHeight) e.classList.add('in');
    }), 1200);
  }catch(e){ document.querySelectorAll('.reveal').forEach(e=>e.classList.add('in')); }
};

/* ---------- boot ---------- */
function boot(){
  if(!chat) chat=newChatState();
  document.body.setAttribute('data-mode', HZ.mode);
  buildHeader(); buildFooter(); buildChat(); buildTabbar();
  HZ.setMode(HZ.mode);
  HZ.applyLang();
  checkBrokerAccount();
  HZ.initReveal();
}
if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot); else boot();
})();
