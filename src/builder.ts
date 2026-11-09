import * as THREE from 'three';
import { LineMaterial } from 'three/addons/lines/LineMaterial.js';
import { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/addons/lines/LineSegmentsGeometry.js';
import { cellAt, cellKey, cellSize, edgeKey, floorHeight, footprint, footprintCells, occupiedSlots, placementCenter,
  type Cell, type Placement } from './grid';
import { islandRim } from './landscape';
import { placeModel } from './scenery';
import { decorations, pondCenter, type DecorationId } from './world-config';

export type BuildState =
  | { mode: 'browse' }
  | { mode: 'selected'; item: DecorationId; blocked: boolean }
  | { mode: 'place' | 'move'; item: DecorationId; target: 'empty' | 'blocked' | 'ready' };

type Draft = { item: DecorationId; turns: number; source?: string; target?: Cell };
const halfCell = cellSize / 2;
const groundHeight = 0.009;
const floorTop = groundHeight + floorHeight;
const gridHeight = floorTop + 0.004;
const contactTolerance = 0.001;

function overlapsHorizontally(a: THREE.Box3, b: THREE.Box3) {
  return Math.min(a.max.x, b.max.x) - Math.max(a.min.x, b.min.x) > contactTolerance &&
    Math.min(a.max.z, b.max.z) - Math.max(a.min.z, b.min.z) > contactTolerance;
}

function onIsland(x: number, z: number) {
  let inside = false;
  let previous = islandRim.length - 1;
  for (let i = 0; i < islandRim.length; i++) {
    const [ax, az] = islandRim[i];
    const [bx, bz] = islandRim[previous];
    if ((az > z) !== (bz > z) && x < (bx - ax) * (z - az) / (bz - az) + ax) inside = !inside;
    previous = i;
  }
  return inside;
}

function buildable(cell: Cell, obstacles: THREE.Box3[], hasPond: boolean) {
  const x = cell.x * cellSize;
  const z = cell.z * cellSize;
  const left = x - halfCell;
  const right = x + halfCell;
  const back = z - halfCell;
  const front = z + halfCell;
  if (!onIsland(left, back) || !onIsland(left, front) || !onIsland(right, back) || !onIsland(right, front)) {
    return false;
  }

  if (hasPond) {
    const pondX = THREE.MathUtils.clamp(pondCenter.x, left, right);
    const pondZ = THREE.MathUtils.clamp(pondCenter.z, back, front);
    if (Math.hypot((pondX - pondCenter.x) / 2.15, (pondZ - pondCenter.z) / 1.87) <= 1) return false;
  }

  return !obstacles.some(({ min, max }) =>
    left < max.x && right > min.x && back < max.z && front > min.z);
}

function createGrid(cells: Cell[]) {
  const positions: number[] = [];
  const edges = new Set<string>();
  for (const cell of cells) {
    const x = cell.x * 2;
    const z = cell.z * 2;
    const corners = [[x - 1, z - 1], [x + 1, z - 1], [x + 1, z + 1], [x - 1, z + 1]];
    for (let i = 0; i < corners.length; i++) {
      const [ax, az] = corners[i];
      const [bx, bz] = corners[(i + 1) % corners.length];
      const key = ax < bx || (ax === bx && az < bz)
        ? `${ax},${az}:${bx},${bz}` : `${bx},${bz}:${ax},${az}`;
      if (edges.has(key)) continue;
      edges.add(key);
      positions.push(ax * halfCell, gridHeight, az * halfCell, bx * halfCell, gridHeight, bz * halfCell);
    }
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  return new THREE.LineSegments(geometry, new THREE.LineBasicMaterial({
    color: 0x354f3c, transparent: true, opacity: 0.52, depthWrite: false, toneMapped: false,
  }));
}

export function createBuilder(
  scene: THREE.Scene, assets: Partial<Record<DecorationId, THREE.Group>>, scenery: THREE.Group, initial: Placement[],
  hasPond: boolean, onSave: (placements: Placement[]) => boolean,
  onChange: (state: BuildState) => void, onEdit: () => void,
) {
  const obstacles = scenery.children.map((object) => new THREE.Box3().setFromObject(object));
  const columns = Math.ceil(Math.max(...islandRim.map(([x]) => Math.abs(x))) / cellSize);
  const rows = Math.ceil(Math.max(...islandRim.map(([, z]) => Math.abs(z))) / cellSize);
  const available: Cell[] = [];
  for (let x = -columns; x <= columns; x++) {
    for (let z = -rows; z <= rows; z++) {
      if (buildable({ x, z }, obstacles, hasPond)) available.push({ x, z });
    }
  }
  const validCells = new Set(available.map(cellKey));
  // Keep saved items and reserve their footprints when optional models are unavailable.
  const unavailable = initial.filter(({ item }) => !assets[item]);
  const reserved = new Set(unavailable.flatMap(occupiedSlots));
  const owners = new Map<string, string>();
  const built = new Map<string, { placement: Placement; model: THREE.Group; bounds: THREE.Box3 }>();
  const modelBounds = new Map<DecorationId, THREE.Box3>();
  const grid = createGrid(available);
  grid.visible = false;
  scene.add(grid);

  const fill = new THREE.Mesh(new THREE.PlaneGeometry(), new THREE.MeshBasicMaterial({
    color: 0xffed9b, transparent: true, opacity: 0.42, depthWrite: false, toneMapped: false,
  }));
  fill.rotation.x = -Math.PI / 2;
  fill.visible = false;
  const sourceFill = fill.clone();
  sourceFill.material = fill.material.clone();
  sourceFill.material.color.setHex(0x9fe9d2);

  const unitBox = new THREE.BoxGeometry();
  const unitEdges = new THREE.EdgesGeometry(unitBox);
  const outlineGeometry = new LineSegmentsGeometry().fromEdgesGeometry(unitEdges);
  unitBox.dispose();
  unitEdges.dispose();
  const selectionOutline = new THREE.Group();
  const border = new LineSegments2(outlineGeometry, new LineMaterial({
    color: 0x224a40, linewidth: 4, depthWrite: false, toneMapped: false,
  }));
  const highlight = new LineSegments2(outlineGeometry, new LineMaterial({
    color: 0xa8ffea, linewidth: 2, depthWrite: false, toneMapped: false,
  }));
  border.renderOrder = 5;
  highlight.renderOrder = 6;
  selectionOutline.add(border, highlight);
  selectionOutline.visible = false;
  scene.add(sourceFill, fill, selectionOutline);

  const ghostMaterial = new THREE.MeshBasicMaterial({
    color: 0xffed9b, transparent: true, opacity: 0.46, depthWrite: false, toneMapped: false,
  });
  let ghost: THREE.Group | undefined;
  let ghostItem: DecorationId | undefined;
  let enabled = false;
  let dirty = false;
  let cursor: Cell | undefined;
  let selection: string | undefined;
  let draft: Draft | undefined;

  function canOccupySlots(placement: Placement, ignoreOwner?: string) {
    return footprintCells(placement).every((cell) => validCells.has(cellKey(cell))) &&
      occupiedSlots(placement).every((slot) => {
        const owner = owners.get(slot);
        return !reserved.has(slot) && (owner === undefined || owner === ignoreOwner);
      });
  }

  function horizontalBounds(placement: Placement) {
    const { item, turns } = placement;
    const center = placementCenter(placement);
    const asset = assets[item];
    if (!asset) {
      const { width, depth } = footprint(placement);
      return new THREE.Box3(
        new THREE.Vector3(center.x - width * halfCell, 0, center.z - depth * halfCell),
        new THREE.Vector3(center.x + width * halfCell, 0, center.z + depth * halfCell),
      );
    }
    let bounds = modelBounds.get(item);
    if (!bounds) {
      bounds = new THREE.Box3().setFromObject(asset);
      modelBounds.set(item, bounds);
    }
    const scale = decorations[item].scale;
    const transform = new THREE.Matrix4().makeRotationY(turns * Math.PI / 2)
      .scale(new THREE.Vector3(scale, scale, scale))
      .setPosition(center.x, 0, center.z);
    return bounds.clone().applyMatrix4(transform);
  }

  function canPlace(placement: Placement, ignoreOwner?: string) {
    if (!canOccupySlots(placement, ignoreOwner)) return false;
    const layer = decorations[placement.item].layer;
    if (layer === 'floor') return true;

    // Reserve the full width of wall segments, including door and window openings.
    const blockedLayer = layer === 'edge' ? 'object' : 'edge';
    const bounds = horizontalBounds(placement);
    for (const [key, entry] of built) {
      if (key !== ignoreOwner && decorations[entry.placement.item].layer === blockedLayer &&
        overlapsHorizontally(bounds, entry.bounds)) return false;
    }
    return !unavailable.some((entry) => decorations[entry.item].layer === blockedLayer &&
      overlapsHorizontally(bounds, horizontalBounds(entry)));
  }

  function index(placement: Placement, model: THREE.Group) {
    const slots = occupiedSlots(placement);
    const key = slots[0];
    built.set(key, { placement, model, bounds: new THREE.Box3().setFromObject(model) });
    for (const slot of slots) owners.set(slot, key);
    return key;
  }

  function unindex(placement: Placement) {
    const slots = occupiedSlots(placement);
    built.delete(slots[0]);
    for (const slot of slots) owners.delete(slot);
  }

  function surfaceHeight(placement: Placement) {
    if (decorations[placement.item].layer !== 'object') return groundHeight;
    const onFloor = footprintCells(placement).some((cell) => owners.has(`floor:${cellKey(cell)}`));
    return groundHeight + (onFloor ? floorHeight : 0);
  }

  function syncElevations() {
    for (const { placement, model, bounds } of built.values()) {
      const height = surfaceHeight(placement);
      if (model.position.y === height) continue;
      model.position.y = height;
      bounds.setFromObject(model);
    }
  }

  function add(placement: Placement) {
    const { x, z } = placementCenter(placement);
    const { item } = placement;
    const asset = assets[item];
    if (!asset) return false;
    const model = placeModel(asset, x, surfaceHeight(placement), z, decorations[item].scale, placement.turns * Math.PI / 2);
    scene.add(model);
    return index(placement, model);
  }

  for (const placement of initial) {
    // Restore older overlaps so the player can move or remove them in the editor.
    if (canOccupySlots(placement)) add(placement);
  }

  syncElevations();

  function positionFill(mesh: typeof fill, cell: Cell, placement?: Placement) {
    const center = placement ? placementCenter(placement) : { x: cell.x * cellSize, z: cell.z * cellSize };
    let { width, depth } = placement ? footprint(placement) : { width: 1, depth: 1 };
    if (placement && decorations[placement.item].layer === 'edge') {
      if (placement.turns % 2 === 0) depth = 0.24;
      else width = 0.24;
    }
    // Keep both overlays above the floor surface and below the grid.
    const height = floorTop + (mesh === sourceFill ? 0.001 : 0.002);
    mesh.position.set(center.x, height, center.z);
    mesh.scale.set(width * cellSize - 0.04, depth * cellSize - 0.04, 1);
    mesh.visible = true;
  }

  function ownerAt(cell: Cell) {
    const key = cellKey(cell);
    const surface = owners.get(`object:${key}`) ?? owners.get(`floor:${key}`);
    if (surface) return surface;
    for (let turns = 0; turns < 4; turns++) {
      const edge = owners.get(edgeKey(cell, turns));
      if (edge) return edge;
    }
  }

  function previewPlacement(): Placement | undefined {
    if (!draft?.target) return;
    const { x, z } = draft.target;
    return { x, z, item: draft.item, turns: draft.turns };
  }

  function showGhost(placement: Placement) {
    const { item, turns } = placement;
    const asset = assets[item];
    if (!asset) return;
    const center = placementCenter(placement);
    if (!ghost || ghostItem !== item) {
      ghost?.removeFromParent();
      ghost = placeModel(asset, 0, 0, 0, decorations[item].scale);
      ghost.traverse((node) => {
        if (node instanceof THREE.Mesh) {
          node.material = ghostMaterial;
          node.castShadow = false;
          node.receiveShadow = false;
        }
      });
      scene.add(ghost);
      ghostItem = item;
    }
    ghost.position.set(center.x, surfaceHeight(placement) + 0.004, center.z);
    ghost.rotation.y = turns * Math.PI / 2;
    ghost.visible = true;
  }

  function updatePreview(rotationBlocked = false) {
    fill.visible = false;
    sourceFill.visible = false;
    selectionOutline.visible = false;
    if (ghost) ghost.visible = false;

    const owner = draft ? draft.source : selection;
    const entry = owner ? built.get(owner) : undefined;
    const existing = entry?.placement;
    if (entry) {
      positionFill(sourceFill, entry.placement, entry.placement);
      entry.bounds.getCenter(selectionOutline.position);
      entry.bounds.getSize(selectionOutline.scale).addScalar(0.028);
      selectionOutline.visible = true;
    }

    if (!draft) {
      if (cursor && !existing) {
        fill.material.color.setHex(0xffed9b);
        positionFill(fill, cursor);
      }
      onChange(existing ? { mode: 'selected', item: existing.item, blocked: rotationBlocked } : { mode: 'browse' });
      return;
    }

    const preview = previewPlacement();
    const ready = preview && canPlace(preview, draft.source);
    if (preview) {
      fill.material.color.setHex(ready ? 0xffed9b : 0xf08f72);
      positionFill(fill, preview, preview);
      if (ready) showGhost(preview);
    }
    onChange({
      mode: draft.source ? 'move' : 'place',
      item: draft.item,
      target: preview ? (ready ? 'ready' : 'blocked') : 'empty',
    });
  }

  function cancel() {
    if (!draft) return false;
    draft = undefined;
    updatePreview();
    return true;
  }

  const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), -gridHeight);
  const groundHit = new THREE.Vector3();
  const boxHit = new THREE.Vector3();
  function pick(ray: THREE.Ray, offset?: Cell): { owner?: string; cell?: Cell; ground?: THREE.Vector3 } {
    if (ray.direction.y >= -0.01) return {};
    const hit = ray.intersectPlane(plane, groundHit);
    const groundDistance = hit ? ray.origin.distanceToSquared(hit) : Infinity;
    let sceneryDistance = Infinity;
    for (const box of obstacles) {
      if (ray.intersectBox(box, boxHit)) {
        sceneryDistance = Math.min(sceneryDistance, ray.origin.distanceToSquared(boxHit));
      }
    }

    let nearest = draft ? Math.min(sceneryDistance, groundDistance) : sceneryDistance;
    let target: string | undefined;
    for (const [key, { placement, bounds }] of built) {
      if (offset || (draft && (key === draft.source || decorations[draft.item].layer !== 'object' ||
        decorations[placement.item].layer !== 'object'))) continue;
      if (!ray.intersectBox(bounds, boxHit)) continue;
      const distance = ray.origin.distanceToSquared(boxHit);
      if (distance < nearest) {
        target = key;
        nearest = distance;
      }
    }

    const x = hit ? hit.x + (offset?.x ?? 0) : 0;
    const z = hit ? hit.z + (offset?.z ?? 0) : 0;
    const cell = hit && onIsland(x, z) && groundDistance <= sceneryDistance + 1e-5
      ? cellAt(x, z) : undefined;
    return { owner: target, cell: (target && built.get(target)?.placement) || cell, ground: hit ?? undefined };
  }

  function setTarget(cell?: Cell) {
    if (!draft || (draft.target?.x === cell?.x && draft.target?.z === cell?.z)) return;
    draft.target = cell;
    updatePreview();
  }

  function aim(ray: THREE.Ray, offset?: Cell) {
    if (draft && (!offset || draft.source)) setTarget(pick(ray, offset).cell);
  }

  function activate(ray: THREE.Ray) {
    if (draft) {
      aim(ray);
      commit();
      return;
    }
    const { owner } = pick(ray);
    selection = owner;
    cursor = owner ? built.get(owner)?.placement : undefined;
    updatePreview();
  }

  function grab(ray: THREE.Ray) {
    if (draft) return;
    const { owner, ground } = pick(ray);
    const placement = owner ? built.get(owner)?.placement : undefined;
    if (!owner || !placement || !ground) return;
    selection = owner;
    cursor = placement;
    updatePreview();
    // Keep the grabbed point in place, even on wide objects or at a shallow camera angle.
    return { x: placement.x * cellSize - ground.x, z: placement.z * cellSize - ground.z };
  }

  function finishDrag(ray?: THREE.Ray, offset?: Cell) {
    if (!draft?.source) return;
    if (ray && offset) aim(ray, offset);
    if (!ray || !commit()) cancel();
  }

  function moveSelection(dx: number, dz: number) {
    if (!enabled) return;
    const origin = draft?.target ?? cursor ?? { x: 0, z: 0 };
    for (let step = 1; step <= Math.max(columns * 2, rows * 2); step++) {
      const next = { x: origin.x + dx * step, z: origin.z + dz * step };
      if (Math.abs(next.x) > columns || Math.abs(next.z) > rows) break;
      if (validCells.has(cellKey(next))) {
        if (draft) draft.target = next;
        else {
          cursor = next;
          selection = ownerAt(next);
        }
        updatePreview();
        return;
      }
    }
    if (!draft?.target && !cursor && available.length) {
      if (draft) draft.target = available[0];
      else {
        cursor = available[0];
        selection = ownerAt(cursor);
      }
      updatePreview();
    }
  }

  function edit() {
    dirty = true;
    syncElevations();
    onEdit();
    updatePreview();
  }

  function transform(owner: string, placement: Placement) {
    const entry = built.get(owner);
    if (!entry || !canPlace(placement, owner)) return false;
    const { x, z } = placementCenter(placement);
    unindex(entry.placement);
    entry.model.position.set(x, entry.model.position.y, z);
    entry.model.rotation.y = placement.turns * Math.PI / 2;
    return index(placement, entry.model);
  }

  function commit() {
    if (!draft) return;
    const placement = previewPlacement();
    if (!placement || !canPlace(placement, draft.source)) return;

    const key = draft.source ? transform(draft.source, placement) : add(placement);
    if (!key) return;
    cursor = placement;
    if (draft.source) {
      draft = undefined;
      selection = key;
    } else {
      draft.target = undefined;
    }
    edit();
    return true;
  }

  function place(item: DecorationId) {
    if (!enabled || !assets[item]) return;
    if (draft?.item === item && !draft.source) {
      cancel();
      return;
    }
    cursor = undefined;
    selection = undefined;
    draft = { item, turns: 0 };
    updatePreview();
  }

  function move() {
    const owner = selection;
    const placement = owner ? built.get(owner)?.placement : undefined;
    if (!owner || !placement || draft) return false;
    draft = { item: placement.item, turns: placement.turns, source: owner };
    updatePreview();
    return true;
  }

  function rotate() {
    if (draft) {
      draft.turns = (draft.turns + 1) % 4;
      updatePreview();
      return;
    }
    const owner = selection;
    const original = owner ? built.get(owner)?.placement : undefined;
    if (!owner || !original) return;

    const placement = { ...original, turns: (original.turns + 1) % 4 };
    const before = footprint(original);
    const after = footprint(placement);
    placement.x += Math.trunc((before.width - after.width) / 2);
    placement.z += Math.trunc((before.depth - after.depth) / 2);
    const key = transform(owner, placement);
    if (key) {
      cursor = placement;
      selection = key;
      edit();
    } else {
      updatePreview(true);
    }
  }

  function remove() {
    const owner = selection;
    const entry = owner ? built.get(owner) : undefined;
    if (!entry || draft) return;
    entry.model.removeFromParent();
    unindex(entry.placement);
    cursor = undefined;
    selection = undefined;
    edit();
  }

  return {
    setMode(active: boolean) {
      if (!active && dirty) {
        const placements = [...built.values()].map(({ placement }) => placement);
        if (!onSave([...placements, ...unavailable])) return false;
        dirty = false;
      }
      enabled = active;
      grid.visible = active;
      cursor = undefined;
      selection = undefined;
      draft = undefined;
      updatePreview();
      return true;
    },
    activate, aim, setTarget, grab, finishDrag, moveSelection, place, move, rotate, remove, commit, cancel,
  };
}
