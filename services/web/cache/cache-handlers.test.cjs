const assert = require("node:assert/strict");
const { after, test } = require("node:test");

const RedisIncrementalCacheHandler = require("./incremental-cache-handler.cjs");
const {
  SharedCacheStore,
  closeSharedStore,
  redisClientOptions,
} = require("./shared-store.cjs");
const useCacheHandler = require("./use-cache-handler.cjs");

after(async () => closeSharedStore());

test("shared Redis cache bounds connection setup without an idle socket timeout", () => {
  const options = redisClientOptions("redis://redis:6379/0", 2_000);
  assert.equal(options.socket.connectTimeout, 2_000);
  assert.equal("socketTimeout" in options.socket, false);
});

test("required production cache rejects a missing Redis URL", () => {
  const previousRequired = process.env.WEB_CACHE_REQUIRED;
  const previousUrl = process.env.WEB_CACHE_REDIS_URL;
  process.env.WEB_CACHE_REQUIRED = "true";
  delete process.env.WEB_CACHE_REDIS_URL;
  try {
    assert.throws(
      () => new SharedCacheStore(),
      /WEB_CACHE_REDIS_URL is required when WEB_CACHE_REQUIRED=true/,
    );
  } finally {
    if (previousRequired === undefined) delete process.env.WEB_CACHE_REQUIRED;
    else process.env.WEB_CACHE_REQUIRED = previousRequired;
    if (previousUrl === undefined) delete process.env.WEB_CACHE_REDIS_URL;
    else process.env.WEB_CACHE_REDIS_URL = previousUrl;
  }
});

async function readStream(stream) {
  const reader = stream.getReader();
  const chunks = [];
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(Buffer.from(value));
    }
  } finally {
    reader.releaseLock();
  }
  return Buffer.concat(chunks);
}

test("incremental cache shares fetch entries and invalidates tags", async () => {
  const handler = new RedisIncrementalCacheHandler();
  const context = { fetchCache: true, kind: "FETCH", tags: ["quran:editions"] };
  await handler.set(
    "fetch-entry",
    {
      kind: "FETCH",
      data: { body: '{"count":1}', headers: {}, status: 200, url: "https://backend/api" },
      revalidate: 3_600,
    },
    context,
  );

  const cached = await handler.get("fetch-entry", context);
  assert.equal(cached.value.data.body, '{"count":1}');

  await handler.revalidateTag("quran:editions");
  assert.equal(await handler.get("fetch-entry", context), null);
});

test("incremental cache round-trips binary route entries", async () => {
  const handler = new RedisIncrementalCacheHandler();
  const context = { fetchCache: false, kind: "APP_ROUTE" };
  await handler.set(
    "binary-entry",
    { kind: "APP_ROUTE", body: Buffer.from([0, 1, 254, 255]), headers: {}, status: 200 },
    context,
  );

  const cached = await handler.get("binary-entry", context);
  assert.deepEqual(cached.value.body, Buffer.from([0, 1, 254, 255]));
});

test("use-cache handler coordinates explicit and soft tags", async () => {
  const timestamp = Date.now();
  const entry = {
    value: new ReadableStream({
      start(controller) {
        controller.enqueue(Buffer.from("shared-value"));
        controller.close();
      },
    }),
    tags: ["audio:reciters"],
    stale: 60,
    timestamp,
    expire: 3_600,
    revalidate: 3_600,
  };
  await useCacheHandler.set("use-cache-entry", Promise.resolve(entry));

  const cached = await useCacheHandler.get("use-cache-entry", ["audio:soft"]);
  assert.equal((await readStream(cached.value)).toString("utf8"), "shared-value");

  await useCacheHandler.updateTags(["audio:reciters"]);
  assert.equal(await useCacheHandler.get("use-cache-entry", []), undefined);
  assert.ok((await useCacheHandler.getExpiration(["audio:reciters"])) >= timestamp);
});
