const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('MyRadio/ContentView.swift','utf8');
const script=source.split('<script>')[1].split('</script>')[0];
new vm.Script(script);
const ctx=vm.createContext({URL});
vm.runInContext(source.slice(source.indexOf('function restoreUnique('),source.indexOf('let localUnique;')),ctx);
vm.runInContext(source.slice(source.indexOf('function contentKey('),source.indexOf('function articleKeys(')),ctx);
vm.runInContext(source.slice(source.indexOf('function headline('),source.indexOf('const NEWS_MAX_AGE_MS')),ctx);
vm.runInContext('let uniqueState={seen:{},newsTitles:[]};'+source.slice(source.indexOf('function unseenNews('),source.indexOf('window.radioNewsDidFinish',source.indexOf('function unseenNews('))),ctx);
const base={id:'a',url:'https://example.com/story?utm_source=a',source:'配信社',title:'宇宙探査機が月面着陸に成功し新しい観測を開始 - 配信社'};
test('publisher decorations and longer versions match the same story',()=>{
 const clean=ctx.headline(base);
 assert.equal(ctx.headline({...base,title:clean+'（配信社）'}),clean);
 assert(ctx.similarHeadline(clean,'【速報】'+clean+' 現地から詳しく報告'));
 assert(!ctx.similarHeadline(clean,'地元の図書館が新しい読み聞かせイベントを開催'));
});
test('changed numbers and distinct stories remain available',()=>{
 assert(!ctx.similarHeadline('日本代表が3対1で勝利して決勝に進出','日本代表が4対1で勝利して決勝に進出'));
 assert(!ctx.similarHeadline('市議会が学校給食の無償化を決定','市議会が公共バスの運賃改定を決定'));
});
test('tracked URLs share a key but article query IDs stay distinct',()=>{
 assert(ctx.newsKeys(base).includes('newsurl:https://example.com/story'));
 assert.notEqual(ctx.canonicalNewsURL('https://example.com/?id=1'),ctx.canonicalNewsURL('https://example.com/?id=2'));
});
test('history survives reload with stale native or corrupt local state',()=>{
 const state=ctx.restoreUnique(JSON.stringify({seen:{old:1},newsTitles:['old']}),JSON.stringify({seen:{new:1},newsTitles:['new']}));
 assert.equal(state.seen.old,1);assert.equal(state.seen.new,1);assert.equal(state.newsTitles.length,2);
 assert.equal(ctx.restoreUnique(JSON.stringify(state),'broken').seen.new,1);
 ctx.stateJSON=JSON.stringify(state);vm.runInContext('uniqueState=JSON.parse(stateJSON)',ctx);
 ctx.article=base;
 vm.runInContext('for(const k of newsKeys(article))uniqueState.seen[k]=1;uniqueState.newsTitles.push(headline(article))',ctx);
 assert(!ctx.unseenNews({...base,id:'b',url:'https://other.example/story',title:'【速報】'+ctx.headline(base)+' 現地から詳しく報告'}));
 assert(!ctx.unseenNews({...base,id:'c',url:'https://example.com/story?utm_source=b',title:'別の表記'}));
});
test('AI repeated sentences and already spoken headline are removed',()=>{
 const sentence='宇宙探査機が月面着陸に成功し新しい観測を開始。';
 assert.equal(ctx.distinctEditorial(sentence+'これからの観測結果が気になりますね。'+sentence,[sentence]),'これからの観測結果が気になりますね。');
});

vm.runInContext(source.slice(source.indexOf('function readingText('),source.indexOf('function pronunciationText(')),ctx);
test('furigana and ruby are spoken once, including repeated cleanup',()=>{
 for(const [input,want] of [
  ['東京（とうきょう）のニュースです。','とうきょうのニュースです。'],
  ['経済(けいざい)の話です。','けいざいの話です。'],
  ['山田（読み：やまだ）さんです。','やまださんです。'],
  ['ラジオ（らじお）です。','ラジオです。'],
  ['<ruby>東京<rp>（</rp><rt>とうきょう</rt><rp>）</rp></ruby>です。','東京です。']
 ]) {assert.equal(ctx.spokenText(input),want);assert.equal(ctx.spokenText(ctx.spokenText(input)),want);}
});
test('qualifications, numbers, quoted speech and intentional words survive',()=>{
 for(const input of ['料金（無料ではない）です。','参加（こどものみ）です。','東京（あす開催）です。','価格（100円）です。','条件（ただし変更あり）です。']){
  assert.equal(ctx.spokenText(input),input.replace('（','、').replace('）','、'));
 }
 assert.equal(ctx.spokenText('「はい、はい」と言いました。'),'はい、はいと言いました。');
 assert.equal(ctx.spokenText('時々、いろいろ考えます。'),'時々、いろいろ考えます。');
});
