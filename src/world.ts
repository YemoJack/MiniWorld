import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { createBuilder, type BuildState } from './builder';
import type { Island } from './data';
import type { Placement } from './grid';
import { renderThumbnails } from './thumbnails';
import { createStructureModels } from './structure-models';
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
      return [id, scene] as const;
    })),
  ]);
  const assets: SceneModels = { ...Object.fromEntries(entries) as ModelSet, ...createStructureModels() };
  for (const result of optional) {
    if (result.status === 'fulfilled') {
      const [id, model] = result.value;
      assets[id as LocalModelId] = model;
    } else {
      console.warn('MiniWorld skipped a local model.', result.reason);
    }
  }
  return assets;
}

export async function createWorld(viewport: HTMLElement, events: WorldEvents, island: Island) {
  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-label', '漂浮小岛');
  const gl = canvas.getContext('webgl2', { alpha: true, antialias: true });
  if (!gl) throw new Error('WebGL 2 unavailable');

  const renderer = new THREE.WebGLRenderer({ canvas, context: gl, alpha: true, antialias: true });
  let assets: SceneModels;
  try {
    assets = await loadModels();
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

  let stage = createIslandScene(island);

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
    disposeIslandScene();
    stage = next;
    resetCamera();
    renderer.shadowMap.needsUpdate = true;
    renderer.render(stage.scene, camera);
  }

  let editing = false;
  function setBuildMode(enabled: boolean) {
    if (!stage.builder.setMode(enabled)) return false;
    editing = enabled;
    if (enabled) canvas.tabIndex = 0;
    else canvas.removeAttribute('tabindex');
    canvas.setAttribute('aria-label', enabled ? '建造网格，方向键选格，回车放置，R 键旋转' : '漂浮小岛');
    if (!enabled) cancelItemPress();
    canvas.style.cursor = enabled ? 'crosshair' : 'grab';
    return true;
  }

  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  const petBounds = new THREE.Sphere(new THREE.Vector3(), 0.71);
  const petHit = new THREE.Vector3();

  function pointAt(event: PointerEvent) {
    const rect = canvas.getBoundingClientRect();
    pointer.set((event.clientX - rect.left) / rect.width * 2 - 1,
      1 - (event.clientY - rect.top) / rect.height * 2);
    raycaster.setFromCamera(pointer, camera);
    return raycaster.ray;
  }

  function pointsAtPet(ray: THREE.Ray) {
    const { pet, scenery } = stage;
    if (!pet) return false;
    petBounds.center.copy(pet.root.position);
    petBounds.center.y = 0.43 + pet.body.position.y;
    if (!ray.intersectSphere(petBounds, petHit)) return false;
    const distance = ray.origin.distanceTo(petHit);
    return !raycaster.intersectObject(scenery).some((hit) => hit.distance < distance);
  }

  canvas.addEventListener('keydown', (event) => {
    if (!editing) return;
    const directions: Record<string, [number, number]> = {
      ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1],
    };
    if (event.key === 'Enter') {
      event.preventDefault();
      if (!event.repeat) stage.builder.commit();
    } else if (event.key.toLowerCase() === 'r' && !event.ctrlKey && !event.metaKey && !event.altKey) {
      event.preventDefault();
      if (!event.repeat) stage.builder.rotate();
    } else if (Object.hasOwn(directions, event.key)) {
      event.preventDefault();
      const [dx, dz] = directions[event.key];
      const angle = Math.round(controls.getAzimuthalAngle() / (Math.PI / 2)) * Math.PI / 2;
      stage.builder.moveSelection(
        Math.round(dx * Math.cos(angle) + dz * Math.sin(angle)),
        Math.round(dz * Math.cos(angle) - dx * Math.sin(angle)),
      );
    }
  });

  const down = new Map<number, { x: number; y: number }>();
  const dragThreshold = 6;
  let gesture = false;
  let itemPress: { id: number; offset: { x: number; z: number }; dragging: boolean } | undefined;

  function cancelItemPress() {
    if (!itemPress) return false;
    if (itemPress.dragging) stage.builder.finishDrag();
    itemPress = undefined;
    controls.enableRotate = true;
    gesture = true;
    return true;
  }

  canvas.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return;
    if (down.size > 0) {
      gesture = true;
      cancelItemPress();
    } else if (editing && !event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey) {
      const offset = stage.builder.grab(pointAt(event));
      if (offset) {
        itemPress = { id: event.pointerId, offset, dragging: false };
        // OrbitControls still tracks the pointer, so a second touch can take over for pinch zoom.
        controls.enableRotate = false;
      }
    }
    down.set(event.pointerId, { x: event.clientX, y: event.clientY });
    canvas.style.cursor = 'grabbing';
  }, { capture: true });

  function isOverCanvas(event: PointerEvent) {
    return document.elementFromPoint(event.clientX, event.clientY) === canvas;
  }

  canvas.addEventListener('pointermove', (event) => {
    const start = down.get(event.pointerId);
    if (start) {
      if (Math.hypot(event.clientX - start.x, event.clientY - start.y) > dragThreshold) gesture = true;
      if (itemPress?.id === event.pointerId && gesture) {
        if (!itemPress.dragging) itemPress.dragging = stage.builder.move();
        if (isOverCanvas(event)) stage.builder.aim(pointAt(event), itemPress.offset);
        else stage.builder.setTarget();
      }
    } else if (event.pointerType === 'mouse' && down.size === 0) {
      const ray = pointAt(event);
      if (editing) stage.builder.aim(ray);
      canvas.style.cursor = editing ? 'crosshair' : pointsAtPet(ray) ? 'pointer' : 'grab';
    }
  });
  canvas.addEventListener('pointerup', (event) => {
    const start = down.get(event.pointerId);
    if (!down.delete(event.pointerId) || !start) return;
    const overCanvas = isOverCanvas(event);
    if (itemPress?.id === event.pointerId) {
      if (itemPress.dragging) {
        stage.builder.finishDrag(overCanvas ? pointAt(event) : undefined, itemPress.offset);
      }
      itemPress = undefined;
      controls.enableRotate = true;
    } else if (overCanvas && !gesture && Math.hypot(event.clientX - start.x, event.clientY - start.y) <= dragThreshold) {
      const ray = pointAt(event);
      if (editing) stage.builder.activate(ray);
      else if (pointsAtPet(ray)) stage.pet?.react();
    }
    if (down.size === 0) gesture = false;
    canvas.style.cursor = editing ? 'crosshair' : 'grab';
  });

  function cancelPointer(event: PointerEvent) {
    if (itemPress?.id === event.pointerId) cancelItemPress();
    down.delete(event.pointerId);
    if (down.size === 0) {
      gesture = false;
      canvas.style.cursor = editing ? 'crosshair' : 'grab';
    }
  }
  canvas.addEventListener('pointercancel', cancelPointer);
  canvas.addEventListener('lostpointercapture', cancelPointer);
  canvas.addEventListener('pointerleave', () => {
    if (editing && down.size === 0) stage.builder.setTarget();
  });

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
    renderer.render(scene, camera);
  }

  function syncAnimation() {
    previousFrame = 0;
    renderer.setAnimationLoop(document.hidden ? null : frame);
  }
  document.addEventListener('visibilitychange', syncAnimation);
  renderer.render(stage.scene, camera);
  syncAnimation();

  canvas.addEventListener('webglcontextlost', () => {
    document.removeEventListener('visibilitychange', syncAnimation);
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
    switchIsland,
    place: (id: DecorationId) => stage.builder.place(id),
    move: () => stage.builder.move(),
    rotate: () => stage.builder.rotate(),
    remove: () => stage.builder.remove(),
    cancel: () => cancelItemPress() || stage.builder.cancel(),
    focusGrid: () => canvas.focus({ preventScroll: true }),
    reset: resetCamera,
    toggleProjection,
  };
}
