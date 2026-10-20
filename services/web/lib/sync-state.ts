import type { AyahAnnotation, SyncEntity, SyncEntityType, SyncOperation } from "./api";

const SYNC_STORAGE_PREFIX = "quran_platform_sync_v1";
export const SYNC_STATE_EVENT = "quran-platform-sync-state";

type StoredSyncState = {
  cursor: number;
  outbox: SyncOperation[];
  reading_position_ids: Record<string, string>;
  // Ayah annotations have no REST list, so the web keeps the synced copy here.
  // `annotations_seeded` is false for state written before this cache existed:
  // such a cursor already skipped older annotations, so they need one snapshot.
  annotations: Record<string, AyahAnnotation>;
  annotations_seeded: boolean;
};

const emptyState = (): StoredSyncState => ({
  cursor: 0,
  outbox: [],
  reading_position_ids: {},
  annotations: {},
  annotations_seeded: false,
});

const storageKey = (userId: string) => `${SYNC_STORAGE_PREFIX}:${userId}`;

function isSyncOperation(value: unknown): value is SyncOperation {
  if (!value || typeof value !== "object") return false;
  const operation = value as Partial<SyncOperation>;
  return (
    typeof operation.operation_id === "string" &&
    typeof operation.entity_id === "string" &&
    ["reading_position", "bookmark", "ayah_annotation", "reminder"].includes(operation.entity_type || "") &&
    ["upsert", "delete"].includes(operation.action || "") &&
    Number.isInteger(operation.base_revision) &&
    typeof operation.client_updated_at === "string" &&
    Boolean(operation.payload) &&
    typeof operation.payload === "object"
  );
}

function isAyahAnnotation(value: unknown): value is AyahAnnotation {
  if (!value || typeof value !== "object") return false;
  const annotation = value as Partial<AyahAnnotation>;
  return (
    typeof annotation.id === "string" &&
    typeof annotation.edition_code === "string" &&
    Boolean(annotation.ayah) &&
    typeof annotation.ayah?.surah_number === "number" &&
    typeof annotation.ayah?.ayah_number === "number" &&
    typeof annotation.color_key === "string" &&
    typeof annotation.note === "string" &&
    Number.isInteger(annotation.revision)
  );
}

function readState(userId: string): StoredSyncState {
  if (typeof window === "undefined") return emptyState();
  try {
    const raw = localStorage.getItem(storageKey(userId));
    if (!raw) return emptyState();
    const parsed = JSON.parse(raw) as Partial<StoredSyncState>;
    return {
      cursor:
        typeof parsed.cursor === "number" && Number.isInteger(parsed.cursor) && parsed.cursor >= 0
          ? parsed.cursor
          : 0,
      outbox: Array.isArray(parsed.outbox) ? parsed.outbox.filter(isSyncOperation) : [],
      reading_position_ids:
        parsed.reading_position_ids && typeof parsed.reading_position_ids === "object"
          ? parsed.reading_position_ids
          : {},
      annotations:
        parsed.annotations && typeof parsed.annotations === "object"
          ? Object.fromEntries(
              Object.values(parsed.annotations)
                .filter(isAyahAnnotation)
                .map((annotation) => [annotation.id, annotation]),
            )
          : {},
      annotations_seeded: parsed.annotations_seeded === true,
    };
  } catch {
    return emptyState();
  }
}

function writeState(userId: string, state: StoredSyncState): void {
  if (typeof window === "undefined") return;
  localStorage.setItem(storageKey(userId), JSON.stringify(state));
  window.dispatchEvent(new CustomEvent(SYNC_STATE_EVENT, { detail: { userId } }));
}

export function getSyncCursor(userId: string): number {
  return readState(userId).cursor;
}

export function setSyncCursor(userId: string, cursor: number): void {
  const state = readState(userId);
  state.cursor = cursor;
  writeState(userId, state);
}

export function getPendingSyncOperations(userId: string): SyncOperation[] {
  return readState(userId).outbox;
}

export function getPendingSyncCount(userId: string): number {
  return readState(userId).outbox.length;
}

export function clearSyncState(userId: string): void {
  if (typeof window === "undefined") return;
  localStorage.removeItem(storageKey(userId));
  window.dispatchEvent(new CustomEvent(SYNC_STATE_EVENT, { detail: { userId } }));
}

export function enqueueSyncOperation(userId: string, operation: SyncOperation): void {
  const state = readState(userId);
  const existingIndex = state.outbox.findIndex(
    (candidate) =>
      candidate.entity_type === operation.entity_type &&
      candidate.entity_id === operation.entity_id,
  );

  if (existingIndex < 0) {
    state.outbox.push(operation);
  } else {
    const existing = state.outbox[existingIndex];
    if (existing.action === "delete") return;
    if (existing.base_revision === 0 && operation.action === "delete") {
      state.outbox.splice(existingIndex, 1);
    } else {
      state.outbox[existingIndex] = {
        ...operation,
        base_revision: existing.base_revision,
        payload:
          operation.action === "delete"
            ? {}
            : { ...existing.payload, ...operation.payload },
      };
    }
  }
  writeState(userId, state);
}

export function replaceSyncOperation(
  userId: string,
  previousOperationId: string,
  operation: SyncOperation,
): void {
  const state = readState(userId);
  const index = state.outbox.findIndex(
    (candidate) => candidate.operation_id === previousOperationId,
  );
  if (index >= 0) state.outbox[index] = operation;
  else state.outbox.push(operation);
  writeState(userId, state);
}

export function removeSyncOperations(userId: string, operationIds: string[]): void {
  if (operationIds.length === 0) return;
  const removed = new Set(operationIds);
  const state = readState(userId);
  state.outbox = state.outbox.filter((operation) => !removed.has(operation.operation_id));
  writeState(userId, state);
}

export function discardEntityOperation(
  userId: string,
  entityType: SyncEntityType,
  entityId: string,
): void {
  const state = readState(userId);
  const nextOutbox = state.outbox.filter(
    (operation) => operation.entity_type !== entityType || operation.entity_id !== entityId,
  );
  if (nextOutbox.length === state.outbox.length) return;
  state.outbox = nextOutbox;
  writeState(userId, state);
}

export function getReadingPositionId(userId: string, editionCode: string): string | null {
  return readState(userId).reading_position_ids[editionCode] || null;
}

export function rememberReadingPositionId(
  userId: string,
  editionCode: string,
  entityId: string,
): void {
  const state = readState(userId);
  state.reading_position_ids[editionCode] = entityId;
  writeState(userId, state);
}

export function rebaseOutboxFromSnapshot(userId: string, entities: SyncEntity[]): void {
  const state = readState(userId);
  const byIdentity = new Map(
    entities.map((entity) => [`${entity.entity_type}:${entity.id}`, entity] as const),
  );
  const positionsByEdition = new Map(
    entities
      .filter((entity) => entity.entity_type === "reading_position")
      .map((entity) => [entity.edition_code, entity] as const),
  );

  state.outbox = state.outbox.map((operation) => {
    const entity =
      operation.entity_type === "reading_position"
        ? positionsByEdition.get(String(operation.payload.edition_code))
        : byIdentity.get(`${operation.entity_type}:${operation.entity_id}`);
    if (!entity) return operation;
    if (entity.entity_type === "reading_position") {
      state.reading_position_ids[entity.edition_code] = entity.id;
    }
    return {
      ...operation,
      entity_id: entity.id,
      base_revision: entity.revision,
    };
  });
  writeState(userId, state);
}

export function getAyahAnnotations(userId: string): AyahAnnotation[] {
  return Object.values(readState(userId).annotations);
}

export function isAyahAnnotationCacheSeeded(userId: string): boolean {
  return readState(userId).annotations_seeded;
}

export function markAyahAnnotationCacheSeeded(userId: string): void {
  const state = readState(userId);
  if (state.annotations_seeded) return;
  state.annotations_seeded = true;
  writeState(userId, state);
}

/** Records a local intent: the outbox carries it until the server accepts it. */
export function storeLocalAyahAnnotation(userId: string, annotation: AyahAnnotation): void {
  const state = readState(userId);
  state.annotations[annotation.id] = annotation;
  writeState(userId, state);
}

export function removeLocalAyahAnnotation(userId: string, annotationId: string): void {
  const state = readState(userId);
  if (!(annotationId in state.annotations)) return;
  delete state.annotations[annotationId];
  writeState(userId, state);
}

/** Moves a local annotation to the id the outbox now uses for it. */
export function rekeyLocalAyahAnnotation(
  userId: string,
  previousId: string,
  nextId: string,
  revision: number,
): void {
  const state = readState(userId);
  const annotation = state.annotations[previousId];
  if (!annotation) return;
  delete state.annotations[previousId];
  state.annotations[nextId] = { ...annotation, id: nextId, revision };
  writeState(userId, state);
}

const hasPendingOperation = (state: StoredSyncState, entityId: string) =>
  state.outbox.some(
    (operation) => operation.entity_type === "ayah_annotation" && operation.entity_id === entityId,
  );

/**
 * Applies server copies. An annotation with a queued local change keeps the
 * local copy: the queued operation still has to reach the server.
 */
export function applyRemoteAyahAnnotations(userId: string, entities: SyncEntity[]): void {
  const annotations = entities.filter(
    (entity): entity is AyahAnnotation & { entity_type: "ayah_annotation" } =>
      entity.entity_type === "ayah_annotation",
  );
  if (annotations.length === 0) return;
  const state = readState(userId);
  for (const annotation of annotations) {
    if (hasPendingOperation(state, annotation.id)) continue;
    if (annotation.deleted_at) delete state.annotations[annotation.id];
    else state.annotations[annotation.id] = annotation;
  }
  writeState(userId, state);
}

/** A full snapshot is authoritative except for annotations with queued changes. */
export function replaceAyahAnnotationsFromSnapshot(userId: string, entities: SyncEntity[]): void {
  const state = readState(userId);
  const next: Record<string, AyahAnnotation> = {};
  for (const [id, annotation] of Object.entries(state.annotations)) {
    if (hasPendingOperation(state, id)) next[id] = annotation;
  }
  for (const entity of entities) {
    if (entity.entity_type !== "ayah_annotation" || entity.deleted_at || next[entity.id]) continue;
    next[entity.id] = entity;
  }
  state.annotations = next;
  state.annotations_seeded = true;
  writeState(userId, state);
}
