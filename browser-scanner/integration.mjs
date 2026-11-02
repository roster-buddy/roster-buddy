import {chromium, webkit} from 'playwright';
import {PDFDocument, StandardFonts} from 'pdf-lib';
import {createServer} from 'node:http';
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'browser-scanner/.results');
await mkdir(output, {recursive: true});
const server = createServer(async (req, res) => {
  if (req.url === '/scanner-test') {
    res.setHeader('Content-Type', 'text/html');
    return res.end('<!doctype html><title>Roster scanner regression</title>');
  }
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const filename = path.resolve(root, 'web', '.' + pathname);
    if (!filename.startsWith(path.join(root, 'web') + path.sep)) throw new Error('Invalid path');
    const type = {'.mjs':'text/javascript','.js':'text/javascript','.wasm':'application/wasm'}[path.extname(filename)];
    if (type) res.setHeader('Content-Type', type);
    res.end(await readFile(filename));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = 'http://127.0.0.1:' + server.address().port;
const pdf = await PDFDocument.create();
const font = await pdf.embedFont(StandardFonts.Courier);
const columns = [30, 170, 310, 410, 525, 685];
for (let n=0; n<2; n++) {
  const page = pdf.addPage([900,350]);
  page.drawText('48-HOUR AMENDMENT', {x:30,y:310,font,size:15});
  page.drawText('DATE 0'+(3+n)+'/08/2026', {x:30,y:280,font,size:15});
  ['NAME','PAY NO','DEPOT','TURN','BOOK ON','BOOK OFF'].forEach((t,i) =>
    page.drawText(t, {x:columns[i],y:240,font,size:15}));
  ['MOORE','21910','WVH',String(204+n),'04:25','12:58'].forEach((t,i) =>
    page.drawText(t, {x:columns[i],y:200,font,size:15}));
}
const pdfBytes = [...await pdf.save()];
try {
  for (const engine of [chromium, webkit]) {
    const browser = await engine.launch({headless:true});
    try {
      const page = await browser.newPage({viewport:{width:820,height:1180}});
      page.setDefaultTimeout(120000);
      const external = [];
      page.on('request', request => {
        if (request.url().startsWith('http') && !request.url().startsWith(origin+'/')) external.push(request.url());
      });
      await page.goto(origin+'/scanner-test');
      const pngBytes = await page.evaluate(async () => {
        const canvas = document.createElement('canvas');
        canvas.width=1800; canvas.height=700;
        const ctx=canvas.getContext('2d');
        ctx.fillStyle='white';ctx.fillRect(0,0,1800,700);
        ctx.fillStyle='black';ctx.font='30px monospace';
        ctx.fillText('48-HOUR AMENDMENT',60,80);
        ctx.fillText('DATE 03/08/2026',60,140);
        const x=[60,340,620,820,1050,1370];
        ['NAME','PAY NO','DEPOT','TURN','BOOK ON','BOOK OFF'].forEach((t,i)=>ctx.fillText(t,x[i],220));
        ['MOORE','21910','WVH','204','04:25','12:58'].forEach((t,i)=>ctx.fillText(t,x[i],300));
        return [...new Uint8Array(await (await new Promise(r=>canvas.toBlob(r,'image/png'))).arrayBuffer())];
      });
      for (const [filename,bytes,count] of [['photo.png',pngBytes,1],['roster.pdf',pdfBytes,2]]) {
        const pages = await page.evaluate(async ({bytes,filename}) => {
          const scanner = await import('/roster_scanner.mjs');
          return JSON.parse(await scanner.scanDocument(new Uint8Array(bytes),filename,filename.endsWith('.pdf')));
        }, {bytes,filename});
        assert.equal(pages.length,count);
        for (const p of pages) {
          assert.match(p.fullText,/21910/);
          assert.match(p.fullText,/04:25/);
          assert.match(p.fullText,/12:58/);
          assert.ok(p.lines.length>5);
        }
        await writeFile(path.join(output,engine.name()+'-'+filename+'.json'),JSON.stringify(pages));
        console.log('PASS '+engine.name()+' '+filename+': correct payroll, times and '+count+' page(s)');
      }
      const cancel = await page.evaluate(async bytes => {
        const scanner = await import('/roster_scanner.mjs');
        const reading = scanner.scanDocument(new Uint8Array(bytes),'photo.png',false);
        scanner.cancelScan();
        try { await reading; return false; } catch { return true; }
      }, pngBytes);
      assert.equal(cancel,true);
      // Failed/cancelled scans must release the worker so a retry can succeed.
      const retry = await page.evaluate(async bytes => {
        const scanner=await import('/roster_scanner.mjs');
        return JSON.parse(await scanner.scanDocument(new Uint8Array(bytes),'retry.png',false));
      },pngBytes);
      assert.equal(retry.length,1);
      const corrupt = await page.evaluate(async () => {
        const scanner=await import('/roster_scanner.mjs');
        try {await scanner.scanDocument(new Uint8Array([1,2,3]),'broken.pdf',true);return false;}
        catch{return true;}
      });
      assert.equal(corrupt,true);
      assert.deepEqual(external,[]);
      console.log('PASS '+engine.name()+': cancellation, retry, corrupt-PDF rejection and same-origin assets');
    } finally { await browser.close(); }
  }
} finally { await new Promise(resolve=>server.close(resolve)); }
