/* Browser integration checks use fixture data only; no production requests/writes. */
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..');
const lead='11111111-1111-4111-8111-111111111111';
const property='22222222-2222-4222-8222-222222222222';
const now='2026-09-09T10:00:00Z';
const profile={client:{id:lead,name:'أحمد Ahmed <script>alert(1)</script>',phone:'01000000000',updated_at:now},requirements:{purpose:'sale',locations:['New Cairo'],budget_max:12000000,bedrooms:3},activities:[{kind:'note',body:'Client requested a viewing',created_at:now}],lead_score:{score:45,temperature:'warm',signals:[{signal:'budget_clarity',points:15}]},matches:[{property:{id:property,title:'New Cairo apartment',area:'New Cairo',price:11000000,currency:'EGP'},score:92,coverage:100,evidence:[{criterion:'budget',status:'matched',actual:11000000}]}],project_matches:[{project:{id:'33333333-3333-4333-8333-333333333333',name:'Garden View',name_ar:'جاردن فيو',area:'New Cairo',developer_name:'Acme'},unit:{id:'unit-one',type:'apartment',bedrooms:3,price_from:10000000,down_payment:'10%',installment_years:8},display_name:'Garden View',score:96,coverage:100,fit_summary:'Fits location, budget and bedrooms',evidence:[{criterion:'location',status:'matched'},{criterion:'budget',status:'matched'}]}],summary:'أحمد يبحث عن شقة · Ahmed is looking for an apartment.',next_best_action:'راجع مشروع Garden View · Review Garden View',missing_information:['type'],risks:[],followup_recommendation:'Tomorrow',engine:'rules'};
let writes=[];
const server=http.createServer((req,res)=>{
  if(req.url.startsWith('/api/')){let raw='';req.on('data',d=>raw+=d);req.on('end',()=>{const body=raw?JSON.parse(raw):{};if(req.method!=='GET')writes.push({url:req.url,body});let value=profile;
    if(req.url.endsWith('/extract'))value={requirements:{budget_max:20000000,down_payment:9000000},engine:'heuristic'};
    if(req.url.endsWith('/message'))value={message:'Hello Ahmed, shall we review your requirements?',engine:'template'};
    if(req.url.endsWith('/profile'))value={ok:true};
    if(req.url.endsWith('/offers'))value={id:'offer1',language:'ar',client_name:'Ahmed',created_at:now,items:[{title:'New Cairo apartment',price:11000000,currency:'EGP'}]};
    if(req.url.includes('/public-offers/'))value={id:'offer1',language:'ar',client_name:'Ahmed',created_at:now,items:[{title:'New Cairo apartment',price:11000000,currency:'EGP'}]};
    res.setHeader('Content-Type','application/json');res.end(JSON.stringify(value));});return;}
  if(req.url.startsWith('/assets/')){const clean=req.url.split('?')[0],file=path.join(root,'frontend',clean);res.setHeader('Content-Type',clean.endsWith('.css')?'text/css':clean.endsWith('.svg')?'image/svg+xml':'application/javascript');res.end(fs.readFileSync(file));return;}
  if(req.url.startsWith('/crm-offer')){res.setHeader('Content-Type','text/html');res.end(fs.readFileSync(path.join(root,'frontend/crm-offer.html')));return;}
  if(req.url.startsWith('/behavior-test')){res.setHeader('Content-Type','text/html');res.end(`<!doctype html><html><body><script>window.behaviorCalls=[];window.HZ={lang:'en',session:()=>({uid:'fixture',token:'fixture'}),sbAuth:async(path,token,method,body)=>{behaviorCalls.push({path,body});return path.startsWith('/crm_behavior_links')?${req.url.includes('active=1')?'[{id:"consent"}]':'[]'}:null;}};</script><script src="/assets/crm-behavior.js"></script></body></html>`);return;}
  if(req.url.startsWith('/deals-test')){const stub=`<script>window.dealWrites=[];window.HZ={requireSession:async()=>({uid:'fixture',token:'fixture'}),sbAuth:async(path,token,method,body)=>{if(method){dealWrites.push({path,body});return null;}if(path.startsWith('/profiles'))return [{role:'broker'}];if(path.startsWith('/clients'))return [{id:'${lead}',name:'Ahmed'}];if(path.startsWith('/listings'))return [{id:'${property}',title:'New Cairo apartment',price:11000000}];return [];}};</script>`;const source=fs.readFileSync(path.join(root,'frontend/deals.html'),'utf8').replace(/<script src="\/assets\/homzy.js[^>]*><\/script>/,stub).replace(/<script src="\/assets\/broker-session.js[^>]*><\/script>/,'');res.setHeader('Content-Type','text/html');res.end(source);return;}
  res.setHeader('Content-Type','text/html');res.end(`<!doctype html><html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><body><button id="open">Open fixture client</button><script type="module">import {installSalesWorkspace} from '/assets/crm-sales.js';window.HZ={lang:new URLSearchParams(location.search).get('lang')||'ar',esc:s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])),hasFeature:()=>true};installSalesWorkspace({session:async()=>({token:'fixture-only'}),reload:async()=>{}});document.querySelector('#open').onclick=()=>openSales('${lead}');</script></body></html>`);
});
(async()=>{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  let browser;
  try{
    browser=await chromium.launch({headless:true,...(process.env.CRM_TEST_BROWSER_CHANNEL?{channel:process.env.CRM_TEST_BROWSER_CHANNEL}:{})});
    const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
    const out=path.join(root,'.tmp','crm-qa');fs.mkdirSync(out,{recursive:true});
    for(const language of ['ar','en'])for(const width of [390,768,1280]){
      await page.setViewportSize({width,height:900});await page.goto(`http://127.0.0.1:${server.address().port}/?lang=${language}`);
      await page.locator('#open').click();await page.locator('[data-tab="profile"]').click();
      assert.equal(await page.locator('dialog').getAttribute('dir'),language==='ar'?'rtl':'ltr');
      assert(await page.locator('dialog').evaluate(el=>el.scrollWidth<=el.clientWidth+1),'Dialog horizontally overflows');
      await page.screenshot({path:path.join(out,`${language}-${width}.png`)});
    }
    await page.locator('[data-tab="copilot"]').click();assert((await page.locator('#sales-content').innerText()).includes('Garden View'));
    await page.locator('[data-tab="profile"]').click();
    writes=[];
    await page.locator('#sales-extract').fill('Budget 20 million, down payment 9 million');await page.locator('#sales-parse').click();
    await page.locator('#sales-apply').waitFor();
    assert.equal(await page.locator('[name="budget_max"]').inputValue(),'12000000');
    await page.locator('[data-extracted="0"]').check();await page.locator('#sales-apply').click();
    assert.equal(await page.locator('[name="budget_max"]').inputValue(),'20000000');
    assert.equal(writes.filter(w=>w.url.endsWith('/profile')).length,0,'Extraction must not save automatically');
    await page.locator('#sales-profile button').click();await page.locator('[data-tab="message"]').click();
    await page.locator('#sales-draft').click();await page.waitForFunction(()=>document.querySelector('#sales-message').value.includes('Hello'));
    assert(!writes.some(w=>w.url.includes('/send')),'Drafting must not send');
    await page.locator('[data-tab="tasks"]').click();await page.locator('[name="due"]').fill('2026-09-10T12:30');await page.locator('[name="title"]').fill('Discuss the offer');await page.locator('[name="reminder"]').selectOption('60');await page.locator('#sales-task button').click();
    await page.waitForFunction(()=>document.querySelector('#sales-status').textContent.includes('Scheduled'));
    assert.equal(writes.find(w=>w.url.endsWith('/followups')).body.reminder_minutes,60);
    await page.locator('[data-tab="matches"]').click();await page.locator('[data-match]').check();await page.locator('#sales-offer').click();
    await page.locator('iframe').waitFor();assert(await page.frameLocator('iframe').locator('body').innerText().then(t=>t.includes('11000000')));
    await page.goto(`http://127.0.0.1:${server.address().port}/crm-offer?token=${lead}`);
    await page.locator('article').waitFor();assert((await page.locator('main').innerText()).includes('11000000'));
    await page.goto(`http://127.0.0.1:${server.address().port}/behavior-test?active=0`);
    await page.evaluate(()=>HZ.trackBehavior('viewed','listing'));
    assert.equal(await page.evaluate(()=>behaviorCalls.filter(c=>c.path.includes('crm_track_behavior')).length),0);
    await page.goto(`http://127.0.0.1:${server.address().port}/behavior-test?active=1`);
    await page.getByRole('button',{name:'Stop sharing'}).waitFor();await page.evaluate(()=>HZ.trackBehavior('viewed','listing'));
    assert.equal(await page.evaluate(()=>behaviorCalls.filter(c=>c.path.includes('crm_track_behavior')).length),1);
    await page.getByRole('button',{name:'Stop sharing'}).click();await page.getByRole('button',{name:'Stop sharing'}).waitFor({state:'detached'});
    await page.evaluate(()=>HZ.trackBehavior('viewed','listing'));
    assert.equal(await page.evaluate(()=>behaviorCalls.filter(c=>c.path.includes('crm_track_behavior')).length),1);
    for(const direction of ['rtl','ltr']){await page.setViewportSize({width:390,height:900});await page.goto(`http://127.0.0.1:${server.address().port}/deals-test`);await page.waitForFunction(()=>document.querySelector('#kpis').textContent.trim());await page.evaluate(async dir=>{document.documentElement.dir=dir;await openDeal();},direction);assert(await page.locator('#dealOv .modal').evaluate(el=>el.scrollWidth<=el.clientWidth+1),'Deal form overflows');await page.screenshot({path:path.join(out,`deal-${direction}-390.png`)});}
    await page.locator('#dLead').selectOption(lead);await page.locator('#dListing').selectOption(property);await page.locator('#dProbability').fill('65');await page.locator('#dNotes').fill('Viewing complete');await page.locator('#dSave').click();assert.equal(await page.evaluate(()=>dealWrites[0].body.listing_id),property);assert.equal(await page.evaluate(()=>dealWrites[0].body.probability),65);
    assert.equal(errors.length,0,errors.join('\n'));console.log('CRM browser checks passed: AR/EN at 390/768/1280px, extraction review, save, message draft, offer preview/shared page, consent-gated tracking and revocation.');
  }finally{if(browser)await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
