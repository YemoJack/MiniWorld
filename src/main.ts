import './style.css';
import { readIslands, writeIslands, type Island, type IslandState } from './data';
import type { Placement } from './grid';
import { decorationCategories, decorations, type DecorationCategory, type DecorationId } from './world-config';
import type { BuildState } from './builder';
import type { createWorld } from './world';

const page = document.querySelector<HTMLElement>('#world')!;
const viewport = document.querySelector<HTMLElement>('#viewport')!;
const exploreToolbar = document.querySelector<HTMLElement>('#explore-toolbar')!;
const buildButton = document.querySelector<HTMLButtonElement>('#build-button')!;
const resetButton = document.querySelector<HTMLButtonElement>('#reset-button')!;
const projectionButton = document.querySelector<HTMLButtonElement>('#projection-button')!;
const playerButton = document.querySelector<HTMLButtonElement>('#player-button')!;
const panel = document.querySelector<HTMLElement>('#build-panel')!;
const tools = document.querySelector<HTMLElement>('#build-tools')!;
const categories = document.querySelector<HTMLElement>('#build-categories')!;
const islandButton = document.querySelector<HTMLButtonElement>('#island-switcher')!;
const islandName = document.querySelector<HTMLElement>('#current-island')!;
const islandDialog = document.querySelector<HTMLDialogElement>('#island-dialog')!;
const islandList = document.querySelector<HTMLUListElement>('#island-list')!;
const islandError = document.querySelector<HTMLElement>('#island-error')!;
const createIslandButton = document.querySelector<HTMLButtonElement>('#create-island')!;
const poster = document.querySelector<HTMLImageElement>('.poster')!;
const context = document.querySelector<HTMLElement>('#build-context')!;
const selectedItem = document.querySelector<HTMLElement>('#selected-item')!;
const status = document.querySelector<HTMLElement>('#build-status')!;
const saveError = document.querySelector<HTMLElement>('#build-error')!;
const moveButton = document.querySelector<HTMLButtonElement>('#move-button')!;
const rotateButton = document.querySelector<HTMLButtonElement>('#rotate-button')!;
const removeButton = document.querySelector<HTMLButtonElement>('#remove-button')!;
const cancelButton = document.querySelector<HTMLButtonElement>('#cancel-preview')!;
const finishButton = document.querySelector<HTMLButtonElement>('#finish-build')!;
const flightHud = document.querySelector<HTMLElement>('#flight-hud')!;
const jumpButton = document.querySelector<HTMLButtonElement>('#jump-button')!;
const crosshair = document.querySelector<SVGSVGElement>('#build-crosshair')!;

let world: Awaited<ReturnType<typeof createWorld>> | undefined;
let editing = false;
let walking = false;
let islands = readIslands();
let active = islands.islands.find(({ id }) => id === islands.activeId)!;
let category: 'all' | DecorationCategory = 'all';
let available = new Set<DecorationId>();
let thumbnailsReady = false;

for (const button of flightHud.querySelectorAll<HTMLButtonElement>('[data-flight]')) {
  const key = button.dataset.flight!;
  button.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    button.setPointerCapture(event.pointerId);
    world?.setMovementKey(key, true);
  });
  const release = () => world?.setMovementKey(key, false);
  button.addEventListener('pointerup', release);
  button.addEventListener('pointercancel', release);
  button.addEventListener('lostpointercapture', release);
}

const icons: Record<DecorationId, string> = {
  floor: 'm3 10 9-5 9 5-9 5-9-5Zm0 0v4l9 5 9-5v-4M6 8l9 5m-5-7 9 5',
  wall: 'M4 4h16v16H4zm0 5h16M4 14h16M9 4v5m6 0v5m-6 0v6',
  doorway: 'M4 20V4h16v16h-4V8H8v12H4Z',
  windowWall: 'M4 4h16v16H4zm4 4h8v7H8zm4 0v7',

  flowers: 'M4 14h16l-2 6H6l-2-6Zm8 0V5m0 4-4-3m4 3 4-3M7 14l-2-3m12 3 2-3',
  crate: 'M4 7 12 3l8 4v10l-8 4-8-4V7Zm0 0 8 4 8-4m-8 4v10M4 12l8 4 8-4',
  lantern: 'M9 6V4a3 3 0 0 1 6 0v2M6 8l3-2h6l3 2-2 10H8L6 8Zm2 10-1 3h10l-1-3m-4-7v4',
  bridge: 'M3 19c4-7 14-7 18 0M3 15c4-7 14-7 18 0M3 15v4m5-9v4m8-4v4m5 1v4',
  bench: 'M4 5h16v6H4zm-2 8h20v3H2zm3 3v4m14-4v4',
  planter: 'M4 12h16l-2 7H6l-2-7Zm8 0V5m0 4C8 9 7 7 7 5c3 0 5 2 5 4Zm0 0c4 0 5-2 5-4-3 0-5 2-5 4Z',
  cafeCounter: 'M3 9h18v3H3zm2 3v8h14v-8M9 9V4h6v3h-3m-4 8h8',
  gazebo: 'M2 10 12 3l10 7H2Zm3 0v10m14-10v10M3 20h18',
  picketFence: 'M5 20V7l2-3 2 3v13m6 0V7l2-3 2 3v13M3 10h18M3 16h18',
  halfWall: 'M3 10h18v10H3zm0 5h18m-12-5v5m6 0v5',
  glassWall: 'M4 3h16v18H4zm3 11 6-6m-3 9 6-6',
  glassDoor: 'M5 21V3h14v18M8 6h8v9H8zm5 12h3',
  shopWindow: 'M3 5h18v14H3zm9 0v14M3 15h18',
  rollerShutter: 'M3 21V4h18v17M3 8h18M3 12h18M3 16h18m-12 4h6',
  shopfront: 'M2 6h20l-2 5H4L2 6Zm2 5v10h16V11M8 21v-6h4v6',
  steelColumn: 'M7 4h10v3H7zm3 3v10m4-10v10m-7 0h10v3H7z',
  stairs: 'M3 20v-4h6v-5h6V6h6v14H3Z',
  flatRoof: 'm3 12 9-6 9 6-9 6-9-6Zm0 0v3l9 6 9-6v-3',
  skylight: 'm3 12 9-6 9 6-9 6-9-6Zm5-3 8 6m0-6-8 6',
  cafeChair: 'M5 3h3v10h10v3H5V3Zm2 13v5m9-5v5',
  cafeTable: 'M3 7h18v3H3zm9 3v10m-5 0h10',
  flowerPot: 'M5 10h14l-2 10H7L5 10Zm7 0V4m0 3L8 4m4 3 4-3',
  pathLight: 'M8 5h8v5H8zm2 5v10m4-10v10m-6 0h8',
  trashBin: 'M5 7h14M9 7V4h6v3m-8 0 1 13h8l1-13',
  treeStump: 'M5 8c0-2 3-4 7-4s7 2 7 4-3 4-7 4-7-2-7-4Zm0 0v8c0 2 3 4 7 4s7-2 7-4V8m-9 0h4',
};

const toolButtons = (Object.keys(decorations) as DecorationId[]).map((id) => {
  const button = document.createElement('button');
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  path.setAttribute('d', icons[id]);
  svg.append(path);
  button.type = 'button';
  const tile = document.createElement('span');
  tile.className = 'build-thumbnail';
  tile.append(svg);
  const name = document.createElement('span');
  name.textContent = decorations[id].label;
  button.append(tile, name);
  button.setAttribute('aria-pressed', 'false');
  button.addEventListener('click', () => {
    world?.place(id);
    world?.focusGrid();
  });
  tools.append(button);
  return { id, button, tile };
});

const categoryOptions = [['all', '全部'], ...Object.entries(decorationCategories)] as const;
const categoryButtons = categoryOptions.map(([key, label]) => {
  const id = key as typeof category;
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = label;
  button.addEventListener('click', () => {
    category = id;
    updateCatalog();
    tools.scrollLeft = 0;
  });
  categories.append(button);
  return { id, button };
});

function updateCatalog() {
  for (const { id, button } of categoryButtons) {
    button.setAttribute('aria-pressed', String(category === id));
  }
  for (const { id, button } of toolButtons) {
    button.hidden = !available.has(id) || (category !== 'all' && decorations[id].category !== category);
  }
}

function showThumbnails() {
  if (thumbnailsReady || !world) return;
  thumbnailsReady = true;
  try {
    const thumbnails = world.thumbnails();
    for (const { id, tile } of toolButtons) {
      const thumbnail = thumbnails.get(id);
      if (!thumbnail) continue;
      const image = document.createElement('img');
      image.alt = '';
      image.width = 168;
      image.height = 112;
      image.src = thumbnail;
      tile.replaceChildren(image);
    }
  } catch (error) {
    console.warn('MiniWorld could not render catalog thumbnails.', error);
  }
}

function persistIslands(next: IslandState) {
  if (!writeIslands(next)) return false;
  islands = next;
  active = next.islands.find(({ id }) => id === next.activeId)!;
  return true;
}

function saveIsland(id: string, placements: Placement[]) {
  const saved = persistIslands({
    ...islands,
    islands: islands.islands.map((island) => island.id === id ? { ...island, placements } : island),
  });
  saveError.hidden = saved;
  return saved;
}

function showIsland() {
  islandName.textContent = active.name;
  const path = active.terrain === 'flat' ? 'island-flat.svg' : 'island.webp';
  poster.src = `${import.meta.env.BASE_URL}${path}`;
}

function activateIsland(id: string, created?: Island) {
  if (id !== active.id) {
    if ((editing && !setEditing(false)) ||
      !persistIslands({ activeId: id, islands: created ? [...islands.islands, created] : islands.islands })) {
      islandError.hidden = false;
      return;
    }
    world?.switchIsland(active);
    showIsland();
  }
  islandDialog.close();
  islandButton.focus();
}

islandButton.addEventListener('click', () => {
  islandError.hidden = true;
  islandList.replaceChildren(...islands.islands.map((island) => {
    const row = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = island.name;
    if (island.id === active.id) button.setAttribute('aria-current', 'true');
    button.addEventListener('click', () => activateIsland(island.id));
    row.append(button);
    return row;
  }));
  islandDialog.showModal();
  islandList.querySelector<HTMLButtonElement>('[aria-current]')?.focus();
});

createIslandButton.addEventListener('click', () => {
  const number = islands.islands.filter(({ terrain }) => terrain === 'flat').length + 1;
  const id = crypto.randomUUID?.() ?? `island-${Date.now()}-${number}`;
  activateIsland(id, { id, name: `岛屿 ${number}`, terrain: 'flat', placements: [] });
});
showIsland();

function showBuildState(state: BuildState) {
  const selected = state.mode === 'selected';
  const preview = state.mode === 'place' || state.mode === 'move';
  crosshair.dataset.state = preview ? state.target : selected ? 'ready' : 'empty';
  context.hidden = state.mode === 'browse';
  selectedItem.textContent = state.mode === 'browse' ? '' : decorations[state.item].label;
  moveButton.hidden = !selected;
  removeButton.hidden = !selected;
  cancelButton.hidden = !preview;
  status.textContent = preview
    ? state.target === 'blocked' ? '位置不可用' : state.target === 'empty'
      ? '瞄准建造表面'
      : ''
    : selected && state.blocked ? '旋转空间不足' : '';

  for (const { id, button } of toolButtons) {
    button.setAttribute('aria-pressed', String(state.mode === 'place' && state.item === id));
  }
}

function updateViewControls() {
  flightHud.hidden = !editing && !walking;
  flightHud.classList.toggle('is-walking', walking && !editing);
  playerButton.hidden = editing || !world?.hasPlayer;
  playerButton.setAttribute('aria-pressed', String(walking));
  projectionButton.hidden = editing || walking;
}

function setEditing(next: boolean) {
  if (!world) return false;
  if (!world.setBuildMode(next)) {
    saveError.hidden = false;
    return false;
  }
  editing = next;
  saveError.hidden = true;
  panel.hidden = !editing;
  updateViewControls();
  exploreToolbar.hidden = editing;
  buildButton.setAttribute('aria-expanded', String(editing));
  if (editing) {
    showThumbnails();
    world.focusGrid();
  } else if (walking) world.focusGrid();
  else buildButton.focus();
  return true;
}

buildButton.addEventListener('click', () => setEditing(true));
finishButton.addEventListener('click', () => setEditing(false));
resetButton.addEventListener('click', () => {
  world?.reset();
  if (walking) world?.focusGrid();
});
jumpButton.addEventListener('click', () => {
  world?.jump();
  world?.focusGrid();
});
playerButton.addEventListener('click', () => {
  if (!world) return;
  walking = world.togglePlayer();
  updateViewControls();
  if (walking) world.focusGrid();
});
projectionButton.addEventListener('click', () => {
  if (!world) return;
  projectionButton.setAttribute('aria-pressed', String(world.toggleProjection()));
  if (editing) world.focusGrid();
});
moveButton.addEventListener('click', () => {
  world?.move();
  world?.focusGrid();
});
rotateButton.addEventListener('click', () => world?.rotate());
removeButton.addEventListener('click', () => {
  world?.remove();
  world?.focusGrid();
});
cancelButton.addEventListener('click', () => {
  world?.cancel();
  world?.focusGrid();
});
page.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape' || !editing || islandDialog.open) return;
  if (world?.cancel()) world.focusGrid();
  else setEditing(false);
});

function showPoster() {
  editing = false;
  walking = false;
  world = undefined;
  page.classList.remove('is-ready');
  buildButton.disabled = true;
  resetButton.disabled = true;
  projectionButton.disabled = true;
  islandButton.disabled = false;
  buildButton.setAttribute('aria-expanded', 'false');
  panel.hidden = true;
  updateViewControls();
  exploreToolbar.hidden = false;
}

async function start() {
  try {
    const { createWorld } = await import('./world');
    world = await createWorld(viewport, {
      buildState: showBuildState,
      save: saveIsland,
      unavailable: showPoster,
    }, active);
    available = new Set(world.availableDecorations);
    walking = world.hasPlayer;
    updateViewControls();
    updateCatalog();
    islandButton.disabled = false;
    buildButton.disabled = false;
    resetButton.disabled = false;
    projectionButton.disabled = false;
    page.classList.add('is-ready');
  } catch (error) {
    console.warn('MiniWorld switched to the static island.', error);
    showPoster();
  }
}
void start();
