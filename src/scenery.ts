import * as THREE from 'three';
import { createClouds, createIsland, createPath, createPond } from './landscape';
import { createPet } from './pet';
import type { Island } from './data';
import { type ModelId } from './world-config';

export type ModelSet = Record<ModelId, THREE.Group>;

export function placeModel(model: THREE.Group, x: number, y: number, z: number, scale: number, angle = 0) {
  const group = new THREE.Group();
  group.position.set(x, y, z);
  group.rotation.y = angle;
  group.scale.setScalar(scale);
  group.add(model.clone(true));
  group.traverse((node) => {
    if (node instanceof THREE.Mesh) {
      node.castShadow = true;
      node.receiveShadow = true;
    }
  });
  return group;
}

export function createScenery(models: ModelSet, terrain: Island['terrain']) {
  const scene = new THREE.Scene();
  scene.add(new THREE.HemisphereLight(0xfff2d9, 0xb7c7ba, 2.25));

  const sun = new THREE.DirectionalLight(0xffe1b2, 2.45);
  sun.position.set(-6, 11, 5);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  sun.shadow.camera.left = -9;
  sun.shadow.camera.right = 9;
  sun.shadow.camera.top = 9;
  sun.shadow.camera.bottom = -9;
  sun.shadow.camera.near = 0.5;
  sun.shadow.camera.far = 25;
  sun.shadow.normalBias = 0.045;
  sun.shadow.bias = -0.0002;
  scene.add(sun);

  const flat = terrain === 'flat';
  const clouds = createClouds();
  const scenery = new THREE.Group();
  const pond = flat ? undefined : createPond();
  const pet = flat ? undefined : createPet();
  const ground = new THREE.Group();
  ground.add(createIsland(flat));
  scene.add(ground, scenery, ...clouds);
  if (!pond || !pet) return { scene, ground, scenery, pet, pond, clouds, sun };

  const cabin = placeModel(models.cabin, -1.0, -0.03, -1.95, 0.58, 0.04);
  scenery.add(cabin);
  ground.add(createPath());
  scene.add(pond.group, pet.root);

  const placements: [ModelId, number, number, number, number, number?][] = [
    ['pine', -4.55, -0.03, -1.46, 0.36, 0.48],
    ['pine', -3.56, -0.02, -3.25, 0.34, 1.48],
    ['pine', 1.16, -0.03, -3.5, 0.28, -0.7],
    ['pine', 3.26, -0.02, -2.75, 0.29, 0.88],
    ['bridge', 3.15, 0.025, -0.89, 0.48, -0.45],
    ['lilies', 3.94, 0.036, 0.58, 0.51, 0.72],
    ['pebbles', 4.82, 0.034, 1.22, 0.56, 1.21],
    ['pebbles', 2.62, 0.026, 1.68, 0.45, -0.41],
    ['flowers', -2.24, 0.0, 0.58, 0.69, 0.23],
    ['flowers', 1.65, 0.0, -0.64, 0.62, 0.2],
    ['flowers', -4.68, 0.0, 1.55, 0.73, 0.7],
    ['crate', 0.62, 0.0, 0.18, 0.82, -0.12],
    ['lantern', 0.60, 0.49, 0.18, 1.16, 0.22],
  ];
  for (const [id, x, y, z, scale, angle] of placements) {
    scenery.add(placeModel(models[id], x, y, z, scale, angle));
  }

  return { scene, ground, scenery, pet, pond, clouds, sun };
}
