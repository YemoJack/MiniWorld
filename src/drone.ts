import * as THREE from 'three';
import { elevationUnits, maxBuildElevation } from './grid';

export const flightKeys = new Set([
  'w', 'a', 's', 'd', 'q', 'e', 'arrowleft', 'arrowright', 'arrowup', 'arrowdown',
]);

function createDroneModel() {
  const model = new THREE.Group();
  const shell = new THREE.MeshStandardMaterial({ color: 0xf7f2de, roughness: 0.65 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x2d5048, roughness: 0.75 });
  const light = new THREE.MeshBasicMaterial({ color: 0x84f4cd });
  const box = new THREE.BoxGeometry();
  const motor = new THREE.CylinderGeometry(0.051, 0.053, 0.05, 10);

  function part(geometry: THREE.BufferGeometry, material: THREE.Material, x: number, y: number, z: number) {
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.set(x, y, z);
    model.add(mesh);
    return mesh;
  }

  part(box, shell, 0, 0, 0).scale.set(0.25, 0.14, 0.34);
  part(box, dark, 0, -0.037, 0).scale.set(0.21, 0.10, 0.26);
  part(box, light, 0, 0.02, 0.172).scale.set(0.13, 0.034, 0.018);
  const rotors: THREE.Mesh[] = [];
  for (const x of [-1, 1]) {
    for (const z of [-1, 1]) {
      const arm = part(box, shell, x * 0.14, 0.012, z * 0.105);
      arm.scale.set(0.31, 0.048, 0.061);
      arm.rotation.y = -x * z * 0.58;
      part(motor, dark, x * 0.26, 0.037, z * 0.19);
      const rotor = part(box, dark, x * 0.26, 0.07, z * 0.19);
      rotor.scale.set(0.22, 0.012, 0.025);
      rotors.push(rotor);
    }
  }
  return { model, rotors };
}

export function createDrone() {
  const { model, rotors } = createDroneModel();
  const camera = new THREE.PerspectiveCamera(58, 1, 0.04, 65);
  const forward = new THREE.Vector3();
  const cameraUp = new THREE.Vector3();
  const focus = new THREE.Vector3();
  const velocity = new THREE.Vector3();
  let yaw = 0;
  let pitch = 0;

  function updateCamera() {
    forward.set(Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), Math.cos(yaw) * Math.cos(pitch));
    cameraUp.set(-Math.sin(yaw) * Math.sin(pitch), Math.cos(pitch), -Math.cos(yaw) * Math.sin(pitch));
    camera.position.copy(model.position).addScaledVector(forward, -2.45).addScaledVector(cameraUp, 0.24);
    focus.copy(camera.position).add(forward);
    camera.lookAt(focus);
    camera.updateMatrixWorld();
    model.rotation.y = yaw;
  }

  function reset() {
    model.position.set(1.06, 0.82, 1.57);
    yaw = -2.55;
    pitch = -0.52;
    updateCamera();
  }

  function turn(horizontal: number, vertical: number) {
    yaw -= horizontal;
    pitch = THREE.MathUtils.clamp(pitch + vertical, -1.42, 1.22);
    updateCamera();
  }

  function fly(keys: Set<string>, touchKeys: Set<string>, dt: number, animate: boolean) {
    if (animate) {
      rotors.forEach((rotor, i) => { rotor.rotation.y += dt * (i % 2 ? 22 : -22); });
    }
    if (!keys.size && !touchKeys.size) return false;
    const key = (name: string) => Number(keys.has(name) || touchKeys.has(name));
    const ahead = key('w') - key('s');
    const right = key('d') - key('a');
    const climb = key('e') - key('q');
    const lookX = key('arrowright') - key('arrowleft');
    const lookY = key('arrowup') - key('arrowdown');
    if (!(ahead || right || climb || lookX || lookY)) return false;
    velocity.set(ahead * Math.sin(yaw) - right * Math.cos(yaw), climb,
      ahead * Math.cos(yaw) + right * Math.sin(yaw));
    model.position.addScaledVector(velocity.normalize(), 2.15 * dt);
    model.position.clamp(
      minPosition,
      maxPosition,
    );
    turn(lookX * 1.45 * dt, lookY * 1.15 * dt);
    return true;
  }

  const minPosition = new THREE.Vector3(-8.5, 0.28, -7);
  const maxPosition = new THREE.Vector3(8.5, maxBuildElevation / elevationUnits + 1.3, 7);
  reset();
  model.visible = false;
  return {
    model, camera, reset, turn, fly,
  };
}
