/* Host dashboard regression checks use fixture data only; no production writes. */
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'../frontend');
const source=fs.readFileSync(path.join(root,'host-dashboard.html'),'utf8')
  .replace(/<link rel="stylesheet" href="https:\/\/unpkg\.com\/leaflet[^>]+>/,'')
  .replace(/<script src="https:\/\/unpkg\.com\/leaflet[^>]+><\/script>/,'')
  .replace('<script src="/assets/homzy.js?v=5"></script>',`<script>
    window.hostCalls=[];
    window.HZ={lang:new URLSearchParams(location.search).get('lang')||'en',
      session:()=>({uid:'11111111-1111-4111-8111-111111111111',token:'fixture'}),
      esc:s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])),
      sb:async p=>p.includes('stay_property_types')?[{slug:'apartment',name_ar:'شقة',name_en:'Apartment'}]:p.includes('stay_destinations')?[{slug:'cairo',name_ar:'القاهرة',name_en:'Cairo'}]:p.includes('stay_amenities')?[{id:1,name_ar:'واي فاي',name_en:'Wi-Fi'}]:[],
      sbAuth:async p=>{hostCalls.push(p);if(p.startsWith('/stay_hosts'))return[{user_id:'11111111-1111-4111-8111-111111111111',verification_status:'pending'}];return[];},
      applyLang:()=>{document.documentElement.lang=HZ.lang;document.documentElement.dir=HZ.lang==='ar'?'rtl':'ltr';document.querySelectorAll('[data-ar]').forEach(el=>{const v=el.getAttribute('data-'+HZ.lang);if(v!=null)el.innerHTML=v;});document.dispatchEvent(new CustomEvent('hz:lang'));}
    };
  </script>`);
const server=http.createServer((req,res)=>{const clean=req.url.split('?')[0];if(clean.startsWith('/assets/')){const file=path.join(root,clean);res.setHeader('Content-Type',file.endsWith('.css')?'text/css':'text/javascript');res.end(fs.readFileSync(file));return;}res.setHeader('Content-Type','text/html');res.end(source);});
(async()=>{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));let browser;
  try{
    browser=await chromium.launch({headless:true,channel:process.env.CRM_TEST_BROWSER_CHANNEL||'msedge'});
    for(const language of ['en','ar']){
      const page=await browser.newPage({viewport:{width:390,height:900}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
      await page.addInitScript(()=>localStorage.setItem('sb-fixture-auth-token',JSON.stringify({access_token:'fixture',expires_at:Date.now()/1000+3600,user:{id:'11111111-1111-4111-8111-111111111111'}})));
      const base=`http://127.0.0.1:${server.address().port}`;
      await page.goto(`${base}/host/verification?lang=${language}`);
      await page.getByText(language==='en'?'Verification status':'حالة التوثيق').waitFor();
      await page.waitForTimeout(300);assert((await page.evaluate(()=>hostCalls.length))<8,'Language rendering triggered an API loop');
      await page.locator('a[href="/host/properties/new"]').first().click();
      await page.locator('#w_title').waitFor();assert.equal(new URL(page.url()).pathname,'/host/properties/new');
      assert.equal(errors.length,0,errors.join('\n'));await page.close();
    }
    console.log('Stays host checks passed: verification renders and Add property opens in AR/EN without a language event loop.');
  }finally{if(browser)await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;server.close();});
