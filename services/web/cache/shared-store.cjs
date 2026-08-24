const { createHash } = require("node:crypto");
const { createClient } = require("@redis/client");

const DEFAULT_ENTRY_TTL_SECONDS = 86_400;
const DEFAULT_TAG_TTL_SECONDS = 172_800;
const DEFAULT_MAX_ENTRY_BYTES = 8 * 1024 * 1024;
const DEFAULT_CONNECT_TIMEOUT_MS = 2_000;
const DEFAULT_RETRY_DELAY_MS = 5_000;
const KEY_PREFIX_PATTERN = /^[A-Za-z0-9:_-]{1,128}$/;

function positiveInteger(name, defaultValue) {
  const rawValue = process.env[name]?.trim();
  const value = rawValue ? Number(rawValue) : defaultValue;
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return value;
}

function booleanValue(name, defaultValue = false) {
  const rawValue = process.env[name]?.trim().toLowerCase();
  if (!rawValue) return defaultValue;
  if (["1", "true", "yes", "on"].includes(rawValue)) return true;
  if (["0", "false", "no", "off"].includes(rawValue)) return false;
  throw new Error(`${name} must be a boolean`);
}

function redisUrl() {
  const value = process.env.WEB_CACHE_REDIS_URL?.trim() ?? "";
  if (!value) return "";
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error("WEB_CACHE_REDIS_URL must be a valid Redis URL");
  }
  if (
    !["redis:", "rediss:"].includes(parsed.protocol) ||
    !parsed.hostname ||
    parsed.search ||
    parsed.hash ||
    !/^\/(?:\d+)?$/.test(parsed.pathname)
  ) {
    throw new Error(
      "WEB_CACHE_REDIS_URL must be a redis:// or rediss:// URL with a host and numeric database",
    );
  }
  return value;
}

function cacheWarning(operation, error) {
  const code =
    error && typeof error === "object" && typeof error.code === "string"
      ? error.code
      : "unknown";
  console.warn(`[web-cache] ${operation} failed (${code})`);
}

function hash(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

class SharedCacheStore {
  constructor() {
    this.url = redisUrl();
    this.required = booleanValue("WEB_CACHE_REQUIRED");
    if (this.required && !this.url) {
      throw new Error("WEB_CACHE_REDIS_URL is required when WEB_CACHE_REQUIRED=true");
    }

    this.keyPrefix =
      process.env.WEB_CACHE_KEY_PREFIX?.trim() || "quran-platform:web-cache:v1";
    if (!KEY_PREFIX_PATTERN.test(this.keyPrefix)) {
      throw new Error(
        "WEB_CACHE_KEY_PREFIX must contain only letters, digits, colon, underscore, or dash",
      );
    }

    this.entryTtlSeconds = positiveInteger(
      "WEB_CACHE_ENTRY_TTL_SECONDS",
      DEFAULT_ENTRY_TTL_SECONDS,
    );
    this.tagTtlSeconds = positiveInteger(
      "WEB_CACHE_TAG_TTL_SECONDS",
      DEFAULT_TAG_TTL_SECONDS,
    );
    if (this.tagTtlSeconds < this.entryTtlSeconds) {
      throw new Error("WEB_CACHE_TAG_TTL_SECONDS must not be shorter than entry TTL");
    }
    this.maxEntryBytes = positiveInteger(
      "WEB_CACHE_MAX_ENTRY_BYTES",
      DEFAULT_MAX_ENTRY_BYTES,
    );
    this.connectTimeoutMs = positiveInteger(
      "WEB_CACHE_CONNECT_TIMEOUT_MS",
      DEFAULT_CONNECT_TIMEOUT_MS,
    );
    this.retryDelayMs = positiveInteger("WEB_CACHE_RETRY_DELAY_MS", DEFAULT_RETRY_DELAY_MS);

    this.client = undefined;
    this.connectPromise = undefined;
    this.retryAfter = 0;
    this.memoryEntries = new Map();
    this.memoryTags = new Map();
  }

  entryKey(scope, key) {
    return `${this.keyPrefix}:entry:${scope}:${hash(key)}`;
  }

  tagsKey() {
    return `${this.keyPrefix}:tags`;
  }

  async redisClient() {
    if (!this.url) return null;
    if (this.client?.isOpen) return this.client;
    if (this.connectPromise) return this.connectPromise;
    if (Date.now() < this.retryAfter) {
      const error = new Error("Redis cache reconnect is cooling down");
      error.code = "CACHE_RETRY_DELAY";
      throw error;
    }

    const client = createClient({
      url: this.url,
      disableOfflineQueue: true,
      socket: {
        connectTimeout: this.connectTimeoutMs,
        socketTimeout: this.connectTimeoutMs,
        reconnectStrategy: (retries) => (retries >= 2 ? false : Math.min(250 * 2 ** retries, 1_000)),
      },
    });
    client.on("error", (error) => cacheWarning("Redis connection", error));
    this.client = client;
    this.connectPromise = client
      .connect()
      .then(() => client)
      .catch((error) => {
        this.retryAfter = Date.now() + this.retryDelayMs;
        if (this.client === client) this.client = undefined;
        if (client.isOpen) client.destroy();
        throw error;
      })
      .finally(() => {
        this.connectPromise = undefined;
      });
    return this.connectPromise;
  }

  async getEntry(scope, key) {
    const storageKey = this.entryKey(scope, key);
    const client = await this.redisClient();
    if (client) return client.get(storageKey);

    const record = this.memoryEntries.get(storageKey);
    if (!record) return null;
    if (record.expiresAt <= Date.now()) {
      this.memoryEntries.delete(storageKey);
      return null;
    }
    return record.value;
  }

  async setEntry(scope, key, value) {
    const storageKey = this.entryKey(scope, key);
    const client = await this.redisClient();
    if (client) {
      await client.set(storageKey, value, { EX: this.entryTtlSeconds });
      return;
    }
    this.memoryEntries.set(storageKey, {
      value,
      expiresAt: Date.now() + this.entryTtlSeconds * 1_000,
    });
  }

  async deleteEntry(scope, key) {
    const storageKey = this.entryKey(scope, key);
    const client = await this.redisClient();
    if (client) {
      await client.del(storageKey);
      return;
    }
    this.memoryEntries.delete(storageKey);
  }

  async getTagExpiration(tags) {
    const uniqueTags = [...new Set(tags.filter((tag) => typeof tag === "string" && tag))];
    if (uniqueTags.length === 0) return 0;

    const members = uniqueTags.map((tag) => hash(tag));
    const client = await this.redisClient();
    let values;
    if (client) {
      values = await client.zmScore(this.tagsKey(), members);
    } else {
      const now = Date.now();
      values = members.map((member) => {
        const record = this.memoryTags.get(member);
        if (!record || record.expiresAt <= now) {
          if (record) this.memoryTags.delete(member);
          return null;
        }
        return record.timestamp;
      });
    }
    return Math.max(...values.map((value) => Number(value) || 0), 0);
  }

  async updateTags(tags) {
    const uniqueTags = [...new Set(tags.filter((tag) => typeof tag === "string" && tag))];
    if (uniqueTags.length === 0) return;

    const timestamp = Date.now();
    const client = await this.redisClient();
    if (client) {
      const transaction = client.multi();
      transaction.zAdd(
        this.tagsKey(),
        uniqueTags.map((tag) => ({ score: timestamp, value: hash(tag) })),
      );
      transaction.zRemRangeByScore(
        this.tagsKey(),
        0,
        timestamp - this.tagTtlSeconds * 1_000,
      );
      transaction.expire(this.tagsKey(), this.tagTtlSeconds);
      await transaction.exec();
      return;
    }

    const expiresAt = timestamp + this.tagTtlSeconds * 1_000;
    for (const tag of uniqueTags) {
      this.memoryTags.set(hash(tag), { timestamp, expiresAt });
    }
  }

  async close() {
    if (this.connectPromise) {
      try {
        await this.connectPromise;
      } catch {
        // A failed connection has already reset the client and set the retry delay.
      }
    }
    const client = this.client;
    this.client = undefined;
    if (client?.isOpen) await client.close();
  }
}

let sharedStore;

function getSharedStore() {
  sharedStore ??= new SharedCacheStore();
  return sharedStore;
}

async function closeSharedStore() {
  if (!sharedStore) return;
  const store = sharedStore;
  sharedStore = undefined;
  await store.close();
}

module.exports = { SharedCacheStore, cacheWarning, closeSharedStore, getSharedStore };
