import { cp, mkdir, readdir, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = path.dirname(fileURLToPath(import.meta.url));
const modules = path.join(root, 'node_modules');
const dest = path.join(root, '..', 'web', 'scan_vendor', 't7-p6');
await rm(dest, {recursive: true, force: true});
await mkdir(path.join(dest, 'core'), {recursive: true});
await mkdir(path.join(dest, 'lang-best'), {recursive: true});
for (const name of ['tesseract.min.js', 'worker.min.js']) {
  await cp(path.join(modules, 'tesseract.js', 'dist', name), path.join(dest, name));
}
for (const name of await readdir(path.join(modules, 'tesseract.js-core'))) {
  if (name.startsWith('tesseract-core') && (name.endsWith('.wasm') || name.endsWith('.wasm.js'))) {
    await cp(path.join(modules, 'tesseract.js-core', name), path.join(dest, 'core', name));
  }
}
await cp(path.join(modules, '@tesseract.js-data/eng/4.0.0_best_int/eng.traineddata.gz'),
  path.join(dest, 'lang-best/eng.traineddata.gz'));
for (const name of ['pdf.mjs', 'pdf.worker.mjs']) {
  await cp(path.join(modules, 'pdfjs-dist', 'legacy/build', name), path.join(dest, name));
}
await cp(path.join(modules, 'pdfjs-dist/cmaps'), path.join(dest, 'cmaps'), {recursive: true});
await cp(path.join(modules, 'pdfjs-dist/standard_fonts'), path.join(dest, 'standard_fonts'), {recursive: true});
await cp(path.join(modules, 'pdfjs-dist/wasm'), path.join(dest, 'wasm'), {recursive: true});
for (const [pkg, filename] of [['tesseract.js','LICENSE.md'], ['tesseract.js-core','LICENSE'], ['pdfjs-dist','LICENSE']]) {
  await cp(path.join(modules, pkg, filename), path.join(dest, pkg + '-LICENSE'));
}
console.log('Prepared same-origin browser OCR and PDF assets.');
