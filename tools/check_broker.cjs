const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.join(__dirname,'../frontend');
for(const file of ['my-day.html','clients.html','deals.html','insights.html','my-listings.html','login.html']){
 for(const match of fs.readFileSync(path.join(root,file),'utf8').matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)){
  if(match[1].includes('application/ld+json'))continue;
  const source=match[2].replace(/^import .*?;\s*$/gm,'');
  new vm.Script(source,{filename:file});
 }
}
for(const file of ['homzy.js','broker-session.js'])new vm.Script(fs.readFileSync(path.join(root,'assets',file),'utf8'),{filename:file});
console.log('Broker pages and shared JavaScript syntax passed.');
const assert=require('node:assert/strict');
(async()=>{
 const listing=fs.readFileSync(path.join(root,'my-listings.html'),'utf8');
 const source=listing.slice(listing.indexOf('window.saveListing=async'),listing.indexOf('window.togglePub='));
 const fields=Object.fromEntries(['fTitleTxt','fPurpose','fType','fArea','fAddress','fPrice','fSize','fBeds','fBaths','fFloor','fDesc','draftBtn','saveBtn'].map(k=>[k,{value:''}]));
 Object.assign(fields.fTitleTxt,{value:'Test unit'});fields.fPrice.value='4500000';fields.fArea.value='New Cairo';
 const calls=[],ctx=vm.createContext({window:{},$:id=>fields[id],UID:'test-owner',EDIT_ID:null,NEW_FILES:[],KEEP_MEDIA:[],SB_KEY:'test',TOKEN:'test',PROFILE:{},fmsg:()=>{},closeForm:()=>{},loadMine:()=>{},api:async(p,o)=>{calls.push({p,...o});return [{id:'test-unit'}];}});
 vm.runInContext(source,ctx);
 await ctx.window.saveListing('draft');
 assert(calls.every(x=>!x.body||JSON.parse(x.body).status!=='active'),'draft must never publish');
 calls.length=0;ctx.EDIT_ID=null;
 await ctx.window.saveListing('active');
 assert.equal(JSON.parse(calls[0].body).status,'draft','new unit starts hidden');
 assert.equal(JSON.parse(calls.at(-1).body).status,'active','publish only after media succeeds');
 calls.length=0;ctx.EDIT_ID=null;fields.fPrice.value='-1';
 await ctx.window.saveListing('active');assert.equal(calls.length,0,'invalid publish must not write');
 console.log('Draft, publish ordering, and invalid-price checks passed (mock writes only).');
})().catch(e=>{console.error(e);process.exitCode=1;});
