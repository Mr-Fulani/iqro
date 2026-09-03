import assert from "node:assert/strict";
import test from "node:test";

import {
  isDuaCategorySlug,
  isDuaCollectionSlug,
} from "./public-route-params.ts";

test("Dua route slugs match the backend SlugField contract", () => {
  assert.equal(isDuaCategorySlug("Morning_Adhkar-2"), true);
  assert.equal(isDuaCollectionSlug("Hisn_Al-Muslim"), true);
  assert.equal(isDuaCategorySlug("not a slug"), false);
  assert.equal(isDuaCollectionSlug("not/a/slug"), false);
});

test("Dua route slug lengths match backend model limits", () => {
  assert.equal(isDuaCategorySlug("a".repeat(120)), true);
  assert.equal(isDuaCategorySlug("a".repeat(121)), false);
  assert.equal(isDuaCollectionSlug("a".repeat(100)), true);
  assert.equal(isDuaCollectionSlug("a".repeat(101)), false);
});
