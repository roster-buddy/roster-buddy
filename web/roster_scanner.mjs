// Loaded with the app; OCR libraries/model are fetched only when scanning starts.
// All recognition runs locally. Worker, WASM and language assets are same-origin.
const VENDOR = 'scan_vendor/t7-p6/';
let active = null;
let tesseractLoading;

async function loadPdf(bytes, base) {
  const pdfjs = await import(new URL('pdf.mjs', base).href);
  pdfjs.GlobalWorkerOptions.workerSrc = new URL('pdf.worker.mjs', base).href;
  return pdfjs.getDocument({data: new Uint8Array(bytes), isEvalSupported: false,
    cMapUrl: new URL('cmaps/', base).href, cMapPacked: true,
    standardFontDataUrl: new URL('standard_fonts/', base).href,
    wasmUrl: new URL('wasm/', base).href});
}

// Render only the card's page so even a large pack opens inside Roster Buddy.
export async function renderJobCardPage(bytes, pageNumber) {
  const task = await loadPdf(bytes, new URL(VENDOR, document.baseURI));
  const canvas = document.createElement('canvas');
  try {
    const pdf = await task.promise;
    const page = await pdf.getPage(pageNumber);
    const viewport = page.getViewport({scale: 2.5});
    canvas.width = Math.ceil(viewport.width);
    canvas.height = Math.ceil(viewport.height);
    await page.render({canvasContext: canvas.getContext('2d'), viewport, background: 'white'}).promise;
    const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    if (!blob) throw new Error('The PDF page could not be rendered.');
    return new Uint8Array(await blob.arrayBuffer());
  } finally {
    canvas.width = 1;
    canvas.height = 1;
    await task.destroy();
  }
}
if (typeof window !== 'undefined') window.rosterRenderJobCardPage = renderJobCardPage;

// Use searchable PDF headers when all required labelled fields are present.
export function readJobCardHeader(text) {
  const headerText = text.replace(/[ \t]+/g, ' ').trim();
  const heading = /^(?:LTP|STP|VSTP)\s+WO\d{2,4}\s+\w+\s*$/im;
  const validity = /^(?:VALID FROM|FROM)\s+\d{2}\/\d{2}\/\d{2,4}\s+TO\s+\d{2}\/\d{2}\/\d{2,4}\s*$/im;
  const bookOn = /^(?:BOOK )?ON\s+\d{2}:\d{2}\s*$/im;
  const bookOff = /^(?:BOOK )?OFF\s+\d{2}:\d{2}\s*$/im;
  if (![heading, validity, bookOn, bookOff].every(pattern => pattern.test(headerText))) return null;
  return headerText;
}

export function canvasSize(width, height) {
  if (!(width > 0 && height > 0)) throw new Error('The image has no readable dimensions.');
  const scale = Math.min(1, 3000 / Math.max(width, height), Math.sqrt(4800000 / (width * height)));
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

export function countStructuredRosterRows(text) {
  return (text || '').split(/\r?\n/).filter(line => {
    if (!/\b\d{4}\b/.test(line)) return false;
    const clockColumns = (line.match(/\b(?:[01]?\d|2[0-3]):\d{2}\b/g) || []).length;
    const clockOrHoursColumns = (line.match(/\b(?:[01]?\d|2[0-3])[:.]\d{2}\b/g) || []).length;
    // Printed rostered hours (for example 8.59) must not be mistaken for a
    // missing book-off clock. Some OCR engines use dots for every column, so
    // three complete time/hour values is also accepted.
    return clockColumns >= 2 || clockOrHoursColumns >= 3;
  }).length;
}

export function countPayrollRosterRows(text) {
  return (text || '').split(/\r?\n/).filter(line =>
    /\b\d{4,8}\s+[A-Za-z]{2,5}\b/.test(line)
  ).length;
}

// A page-layout pass is quick and normally preserves the table columns well,
// but a small number of complete rows must not make a partly read page look
// successful. When the page contains a roster-sized set of payroll rows, run
// the slower enlarged band pass unless nearly all of those rows have both
// clocks. The two readings are then offered to the row parser independently.
export function needsDetailedRosterPass(text) {
  const rows = (text || '').split(/\r?\n/).filter(line =>
    /\b\d{4,8}\s+[A-Za-z]{2,5}\b/.test(line));
  if (rows.length < 5) return countStructuredRosterRows(text) < 3;

  // A 36-driver page with 35 good clocks still needs detailed OCR for
  // its one unreadable row. Do not treat hours (8.28) as a book-on time.
  // Leave and non-working codes legitimately have no pair of clocks.
  const noShift = /\b(?:ALD|ALW|AW|ND|NDNA|NONA|NO|ZS|SF|RD)\b/i;
  return rows.some(row => {
    if (noShift.test(row)) return false;
    const clocks = (row.match(/\b(?:[01]?\d|2[0-3]):[0-5]\d\b/g) || []).length;
    const clocksOrHours = (row.match(/\b(?:[01]?\d|2[0-3])[:.][0-5]\d\b/g) || []).length;
    return clocks < 2 && clocksOrHours < 3;
  });
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

// Photos selected from the iPhone viewer can include large black bars above
// and below a comparatively small, shadowed sheet. Crop those bars and flatten
// broad lighting changes before OCR so names, payrolls and shift columns stay
// on the same row.
export function documentVerticalBounds(pixels, width, height) {
  const nearlyBlack = y => {
    let black = 0;
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      if (Math.max(pixels[i], pixels[i + 1], pixels[i + 2]) < 24) black++;
    }
    return black >= width * 0.98;
  };
  let top = 0;
  let bottom = height;
  while (top < bottom && nearlyBlack(top)) top++;
  while (bottom > top && nearlyBlack(bottom - 1)) bottom--;
  return bottom - top >= height * 0.35 ? {top, bottom} : {top: 0, bottom: height};
}

function flattenShadows(imageData) {
  const {data: pixels, width, height} = imageData;
  const stride = width + 1;
  const sums = new Float64Array(stride * (height + 1));
  for (let y = 0; y < height; y++) {
    let row = 0;
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      row += pixels[i] * 0.299 + pixels[i + 1] * 0.587 + pixels[i + 2] * 0.114;
      sums[(y + 1) * stride + x + 1] = sums[y * stride + x + 1] + row;
    }
  }
  const radius = Math.max(6, Math.round(width / 40));
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const x0 = Math.max(0, x - radius);
      const x1 = Math.min(width, x + radius + 1);
      const y0 = Math.max(0, y - radius);
      const y1 = Math.min(height, y + radius + 1);
      const background = (sums[y1 * stride + x1] - sums[y0 * stride + x1] -
        sums[y1 * stride + x0] + sums[y0 * stride + x0]) / ((x1 - x0) * (y1 - y0));
      const i = (y * width + x) * 4;
      const grey = pixels[i] * 0.299 + pixels[i + 1] * 0.587 + pixels[i + 2] * 0.114;
      const value = Math.min(255, Math.round(255 * grey / Math.max(1, background)));
      pixels[i] = pixels[i + 1] = pixels[i + 2] = value;
    }
  }
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
    const raster = ctx.getImageData(0, 0, canvas.width, canvas.height);
    const bounds = documentVerticalBounds(raster.data, canvas.width, canvas.height);
    const cropped = bounds.top + canvas.height - bounds.bottom;
    if (cropped > canvas.height * 0.1 && canvas.width < 1400) {
      const sheetHeight = bounds.bottom - bounds.top;
      const sheet = document.createElement('canvas');
      const scale = Math.min(1800 / canvas.width,
        Math.sqrt(4800000 / (canvas.width * sheetHeight)));
      sheet.width = Math.round(canvas.width * scale);
      sheet.height = Math.round(sheetHeight * scale);
      const sheetContext = sheet.getContext('2d');
      sheetContext.drawImage(canvas, 0, bounds.top, canvas.width, sheetHeight,
        0, 0, sheet.width, sheet.height);
      const prepared = sheetContext.getImageData(0, 0, sheet.width, sheet.height);
      flattenShadows(prepared);
      sheetContext.putImageData(prepared, 0, 0);
      sheet.rosterPrepared = true;
      canvas.width = 1;
      canvas.height = 1;
      return sheet;
    }
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
      if (image.rosterPrepared) {
        await worker.setParameters({tessedit_pageseg_mode: '6'});
        return [await recognise(image, 1, 1)];
      }
      // Prefer page-layout OCR for roster tables. It keeps narrow columns
      // (turn, book-on, book-off and hours) separate. The old portrait-band
      // pass uses single-block OCR and can fuse them into one unreadable token.
      if (image.height > 1000 && image.height > image.width * 1.15) {
        await worker.setParameters({tessedit_pageseg_mode: '3'});
        const {data: pageData} = await worker.recognize(image, {}, {text: true, blocks: true});
        check();
        const pageResult = normaliseRecognition(pageData);
        if (!needsDetailedRosterPass(pageResult.fullText)) {
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
          const detailedText=results.map(r=>r.fullText).join('\n');
          if(!detailedText.trim()) throw new Error('No readable text was found. Try a clearer photo.');
          // Keep the natural page reading as fullText and the enlarged band
          // reading as positioned lines. DailyScanText validates both parses,
          // merges complementary payroll rows, and never joins clocks across
          // different drivers.
          return [{fullText:pageResult.fullText,lines:results.flatMap(r=>r.lines),
            confidence:results.reduce((n,r)=>n+r.confidence,0)/results.length}];
        } finally {image.width=1;image.height=1;}
      }
      return [await recognise(image, 1, 1)];
    }

    loadingTask = await loadPdf(bytes, base);
    pdf = await loadingTask.promise;
    check();
    if (pdf.numPages < 1 || pdf.numPages > 60) throw new Error('Choose a PDF with 1–60 pages.');
    const pages = [];
    for (let i = 1; i <= pdf.numPages; i++) {
      check();
      report('Preparing page ' + i + ' of ' + pdf.numPages, (i - 1) / pdf.numPages);
      const page = await pdf.getPage(i);
      const {items} = await page.getTextContent();
      const text = items.map(item => item.str ? item.str + (item.hasEOL ? '\n' : ' ') : '').join('');
      const header = readJobCardHeader(text);
      if (header) {
        pages.push({fullText: header, lines: [], confidence: null});
        page.cleanup();
        continue;
      }
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

// Isolate the top-right stamp and present three deskewed views to OCR.
// This image is classification-only; it never replaces the roster table.
export async function prepareCloudStamp(bytes, name) {
  const source = await imageCanvas(bytes, name);
  const tileWidth = 900, tileHeight = 600;
  const output = document.createElement('canvas');
  output.width = tileWidth * 3; output.height = tileHeight;
  const ctx = output.getContext('2d');
  ctx.fillStyle = 'white'; ctx.fillRect(0, 0, output.width, output.height);
  try {
    const sx = source.width * 0.40, sw = source.width * 0.60;
    const sh = source.height * 0.27;
    const scale = Math.min(780 / sw, 440 / sh);
    [-12, 0, 12].forEach((degrees, i) => {
      ctx.save();
      ctx.beginPath(); ctx.rect(i * tileWidth, 0, tileWidth, tileHeight); ctx.clip();
      ctx.translate(i * tileWidth + tileWidth / 2, tileHeight / 2);
      ctx.rotate(degrees * Math.PI / 180);
      ctx.filter = 'grayscale(1) contrast(1.6)';
      ctx.drawImage(source, sx, 0, sw, sh, -sw * scale / 2, -sh * scale / 2, sw * scale, sh * scale);
      ctx.restore();
    });
    const blob = await new Promise(resolve => output.toBlob(resolve, 'image/jpeg', 0.90));
    if (!blob || blob.size > 990000) throw new Error('Stamp image unavailable.');
    return new Uint8Array(await blob.arrayBuffer());
  } finally {
    source.width = 1; source.height = 1; output.width = 1; output.height = 1;
  }
}
if (typeof window !== 'undefined') window.rosterPrepareCloudStamp = prepareCloudStamp;
