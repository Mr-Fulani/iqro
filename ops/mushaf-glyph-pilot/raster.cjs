/** Offline draft rasterizer. No upload, no URLs, no font rendering, no overwrite. */
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('sharp');

const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const requireValue = (value, message) => { if (!value) throw new Error(message); };
const widths = [720, 1440, 2160];
const expectedRuntime = {sharp: '0.35.4', vips: '8.18.6', rsvg: '2.62.91', webp: '1.6.0'};

function validateSvg(svg) {
  const text = svg.toString('utf8');
  requireValue(!/(?:href|url\(|<script|<image|<use|<text|<foreignObject|<!|<\?|style\s*=)/i.test(text), 'External/text SVG content');
  requireValue(!/<\/?(?!svg\b|title\b|rect\b|path\b)[a-z]/i.test(text), 'Unexpected SVG element');
}

async function writeOnce(file, bytes) {
  try { await fs.writeFile(file, bytes, {flag: 'wx'}); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const stat = await fs.lstat(file);
    requireValue(stat.isFile() && !stat.isSymbolicLink() &&
      (await fs.readFile(file)).equals(Buffer.from(bytes)), 'Existing artifact differs; nothing overwritten');
  }
}

async function renderPage(svg, output, stem) {
  for (const [name, version] of Object.entries(expectedRuntime)) {
    requireValue(sharp.versions[name] === version, `Unverified raster runtime: ${name}`);
  }
  validateSvg(svg);
  requireValue(/^page-\d{3}$/.test(stem), 'Invalid page stem');
  sharp.cache(false);
  sharp.concurrency(1);
  const assets = [];
  for (const width of widths) {
    const height = Math.round(width * 1.6);
    const png = await sharp(svg, {density: width / 1000 * 72, limitInputPixels: 20_000_000})
      .resize(width, height, {fit: 'fill'}).png().toBuffer();
    const webp = await sharp(png).webp({lossless: true, effort: 6}).toBuffer();
    const reference = await sharp(png).ensureAlpha().raw().toBuffer();
    const decoded = await sharp(webp).ensureAlpha().raw().toBuffer();
    requireValue(reference.equals(decoded), 'Lossless pixel comparison failed');
    const metadata = await sharp(webp).metadata();
    requireValue(metadata.format === 'webp' && metadata.width === width && metadata.height === height, 'Wrong raster dimensions');
    const name = `${stem}-w${width}.webp`;
    await writeOnce(path.join(output, name), webp);
    assets.push({path: name, width, height, bytes: webp.length, sha256: sha(webp), lossless: true});
  }
  return assets;
}

async function checkedFile(root, name, expectedHash) {
  const file = path.join(root, name);
  const stat = await fs.lstat(file);
  requireValue(stat.isFile() && !stat.isSymbolicLink() && stat.size <= 10_000_000, 'Invalid input file');
  const bytes = await fs.readFile(file);
  requireValue(sha(bytes) === expectedHash, `Input checksum mismatch: ${name}`);
  return bytes;
}

async function rasterize(source, output) {
  const expected = expectedRuntime;
  for (const [name, version] of Object.entries(expected)) {
    requireValue(sharp.versions[name] === version, `Unverified raster runtime: ${name}`);
  }
  try { await fs.lstat(output); throw new Error('Output already exists; nothing overwritten'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const audit = JSON.parse(await fs.readFile(path.join(source, 'audit.json'), 'utf8'));
  requireValue(audit.status === 'draft' && audit.publication_approved === false, 'Only unpublished drafts');
  requireValue(/^[a-f0-9]{40}$/.test(audit.source_commit), 'Missing source identity');
  requireValue(audit.pages_prepared.length > 0 && audit.pages_prepared.length <= 6, 'Pilot requires 1–6 pages');
  const seen = new Set();
  const inputs = [];
  // Validate every input before creating the output directory.
  for (const entry of audit.pages_prepared) {
    requireValue(Number.isInteger(entry.page) && entry.page >= 1 && entry.page <= 604 && !seen.has(entry.page), 'Invalid page');
    seen.add(entry.page);
    const stem = `page-${String(entry.page).padStart(3, '0')}`;
    const svg = await checkedFile(source, `${stem}.svg`, entry.svg_sha256);
    const geometry = await checkedFile(source, `${stem}.mobile.json`, entry.mobile_sha256);
    // Only our closed path SVG format is accepted: never fetch links or use system fonts.
    validateSvg(svg);
    const model = JSON.parse(geometry);
    requireValue(model.status === 'draft' && model.number === entry.page && model.assets.length === 0 &&
      model.image_width === 1000 && model.image_height === 1600, 'Geometry identity mismatch');
    inputs.push({entry, stem, svg, geometry});
  }
  await fs.mkdir(output); // Exclusive: even a concurrent existing directory is not reused.
  const manifest = {schema_version: 1, status: 'draft', publication_approved: false,
    source_commit: audit.source_commit, renderer: 'iqro-glyph-pilot-raster-1',
    runtime: expected, widths, pages: []};
  sharp.cache(false);
  sharp.concurrency(1);
  for (const {entry, stem, svg, geometry} of inputs) {
    const assets = await renderPage(svg, output, stem);
    const geometryPath = `${stem}.mobile.json`;
    await fs.writeFile(path.join(output, geometryPath), geometry, {flag: 'wx'});
    manifest.pages.push({page: entry.page, source_svg_sha256: entry.svg_sha256,
      geometry: {path: geometryPath, bytes: geometry.length, sha256: sha(geometry)}, assets});
  }
  await fs.writeFile(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2), {flag: 'wx'});
  return manifest;
}

module.exports = {rasterize, checkedFile, renderPage, writeOnce};
if (require.main === module) {
  const [source, output, ...extra] = process.argv.slice(2);
  if (!source || !output || extra.length) {
    process.stderr.write('Usage: node raster.cjs SOURCE_DIRECTORY NEW_OUTPUT_DIRECTORY\n');
    process.exitCode = 1;
  } else {
    rasterize(path.resolve(source), path.resolve(output)).then(manifest => {
      console.log(JSON.stringify({status: manifest.status, pages: manifest.pages.map(p => ({
        page: p.page, geometryBytes: p.geometry.bytes, assets: p.assets.map(a => ({width: a.width, bytes: a.bytes})),
      }))}, null, 2));
    }).catch(error => { console.error(error.message); process.exitCode = 1; });
  }
}
