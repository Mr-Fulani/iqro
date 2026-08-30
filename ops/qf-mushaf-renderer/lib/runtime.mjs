import { execFile } from "node:child_process";
import { createRequire } from "node:module";
import { promisify } from "node:util";

import { ContractError, regularNonSymlinkPath, sha256File } from "./contract.mjs";

const execFileAsync = promisify(execFile);
const require = createRequire(import.meta.url);

export async function verifyRuntime(assetLock, environment, dependencies = {}) {
  const runtime = assetLock.lock.runtime;
  if (runtime.playwright_core_version !== "1.62.1") {
    throw new ContractError("Asset lock must pin playwright-core 1.62.1.");
  }
  const installed = dependencies.installedPlaywrightVersion
    ?? require("playwright-core/package.json").version;
  if (installed !== runtime.playwright_core_version) {
    throw new ContractError("Installed playwright-core does not match the asset lock.");
  }
  if (runtime.platform !== `${process.platform}-${process.arch}`) {
    throw new ContractError("Host platform does not match the asset lock.");
  }
  if (
    !/^sha256:[0-9a-f]{64}$/.test(runtime.container_image_digest || "") ||
    environment.IQRO_QF_RENDERER_CONTAINER_IMAGE_DIGEST !== runtime.container_image_digest
  ) {
    throw new ContractError("Container image digest does not match the asset lock.");
  }
  const node = await verifyExecutable(runtime.node, process.execPath, "Node.js");
  const chromium = await verifyExecutable(
    runtime.chromium,
    environment.IQRO_QF_CHROMIUM_EXECUTABLE,
    "Chromium",
  );
  const cwebp = await verifyExecutable(
    runtime.cwebp,
    environment.IQRO_QF_CWEBP_EXECUTABLE,
    "cwebp",
  );
  return { node, chromium, cwebp, playwrightVersion: installed };
}

async function verifyExecutable(spec, environmentPath, label) {
  if (
    !spec ||
    typeof spec !== "object" ||
    !/^[0-9a-f]{64}$/.test(spec.sha256 || "") ||
    typeof spec.version !== "string" ||
    !spec.version
  ) {
    throw new ContractError(`${label} runtime lock is invalid.`);
  }
  if (!environmentPath) throw new ContractError(`${label} executable path is not configured.`);
  const path = await regularNonSymlinkPath(environmentPath, `${label} executable`);
  if ((await sha256File(path)) !== spec.sha256) {
    throw new ContractError(`${label} executable checksum does not match the asset lock.`);
  }
  const versionArguments = label === "cwebp" ? ["-version"] : ["--version"];
  let output;
  try {
    output = await execFileAsync(path, versionArguments, {
      encoding: "utf8",
      maxBuffer: 16 * 1024,
      timeout: 15_000,
      windowsHide: true,
    });
  } catch {
    throw new ContractError(`${label} version probe failed.`);
  }
  const observed = `${output.stdout}\n${output.stderr}`.trim();
  if (!observed.includes(spec.version)) {
    throw new ContractError(`${label} version does not match the asset lock.`);
  }
  return { path, version: spec.version, sha256: spec.sha256 };
}
