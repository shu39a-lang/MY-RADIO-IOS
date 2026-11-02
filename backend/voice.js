'use strict';
// Server-side AI voice production. No speech synthesis takes place in iOS.
// This backend keeps the provider behind one API so it can be migrated before
// the OpenAI Speech API models' January 2027 retirement.
const VOICES = Object.freeze(['cedar','onyx','echo','ash','marin','coral','nova','shimmer','sage','alloy']);
const MAX_SPEECH_CHARS = 1700;
const PREVIEW_SCRIPT = 'こんにちは。マイラジオへようこそ。今日はあなたの好きな話題を、落ち着いたラジオ番組としてお届けします。どうぞ、ゆっくりお楽しみください。';
const styleInstructions = {
  '親しみやすいDJ': '自然な日本語のラジオDJ。話しかけるように親しみをこめて、過度に明るくせず、文のまとまりごとに少し息継ぎを入れ、語尾を機械的に揃えない。',
  '落ち着いた解説': '落ち着いた日本語のラジオナレーション。自然な間、柔らかな抑揚、ゆっくりめの聴き取りやすい声。抑揚を誇張しない。',
  '元気なDJ': '明るく心地よい日本語のラジオDJ。自然な笑顔を感じるような温かい声で、勢いを出し過ぎず、聞き疲れしない抑揚と間で。'
};
function normalizeSpeech(body = {}) {
  const input = typeof body.text === 'string' ? body.text.trim() : '';
  const voice = typeof body.voice === 'string' ? body.voice : '';
  const style = typeof body.style === 'string' ? body.style : '';
  if (!input || [...input].length > MAX_SPEECH_CHARS) throw Object.assign(new Error('Invalid speech length'), {status:400});
  if (!VOICES.includes(voice)) throw Object.assign(new Error('Unsupported voice'), {status:400});
  return {input, voice, instructions: `${styleInstructions[style] || styleInstructions['親しみやすいDJ']} 出力は読み上げ音声だけ。原稿は一文字も補わず、省略しない。`};
}
function elevenLabsVoiceID(voice) {
  let mapping;
  try { mapping = JSON.parse(process.env.ELEVENLABS_VOICE_MAP || '{}'); }
  catch { throw new Error('Invalid ELEVENLABS_VOICE_MAP'); }
  if (typeof mapping !== 'object' || !mapping || Array.isArray(mapping)) throw new Error('Invalid voice map');
  const id = mapping[voice];
  if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{15,80}$/.test(id)) {
    throw new Error(`ElevenLabs Japanese voice ID is not configured for '${voice}'`);
  }
  return id;
}

async function synthesizeSpeech(payload, fetchImpl = fetch) {
  const p = normalizeSpeech(payload);
  const provider = (process.env.VOICE_PROVIDER || 'openai').toLowerCase();
  let target, options;
  if (provider === 'elevenlabs') {
    if (!process.env.ELEVENLABS_API_KEY) throw new Error('ELEVENLABS_API_KEY is not configured');
    const id = elevenLabsVoiceID(p.voice);
    target = `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(id)}?output_format=mp3_44100_128`;
    options = {method:'POST', headers:{'xi-api-key':process.env.ELEVENLABS_API_KEY,
      'Content-Type':'application/json'},
      body: JSON.stringify({text:p.input,model_id:process.env.ELEVENLABS_MODEL || 'eleven_v4',language_code:'ja'}),
      signal:AbortSignal.timeout(100_000)};
  } else if (provider === 'openai') {
    if (!process.env.OPENAI_API_KEY) throw new Error('OPENAI_API_KEY is not configured');
    target = 'https://api.openai.com/v1/audio/speech';
    options = {method:'POST', headers:{'Authorization':`Bearer ${process.env.OPENAI_API_KEY}`,
      'Content-Type':'application/json'},
      body:JSON.stringify({model:process.env.OPENAI_TTS_MODEL || 'gpt-4o-mini-tts',
        voice:p.voice,input:p.input,instructions:p.instructions,response_format:'mp3'}),
      signal:AbortSignal.timeout(100_000)};
  } else { throw new Error('Unsupported VOICE_PROVIDER'); }
  const response = await fetchImpl(target, options);
  if (!response.ok) {
    console.error('Speech provider failed with status', response.status);
    throw Object.assign(new Error('Speech provider unavailable'), {status:502});
  }
  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.length < 300 || buffer.length > 12_000_000) throw new Error('Unexpected MP3 size');
  return buffer;
}

module.exports = {VOICES, MAX_SPEECH_CHARS, PREVIEW_SCRIPT, normalizeSpeech, synthesizeSpeech, elevenLabsVoiceID};
