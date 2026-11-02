'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {secureEqual, normalize, collectSources, pickResponseText, extractProgram} = require('./server');

test('requires a nonempty secret, compares correctly', () => {
  assert.equal(secureEqual('', ''), false);
  assert.equal(secureEqual('secret', 'secret'), true);
  assert.equal(secureEqual('wrong', 'secret'), false);
});
test('truncates user fields and normalizes duration', () => {
  const r = normalize({profile: {nickname:'a'.repeat(100), minutes:4, interests:['music',5]}});
  assert.equal(r.profile.nickname.length, 35);
  assert.equal(r.profile.minutes, 10);
  assert.deepEqual(r.profile.interests, ['music']);
});
test('extracts text and clickable sources', () => {
  const result = {output:[{type:'message',content:[{
    type:'output_text', text:'番組タイトル: 朝の音楽\n' + 'こんにちは。'.repeat(40),
    annotations:[{type:'url_citation',title:'News',url:'https://example.com/news'}]
  }]}]};
  assert.match(pickResponseText(result), /朝の音楽/);
  assert.deepEqual(collectSources(result), [{title:'News',url:'https://example.com/news'}]);
  assert.equal(extractProgram(pickResponseText(result), collectSources(result)).title, '朝の音楽');
});
