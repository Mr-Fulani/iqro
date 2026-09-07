/** Bounded stdin adapter used by the resumable full-corpus builder. */
const fs = require('node:fs/promises');
const path = require('node:path');
const {renderPage} = require('./raster.cjs');
async function main() {
  const [output, stem] = process.argv.slice(2);
  if (!output || !/^page-\d{3}$/.test(stem)) throw new Error('Expected output directory and page stem');
  const chunks = [];
  let size = 0;
  for await (const chunk of process.stdin) {
    size += chunk.length;
    if (size > 10_000_000) throw new Error('SVG input too large');
    chunks.push(chunk);
  }
  await fs.mkdir(output, {recursive: true});
  const assets = await renderPage(Buffer.concat(chunks), path.resolve(output), stem);
  process.stdout.write(JSON.stringify(assets));
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
