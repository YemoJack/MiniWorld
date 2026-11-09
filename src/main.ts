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

let world: Awaited<ReturnType<typeof createWorld>> | undefined;
let editing = false;
let islands = readIslands();
let active = islands.islands.find(({ id }) => id === islands.activeId)!;
let category: 'all' | DecorationCategory = 'all';
let available = new Set<DecorationId>();
let thumbnailsReady = false;

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
  return persistIslands({
    ...islands,
    islands: islands.islands.map((island) => island.id === id ? { ...island, placements } : island),
  });
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
  context.hidden = state.mode === 'browse';
  selectedItem.textContent = state.mode === 'browse' ? '' : decorations[state.item].label;
  moveButton.hidden = !selected;
  removeButton.hidden = !selected;
  cancelButton.hidden = !preview;
  status.textContent = preview
    ? state.target === 'blocked' ? '位置不可用' : state.target === 'empty'
      ? state.mode === 'move' ? '点选目标格' : '点格放置'
      : ''
    : selected && state.blocked ? '旋转空间不足' : '';

  for (const { id, button } of toolButtons) {
    button.setAttribute('aria-pressed', String(state.mode === 'place' && state.item === id));
  }
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
  exploreToolbar.hidden = editing;
  buildButton.setAttribute('aria-expanded', String(editing));
  if (editing) {
    showThumbnails();
    world.focusGrid();
  } else buildButton.focus();
  return true;
}

buildButton.addEventListener('click', () => setEditing(true));
finishButton.addEventListener('click', () => setEditing(false));
resetButton.addEventListener('click', () => world?.reset());
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
  world = undefined;
  page.classList.remove('is-ready');
  buildButton.disabled = true;
  resetButton.disabled = true;
  projectionButton.disabled = true;
  islandButton.disabled = false;
  buildButton.setAttribute('aria-expanded', 'false');
  panel.hidden = true;
  exploreToolbar.hidden = false;
}

async function start() {
  try {
    const { createWorld } = await import('./world');
    world = await createWorld(viewport, { buildState: showBuildState, save: saveIsland, unavailable: showPoster }, active);
    available = new Set(world.availableDecorations);
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
