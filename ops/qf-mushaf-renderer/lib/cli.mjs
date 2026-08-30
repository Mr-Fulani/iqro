import { lstat, readFile, realpath } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";

import {
  ContractError,
  loadAssetLock,
  loadResourceBundle,
  validateRenderRequest,
} from "./contract.mjs";
import { renderPage } from "./render.mjs";
import { verifyRuntime } from "./runtime.mjs";

const MAX_REQUEST_BYTES = 16 * 1024 * 1024;

export async function runCli(argumentsValue, environment) {
  const command = argumentsValue[0];
  if (command === "--version" && argumentsValue.length === 1) {
    const assetLock = await loadAssetLock(environment);
    const runtime = await verifyRuntime(assetLock, environment);
    process.stdout.write(
      `iqro-qf-renderer-1.0.0+pw.${runtime.playwrightVersion}+lock.${assetLock.lockChecksum.slice(0, 12)}\n`,
    );
    return;
  }
  if (command !== "render-page") throw new ContractError("Expected --version or render-page.");
  const requestValue = option(argumentsValue, "--request");
  const outputValue = option(argumentsValue, "--output");
  if (!requestValue || !outputValue || argumentsValue.length !== 5) {
    throw new ContractError("render-page requires exactly --request and --output.");
  }
  const requestPath = await regularInput(requestValue);
  const outputDirectory = await safeOutputDirectory(outputValue);
  const requestStats = await lstat(requestPath);
  if (requestStats.size <= 0 || requestStats.size > MAX_REQUEST_BYTES) {
    throw new ContractError("Render request exceeds the bounded size limit.");
  }
  let request;
  try {
    request = validateRenderRequest(JSON.parse(await readFile(requestPath, "utf8")));
  } catch (error) {
    if (error instanceof ContractError) throw error;
    throw new ContractError("Render request is not valid JSON.");
  }
  const assetLock = await loadAssetLock(environment);
  const runtime = await verifyRuntime(assetLock, environment);
  const bundle = await loadResourceBundle(assetLock, request.source, request.page.number);
  await renderPage({ request, bundle, runtime, outputDirectory });
}

function option(argumentsValue, name) {
  const index = argumentsValue.indexOf(name);
  if (index < 0 || index + 1 >= argumentsValue.length) return undefined;
  return argumentsValue[index + 1];
}

async function regularInput(pathValue) {
  if (!isAbsolute(pathValue)) throw new ContractError("Request path must be absolute.");
  const stats = await lstat(pathValue).catch(() => null);
  if (!stats?.isFile() || stats.isSymbolicLink()) {
    throw new ContractError("Request must be a regular non-symlink file.");
  }
  return realpath(pathValue);
}

async function safeOutputDirectory(pathValue) {
  if (!isAbsolute(pathValue)) throw new ContractError("Output path must be absolute.");
  const stats = await lstat(pathValue).catch(() => null);
  if (!stats?.isDirectory() || stats.isSymbolicLink()) {
    throw new ContractError("Output must be an existing non-symlink directory.");
  }
  const path = await realpath(pathValue);
  for (const filename of ["manifest.json", "canonical.png"]) {
    const target = resolve(path, filename);
    const existing = await lstat(target).catch(() => null);
    if (existing) throw new ContractError("Output directory contains renderer-owned files.");
  }
  return path;
}
