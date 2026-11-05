import test from 'node:test';
import assert from 'node:assert/strict';
import {canvasSize, countStructuredRosterRows, documentVerticalBounds,
  normaliseRecognition} from '../web/roster_scanner.mjs';

test('large photos keep table aspect ratio within iPad memory limits', () => {
  const size = canvasSize(12000, 8000);
  assert.ok(size.width * size.height <= 4805000);
  assert.ok(size.width <= 3000);
  assert.ok(Math.abs(size.width / size.height - 1.5) < 0.01);
  assert.deepEqual(canvasSize(1600, 1200), {width: 1600, height: 1200});
  assert.throws(() => canvasSize(0, 1200));
});

test('iPhone viewer bars are cropped without cropping a dark document', () => {
  const pixels = new Uint8ClampedArray(10 * 20 * 4).fill(255);
  for (let y = 0; y < 5; y++) {
    for (let x = 0; x < 10; x++) pixels.fill(0, (y * 10 + x) * 4, (y * 10 + x) * 4 + 3);
  }
  for (let y = 16; y < 20; y++) {
    for (let x = 0; x < 10; x++) pixels.fill(0, (y * 10 + x) * 4, (y * 10 + x) * 4 + 3);
  }
  assert.deepEqual(documentVerticalBounds(pixels, 10, 20), {top: 5, bottom: 16});
  assert.deepEqual(documentVerticalBounds(new Uint8ClampedArray(10 * 20 * 4), 10, 20),
    {top: 0, bottom: 20});
});

test('recognition preserves word boxes used to reconstruct roster columns', () => {
  const result = normaliseRecognition({text: '21910  04:25  12:58', confidence: 87,
    blocks: [{paragraphs: [{lines: [{words: [
      {text: '21910', bbox: {x0: 10, y0: 20, x1: 60, y1: 40}},
      {text: '04:25', bbox: {x0: 150, y0: 20, x1: 200, y1: 40}},
      {text: '', bbox: {x0: 0, y0: 0, x1: 0, y1: 0}},
    ]}]}]}]});
  assert.equal(result.confidence, 87);
  assert.equal(result.lines.length, 2);
  assert.equal(result.lines[1].left, 150);
  assert.equal(result.lines[0].text, '21910');
});

test('empty OCR output remains empty rather than inventing records', () => {
  assert.deepEqual(normaliseRecognition({}), {fullText: '', lines: [], confidence: 0});
});

test('header words inside one cell stay together for column mapping', () => {
  const result = normaliseRecognition({text: 'BOOK ON   BOOK OFF', blocks: [{
    paragraphs: [{lines: [{words: [
      {text: 'BOOK', bbox: {x0: 0, y0: 0, x1: 40, y1: 20}},
      {text: 'ON', bbox: {x0: 46, y0: 0, x1: 66, y1: 20}},
      {text: 'BOOK', bbox: {x0: 160, y0: 0, x1: 200, y1: 20}},
      {text: 'OFF', bbox: {x0: 206, y0: 0, x1: 236, y1: 20}},
    ]}]}],
  }]});
  assert.deepEqual(result.lines.map(l => l.text), ['BOOK ON', 'BOOK OFF']);
});


test('structured roster rows favour full-page table recognition', () => {
  const clean = [
    'B Moore 1910 WOD 208 08:11 17:10 8.59 Amended Turn',
    'A Jesson 3280 WOD DI DI 10:00 22:00 8.45',
    'J Brooks 3849 WOD TW TW 12:00 20:45 8.45',
  ].join('\n');
  assert.equal(countStructuredRosterRows(clean), 3);
  assert.equal(countStructuredRosterRows(
    'B Moore 1910 WOD 2085:08:11.517:102-58759 Amended Turn'
  ), 0);
});
