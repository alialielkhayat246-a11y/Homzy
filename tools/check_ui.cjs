const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.join(__dirname,'../frontend');
for(const file of ['index.html','app.html']){
  const source=fs.readFileSync(path.join(root,file),'utf8');
  for(const match of source.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)){
    if(match[0].includes('application/ld+json'))continue;
    new vm.Script(match[1],{filename:file});
  }
}
const context=vm.createContext({HZ:{lang:'ar'}});
vm.runInContext(fs.readFileSync(path.join(root,'assets/catalog-ui.js'),'utf8'),context);
const catalog=context.HZ.catalog;
assert.equal(catalog.area('New Cairo'),'القاهرة الجديدة');
assert.equal(catalog.category('clinic'),'medical');
assert.equal(catalog.category('office'),'office');
assert.equal(catalog.category('shop'),'commercial');
assert.equal(catalog.category('villa'),'residential');
assert.equal(catalog.category('unknown'),'');
assert.equal(catalog.text('10% down payment (≈ 330,000 EGP)'),'10% مقدم (≈ 330,000 ج.م)');
context.HZ.lang='en';
assert.equal(catalog.area('New Cairo'),'New Cairo');
assert.equal(catalog.text('After 3 years'),'After 3 years');
console.log('Inline JavaScript syntax and catalog localization/category checks passed.');

(async()=>{
  const app=fs.readFileSync(path.join(root,'app.html'),'utf8');
  const projects=[{id:'a',total_count:3},{id:'b',total_count:3},{id:'c',total_count:3}];
  const units=[{project_id:'a',type:'clinic'},{project_id:'a',type:'office'},{project_id:'b',type:'villa'},{project_id:'c',type:'clinic'}];
  let requests=0;
  context.HZ.rpc=async(_,args)=>{requests++;return projects.slice(args.p_offset,args.p_offset+Math.min(args.p_limit,2));};
  context.sb=async()=>units;
  vm.runInContext(app.slice(app.indexOf('const TYPE_CACHE='),app.indexOf('function renderActiveFilters()')),context);
  const first=await context.fetchProjectRows({p_offset:0,p_limit:1},'medical');
  const second=await context.fetchProjectRows({p_offset:1,p_limit:1},'medical');
  assert.equal(first[0].id,'a');assert.equal(second[0].id,'c');
  assert.equal(first[0].total_count,2);assert.equal(requests,2,'filtered pagination reuses complete results');
  const none=await context.fetchProjectRows({p_offset:0,p_limit:12},'commercial');
  assert.equal(none.length,0);
  context.HZ.lang='ar';context.esc=String;context.t=k=>k;context.money=n=>n+' EGP';
  vm.runInContext(app.slice(app.indexOf('function unitTypeLabel('),app.indexOf('async function submitViewing(')),context);
  const html=context.projectDetail({id:'a',name:'Example',area:'New Cairo'},[
    {type:'office',size_from:34,price_from:3300000},
    {type:'shop',size_from:32,price_from:4500000}
  ],[],[]);
  const rows=[...html.matchAll(/<tr><td data-label=[\s\S]*?<\/tr>/g)].map(m=>m[0]);
  assert(rows[0].includes('34 sqm')&&rows[0].includes('3300000 EGP'));
  assert(rows[1].includes('32 sqm')&&rows[1].includes('4500000 EGP'));
  console.log('Category pagination, empty results, caching, and exact unit price/size pairing passed.');
})().catch(e=>{console.error(e);process.exitCode=1;});
