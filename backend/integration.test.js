'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const {handle} = require('./server');

function send(port,path,body,token) {
  return new Promise((resolve,reject)=> {
    const bytes = Buffer.from(JSON.stringify(body));
    const r = http.request({port,host:'127.0.0.1',path,method:'POST',
      headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`,'Content-Length':bytes.length}},res=> {
      const buffers=[];res.on('data',b=>buffers.push(b));res.on('end',()=>resolve({status:res.statusCode,
        type:res.headers['content-type'],bytes:Buffer.concat(buffers)}));
    });r.on('error',reject);r.end(bytes);
  });
}
test('protected API creates a personalized real script and returns synthesized MP3 bytes',async()=> {
  const saveFetch=global.fetch;
  process.env.OPENAI_API_KEY='example-test-key';
  process.env.MYRADIO_ACCESS_TOKEN='local-secret';
  delete process.env.VOICE_PROVIDER;
  const calls=[];
  global.fetch = async(url,options)=> {
    calls.push({url,body:JSON.parse(options.body)});
    if(url.includes('/audio/speech')) return {ok:true,arrayBuffer:async()=>Buffer.alloc(1000,1)};
    return {ok:true,json:async()=>({output:[{type:'message',content:[{type:'output_text',
      text:'番組タイトル: ギターをもっと楽しむ朝\n'+'1970年代のアコースティックギターとフォークの魅力を語ります。'.repeat(10),annotations:[]}]}]})};
  };
  const server=http.createServer((req,res)=>handle(req,res));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try {
    const port=server.address().port;
    const bad=await send(port,'/api/program',{profile:{interests:['音楽・楽器']}},'wrong');
    assert.equal(bad.status,401);
    const episode=await send(port,'/api/program',{profile:{interests:['音楽・楽器'],minutes:10,
      topicNotes:{'音楽・楽器':'1970年代のフォーク'},topicImportance:{'音楽・楽器':3}}},'local-secret');
    assert.equal(episode.status,200);
    assert.match(JSON.parse(episode.bytes.toString()).title,/ギター/);
    assert.match(JSON.stringify(calls[0].body),/1970年代のフォーク/);
    const speech=await send(port,'/api/speech',{text:'今日はフォークの話です。',voice:'cedar',style:'親しみやすいDJ'},'local-secret');
    assert.equal(speech.status,200);
    assert.match(speech.type,/audio\/mpeg/);
    assert.equal(speech.bytes.length,1000);
  } finally {await new Promise(resolve=>server.close(resolve));global.fetch=saveFetch;
    delete process.env.OPENAI_API_KEY;delete process.env.MYRADIO_ACCESS_TOKEN;}
});
