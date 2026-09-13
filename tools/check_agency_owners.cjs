/* Browser checks use fixture data only; no production requests or writes. */
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'../frontend');
const agent='11111111-1111-4111-8111-111111111111';
const manager='22222222-2222-4222-8222-222222222222';
const agency='33333333-3333-4333-8333-333333333333';
const owner='44444444-4444-4444-8444-444444444444';
const roster=[
  {user_id:agent,name:'Agent One',phone:'01000000001',status:'active'},
  {user_id:manager,name:'Manager One',phone:'01000000002',status:'active'}
];
const server=http.createServer((req,res)=>{
  if(req.url.startsWith('/assets/')){
    const clean=req.url.split('?')[0],file=path.join(root,clean);
    res.setHeader('Content-Type',clean.endsWith('.css')?'text/css':'application/javascript');
    res.end(fs.readFileSync(file));return;
  }
  let source=fs.readFileSync(path.join(root,'owners.html'),'utf8');
  source=source.replace(
    "import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';",
    "const createClient=()=>({auth:{getSession:async()=>({data:{session:{access_token:'fixture',user:{id:new URLSearchParams(location.search).get('uid')}}}}),signInWithPassword:async()=>({error:null})}});"
  );
  res.setHeader('Content-Type','text/html');res.end(source);
});
(async()=>{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const browser=await chromium.launch({channel:process.env.CRM_TEST_BROWSER_CHANNEL||'msedge',headless:true});
  try{
    for(const role of ['agent','manager'])for(const language of ['ar','en'])for(const width of [390,1280]){
      const uid=role==='manager'?manager:agent,writes=[];
      const context=await browser.newContext({viewport:{width,height:900}});
      await context.addInitScript(lang=>localStorage.setItem('hz_lang',lang),language);
      await context.route('https://ceoqtkbpdxnkuptnnwjg.supabase.co/rest/v1/**',async route=>{
        const request=route.request(),url=request.url(),method=request.method();
        if(method!=='GET')writes.push({url,method,body:request.postDataJSON()});
        let body=[];
        if(url.includes('/agencies?'))body=[{id:agency,name:'Fixture Agency'}];
        else if(url.includes('/rpc/my_perms'))body=role==='manager'?['owner.view','owner.view_phone','owner.create','owner.edit','team.manage']:['owner.view','owner.create','owner.edit'];
        else if(url.includes('/rpc/agency_team_roster'))body=roster;
        else if(url.includes('/rpc/agency_list_owners'))body=[{id:owner,name:'Owner One',phone:role==='manager'?'01012345678':null,whatsapp:null,area:'New Cairo',property_ref:'A-12',property_type:'Apartment',asking_price:9000000,source_kind:'agent',stage:'new',assigned_to:agent}];
        else if(url.includes('/profiles?'))body=[{role:'broker',full_name:'Fixture Broker'}];
        await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(body)});
      });
      const page=await context.newPage(),errors=[];
      page.on('pageerror',error=>errors.push(error.message));
      await page.goto('http://127.0.0.1:'+server.address().port+'/owners?uid='+uid);
      await page.getByText('Owner One').waitFor();
      assert.equal(await page.locator('html').getAttribute('dir'),language==='ar'?'rtl':'ltr');
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true,role+' '+language+' '+width+' body overflow');
      assert.equal(await page.locator('a[href^="tel:"]').count(),role==='manager'?1:0,'phone masking');
      await page.locator('.create-only').click();
      assert.equal(await page.locator('#oKind option[value="company"]').isDisabled(),role!=='manager');
      assert.equal(await page.locator('#oAssignee option').count(),role==='manager'?3:2);
      if(role==='agent'&&language==='en'&&width===390){
        await page.locator('#oName').fill('New owner');
        await page.locator('#saveOwner').click();
        await page.locator('#ownerOv').waitFor({state:'hidden'});
        const created=writes.find(w=>w.url.includes('/rpc/agency_create_owner'));
        assert(created,'create owner RPC was not called');
        assert.equal(created.body.p_source_kind,'agent');
        assert.equal(created.body.p_assigned_to,agent);
      }
      assert.deepEqual(errors,[]);
      await context.close();
    }
    console.log('Agency owners passed: AR/EN, mobile/desktop, phone masking, role-scoped source and assignee controls.');
  }finally{await browser.close();server.close();}
})().catch(error=>{console.error(error);process.exitCode=1;server.close();});
