const { cacheWarning, getSharedStore } = require("./shared-store.cjs");
const { deserialize, serialize } = require("./serialization.cjs");

const CACHE_SCHEMA = 1;
const CACHE_TAGS_HEADER = "x-next-cache-tags";

function normalizeTags(tags) {
  return [...new Set((tags ?? []).filter((tag) => typeof tag === "string" && tag))];
}

function entryTags(entry, context) {
  const tags = [...(context.tags ?? []), ...(context.softTags ?? [])];
  if (entry.value?.kind === "FETCH") tags.push(...(entry.value.tags ?? []));

  const headerTags = entry.value?.headers?.[CACHE_TAGS_HEADER];
  if (typeof headerTags === "string") tags.push(...headerTags.split(","));
  return normalizeTags(tags);
}

module.exports = class RedisIncrementalCacheHandler {
  constructor() {
    this.store = getSharedStore();
  }

  async get(key, context) {
    try {
      const stored = await this.store.getEntry("incremental", key);
      if (!stored) return null;
      const entry = deserialize(stored);
      if (
        !entry ||
        entry.schema !== CACHE_SCHEMA ||
        !Number.isFinite(entry.lastModified) ||
        !("value" in entry)
      ) {
        return null;
      }

      const invalidatedAt = await this.store.getTagExpiration(entryTags(entry, context));
      if (invalidatedAt >= entry.lastModified) return null;
      return { lastModified: entry.lastModified, value: entry.value };
    } catch (error) {
      cacheWarning("incremental cache read", error);
      return null;
    }
  }

  async set(key, data, context) {
    try {
      if (data === null) {
        await this.store.deleteEntry("incremental", key);
        return;
      }
      const value =
        data.kind === "FETCH"
          ? { ...data, tags: normalizeTags([...(data.tags ?? []), ...(context.tags ?? [])]) }
          : data;
      const serialized = serialize({ schema: CACHE_SCHEMA, lastModified: Date.now(), value });
      if (Buffer.byteLength(serialized, "utf8") > this.store.maxEntryBytes) {
        cacheWarning("incremental cache entry size limit", { code: "ENTRY_TOO_LARGE" });
        return;
      }
      await this.store.setEntry("incremental", key, serialized);
    } catch (error) {
      cacheWarning("incremental cache write", error);
    }
  }

  async revalidateTag(tags) {
    const normalized = normalizeTags(Array.isArray(tags) ? tags : [tags]);
    await this.store.updateTags(normalized);
  }

  resetRequestCache() {}
};
