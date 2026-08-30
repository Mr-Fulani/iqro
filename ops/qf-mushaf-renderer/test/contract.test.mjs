import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { chmod, mkdir, mkdtemp, readFile, realpath, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  ContractError,
  loadAssetLock,
  loadResourceBundle,
  resolvePinnedAsset,
  validatePageGeometry,
  validateRenderRequest,
} from "../lib/contract.mjs";
import { verifyRuntime } from "../lib/runtime.mjs";

const SOURCE_CHECKSUM = "a".repeat(64);

test("render contract rejects resource 11 and unsafe output", () => {
  assert.throws(
    () => validateRenderRequest(request({ sourceId: 11 })),
    (error) => error instanceof ContractError && /resources 1, 5 and 19/.test(error.message),
  );
  assert.throws(
    () => validateRenderRequest(request({ widths: [319] })),
    (error) => error instanceof ContractError && /widths/.test(error.message),
  );
});

test("asset lock requires explicit provider rights and a pinned checksum", async () => {
  const fixture = await fixtureDirectory();
  const lock = fixture.lock();
  lock.license_evidence.rights = lock.license_evidence.rights.slice(0, -1);
  await writeFile(fixture.lockPath, JSON.stringify(lock));
  const checksum = await sha256(fixture.lockPath);

  await assert.rejects(
    loadAssetLock({
      IQRO_QF_RENDERER_ASSET_LOCK: fixture.lockPath,
      IQRO_QF_RENDERER_ASSET_LOCK_SHA256: checksum,
    }),
    (error) => error instanceof ContractError && /every required right/.test(error.message),
  );
  await assert.rejects(
    loadAssetLock({
      IQRO_QF_RENDERER_ASSET_LOCK: fixture.lockPath,
      IQRO_QF_RENDERER_ASSET_LOCK_SHA256: "f".repeat(64),
    }),
    (error) => error instanceof ContractError && /checksum/.test(error.message),
  );
});

test("authorized source bundle is checksum-bound and loads pinned WOFF2/background", async () => {
  const fixture = await fixtureDirectory();
  const lock = fixture.lock();
  await writeFile(fixture.lockPath, JSON.stringify(lock));
  const assetLock = await loadAssetLock({
    IQRO_QF_RENDERER_ASSET_LOCK: fixture.lockPath,
    IQRO_QF_RENDERER_ASSET_LOCK_SHA256: await sha256(fixture.lockPath),
  });

  const bundle = await loadResourceBundle(
    assetLock,
    { resource_id: 5, source_checksum_sha256: SOURCE_CHECKSUM },
    1,
  );

  assert.equal(bundle.geometry.resource_id, 5);
  assert.equal(bundle.backgroundMime, "image/png");
  await assert.rejects(
    loadResourceBundle(
      assetLock,
      { resource_id: 5, source_checksum_sha256: "b".repeat(64) },
      1,
    ),
    (error) => error instanceof ContractError && /not approved/.test(error.message),
  );
});

test("page-font resources resolve every per-page font inside the locked bundle", async () => {
  const fixture = await fixtureDirectory();
  const fontDirectory = join(fixture.root, "resources", "1");
  const pageFontPath = join(fontDirectory, "page-001.woff2");
  const fontsManifestPath = join(fontDirectory, "fonts.json");
  await mkdir(fontDirectory, { recursive: true });
  await writeFile(pageFontPath, Buffer.concat([Buffer.from("wOF2"), Buffer.alloc(32)]));
  const pageFontChecksum = await sha256(pageFontPath);
  await writeFile(
    fontsManifestPath,
    JSON.stringify({
      schema_version: 1,
      fonts: Object.fromEntries(
        Array.from({ length: 604 }, (_, index) => [
          String(index + 1),
          { path: "page-001.woff2", sha256: pageFontChecksum },
        ]),
      ),
    }),
  );
  const geometry = JSON.parse(await readFile(fixture.geometryPath, "utf8"));
  geometry.resource_id = 1;
  await writeFile(fixture.geometryPath, JSON.stringify(geometry));
  const lock = fixture.lock();
  lock.resources = {
    "1": {
      mode: "page-font",
      allowed_source_checksums: [SOURCE_CHECKSUM],
      fonts_manifest: {
        path: "resources/1/fonts.json",
        sha256: await sha256(fontsManifestPath),
      },
      geometry: { path: "geometry.json", sha256: await sha256(fixture.geometryPath) },
    },
  };
  await writeFile(fixture.lockPath, JSON.stringify(lock));
  const assetLock = await loadAssetLock({
    IQRO_QF_RENDERER_ASSET_LOCK: fixture.lockPath,
    IQRO_QF_RENDERER_ASSET_LOCK_SHA256: await sha256(fixture.lockPath),
  });

  const bundle = await loadResourceBundle(
    assetLock,
    { resource_id: 1, source_checksum_sha256: SOURCE_CHECKSUM },
    604,
  );
  assert.equal(bundle.fontPath, await realpath(pageFontPath));
});

test("page geometry must match every QF source word identity", () => {
  const renderRequest = request({});
  const geometry = { canonical_width: 1440, canonical_height: 2208 };
  const exact = {
    words: [
      {
        position_in_page: 1,
        source_id: 101,
        line_number: 1,
        x: 100,
        y: 100,
        width: 200,
        height: 100,
        font_size: 64,
        text_sha256: sha256Text("fixture"),
        anchor: "center",
      },
    ],
  };

  assert.doesNotThrow(() => validatePageGeometry(renderRequest, geometry, exact));
  assert.throws(
    () => validatePageGeometry(renderRequest, geometry, {
      words: [{ ...exact.words[0], source_id: 999 }],
    }),
    (error) => error instanceof ContractError && /identity/.test(error.message),
  );
  assert.throws(
    () => validatePageGeometry(renderRequest, geometry, {
      words: [{ ...exact.words[0], text_sha256: "f".repeat(64) }],
    }),
    (error) => error instanceof ContractError && /identity/.test(error.message),
  );
});

test("pinned assets cannot escape the release directory", async () => {
  const parent = await mkdtemp(join(tmpdir(), "iqro-qf-path-"));
  const root = join(parent, "release");
  const outside = join(parent, "outside.woff2");
  await mkdir(root);
  await writeFile(outside, "outside");
  await assert.rejects(
    resolvePinnedAsset(root, "../outside.woff2", await sha256(outside), "Test asset"),
    (error) => error instanceof ContractError && /escapes/.test(error.message),
  );
});

test("runtime is platform/container bound and probes executables without a shell", async () => {
  const root = await mkdtemp(join(tmpdir(), "iqro-qf-runtime-"));
  const unusualDirectory = join(root, "runtime;still-argv");
  await mkdir(unusualDirectory);
  const chromiumPath = join(unusualDirectory, "chromium");
  const cwebpPath = join(unusualDirectory, "cwebp");
  await executable(chromiumPath, "Chromium 151.0.7922.34");
  await executable(cwebpPath, "1.5.0");
  const digest = `sha256:${"e".repeat(64)}`;
  const assetLock = {
    lock: {
      runtime: {
        playwright_core_version: "1.62.1",
        platform: `${process.platform}-${process.arch}`,
        container_image_digest: digest,
        node: { sha256: await sha256(process.execPath), version: process.version },
        chromium: {
          sha256: await sha256(chromiumPath),
          version: "151.0.7922.34",
        },
        cwebp: { sha256: await sha256(cwebpPath), version: "1.5.0" },
      },
    },
  };
  const environment = {
    IQRO_QF_RENDERER_CONTAINER_IMAGE_DIGEST: digest,
    IQRO_QF_CHROMIUM_EXECUTABLE: chromiumPath,
    IQRO_QF_CWEBP_EXECUTABLE: cwebpPath,
  };

  const runtime = await verifyRuntime(assetLock, environment, {
    installedPlaywrightVersion: "1.62.1",
  });
  assert.equal(runtime.chromium.path, await realpath(chromiumPath));
  await assert.rejects(
    verifyRuntime(
      assetLock,
      { ...environment, IQRO_QF_RENDERER_CONTAINER_IMAGE_DIGEST: `sha256:${"a".repeat(64)}` },
      { installedPlaywrightVersion: "1.62.1" },
    ),
    (error) => error instanceof ContractError && /Container image digest/.test(error.message),
  );
});

async function fixtureDirectory() {
  const root = await mkdtemp(join(tmpdir(), "iqro-qf-renderer-"));
  const evidencePath = join(root, "provider-approval.txt");
  const fontPath = join(root, "font.woff2");
  const backgroundPath = join(root, "background.png");
  const geometryPath = join(root, "geometry.json");
  const lockPath = join(root, "assets.lock.json");
  await writeFile(evidencePath, "Test-only provider approval fixture.\n");
  await writeFile(fontPath, Buffer.concat([Buffer.from("wOF2"), Buffer.alloc(32)]));
  await writeFile(
    backgroundPath,
    Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), Buffer.alloc(32)]),
  );
  const pages = Object.fromEntries(
    Array.from({ length: 604 }, (_, index) => [
      String(index + 1),
      {
        background: { path: "background.png", sha256: "pending" },
        words: index === 0
          ? [{
              position_in_page: 1,
              source_id: 101,
              line_number: 1,
              x: 100,
              y: 100,
              width: 200,
              height: 100,
              font_size: 64,
              text_sha256: sha256Text("fixture"),
              anchor: "center",
            }]
          : [],
      },
    ]),
  );
  const backgroundChecksum = await sha256(backgroundPath);
  for (const page of Object.values(pages)) page.background.sha256 = backgroundChecksum;
  await writeFile(
    geometryPath,
    JSON.stringify({
      schema_version: 1,
      resource_id: 5,
      source_checksum_sha256: SOURCE_CHECKSUM,
      page_count: 604,
      canonical_width: 1440,
      canonical_height: 2208,
      pages,
    }),
  );
  const evidenceChecksum = await sha256(evidencePath);
  const fontChecksum = await sha256(fontPath);
  const geometryChecksum = await sha256(geometryPath);
  return {
    root,
    geometryPath,
    lockPath,
    lock: () => ({
      schema_version: 1,
      release_id: "test-only-1.0.0",
      license_evidence: {
        decision: "approved",
        provider: "Test fixture provider",
        approval_reference: "TEST-ONLY",
        approved_at: "2026-08-30T00:00:00Z",
        path: "provider-approval.txt",
        sha256: evidenceChecksum,
        rights: [
          "cache_provider_fonts_for_server_rendering",
          "create_lossless_webp_derivatives",
          "host_derivatives_in_first_party_object_storage",
          "deliver_derivatives_to_first_party_native_clients",
        ],
      },
      runtime: {
        playwright_core_version: "1.62.1",
        platform: `${process.platform}-${process.arch}`,
        container_image_digest: `sha256:${"e".repeat(64)}`,
        chromium: { sha256: "c".repeat(64), version: "test" },
        cwebp: { sha256: "d".repeat(64), version: "test" },
      },
      resources: {
        "5": {
          mode: "unicode-font",
          allowed_source_checksums: [SOURCE_CHECKSUM],
          font: { path: "font.woff2", sha256: fontChecksum },
          geometry: { path: "geometry.json", sha256: geometryChecksum },
        },
      },
    }),
  };
}

function request({ sourceId = 5, widths = [720] }) {
  return {
    schema_version: 1,
    source: { resource_id: sourceId, source_checksum_sha256: SOURCE_CHECKSUM },
    page: {
      number: 1,
      lines_per_page: 15,
      verse_mapping: { "1": "1-1" },
      words: [{ id: 101, position_in_page: 1, line_number: 1, text: "fixture" }],
    },
    output: { format: "webp", lossless: true, widths },
  };
}

async function sha256(path) {
  return createHash("sha256").update(await readFile(path)).digest("hex");
}

async function executable(path, version) {
  await writeFile(path, `#!/bin/sh\nprintf '%s\\n' '${version}'\n`);
  await chmod(path, 0o755);
}

function sha256Text(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}
