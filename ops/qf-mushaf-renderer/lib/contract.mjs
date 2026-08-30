import { createHash } from "node:crypto";
import { lstat, readFile, realpath } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const RELEASE_PATTERN = /^[a-z0-9]+(?:[a-z0-9._-]*[a-z0-9])?$/;
const REQUIRED_RIGHTS = new Set([
  "cache_provider_fonts_for_server_rendering",
  "create_lossless_webp_derivatives",
  "host_derivatives_in_first_party_object_storage",
  "deliver_derivatives_to_first_party_native_clients",
]);

export class ContractError extends Error {}

export async function sha256File(path) {
  const payload = await readFile(path);
  return createHash("sha256").update(payload).digest("hex");
}

export async function loadAssetLock(environment) {
  const lockValue = environment.IQRO_QF_RENDERER_ASSET_LOCK;
  const expectedChecksum = environment.IQRO_QF_RENDERER_ASSET_LOCK_SHA256;
  if (!lockValue || !isAbsolute(lockValue)) {
    throw new ContractError("IQRO_QF_RENDERER_ASSET_LOCK must be an absolute path.");
  }
  if (!SHA256_PATTERN.test(expectedChecksum || "")) {
    throw new ContractError("IQRO_QF_RENDERER_ASSET_LOCK_SHA256 must pin the asset lock.");
  }
  const lockPath = await regularNonSymlinkPath(lockValue, "Asset lock");
  if ((await sha256File(lockPath)) !== expectedChecksum) {
    throw new ContractError("Asset lock checksum does not match the pinned SHA-256.");
  }
  const lock = await readJsonObject(lockPath, "Asset lock");
  validateAssetLockShape(lock);
  const root = dirname(lockPath);
  await verifyEvidence(lock.license_evidence, root);
  return { lock, lockPath, lockChecksum: expectedChecksum, root };
}

export function validateAssetLockShape(lock) {
  if (lock.schema_version !== 1) throw new ContractError("Asset lock schema_version must be 1.");
  if (!RELEASE_PATTERN.test(lock.release_id || "")) {
    throw new ContractError("Asset lock release_id is invalid.");
  }
  if (!lock.runtime || typeof lock.runtime !== "object") {
    throw new ContractError("Asset lock runtime section is required.");
  }
  if (!lock.resources || typeof lock.resources !== "object" || Array.isArray(lock.resources)) {
    throw new ContractError("Asset lock resources section is required.");
  }
  const sourceIds = Object.keys(lock.resources);
  if (sourceIds.length === 0 || sourceIds.some((value) => !["1", "5", "19"].includes(value))) {
    throw new ContractError("Only Quran.Foundation resources 1, 5 and 19 may be locked.");
  }
  for (const sourceId of sourceIds) validateResourceShape(Number(sourceId), lock.resources[sourceId]);
}

export async function loadResourceBundle(assetLock, requestSource, pageNumber) {
  const resource = assetLock.lock.resources[String(requestSource.resource_id)];
  if (!resource) throw new ContractError("Requested Mushaf resource is absent from the asset lock.");
  if (!resource.allowed_source_checksums.includes(requestSource.source_checksum_sha256)) {
    throw new ContractError("QF source checksum is not approved by this asset lock.");
  }
  const geometryPath = await resolvePinnedAsset(
    assetLock.root,
    resource.geometry.path,
    resource.geometry.sha256,
    "Geometry manifest",
  );
  const geometry = await readJsonObject(geometryPath, "Geometry manifest");
  validateGeometryManifest(
    geometry,
    requestSource.resource_id,
    requestSource.source_checksum_sha256,
  );
  const pageGeometry = geometry.pages[String(pageNumber)];
  if (!pageGeometry) throw new ContractError("Geometry manifest has no requested page.");

  const fontSpec = await resourceFontSpec(resource, assetLock.root, pageNumber);
  const fontPath = await resolvePinnedAsset(
    assetLock.root,
    fontSpec.path,
    fontSpec.sha256,
    "Mushaf font",
  );
  if (!(await readFile(fontPath)).subarray(0, 4).equals(Buffer.from("wOF2"))) {
    throw new ContractError("Pinned Mushaf font is not a WOFF2 file.");
  }

  const backgroundPath = await resolvePinnedAsset(
    dirname(geometryPath),
    pageGeometry.background.path,
    pageGeometry.background.sha256,
    "Page background",
  );
  const backgroundMime = await imageMime(backgroundPath);
  return {
    resource,
    geometry,
    pageGeometry,
    fontPath,
    backgroundPath,
    backgroundMime,
  };
}

export function validateRenderRequest(request) {
  if (!request || typeof request !== "object" || request.schema_version !== 1) {
    throw new ContractError("Render request schema_version must be 1.");
  }
  const source = request.source;
  const page = request.page;
  const output = request.output;
  if (!source || !page || !output) throw new ContractError("Render request sections are missing.");
  if (![1, 5, 19].includes(source.resource_id)) {
    throw new ContractError("Only resources 1, 5 and 19 are renderable.");
  }
  if (!SHA256_PATTERN.test(source.source_checksum_sha256 || "")) {
    throw new ContractError("Render request source checksum is invalid.");
  }
  if (!Number.isInteger(page.number) || page.number < 1 || page.number > 604) {
    throw new ContractError("Render request page number is invalid.");
  }
  if (!Number.isInteger(page.lines_per_page) || page.lines_per_page < 1 || page.lines_per_page > 30) {
    throw new ContractError("Render request line count is invalid.");
  }
  if (!Array.isArray(page.words) || page.words.length === 0 || page.words.length > 500) {
    throw new ContractError("Render request must contain a bounded non-empty word array.");
  }
  const seenIds = new Set();
  const seenPositions = new Set();
  for (const word of page.words) {
    if (
      !word ||
      !Number.isInteger(word.id) ||
      word.id <= 0 ||
      !Number.isInteger(word.position_in_page) ||
      word.position_in_page <= 0 ||
      !Number.isInteger(word.line_number) ||
      word.line_number <= 0 ||
      word.line_number > page.lines_per_page ||
      typeof word.text !== "string" ||
      word.text.length === 0 ||
      word.text.length > 128 ||
      /[\u0000-\u001f\u007f]/u.test(word.text)
    ) {
      throw new ContractError("Render request contains an invalid word.");
    }
    if (seenIds.has(word.id) || seenPositions.has(word.position_in_page)) {
      throw new ContractError("Render request contains duplicate word identities.");
    }
    seenIds.add(word.id);
    seenPositions.add(word.position_in_page);
  }
  if (output.format !== "webp" || output.lossless !== true) {
    throw new ContractError("Renderer only supports lossless WebP output.");
  }
  if (
    !Array.isArray(output.widths) ||
    output.widths.length === 0 ||
    output.widths.length > 6 ||
    output.widths.some((width) => !Number.isInteger(width) || width < 320 || width > 4096) ||
    new Set(output.widths).size !== output.widths.length
  ) {
    throw new ContractError("Render request widths are invalid.");
  }
  return request;
}

export function validatePageGeometry(request, geometry, pageGeometry) {
  const expectedPositions = new Map(
    request.page.words.map((word) => [
      word.position_in_page,
      {
        id: word.id,
        line_number: word.line_number,
        text_sha256: sha256Text(word.text),
      },
    ]),
  );
  if (!Array.isArray(pageGeometry.words) || pageGeometry.words.length !== expectedPositions.size) {
    throw new ContractError("Page geometry does not cover every source word exactly once.");
  }
  const seen = new Set();
  for (const box of pageGeometry.words) {
    const source = expectedPositions.get(box.position_in_page);
    if (
      !source ||
      source.id !== box.source_id ||
      source.line_number !== box.line_number ||
      source.text_sha256 !== box.text_sha256 ||
      seen.has(box.position_in_page)
    ) {
      throw new ContractError("Page geometry identity does not match the QF snapshot.");
    }
    seen.add(box.position_in_page);
    validateWordBox(box, geometry.canonical_width, geometry.canonical_height);
  }
}

async function verifyEvidence(evidence, root) {
  if (!evidence || evidence.decision !== "approved") {
    throw new ContractError("Provider/license evidence must have an approved decision.");
  }
  if (
    typeof evidence.provider !== "string" ||
    evidence.provider.length < 3 ||
    typeof evidence.approval_reference !== "string" ||
    evidence.approval_reference.length < 3 ||
    typeof evidence.approved_at !== "string" ||
    Number.isNaN(Date.parse(evidence.approved_at))
  ) {
    throw new ContractError("Provider/license evidence metadata is incomplete.");
  }
  const rights = new Set(Array.isArray(evidence.rights) ? evidence.rights : []);
  if ([...REQUIRED_RIGHTS].some((right) => !rights.has(right))) {
    throw new ContractError("Provider/license evidence does not grant every required right.");
  }
  await resolvePinnedAsset(root, evidence.path, evidence.sha256, "Provider/license evidence");
}

function validateResourceShape(sourceId, resource) {
  if (!resource || typeof resource !== "object") throw new ContractError("Resource lock is invalid.");
  const expectedMode = sourceId === 5 ? "unicode-font" : "page-font";
  if (resource.mode !== expectedMode) throw new ContractError("Resource font mode is invalid.");
  if (
    !Array.isArray(resource.allowed_source_checksums) ||
    resource.allowed_source_checksums.length === 0 ||
    resource.allowed_source_checksums.some((value) => !SHA256_PATTERN.test(value))
  ) {
    throw new ContractError("Resource source checksum allowlist is invalid.");
  }
  validatePinnedReference(resource.geometry, "Geometry manifest");
  if (sourceId === 5) validatePinnedReference(resource.font, "Mushaf font");
  else validatePinnedReference(resource.fonts_manifest, "Page-font manifest");
}

async function resourceFontSpec(resource, root, pageNumber) {
  if (resource.mode === "unicode-font") return resource.font;
  const manifestPath = await resolvePinnedAsset(
    root,
    resource.fonts_manifest.path,
    resource.fonts_manifest.sha256,
    "Page-font manifest",
  );
  const manifest = await readJsonObject(manifestPath, "Page-font manifest");
  if (manifest.schema_version !== 1 || !manifest.fonts || typeof manifest.fonts !== "object") {
    throw new ContractError("Page-font manifest is invalid.");
  }
  const expectedPages = Array.from({ length: 604 }, (_, index) => String(index + 1));
  if (Object.keys(manifest.fonts).sort((a, b) => Number(a) - Number(b)).join(",") !== expectedPages.join(",")) {
    throw new ContractError("Page-font manifest must cover pages 1-604 exactly.");
  }
  const font = manifest.fonts[String(pageNumber)];
  validatePinnedReference(font, "Page font");
  return { ...font, path: join(dirname(resource.fonts_manifest.path), font.path) };
}

function validateGeometryManifest(geometry, sourceId, sourceChecksum) {
  if (
    geometry.schema_version !== 1 ||
    geometry.resource_id !== sourceId ||
    geometry.source_checksum_sha256 !== sourceChecksum ||
    geometry.page_count !== 604 ||
    !Number.isInteger(geometry.canonical_width) ||
    geometry.canonical_width < 900 ||
    geometry.canonical_width > 4096 ||
    !Number.isInteger(geometry.canonical_height) ||
    geometry.canonical_height < 1200 ||
    geometry.canonical_height > 8192 ||
    !geometry.pages ||
    typeof geometry.pages !== "object"
  ) {
    throw new ContractError("Geometry manifest identity or dimensions are invalid.");
  }
  const expectedPages = Array.from({ length: 604 }, (_, index) => String(index + 1));
  if (Object.keys(geometry.pages).sort((a, b) => Number(a) - Number(b)).join(",") !== expectedPages.join(",")) {
    throw new ContractError("Geometry manifest must cover pages 1-604 exactly.");
  }
  for (const page of Object.values(geometry.pages)) {
    if (!page || typeof page !== "object") throw new ContractError("Page geometry is invalid.");
    validatePinnedReference(page.background, "Page background");
  }
}

function validateWordBox(box, canvasWidth, canvasHeight) {
  const integers = ["position_in_page", "source_id", "line_number", "x", "y", "width", "height", "font_size"];
  if (integers.some((name) => !Number.isInteger(box[name]))) {
    throw new ContractError("Word geometry values must be integers.");
  }
  if (
    box.position_in_page <= 0 ||
    box.source_id <= 0 ||
    box.line_number <= 0 ||
    box.x < 0 ||
    box.y < 0 ||
    box.width <= 0 ||
    box.height <= 0 ||
    box.font_size <= 0 ||
    !SHA256_PATTERN.test(box.text_sha256 || "") ||
    box.x + box.width > canvasWidth ||
    box.y + box.height > canvasHeight ||
    !["start", "center", "end"].includes(box.anchor)
  ) {
    throw new ContractError("Word geometry is outside the canonical page.");
  }
}

function sha256Text(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function validatePinnedReference(reference, label) {
  if (
    !reference ||
    typeof reference.path !== "string" ||
    !reference.path ||
    isAbsolute(reference.path) ||
    !SHA256_PATTERN.test(reference.sha256 || "")
  ) {
    throw new ContractError(`${label} reference is invalid.`);
  }
}

export async function resolvePinnedAsset(root, pathValue, checksum, label) {
  validatePinnedReference({ path: pathValue, sha256: checksum }, label);
  const candidate = resolve(root, pathValue);
  const rootPath = await realpath(root);
  const resolved = await regularNonSymlinkPath(candidate, label);
  const relation = relative(rootPath, resolved);
  if (relation === ".." || relation.startsWith(`..${sep}`) || isAbsolute(relation)) {
    throw new ContractError(`${label} escapes the asset-lock directory.`);
  }
  if ((await sha256File(resolved)) !== checksum) {
    throw new ContractError(`${label} checksum does not match the asset lock.`);
  }
  return resolved;
}

export async function regularNonSymlinkPath(pathValue, label) {
  let stats;
  try {
    stats = await lstat(pathValue);
  } catch {
    throw new ContractError(`${label} is missing.`);
  }
  if (!stats.isFile() || stats.isSymbolicLink()) {
    throw new ContractError(`${label} must be a regular non-symlink file.`);
  }
  return realpath(pathValue);
}

async function readJsonObject(path, label) {
  let parsed;
  try {
    parsed = JSON.parse(await readFile(path, "utf8"));
  } catch {
    throw new ContractError(`${label} is not valid JSON.`);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new ContractError(`${label} must be a JSON object.`);
  }
  return parsed;
}

async function imageMime(path) {
  const header = (await readFile(path)).subarray(0, 12);
  if (header.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
    return "image/png";
  }
  if (header.subarray(0, 4).equals(Buffer.from("RIFF")) && header.subarray(8, 12).equals(Buffer.from("WEBP"))) {
    return "image/webp";
  }
  throw new ContractError("Pinned page background must be PNG or WebP.");
}
