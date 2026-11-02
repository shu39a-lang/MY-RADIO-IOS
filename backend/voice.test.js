'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {VOICES, normalizeSpeech, synthesizeSpeech} = require('./voice');
test('voices are selectable and validated', () => {
  assert.ok(VOICES.length >= 8);
  assert.equal(normalizeSpeech({text:'こんにちは',voice:'cedar'}).voice, 'cedar');
  assert.throws(()=>normalizeSpeech({text:'こんにちは',voice:'unknown'}));
  assert.throws(()=>normalizeSpeech({text:'x'.repeat(1701),voice:'nova'}));
});
test('sends correct speech request and returns audio bytes', async()=> {
  process.env.OPENAI_API_KEY = 'test-key-local';
  let called;
  const fake = async(url, opts) => {
    called={url,body:JSON.parse(opts.body)};
    return {ok:true,arrayBuffer:async()=>Buffer.alloc(550,3)};
  };
  const bytes=await synthesizeSpeech({voice:'marin',style:'落ち着いた解説',text:'日本語のラジオです。'},fake);
  assert.equal(called.url,'https://api.openai.com/v1/audio/speech');
  assert.equal(called.body.response_format,'mp3');
  assert.equal(called.body.voice,'marin');
  assert.match(called.body.instructions,/日本語/);
  assert.equal(bytes.length,550);
});

test('premium speech provider picks mapped licensed Japanese voice', async()=> {
  process.env.VOICE_PROVIDER = 'elevenlabs';
  process.env.ELEVENLABS_API_KEY = 'fake-test-key';
  process.env.ELEVENLABS_VOICE_MAP = JSON.stringify({marin:'voice123456789ABCDEFG'});
  let target, body;
  const fake = async(url,options)=> {target=url;body=JSON.parse(options.body);
    return {ok:true,arrayBuffer:async()=>Buffer.alloc(500,2)};};
  try {
    await synthesizeSpeech({voice:'marin',text:'自然な日本語です。'},fake);
    assert.match(target,/api\.elevenlabs\.io/);
    assert.equal(body.language_code,'ja');
    assert.equal(body.model_id,'eleven_v4');
    assert.throws(()=>normalizeSpeech({voice:'not-a-voice',text:'hello'}));
  } finally { delete process.env.VOICE_PROVIDER; delete process.env.ELEVENLABS_VOICE_MAP; delete process.env.ELEVENLABS_API_KEY; }
});
