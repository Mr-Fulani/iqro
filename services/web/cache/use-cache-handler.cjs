const { cacheWarning, getSharedStore } = require("./shared-store.cjs");

const CACHE_SCHEMA = 1;
const pendingSets = new Map();

function normalizeTags(tags) {
  return [...new Set((tags ?? []).filter((tag) => typeof tag === "string" && tag))];
}

async function streamToBuffer(stream, maxBytes) {
  const reader = stream.getReader();
  const chunks = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const chunk = Buffer.from(value);
      totalBytes += chunk.byteLength;
      if (totalBytes > maxBytes) {
        const error = new Error("Shared use-cache entry exceeds the configured size limit");
        error.code = "ENTRY_TOO_LARGE";
        throw error;
      }
      chunks.push(chunk);
    }
  } finally {
    reader.releaseLock();
  }
  return Buffer.concat(chunks);
}

function bufferToStream(buffer) {
  return new ReadableStream({
    start(controller) {
      controller.enqueue(buffer);
      controller.close();
    },
  });
}

const store = getSharedStore();

const handler = {
  async get(cacheKey, softTags) {
    const pendingSet = pendingSets.get(cacheKey);
    if (pendingSet) await pendingSet;

    try {
      const stored = await store.getEntry("use-cache", cacheKey);
      if (!stored) return undefined;
      const entry = JSON.parse(stored);
      if (
        !entry ||
        entry.schema !== CACHE_SCHEMA ||
        !Number.isFinite(entry.timestamp) ||
        !Number.isFinite(entry.revalidate) ||
        typeof entry.value !== "string"
      ) {
        return undefined;
      }
      if (Date.now() > entry.timestamp + entry.revalidate * 1_000) return undefined;

      const tags = normalizeTags([...(entry.tags ?? []), ...(softTags ?? [])]);
      const invalidatedAt = await store.getTagExpiration(tags);
      if (invalidatedAt >= entry.timestamp) return undefined;
      return {
        value: bufferToStream(Buffer.from(entry.value, "base64")),
        tags: normalizeTags(entry.tags),
        stale: entry.stale,
        timestamp: entry.timestamp,
        expire: entry.expire,
        revalidate: entry.revalidate,
      };
    } catch (error) {
      cacheWarning("use-cache read", error);
      return undefined;
    }
  },

  async set(cacheKey, pendingEntry) {
    let resolvePending;
    const pending = new Promise((resolve) => {
      resolvePending = resolve;
    });
    pendingSets.set(cacheKey, pending);

    try {
      const entry = await pendingEntry;
      if (entry.expire === 0) return;
      const [returnStream, storageStream] = entry.value.tee();
      entry.value = returnStream;
      const value = await streamToBuffer(storageStream, store.maxEntryBytes);
      const serialized = JSON.stringify({
        schema: CACHE_SCHEMA,
        value: value.toString("base64"),
        tags: normalizeTags(entry.tags),
        stale: entry.stale,
        timestamp: entry.timestamp,
        expire: entry.expire,
        revalidate: entry.revalidate,
      });
      await store.setEntry("use-cache", cacheKey, serialized);
    } catch (error) {
      cacheWarning("use-cache write", error);
    } finally {
      resolvePending();
      pendingSets.delete(cacheKey);
    }
  },

  async refreshTags() {
    // Tag timestamps are read directly from Redis by getExpiration/get, so there is no
    // process-local manifest to refresh. Keeping this method explicit satisfies Next.js'
    // multi-instance handler contract without adding a keyspace scan per request.
  },

  async getExpiration(tags) {
    try {
      return await store.getTagExpiration(normalizeTags(tags));
    } catch (error) {
      cacheWarning("tag expiration read", error);
      return 0;
    }
  },

  async updateTags(tags) {
    await store.updateTags(normalizeTags(tags));
  },
};

module.exports = handler;
