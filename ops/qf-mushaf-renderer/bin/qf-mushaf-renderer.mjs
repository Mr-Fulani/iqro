#!/usr/bin/env node

import { runCli } from "../lib/cli.mjs";

try {
  await runCli(process.argv.slice(2), process.env);
} catch (error) {
  const message = error instanceof Error ? error.message : "Unknown renderer failure.";
  process.stderr.write(`qf-mushaf-renderer: ${message}\n`);
  process.exitCode = 1;
}
