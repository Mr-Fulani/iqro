import assert from "node:assert/strict";
import { access } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { DEFAULT_RECITER_PORTRAIT, reciterPortraitUrl } from "./reciter-portraits.ts";

test("the portrait uploaded in the admin comes first", () => {
  const uploaded = "https://media.example.test/reciters/custom.webp";
  assert.equal(reciterPortraitUrl({ slug: "qf-7-mishari-rashid-al-afasy", portrait_url: uploaded }), uploaded);
  assert.equal(reciterPortraitUrl({ slug: "new-reciter", portrait_url: uploaded }), uploaded);
});

test("a curated reciter keeps its own portrait", () => {
  assert.equal(
    reciterPortraitUrl({ slug: "qf-7-mishari-rashid-al-afasy", portrait_url: null }),
    "/reciters/mishari-rashid-al-afasy.webp",
  );
});

test("a reciter without a portrait gets the default figure", async () => {
  assert.equal(reciterPortraitUrl({ slug: "new-reciter", portrait_url: null }), DEFAULT_RECITER_PORTRAIT);
  assert.equal(reciterPortraitUrl({ slug: "new-reciter", portrait_url: "" }), DEFAULT_RECITER_PORTRAIT);
  await access(path.join(import.meta.dirname, "..", "public", DEFAULT_RECITER_PORTRAIT.slice(1)));
});
