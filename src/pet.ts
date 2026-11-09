import * as THREE from 'three';
import { petRoute } from './world-config';

export function createPet() {
  const root = new THREE.Group();
  const body = new THREE.Group();
  root.add(body);

  const ochre = new THREE.MeshStandardMaterial({ color: 0xcf7c49, flatShading: true });
  const ivory = new THREE.MeshStandardMaterial({ color: 0xffe5bc, flatShading: true });
  const dark = new THREE.MeshStandardMaterial({ color: 0x473c34, flatShading: true });
  const round = new THREE.IcosahedronGeometry(1, 1);
  const cone = new THREE.ConeGeometry(1, 1, 4);
  const block = new THREE.BoxGeometry();

  function part(parent: THREE.Group, geometry: THREE.BufferGeometry, material: THREE.Material,
    x: number, y: number, z: number, sx: number, sy: number, sz: number) {
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.set(x, y, z);
    mesh.scale.set(sx, sy, sz);
    parent.add(mesh);
    return mesh;
  }

  part(body, round, ochre, 0, 0.31, -0.05, 0.29, 0.25, 0.39);
  part(body, round, ivory, 0, 0.27, 0.17, 0.21, 0.21, 0.18);
  const head = new THREE.Group();
  head.position.set(0, 0.45, 0.22);
  body.add(head);
  part(head, round, ochre, 0, 0.12, 0, 0.275, 0.25, 0.25);
  part(head, round, ivory, 0, 0.04, 0.168, 0.215, 0.12, 0.145);
  part(head, round, dark, 0, 0.065, 0.283, 0.058, 0.046, 0.055);

  for (const side of [-1, 1]) {
    part(head, round, dark, side * 0.127, 0.15, 0.195, 0.031, 0.042, 0.027);
    const ear = part(head, cone, ochre, side * 0.16, 0.32, -0.021, 0.135, 0.31, 0.10);
    ear.rotation.z = side * -0.18;
    const inner = part(head, cone, ivory, side * 0.158, 0.333, 0.049, 0.064, 0.18, 0.026);
    inner.rotation.z = ear.rotation.z;
  }

  const legs: THREE.Group[] = [];
  for (const x of [-0.155, 0.155]) {
    for (const z of [-0.25, 0.17]) {
      const leg = new THREE.Group();
      leg.position.set(x, 0.22, z);
      part(leg, block, ochre, 0, -0.076, 0, 0.115, 0.20, 0.12);
      part(leg, round, dark, 0, -0.172, 0.014, 0.07, 0.048, 0.089);
      legs.push(leg);
      body.add(leg);
    }
  }

  const tail = new THREE.Group();
  tail.position.set(0, 0.30, -0.28);
  const tailFur = part(tail, round, ochre, 0, 0.19, -0.20, 0.15, 0.16, 0.33);
  tailFur.rotation.x = 0.52;
  part(tail, round, ivory, 0, 0.30, -0.405, 0.104, 0.108, 0.15).rotation.x = 0.52;
  body.add(tail);

  const shadowMaterial = new THREE.MeshBasicMaterial({ color: 0x4d5139, transparent: true, opacity: 0.19, depthWrite: false });
  const shadow = new THREE.Mesh(new THREE.CircleGeometry(0.48, 20), shadowMaterial);
  shadow.rotation.x = -Math.PI / 2;
  shadow.position.y = 0.014;
  shadow.scale.y = 0.71;
  root.add(shadow);

  let waypoint = 1;
  let pause = 1.6;
  let bounce = 0;
  let gait = 0;
  const duration = 0.58;
  root.position.set(petRoute[0][0], 0, petRoute[0][1]);
  root.rotation.y = 0.48;

  return {
    root,
    body,
    react() { bounce = duration; },
    update(dt: number, time: number, reducedMotion: boolean) {
      let stride = 0;
      if (bounce > 0) {
        bounce = Math.max(0, bounce - dt);
      } else if (!reducedMotion) {
        pause -= dt;
        if (pause <= 0) {
          const [x, z] = petRoute[waypoint];
          const dx = x - root.position.x;
          const dz = z - root.position.z;
          const distance = Math.hypot(dx, dz);
          const step = dt * 0.64;
          if (distance <= step) {
            root.position.set(x, 0, z);
            waypoint = (waypoint + 1) % petRoute.length;
            pause = 1.2;
          } else {
            root.position.x += dx / distance * step;
            root.position.z += dz / distance * step;
            root.rotation.y = Math.atan2(dx, dz);
            gait += dt * 11;
            stride = 0.42;
          }
        }
      }

      const jump = Math.sin(Math.PI * bounce / duration);
      legs.forEach((leg, index) => {
        leg.rotation.x = Math.sin(gait) * stride * (index === 0 || index === 3 ? 1 : -1);
      });
      body.position.y = reducedMotion ? 0 : jump * 0.56 + Math.abs(Math.sin(gait)) * stride * 0.08;
      head.rotation.z = reducedMotion ? jump * 0.24 : jump * 0.14 + Math.sin(time * 1.45) * 0.035;
      tail.rotation.y = reducedMotion ? 0 : Math.sin(time * 4.3) * (0.21 + jump * 0.3);
      shadowMaterial.opacity = 0.19 - jump * 0.10;
    },
  };
}
