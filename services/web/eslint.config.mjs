import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTypeScript from "eslint-config-next/typescript";

export default defineConfig([
  ...nextVitals,
  ...nextTypeScript,
  {
    rules: {
      // Existing data-loading effects intentionally expose loading state while
      // synchronizing the UI with the backend. Refactor these alongside a
      // future query-cache adoption instead of hiding requests from users.
      "react-hooks/set-state-in-effect": "off",
      // These callbacks are not compiler-memoized; exhaustive-deps remains the
      // authoritative dependency check for the current client architecture.
      "react-hooks/immutability": "off",
    },
  },
  {
    files: ["cache/**/*.cjs"],
    rules: {
      // Next.js loads custom cache handlers from CommonJS paths in both build workers and the
      // standalone server. Keeping this boundary as CJS also mirrors the upstream handler API.
      "@typescript-eslint/no-require-imports": "off",
    },
  },
  globalIgnores([".next/**", "out/**", "build/**", "next-env.d.ts"]),
]);
