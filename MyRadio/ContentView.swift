  onlineLookupPending=true;waitingForOnlineBeforeGoodbye=false;
  preparedFeature=feature;preparedAt=Date.now();
 if(!preview){
  // Each user-selected genre has an immediate, meaningful offline introduction.
  // A single genre gets two different chapters; the morning special gets five.
  const starters=feature?5:Math.max(2,specs.length);
  for(let i=0;i<starters;i++){
   const spec=specs[i%specs.length];
   preparedSegments.push(localRadioFeature(spec.key,i,spec.query));
  }
  try{saveUnique()}catch(e){$('log').textContent='放送履歴を保存できませんでした。';return;}
  playPrepared(); // Calls utter() synchronously; does not wait for a network request.
  if(!playing)return;
  const progress=document.createElement('p');progress.className='note';
  progress.textContent='放送を開始しました。ニュースと背景資料は放送中に準備しています。';
  $('log').prepend(progress);
 }else{
  $('log').textContent='番組表を準備しています。ニュースが取得できない場合も収録特集を利用します。';
  renderLineup();
 }
 const token=dailyRun; // Obtained after playPrepared(), which resets the run token.
 // Concurrent lookups: a slow or failed genre never blocks the other categories.
 try{
  const results=await Promise.all(specs.map(async(spec)=>{
   const [bulletinResult,articleResult]=await Promise.allSettled([
    fetchNews(NEWS_QUERIES[spec.key]||spec.query),
    obtainArticles(spec.key,spec.query,spec.count,token)
   ]);
   if(token!==dailyRun)return null;
   const news=bulletinResult.status==='fulfilled'?(bulletinResult.value.items||[]):[];
   const found=articleResult.status==='fulfilled'?articleResult.value:[];
   return {spec,news,found,fetchedAt:bulletinResult.status==='fulfilled'?(bulletinResult.value.fetchedAt||Date.now()):0};
  }));
  if(token!==dailyRun)return;
  const resultSegments=[],fallbacks=[];
  let fetchedAt=Date.now();
  for(const entry of results){
   if(!entry)continue;
   const {spec,news,found}=entry;
   if(entry.fetchedAt)fetchedAt=Math.max(fetchedAt,entry.fetchedAt);
   const selected=[];
   for(const n of news.sort((a,b)=>Number(b.publishedAt)-Number(a.publishedAt))){
    if(!n.title||!n.source||!/^https:\/\//.test(n.url)||!freshNews(n)||!unseenNews(n))continue;
    if(resultSegments.filter(s=>s.kind==='news').some(s=>similarHeadline(headline(s.news),headline(n)))||
       selected.some(v=>similarHeadline(headline(v),headline(n))))continue;
    selected.push(n);
    if(selected.length>=(feature?5:2))break;
   }
   if(!selected.length)fallbacks.push(TOPICS[spec.key]?.n||spec.query);
   for(const n of selected)resultSegments.push({kind:'news',title:headline(n),news:n,topicKey:spec.key});
   const existing=new Set(resultSegments.filter(s=>s.kind==='background').map(s=>s.article.pageid));
   for(const a of found){
    if(existing.has(a.pageid)||!unseen(a))continue;
    resultSegments.push({kind:'background',title:a.title,article:a,topicKey:spec.key});
    existing.add(a.pageid);
   }
   if(preview){
    const left=Math.max(0,spec.count-found.length);
    for(let i=0;i<left;i++)resultSegments.push(localRadioFeature(spec.key,i,spec.query));
   }
  }
  if(token!==dailyRun)return;
  preparedAt=fetchedAt;
  if(preview){
   preparedSegments=resultSegments;
   if(!preparedSegments.length)throw Error('この話題の番組を準備できませんでした。');
   saveUnique();renderLineup();
   $('log').textContent=(fallbacks.length?'ニュースがない分野：'+fallbacks.join('、')+'。背景解説・収録特集をご利用ください。\n':'')+
     '番組表を用意しました。「この順番で放送開始」を押してください。';
   $('lineupcard').scrollIntoView({block:'nearest'});
  }else if(playing){
   // Keep the currently spoken paragraph intact; put live material next, never
   // clear or restart speech. The existing local chapters stay available after it.
   if(resultSegments.length){
    // With the offline introduction already completed, append after the
    // playback cursor so the newly fetched news cannot be skipped.
    const insertAt=waitingForOnlineBeforeGoodbye?preparedSegments.length:Math.max(0,activeSegment+1);
    preparedSegments.splice(insertAt,0,...resultSegments);
   }
   renderLineup();
   const notice=document.createElement('p');notice.className='note';
   notice.textContent=resultSegments.length
    ? 'ニュース・背景資料の準備ができました。現在の話題が終わると続けて放送します。'
    : 'オンライン情報が見つからなかったため、収録済みの特集を続けます。';
   $('log').appendChild(notice);
  }
 }catch(e){
  if(token!==dailyRun)return;
  if(preview){$('log').textContent=e.message;reqStatus(e.message);return;}
  // After playback has started, a background lookup must never stop the radio.
  const notice=document.createElement('p');notice.className='note';
  notice.textContent='ニュースの準備ができなかったため、収録済みの特集を続けます。';
  $('log').appendChild(notice);
 }finally{
  if(token===dailyRun){
   onlineLookupPending=false;
   if(waitingForOnlineBeforeGoodbye&&playing&&nextPrepared){
    waitingForOnlineBeforeGoodbye=false;
    nextPrepared();
   }
  }
 }
}
startRadio=function(){if(!sel.size){alert('話題を1つ以上選んでください');return}playFresh([...sel].map(key=>({key,query:DAILY_QUERIES[key]||TOPICS[key].n,count:1})))};
startProgram=function(){refreshDaily();const key=featureKey();playFresh([{key,query:DAILY_QUERIES[key],count:5}],true)};
// Replace the request listener too; no short/fixed fallback can replay an old explanation.
$('reqgo').removeEventListener('click',onRequest);
onRequest=function(){const query=$('req').value.trim();if(!query){reqStatus('聞きたいことを入力してください。');return}reqStatus(query);reqSource('','');++requestSerial;playFresh([{key:'request:'+query,query,count:1}])};
$('reqgo').addEventListener('click',onRequest);

renderReq();
renderChs();
renderTopics();renderVoices();
</script>
</body>
</html>

"""##
}

