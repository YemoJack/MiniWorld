import * as THREE from 'three';
import { pondCenter } from './world-config';

type Point = readonly [number, number, number];

export const islandRim = [
  [6.8, 0.0], [6.3, 2.3], [4.9, 4.0], [2.5, 4.95],
  [0.15, 5.3], [-2.4, 5.0], [-4.7, 4.3], [-6.15, 2.6],
  [-6.8, 0.45], [-6.5, -1.7], [-5.2, -3.5], [-3.1, -4.65],
  [-0.75, -5.05], [1.7, -4.7], [3.7, -4.45], [5.55, -3.0],
] as const;

const grassColors = [0x9ba963, 0x93a65f, 0xa4af6a, 0x99aa61, 0x9fad67];
const edgeColors = [0x82834d, 0x737347, 0x8a8850];
const rockColors = [0x8c7765, 0x9a826a, 0x796b60, 0xa08770, 0x6c625a, 0x8c7465];

export function createIsland(flat = false) {
  const positions: number[] = [];
  const colors: number[] = [];
  const tint = new THREE.Color();

  function triangle(a: Point, b: Point, c: Point, color: number) {
    positions.push(...a, ...b, ...c);
    tint.setHex(color);
    for (let i = 0; i < 3; i++) colors.push(tint.r, tint.g, tint.b);
  }

  const top = islandRim.map(([x, z]): Point => [x, 0, z]);
  const inner = islandRim.map(([x, z], i): Point => [x * 0.54, flat ? 0 : -0.035 - (i % 3) * 0.016, z * 0.54]);
  const lip = islandRim.map(([x, z], i): Point => [x * 1.015, -0.28 - (i % 3) * 0.07, z * 1.015]);
  const rock = islandRim.map(([x, z], i): Point => {
    const scale = 0.67 + Math.sin(i * 2.3) * 0.14;
    return [x * scale, -1.69 + Math.sin(i * 1.65) * 0.48, z * scale];
  });
  const bottom = islandRim.map(([x, z], i): Point => {
    const scale = 0.28 + Math.sin(i * 1.86) * 0.09;
    return [x * scale - 0.25, -3.64 + Math.sin(i * 1.22) * 0.45, z * scale + 0.16];
  });

  for (let i = 0; i < islandRim.length; i++) {
    const next = (i + 1) % islandRim.length;
    triangle([0, flat ? 0 : -0.09, 0], inner[next], inner[i], grassColors[i % grassColors.length]);
    triangle(inner[i], inner[next], top[i], grassColors[(i + 2) % grassColors.length]);
    triangle(top[i], inner[next], top[next], grassColors[(i + 3) % grassColors.length]);
    triangle(top[i], top[next], lip[i], edgeColors[i % edgeColors.length]);
    triangle(lip[i], top[next], lip[next], edgeColors[(i + 1) % edgeColors.length]);
    triangle(lip[i], lip[next], rock[i], rockColors[i % rockColors.length]);
    triangle(rock[i], lip[next], rock[next], rockColors[(i + 1) % rockColors.length]);
    triangle(rock[i], rock[next], bottom[i], rockColors[(i + 3) % rockColors.length]);
    triangle(bottom[i], rock[next], bottom[next], rockColors[(i + 4) % rockColors.length]);
    triangle(bottom[i], bottom[next], [-0.43, -3.94, 0.1], rockColors[(i + 2) % rockColors.length]);
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  geometry.computeVertexNormals();
  const island = new THREE.Mesh(geometry, new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1 }));
  island.receiveShadow = true;
  return island;
}

function flatPond(radiusX: number, radiusZ: number, color: number, height: number) {
  const shape = new THREE.Shape();
  const sides = 16;
  for (let i = 0; i < sides; i++) {
    const angle = i / sides * Math.PI * 2;
    const taper = 1 + Math.sin(angle * 3 + 0.4) * 0.075;
    const x = Math.cos(angle) * radiusX * taper;
    const y = Math.sin(angle) * radiusZ * taper;
    if (i === 0) shape.moveTo(x, y);
    else shape.lineTo(x, y);
  }
  shape.closePath();
  const mesh = new THREE.Mesh(new THREE.ShapeGeometry(shape), new THREE.MeshStandardMaterial({ color, roughness: 0.78 }));
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.set(pondCenter.x, height, pondCenter.z);
  mesh.receiveShadow = true;
  return mesh;
}

export function createPond() {
  const group = new THREE.Group();
  group.add(
    flatPond(2.0, 1.74, 0xb6ae78, 0.018),
    flatPond(1.87, 1.59, 0x8dc3a6, 0.026),
    flatPond(1.63, 1.37, 0x6eaaa9, 0.032),
  );

  const ripples = [0, 1].map(() => {
    const material = new THREE.MeshBasicMaterial({
      color: 0xe8f6d8, transparent: true, opacity: 0, depthWrite: false,
    });
    const ripple = new THREE.Mesh(new THREE.RingGeometry(0.84, 0.89, 24), material);
    ripple.rotation.x = -Math.PI / 2;
    ripple.position.set(pondCenter.x + 0.42, 0.039, pondCenter.z + 0.25);
    group.add(ripple);
    return ripple;
  });

  return { group, update(time: number) {
    ripples.forEach((ripple, index) => {
      const phase = (time * 0.26 + index * 0.46) % 1;
      ripple.scale.setScalar(0.14 + phase * 0.68);
      ripple.material.opacity = Math.sin(Math.PI * phase) * 0.29;
    });
  } };
}

export function createPath() {
  const group = new THREE.Group();
  const geometry = new THREE.CylinderGeometry(0.49, 0.53, 0.095, 7);
  const materials = [0xc2b58f, 0xd0bd96, 0xb6af90].map((color) =>
    new THREE.MeshStandardMaterial({ color, roughness: 1 }));
  const points = [
    [-0.8, 0.12], [-0.7, 0.71], [-0.5, 1.28], [-0.21, 1.85],
    [0.07, 2.43], [0.47, 2.96], [0.88, 3.43], [1.15, 3.95], [1.37, 4.47],
  ];
  points.forEach(([x, z], index) => {
    const stone = new THREE.Mesh(geometry, materials[index % materials.length]);
    stone.position.set(x, 0.014, z);
    stone.rotation.y = index * 1.6;
    stone.scale.set(0.92 + (index % 3) * 0.12, 1, 0.58 + (index % 2) * 0.09);
    stone.receiveShadow = true;
    group.add(stone);
  });
  return group;
}

export function createClouds() {
  const geometry = new THREE.IcosahedronGeometry(1, 1);
  const material = new THREE.MeshBasicMaterial({ color: 0xfff8e7, toneMapped: false });
  const cloudLocations = [
    [-9.9, 0.2, -5.2, 0.9], [-4.5, 2.6, -9.6, 0.82],
    [5.1, 1.9, -8.1, 1.14], [9.5, -1.25, -3.1, 0.98], [-4.5, -3.8, 4.8, 0.62],
  ];
  return cloudLocations.map(([x, y, z, scale]) => {
    const cloud = new THREE.Group();
    const lobes = [
      [-0.8, 0, 0, 0.79], [-0.22, 0.24, 0, 0.92],
      [0.49, 0.12, 0.02, 0.84], [0.98, -0.07, 0, 0.59],
    ];
    for (const [offsetX, offsetY, offsetZ, size] of lobes) {
      const lobe = new THREE.Mesh(geometry, material);
      lobe.position.set(offsetX, offsetY, offsetZ);
      lobe.scale.set(size * 1.27, size * 0.58, size * 0.71);
      cloud.add(lobe);
    }
    cloud.position.set(x, y, z);
    cloud.scale.setScalar(scale);
    return cloud;
  });
}
