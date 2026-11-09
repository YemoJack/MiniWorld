import * as THREE from 'three';
import { cellSize, floorHeight } from './grid';

export function createStructureModels() {
  const box = new THREE.BoxGeometry();
  const wood = new THREE.MeshStandardMaterial({ color: 0xa8784c, roughness: 0.9 });
  const trim = new THREE.MeshStandardMaterial({ color: 0x956749, roughness: 0.9 });
  const siding = new THREE.MeshStandardMaterial({ color: 0xd9be93, roughness: 1 });
  const sidingShade = new THREE.MeshStandardMaterial({ color: 0xcfb188, roughness: 1 });
  const boards = [0xb48860, 0xbf966b, 0xb98d65, 0xc69e75].map((color) =>
    new THREE.MeshStandardMaterial({ color, roughness: 0.92 }));

  function addBox(group: THREE.Group, material: THREE.Material,
    x: number, y: number, z: number, width: number, height: number, depth: number) {
    const mesh = new THREE.Mesh(box, material);
    mesh.position.set(x, y, z);
    mesh.scale.set(width, height, depth);
    group.add(mesh);
  }

  const floor = new THREE.Group();
  const boardWidth = cellSize / boards.length;
  addBox(floor, wood, 0, floorHeight / 3, 0, cellSize, floorHeight * 2 / 3, cellSize);
  boards.forEach((material, index) => {
    const z = (index - (boards.length - 1) / 2) * boardWidth;
    addBox(floor, material, 0, floorHeight * 3 / 4, z, cellSize, floorHeight / 2, boardWidth - 0.008);
  });

  const height = 1.12;
  const post = 0.055;
  const span = cellSize - post * 2;
  const depth = 0.076;

  function wallFrame() {
    const group = new THREE.Group();
    for (const x of [-1, 1]) {
      addBox(group, trim, x * (cellSize - post) / 2, height / 2, 0, post, height, 0.1);
    }
    addBox(group, trim, 0, height - post / 2, 0, span, post, 0.1);
    return group;
  }

  function panels(group: THREE.Group, x: number, width: number, bottom: number, top: number) {
    const rows = Math.max(1, Math.round((top - bottom) / 0.13));
    const rowHeight = (top - bottom) / rows;
    for (let i = 0; i < rows; i++) {
      addBox(group, i % 2 ? sidingShade : siding, x, bottom + (i + 0.5) * rowHeight, 0,
        width, rowHeight - 0.006, depth);
    }
  }

  const wall = wallFrame();
  panels(wall, 0, span, 0, height - post);
  addBox(wall, trim, 0, post / 2, 0, span, post, 0.1);

  const doorway = wallFrame();
  const doorWidth = 0.53;
  const doorTop = 0.91;
  const doorSide = (span - doorWidth) / 2;
  for (const side of [-1, 1]) {
    panels(doorway, side * (doorWidth + doorSide) / 2, doorSide, 0, doorTop);
    addBox(doorway, trim, side * doorWidth / 2, doorTop / 2, 0, 0.026, doorTop, 0.096);
  }
  panels(doorway, 0, span, doorTop, height - post);
  addBox(doorway, trim, 0, doorTop, 0, doorWidth + 0.026, 0.036, 0.1);

  const windowWall = wallFrame();
  const windowWidth = 0.46;
  const sill = 0.49;
  const windowTop = 0.88;
  const windowSide = (span - windowWidth) / 2;
  panels(windowWall, 0, span, 0, sill);
  panels(windowWall, 0, span, windowTop, height - post);
  for (const side of [-1, 1]) {
    panels(windowWall, side * (windowWidth + windowSide) / 2, windowSide, sill, windowTop);
  }
  for (const y of [sill, windowTop]) {
    addBox(windowWall, trim, 0, y, 0, windowWidth + 0.04, 0.043, 0.105);
  }
  addBox(windowWall, trim, 0, (sill + windowTop) / 2, 0, 0.028, windowTop - sill, 0.071);

  return { floor, wall, doorway, windowWall };
}
