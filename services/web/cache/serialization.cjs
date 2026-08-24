const TYPE_MARKER = "__quran_web_cache_type_v1";

function replacer(key, value) {
  const original = this[key];
  if (Buffer.isBuffer(original) || original instanceof Uint8Array) {
    return { [TYPE_MARKER]: "buffer", value: Buffer.from(original).toString("base64") };
  }
  if (original instanceof Map) {
    return { [TYPE_MARKER]: "map", value: [...original.entries()] };
  }
  return value;
}

function reviver(_key, value) {
  if (!value || typeof value !== "object" || !(TYPE_MARKER in value)) return value;
  if (value[TYPE_MARKER] === "buffer" && typeof value.value === "string") {
    return Buffer.from(value.value, "base64");
  }
  if (value[TYPE_MARKER] === "map" && Array.isArray(value.value)) {
    return new Map(value.value);
  }
  throw new Error("Invalid shared web cache type marker");
}

function serialize(value) {
  return JSON.stringify(value, replacer);
}

function deserialize(value) {
  return JSON.parse(value, reviver);
}

module.exports = { deserialize, serialize };
