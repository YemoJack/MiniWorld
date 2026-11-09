import { decorations, type DecorationId } from './world-config';

export const cellSize = 0.85;
export const floorHeight = 0.054;

export type Cell = { x: number; z: number };
export type Placement = Cell & { item: DecorationId; turns: number };

export function cellAt(x: number, z: number): Cell {
  return { x: Math.round(x / cellSize), z: Math.round(z / cellSize) };
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

export function edgeKey({ x, z }: Cell, turns: number) {
  const [dx, dz] = edgeDirections[turns];
  return `edge:${x * 2 + dx},${z * 2 + dz}`;
}

export function occupiedSlots(placement: Placement) {
  const layer = decorations[placement.item].layer;
  if (layer === 'edge') return [edgeKey(placement, placement.turns)];
  return footprintCells(placement).map((cell) => `${layer}:${cellKey(cell)}`);
}

export function placementCenter(placement: Placement) {
  const center = footprintCenter(placement);
  if (decorations[placement.item].layer !== 'edge') return center;
  const [dx, dz] = edgeDirections[placement.turns];
  return { x: center.x + dx * cellSize / 2, z: center.z + dz * cellSize / 2 };
}
