/* Presentation helpers: keep source values intact for queries and matching. */
HZ.catalog = {
  area(value){
    const names={'new cairo':'القاهرة الجديدة','new capital':'العاصمة الإدارية الجديدة','new zayed':'زايد الجديدة','north coast':'الساحل الشمالي','6th of october':'٦ أكتوبر','6 october':'٦ أكتوبر','october 6':'٦ أكتوبر','sheikh zayed':'الشيخ زايد','zayed':'الشيخ زايد','mostakbal city':'مدينة المستقبل','ain sokhna':'العين السخنة','shorouk':'الشروق','shorouk city':'الشروق','october gardens':'حدائق أكتوبر','new obour':'العبور الجديدة','alexandria':'الإسكندرية','ras el hekma':'رأس الحكمة','new alamein':'العلمين الجديدة','hurghada':'الغردقة','zahraa el maadi':'زهراء المعادي','naser city':'مدينة نصر','nasr city':'مدينة نصر','soma bay':'سوما باي','el maadi':'المعادي','red sea':'البحر الأحمر','new heliopolis':'هليوبوليس الجديدة','ras sudar':'رأس سدر','galala':'الجلالة','sheraton':'شيراتون','el mokatam':'المقطم','6th settlement':'التجمع السادس','el gouna':'الجونة','new october':'أكتوبر الجديدة','sahl hasheesh':'سهل حشيش'};
    return HZ.lang==='ar'?(names[String(value||'').toLowerCase().trim()]||value||''):(value||'');
  },
  text(value){
    if(HZ.lang!=='ar') return value||'';
    const years=n=>+n===1?'سنة':+n===2?'سنتين':n+(+n<=10?' سنوات':' سنة');
    return String(value||'').replace(/after\s+(\d+)\s+years?/gi,(_,n)=>'خلال '+years(n)).replace(/ready to move/gi,'استلام فوري').replace(/off[ -]plan/gi,'تحت الإنشاء').replace(/fully finished/gi,'تشطيب كامل').replace(/semi[ -]finished/gi,'نصف تشطيب').replace(/core\s*&\s*shell/gi,'بدون تشطيب').replace(/(\d+)[ -]year installments/gi,(_,n)=>'تقسيط على '+years(n)).replace(/down payment/gi,'مقدم').replace(/delivery/gi,'التسليم').replace(/EGP/gi,'ج.م');
  },
  category(type){
    if(['office','administrative'].includes(type)) return 'office';
    if(['clinic','medical'].includes(type)) return 'medical';
    if(['shop','retail','commercial','store'].includes(type)) return 'commercial';
    if(['apartment','duplex','penthouse','studio','townhouse','twinhouse','villa','chalet'].includes(type)) return 'residential';
    return '';
  },
  icon(path='M3 10 12 3l9 7v11H3Z M9 21v-8h6v8'){
    return `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${path}"/></svg>`;
  }
};
