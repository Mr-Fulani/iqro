import assert from "node:assert/strict";
import test from "node:test";
import { setImmediate } from "node:timers/promises";
import { MushafPageCache } from "./mushaf-page-cache.ts";

test("navigation shares prefetch and only exposes fully prepared pages", async () => {
  let requests = 0;
  let ready!: () => void;
  const assets = new Promise<void>((resolve) => { ready = resolve; });
  const cache = new MushafPageCache(async (page) => { requests += 1; return page; }, () => assets, 604);
  cache.focus(128);
  const preload = cache.load(129);
  const navigation = cache.load(129);
  assert.equal(preload, navigation);
  assert.equal(cache.peek(129), undefined);
  ready();
  assert.equal(await navigation, 129);
  assert.equal(cache.peek(129), 129);
  assert.equal(requests, 1);
});

test("prefetch keeps two pages on either side and stops at book boundaries", async () => {
  const fetched: number[] = [];
  const cache = new MushafPageCache(async (page) => { fetched.push(page); return page; }, async () => {}, 604);
  cache.focus(128);
  await cache.load(128);
  cache.prefetch();
  await setImmediate();
  assert.deepEqual([...fetched].sort((a, b) => a - b), [126, 127, 128, 129, 130]);
  cache.focus(604);
  assert.equal(cache.peek(128), undefined);
  cache.prefetch();
  await setImmediate();
  assert.deepEqual(fetched.slice(5).sort((a, b) => a - b), [602, 603]);
  cache.focus(1);
  cache.prefetch();
  await setImmediate();
  assert.deepEqual(fetched.slice(7).sort((a, b) => a - b), [2, 3]);
});

test("old background chains cannot continue after a distant jump", async () => {
  let finish!: () => void;
  const held = new Promise<void>((resolve) => { finish = resolve; });
  const fetched: number[] = [];
  const prepared: number[] = [];
  const cache = new MushafPageCache(async (page) => { fetched.push(page); await held; return page; }, async (page) => { prepared.push(page); }, 604);
  cache.focus(128);
  cache.prefetch();
  cache.focus(400);
  finish();
  await setImmediate();
  assert.deepEqual(fetched.sort((a, b) => a - b), [127, 129]);
  assert.deepEqual(prepared, []);
  assert.equal(cache.peek(129), undefined);
});

test("a failed prefetch is retried when that page is opened", async () => {
  let attempts = 0;
  const cache = new MushafPageCache(async (page) => {
    if (page === 129 && ++attempts === 1) throw new Error("Temporary failure");
    return page;
  }, async () => {}, 604);
  cache.focus(128);
  cache.prefetch();
  await setImmediate();
  assert.equal(cache.peek(129), undefined);
  cache.focus(129);
  assert.equal(await cache.load(129), 129);
  assert.equal(attempts, 2);
});
