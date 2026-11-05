// Loaded with the app; OCR libraries/model are fetched only when scanning starts.
// All recognition runs locally. Worker, WASM and language assets are same-origin.
const VENDOR = 'scan_vendor/t7-p6/';
let active = null;
let tesseractLoading;

export function canvasSize(width, height) {
  if (!(width > 0 && height > 0)) throw new Error('The image has no readable dimensions.');
  const scale = Math.min(1, 3000 / Math.max(width, height), Math.sqrt(4800000 / (width * height)));
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

export function countStructuredRosterRows(text) {
  return (text || '').split(/\r?\n/).filter(line =>
    /\b\d{4}\b/.test(line) &&
    (line.match(/\b(?:[01]?\d|2[0-3])[:.]\d{2}\b/g) || []).length >= 2
  ).length;
}

export function normaliseRecognition(data, region) {
  const lines = [];
  const rowTexts = [];
  for (const block of data.blocks || []) {
    for (const paragraph of block.paragraphs || []) {
      for (const line of paragraph.lines || []) {
        const offset = region?.offset || 0;
        const scale = region?.scale || 1;
        if (region) {
          const centre = ((line.bbox.y0 + line.bbox.y1) / 2) / scale + offset;
          if (centre < region.start || centre >= region.end) continue;
        }
        rowTexts.push(line.text || (line.words || []).map(w=>w.text).join(' '));
        // Keep words inside a cell together (e.g. "BOOK ON"), while retaining
        // large column gaps for the shared row reconstructor.
        const words = (line.words || []).filter(w => w.text?.trim() && w.bbox)
          .sort((a, b) => a.bbox.x0 - b.bbox.x0);
        let cell;
        for (const word of words) {
          const b = word.bbox;
          const charWidth = (b.x1 - b.x0) / Math.max(1, word.text.length);
          const gap = cell ? b.x0 - cell.right : Infinity;
          const threshold = Math.max((b.y1 - b.y0) * 0.6, charWidth * 2);
          if (!cell || gap > threshold) {
            cell = {text: word.text, left: b.x0, top: line.bbox?.y0 ?? b.y0, right: b.x1, bottom: line.bbox?.y1 ?? b.y1};
            lines.push(cell);
          } else {
            cell.text += ' ' + word.text;
            cell.right = b.x1;
            cell.top = Math.min(cell.top, line.bbox?.y0 ?? b.y0);
            cell.bottom = Math.max(cell.bottom, line.bbox?.y1 ?? b.y1);
          }
        }
      }
    }
  }
  if (region) {
    for (const line of lines) {
      line.left /= region.scale; line.right /= region.scale;
      line.top = line.top / region.scale + region.offset;
      line.bottom = line.bottom / region.scale + region.offset;
    }
  }
  return { fullText: region ? rowTexts.join('\n') : data.text || '', lines, confidence: Number(data.confidence) || 0 };
}

function loadTesseract(base) {
  if (globalThis.Tesseract) return Promise.resolve(globalThis.Tesseract);
  if (!tesseractLoading) {
    tesseractLoading = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = new URL('tesseract.min.js', base).href;
      script.onload = () => resolve(globalThis.Tesseract);
      script.onerror = () => { script.remove(); tesseractLoading = null; reject(new Error('Scanner files could not load. Check your connection and retry.')); };
      document.head.append(script);
    });
  }
  return tesseractLoading;
}

async function imageCanvas(bytes, name) {
  const url = URL.createObjectURL(new Blob([bytes]));
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    const size = canvasSize(image.naturalWidth, image.naturalHeight);
    const canvas = document.createElement('canvas');
    Object.assign(canvas, size);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = 'white';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
    return canvas;
  } catch {
    throw new Error('This photo could not be opened. Take another photo, or choose a JPG or PNG image.');
  } finally { URL.revokeObjectURL(url); }
}

export function cancelScan() {
  active?.cancel();
}

export async function scanDocument(bytes, name, isPdf, report = () => {}) {
  if (active) throw new Error('A document is already being scanned.');
  if (!bytes.length) throw new Error('The selected document is empty.');
  if (bytes.length > 40 * 1024 * 1024) throw new Error('Choose a document smaller than 40 MB.');
  const session = { cancelled: false, worker: null };
  active = session;
  let pdf, loadingTask, timer, failScan;
  const stopped = new Promise((_, reject) => {
    failScan = reject;
    session.cancel = () => { session.cancelled = true; reject(new Error('Scan cancelled.')); };
    timer = setTimeout(() => {
      session.cancelled = true;
      reject(new Error('Scanning took too long. Try fewer pages or a clearer photo.'));
    }, 10 * 60 * 1000);
  });
  const check = () => { if (session.cancelled) throw new Error('Scan cancelled.'); };
  const base = new URL(VENDOR, document.baseURI);
  async function recognise(canvas, page, total) {
    check();
    try {
      session.page = page; session.total = total;
      const {data} = await session.worker.recognize(canvas, {}, {text: true, blocks: true});
      check();
      const result = normaliseRecognition(data);
      if (!result.fullText.trim()) throw new Error('No readable text was found on page ' + page + '. Try a clearer photo.');
      return result;
    } finally { canvas.width = 1; canvas.height = 1; }
  }
  const work = async () => {
    report('Loading scanner… The first scan downloads its reading tools.', -1);
    const Tesseract = await loadTesseract(base);
    check();
    const worker = await Tesseract.createWorker('eng', 1, {
      workerPath: new URL('worker.min.js', base).href,
      corePath: new URL('core/', base).href,
      langPath: new URL('lang-best/', base).href.replace(/\/$/, ''),
      workerBlobURL: false,
      // HTTP caching retains the model without Safari IndexedDB worker locks.
      cacheMethod: 'none',
      errorHandler: error => failScan(new Error(error?.message || 'The reading engine stopped. Please retry.')),
      logger: m => {
        if (!session.cancelled && m.status === 'recognizing text') {
          report((session.sections ? 'Reading section ' : 'Reading page ') + (session.page || 1) + ' of ' + (session.total || 1),
            ((session.page || 1) - 1 + m.progress) / (session.total || 1));
        }
      },
    });
    session.worker = worker;
    if (session.cancelled) { await worker.terminate(); check(); }
    await worker.setParameters({tessedit_pageseg_mode: '3', preserve_interword_spaces: '1'});
    check();
    if (!isPdf) {
      const image = await imageCanvas(bytes, name);
      // Prefer page-layout OCR for roster tables. It keeps narrow columns
      // (turn, book-on, book-off and hours) separate. The old portrait-band
      // pass uses single-block OCR and can fuse them into one unreadable token.
      if (image.height > 1000 && image.height > image.width * 1.15) {
        await worker.setParameters({tessedit_pageseg_mode: '3'});
        const {data: pageData} = await worker.recognize(image, {}, {text: true, blocks: true});
        check();
        const pageResult = normaliseRecognition(pageData);
        if (countStructuredRosterRows(pageResult.fullText) >= 3) {
          image.width = 1; image.height = 1;
          return [pageResult];
        }
        try {
          const first = Math.round(image.height * 0.16);
          const step = Math.round(image.width * 0.28);
          const pad = Math.round(image.width * 0.07);
          const bounds = [0, first];
          while (bounds.at(-1) < image.height) bounds.push(Math.min(image.height, bounds.at(-1) + step));
          const results = [];
          session.sections = true;
          await worker.setParameters({tessedit_pageseg_mode: '6'});
          for (let i=0; i<bounds.length-1; i++) {
            check();
            session.page=i+1; session.total=bounds.length-1;
            const start=bounds[i], end=bounds[i+1];
            const top=Math.max(0,start-pad), bottom=Math.min(image.height,end+pad);
            const scale=Math.min(2,3000/image.width,Math.sqrt(4800000/(image.width*(bottom-top))));
            const tile=document.createElement('canvas');
            tile.width=Math.round(image.width*scale); tile.height=Math.round((bottom-top)*scale);
            tile.getContext('2d').drawImage(image,0,top,image.width,bottom-top,0,0,tile.width,tile.height);
            try {
              const {data}=await worker.recognize(tile,{}, {text:true,blocks:true});
              check();
              results.push(normaliseRecognition(data,{scale,offset:top,start,end}));
            } finally {tile.width=1;tile.height=1;}
          }
          const fullText=results.map(r=>r.fullText).join('\n');
          if(!fullText.trim()) throw new Error('No readable text was found. Try a clearer photo.');
          return [{fullText,lines:results.flatMap(r=>r.lines),
            confidence:results.reduce((n,r)=>n+r.confidence,0)/results.length}];
        } finally {image.width=1;image.height=1;}
      }
      return [await recognise(image, 1, 1)];
    }

    const pdfjs = await import(new URL('pdf.mjs', base).href);
    pdfjs.GlobalWorkerOptions.workerSrc = new URL('pdf.worker.mjs', base).href;
    loadingTask = pdfjs.getDocument({data: new Uint8Array(bytes), isEvalSupported: false,
      cMapUrl: new URL('cmaps/', base).href, cMapPacked: true,
      standardFontDataUrl: new URL('standard_fonts/', base).href,
      wasmUrl: new URL('wasm/', base).href});
    pdf = await loadingTask.promise;
    check();
    if (pdf.numPages < 1 || pdf.numPages > 60) throw new Error('Choose a PDF with 1–60 pages.');
    const pages = [];
    for (let i = 1; i <= pdf.numPages; i++) {
      check();
      report('Preparing page ' + i + ' of ' + pdf.numPages, (i - 1) / pdf.numPages);
      const page = await pdf.getPage(i);
      const original = page.getViewport({scale: 2.5});
      const size = canvasSize(original.width, original.height);
      const viewport = page.getViewport({scale: 2.5 * size.width / original.width});
      const canvas = document.createElement('canvas');
      canvas.width = Math.ceil(viewport.width);
      canvas.height = Math.ceil(viewport.height);
      try {
        await page.render({canvasContext: canvas.getContext('2d'), viewport, background: 'white'}).promise;
        check();
        pages.push(await recognise(canvas, i, pdf.numPages));
      } finally { page.cleanup(); canvas.width = 1; canvas.height = 1; }
    }
    return pages;
  };
  try {
    return JSON.stringify(await Promise.race([work(), stopped]));
  } catch (error) {
    if (session.cancelled) throw error;
    throw new Error(error?.message || 'The scanner could not read this document. Try a clearer photo.');
  } finally {
    clearTimeout(timer);
    // Stop outstanding work before allowing the next scan.
    session.cancelled = true;
    await session.worker?.terminate().catch(() => {});
    await loadingTask?.destroy().catch(() => {});
    if (active === session) active = null;
  }
}
if (typeof window !== 'undefined') {
  window.rosterScanDocument = (...args) => scanDocument(...args).catch(error =>
    JSON.stringify({error: error?.message || 'The scanner could not read this document.'}));
  window.rosterCancelScan = cancelScan;
}

// Prepare a temporary JPEG for the free cloud scanner; the upload stays original.
export async function prepareCloudImage(bytes, name) {
  const canvas = await imageCanvas(bytes, name);
  try {
    for (const quality of [0.94, 0.88, 0.8, 0.7, 0.6]) {
      const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', quality));
      if (!blob) throw new Error('The photo could not be prepared.');
      if (blob.size <= 990000) return new Uint8Array(await blob.arrayBuffer());
    }
    throw new Error('The photo could not fit the free scanner limit while retaining readable detail.');
  } finally { canvas.width = 1; canvas.height = 1; }
}
if (typeof window !== 'undefined') window.rosterPrepareCloudImage = prepareCloudImage;
