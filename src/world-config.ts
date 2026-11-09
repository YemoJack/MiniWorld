export const models = {
  cabin: 'porch-log-cabin-d2f3ef',
  pine: 'campground-pine-stand-0bf4f2',
  lilies: 'lily-pads-b0c5d0',
  pebbles: 'lake-pebbles-6c0359',
  flowers: 'flower-bed-708e73',
  lantern: 'farm-lantern-747dc8',
  crate: 'wooden-crate-e46521',
  bridge: 'creek-footbridge-d35cf7',
} as const;

export type ModelId = keyof typeof models;

export const localModels = {
  bench: 'bench.glb',
  planter: 'planter.glb',
  cafeCounter: 'cafe-counter.glb',
} as const;

export type LocalModelId = keyof typeof localModels;

export const decorationCategories = { structure: '结构', furniture: '家具', garden: '园艺', landscape: '景观' } as const;
export type DecorationCategory = keyof typeof decorationCategories;

export const decorations = {
  floor: { category: 'structure', layer: 'floor', label: '木地板', width: 1, depth: 1, scale: 1 },
  wall: { category: 'structure', layer: 'edge', label: '墙壁', width: 1, depth: 1, scale: 1 },
  doorway: { category: 'structure', layer: 'edge', label: '门洞', width: 1, depth: 1, scale: 1 },
  windowWall: { category: 'structure', layer: 'edge', label: '窗墙', width: 1, depth: 1, scale: 1 },
  flowers: { category: 'garden', layer: 'object', label: '花坛', width: 1, depth: 1, scale: 0.78 },
  crate: { category: 'furniture', layer: 'object', label: '木箱', width: 1, depth: 1, scale: 0.94 },
  lantern: { category: 'landscape', layer: 'object', label: '提灯', width: 1, depth: 1, scale: 1.35 },
  bridge: { category: 'landscape', layer: 'object', label: '木桥', width: 3, depth: 2, scale: 0.54 },
  bench: { category: 'furniture', layer: 'object', label: '长椅', width: 3, depth: 1, scale: 1 },
  planter: { category: 'garden', layer: 'object', label: '种植箱', width: 3, depth: 1, scale: 1 },
  cafeCounter: { category: 'furniture', layer: 'object', label: '咖啡台', width: 2, depth: 1, scale: 1 },
} as const;

export type DecorationId = keyof typeof decorations;

export const petRoute = [
  [-3.18, 2.12],
  [-2.18, 2.75],
  [-2.22, 3.95],
  [-3.62, 3.25],
] as const;

export const pondCenter = { x: 3.35, z: 0.35 };

export function modelUrl(id: ModelId) {
  return `${import.meta.env.BASE_URL}models/${models[id]}.glb`;
}
