import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { createBuilder, type BuildState } from './builder';
import type { Island } from './data';
import { createDrone, flightKeys } from './drone';
import type { Placement } from './grid';
import { createPlayer, walkKeys } from './player';
import { renderThumbnails } from './thumbnails';
import { createStructureModels, fitImportedFloor } from './structure-models';
import { createScenery, type ModelSet } from './scenery';
import { decorations, localModels, modelUrl, models, type DecorationId, type LocalModelId, type ModelId } from './world-config';

declare const __LOCAL_MODEL_FILES__: string[];
type SceneModels = ModelSet & ReturnType<typeof createStructureModels> & Partial<Record<LocalModelId, THREE.Group>>;

type WorldEvents = {
  buildState: (state: BuildState) => void;
  save: (id: string, placements: Placement[]) => boolean;
  unavailable: () => void;
};

const defaultPosition = new THREE.Vector3(10.5, 8.3, 15.5);
const target = new THREE.Vector3(0, -0.64, 0);


async function loadModels() {
  const loader = new GLTFLoader();
  const core = Promise.all((Object.keys(models) as ModelId[]).map(async (id) => {
    const { scene } = await loader.loadAsync(modelUrl(id));
    return [id, scene] as const;
  }));
  const local = import.meta.env.DEV
    ? Object.entries(localModels).filter(([, file]) => __LOCAL_MODEL_FILES__.includes(file))
    : [];
  const [entries, optional] = await Promise.all([
    core,
    Promise.allSettled(local.map(async ([id, file]) => {
      const { scene } = await loader.loadAsync(`${import.meta.env.BASE_URL}local-assets/models/${file}`);
      // Keep the fence length fitted to one grid edge.
      if (id === 'picketFence') scene.scale.set(1, 2.15, 1.85);
      return [id, scene] as const;
    })),
  ]);
  const assets: SceneModels = { ...Object.fromEntries(entries) as ModelSet, ...createStructureModels() };
  for (const result of optional) {
    if (result.status === 'fulfilled') {
      const [id, model] = result.value;
      assets[id as LocalModelId] = id === 'flatRoof' || id === 'skylight'
        ? fitImportedFloor(model, id === 'flatRoof') : model;
    } else {
      console.warn('MiniWorld skipped a local model.', result.reason);
    }
  }
  return assets;
}

async function loadPlayer() {
  if (!import.meta.env.DEV || !__LOCAL_MODEL_FILES__.includes('player.glb')) return undefined;
  try {
    const { scene, animations } = await new GLTFLoader().loadAsync(`${import.meta.env.BASE_URL}local-assets/models/player.glb`);
    return createPlayer(scene, animations);
  } catch (error) {
    console.warn('MiniWorld skipped the local player model.', error);
  }
}

export async function createWorld(viewport: HTMLElement, events: WorldEvents, island: Island) {
  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-label', '漂浮小岛');
  const gl = canvas.getContext('webgl2', { alpha: true, antialias: true });
  if (!gl) throw new Error('WebGL 2 unavailable');

  const renderer = new THREE.WebGLRenderer({ canvas, context: gl, alpha: true, antialias: true });
  let assets: SceneModels;
  let player: Awaited<ReturnType<typeof loadPlayer>>;
  try {
    [assets, player] = await Promise.all([loadModels(), loadPlayer()]);
  } catch (error) {
    renderer.dispose();
    renderer.forceContextLoss();
    throw error;
  }
  if (gl.isContextLost()) {
    renderer.dispose();
    throw new Error('WebGL context lost');
  }

  renderer.setClearColor(0x000000, 0);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  renderer.shadowMap.autoUpdate = false;
  renderer.shadowMap.needsUpdate = true;
  viewport.append(canvas);

  const shared = new Set<THREE.BufferGeometry | THREE.Material>();
  for (const asset of Object.values(assets)) {
    asset.traverse((object) => {
      if (!(object instanceof THREE.Mesh)) return;
      shared.add(object.geometry);
      for (const material of [object.material].flat() as THREE.Material[]) shared.add(material);
    });
  }

  function createIslandScene(island: Island) {
    const stage = createScenery(assets, island.terrain);
    const builder = createBuilder(stage.scene, assets, stage.scenery, island.placements, Boolean(stage.pond),
      (placements) => events.save(island.id, placements), events.buildState, () => {
        renderer.shadowMap.needsUpdate = true;
      });
    return { ...stage, builder, cloudOrigins: stage.clouds.map((cloud) => cloud.position.x) };
  }

  const drone = createDrone();
  let stage = createIslandScene(island);
  stage.scene.add(drone.model);
  let walking = Boolean(player);
  let editing = false;

  function preparePlayer(spawn: boolean) {
    if (!player) return;
    stage.scene.add(player.model);
    player.setWorld(stage.scene, [stage.ground, stage.scenery, stage.builder.structures], spawn);
    if (!walking || editing) player.model.visible = false;
  }
  preparePlayer(true);

  function disposeIslandScene() {
    const resources = new Set<THREE.BufferGeometry | THREE.Material>();
    stage.scene.traverse((object) => {
      if (!(object instanceof THREE.Mesh || object instanceof THREE.Line)) return;
      resources.add(object.geometry);
      for (const material of [object.material].flat() as THREE.Material[]) resources.add(material);
    });
    for (const resource of resources) {
      if (!shared.has(resource)) resource.dispose();
    }
    stage.sun.shadow.dispose();
  }

  const orthographic = new THREE.OrthographicCamera(-10, 10, 8, -8, 0.1, 80);
  const perspective = new THREE.PerspectiveCamera(40, 1, 0.1, 80);
  const focalRatio = Math.tan(THREE.MathUtils.degToRad(perspective.fov / 2));
  const defaultOffset = defaultPosition.clone().sub(target);
  let camera: THREE.OrthographicCamera | THREE.PerspectiveCamera = orthographic;
  orthographic.position.copy(defaultPosition);
  const controls = new OrbitControls<THREE.Camera>(camera, canvas);
  controls.target.copy(target);
  controls.cursor.copy(target);
  controls.maxTargetRadius = 4;
  controls.minZoom = 0.70;
  controls.maxZoom = 3.5;
  controls.touches.TWO = THREE.TOUCH.DOLLY_PAN;
  controls.update();
  controls.enabled = !walking;

  function perspectiveDistance(zoom: number) {
    return orthographic.top / (focalRatio * zoom);
  }

  function resetCamera() {
    controls.target.copy(target);
    camera.zoom = 1;
    camera.position.copy(defaultOffset);
    if (camera === perspective) camera.position.setLength(perspectiveDistance(1));
    camera.position.add(target);
    camera.updateProjectionMatrix();
    controls.update();
    camera.updateMatrixWorld();
  }

  function toggleProjection() {
    const offset = camera.position.clone().sub(controls.target);
    if (camera === orthographic) {
      offset.setLength(perspectiveDistance(orthographic.zoom));
      controls.minDistance = perspectiveDistance(controls.maxZoom);
      controls.maxDistance = perspectiveDistance(controls.minZoom);
      camera = perspective;
    } else {
      orthographic.zoom = orthographic.top / (focalRatio * offset.length());
      offset.setLength(defaultOffset.length());
      controls.minDistance = 0;
      controls.maxDistance = Infinity;
      camera = orthographic;
    }
    camera.position.copy(controls.target).add(offset);
    camera.updateProjectionMatrix();
    controls.object = camera;
    controls.update();
    camera.updateMatrixWorld();
    return camera === perspective;
  }

  function switchIsland(island: Island) {
    const next = createIslandScene(island);
    drone.model.removeFromParent();
    player?.model.removeFromParent();
    disposeIslandScene();
    stage = next;
    stage.scene.add(drone.model);
    preparePlayer(true);
    resetCamera();
    renderer.shadowMap.needsUpdate = true;
    renderer.render(stage.scene, viewCamera());
  }

  const keys = new Set<string>();
  const touchKeys = new Set<string>();
  const raycaster = new THREE.Raycaster();
  const center = new THREE.Vector2();
  const pointer = new THREE.Vector2();
  const petBounds = new THREE.Sphere(new THREE.Vector3(0, 0, 0), 0.71);
  const petHit = new THREE.Vector3();

  function centerRay() {
    raycaster.setFromCamera(center, drone.camera);
    return raycaster.ray;
  }

  function aim() {
    if (!editing) return;
    stage.builder.aim(centerRay());
  }

  function viewCamera() {
    return editing ? drone.camera : walking && player ? player.camera : camera;
  }

  function updateMode() {
    controls.enabled = !editing && !walking;
    clearInput();
    renderer.shadowMap.needsUpdate = true;
    canvas.tabIndex = editing || walking ? 0 : -1;
    canvas.setAttribute('aria-label', editing
      ? '无人机建造。WASD 移动，E 上升，Q 下降，方向键转向，回车选择或放置，R 旋转。'
      : walking ? '第三人称角色。WASD 行走，空格跳跃，拖动场景或按方向键转向。' : '漂浮小岛');
    canvas.style.cursor = 'grab';
  }

  function setBuildMode(enabled: boolean) {
    if (!stage.builder.setMode(enabled)) return false;
    editing = enabled;
    drone.model.visible = enabled;
    if (enabled) {
      if (player) player.model.visible = false;
      drone.reset();
      aim();
    } else {
      preparePlayer(false);
    }
    updateMode();
    return true;
  }

  function togglePlayer() {
    if (!player || editing) return walking;
    walking = !walking;
    if (walking) player.resetView();
    else player.model.visible = false;
    updateMode();
    return walking;
  }

  function pointsAtPet(event: PointerEvent) {
    const { pet, scenery } = stage;
    if (!pet) return false;
    const rect = canvas.getBoundingClientRect();
    pointer.set((event.clientX - rect.left) / rect.width * 2 - 1,
      1 - (event.clientY - rect.top) / rect.height * 2);
    raycaster.setFromCamera(pointer, viewCamera());
    const { ray } = raycaster;
    petBounds.center.copy(pet.root.position);
    petBounds.center.y = 0.43 + pet.body.position.y;
    if (!ray.intersectSphere(petBounds, petHit)) return false;
    const distance = ray.origin.distanceTo(petHit);
    return !raycaster.intersectObject(scenery).some((hit) => hit.distance < distance);
  }

  function activate() {
    if (!editing) return;
    stage.builder.activate(centerRay());
    aim();
  }

  function rotate() {
    stage.builder.rotate();
    aim();
  }

  function pressKey(event: KeyboardEvent) {
    if ((!editing && !walking) || event.ctrlKey || event.metaKey || event.altKey ||
      (event.target !== canvas && event.target !== document.body)) return;
    const key = event.key.toLowerCase();
    if ((editing ? flightKeys : walkKeys).has(key)) {
      event.preventDefault();
      keys.add(key);
    } else if (!editing && key === ' ') {
      event.preventDefault();
      if (!event.repeat) player?.jump();
    } else if (editing && (key === 'enter' || key === ' ' || key === 'r')) {
      event.preventDefault();
      if (event.repeat) return;
      if (key === 'r') rotate();
      else activate();
    }
  }
  window.addEventListener('keydown', pressKey);
  const releaseKey = (event: KeyboardEvent) => keys.delete(event.key.toLowerCase());
  const clearInput = () => {
    keys.clear();
    touchKeys.clear();
  };
  window.addEventListener('keyup', releaseKey);
  window.addEventListener('blur', clearInput);
  canvas.addEventListener('blur', () => keys.clear());

  const down = new Map<number, { x: number; y: number }>();
  const dragThreshold = 6;
  let gesture = false;
  let lookPointer: number | undefined;

  canvas.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return;
    if (down.size) gesture = true;
    if ((editing || walking) && !down.size) {
      lookPointer = event.pointerId;
      canvas.focus({ preventScroll: true });
      canvas.setPointerCapture(event.pointerId);
    }
    down.set(event.pointerId, { x: event.clientX, y: event.clientY });
    canvas.style.cursor = 'grabbing';
  });

  canvas.addEventListener('pointermove', (event) => {
    const start = down.get(event.pointerId);
    if (!start) {
      if (!editing && !down.size && event.pointerType === 'mouse') {
        canvas.style.cursor = pointsAtPet(event) ? 'pointer' : 'grab';
      }
      return;
    }
    const dx = event.clientX - start.x;
    const dy = event.clientY - start.y;
    if (Math.hypot(dx, dy) > dragThreshold) gesture = true;
    if ((editing || walking) && gesture && event.pointerId === lookPointer) {
      if (editing) drone.turn(dx * 0.005, -dy * 0.005);
      else player?.turn(dx * 0.005, dy * 0.005);
      start.x = event.clientX;
      start.y = event.clientY;
      aim();
    }
  });

  function endPointer(event: PointerEvent) {
    down.delete(event.pointerId);
    if (event.pointerId === lookPointer) lookPointer = undefined;
    if (!down.size) {
      gesture = false;
      canvas.style.cursor = 'grab';
    }
  }

  canvas.addEventListener('pointerup', (event) => {
    const start = down.get(event.pointerId);
    const click = start && !gesture && Math.hypot(event.clientX - start.x, event.clientY - start.y) <= dragThreshold &&
      document.elementFromPoint(event.clientX, event.clientY) === canvas;
    endPointer(event);
    if (!click) return;
    if (editing) activate();
    else if (pointsAtPet(event)) stage.pet?.react();
  });
  canvas.addEventListener('pointercancel', endPointer);
  canvas.addEventListener('lostpointercapture', endPointer);

  function resize() {
    const { clientWidth: width, clientHeight: height } = viewport;
    if (!width || !height) return;
    const aspect = width / height;
    const halfHeight = Math.max(6.75, 8.05 / aspect);
    const scale = halfHeight / orthographic.top;
    orthographic.left = -halfHeight * aspect;
    orthographic.right = halfHeight * aspect;
    orthographic.top = halfHeight;
    orthographic.bottom = -halfHeight;
    orthographic.updateProjectionMatrix();
    drone.camera.aspect = aspect;
    drone.camera.updateProjectionMatrix();
    if (player) {
      player.camera.aspect = aspect;
      player.camera.updateProjectionMatrix();
    }
    perspective.aspect = aspect;
    perspective.far = perspectiveDistance(controls.minZoom) + 40;
    perspective.updateProjectionMatrix();
    if (camera === perspective) {
      controls.minDistance = perspectiveDistance(controls.maxZoom);
      controls.maxDistance = perspectiveDistance(controls.minZoom);
      perspective.position.sub(controls.target).multiplyScalar(scale).add(controls.target);
      controls.update();
      perspective.updateMatrixWorld();
    }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, width < 700 ? 1.35 : 1.65));
    renderer.setSize(width, height, false);
  }
  resize();
  const observer = new ResizeObserver(resize);
  observer.observe(viewport);

  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  let elapsed = 0;
  let previousFrame = 0;

  function frame(now: number) {
    const dt = previousFrame ? Math.min((now - previousFrame) / 1000, 0.05) : 0;
    previousFrame = now;
    const { scene, pet, pond, clouds, cloudOrigins } = stage;
    if (!motion.matches) {
      elapsed += dt;
      pond?.update(elapsed);
      clouds.forEach((cloud, index) => {
        cloud.position.x = cloudOrigins[index] + Math.sin(elapsed * 0.15 + index * 0.7) * 0.8;
      });
    }
    pet?.update(dt, elapsed, motion.matches || editing);
    if (editing && drone.fly(keys, touchKeys, dt, !motion.matches)) aim();
    if (!editing && walking && player?.update(keys, touchKeys, dt, !motion.matches)) {
      renderer.shadowMap.needsUpdate = true;
    }
    renderer.render(scene, viewCamera());
  }

  function syncAnimation() {
    previousFrame = 0;
    if (document.hidden) clearInput();
    renderer.setAnimationLoop(document.hidden ? null : frame);
  }
  document.addEventListener('visibilitychange', syncAnimation);
  updateMode();
  renderer.render(stage.scene, viewCamera());
  syncAnimation();

  canvas.addEventListener('webglcontextlost', () => {
    document.removeEventListener('visibilitychange', syncAnimation);
    window.removeEventListener('keydown', pressKey);
    window.removeEventListener('keyup', releaseKey);
    window.removeEventListener('blur', clearInput);
    renderer.setAnimationLoop(null);
    observer.disconnect();
    controls.dispose();
    disposeIslandScene();
    renderer.dispose();
    canvas.remove();
    events.unavailable();
  }, { once: true });

  const availableDecorations = (Object.keys(decorations) as DecorationId[]).filter((id) => assets[id]);
  let thumbnails: Map<DecorationId, string> | undefined;
  return {
    availableDecorations,
    thumbnails: () => thumbnails ??= renderThumbnails(renderer, assets, availableDecorations),
    setBuildMode,
    hasPlayer: Boolean(player),
    togglePlayer,
    jump() {
      if (walking && !editing) player?.jump();
    },
    setMovementKey(key: string, pressed: boolean) {
      if ((!editing && !walking) || !(editing ? flightKeys : walkKeys).has(key)) return;
      if (pressed) touchKeys.add(key);
      else touchKeys.delete(key);
    },
    switchIsland,
    place(id: DecorationId) {
      stage.builder.place(id);
      aim();
    },
    move() {
      stage.builder.move();
      aim();
    },
    rotate,
    remove() {
      stage.builder.remove();
      aim();
    },
    cancel() {
      const cancelled = stage.builder.cancel();
      if (cancelled) aim();
      return cancelled;
    },
    focusGrid: () => canvas.focus({ preventScroll: true }),
    reset() {
      if (walking && player) player.resetView();
      else resetCamera();
    },
    toggleProjection,
  };
}
