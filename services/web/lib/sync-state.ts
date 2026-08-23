import type { SyncEntity, SyncEntityType, SyncOperation } from "./api";

const SYNC_STORAGE_PREFIX = "quran_platform_sync_v1";
export const SYNC_STATE_EVENT = "quran-platform-sync-state";

type StoredSyncState = {
  cursor: number;
  outbox: SyncOperation[];
  reading_position_ids: Record<string, string>;
};

const emptyState = (): StoredSyncState => ({
  cursor: 0,
  outbox: [],
  reading_position_ids: {},
});

const storageKey = (userId: string) => `${SYNC_STORAGE_PREFIX}:${userId}`;

function isSyncOperation(value: unknown): value is SyncOperation {
  if (!value || typeof value !== "object") return false;
  const operation = value as Partial<SyncOperation>;
  return (
    typeof operation.operation_id === "string" &&
    typeof operation.entity_id === "string" &&
    ["reading_position", "bookmark", "reminder"].includes(operation.entity_type || "") &&
    ["upsert", "delete"].includes(operation.action || "") &&
    Number.isInteger(operation.base_revision) &&
    typeof operation.client_updated_at === "string" &&
    Boolean(operation.payload) &&
    typeof operation.payload === "object"
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
