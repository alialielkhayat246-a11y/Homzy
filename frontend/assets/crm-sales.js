/* Progressive extension of clients.html, using its refreshed Supabase session. */
export function installSalesWorkspace({session, reload}) {
  const tr=(ar,en)=>HZ.lang==='en'?en:ar;
  const esc=HZ.esc;
  const labels={purpose:['شراء / إيجار','Buy / Rent'],category:['الفئة','Category'],locations:['المناطق (بفاصلة)','Locations (comma separated)'],type:['نوع العقار','Property type'],bedrooms:['غرف النوم','Bedrooms'],bathrooms:['الحمامات','Bathrooms'],area_min:['أقل مساحة م²','Minimum area m²'],area_max:['أكبر مساحة م²','Maximum area m²'],budget_min:['أقل ميزانية EGP','Minimum budget EGP'],budget_max:['أقصى ميزانية EGP','Maximum budget EGP'],down_payment:['المقدم المتاح EGP','Available down payment EGP'],installment_years:['سنوات التقسيط','Installment years'],delivery:['التسليم','Delivery'],developers:['المطورون (بفاصلة)','Developers (comma separated)'],finishing:['التشطيب','Finishing'],location:['الموقع','Location'],budget:['الميزانية','Budget'],size:['المساحة','Area'],developer:['المطور','Developer']};
  const label=k=>labels[k]?tr(...labels[k]):k;
  Object.assign(labels,{
    total_leads:['إجمالي العملاء','Total leads'],new_leads:['عملاء جدد','New leads'],hot_leads:['عملاء ساخنون','Hot leads'],active_deals:['صفقات نشطة','Active deals'],closed_deals:['صفقات مكسوبة','Closed won'],lost_deals:['صفقات خاسرة','Closed lost'],pipeline_value:['قيمة الصفقات EGP','Pipeline value EGP'],weighted_pipeline_value:['القيمة المرجحة EGP','Weighted pipeline EGP'],conversion_rate:['نسبة التحويل %','Conversion rate %'],overdue_tasks:['مهام متأخرة','Overdue tasks'],followup_completion:['إتمام المهام %','Task completion %'],followups_today:['متابعات اليوم','Follow-ups today'],overdue_followups:['متابعات متأخرة','Overdue follow-ups'],meetings_today:['مقابلات اليوم','Meetings today'],offers_sent:['عملاء بمرحلة العرض','Leads at offer stage'],budget_clarity:['ميزانية واضحة','Clear budget'],location_clarity:['موقع محدد','Location specified'],financing_clarity:['مقدم محدد','Down payment specified'],recent_activity:['نشاط حديث','Recent activity'],viewed:['مشاهدات مسجلة','Recorded views'],saved:['عقارات محفوظة','Saved properties'],search:['نشاط البحث','Search activity'],inquiry:['استفسارات','Inquiries'],response:['ردود العميل','Client responses'],viewing_attended:['معاينات تمت','Attended viewings'],offer_requested:['طلب عرض','Offer requested']
  });
  const numeric=new Set(['bedrooms','bathrooms','area_min','area_max','budget_min','budget_max','down_payment','installment_years']);
  Object.assign(labels,{hot_lead:['عميل ساخن','Hot lead'],new_lead:['عميل جديد','New lead'],followup_due:['موعد متابعة','Follow-up due'],meeting_today:['مقابلة اليوم','Meeting today'],deal_attention:['صفقة تحتاج متابعة','Deal needs attention'],overdue:['متأخر','Overdue'],high:['عالية','High'],medium:['متوسطة','Medium'],low:['منخفضة','Low'],hot:['ساخن','Hot'],warm:['دافئ','Warm'],cold:['بارد','Cold'],new:['جديد','New'],contact:['تم التواصل','Contacted'],matching:['مطابقة عقارات','Property matching'],viewing:['معاينة','Viewing'],offer_sent:['عرض مرسل','Offer sent'],negotiate:['تفاوض','Negotiation'],reservation:['حجز','Reservation'],lost:['خسارة','Lost']});
  Object.assign(labels,{leads:['العملاء','Leads'],contacts:['التواصل','Contacts'],qualified:['المؤهلون','Qualified'],meetings:['المعاينات المكتملة','Completed viewings'],offers:['العروض','Offers'],negotiations:['التفاوض','Negotiations'],closed:['الإغلاق','Closed']});
  Object.assign(labels,{area:['الموقع','Location'],project:['المشروع','Project'],size_sqm:['المساحة م²','Area m²'],price:['السعر','Price'],currency:['العملة','Currency'],down_payment_amount:['قيمة المقدم','Down payment amount'],amenities:['المرافق','Amenities']});
  const arrays=new Set(['locations','developers']);
  let state=null, leadId=null, revision=0, activeTab='copilot';
  const dialog=document.createElement('dialog'); dialog.className='sales-dialog';
  dialog.setAttribute('aria-labelledby','sales-title'); document.body.append(dialog);
  const css=document.createElement('link');css.rel='stylesheet';css.href='/assets/crm-sales.css';document.head.append(css);
  async function request(path,options={}){
    const s=await session();
    const response=await fetch('/api/crm/sales'+path,{...options,headers:{'Content-Type':'application/json',Authorization:'Bearer '+s.token},signal:AbortSignal.timeout(60000)});
    let data;try{data=await response.json();}catch{throw Error(tr('استجابة غير صالحة','Invalid server response'));}
    if(!response.ok)throw Error(typeof data.detail==='string'?data.detail:tr('راجع البيانات وحاول تاني','Check the fields and retry'));
    return data;
  }
  const post=(path,body)=>request(path,{method:'POST',body:JSON.stringify(body)});
  function message(text,error=false){const node=dialog.querySelector('#sales-status');if(node){node.textContent=text;node.className=error?'sales-error':'sales-muted';}}
  async function run(button,fn){button.disabled=true;message('');try{await fn();}catch(e){message(e.message,true);}finally{button.disabled=false;}}
  const fmt=v=>v==null?'—':typeof v==='object'?JSON.stringify(v):String(v);
  const money=v=>v==null?'—':Number(v).toLocaleString(HZ.lang==='en'?'en-US':'ar-EG')+' EGP';
  const card=(title,body)=>`<section class="sales-card"><h3>${esc(title)}</h3>${body}</section>`;
  const evidence=m=>`<ul class="sales-evidence">${(m.evidence||[]).map(x=>`<li class="${x.status}">${esc(label(x.criterion))}: ${x.status==='matched'?tr('مطابق','Matches'):x.status==='unknown'?tr('بيانات ناقصة','Missing data'):tr('غير مطابق','Does not match')}</li>`).join('')}</ul>`;
  function projectCard(m,compact=false){
    const p=m.project||{},u=m.unit||{},name=m.display_name||p.name_ar||p.name||tr('مشروع','Project');
    const facts=[p.area,p.developer_name,u.type,u.bedrooms!=null?(u.bedrooms+' '+tr('غرف','beds')):null,u.price_from!=null?tr('من ','From ')+money(u.price_from):null,u.down_payment?tr('مقدم ','Down payment ')+u.down_payment:null,u.installment_years?u.installment_years+' '+tr('سنوات تقسيط','installment years'):null].filter(Boolean);
    return card(name,`<div class="sales-project-head"><div class="sales-score">${m.score}%</div><div><strong>${esc(m.fit_summary||'')}</strong><p>${facts.map(esc).join(' · ')}</p><small class="sales-muted">${tr('اكتمال بيانات المقارنة','Comparison data coverage')}: ${m.coverage}%</small></div></div>${compact?'':evidence(m)}${p.id?`<a class="sales-project-link" href="/app?project=${encodeURIComponent(p.id)}">${tr('فتح المشروع ومراجعة التوافر','Open project and review availability')}</a>`:''}`);
  }
  function shell(title){
    dialog.dir=HZ.lang==='en'?'ltr':'rtl';dialog.lang=HZ.lang==='en'?'en':'ar';
    dialog.innerHTML=`<header><h2 id="sales-title">${esc(title)}</h2><button id="sales-close" aria-label="${tr('إغلاق','Close')}">✕</button></header><div class="sales-body"><p id="sales-status" role="status" aria-live="polite"></p><div id="sales-nav"></div><div id="sales-content"></div></div>`;
    dialog.querySelector('#sales-close').onclick=()=>dialog.close();if(!dialog.open)dialog.showModal();
  }
  window.openSales=async id=>{
    const current=++revision;leadId=id;state=null;shell(tr('مساعد مبيعات Homzy','Homzy Sales Copilot'));message(tr('جاري التحميل…','Loading…'));
    try{const data=await request(`/clients/${id}/copilot?language=${HZ.lang==='en'?'en':'ar'}`);if(current!==revision)return;state=data;message('');renderNav();renderTab();
      const offerId=new URLSearchParams(location.search).get('offer');
      if(offerId){const offers=await request(`/clients/${id}/offers`);if(current!==revision)return;const offer=offers.find(o=>o.id===offerId);if(offer)preview(offer);}
    }
    catch(e){if(current===revision)message(e.message,true);}
  };
  function renderNav(){
    dialog.querySelector('#sales-title').textContent=state.client.name+' · Homzy';
    const tabs=[['copilot','المساعد','Copilot'],['profile','الاحتياجات','Requirements'],['matches','المطابقة','Matches'],['message','الرسائل','Messages'],['tasks','المتابعة','Follow-up'],['timeline','النشاط','Activity'],['offers','العروض','Offers']];
    dialog.querySelector('#sales-nav').innerHTML='<nav class="sales-tabs">'+tabs.map(([key,ar,en])=>`<button data-tab="${key}" aria-selected="${activeTab===key}">${tr(ar,en)}</button>`).join('')+'</nav>';
    dialog.querySelectorAll('[data-tab]').forEach(button=>button.onclick=()=>{activeTab=button.dataset.tab;message('');renderNav();renderTab();});
    const invite=document.createElement('button');invite.textContent=tr('إنشاء دعوة موافقة لمشاركة نشاط السوق','Create marketplace activity consent invite');
    dialog.querySelector('#sales-nav').append(invite);
    invite.onclick=()=>run(invite,async()=>{const result=await post(`/clients/${leadId}/behavior-invite`,{});const url=location.origin+'/app?crm_consent='+result.invite;message(tr('أرسل الرابط للعميل للمراجعة والموافقة: ','Send this link to the client to review and consent: ')+url);try{await navigator.clipboard.writeText(url);}catch{/* The visible URL remains available to copy manually. */}});
  }
  const content=()=>dialog.querySelector('#sales-content');
  function renderTab(){
    if(activeTab==='profile')return renderProfile();if(activeTab==='matches')return renderMatches();if(activeTab==='message')return renderMessage();if(activeTab==='tasks')return renderTasks();if(activeTab==='offers')return renderOffers();
    if(activeTab==='timeline'){
      content().innerHTML=card(tr('آخر ٢٠٠ نشاط','Latest 200 activities'),`<ol class="sales-timeline">${state.activities.map(a=>`<li><strong>${esc(a.kind)}</strong> · <time>${esc(new Date(a.created_at).toLocaleString())}</time><p>${esc(a.body||'')}</p></li>`).join('')||tr('لا يوجد نشاط مسجّل','No recorded activity')}</ol>`);return;
    }
    const s=state.lead_score;
    const projects=state.project_matches||[];
    content().innerHTML=card(tr('ملخص العميل','Client summary'),`<p>${esc(state.summary)}</p>`)+`<div class="sales-grid">`+card(tr('درجة اهتمام استرشادية','Indicative intent score'),`<div class="sales-score">${s.score}/100</div><p>${esc(label(s.temperature))}</p><ul>${s.signals.map(x=>`<li>${esc(label(x.signal))} +${x.points}${x.count?' ('+x.count+')':''}</li>`).join('')}</ul><p class="sales-muted">${tr('آخر ٣٠ يومًا من النشاط المسجّل. ليست نسبة احتمال إتمام الصفقة.','Last 30 days of recorded activity. This is not a closing probability.')}</p>`)+card(tr('الخطوة التالية','Next best action'),`<p>${esc(state.next_best_action)}</p><p>${esc(state.followup_recommendation)}</p><p>${state.missing_information.map(label).map(esc).join(' · ')}</p>${state.risks.map(r=>`<p>${esc(r)}</p>`).join('')}`)+`</div>`+card(tr('أفضل مشروعات للعميل','Best-fit projects for this client'),projects.slice(0,3).map(m=>projectCard(m,true)).join('')||tr('لا توجد مشروعات مناسبة للبيانات المحفوظة حاليًا. راجع الاحتياجات أو المخزون.','No projects currently fit the saved requirements. Review the requirements or inventory.'))+`<p class="sales-muted">${tr('الترشيحات تستخدم بيانات العميل المحفوظة وبيانات المشروعات الفعلية. أكّد السعر والتوافر قبل العرض.','Recommendations use the saved client profile and recorded project data. Confirm price and availability before presenting.')}</p>`;
  }
  function field(key,value){
    const val=Array.isArray(value)?value.join(', '):value??'';
    const options=key==='purpose'?[['','—'],['sale',tr('شراء','Buy')],['rent',tr('إيجار','Rent')]]:key==='category'?[['','—'],['residential',tr('سكني','Residential')],['commercial',tr('تجاري','Commercial')]]:null;
    return `<label class="sales-field">${esc(label(key))}${options?`<select name="${key}">${options.map(([v,l])=>`<option value="${v}" ${v===val?'selected':''}>${l}</option>`).join('')}</select>`:`<input name="${key}" value="${esc(String(val))}" ${numeric.has(key)?'type="number" min="0" step="any"':'maxlength="500"'}>`}</label>`;
  }
  function readRequirements(form){const req={};for(const key of Object.keys(state.requirements).concat(Object.keys(labels)).filter((v,i,a)=>a.indexOf(v)===i)){const input=form.elements.namedItem(key);if(!input)continue;const value=input.value.trim();if(value)req[key]=arrays.has(key)?value.split(/[,،]/).map(s=>s.trim()).filter(Boolean):numeric.has(key)?Number(value):value;}return req;}
  function renderProfile(){
    const contact=state.client.custom?.sales_contact||{};
    const keys=['purpose','category','locations','type','bedrooms','bathrooms','area_min','area_max','budget_min','budget_max','down_payment','installment_years','delivery','developers','finishing'];
    content().innerHTML=card(tr('استخراج الاحتياجات','Extract requirements'),`<label class="sales-field">${tr('الصق كلام العميل بالعربي أو الإنجليزي','Paste the client’s Arabic or English text')}<textarea id="sales-extract" maxlength="4000"></textarea></label><button id="sales-parse">${tr('تحليل ومراجعة','Extract and review')}</button><div id="sales-review"></div>`)+`<form id="sales-profile"><div class="sales-grid">${keys.map(k=>field(k,state.requirements[k])).join('')}<label class="sales-field">Email<input type="email" name="email" maxlength="254" value="${esc(contact.email||'')}"></label><label class="sales-field">WhatsApp<input name="whatsapp" maxlength="30" value="${esc(contact.whatsapp||state.client.phone||'')}"></label></div><div class="sales-actions"><button class="sales-primary">${tr('حفظ البيانات بعد المراجعة','Save reviewed profile')}</button></div></form>`;
    const form=dialog.querySelector('#sales-profile');
    content().insertAdjacentHTML('afterbegin',card(tr('بيانات العميل','Client details'),`<div class="sales-grid"><p>${tr('الهاتف','Phone')}: ${esc(state.client.phone||'—')}</p><p>${tr('المصدر','Source')}: ${esc(state.client.source||'—')}</p><p>${tr('البروكر المسؤول','Assigned broker')}: ${esc(state.broker?.full_name||'—')}</p><p>${tr('المرحلة','Stage')}: ${esc(label(state.client.stage||'new'))}</p><p>${tr('آخر نشاط مسجّل','Last recorded activity')}: ${esc(state.client.last_activity||'—')}</p><p>${tr('المتابعة القادمة','Next follow-up')}: ${esc(state.client.next_followup||'—')}</p><p>${tr('تاريخ الإضافة','Created')}: ${esc(state.client.created_at||'—')}</p><p>${tr('ملاحظات','Notes')}: ${esc(state.client.notes||'—')}</p></div>`));
    dialog.querySelector('#sales-parse').onclick=e=>run(e.target,async()=>{
      const draft=await post('/extract',{text:dialog.querySelector('#sales-extract').value});
      const entries=Object.entries(draft.requirements).filter(([,v])=>v!==null&&(!Array.isArray(v)||v.length));
      const review=dialog.querySelector('#sales-review');review.innerHTML=`<p>${tr('اختار الحقول التي تريد تطبيقها على النموذج. لن يتم الحفظ تلقائيًا.','Select fields to apply to the form. Nothing is saved automatically.')} (${esc(draft.engine)})</p>`+entries.map(([key,value],i)=>`<label class="sales-card" style="display:block"><input type="checkbox" data-extracted="${i}"> ${esc(label(key))}: ${esc(fmt(state.requirements[key]))} → ${esc(fmt(value))}</label>`).join('')+`<button type="button" id="sales-apply">${tr('تطبيق المحدد على النموذج','Apply selected to form')}</button>`;
      review.querySelector('#sales-apply').onclick=()=>{review.querySelectorAll('input:checked').forEach(input=>{const [key,value]=entries[Number(input.dataset.extracted)];const el=form.elements.namedItem(key);if(el)el.value=Array.isArray(value)?value.join(', '):value;});message(tr('راجع النموذج ثم احفظ','Review the form, then save'));};
    });
    form.onsubmit=e=>{e.preventDefault();run(form.querySelector('button'),async()=>{
      await request(`/clients/${leadId}/profile`,{method:'PUT',body:JSON.stringify({requirements:readRequirements(form),email:form.elements.email.value,whatsapp:form.elements.whatsapp.value,expected_updated_at:state.client.updated_at})});
      await reload();await window.openSales(leadId);message(tr('تم الحفظ','Saved'));
    });};
  }
  function renderMatches(){
    const projects=state.project_matches||[],matches=state.matches||[];
    const projectWarning=state.catalog_limited?`<p class="sales-error">${tr('نتائج المشروعات محدودة بأول ٥ آلاف نوع وحدة','Project results limited to the first 5,000 unit types')}</p>`:'';
    const projectSection=card(tr('مشروعات المطورين المطابقة للاحتياجات المحفوظة','Developer projects matched to saved requirements'),projectWarning+(projects.map(m=>projectCard(m)).join('')||tr('لا توجد مشروعات مطابقة حاليًا.','No matching projects currently.')));
    const listingSection=card(tr('وحدات السوق المسجلة','Recorded marketplace listings'),matches.map((m,i)=>card(m.property.title||'Homzy',`<label><input type="checkbox" data-match="${i}"> ${tr('إضافة للعرض','Add to offer')}</label><div class="sales-score">${m.score}%</div><p>${esc(m.property.area||'—')} · ${esc(fmt(m.property.price))} ${esc(m.property.currency||'EGP')}</p><p class="sales-muted">${tr('اكتمال بيانات المقارنة','Comparison data coverage')}: ${m.coverage}%</p>${evidence(m)}`)).join('')||tr('لا توجد وحدات سوق مسجلة مطابقة.','No matching marketplace listings are recorded.'));
    content().innerHTML=`<p>${tr('النتائج مرتبة باستخدام كل الاحتياجات المحفوظة. البيانات الناقصة تقلل درجة المطابقة.','Results are ranked using all saved requirements. Missing catalog details reduce the match score.')}</p>${state.inventory_limited?'<p class="sales-error">'+tr('نتائج السوق محدودة بأول ١٠ آلاف وحدة','Marketplace results limited to the first 10,000 listings')+'</p>':''}`+projectSection+listingSection+(matches.length?`<button id="sales-offer" class="sales-primary">${tr('إنشاء عرض من وحدات السوق ومعاينته','Create and preview a marketplace offer')}</button>`:'');
    const offerButton=dialog.querySelector('#sales-offer');if(!offerButton)return;
    offerButton.onclick=e=>run(e.target,async()=>{
      if(!HZ.PLAN&&HZ.loadPlan)await HZ.loadPlan();
      if(HZ.hasFeature&&!HZ.hasFeature('branded_pdf'))throw Error(tr('عروض PDF تتطلب باقة Pro','PDF offers require Pro'));
      const ids=[...dialog.querySelectorAll('[data-match]:checked')].map(x=>state.matches[Number(x.dataset.match)].property.id);
      if(!ids.length||ids.length>8)throw Error(tr('اختار من ١ إلى ٨ وحدات','Select 1–8 properties'));
      const offer=await post(`/clients/${leadId}/offers`,{listing_ids:ids,language:HZ.lang==='en'?'en':'ar'});preview(offer);
    });
  }
  function renderMessage(){
    const select=(name,entries)=>`<label class="sales-field">${esc(name)}<select id="sales-${name}">${entries.map(([v,ar,en])=>`<option value="${v}">${tr(ar,en)}</option>`).join('')}</select></label>`;
    content().innerHTML=`<div class="sales-grid">`+select('language',[['ar','العربية','Arabic'],['en','الإنجليزية','English']])+select('channel',[['whatsapp','واتساب','WhatsApp'],['phone','نص مكالمة','Phone script'],['email','بريد إلكتروني','Email']])+select('occasion',[['initial','تواصل أول','Initial contact'],['followup','متابعة','Follow-up'],['property','ترشيح عقار','Property recommendation'],['meeting','تأكيد مقابلة','Meeting confirmation'],['post_meeting','بعد المقابلة','Post-meeting'],['offer','متابعة عرض','Offer follow-up'],['reengagement','إعادة التواصل','Re-engagement']])+select('tone',[['professional','احترافي','Professional'],['friendly','ودّي','Friendly'],['short','مختصر','Short'],['persuasive','مقنع','Persuasive']])+`</div><div class="sales-actions"><button id="sales-draft">${tr('إنشاء مسودة','Generate draft')}</button><button id="sales-copy">${tr('نسخ النص بعد المراجعة','Copy reviewed text')}</button></div><textarea id="sales-message" aria-label="${tr('مسودة قابلة للتعديل','Editable draft')}"></textarea><p class="sales-muted">${tr('لن يتم إرسال أي رسالة تلقائيًا.','No message is sent automatically.')}</p>`;
    dialog.querySelector('#sales-language').value=HZ.lang==='en'?'en':'ar';
    dialog.querySelector('#sales-draft').onclick=e=>run(e.target,async()=>{const body={};for(const k of ['language','channel','occasion','tone'])body[k]=dialog.querySelector('#sales-'+k).value;const result=await post(`/clients/${leadId}/message`,body);dialog.querySelector('#sales-message').value=result.message;message(result.engine);});
    dialog.querySelector('#sales-copy').onclick=e=>run(e.target,async()=>{await navigator.clipboard.writeText(dialog.querySelector('#sales-message').value);message(tr('تم النسخ','Copied'));});
  }
  function renderTasks(){
    content().innerHTML=`<form id="sales-task" class="sales-grid"><label class="sales-field">${tr('النوع','Type')}<select name="kind">${[['call','مكالمة','Call'],['whatsapp','واتساب','WhatsApp'],['meeting','مقابلة','Meeting'],['email','بريد','Email'],['offer_followup','متابعة عرض','Offer follow-up'],['other','أخرى','Other']].map(([v,ar,en])=>`<option value="${v}">${tr(ar,en)}</option>`).join('')}</select></label><label class="sales-field">${tr('الموعد بالتوقيت المحلي','Due in your local time')}<input type="datetime-local" name="due" required></label><label class="sales-field">${tr('ملاحظات / عنوان','Notes / title')}<textarea name="title" maxlength="1000" required></textarea></label><label class="sales-field">${tr('الأولوية','Priority')}<select name="priority"><option>medium</option><option>high</option><option>low</option></select></label><button class="sales-primary">${tr('جدولة المتابعة','Schedule follow-up')}</button></form>`;
    const form=dialog.querySelector('form');
    form.querySelector('button').insertAdjacentHTML('beforebegin',`<label class="sales-field">${tr('تذكير داخل مساحة العمل','Workspace reminder')}<select name="reminder"><option value="0">${tr('في الموعد','At due time')}</option><option value="15">${tr('قبل ١٥ دقيقة','15 minutes before')}</option><option value="60">${tr('قبل ساعة','1 hour before')}</option><option value="1440">${tr('قبل يوم','1 day before')}</option></select></label>`);
    form.onsubmit=e=>{e.preventDefault();run(form.querySelector('button'),async()=>{await post(`/clients/${leadId}/followups`,{kind:form.elements.kind.value,title:form.elements.title.value,due_at:new Date(form.elements.due.value).toISOString(),priority:form.elements.priority.value,reminder_minutes:Number(form.elements.reminder.value),local_day:form.elements.due.value.slice(0,10)});await reload();message(tr('تمت الجدولة — تابعها من يومي','Scheduled — see My Day'));form.reset();});};
  }
  async function renderOffers(){
    const id=leadId;content().innerHTML=tr('جاري التحميل…','Loading…');
    try{const offers=await request(`/clients/${id}/offers`);if(leadId!==id||activeTab!=='offers')return;content().innerHTML=offers.map((o,i)=>card(new Date(o.created_at).toLocaleString(),`<p>${o.items.length} ${tr('وحدة','properties')}</p><button data-offer="${i}">${tr('معاينة / PDF','Preview / PDF')}</button>`)).join('')||tr('لا توجد عروض بعد','No offers yet');dialog.querySelectorAll('[data-offer]').forEach(b=>b.onclick=()=>preview(offers[Number(b.dataset.offer)]));}catch(e){message(e.message,true);}
  }
  function preview(offer){
    const ar=offer.language==='ar', t=(a,e)=>ar?a:e;
    const safeImage=url=>{try{const u=new URL(url);return u.protocol==='https:'?u.href:'';}catch{return '';}};
    const html=`<!doctype html><html lang="${ar?'ar':'en'}" dir="${ar?'rtl':'ltr'}"><head><meta charset="utf-8"><style>body{font:16px Arial,sans-serif;color:#0D1B2A;margin:30px;line-height:1.7}header{border-bottom:4px solid #2563EB;padding-bottom:20px}article{break-before:page}article:first-of-type{break-before:auto}img{max-width:100%;max-height:280px;object-fit:contain}dl{display:grid;grid-template-columns:1fr 2fr;gap:8px}dd{margin:0}footer{border-top:1px solid #ccc;font-size:12px}@page{size:A4;margin:16mm}@media print{body{margin:0}}</style></head><body><header><h1>Homzy</h1><h2>${t('عرض عقاري','Property proposal')}</h2><p>${esc(offer.client_name)}</p><small>${esc(new Date(offer.created_at).toLocaleDateString())} · ${esc(offer.id)}</small></header>${offer.items.map(p=>`<article><h2>${esc(p.title)}</h2>${(p.images||[]).slice(0,1).map(safeImage).filter(Boolean).map(url=>`<img src="${esc(url)}" alt="${esc(p.title)}">`).join('')}<dl>${['project','developer','area','type','size_sqm','bedrooms','bathrooms','price','currency','down_payment_amount','installment_years','delivery','finishing','amenities'].filter(k=>p[k]!=null).map(k=>`<dt>${esc(label(k))}</dt><dd>${esc(fmt(p[k]))}</dd>`).join('')}</dl></article>`).join('')}<footer>${t('الأسعار والتوافر وقت إعداد العرض، وتخضع للتأكيد.','Prices and availability are recorded at creation and subject to confirmation.')}</footer></body></html>`;
    content().innerHTML=`<div class="sales-actions"><button id="sales-print">${tr('طباعة / حفظ PDF','Print / Save PDF')}</button><button id="sales-link">${tr('نسخ رابط خاص بالبروكر','Copy broker-only link')}</button></div><iframe class="sales-preview" title="${tr('معاينة العرض','Offer preview')}"></iframe>`;
    const frame=content().querySelector('iframe');frame.srcdoc=html.replace('</header>',`<p>${esc([offer.broker_info?.name,offer.broker_info?.company,offer.broker_info?.phone].filter(Boolean).join(' · '))}</p></header>`);
    const share=document.createElement('button');share.textContent=tr('إنشاء رابط للعميل لمدة ٧ أيام','Create 7-day client share link');
    const revoke=document.createElement('button');revoke.textContent=tr('إلغاء روابط المشاركة','Revoke share links');
    content().querySelector('.sales-actions').append(share,revoke);
    share.onclick=()=>run(share,async()=>{
      const result=await post(`/offers/${offer.id}/share`,{});const url=location.origin+'/crm-offer?token='+result.token;
      const box=document.createElement('div');box.className='sales-card';
      box.innerHTML=`<p>${tr('الرابط يتضمن اسم العميل والعرض وبيانات تواصل البروكر.','This link contains the client’s name, offer and broker contact details.')}</p><input readonly aria-label="Share URL" value="${esc(url)}" style="width:100%"><button data-copy-share>${tr('نسخ الرابط','Copy link')}</button><a target="_blank" rel="noopener" href="https://wa.me/?text=${encodeURIComponent(url)}">WhatsApp</a>`;
      box.querySelector('[data-copy-share]').onclick=e=>run(e.target,async()=>{await navigator.clipboard.writeText(url);message(tr('تم النسخ','Copied'));});content().append(box);
    });
    revoke.onclick=()=>run(revoke,async()=>{await request(`/offers/${offer.id}/share`,{method:'DELETE'});message(tr('تم إلغاء جميع روابط هذا العرض','All share links for this offer were revoked'));});
    dialog.querySelector('#sales-print').onclick=e=>run(e.target,async()=>{await frame.contentDocument.fonts.ready;await Promise.all([...frame.contentDocument.images].map(img=>img.decode().catch(()=>{})));frame.contentWindow.focus();frame.contentWindow.print();});
    dialog.querySelector('#sales-link').onclick=e=>run(e.target,async()=>{await navigator.clipboard.writeText(location.origin+'/clients?lead='+leadId+'&offer='+offer.id);message(tr('رابط خاص يحتاج تسجيل دخول البروكر. أرسل ملف PDF للعميل.','This private link requires broker sign-in. Send the PDF file to your client.'));});
  }
  window.openSalesOverview=async()=>{
    ++revision;shell(tr('نظرة عامة على المبيعات','Sales overview'));message(tr('جاري التحميل…','Loading…'));
    try{const data=await request('/overview?offset='+new Date().getTimezoneOffset()+'&language='+(HZ.lang==='en'?'en':'ar'));message(data.limited?tr('مقاييس جزئية: حد ١٠٠٠ سجل لكل نوع','Partial metrics: 1,000 records per entity'):'');
      content().innerHTML=`<nav class="sales-actions"><a href="/my-day">${tr('مهام اليوم','Today’s tasks')}</a><a href="/deals">${tr('الصفقات','Deals')}</a><a href="/insights">${tr('التحليلات','Analytics')}</a><a href="/my-listings">${tr('المخزون','Inventory')}</a></nav><div class="sales-kpis">${Object.entries(data.kpis).map(([k,v])=>card(label(k),`<strong>${Number(v).toLocaleString()}</strong>`)).join('')}</div>`+card(tr('توصيات المتابعة','Follow-up recommendations'),data.insights.map(i=>`<p>${i.count}: ${i.key==='overdue_followups'?tr('متابعات متأخرة — راجع مهام اليوم','Overdue follow-ups — review My Day'):tr('عملاء بدون موعد متابعة — حدد الخطوة التالية','Clients without a follow-up — schedule the next step')}</p>`).join(''))+`<label class="sales-field">${tr('بحث العملاء والصفقات والعقارات المسجلة','Search clients, deals and recorded properties')}<input id="sales-search" type="search"></label><div id="sales-results"></div>`;
      if(data.ai_insight)content().insertAdjacentHTML('beforeend',card(tr('توصية الأداء','Performance recommendation'),`<p>${esc(data.ai_insight)}</p><small>${esc(data.engine)}</small>`));
      const leadList=rows=>rows.map(l=>`<p><button class="sales-lead-open" data-lead="${esc(l.id)}">${esc(l.name)} · ${l.lead_score??0}/100</button></p>`).join('')||'—';
      content().insertAdjacentHTML('beforeend',`<div class="sales-grid">`+card(tr('أحدث العملاء','Recent leads'),leadList([...data.leads].sort((a,b)=>(b.created_at||'').localeCompare(a.created_at||'')).slice(0,5)))+card(tr('عملاء ساخنون','Hot leads'),leadList(data.leads.filter(l=>['hot','very_hot'].includes(l.temperature)).slice(0,5)))+`</div>`+card(tr('آخر نشاط','Recent activity'),(data.recent_activity||[]).map(a=>`<p>${esc(label(a.kind))} · ${esc(a.body||'')} <small>${esc(a.created_at||'')}</small></p>`).join('')||'—'));
      dialog.querySelectorAll('.sales-lead-open').forEach(b=>b.onclick=()=>window.openSales(b.dataset.lead));
      if(data.performance){
        const p=data.performance;
        const names={first_recorded_contact_hours:['ساعات لأول تواصل مسجّل','Hours to first recorded contact'],contact_rate:['معدل التواصل %','Contact rate %'],meeting_conversion:['من التواصل لمعاينة مكتملة %','Contact to completed viewing %'],offer_conversion:['من معاينة لعرض %','Viewing to offer %'],closing_rate:['معدل الإغلاق %','Closing rate %'],average_deal_value:['متوسط الصفقة EGP','Average deal EGP'],average_sales_cycle_days:['متوسط دورة البيع بالأيام','Average sales cycle days'],followup_completion:['إنجاز المتابعات %','Follow-up completion %']};
        content().insertAdjacentHTML('beforeend',card(tr('كفاءة المبيعات','Sales efficiency'),`<div class="sales-kpis">${Object.entries(names).map(([k,n])=>card(tr(...n),`<strong>${esc(fmt(p[k]))}</strong>`)).join('')}</div><p class="sales-muted">${tr('تعتمد على النشاط المسجّل فقط. المراحل التي تم تخطيها لا يتم افتراضها.','Based on recorded history only. Skipped stages are not inferred.')}</p>`)+card(tr('مسار التحويل','Sales funnel'),Object.entries(p.funnel||{}).map(([key,value])=>`<p>${esc(label(key))} · ${value} <meter min="0" max="${Math.max(1,p.funnel.leads)}" value="${value}"></meter></p>`).join(''))+card(tr('أسباب الخسارة','Lost reasons'),Object.entries(p.lost_reasons||{}).map(([reason,count])=>`<p>${esc(reason)} · ${count}</p>`).join('')||'—'));
      }
      let dismissed=[];try{dismissed=JSON.parse(localStorage.getItem('hz_sales_dismissed')||'[]');}catch{/* invalid local state */}
      content().insertAdjacentHTML('beforeend',card(tr('تنبيهات تحتاج انتباهك','Notifications requiring attention'),(data.notifications||[]).filter(n=>!dismissed.includes(n.id)).map((n,i)=>`<div class="sales-card" data-notification="${i}"><strong>${esc(label(n.priority))} · ${esc(n.title||n.type)}</strong><p>${esc(label(n.type))}</p><button data-dismiss="${esc(n.id)}">${tr('تجاهل لليوم','Dismiss today')}</button></div>`).join('')||tr('لا توجد تنبيهات جديدة','No new notifications')));
      dialog.querySelectorAll('[data-dismiss]').forEach(b=>b.onclick=()=>{dismissed.push(b.dataset.dismiss);try{localStorage.setItem('hz_sales_dismissed',JSON.stringify(dismissed.slice(-200)));}catch{/* storage may be unavailable */}b.closest('[data-notification]').remove();});
      const search=dialog.querySelector('#sales-search');let timer,searchRevision=0;
      search.oninput=()=>{clearTimeout(timer);const current=++searchRevision,q=search.value.trim();const results=dialog.querySelector('#sales-results');results.textContent='';if(q.length<2)return;
        timer=setTimeout(async()=>{try{const rows=await request('/search?q='+encodeURIComponent(q));if(current!==searchRevision||!results.isConnected)return;
          results.innerHTML=rows.map(r=>r.kind==='client'?`<button data-lead="${esc(r.id)}">${esc(r.label)} · ${esc(r.detail||'')}</button>`:`<p>${esc(r.kind)} · ${esc(r.label)} · ${esc(r.detail||'')}</p>`).join('')||tr('لا توجد نتائج','No results');results.querySelectorAll('[data-lead]').forEach(b=>b.onclick=()=>window.openSales(b.dataset.lead));
        }catch(e){message(e.message,true);}},300);
      };
    }catch(e){message(e.message,true);}
  };
}
