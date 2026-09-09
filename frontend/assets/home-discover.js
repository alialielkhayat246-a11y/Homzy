(() => {
  const paths=['M12 3v18 M3 12h18 M5 5l14 14 M19 5 5 19','M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3Z M9 3v15 M15 6v15',null,'M4 7h16v14H4Z M8 7V3h8v4 M4 12h16','M7 2h10v20H7Z M11 18h2','M3 3h18v14H8l-5 4Z M7 8h10 M7 12h6'];
  document.querySelectorAll('.xcard .fic').forEach((el,i)=>el.innerHTML=HZ.catalog.icon(paths[i]||undefined));
  const badge=document.querySelector('.hero .eyebrow');
  if(badge?.firstChild?.nodeType===3)badge.firstChild.textContent='';
  badge?.insertAdjacentHTML('afterbegin',HZ.catalog.icon());
  let projects=[];
  function render(){
    if(!projects.length)return;
    const ar=HZ.lang==='ar', esc=HZ.esc;
    document.getElementById('homeProjects').innerHTML=projects.map(p=>`<a class="home-project" href="/app?project=${encodeURIComponent(p.id)}"><img loading="lazy" src="${esc(p.cover_image_url)}" alt="${esc(ar?(p.name_ar||p.name):p.name)}"><div class="copy"><h3>${esc(ar?(p.name_ar||p.name):p.name)}</h3><p>${esc(HZ.catalog.area(p.area))}</p>${p.price_from_min!=null?`<b>${ar?'يبدأ من':'From'} ${Number(p.price_from_min).toLocaleString(ar?'ar-EG':'en-US')} ${ar?'ج.م':'EGP'}</b>`:''}<p>${ar?'عرض المشروع ←':'Explore project →'}</p></div></a>`).join('');
    const areas=[...new Set(projects.map(p=>p.area).filter(Boolean))];
    document.getElementById('homeAreas').innerHTML=areas.map(area=>`<a href="/app?area=${encodeURIComponent(area)}">${esc(HZ.catalog.area(area))} ${ar?'←':'→'}</a>`).join('');
    document.getElementById('homeDiscover').hidden=false;
  }
  HZ.rpc('search_projects',{p_q:null,p_areas:null,p_min:null,p_max:null,p_beds:null,p_ready:null,p_sort:'recent',p_limit:12,p_offset:0}).then(rows=>{
    // Prefer different areas, always using real catalog images and prices.
    const candidates=(rows||[]).filter(p=>p.cover_image_url), seen=new Set();
    for(const p of candidates){if(!seen.has(p.area)){projects.push(p);seen.add(p.area);}if(projects.length===3)break;}
    for(const p of candidates){if(projects.length===3)break;if(!projects.includes(p))projects.push(p);}
    render();
  }).catch(()=>{});
  document.addEventListener('hz:lang',render);
})();
