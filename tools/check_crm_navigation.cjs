const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'../frontend');
const server=http.createServer((req,res)=>{
  if(req.url.startsWith('/assets/')){
    const file=path.join(root,req.url.split('?')[0]);
    res.setHeader('Content-Type',file.endsWith('.css')?'text/css':'text/javascript');
    res.end(fs.readFileSync(file));return;
  }
  res.setHeader('Content-Type','text/html');
  res.end('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/assets/homzy.css"><link rel="stylesheet" href="/assets/broker-workspace.css"></head><body'+(req.url==='/clients'?' class="broker-workspace"':'')+'><div id="hz-header"></div><main><h1>Navigation fixture</h1></main><div id="hz-footer"></div><script src="/assets/homzy.js"></script></body></html>');
});
(async()=>{
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const base='http://127.0.0.1:'+server.address().port;
  const browser=await chromium.launch({channel:process.env.CRM_TEST_BROWSER_CHANNEL||'msedge',headless:true});
  try{
    for(const width of [390,768,1024,1280])for(const role of ['guest','broker','profile-error']){
      const context=await browser.newContext({viewport:{width,height:900},reducedMotion:'reduce'});
      await context.addInitScript(({role})=>{
        if(!localStorage.getItem('hz_lang'))localStorage.setItem('hz_lang','en');
        if(role!=='guest')localStorage.setItem('sb-fixture-auth-token',JSON.stringify({access_token:'fixture',expires_at:Date.now()/1000+3600,user:{id:'11111111-1111-4111-8111-111111111111'}}));
      },{role});
      await context.route('https://**/*',route=>{
        const url=route.request().url();
        if(url.includes('/profiles?'))return route.fulfill({status:role==='profile-error'?503:200,contentType:'application/json',body:JSON.stringify([{role:'broker',full_name:'Fixture broker'}])});
        return route.fulfill({contentType:'application/json',body:'[]'});
      });
      const page=await context.newPage();
      const errors=[];page.on('pageerror',e=>{errors.push(e.message);console.error(e.message);});
      await page.goto(base+(width===1280?'/clients':'/'));
      await page.waitForFunction(()=>window.HZ&&HZ.isBroker!==undefined,{},{timeout:10000}).catch(async e=>{console.error(await page.evaluate(()=>({hz:!!window.HZ,html:document.body.innerHTML.slice(-800)})));throw e;});
      for(const language of ['en','ar','en']){
        if(await page.locator('html').getAttribute('lang')!==language)await page.locator('#hzLang').click();
        assert.equal(await page.locator('html').getAttribute('dir'),language==='ar'?'rtl':'ltr');
        // The CRM entry must stay discoverable even while role lookup is unavailable.
        const desktop=page.locator('#hzLinks a[href="/crm"]');
        const shortcut=page.locator('#hzCrmEntry');
        if(await desktop.isVisible())await desktop.click();
        else if(await shortcut.isVisible())await shortcut.click();
        else{
          await page.locator('#hzMenuBtn').click();
          const mobile=page.locator('#hzDrawerNav a[href="/crm"]');
          assert.equal(await mobile.isVisible(),true,`${role} ${language} ${width}: missing CRM`);
          await mobile.click();
        }
        await page.waitForURL(base+'/crm');
        await page.waitForFunction(()=>window.HZ&&HZ.isBroker!==undefined);
        assert.equal(await page.locator('html').getAttribute('lang'),language);
        const overflow=await page.evaluate(()=>document.getElementById('hzNav').scrollWidth>innerWidth+2);
        assert.equal(overflow,false,`${role} ${language} ${width}: header overflow`);
      }
      assert.deepEqual(errors,[]);
      await context.close();
    }
    console.log('CRM navigation passed: English/Arabic toggling, desktop/mobile, broker/guest and failed profile lookup.');
  }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;server.close();});
