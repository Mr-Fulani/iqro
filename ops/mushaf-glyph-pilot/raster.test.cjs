const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {rasterize, checkedFile} = require('./raster.cjs');

const sha = b => crypto.createHash('sha256').update(b).digest('hex');
async function fixture(t, svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1600"><path d="M0 0 L1000 0 L1000 1600 L0 1600 Z"/></svg>') {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'iqro-raster-test-'));
  // Only test-owned synthetic fixtures, not source assets or build directories.
  t.after(() => fs.rm(root, {recursive: true}));
  const geometry = JSON.stringify({number: 1, status: 'draft', assets: [], image_width: 1000, image_height: 1600});
  const audit = {status: 'draft', publication_approved: false, source_commit: 'a'.repeat(40),
    pages_prepared: [{page: 1, svg_sha256: sha(svg), mobile_sha256: sha(geometry)}]};
  await fs.writeFile(path.join(root, 'page-001.svg'), svg, {flag: 'wx'});
  await fs.writeFile(path.join(root, 'page-001.mobile.json'), geometry, {flag: 'wx'});
  await fs.writeFile(path.join(root, 'audit.json'), JSON.stringify(audit), {flag: 'wx'});
  return root;
}

test('prepares three lossless sizes and never overwrites a result', async t => {
  const root = await fixture(t);
  const output = path.join(root, 'result');
  const manifest = await rasterize(root, output);
  assert.equal(manifest.publication_approved, false);
  assert.deepEqual(manifest.pages[0].assets.map(a => a.width), [720, 1440, 2160]);
  for (const asset of manifest.pages[0].assets) {
    const bytes = await fs.readFile(path.join(output, asset.path));
    assert.equal(sha(bytes), asset.sha256);
    assert.equal(bytes.length, asset.bytes);
    assert.equal(asset.lossless, true);
  }
  const before = await fs.readFile(path.join(output, 'manifest.json'));
  await assert.rejects(rasterize(root, output), /nothing overwritten/);
  assert.deepEqual(await fs.readFile(path.join(output, 'manifest.json')), before);
});

test('rejects tampered input before exposing a bundle', async t => {
  const root = await fixture(t);
  await fs.appendFile(path.join(root, 'page-001.svg'), 'tampered');
  await assert.rejects(rasterize(root, path.join(root, 'result')), /checksum mismatch/);
  await assert.rejects(fs.lstat(path.join(root, 'result')), {code: 'ENOENT'});
});

test('rejects remote content even with a matching local checksum', async t => {
  const root = await fixture(t, '<svg><image href="https://example.invalid/font.svg"/></svg>');
  await assert.rejects(rasterize(root, path.join(root, 'result')), /External\/text SVG content/);
  await assert.rejects(fs.lstat(path.join(root, 'result')), {code: 'ENOENT'});
});

test('rejects symlink input', async t => {
  const root = await fixture(t);
  await fs.symlink(path.join(root, 'page-001.svg'), path.join(root, 'linked.svg'));
  await assert.rejects(checkedFile(root, 'linked.svg', 'a'.repeat(64)), /Invalid input file/);
});
