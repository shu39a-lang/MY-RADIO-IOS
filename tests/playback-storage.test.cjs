const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('MyRadio/ContentView.swift','utf8');
function runtime({localFails=false,native=true,nativeOK=true,postThrows=false}={}){
 const saved={},messages=[];
 const ctx=vm.createContext({window:{},setTimeout,clearTimeout,
  localStorage:{getItem:()=>null,setItem:(k,v)=>{if(localFails)throw Error('QuotaExceededError');saved[k]=v}},
  hasNative:()=>native,
  sendNative:msg=>{if(postThrows)throw Error('bridge unavailable');messages.push(msg);queueMicrotask(()=>ctx.window.radioHistorySaved({id:msg.id,ok:nativeOK}))}
 });
 vm.runInContext("const UNIQUE_KEY='myradio_unique_v1';let uniqueState;"+source.slice(source.indexOf('function restoreUnique('),source.indexOf('function localDay()')),ctx);
 return {ctx,saved,messages};
}
test('WebKit storage failure still saves and confirms native history',async()=>{
 const {ctx,messages}=runtime({localFails:true});
 vm.runInContext("uniqueState.seen.heard='2026-11-17'",ctx);
 await ctx.saveUnique();
 assert.equal(JSON.parse(messages[0].value).seen.heard,'2026-11-17');
 assert.equal(JSON.parse(ctx.window.__myradioSaved.myradio_unique_v1).seen.heard,'2026-11-17');
});
test('local history remains usable when native storage rejects or bridge throws',async()=>{
 for(const options of [{nativeOK:false},{postThrows:true},{native:false}]){
  const {ctx,saved}=runtime(options);await ctx.saveUnique();assert(saved.myradio_unique_v1);
 }
});
test('both stores failing does not report successful persistence',async()=>{
 const {ctx}=runtime({localFails:true,nativeOK:false});
 await assert.rejects(ctx.saveUnique(),/放送履歴/);
 assert.equal(ctx.window.__myradioSaved,undefined);
});
test('malformed saved fields are normalized without erasing heard history',()=>{
 const {ctx}=runtime();
 const result=ctx.restoreUnique(JSON.stringify({seen:{heard:1},newsTitles:5,queues:{tech:'bad'},editorialHistory:[null]}),JSON.stringify({seen:{older:1},newsTitles:['headline']}));
 assert.equal(result.seen.heard,1);assert.equal(result.seen.older,1);
 assert.equal(result.newsTitles[0],'headline');assert.equal(result.queues.tech.length,0);assert.equal(result.editorialHistory.length,0);
});
