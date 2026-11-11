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
      const renderedPages = await page.evaluate(async bytes => {
        await import('/roster_scanner.mjs');
        const render = number => window.rosterRenderJobCardPage(new Uint8Array(bytes), number);
        return [[...await render(1)], [...await render(2)]];
      }, pdfBytes);
      for (const image of renderedPages) {
        assert.deepEqual(image.slice(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      }
      assert.notDeepEqual(renderedPages[0], renderedPages[1]);
      console.log('PASS '+engine.name()+': job card viewer renders the requested PDF page');
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
      const portraitBytes = await page.evaluate(async () => {
        const canvas=document.createElement('canvas');
        canvas.width=1100;canvas.height=1500;
        const ctx=canvas.getContext('2d');
        ctx.fillStyle='white';ctx.fillRect(0,0,1100,1500);
        ctx.fillStyle='black';ctx.font='20px monospace';
        ctx.fillText('Daily Roster Report',30,45);
        ctx.fillText('7-DAY AMENDMENT',30,80);
        ctx.fillText('Report for Thursday 05/11/26 in All Links',30,115);
        const xs=[30,280,420,550,670,815,960];
        ['Name','Pay','Depot Amend','Turn','Book','Book','Rostered'].forEach((t,i)=>ctx.fillText(t,xs[i],170));
        ['','No.','Ind / Count','','On','Off','Hours'].forEach((t,i)=>ctx.fillText(t,xs[i],192));
        for(let i=0;i<32;i++){
          const own=i===31;
          const row=[own?'A Tester':'A Driver',own?'1910':String(6000+i),'WOD ALLOC',
            own?'213':String(200+i),own?'16:53':'04:25',own?'01:11':'12:58','8.45'];
          row.forEach((t,c)=>ctx.fillText(t,xs[c],240+i*34));
        }
        return [...new Uint8Array(await (await new Promise(r=>canvas.toBlob(r,'image/png'))).arrayBuffer())];
      });
      for (const [filename,bytes,count] of [['photo.png',pngBytes,1],['roster.pdf',pdfBytes,2],['portrait.png',portraitBytes,1]]) {
        const pages = await page.evaluate(async ({bytes,filename}) => {
          const scanner = await import('/roster_scanner.mjs');
          return JSON.parse(await scanner.scanDocument(new Uint8Array(bytes),filename,filename.endsWith('.pdf')));
        }, {bytes,filename});
        assert.equal(pages.length,count);
        for (const p of pages) {
          assert.match(p.fullText,filename==='portrait.png' ? /1910/ : /21910/);
          assert.match(p.fullText,filename==='portrait.png' ? /16:53/ : /04:25/);
          assert.match(p.fullText,filename==='portrait.png' ? /01:11/ : /12:58/);
          assert.ok(p.lines.length>5);
        }
        await writeFile(path.join(output,engine.name()+'-'+filename+'.json'),JSON.stringify(pages));
        console.log('PASS '+engine.name()+' '+filename+': correct payroll, times and '+count+' page(s)');
      }
      const stamp = await page.evaluate(async () => {
        const scanner = await import('/roster_scanner.mjs');
        const source = document.createElement('canvas');
        source.width = 1200; source.height = 1600;
        const ctx = source.getContext('2d');
        ctx.fillStyle = 'white'; ctx.fillRect(0, 0, 1200, 1600);
        ctx.fillStyle = 'black'; ctx.font = 'bold 80px sans-serif';
        ctx.save(); ctx.translate(900, 150); ctx.rotate(10 * Math.PI / 180);
        ctx.fillText('7 DAY', -120, 0); ctx.restore();
        // A body marker must never leak into the classification-only crop.
        ctx.fillRect(0, 700, 1200, 900);
        const bytes = new Uint8Array(await (await new Promise(r =>
          source.toBlob(r, 'image/png'))).arrayBuffer());
        const crop = await scanner.prepareCloudStamp(bytes, 'stamp.png');
        const url = URL.createObjectURL(new Blob([crop], {type: 'image/jpeg'}));
        const image = new Image(); image.src = url; await image.decode();
        const canvas = document.createElement('canvas');
        canvas.width = image.width; canvas.height = image.height;
        const pixels = canvas.getContext('2d'); pixels.drawImage(image, 0, 0);
        const data = pixels.getImageData(0, 0, canvas.width, canvas.height).data;
        let ink = 0;
        for (let i = 0; i < data.length; i += 4) if (data[i] < 100) ink++;
        URL.revokeObjectURL(url);
        return {width: image.width, height: image.height, size: crop.length,
          inkFraction: ink / (canvas.width * canvas.height)};
      });
      assert.equal(stamp.width, 2700);
      assert.equal(stamp.height, 600);
      assert.ok(stamp.size < 1000000);
      assert.ok(stamp.inkFraction > 0.005 && stamp.inkFraction < 0.15);
      console.log('PASS '+engine.name()+': stamp crop retains text and excludes roster body');
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
