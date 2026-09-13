import * as SecureStore from 'expo-secure-store';

const CHUNK_SIZE = 400;
const memoryStorage = new Map<string, string>();

function secureKey(key: string): string {
  return `kratos.${key.replace(/[^A-Za-z0-9._-]/g, '_')}`;
}

function metadataKey(key: string): string {
  return `${secureKey(key)}.chunks`;
}

function chunkKey(key: string, index: number): string {
  return `${secureKey(key)}.${index}`;
}

function generationPointerKey(key: string): string {
  return `${secureKey(key)}.current_generation`;
}

function pendingGenerationKey(key: string): string {
  return `${secureKey(key)}.pending_generation`;
}

function generationMetadataKey(key: string, generation: string): string {
  return `${secureKey(key)}.generation.${generation}.chunks`;
}

function generationChunkKey(key: string, generation: string, index: number): string {
  return `${secureKey(key)}.generation.${generation}.${index}`;
}

function chunks(value: string): string[] {
  const result: string[] = [];
  for (let index = 0; index < value.length; index += CHUNK_SIZE) {
    result.push(value.slice(index, index + CHUNK_SIZE));
  }
  return result.length ? result : [''];
}

async function storedChunkCount(key: string): Promise<number> {
  const rawCount = await SecureStore.getItemAsync(metadataKey(key));
  const count = Number(rawCount);
  return Number.isInteger(count) && count > 0 ? count : 0;
}

async function generationChunkCount(key: string, generation: string): Promise<number> {
  const rawCount = await SecureStore.getItemAsync(generationMetadataKey(key, generation));
  const count = Number(rawCount);
  return Number.isInteger(count) && count > 0 ? count : 0;
}

async function deleteGeneration(key: string, generation: string): Promise<void> {
  const count = await generationChunkCount(key, generation);
  await Promise.all([
    SecureStore.deleteItemAsync(generationMetadataKey(key, generation)),
    ...Array.from({ length: count }, (_, index) =>
      SecureStore.deleteItemAsync(generationChunkKey(key, generation, index)),
    ),
  ]);
}

async function readLegacyValue(key: string): Promise<string | null> {
  const count = await storedChunkCount(key);
  if (!count) return null;
  const stored = await Promise.all(
    Array.from({ length: count }, (_, index) => SecureStore.getItemAsync(chunkKey(key, index))),
  );
  return stored.every((part): part is string => part !== null) ? stored.join('') : null;
}

async function readCommittedGeneration(key: string, generation: string): Promise<string | null> {
  const count = await generationChunkCount(key, generation);
  if (!count) return null;
  const stored = await Promise.all(
    Array.from({ length: count }, (_, index) =>
      SecureStore.getItemAsync(generationChunkKey(key, generation, index)),
    ),
  );
  return stored.every((part): part is string => part !== null) ? stored.join('') : null;
}

function nextGeneration(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

const writeChains = new Map<string, Promise<void>>();

function serializeWrite(key: string, operation: () => Promise<void>): Promise<void> {
  const previous = writeChains.get(key) ?? Promise.resolve();
  const next = previous.catch(() => undefined).then(operation);
  writeChains.set(key, next);
  return next.finally(() => {
    if (writeChains.get(key) === next) writeChains.delete(key);
  });
}

export const secureSessionStorage = {
  async getItem(key: string): Promise<string | null> {
    if (process.env.EXPO_OS === 'web') return memoryStorage.get(key) ?? null;

    const [generation, pendingGeneration] = await Promise.all([
      SecureStore.getItemAsync(generationPointerKey(key)),
      SecureStore.getItemAsync(pendingGenerationKey(key)),
    ]);
    if (!generation) {
      // Existing signed-in installations used this legacy completed format. It
      // stays readable; the next session replacement upgrades it atomically.
      if (pendingGeneration) {
        await deleteGeneration(key, pendingGeneration);
        await SecureStore.deleteItemAsync(pendingGenerationKey(key));
      }
      return readLegacyValue(key);
    }

    // A pending generation was never committed, so it cannot affect the
    // currently readable session. Cleaning it here is safe and opportunistic.
    if (pendingGeneration && pendingGeneration !== generation) {
      await deleteGeneration(key, pendingGeneration);
      await SecureStore.deleteItemAsync(pendingGenerationKey(key));
    }
    return readCommittedGeneration(key, generation);
  },

  async setItem(key: string, value: string): Promise<void> {
    if (process.env.EXPO_OS === 'web') {
      memoryStorage.set(key, value);
      return;
    }

    await serializeWrite(key, async () => {
      const [previousGeneration, stalePendingGeneration] = await Promise.all([
        SecureStore.getItemAsync(generationPointerKey(key)),
        SecureStore.getItemAsync(pendingGenerationKey(key)),
      ]);
      if (stalePendingGeneration && stalePendingGeneration !== previousGeneration) {
        await deleteGeneration(key, stalePendingGeneration);
      }

      const generation = nextGeneration();
      const nextChunks = chunks(value);
      await SecureStore.setItemAsync(pendingGenerationKey(key), generation);
      await Promise.all(
        nextChunks.map((part, index) =>
          SecureStore.setItemAsync(generationChunkKey(key, generation, index), part),
        ),
      );
      await SecureStore.setItemAsync(generationMetadataKey(key, generation), String(nextChunks.length));

      // This is the commit point. Readers only follow this pointer, never a
      // generation that is still being assembled.
      await SecureStore.setItemAsync(generationPointerKey(key), generation);
      await SecureStore.deleteItemAsync(pendingGenerationKey(key));

      if (previousGeneration && previousGeneration !== generation) {
        await deleteGeneration(key, previousGeneration);
      }
      // Legacy chunks can only be a prior completed generation, and are safe
      // to clean after the new pointer has committed.
      const legacyCount = await storedChunkCount(key);
      await Promise.all([
        SecureStore.deleteItemAsync(metadataKey(key)),
        ...Array.from({ length: legacyCount }, (_, index) =>
          SecureStore.deleteItemAsync(chunkKey(key, index)),
        ),
      ]);
    });
  },

  async removeItem(key: string): Promise<void> {
    if (process.env.EXPO_OS === 'web') {
      memoryStorage.delete(key);
      return;
    }

    await serializeWrite(key, async () => {
      const [generation, pendingGeneration, legacyCount] = await Promise.all([
        SecureStore.getItemAsync(generationPointerKey(key)),
        SecureStore.getItemAsync(pendingGenerationKey(key)),
        storedChunkCount(key),
      ]);
      await Promise.all([
        SecureStore.deleteItemAsync(generationPointerKey(key)),
        SecureStore.deleteItemAsync(pendingGenerationKey(key)),
        SecureStore.deleteItemAsync(metadataKey(key)),
        ...(generation ? [deleteGeneration(key, generation)] : []),
        ...(pendingGeneration && pendingGeneration !== generation
          ? [deleteGeneration(key, pendingGeneration)]
          : []),
        ...Array.from({ length: legacyCount }, (_, index) =>
          SecureStore.deleteItemAsync(chunkKey(key, index)),
        ),
      ]);
    });
  },
};
