import { cellAt, type Placement } from './grid';
import { decorations, type DecorationId } from './world-config';

const storageKey = 'miniworld.placements.v2';
const previousKey = 'miniworld.placements.v1';
const previousSlots = [
  { id: 'path', x: -1.35, z: 1.88 },
  { id: 'yard', x: -0.05, z: 3.65 },
  { id: 'pond', x: 2.25, z: 3.32 },
] as const;

function isDecoration(value: unknown): value is DecorationId {
  return typeof value === 'string' && Object.hasOwn(decorations, value);
}

function isPlacement(value: unknown): value is Placement {
  if (value === null || typeof value !== 'object') return false;
  const { item, turns, x, z } = value as Partial<Placement>;
  return isDecoration(item) && typeof turns === 'number' && Number.isInteger(turns) &&
    turns >= 0 && turns < 4 && Number.isSafeInteger(x) && Number.isSafeInteger(z);
}

function readLegacyPlacements(): Placement[] {
  try {
    const stored = localStorage.getItem(storageKey);
    if (stored !== null) {
      const values: unknown = JSON.parse(stored);
      return Array.isArray(values) ? values.filter(isPlacement) : [];
    }

    const legacy: unknown = JSON.parse(localStorage.getItem(previousKey) ?? '{}');
    if (legacy === null || typeof legacy !== 'object') return [];
    const values = legacy as Record<string, unknown>;
    return previousSlots.flatMap(({ id, x, z }) => {
      const item = values[id];
      return isDecoration(item) ? [{ ...cellAt(x, z), item, turns: 0 }] : [];
    });
  } catch {
    return [];
  }
}

export type Island = {
  id: string;
  name: string;
  terrain: 'flat' | 'cabin';
  placements: Placement[];
};
export type IslandState = { activeId: string; islands: Island[] };

const islandKey = 'miniworld.islands.v1';

function isIsland(value: unknown): value is Island {
  if (value === null || typeof value !== 'object') return false;
  const island = value as Partial<Island>;
  return typeof island.id === 'string' && island.id.length > 0 &&
    typeof island.name === 'string' && island.name.length > 0 &&
    (island.terrain === 'flat' || island.terrain === 'cabin') &&
    Array.isArray(island.placements);
}

export function readIslands(): IslandState {
  try {
    const stored: unknown = JSON.parse(localStorage.getItem(islandKey) ?? 'null');
    if (stored !== null && typeof stored === 'object') {
      const state = stored as Partial<IslandState>;
      if (Array.isArray(state.islands)) {
        const ids = new Set<string>();
        const islands = state.islands.filter(isIsland).filter(({ id }) => {
          if (ids.has(id)) return false;
          ids.add(id);
          return true;
        }).map((island) => ({ ...island, placements: island.placements.filter(isPlacement) }));
        if (islands.length) {
          const active = islands.find(({ id }) => id === state.activeId) ?? islands[0];
          return { activeId: active.id, islands };
        }
      }
    }
  } catch {
    // Start from the defaults when storage is unavailable.
  }
  return {
    activeId: 'flat',
    islands: [
      { id: 'flat', name: '平坦岛', terrain: 'flat', placements: [] },
      { id: 'cabin', name: '木屋岛', terrain: 'cabin', placements: readLegacyPlacements() },
    ],
  };
}

export function writeIslands(state: IslandState) {
  try {
    localStorage.setItem(islandKey, JSON.stringify(state));
    return true;
  } catch {
    return false;
  }
}
