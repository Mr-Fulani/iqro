import { spawn } from "node:child_process";
import { cp, readFile, writeFile } from "node:fs/promises";

const requiredEnvironment = ["BACKEND_INTERNAL_URL", "SITE_URL", "HOSTNAME", "PORT"];
for (const name of requiredEnvironment) {
  if (!process.env[name]) throw new Error(`${name} is required for the production test server`);
}

const nextEnvContents = await readFile("next-env.d.ts", "utf8");
const build = spawn(process.execPath, ["node_modules/next/dist/bin/next", "build"], {
  env: { ...process.env, NODE_ENV: "production" },
  stdio: "inherit",
});
let buildExitCode;
try {
  buildExitCode = await new Promise((resolve, reject) => {
    build.once("error", reject);
    build.once("exit", (code, signal) => resolve(code ?? signal));
  });
} finally {
  await writeFile("next-env.d.ts", nextEnvContents);
}
if (buildExitCode !== 0) {
  throw new Error(`Next.js production build exited with ${buildExitCode}`);
}

await cp("public", ".next/standalone/public", { recursive: true });
await cp(".next/static", ".next/standalone/.next/static", { recursive: true });
await import("../.next/standalone/server.js");
