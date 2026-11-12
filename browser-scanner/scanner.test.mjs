import test from 'node:test';
import assert from 'node:assert/strict';
import {baseRosterOrientationScore, canvasSize, countPayrollRosterRows, countStructuredRosterRows,
  documentVerticalBounds, needsDetailedRosterPass,
  normaliseRecognition, repairBaseRosterLineNumbers} from '../web/roster_scanner.mjs';

test('Base Roster orientation favours weekday columns over upside-down noise', () => {
  const upsideDown = {
    fullText: 'fais oBny rT osSswoig 0061 hox ppny 8051',
    lines: Array.from({length: 40}, () => ({})),
  };
  const upright = {
    fullText: 'Sunday Monday Tuesday Wednesday Thursday Friday Saturday\n' +
      '35 07:45 16:30 8.45 205 No Duty No Duty 16:53 00:06 8.45 Sp\n' +
      '3535 Walsall Ruge Redditch',
    lines: Array.from({length: 10}, () => ({})),
  };
  assert.ok(baseRosterOrientationScore(upright) >
    baseRosterOrientationScore(upsideDown));
});

test('Base Roster line numbers are recovered from the fixed printed grid', () => {
  const lines = [
    {text: 'Sunday', left: 100, top: 20, right: 160, bottom: 35},
    {text: 'Saturday', left: 700, top: 20, right: 770, bottom: 35},
    ...['1', '2', '3', 'a4', '5', '6', '7', '8'].map((text, index) => ({
      text,
      left: 40,
      top: 70 + index * 54,
      right: 55,
      bottom: 84 + index * 54,
    })),
    ...Array.from({length: 8}, (_, index) => ({
      text: String(3500 + index),
      left: 40,
      top: 96 + index * 54,
      right: 80,
      bottom: 110 + index * 54,
    })),
    {text: 'No Duty', left: 110, top: 70, right: 170, bottom: 84},
  ];
  const repaired = repairBaseRosterLineNumbers({fullText: '', lines});
  const numbers = repaired.lines.filter(line => /^\d{1,2}$/.test(line.text))
    .map(line => Number(line.text));
  assert.deepEqual(numbers, [1, 2, 3, 4, 5, 6, 7, 8]);
});

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

test('partly read roster pages receive an enlarged detail pass', () => {
  const complete = [
    'D Lawrence 1167 WOD ALLOC 201 04:25 12:53 8.45',
    'N Cotton 5380 WOD ALLOC 9001 04:25 13:10 8.45',
    'N Appleby 2175 WOD RK 202 04:48 12:10 8.28',
    'A Passmore 4365 WOD ALLOC 203 04:54 13:22 8.45',
    'PJ Pratt 1040 WOD 204 04:56 12:58 8.02',
  ].join('\n');
  const partial = [
    complete,
    'M Winfindale 0979 WOD LD LD 08:11 OTELT 8.59',
    'S Ellison 2335 WOD RL RL 12:30',
    'MA Khukon 1378 WOD D3 D3 12:45',
    'N Carter 0049 WOD ALLOC 215 17:11',
    'B Morris 1192 WOD ALD',
  ].join('\n');
  assert.equal(countPayrollRosterRows(partial), 10);
  assert.equal(countStructuredRosterRows(partial), 5);
  assert.equal(needsDetailedRosterPass(partial), true);
  assert.equal(needsDetailedRosterPass(complete), false);
});

test('36-row 48-hour report rereads one damaged D3 clock', () => {
  const report = [
    'NAJ Macpherson 3075 WOD D3 D3= 2041904 “13:22 8.28',
    ...Array.from({length: 32}, (_, i) =>
      `A Driver ${(4000 + i)} WOD ALLOC 201 04:25 12:53 8.28`),
    'G Aitken 1890 WOD ALD ALD 08:45',
    'A Passmore 4365 WOD ALW ALW 08:20',
    'S Rose 1190 WOD ALW ALW 08:45',
  ].join('\n');
  assert.equal(countPayrollRosterRows(report), 36);
  assert.equal(needsDetailedRosterPass(report), true);
  assert.equal(needsDetailedRosterPass(report.replace(
    'D3= 2041904 “13:22', 'D3 04:54 13:22'
  )), false);
});

test('checks isolated Base Roster fields before accepting the shift', async () => {
  const {readBaseRosterDay} = await import('../web/roster_scanner.mjs');
  assert.equal(readBaseRosterDay([['17:11', '01:31', '08:20', '215']], '171101310820215'),
    '17:11 01:31 08:20 215');
  assert.equal(readBaseRosterDay([['17:11', '01:31', '08:20', '15']], ''), '?');
  assert.equal(readBaseRosterDay([['17:14', '01:31', '08:20', '215']], ''), '?');
  assert.equal(readBaseRosterDay([['', '', 'No', 'Duty']], ''), 'No Duty');
  assert.equal(readBaseRosterDay([['', '', '', '']], ''), '?');
  assert.equal(readBaseRosterDay([['', '', '', '']], '', {blank: true}), '');
});

test('flags conflicting turn readings across Base Roster pages', async () => {
  const {flagConflictingBaseRosterTurns} = await import('../web/roster_scanner.mjs');
  const heading = 'WEEK | SUNDAY | MONDAY | TUESDAY | WEDNESDAY | THURSDAY | FRIDAY | SATURDAY';
  const pages = [
    {lines: [], fullText: heading + '\n1 | | 17:11 01:31 08:20 245 | No Duty\n1234'},
    {lines: [], fullText: heading + '\n2 | | 17:11 01:31 08:20 215 | No Duty\n5678'},
  ];
  for (const page of flagConflictingBaseRosterTurns(pages)) {
    assert.match(page.fullText, /\| \? \| No Duty/);
  }
});
