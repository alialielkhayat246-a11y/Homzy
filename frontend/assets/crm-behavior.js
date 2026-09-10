/* Marketplace activity is shared only after the signed-in customer accepts an invite. */
(()=>{
  const tr=(ar,en)=>HZ.lang==='en'?en:ar;
  let enabled=false;
  HZ.trackBehavior=async(kind,listing=null,meta={})=>{
    if(!enabled)return;
    const s=HZ.session();if(!s)return;
    try{await HZ.sbAuth('/rpc/crm_track_behavior',s.token,'POST',{p_kind:kind,p_listing:listing,p_meta:meta});}catch{/* Telemetry must not interrupt browsing. */}
  };
  async function boot(){
    const s=HZ.session();
    const invitation=new URLSearchParams(location.search).get('crm_consent');
    if(!s){if(invitation){const banner=document.createElement('p');banner.style.cssText='padding:18px;text-align:center';const link=document.createElement('a');link.href='/login?next='+encodeURIComponent(location.pathname+location.search);link.textContent=tr('سجّل الدخول لمراجعة دعوة مشاركة النشاط','Sign in to review your activity-sharing invitation');banner.append(link);document.body.prepend(banner);}return;}
    let links=[];
    try{links=await HZ.sbAuth('/crm_behavior_links?actor_id=eq.'+s.uid+'&revoked_at=is.null&accepted_at=not.is.null&select=id',s.token)||[];}catch{return;}
    enabled=links.length>0;
    if(enabled){const banner=document.createElement('div');banner.className='sales-card';banner.style.cssText='padding:12px;margin:12px auto;max-width:1100px;background:#eef4fb;border-radius:12px';banner.textContent=tr('أنت تشارك نشاط البحث والعقارات مع البروكر بإذنك. ','You are sharing search and property activity with your broker. ');const revoke=document.createElement('button');revoke.textContent=tr('إيقاف المشاركة','Stop sharing');revoke.onclick=async()=>{revoke.disabled=true;try{for(const link of links)await HZ.sbAuth('/rpc/crm_revoke_behavior',s.token,'POST',{p_link:link.id});enabled=false;banner.remove();}catch{revoke.disabled=false;revoke.textContent=tr('تعذّر الإيقاف — حاول تاني','Could not stop sharing — retry');}};banner.append(revoke);document.body.prepend(banner);}
    if(!invitation||!/^[0-9a-f-]{36}$/i.test(invitation))return;
    const dialog=document.createElement('dialog');dialog.style.cssText='max-width:480px;width:90vw;border:1px solid #ddd;border-radius:16px;padding:24px';dialog.dir=HZ.lang==='en'?'ltr':'rtl';
    const title=document.createElement('h2');title.textContent=tr('مشاركة نشاطك مع البروكر','Share activity with your broker');
    const text=document.createElement('p');text.textContent=tr('لو وافقت، البروكر صاحب الدعوة هيشوف مشاهداتك للعقارات والبحث وتفاعلاتك للمساعدة في الترشيحات. تقدر توقف المشاركة في أي وقت. وافق فقط لو تعرف صاحب الدعوة.','If you agree, the inviting broker can see your property views, searches and interactions to improve recommendations. You can stop sharing at any time. Accept only if you recognize the person who sent this invitation.');
    const accept=document.createElement('button');accept.textContent=tr('أوافق على المشاركة','I agree to share');const cancel=document.createElement('button');cancel.textContent=tr('لا، شكرًا','No, thanks');cancel.onclick=()=>dialog.remove();
    accept.onclick=async()=>{accept.disabled=true;try{await HZ.sbAuth('/rpc/crm_accept_behavior',s.token,'POST',{p_invite:invitation});location.href='/app';}catch{accept.disabled=false;text.textContent=tr('الدعوة انتهت أو غير متاحة.','Invitation expired or unavailable.');}};
    dialog.append(title,text,accept,cancel);document.body.append(dialog);dialog.showModal();
  }
  boot();
})();
