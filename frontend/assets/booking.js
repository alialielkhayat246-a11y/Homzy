/* Homzy — viewing booking widget (unit page + "my bookings" reschedule).
   HZBook.mount(el, {listingId, mode:'book'|'reschedule', apptId, onDone})
   Days and slots come from the database (appt_open_days / appt_available_slots),
   which already applies the broker's hours, the owner's hours, blackouts, other
   bookings and the daily limit; booking itself is re-validated server-side. */
(function(){
const L=(ar,en)=>(window.HZ&&HZ.lang==='en')?en:ar;
const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const ERR={
  login_required:['سجّل دخولك الأول عشان تحجز.','Please log in to book.'],
  listing_unavailable:['الوحدة دي مش متاحة للحجز حالياً.','This property is not available for booking.'],
  own_listing:['دي وحدتك — مش هينفع تحجز معاينة لنفسك.','This is your own listing.'],
  name_required:['اكتب اسمك.','Enter your name.'],
  phone_invalid:['رقم الموبايل مش صحيح.','Invalid phone number.'],
  already_booked:['عندك طلب معاينة مفتوح للوحدة دي بالفعل — تابعه من «حجوزاتي».','You already have an open booking for this property.'],
  too_many_pending:['عندك 3 طلبات معاينة مستنية رد — استنى ردهم الأول.','You have 3 pending requests already.'],
  slot_taken:['الميعاد ده اتحجز لسه — اختار ميعاد تاني.','That time was just taken — pick another.'],
  daily_limit:['اليوم ده اتملى — اختار يوم تاني.','That day is fully booked — pick another day.'],
  broker_unavailable:['الميعاد ده برّه مواعيد البروكر.','Outside the broker\'s hours.'],
  owner_unavailable:['المالك مش متاح في الميعاد ده.','The owner is not available then.'],
  too_soon:['الميعاد قريب أوي — اختار ميعاد أبعد شوية.','Too soon — pick a later time.'],
  too_far:['الميعاد بعيد أوي.','Too far ahead.'],
  bad_status:['الحجز ده مايتعدّلش في حالته الحالية.','This booking can\'t be changed now.'],
  forbidden:['مش مسموح.','Not allowed.']
};
const errText=c=>{ const e=ERR[c]; return e?L(e[0],e[1]):L('حصل خطأ، جرّب تاني.','Something went wrong.'); };
const dayName=(d)=>new Date(d+'T12:00:00').toLocaleDateString(L('ar-EG','en-GB'),{weekday:'short'});
const dayNum=(d)=>new Date(d+'T12:00:00').toLocaleDateString(L('ar-EG','en-GB'),{day:'numeric',month:'short'});
const timeLbl=(iso)=>new Date(iso).toLocaleTimeString(L('ar-EG','en-GB'),{hour:'numeric',minute:'2-digit',timeZone:'Africa/Cairo'});
const fullLbl=(iso)=>new Date(iso).toLocaleString(L('ar-EG','en-GB'),{weekday:'long',day:'numeric',month:'long',hour:'numeric',minute:'2-digit',timeZone:'Africa/Cairo'});

const CSS=`.hzb{background:#fff;border:1px solid var(--line,#EBE5DE);border-radius:16px;padding:16px}
.hzb h3{margin:0 0 4px;font-size:17px;color:var(--navy,#0B1D36)} .hzb .sub{font-size:13px;color:#6b7686;margin-bottom:12px}
.hzb .days{display:flex;gap:8px;overflow-x:auto;padding-bottom:6px;scrollbar-width:thin}
.hzb .day{flex:none;min-width:64px;border:1.5px solid var(--line-2,#e2dad1);background:#fff;border-radius:12px;padding:8px 6px;text-align:center;cursor:pointer;font-family:inherit}
.hzb .day b{display:block;font-size:13px;color:var(--navy,#0B1D36)} .hzb .day small{font-size:12px;color:#6b7686}
.hzb .day.on{border-color:var(--teal,#0F766E);background:var(--teal,#0F766E)} .hzb .day.on b,.hzb .day.on small{color:#fff}
.hzb .day:disabled{opacity:.38;cursor:not-allowed}
.hzb .slots{display:flex;flex-wrap:wrap;gap:8px;margin:12px 0}
.hzb .slot{border:1.5px solid var(--line-2,#e2dad1);background:#fff;border-radius:10px;padding:8px 14px;font-weight:800;font-size:14px;cursor:pointer;font-family:inherit;color:var(--navy,#0B1D36)}
.hzb .slot.on{background:var(--navy,#0B1D36);border-color:var(--navy,#0B1D36);color:#fff}
.hzb .muted{font-size:13px;color:#6b7686;margin:10px 0}
.hzb input,.hzb textarea{width:100%;box-sizing:border-box;font-family:inherit;font-size:14px;padding:10px 12px;margin-bottom:8px;border:1.5px solid var(--line-2,#e2dad1);border-radius:10px}
.hzb .go{width:100%;margin-top:4px} .hzb .msg{margin-top:10px;font-weight:700;font-size:13.5px;line-height:1.6}
.hzb .msg.err{color:#B42318} .hzb .msg.ok{color:#137a3e}
.hzb .done{background:#E6F6EC;border-radius:12px;padding:14px;color:#0f5132;font-weight:700;line-height:1.7}`;

function api(fn,args){ const s=HZ.session(); return HZ.sbAuth('/rpc/'+fn, s?s.token:null, 'POST', args||{}); }

window.HZBook={ mount: async function(el,o){
  if(!document.getElementById('hzbCss')){ const st=document.createElement('style'); st.id='hzbCss'; st.textContent=CSS; document.head.appendChild(st); }
  const reschedule=o.mode==='reschedule';
  let DAY=null, SLOT=null;
  el.innerHTML=`<div class="hzb"><h3>📅 ${reschedule?L('اختار ميعاد جديد','Pick a new time'):L('احجز معاينة','Book a viewing')}</h3>
    <div class="sub">${L('اختار اليوم وبعدين الساعة — الظاهر هنا بس المواعيد المتاحة فعلاً.','Pick a day, then a time — only free times are shown.')}</div>
    <div class="days" data-r="days"><div class="muted">…</div></div><div data-r="slots"></div><div data-r="form"></div><div class="msg" data-r="msg"></div></div>`;
  const $=r=>el.querySelector('[data-r="'+r+'"]');
  const msg=(t,ok)=>{ const m=$('msg'); m.className='msg '+(ok?'ok':'err'); m.textContent=t||''; };
  let days=[]; try{ days=await HZ.rpc('appt_open_days',{p_listing:o.listingId,p_days:14})||[]; }catch(e){}
  if(!days.some(d=>d.slots>0)){ $('days').innerHTML=`<div class="muted">${L('مفيش مواعيد متاحة في الأسبوعين الجايين — تقدر تتواصل مع البروكر مباشرة.','No free times in the next two weeks — contact the broker directly.')}</div>`; return; }
  $('days').innerHTML=days.map(d=>`<button type="button" class="day" data-d="${d.day}" ${d.slots>0?'':'disabled'}><b>${esc(dayName(d.day))}</b><small>${esc(dayNum(d.day))}</small></button>`).join('');
  $('days').querySelectorAll('.day').forEach(b=>b.onclick=()=>pickDay(b.dataset.d));
  async function pickDay(d){
    DAY=d; SLOT=null; msg('');
    $('days').querySelectorAll('.day').forEach(b=>b.classList.toggle('on',b.dataset.d===d));
    $('slots').innerHTML='<div class="muted">…</div>'; $('form').innerHTML='';
    let s=[]; try{ s=await HZ.rpc('appt_available_slots',{p_listing:o.listingId,p_day:d})||[]; }catch(e){}
    if(!s.length){ $('slots').innerHTML=`<div class="muted">${L('اليوم ده اتملى — اختار يوم تاني.','This day just filled up — pick another.')}</div>`; return; }
    $('slots').innerHTML='<div class="slots">'+s.map(x=>`<button type="button" class="slot" data-s="${x.starts_at}">${esc(timeLbl(x.starts_at))}</button>`).join('')+'</div>';
    $('slots').querySelectorAll('.slot').forEach(b=>b.onclick=()=>pickSlot(b.dataset.s));
  }
  async function pickSlot(s){
    SLOT=s; msg('');
    $('slots').querySelectorAll('.slot').forEach(b=>b.classList.toggle('on',b.dataset.s===s));
    const sess=HZ.session();
    if(!sess && !reschedule){
      $('form').innerHTML=`<a class="btn btn-teal go" href="/login?next=${encodeURIComponent(location.pathname+location.search+'#book')}">${L('سجّل دخول عشان تأكّد الحجز','Log in to confirm')}</a>`; return; }
    if(reschedule){
      $('form').innerHTML=`<button type="button" class="btn btn-teal go" data-r="go">${L('غيّر الميعاد لـ','Move to')} ${esc(fullLbl(s))}</button>`;
    }else{
      let me={}; try{ me=(await HZ.sbAuth('/profiles?select=full_name,phone&id=eq.'+sess.uid, sess.token))[0]||{}; }catch(e){}
      $('form').innerHTML=`<div class="muted">${L('ميعادك','Your time')}: <b>${esc(fullLbl(s))}</b></div>
        <input data-r="name" placeholder="${L('اسمك','Your name')}" value="${esc(me.full_name||'')}">
        <input data-r="phone" type="tel" inputmode="tel" placeholder="${L('رقم موبايلك','Mobile number')}" value="${esc(me.phone||'')}">
        <textarea data-r="notes" rows="2" placeholder="${L('ملاحظة للبروكر (اختياري)','Note for the broker (optional)')}"></textarea>
        <button type="button" class="btn btn-teal go" data-r="go">${L('ابعت طلب الحجز','Send booking request')}</button>`;
    }
    $('go').onclick=submit;
  }
  async function submit(){
    const b=$('go'); b.disabled=true; msg('');
    try{
      const r= reschedule
        ? await api('appt_reschedule',{p_id:o.apptId,p_new_start:SLOT,p_reason:null})
        : await api('appt_book',{p_listing:o.listingId,p_starts_at:SLOT,p_name:$('name').value.trim(),p_phone:$('phone').value.trim(),p_notes:$('notes').value.trim()||null});
      if(!r||!r.ok){ msg(errText(r&&r.error)); b.disabled=false; if(r&&['slot_taken','daily_limit'].includes(r.error)&&DAY) pickDay(DAY); return; }
      if(reschedule){ el.innerHTML=`<div class="hzb"><div class="done">✅ ${L('اتغيّر الميعاد لـ','Moved to')} ${esc(fullLbl(SLOT))}${r.status==='pending'?'<br>'+L('مستني تأكيد البروكر.','Waiting for the broker to confirm.'):''}</div></div>`; }
      else{ el.innerHTML=`<div class="hzb"><div class="done">✅ ${L('وصل طلبك للبروكر','Your request was sent')} — ${esc(fullLbl(SLOT))}<br>
        ${L('الميعاد محجوز ليك لحد ما البروكر يأكّد (قبل','The time is held for you until the broker confirms (by')} ${esc(fullLbl(r.hold_expires_at))}).<br>
        <a href="/my-bookings" style="font-weight:800">${L('تابع حجوزاتك ←','Track your bookings →')}</a></div></div>`; }
      o.onDone&&o.onDone(r);
    }catch(e){ msg(errText()); b.disabled=false; }
  }
}};
})();
