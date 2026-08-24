import { spawn } from "node:child_process";
import { cp, readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { chromium } from "@playwright/test";
import { launch } from "chrome-launcher";
import lighthouse from "lighthouse";

const projectDirectory = fileURLToPath(new URL("../", import.meta.url));
const budgetPath = fileURLToPath(new URL("../lighthouse-budget.json", import.meta.url));
const budget = JSON.parse(await readFile(budgetPath, "utf8"));
const webPort = Number(process.env.LIGHTHOUSE_WEB_PORT || 3110);
const apiPort = Number(process.env.LIGHTHOUSE_API_PORT || 3198);
const baseUrl = `http://127.0.0.1:${webPort}`;
const apiUrl = `http://127.0.0.1:${apiPort}`;
const routeFilter = process.env.LIGHTHOUSE_ROUTE;
const routes = routeFilter
  ? budget.routes.filter((route) => route.path === routeFilter)
  : budget.routes;
const childProcesses = [];

if (routes.length === 0) {
  throw new Error(`LIGHTHOUSE_ROUTE does not match a budgeted route: ${routeFilter}`);
}

function startProcess(command, args, environment = {}) {
  const child = spawn(command, args, {
    cwd: projectDirectory,
    env: { ...process.env, ...environment },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  const appendOutput = (chunk) => {
    output = `${output}${chunk}`.slice(-16_000);
  };
  child.stdout.on("data", appendOutput);
  child.stderr.on("data", appendOutput);
  childProcesses.push({ child, output: () => output });
  return child;
}

async function waitForProcess(child, label) {
  const exitCode = await new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code, signal) => resolve(code ?? signal));
  });
  if (exitCode !== 0) throw new Error(`${label} exited with ${exitCode}`);
}

async function waitForUrl(url, timeoutMs = 60_000) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url, { redirect: "follow" });
      if (response.ok) return response;
      lastError = new Error(`${url} returned HTTP ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for ${url}: ${lastError}`);
}

function stopProcess(child) {
  if (!child.killed) child.kill("SIGTERM");
}

async function stopChildren() {
  for (const { child } of childProcesses.toReversed()) stopProcess(child);
  await Promise.all(
    childProcesses.map(
      ({ child }) =>
        new Promise((resolve) => {
          if (child.exitCode !== null || child.signalCode !== null) return resolve();
          const timeout = setTimeout(() => {
            child.kill("SIGKILL");
            resolve();
          }, 5_000);
          child.once("exit", () => {
            clearTimeout(timeout);
            resolve();
          });
        }),
    ),
  );
}

function describeValue(value, unit = "") {
  return `${Math.round(value * 100) / 100}${unit}`;
}

function assertAtMost(failures, route, label, actual, expected, unit = "") {
  if (typeof actual !== "number" || actual > expected) {
    failures.push(
      `${route}: ${label} ${describeValue(actual ?? Number.NaN, unit)} > ${expected}${unit}`,
    );
  }
}

function resourceRows(lhr) {
  const items = lhr.audits["resource-summary"]?.details?.items;
  if (!Array.isArray(items)) return new Map();
  return new Map(items.map((item) => [item.resourceType, item]));
}

function failingCategoryAudits(lhr, category) {
  const auditReferences = lhr.categories[category]?.auditRefs || [];
  return auditReferences
    .map(({ id }) => lhr.audits[id])
    .filter(
      (audit) =>
        audit &&
        typeof audit.score === "number" &&
        audit.score < 1 &&
        audit.scoreDisplayMode !== "manual" &&
        audit.scoreDisplayMode !== "notApplicable",
    )
    .map((audit) => {
      const items = Array.isArray(audit.details?.items) ? audit.details.items : [];
      const selectors = items
        .slice(0, 3)
        .map((item) => item.node?.selector || item.node?.snippet)
        .filter(Boolean)
        .join(" | ");
      return `${audit.id}=${audit.score}${selectors ? ` [${selectors}]` : ""}`;
    })
    .join(", ");
}

async function validateDocument(route) {
  const response = await fetch(`${baseUrl}${route.path}`);
  if (!response.ok) throw new Error(`${route.path} returned HTTP ${response.status}`);
  const html = await response.text();
  const htmlTag = html.match(/<html\b[^>]*>/i)?.[0] || "";
  const langPattern = new RegExp(`\\blang=["']${route.locale}["']`, "i");
  const directionPattern = new RegExp(`\\bdir=["']${route.direction}["']`, "i");
  if (!langPattern.test(htmlTag) || !directionPattern.test(htmlTag)) {
    throw new Error(
      `${route.path} expected lang=${route.locale} dir=${route.direction}, got ${htmlTag || "no html tag"}`,
    );
  }
}

async function run() {
  startProcess(process.execPath, ["e2e/mock-public-api.mjs"], {
    MOCK_PUBLIC_API_PORT: String(apiPort),
  });
  await waitForUrl(`${apiUrl}/api/v1/quran/editions`);

  const productionEnvironment = {
    BACKEND_INTERNAL_URL: apiUrl,
    SITE_URL: baseUrl,
    NODE_ENV: "production",
  };
  const nextEnvPath = fileURLToPath(new URL("../next-env.d.ts", import.meta.url));
  const nextEnvContents = await readFile(nextEnvPath, "utf8");
  const build = startProcess(
    process.execPath,
    ["node_modules/next/dist/bin/next", "build"],
    productionEnvironment,
  );
  try {
    await waitForProcess(build, "Next.js production build");
  } finally {
    await writeFile(nextEnvPath, nextEnvContents);
  }

  await cp("public", ".next/standalone/public", { recursive: true });
  await cp(".next/static", ".next/standalone/.next/static", { recursive: true });
  startProcess(
    process.execPath,
    [".next/standalone/server.js"],
    {
      HOSTNAME: "127.0.0.1",
      PORT: String(webPort),
      ...productionEnvironment,
    },
  );
  await waitForUrl(`${baseUrl}/ru`, 90_000);

  for (const route of routes) await validateDocument(route);

  const chromePath = process.env.CHROME_PATH || chromium.executablePath();
  const chrome = await launch({
    chromePath,
    chromeFlags: ["--headless=new", "--no-sandbox", "--disable-dev-shm-usage"],
  });
  const failures = [];

  try {
    for (const route of routes) {
      const url = `${baseUrl}${route.path}`;
      const result = await lighthouse(url, {
        port: chrome.port,
        output: "json",
        logLevel: "error",
        onlyCategories: ["performance", "accessibility", "best-practices", "seo"],
        formFactor: "mobile",
        throttlingMethod: "simulate",
        maxWaitForLoad: 45_000,
      });
      if (!result?.lhr) {
        failures.push(`${route.path}: Lighthouse did not produce a report`);
        continue;
      }
      const { lhr } = result;
      if (lhr.runtimeError) {
        failures.push(`${route.path}: ${lhr.runtimeError.code} ${lhr.runtimeError.message}`);
        continue;
      }

      for (const [category, minimum] of Object.entries(budget.categories)) {
        const score = lhr.categories[category]?.score;
        if (typeof score !== "number" || score < minimum) {
          const auditDetails = failingCategoryAudits(lhr, category);
          failures.push(
            `${route.path}: ${category} score ${score ?? "missing"} < ${minimum}` +
              (auditDetails ? ` (${auditDetails})` : ""),
          );
        }
      }
      for (const [audit, maximum] of Object.entries(budget.metricsMs)) {
        assertAtMost(
          failures,
          route.path,
          audit,
          lhr.audits[audit]?.numericValue,
          maximum,
          "ms",
        );
      }
      for (const [audit, maximum] of Object.entries(budget.metricsUnitless)) {
        assertAtMost(
          failures,
          route.path,
          audit,
          lhr.audits[audit]?.numericValue,
          maximum,
        );
      }

      const rows = resourceRows(lhr);
      for (const [resourceType, maximumKiB] of Object.entries(budget.resourceSizesKiB)) {
        assertAtMost(
          failures,
          route.path,
          `${resourceType} transfer size`,
          (rows.get(resourceType)?.transferSize ?? Number.NaN) / 1024,
          maximumKiB,
          "KiB",
        );
      }
      for (const [resourceType, maximumCount] of Object.entries(budget.resourceCounts)) {
        assertAtMost(
          failures,
          route.path,
          `${resourceType} request count`,
          rows.get(resourceType)?.requestCount,
          maximumCount,
        );
      }

      const scores = Object.fromEntries(
        Object.keys(budget.categories).map((category) => [
          category,
          Math.round((lhr.categories[category]?.score ?? 0) * 100),
        ]),
      );
      const totalKiB = Math.round((rows.get("total")?.transferSize ?? 0) / 1024);
      console.log(
        `${route.template} ${route.locale}/${route.direction} ${route.path}: ` +
          `perf=${scores.performance} a11y=${scores.accessibility} ` +
          `best=${scores["best-practices"]} seo=${scores.seo} transfer=${totalKiB}KiB`,
      );
    }
  } finally {
    await chrome.kill();
  }

  if (failures.length > 0) {
    throw new Error(`Lighthouse budget failed:\n- ${failures.join("\n- ")}`);
  }
  console.log(`Lighthouse budgets passed for ${routes.length} localized routes.`);
}

try {
  await run();
} catch (error) {
  for (const processInfo of childProcesses) {
    const output = processInfo.output();
    if (output) process.stderr.write(`\nChild process output:\n${output}\n`);
  }
  console.error(error);
  process.exitCode = 1;
} finally {
  await stopChildren();
}
