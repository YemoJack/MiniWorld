import { decorations, type DecorationId } from './world-config';

export const cellSize = 0.85;
export const floorHeight = 0.054;
export const wallHeight = 1.12;
export const storeyHeight = wallHeight + floorHeight;
// Elevations are integer millimetres so equal heights share exactly the same slots.
export const elevationUnits = 1000;
export const storeyStep = Math.round(storeyHeight * elevationUnits);
export const maxBuildElevation = 8000;
export const subdivisions = 5;
export const fineCellSize = cellSize / subdivisions;

export type Cell = { x: number; z: number };
export type SnapCell = Cell & { offsetX?: number; offsetZ?: number };
export type GridPosition = SnapCell & { elevation: number };
export type Placement = GridPosition & { item: DecorationId; turns: number };

const fineItems = new Set<DecorationId>([
  'flowers', 'crate', 'lantern', 'cafeChair', 'cafeTable', 'flowerPot', 'pathLight', 'trashBin', 'treeStump',
]);

export function usesFineGrid(item: DecorationId) {
  return fineItems.has(item);
}

export function cellAt(x: number, z: number): Cell {
  return { x: Math.round(x / cellSize), z: Math.round(z / cellSize) };
}

export function snapCellAt(x: number, z: number, fine: boolean): SnapCell {
  if (!fine) return cellAt(x, z);
  const sx = Math.round(x / fineCellSize);
  const sz = Math.round(z / fineCellSize);
  const cx = Math.round(sx / subdivisions);
  const cz = Math.round(sz / subdivisions);
  return { x: cx, z: cz, offsetX: sx - cx * subdivisions, offsetZ: sz - cz * subdivisions };
}

export function cellKey({ x, z }: Cell) {
  return `${x},${z}`;
}

export function footprint({ item, turns }: Placement) {
  const { width, depth } = decorations[item];
  return turns % 2 === 0 ? { width, depth } : { width: depth, depth: width };
}

export function footprintCells(placement: Placement) {
  const { width, depth } = footprint(placement);
  const cells: Cell[] = [];
  for (let x = 0; x < width; x++) {
    for (let z = 0; z < depth; z++) {
      cells.push({ x: placement.x + x, z: placement.z + z });
    }
  }
  return cells;
}

export function footprintCenter(placement: Placement) {
  const { width, depth } = footprint(placement);
  return {
    x: (placement.x + (width - 1) / 2) * cellSize,
    z: (placement.z + (depth - 1) / 2) * cellSize,
  };
}

const edgeDirections = [[0, 1], [1, 0], [0, -1], [-1, 0]] as const;

export function edgeKey({ x, z }: Cell, turns: number, elevation: number) {
  const [dx, dz] = edgeDirections[turns];
  return `edge:${elevation}:${x * 2 + dx},${z * 2 + dz}`;
}

export function cellSlot(layer: 'floor' | 'object', cell: Cell, elevation: number) {
  return `${layer}:${elevation}:${cellKey(cell)}`;
}

export function neighborCell({ x, z }: Cell, turns: number): Cell {
  const [dx, dz] = edgeDirections[turns];
  return { x: x + dx, z: z + dz };
}

export function occupiedSlots(placement: Placement) {
  const { elevation, turns } = placement;
  const layer = decorations[placement.item].layer;
  const cells = footprintCells(placement);
  if (layer === 'edge') return cells.map((cell) => edgeKey(cell, turns, elevation));
  if (usesFineGrid(placement.item)) {
    const x = placement.x * subdivisions + (placement.offsetX ?? 0);
    const z = placement.z * subdivisions + (placement.offsetZ ?? 0);
    return [`detail:${elevation}:${x},${z}`];
  }
  return cells.map((cell) => cellSlot(layer, cell, elevation));
}

export function placementCenter(placement: Placement) {
  const center = footprintCenter(placement);
  if (usesFineGrid(placement.item)) {
    return {
      x: center.x + (placement.offsetX ?? 0) * fineCellSize,
      z: center.z + (placement.offsetZ ?? 0) * fineCellSize,
    };
  }
  if (decorations[placement.item].layer !== 'edge') return center;
  const [dx, dz] = edgeDirections[placement.turns];
  return { x: center.x + dx * cellSize / 2, z: center.z + dz * cellSize / 2 };
}
