import assert from "node:assert/strict";
import test from "node:test";

import type { AyahAnnotation, SyncEntity } from "./api.ts";
import {
  ayahNotes,
  indexAyahAnnotations,
  normalizeAyahHighlightColor,
} from "./ayah-annotations.ts";
import {
  applyRemoteAyahAnnotations,
  enqueueSyncOperation,
  getAyahAnnotations,
  getPendingSyncOperations,
  isAyahAnnotationCacheSeeded,
  markSyncOperationsInFlight,
  removeSyncOperations,
  replaceAyahAnnotationsFromSnapshot,
  retargetQueuedOperations,
  storeLocalAyahAnnotation,
} from "./sync-state.ts";

const store = new Map<string, string>();
Object.assign(globalThis, {
  window: { dispatchEvent: () => true },
  localStorage: {
    getItem: (key: string) => store.get(key) ?? null,
    setItem: (key: string, value: string) => void store.set(key, value),
    removeItem: (key: string) => void store.delete(key),
  },
});

const userId = "00000000-0000-7000-8000-000000000102";

function annotation(overrides: Partial<AyahAnnotation> = {}): AyahAnnotation {
  return {
    id: "01992d87-6c00-7000-8000-000000000901",
    edition_code: "madani-hafs",
    page_number: 42,
    ayah: { id: "a", surah_number: 2, ayah_number: 255 },
    color_key: "blue",
    note: "Аят аль-Курси",
    client_updated_at: "2026-10-01T10:00:00Z",
    revision: 1,
    deleted_at: null,
    updated_at: "2026-10-01T10:00:00Z",
    ...overrides,
  };
}

const remote = (value: AyahAnnotation): SyncEntity => ({ ...value, entity_type: "ayah_annotation" });

test("unknown highlight colors fall back to lime, as in the app", () => {
  assert.equal(normalizeAyahHighlightColor("pink"), "pink");
  assert.equal(normalizeAyahHighlightColor("emerald"), "lime");
  assert.equal(normalizeAyahHighlightColor(undefined), "lime");
});

test("the newest live annotation of the edition wins per ayah", () => {
  const index = indexAyahAnnotations(
    [
      annotation({ id: "old", color_key: "yellow", updated_at: "2026-10-01T09:00:00Z" }),
      annotation({ id: "new", updated_at: "2026-10-02T09:00:00Z" }),
      annotation({ id: "gone", deleted_at: "2026-10-03T09:00:00Z", updated_at: "2026-10-03T09:00:00Z" }),
      annotation({ id: "other", edition_code: "other-edition", updated_at: "2026-10-04T09:00:00Z" }),
    ],
    "madani-hafs",
  );
  assert.deepEqual(Object.keys(index), ["2:255"]);
  assert.equal(index["2:255"].id, "new");
});

test("the notes list skips highlights without a note", () => {
  const notes = ayahNotes([
    annotation({ id: "highlight-only", note: "  " }),
    annotation({ id: "noted" }),
  ]);
  assert.deepEqual(notes.map((item) => item.id), ["noted"]);
});

test("remote copies replace the cache unless a local change is queued", () => {
  store.clear();
  const queued = annotation({ id: "01992d87-6c00-7000-8000-000000000902", revision: 0, note: "local" });
  storeLocalAyahAnnotation(userId, queued);
  enqueueSyncOperation(userId, {
    operation_id: "01992d87-6c00-7000-8000-000000000a01",
    entity_type: "ayah_annotation",
    entity_id: queued.id,
    action: "upsert",
    base_revision: 0,
    client_updated_at: queued.client_updated_at,
    payload: { note: "local" },
  });

  applyRemoteAyahAnnotations(userId, [
    remote(annotation()),
    remote({ ...queued, note: "server", revision: 1 }),
  ]);
  const byId = Object.fromEntries(getAyahAnnotations(userId).map((item) => [item.id, item]));
  assert.equal(byId[annotation().id].note, "Аят аль-Курси");
  assert.equal(byId[queued.id].note, "local");

  applyRemoteAyahAnnotations(userId, [
    remote(annotation({ deleted_at: "2026-10-05T10:00:00Z", revision: 2 })),
  ]);
  assert.deepEqual(getAyahAnnotations(userId).map((item) => item.id), [queued.id]);
});

test("a snapshot seeds the cache and keeps only queued local annotations", () => {
  store.clear();
  assert.equal(isAyahAnnotationCacheSeeded(userId), false);
  storeLocalAyahAnnotation(userId, annotation({ id: "stale" }));
  replaceAyahAnnotationsFromSnapshot(userId, [
    remote(annotation({ id: "fresh" })),
    remote(annotation({ id: "deleted", deleted_at: "2026-10-05T10:00:00Z" })),
  ]);
  assert.deepEqual(getAyahAnnotations(userId).map((item) => item.id), ["fresh"]);
  assert.equal(isAyahAnnotationCacheSeeded(userId), true);
});

const entityId = "01992d87-6c00-7000-8000-000000000903";
const createOperation = {
  operation_id: "01992d87-6c00-7000-8000-000000000b01",
  entity_type: "ayah_annotation" as const,
  entity_id: entityId,
  action: "upsert" as const,
  base_revision: 0,
  client_updated_at: "2026-10-20T10:00:00Z",
  payload: { edition_code: "madani-hafs", surah_number: 2, ayah_number: 255, note: "new" },
};
const deleteOperation = {
  ...createOperation,
  operation_id: "01992d87-6c00-7000-8000-000000000b02",
  action: "delete" as const,
  payload: {},
};

test("deleting an unsent annotation drops its create", () => {
  store.clear();
  enqueueSyncOperation(userId, createOperation);
  enqueueSyncOperation(userId, deleteOperation);
  assert.deepEqual(getPendingSyncOperations(userId), []);
});

test("a delete queued while the create is being pushed waits behind it", () => {
  store.clear();
  enqueueSyncOperation(userId, createOperation);
  markSyncOperationsInFlight([createOperation.operation_id], true);
  enqueueSyncOperation(userId, deleteOperation);
  assert.deepEqual(
    getPendingSyncOperations(userId).map((operation) => [operation.operation_id, operation.action]),
    [[createOperation.operation_id, "upsert"], [deleteOperation.operation_id, "delete"]],
  );

  // The server accepted the create as revision 1: the delete follows it.
  markSyncOperationsInFlight([createOperation.operation_id], false);
  removeSyncOperations(userId, [createOperation.operation_id]);
  retargetQueuedOperations(userId, "ayah_annotation", entityId, entityId, 1);
  assert.deepEqual(getPendingSyncOperations(userId), [{ ...deleteOperation, base_revision: 1 }]);
});

test("an edit made while the create is being pushed is not merged into it", () => {
  store.clear();
  enqueueSyncOperation(userId, createOperation);
  markSyncOperationsInFlight([createOperation.operation_id], true);
  const edit = {
    ...createOperation,
    operation_id: "01992d87-6c00-7000-8000-000000000b03",
    payload: { ...createOperation.payload, note: "edited" },
  };
  enqueueSyncOperation(userId, edit);
  markSyncOperationsInFlight([createOperation.operation_id], false);
  assert.deepEqual(getPendingSyncOperations(userId), [createOperation, edit]);
});
