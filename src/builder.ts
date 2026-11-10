import * as THREE from 'three';
import { LineMaterial } from 'three/addons/lines/LineMaterial.js';
import { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/addons/lines/LineSegmentsGeometry.js';
import { cellKey, cellSize, cellSlot, elevationUnits, fineCellSize, floorHeight, footprint, footprintCells, maxBuildElevation,
  neighborCell, occupiedSlots, placementCenter, snapCellAt, storeyStep, subdivisions, usesFineGrid,
  type Cell, type GridPosition, type Placement } from './grid';
import { islandRim } from './landscape';
import { placeModel } from './scenery';
import { decorations, pondCenter, type DecorationId } from './world-config';

export type BuildState =
  | { mode: 'browse' }
  | { mode: 'selected'; item: DecorationId; blocked: boolean }
  | { mode: 'place' | 'move'; item: DecorationId; target: 'empty' | 'blocked' | 'ready' };

type Draft = { item: DecorationId; turns: number; source?: string; target?: GridPosition };
const halfCell = cellSize / 2;
const groundHeight = 0.009;
const floorTop = groundHeight + floorHeight;
const gridHeight = floorTop + 0.004;


function worldHeight(elevation: number) {
  return groundHeight + elevation / elevationUnits;
}

function floorSurface(elevation: number) {
  return elevation === 0 ? floorTop : worldHeight(elevation);
}
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
  const built = new Map<string, { placement: Placement; model: THREE.Group; bounds: THREE.Box3; collision: THREE.Box3 }>();
  const modelBounds = new Map<DecorationId, THREE.Box3>();
  const structures = new THREE.Group();
  scene.add(structures);
  const grid = createGrid(available);
  grid.visible = false;
  const lines: number[] = [];
  for (let i = 1; i < subdivisions; i++) {
    const line = i * fineCellSize - halfCell;
    lines.push(line, 0, -halfCell, line, 0, halfCell, -halfCell, 0, line, halfCell, 0, line);
  }
  const detailGeometry = new THREE.BufferGeometry();
  detailGeometry.setAttribute('position', new THREE.Float32BufferAttribute(lines, 3));
  const detailGrid = new THREE.LineSegments(detailGeometry, new THREE.LineBasicMaterial({
    color: 0xe7fff1, transparent: true, opacity: 0.75, depthWrite: false, toneMapped: false,
  }));
  detailGrid.visible = false;
  scene.add(grid, detailGrid);

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
    color: 0x9fe9d2, transparent: true, opacity: 0.46, depthWrite: false, toneMapped: false,
  });
  let ghost: THREE.Group | undefined;
  let ghostItem: DecorationId | undefined;
  let enabled = false;
  let dirty = false;
  let hovered: string | undefined;
  let selection: string | undefined;
  let draft: Draft | undefined;

  function canOccupySlots(placement: Placement, ignoreOwner?: string) {
    return footprintCells(placement).every((cell) => validCells.has(cellKey(cell))) &&
      occupiedSlots(placement).every((slot) => {
        const owner = owners.get(slot);
        return !reserved.has(slot) && (owner === undefined || owner === ignoreOwner);
      });
  }

  function assetBounds(item: DecorationId) {
    let bounds = modelBounds.get(item);
    if (!bounds && assets[item]) {
      bounds = new THREE.Box3().setFromObject(assets[item]!);
      modelBounds.set(item, bounds);
    }
    return bounds;
  }

  function hasFloor(cell: Cell, elevation: number) {
    const slot = cellSlot('floor', cell, elevation);
    return owners.has(slot) || reserved.has(slot);
  }

  function stairAt(cell: Cell, elevation: number) {
    const owner = owners.get(cellSlot('object', cell, elevation));
    const placement = owner ? built.get(owner)?.placement : undefined;
    return placement?.item === 'stairs' ? placement : undefined;
  }

  function hasSupport(placement: Placement, cells: Cell[]) {
    const { item, turns, elevation } = placement;
    const layer = decorations[item].layer;
    if (elevation < 0 || elevation > maxBuildElevation ||
      (item === 'stairs' && elevation + storeyStep > maxBuildElevation)) return false;
    if (elevation === 0 || layer === 'floor') return true;
    if (cells.every((cell) => hasFloor(cell, elevation) ||
      (layer === 'edge' && hasFloor(neighborCell(cell, turns), elevation)))) return true;
    if (item !== 'stairs') return false;

    // At the upper landing, continue straight or turn back over the previous flight.
    return stairAt(neighborCell(placement, turns), elevation - storeyStep)?.turns === turns ||
      stairAt(placement, elevation - storeyStep)?.turns === (turns + 2) % 4;
  }

  function placementHeight(placement: Placement, allowFutureFloor = false) {
    const { item, elevation } = placement;
    const layer = decorations[item].layer;
    if (layer === 'floor') return floorSurface(elevation) - (assetBounds(item)?.max.y ?? floorHeight);
    if (elevation > 0 || layer === 'edge' || item === 'steelColumn') return worldHeight(elevation);
    return allowFutureFloor || touchedCells(placement).some((cell) => hasFloor(cell, elevation))
      ? floorTop : groundHeight;
  }

  function placementScale(placement: Placement, height: number) {
    const scale = decorations[placement.item].scale;
    if (placement.item !== 'stairs') return new THREE.Vector3(scale, scale, scale);
    const bounds = assetBounds('stairs')!;
    return new THREE.Vector3(
      cellSize / (bounds.max.x - bounds.min.x),
      (worldHeight(placement.elevation + storeyStep) - height) / (bounds.max.y - bounds.min.y),
      cellSize / (bounds.max.z - bounds.min.z),
    );
  }

  function placementBounds(placement: Placement) {
    const { item, turns, elevation } = placement;
    const center = placementCenter(placement);
    const bounds = assetBounds(item);
    if (!bounds) {
      const { width, depth } = footprint(placement);
      const height = floorSurface(elevation);
      const layer = decorations[item].layer;
      return new THREE.Box3(
        new THREE.Vector3(center.x - width * halfCell, height - floorHeight, center.z - depth * halfCell),
        new THREE.Vector3(center.x + width * halfCell, layer === 'floor' ? height : worldHeight(elevation + storeyStep), center.z + depth * halfCell),
      );
    }
    const height = placementHeight(placement, true);
    const transform = new THREE.Matrix4().makeRotationY(turns * Math.PI / 2)
      .scale(placementScale(placement, height))
      .setPosition(center.x, height, center.z);
    const box = bounds.clone().applyMatrix4(transform);
    if (decorations[item].layer === 'floor') box.min.y = Math.min(box.min.y, floorSurface(elevation) - floorHeight);
    return box;
  }

  function touchedCells(placement: Placement, bounds?: THREE.Box3) {
    if (!usesFineGrid(placement.item) || !assets[placement.item]) return footprintCells(placement);
    const box = bounds ?? placementBounds(placement);
    const cells: Cell[] = [];
    const first = snapCellAt(box.min.x + contactTolerance, box.min.z + contactTolerance, false);
    const last = snapCellAt(box.max.x - contactTolerance, box.max.z - contactTolerance, false);
    for (let x = first.x; x <= last.x; x++) {
      for (let z = first.z; z <= last.z; z++) cells.push({ x, z });
    }
    return cells;
  }

  const unavailableBounds = unavailable.map((placement) => ({ placement, collision: placementBounds(placement) }));

  function canPlace(placement: Placement, ignoreOwner?: string) {
    if (!canOccupySlots(placement, ignoreOwner)) return false;
    const layer = decorations[placement.item].layer;
    const bounds = placementBounds(placement);
    const cells = touchedCells(placement, bounds);
    if (!cells.every((cell) => validCells.has(cellKey(cell))) || !hasSupport(placement, cells)) return false;

    function collides({ placement: other, collision }: { placement: Placement; collision: THREE.Box3 }) {
      const otherLayer = decorations[other.item].layer;
      if (placement.elevation === other.elevation &&
        (layer === 'floor' || otherLayer === 'floor' || (layer === 'edge' && otherLayer === 'edge'))) return false;
      return Math.min(bounds.max.y, collision.max.y) - Math.max(bounds.min.y, collision.min.y) > contactTolerance &&
        overlapsHorizontally(bounds, collision);
    }

    for (const [key, entry] of built) {
      if (key !== ignoreOwner && collides(entry)) return false;
    }
    return !unavailableBounds.some(collides);
  }

  function index(placement: Placement, model: THREE.Group) {
    const slots = occupiedSlots(placement);
    const key = slots[0];
    built.set(key, {
      placement, model, bounds: new THREE.Box3().setFromObject(model), collision: placementBounds(placement),
    });
    for (const slot of slots) owners.set(slot, key);
    return key;
  }

  function unindex(placement: Placement) {
    const slots = occupiedSlots(placement);
    built.delete(slots[0]);
    for (const slot of slots) owners.delete(slot);
  }

  function syncElevations() {
    for (const { placement, model, bounds } of built.values()) {
      const height = placementHeight(placement);
      if (model.position.y === height) continue;
      model.position.y = height;
      model.scale.copy(placementScale(placement, height));
      bounds.setFromObject(model);
    }
  }

  function add(placement: Placement) {
    const { x, z } = placementCenter(placement);
    const { item } = placement;
    const asset = assets[item];
    if (!asset) return false;
    const height = placementHeight(placement);
    const model = placeModel(asset, x, height, z, 1, placement.turns * Math.PI / 2);
    if (decorations[item].layer === 'floor') model.userData.walkableFloor = true;
    model.scale.copy(placementScale(placement, height));
    structures.add(model);
    return index(placement, model);
  }

  for (const placement of initial) {
    // Restore older overlaps so the player can move or remove them in the editor.
    if (canOccupySlots(placement)) add(placement);
  }

  syncElevations();

  function positionFill(mesh: typeof fill, placement: Placement) {
    const center = placementCenter(placement);
    const fine = usesFineGrid(placement.item);
    let { width, depth }: { width: number; depth: number } = footprint(placement);
    if (decorations[placement.item].layer === 'edge') {
      if (placement.turns % 2 === 0) depth = 0.24;
      else width = 0.24;
    }
    const surface = floorSurface(placement.elevation);
    const height = surface + (mesh === sourceFill ? 0.001 : 0.002);
    const size = fine ? fineCellSize : cellSize;
    const margin = fine ? 0.012 : 0.04;
    mesh.position.set(center.x, height, center.z);
    mesh.scale.set(width * size - margin, depth * size - margin, 1);
    mesh.visible = true;
  }

  function previewPlacement(): Placement | undefined {
    if (!draft?.target) return;
    return { ...draft.target, item: draft.item, turns: draft.turns };
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
    const height = placementHeight(placement);
    ghost.position.set(center.x, height + 0.004, center.z);
    ghost.scale.copy(placementScale(placement, height));
    ghost.rotation.y = turns * Math.PI / 2;
    ghost.visible = true;
  }

  function updatePreview(rotationBlocked = false) {
    fill.visible = false;
    sourceFill.visible = false;
    selectionOutline.visible = false;
    detailGrid.visible = false;
    if (ghost) ghost.visible = false;

    const selected = selection ? built.get(selection) : undefined;
    const owner = draft ? draft.source : selection ?? hovered;
    const entry = owner ? built.get(owner) : undefined;
    if (entry) {
      if (draft || selected) positionFill(sourceFill, entry.placement);
      entry.bounds.getCenter(selectionOutline.position);
      entry.bounds.getSize(selectionOutline.scale).addScalar(0.028);
      selectionOutline.visible = true;
    }

    if (!draft) {
      onChange(selected ? { mode: 'selected', item: selected.placement.item, blocked: rotationBlocked } : { mode: 'browse' });
      return;
    }

    const preview = previewPlacement();
    const ready = preview && canPlace(preview, draft.source);
    if (preview) {
      fill.material.color.setHex(ready ? 0x9fe9d2 : 0xf08f72);
      positionFill(fill, preview);
      if (usesFineGrid(preview.item) && validCells.has(cellKey(preview))) {
        detailGrid.position.set(preview.x * cellSize, floorSurface(preview.elevation) + 0.007, preview.z * cellSize);
        detailGrid.visible = true;
      }
      const source = entry?.placement;
      const unchanged = source?.turns === preview.turns &&
        occupiedSlots(source)[0] === occupiedSlots(preview)[0];
      if (ready && !unchanged) showGhost(preview);
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

  const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), -groundHeight);
  const planeHit = new THREE.Vector3();
  const boxHit = new THREE.Vector3();
  const picker = new THREE.Raycaster(undefined, undefined, 0, 12);
  const wallRim = 0.10;

  function pickSurface(ray: THREE.Ray, ignoreOwner?: string) {
    picker.ray.copy(ray);
    const ground = ray.direction.y < 0 ? ray.intersectPlane(plane, planeHit) : null;
    const groundDistance = ground ? ray.origin.distanceTo(ground) : Infinity;
    const sceneryDistance = picker.intersectObject(scenery, true)[0]?.distance ?? Infinity;
    let nearest = Math.min(sceneryDistance, groundDistance);
    let owner: string | undefined;
    let point: THREE.Vector3 | undefined;
    for (const [key, { model, bounds }] of built) {
      if (key === ignoreOwner || !ray.intersectBox(bounds, boxHit) || ray.origin.distanceTo(boxHit) > nearest) continue;
      const hit = picker.intersectObject(model, true)[0];
      if (hit && hit.distance <= nearest) {
        owner = key;
        point = hit.point;
        nearest = hit.distance;
      }
    }
    if (!owner && ground && groundDistance < sceneryDistance && groundDistance <= picker.far &&
      onIsland(ground.x, ground.z)) point = ground;
    return { owner, point };
  }

  function targetOnSurface(ray: THREE.Ray, draft: Draft): GridPosition | undefined {
    const { owner, point } = pickSurface(ray, draft.source);
    if (!point) return;
    const targetLayer = decorations[draft.item].layer;
    const surface = owner ? built.get(owner) : undefined;
    if (!surface) return { ...snapCellAt(point.x, point.z, usesFineGrid(draft.item)), elevation: 0 };

    const support = surface.placement;
    const layer = decorations[support.item].layer;
    if (layer === 'floor') {
      if (targetLayer !== 'floor') {
        const top = floorSurface(support.elevation);
        if (ray.origin.y <= top || point.y < top - 0.035) return;
        return { ...snapCellAt(point.x, point.z, usesFineGrid(draft.item)), elevation: support.elevation };
      }

      // Aim near a slab rim to extend it at the same elevation.
      const center = placementCenter(support);
      const dx = point.x - center.x;
      const dz = point.z - center.z;
      if (Math.max(Math.abs(dx), Math.abs(dz)) < halfCell * 0.55) return;
      const turns = Math.abs(dx) > Math.abs(dz) ? (dx > 0 ? 1 : 3) : (dz > 0 ? 0 : 2);
      return { ...neighborCell(support, turns), elevation: support.elevation };
    }

    if (surface.bounds.max.y - point.y > wallRim) return;
    if (support.item === 'stairs') {
      if (targetLayer !== 'floor' && draft.item !== 'stairs') return;
      const exit = neighborCell(support, (support.turns + 2) % 4);
      const cell = draft.item === 'stairs' && draft.turns === (support.turns + 2) % 4 ? support : exit;
      return { x: cell.x, z: cell.z, elevation: support.elevation + storeyStep };
    }
    if (targetLayer !== 'floor' || (layer !== 'edge' && support.item !== 'steelColumn')) return;

    // Align the underside of the slab with the top of the support.
    const elevation = Math.round((surface.bounds.max.y + floorHeight - groundHeight) * elevationUnits);
    if (layer !== 'edge') return { x: support.x, z: support.z, elevation };
    const center = placementCenter(support);
    const axis = support.turns % 2 === 0 ? 'z' : 'x';
    const offset = point[axis] - center[axis];
    const side = Math.sign(Math.abs(offset) > 0.012 ? offset : ray.origin[axis] - center[axis]) || 1;
    const x = axis === 'x' ? center.x + side * halfCell : point.x;
    const z = axis === 'z' ? center.z + side * halfCell : point.z;
    return { ...snapCellAt(x, z, false), elevation };
  }

  function aim(ray: THREE.Ray) {
    if (!enabled) return;
    if (!draft) {
      const { owner } = pickSurface(ray);
      if (owner === hovered) return;
      hovered = owner;
      updatePreview();
      return;
    }
    const next = targetOnSurface(ray, draft);
    const previous = draft.target;
    if (next?.x === previous?.x && next?.z === previous?.z && next?.elevation === previous?.elevation &&
      next?.offsetX === previous?.offsetX && next?.offsetZ === previous?.offsetZ) return;
    draft.target = next;
    updatePreview();
  }

  function activate(ray: THREE.Ray) {
    aim(ray);
    if (draft) {
      commit();
      return;
    }
    selection = hovered;
    updatePreview();
  }

  function saveChanges() {
    if (!dirty) return true;
    const placements = [...built.values()].map(({ placement }) => placement);
    if (!onSave([...placements, ...unavailable])) return false;
    dirty = false;
    return true;
  }

  function edit() {
    dirty = true;
    syncElevations();
    saveChanges();
    onEdit();
    updatePreview();
  }

  function transform(owner: string, placement: Placement) {
    const entry = built.get(owner);
    if (!entry || !canPlace(placement, owner)) return false;
    const { x, z } = placementCenter(placement);
    unindex(entry.placement);
    const height = placementHeight(placement);
    entry.model.position.set(x, height, z);
    entry.model.scale.copy(placementScale(placement, height));
    entry.model.rotation.y = placement.turns * Math.PI / 2;
    return index(placement, entry.model);
  }

  function commit() {
    if (!draft) return;
    const placement = previewPlacement();
    if (!placement || !canPlace(placement, draft.source)) return;

    const key = draft.source ? transform(draft.source, placement) : add(placement);
    if (!key) return;
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
    hovered = undefined;
    unindex(entry.placement);
    selection = undefined;
    edit();
  }

  return {
    structures,
    setMode(active: boolean) {
      if (!active && !saveChanges()) return false;
      enabled = active;
      hovered = undefined;
      selection = undefined;
      draft = undefined;
      grid.visible = active;
      updatePreview();
      return true;
    },
    activate, aim, place, move, rotate, remove, cancel,
  };
}
