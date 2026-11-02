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

export function normaliseRecognition(data) {
  const lines = [];
  for (const block of data.blocks || []) {
    for (const paragraph of block.paragraphs || []) {
      for (const line of paragraph.lines || []) {
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
            cell = {text: word.text, left: b.x0, top: b.y0, right: b.x1, bottom: b.y1};
            lines.push(cell);
          } else {
            cell.text += ' ' + word.text;
            cell.right = b.x1;
            cell.top = Math.min(cell.top, b.y0);
            cell.bottom = Math.max(cell.bottom, b.y1);
          }
        }
      }
    }
  }
  return { fullText: data.text || '', lines, confidence: Number(data.confidence) || 0 };
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
  let pdf, loadingTask, timer;
  const stopped = new Promise((_, reject) => {
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
      langPath: new URL('lang/', base).href.replace(/\/$/, ''),
      workerBlobURL: false,
      logger: m => {
        if (!session.cancelled && m.status === 'recognizing text') {
          report('Reading page ' + (session.page || 1) + ' of ' + (session.total || 1),
            ((session.page || 1) - 1 + m.progress) / (session.total || 1));
        }
      },
    });
    session.worker = worker;
    if (session.cancelled) { await worker.terminate(); check(); }
    await worker.setParameters({tessedit_pageseg_mode: '3', preserve_interword_spaces: '1'});
    check();
    if (!isPdf) return [await recognise(await imageCanvas(bytes, name), 1, 1)];

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
