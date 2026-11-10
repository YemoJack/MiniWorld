import * as THREE from 'three';
import { Capsule } from 'three/addons/math/Capsule.js';
import { Octree } from 'three/addons/math/Octree.js';
import { cellSize, floorHeight } from './grid';

export const walkKeys = new Set([
  'w', 'a', 's', 'd', 'arrowleft', 'arrowright', 'arrowup', 'arrowdown',
]);

function attachAccessories(avatar: THREE.Group) {
  const head = avatar.getObjectByName('Head')!;
  const accessories: THREE.Object3D[] = [];
  avatar.traverse((node) => {
    if (/^(SM_Chr_Hair|SM_Chr_Attach_Glasses)/.test(node.name)) accessories.push(node);
  });
  for (const accessory of accessories) head.attach(accessory);
}

function createWalkCycle(avatar: THREE.Group) {
  const xAxis = new THREE.Vector3(1, 0, 0);
  const yAxis = new THREE.Vector3(0, 1, 0);
  const zAxis = new THREE.Vector3(0, 0, 1);
  const rotation = new THREE.Quaternion();
  const hips = avatar.getObjectByName('Hips')!;
  const hipY = hips.position.y;

  function joint(name: string, axis: THREE.Vector3) {
    const bone = avatar.getObjectByName(name)!;
    const rest = bone.quaternion.clone();
    const localAxis = axis.clone().applyQuaternion(bone.getWorldQuaternion(new THREE.Quaternion()).invert());
    return (angle: number) => bone.quaternion.copy(rest).multiply(rotation.setFromAxisAngle(localAxis, angle));
  }

  joint('Shoulder_L', zAxis)(-1.40);
  joint('Shoulder_R', zAxis)(1.40);
  const leftArm = joint('Shoulder_L', xAxis);
  const rightArm = joint('Shoulder_R', xAxis);
  const leftElbow = joint('Elbow_L', xAxis);
  const rightElbow = joint('Elbow_R', xAxis);
  const leftLeg = joint('UpperLeg_L', xAxis);
  const rightLeg = joint('UpperLeg_R', xAxis);
  const leftKnee = joint('LowerLeg_L', xAxis);
  const rightKnee = joint('LowerLeg_R', xAxis);
  const chest = joint('Spine_02', yAxis);
  let phase = 0;
  let idleTime = 0;
  let weight = 0;
  let airborne = 0;

  return (distance: number, dt: number, animate: boolean, grounded: boolean) => {
    if (animate) {
      if (grounded) phase += distance * 7.6;
      idleTime += dt;
    }
    weight = THREE.MathUtils.damp(weight, animate && grounded && distance > 0 ? 1 : 0, 14, dt);
    airborne = THREE.MathUtils.damp(airborne, animate && !grounded ? 1 : 0, 18, dt);
    const swing = Math.sin(phase) * weight;
    const swingFoot = (angle: number) => Math.max(0, angle) ** 1.4 * 0.72;
    leftArm(0.24 * swing - airborne * 0.36);
    rightArm(-0.24 * swing - airborne * 0.25);
    leftElbow(-0.10 - swingFoot(swing) * 0.22 - airborne * 0.34);
    rightElbow(-0.10 - swingFoot(-swing) * 0.22 - airborne * 0.34);
    leftLeg(-0.44 * swing - airborne * 0.37);
    rightLeg(0.44 * swing - airborne * 0.19);
    leftKnee(swingFoot(-swing) + airborne * 0.55);
    rightKnee(swingFoot(swing) + airborne * 0.43);
    chest(-swing * 0.12);
    hips.position.y = hipY + Math.abs(swing) * 0.032 + Math.sin(idleTime * 2.2) * (1 - weight) * 0.004;
  };
}

function createPlayerAnimation(avatar: THREE.Group, clips: THREE.AnimationClip[]) {
  const idle = clips.find(({ name }) => /^idle$/i.test(name));
  const walk = clips.find(({ name }) => /^(walk|walking)$/i.test(name));
  const jump = clips.find(({ name }) => /^jump$/i.test(name));
  if (!idle || !walk || !jump) return createWalkCycle(avatar);

  const mixer = new THREE.AnimationMixer(avatar);
  const rest = mixer.clipAction(idle).play();
  const stride = mixer.clipAction(walk);
  const leap = mixer.clipAction(jump).setLoop(THREE.LoopOnce, 1);
  leap.clampWhenFinished = true;
  let active = rest;

  return (distance: number, dt: number, animate: boolean, grounded: boolean) => {
    const next = animate ? (!grounded ? leap : distance > 0 ? stride : rest) : rest;
    if (next !== active) {
      active.fadeOut(0.12);
      next.reset().fadeIn(0.12).play();
      active = next;
    }
    mixer.update(dt);
  };
}

export function createPlayer(avatar: THREE.Group, clips: THREE.AnimationClip[]) {
  const model = new THREE.Group();
  const avatarBounds = new THREE.Box3().setFromObject(avatar, true);
  avatar.position.y = -avatarBounds.min.y;
  model.scale.setScalar(0.84 / (avatarBounds.max.y - avatarBounds.min.y));
  model.add(avatar);
  avatar.traverse((node) => {
    if (node instanceof THREE.Mesh) node.castShadow = true;
  });
  attachAccessories(avatar);
  const animatePlayer = createPlayerAnimation(avatar, clips);
  const camera = new THREE.PerspectiveCamera(54, 1, 0.035, 65);
  const radius = 0.14;
  const slabRadius = 0.025;
  const footClearance = 0.003;
  const collider = new Capsule(new THREE.Vector3(), new THREE.Vector3(), radius);
  const ray = new THREE.Ray();
  const normal = new THREE.Vector3();
  const focus = new THREE.Vector3();
  const offset = new THREE.Vector3();
  let octree = new Octree();
  let floorSlabs = new Octree();
  let stairSurfaces = new Octree();
  let grounded = true;
  let verticalSpeed = 0;
  let yaw = Math.PI;
  let pitch = 0.30;
  let cameraY = 0;
  let cameraDistance = 2.7;
  let cameraTargetDistance = 2.7;

  function updateCamera(dt = 0, reset = false) {
    const targetY = model.position.y + 0.59;
    cameraY = reset || Math.abs(cameraY - targetY) < 0.001
      ? targetY : THREE.MathUtils.damp(cameraY, targetY, 18, dt);
    focus.set(model.position.x, cameraY, model.position.z);
    offset.set(-Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.cos(yaw) * Math.cos(pitch));
    ray.set(focus, offset);
    const obstacle = nearestHit(octree.rayIntersect(ray), floorSlabs.rayIntersect(ray));
    cameraTargetDistance = obstacle ? THREE.MathUtils.clamp(obstacle.distance - 0.12, 0.20, 2.7) : 2.7;
    cameraDistance = reset || cameraTargetDistance - cameraDistance < 0.001
      ? cameraTargetDistance : THREE.MathUtils.damp(cameraDistance, cameraTargetDistance, 12, dt);
    camera.position.copy(focus).addScaledVector(offset, cameraDistance);
    camera.lookAt(focus);
    camera.updateMatrixWorld();
    model.visible = cameraDistance > 0.40;
  }

  function nearestHit(a: ReturnType<Octree['rayIntersect']>, b: ReturnType<Octree['rayIntersect']>) {
    return b && (!a || b.distance < a.distance) ? b : a;
  }

  function floorAt(x: number, z: number, fromY: number, range: number) {
    ray.origin.set(x, fromY, z);
    ray.direction.set(0, -1, 0);
    const solid = octree.rayIntersect(ray);
    const ramp = stairSurfaces.rayIntersect(ray);
    const solidFloor = solid && solid.triangle.getNormal(normal).y >= 0.55 ? solid : false;
    const floor = nearestHit(nearestHit(solidFloor, floorSlabs.rayIntersect(ray)), ramp);
    if (!floor || floor.distance > range) return undefined;
    return floor.position.y + footClearance;
  }

  function collisionAt(x: number, y: number, z: number) {
    collider.radius = radius;
    collider.start.set(x, y + radius, z);
    collider.end.set(x, y + 0.84 - radius, z);
    const collision = octree.capsuleIntersect(collider);
    if (collision && collision.depth > 0.006) return collision;
    // Use a narrow vertical probe for slabs so a stair landing does not catch
    // the side of the body before the feet actually reach it.
    collider.radius = slabRadius;
    collider.start.y = y + slabRadius;
    collider.end.y = y + 0.84 - slabRadius;
    const slab = floorSlabs.capsuleIntersect(collider);
    return slab && slab.depth > 0.006 ? slab : undefined;
  }

  function fits(x: number, y: number, z: number) {
    return !collisionAt(x, y, z);
  }

  function clearLedgeHeight(x: number, z: number, blocked: number, clear: number) {
    for (let i = 0; i < 6; i++) {
      const middle = (blocked + clear) / 2;
      if (fits(x, middle, z)) clear = middle;
      else blocked = middle;
    }
    return clear;
  }

  function land(x: number, y: number, z: number) {
    model.position.set(x, y, z);
    grounded = true;
    verticalSpeed = 0;
  }

  function settleOnSlab(x: number, y: number, z: number) {
    // A falling foot can enter the slab at its edge before the next vertical
    // sweep. Only recover from within its thickness, never from below it.
    ray.origin.set(x, y + floorHeight, z);
    ray.direction.set(0, -1, 0);
    const slab = floorSlabs.rayIntersect(ray);
    if (!slab || slab.position.y < y || !fits(x, slab.position.y + footClearance, z)) return false;
    land(x, slab.position.y + footClearance, z);
    return true;
  }

  function moveTo(x: number, z: number, allowFall = false) {
    const { x: oldX, y: oldY, z: oldZ } = model.position;
    if (!grounded) {
      if (verticalSpeed <= 0 && settleOnSlab(x, oldY, z)) return true;
      if (!fits(x, oldY, z)) return false;
      model.position.set(x, oldY, z);
      return true;
    }
    const height = floorAt(x, z, oldY + 0.19, 0.43);
    if (height !== undefined && fits(x, height, z)) {
      model.position.set(x, height, z);
      return true;
    }
    // At a downward seam the capsule still overlaps the upper floor lip.
    // Move forward and lower only as far as the lip allows.
    if (height !== undefined && height < oldY && fits(x, oldY, z)) {
      model.position.set(x, clearLedgeHeight(x, z, height, oldY), z);
      return true;
    }
    // Probe ahead so the capsule can clear the front lip of a stair landing.
    const distance = Math.hypot(x - oldX, z - oldZ);
    if (distance > 0.00001) {
      const ahead = radius / distance;
      const step = floorAt(x + (x - oldX) * ahead, z + (z - oldZ) * ahead, oldY + 0.24, 0.25);
      if (step !== undefined && step >= oldY - 0.006 && fits(x, step, z)) {
        // Use the next surface to bound the step, without snapping up to it early.
        const base = Math.min(step, height ?? oldY);
        model.position.set(x, fits(x, base, z) ? base : clearLedgeHeight(x, z, base, step), z);
        return true;
      }
    }
    if (!allowFall || height !== undefined || !fits(x, oldY, z)) return false;
    model.position.set(x, oldY, z);
    grounded = false;
    verticalSpeed = 0;
    return true;
  }

  function jump() {
    const { x, y, z } = model.position;
    if (!grounded && (verticalSpeed > 0 || !settleOnSlab(x, y, z))) return;
    grounded = false;
    verticalSpeed = 2.65;
  }

  function moveVertically(dt: number) {
    if (grounded) return;
    const { x, y, z } = model.position;
    verticalSpeed -= 8.2 * dt;
    const next = y + verticalSpeed * dt;
    if (verticalSpeed <= 0) {
      if (settleOnSlab(x, y, z)) return;
      const floor = floorAt(x, z, y + 0.01, y - next + 0.015);
      if (floor !== undefined && fits(x, floor, z)) {
        land(x, floor, z);
        return;
      }
    }
    const collision = collisionAt(x, next, z);
    if (!collision) {
      model.position.y = next;
    } else {
      // The feet can clear a ledge while the rounded capsule still grazes its edge.
      const side = Math.hypot(collision.normal.x, collision.normal.z);
      const push = side > 0.01 ? Math.min(radius, (collision.depth + 0.002) / side) / side : 0;
      const nextX = x + collision.normal.x * push;
      const nextZ = z + collision.normal.z * push;
      if (verticalSpeed < 0 && push > 0 && fits(nextX, next, nextZ)) {
        model.position.set(nextX, next, nextZ);
      } else verticalSpeed = 0;
    }
    if (model.position.y < -3) {
      spawnPlayer();
      updateCamera(0, true);
    }
  }

  function spawnPlayer() {
    grounded = true;
    verticalSpeed = 0;
    model.position.set(0, 0, 2.8);
    const positions = [[0, 2.8], [0, 3.8], [-3, 2], [3, 2.8], [-4, 0], [4, 0]];
    positions.some(([x, z]) => moveTo(x, z));
  }

  function resetView() {
    yaw = model.rotation.y;
    pitch = 0.30;
    updateCamera(0, true);
  }

  function setWorld(scene: THREE.Scene, surfaces: THREE.Object3D[], spawn: boolean) {
    const collisionLayer = 1;
    octree = new Octree();
    floorSlabs = new Octree();
    stairSurfaces = new Octree();
    octree.maxLevel = 8;
    octree.layers.set(collisionLayer);
    scene.updateMatrixWorld(true);
    const slab = new THREE.BoxGeometry(cellSize, floorHeight, cellSize).translate(0, floorHeight / 2, 0);
    const vertices = slab.getAttribute('position');
    const indices = slab.index!;
    function collect(node: THREE.Object3D) {
      if (node.userData.walkableFloor) {
        // The player stands on the full slab, independent of planks or glass details.
        for (let i = 0; i < indices.count; i += 3) {
          const vertex = (j: number) => new THREE.Vector3()
            .fromBufferAttribute(vertices, indices.getX(j)).applyMatrix4(node.matrixWorld);
          floorSlabs.addTriangle(new THREE.Triangle(vertex(i), vertex(i + 1), vertex(i + 2)));
        }
        return;
      }
      if (node instanceof THREE.Mesh && node.userData.walkableRamp) {
        node.geometry.computeBoundingBox();
        const { min, max } = node.geometry.boundingBox!;
        const a = new THREE.Vector3(min.x, min.y, max.z).applyMatrix4(node.matrixWorld);
        const b = new THREE.Vector3(max.x, min.y, max.z).applyMatrix4(node.matrixWorld);
        const c = new THREE.Vector3(min.x, max.y, min.z).applyMatrix4(node.matrixWorld);
        const d = new THREE.Vector3(max.x, max.y, min.z).applyMatrix4(node.matrixWorld);
        stairSurfaces.addTriangle(new THREE.Triangle(a, b, c));
        stairSurfaces.addTriangle(new THREE.Triangle(b, d, c));
      } else if (node instanceof THREE.Mesh) node.layers.enable(collisionLayer);
      for (const child of node.children) collect(child);
    }
    for (const surface of surfaces) collect(surface);
    slab.dispose();
    octree.fromGraphNode(scene);
    if (!floorSlabs.bounds.isEmpty()) floorSlabs.build();
    if (!stairSurfaces.bounds.isEmpty()) stairSurfaces.build();
    if (spawn) {
      spawnPlayer();
      model.rotation.y = Math.PI;
    } else if (!moveTo(model.position.x, model.position.z, true)) {
      spawnPlayer();
    }
    if (spawn) resetView();
    else updateCamera(0, true);
  }

  function turn(horizontal: number, vertical: number, dt = 0) {
    yaw -= horizontal;
    pitch = THREE.MathUtils.clamp(pitch + vertical, -0.12, 1.16);
    updateCamera(dt);
  }

  function update(keys: Set<string>, touchKeys: Set<string>, dt: number, animate: boolean) {
    const key = (name: string) => Number(keys.has(name) || touchKeys.has(name));
    const forward = key('w') - key('s');
    const side = key('d') - key('a');
    const horizontal = key('arrowright') - key('arrowleft');
    const vertical = key('arrowdown') - key('arrowup');
    const previousY = model.position.y;
    let distance = 0;
    if (forward || side) {
      const speed = dt * 1.30 / Math.hypot(forward, side);
      const dx = (Math.sin(yaw) * forward - Math.cos(yaw) * side) * speed;
      const dz = (Math.cos(yaw) * forward + Math.sin(yaw) * side) * speed;
      const { x, z } = model.position;
      if (!moveTo(x + dx, z + dz, true)) {
        if (Math.abs(dx) > 0.00001) moveTo(x + dx, z, true);
        if (Math.abs(dz) > 0.00001) moveTo(model.position.x, z + dz, true);
      }
      distance = Math.hypot(model.position.x - x, model.position.z - z);
      if (distance > 0.00001) model.rotation.y = Math.atan2(model.position.x - x, model.position.z - z);
    }
    for (let remaining = dt; remaining > 0 && !grounded;) {
      const step = Math.min(remaining, 1 / 90);
      moveVertically(step);
      remaining -= step;
    }
    const moved = distance > 0 || previousY !== model.position.y;
    if (moved || horizontal || vertical ||
      cameraY !== model.position.y + 0.59 || cameraDistance !== cameraTargetDistance) {
      turn(horizontal * 1.45 * dt, vertical * dt, dt);
    }
    animatePlayer(distance, dt, animate, grounded);
    return moved;
  }

  return { model, camera, setWorld, resetView, turn, update, jump };
}
