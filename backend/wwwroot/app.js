const $ = (id) => document.getElementById(id);
const fmt = (value) => new Intl.NumberFormat('es-MX').format(value ?? 0);
const time = (value) => {
  const millis = Math.max(0, Math.round(Number(value || 0) * 1000));
  const minutes = Math.floor(millis / 60000);
  const seconds = Math.floor((millis % 60000) / 1000);
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}.${String(millis % 1000).padStart(3, '0')}`;
};
const date = (iso) => {
  if (!iso) return '';
  const parsed = new Date(iso);
  return Number.isNaN(parsed.getTime()) ? '' : new Intl.DateTimeFormat('es-MX', { dateStyle: 'short', timeStyle: 'short' }).format(parsed);
};
const levelNames = ['Ruinas del huerto', 'Bosque esmeralda', 'Dunas del sol', 'Cumbres de cristal'];
const levelName = (id, details = null) => id == null
  ? (details?.map_name || `Mapa personalizado #${details?.map_id || '?'}`)
  : (levelNames[id - 1] || `Mapa ${id}`);
let category = 'any_percent';
let officialLayouts = [];
let communityMaps = [];
let replayRows = [];
let selectedReplayId = null;
let replayDetail = null;
let replayLayout = null;
let replaySamples = [];
let replayDuration = 0;
let currentTime = 0;
let playing = false;
let lastAnimationTime = 0;
let selectedMapId = null;
let replayRequestSerial = 0;
let lastActiveEventId = null;
const themes = {
  ruins: { sky: '#c9b293', platform: ['#a74f46', '#b75a4e', '#477e32', '#77be45', '#913e3d', '#c86a57'] },
  forest: { sky: '#91b5a0', platform: ['#624934', '#79533c', '#24704c', '#82db70', '#463c31', '#926849'] },
  desert: { sky: '#eed08b', platform: ['#a75a38', '#c97c42', '#dca34d', '#ffe08a', '#995136', '#edac62'] },
  snow: { sky: '#a4cde2', platform: ['#476d9b', '#608aba', '#a8dcec', '#effbff', '#385b8b', '#82b9d5'] },
};
const backgroundThemes = { Brown: 'ruins', Green: 'forest', Yellow: 'desert', Blue: 'snow' };
const fruitThemes = { Apple: 'ruins', Cherries: 'forest', Orange: 'desert', Strawberry: 'snow' };
const gameAssetNames = [
  ...['ruins', 'forest', 'desert', 'snow'].flatMap((theme) => [`background-${theme}`, `fruit-${theme}`]),
  'saw', 'trampoline', 'start', 'goal', 'player-idle', 'player-run', 'player-jump', 'player-fall', 'player-hit',
];
const gameImages = new Map();
function loadGameAssets() {
  return Promise.all(gameAssetNames.map((name) => new Promise((resolve) => {
    const image = new Image();
    image.onload = () => { gameImages.set(name, image); resolve(); };
    image.onerror = resolve;
    image.src = `/game-assets/${name}.png`;
  }))).then(() => {
    window.gameAssetsReady = true;
    window.dispatchEvent(new Event('game-assets-loaded'));
  });
}
const themeNames = { ruins: 'Ruinas', forest: 'Bosque', desert: 'Desierto', snow: 'Nieve' };
const eventLabels = {
  level_started: 'Comenzó', map_test_started: 'Comenzó prueba',
  fruit_collected: 'Fruta recogida', coin_collected: 'Moneda recogida',
  jump: 'Salto', trampoline_bounce: 'Trampolín', death: 'Murió',
  respawn: 'Volvió al inicio', level_restarted: 'Reinició nivel',
  map_test_restarted: 'Reinició prueba', level_completed: 'Llegó a la meta',
  map_test_completed: 'Llegó a la meta',
};

async function getJson(url) {
  const response = await fetch(url, { cache: 'no-store' });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

function cell(row, value) {
  const node = document.createElement('td');
  node.textContent = value;
  row.append(node);
  return node;
}

async function loadLeaderboard() {
  const body = $('leaderboard-body');
  body.replaceChildren();
  const level = Number($('level-select').value);
  try {
    const records = await getJson(`/api/leaderboards?level_id=${level}&category=${category}`);
    if (!records.length) {
      const row = document.createElement('tr');
      const empty = document.createElement('td');
      empty.colSpan = 6;
      empty.className = 'empty';
      empty.textContent = 'Todavía no hay tiempos en esta categoría.';
      row.append(empty);
      body.append(row);
      return;
    }
    records.forEach((record, index) => {
      const row = document.createElement('tr');
      cell(row, String(index + 1).padStart(2, '0'));
      cell(row, record.name || 'Jugador');
      cell(row, time(record.seconds));
      cell(row, fmt(record.fruits_collected));
      cell(row, fmt(record.coins_collected));
      const replayCell = cell(row, '');
      if (record.attempt_id) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'table-replay-button';
        button.textContent = 'VER RUTA ↗';
        button.addEventListener('click', () => openReplay(record.attempt_id, true));
        replayCell.append(button);
      } else {
        replayCell.textContent = 'Sin recorrido';
        replayCell.className = 'muted-cell';
      }
      body.append(row);
    });
  } catch {
    const row = document.createElement('tr');
    const error = document.createElement('td');
    error.colSpan = 6;
    error.className = 'empty';
    error.textContent = 'No se pudieron cargar los tiempos.';
    row.append(error);
    body.append(row);
  }
}

function feedItem(parent, heading, detail, metric, replayId = null) {
  const li = document.createElement('li');
  const main = document.createElement('span');
  const strong = document.createElement('strong');
  strong.textContent = heading;
  const small = document.createElement('small');
  small.textContent = detail;
  main.append(strong, small);
  const value = document.createElement('span');
  value.className = 'metric';
  value.textContent = metric;
  li.append(main, value);
  if (replayId) {
    li.classList.add('feed-link');
    li.tabIndex = 0;
    li.setAttribute('role', 'button');
    li.setAttribute('aria-label', `Ver recorrido de ${heading}`);
    li.addEventListener('click', () => openReplay(replayId, true));
    li.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); openReplay(replayId, true); }
    });
  }
  parent.append(li);
}

async function loadDashboard() {
  const status = $('server-status');
  try {
    const data = await getJson('/api/dashboard');
    status.className = 'server-status online';
    status.lastChild.textContent = ' En línea';
    for (const key of ['sessions', 'runs', 'fruits', 'coins', 'maps']) {
      $(`stat-${key}`).textContent = fmt(data.totals[key]);
    }
    const runs = $('recent-runs');
    runs.replaceChildren();
    data.recent_runs.forEach((run) => feedItem(runs, run.name,
      `${levelName(run.level_id)} · ${run.category === 'all_fruits' ? 'Todas las frutas' : 'Any%'} · ${date(run.completed_at)}`,
      time(run.seconds), run.attempt_id));
    if (!data.recent_runs.length) feedItem(runs, 'Sin partidas todavía', 'Termina un nivel para aparecer aquí.', '—');
    const events = $('recent-events');
    events.replaceChildren();
    data.recent_events.forEach((event) => feedItem(events, event.name,
      `${eventLabels[event.event_type] || event.event_type.replaceAll('_', ' ')} · ${levelName(event.level_id, event.details)} · ${date(event.occurred_at)}`,
      `${event.fruits_collected} 🍎  ${event.coins_collected} ◉`));
    if (!data.recent_events.length) feedItem(events, 'Sin eventos todavía', 'La actividad del juego aparecerá aquí.', '—');
  } catch {
    status.className = 'server-status offline';
    status.lastChild.textContent = ' Sin datos';
    $('recent-runs').textContent = 'No se pudo consultar SQL Server.';
    $('recent-events').textContent = 'No se pudo consultar SQL Server.';
  }
}

async function loadMaps() {
  const list = $('maps-list');
  try {
    const maps = await getJson('/api/maps');
    communityMaps = Array.isArray(maps) ? maps : [];
    updateMapFilter();
    renderReplayList();
    list.replaceChildren();
    if (!communityMaps.length) {
      list.append(messageNode('Aún no hay mapas creados en Map Maker.'));
      $('map-detail').hidden = true;
      return;
    }
    communityMaps.forEach((map) => {
      const card = document.createElement('button');
      card.type = 'button';
      card.className = 'map-card';
      card.dataset.mapId = String(map.id);
      const canvas = document.createElement('canvas');
      canvas.width = 480;
      canvas.height = 270;
      canvas.setAttribute('aria-hidden', 'true');
      const body = document.createElement('span');
      body.className = 'map-card-body';
      const number = document.createElement('span');
      number.className = 'map-number';
      number.textContent = `MAPA #${String(map.id).padStart(3, '0')}`;
      const name = document.createElement('strong');
      name.textContent = map.name;
      const detail = document.createElement('span');
      detail.textContent = `${themeNames[map.data?.theme] || 'Tema libre'} · ${map.data?.fruits?.length || 0} frutas · ${map.data?.coins?.length || 0} monedas`;
      body.append(number, name, detail);
      card.append(canvas, body);
      card.addEventListener('click', () => selectCommunityMap(map.id));
      list.append(card);
      drawScene(canvas, map.data);
    });
    selectCommunityMap(communityMaps.some((map) => map.id === selectedMapId) ? selectedMapId : communityMaps[0].id);
  } catch {
    list.replaceChildren(messageNode('No se pudieron cargar los mapas.'));
  }
}

document.querySelectorAll('[data-category]').forEach((button) => {
  button.addEventListener('click', () => {
    category = button.dataset.category;
    document.querySelectorAll('[data-category]').forEach((item) => {
      const active = item === button;
      item.classList.toggle('active', active);
      item.setAttribute('aria-pressed', String(active));
    });
    $('category-note').textContent = category === 'any_percent'
      ? 'Any%: termina con menos frutas que el total de ese nivel.'
      : 'Todas las frutas: recoge cada fruta del nivel antes de llegar a la meta.';
    loadLeaderboard();
  });
});
$('level-select').addEventListener('change', loadLeaderboard);

function messageNode(message) {
  const node = document.createElement('p');
  node.className = 'empty';
  node.textContent = message;
  return node;
}

function n(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function pointOf(point) { return { x: n(point?.x), y: n(point?.y) }; }

function normalizeLayout(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const points = (key) => Array.isArray(raw[key]) ? raw[key].filter((point) => Number.isFinite(Number(point?.x)) && Number.isFinite(Number(point?.y))) : [];
  const theme = themes[raw.theme] ? raw.theme : 'ruins';
  return {
    name: raw.name || '', theme,
    backgroundTheme: (themes[raw.backgroundTheme] && raw.backgroundTheme) || backgroundThemes[raw.background] || theme,
    fruitTheme: (themes[raw.fruitTheme] && raw.fruitTheme) || fruitThemes[raw.fruit] || theme,
    width: Math.max(1, n(raw.width, 960)), height: Math.max(1, n(raw.height, 540)),
    spawn: raw.spawn || { x: 50, y: 445 }, goal: raw.goal || { x: 900, y: 445 },
    platforms: Array.isArray(raw.platforms) ? raw.platforms : [],
    fruits: points('fruits'), coins: points('coins'),
    saws: points('saws'), trampolines: points('trampolines'),
  };
}

async function loadOfficialLayouts() {
  try {
    const payload = await getJson('/official_levels.json');
    officialLayouts = Array.isArray(payload) ? payload : (payload.levels || []);
    if (!replayDetail && officialLayouts.length) {
      const preview = normalizeLayout(officialLayouts[0]);
      drawScene($('replay-canvas'), preview);
      drawOverview(preview, 0, pointOf(preview.spawn), 0);
    }
  } catch {
    officialLayouts = [];
  }
}

function cameraFor(layout, point, canvas) {
  const visible = canvas.width * layout.height / canvas.height;
  return Math.max(0, Math.min(Math.max(0, layout.width - visible), point.x - visible / 2));
}

function drawMarker(ctx, point, color, label, radius = 12) {
  const p = pointOf(point);
  ctx.fillStyle = color;
  ctx.beginPath(); ctx.arc(p.x, p.y, radius, 0, Math.PI * 2); ctx.fill();
  ctx.strokeStyle = '#14302b'; ctx.lineWidth = 3; ctx.stroke();
  ctx.fillStyle = '#14302b'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.font = 'bold 14px sans-serif'; ctx.fillText(label, p.x, p.y + 1);
}

function drawSprite(ctx, name, frameWidth, frameHeight, x, y, frame = 0, rotation = 0, flip = false) {
  const image = gameImages.get(name);
  if (!image) return false;
  const frameCount = Math.max(1, Math.floor(image.width / frameWidth));
  ctx.save();
  ctx.translate(x, y);
  if (rotation) ctx.rotate(rotation);
  if (flip) ctx.scale(-1, 1);
  ctx.drawImage(image, (frame % frameCount) * frameWidth, 0, frameWidth, frameHeight,
    -frameWidth / 2, -frameHeight / 2, frameWidth, frameHeight);
  ctx.restore();
  return true;
}

function drawScenery(ctx, layout, camera, visible) {
  const palette = themes[layout.theme];
  const tile = gameImages.get(`background-${layout.backgroundTheme}`);
  ctx.fillStyle = tile ? ctx.createPattern(tile, 'repeat') : palette.sky;
  ctx.fillRect(camera, 0, visible, layout.height);
  const first = Math.max(0, Math.floor(camera / 960));
  const last = Math.min(Math.ceil(layout.width / 960) - 1, Math.floor((camera + visible) / 960));
  for (let section = first; section <= last; section++) {
    ctx.save(); ctx.translate(section * 960, 0);
    if (layout.theme === 'forest') {
      ctx.fillStyle = 'rgba(8,46,41,.35)'; ctx.fillRect(0, 0, 960, 540);
      for (let x = -30; x < 1000; x += 115) {
        const y = 160 + (x * 7 % 65);
        ctx.fillStyle = '#315c49'; ctx.fillRect(x + 39, y, 27, 370);
        ctx.fillStyle = '#3c7052'; ctx.fillRect(x + 47, y, 7, 370);
        ctx.fillStyle = '#397951';
        for (let branch = 0; branch < 3; branch++) ctx.fillRect(x - branch * 14, y + branch * 40, 104 + branch * 28, 52);
      }
      ctx.fillStyle = '#d4e79a';
      for (let x = 45; x < 960; x += 91) ctx.fillRect(x, 180 + x * 13 % 250, 3, 3);
    } else if (layout.theme === 'desert') {
      ctx.fillStyle = 'rgba(194,92,33,.15)'; ctx.fillRect(0, 0, 960, 540);
      ctx.fillStyle = '#ffe8a2'; ctx.beginPath(); ctx.arc(770, 145, 43, 0, Math.PI * 2); ctx.fill();
      for (let x = -160; x < 1100; x += 260) {
        ctx.fillStyle = '#d6a15f'; ctx.beginPath(); ctx.moveTo(x, 485); ctx.lineTo(x + 155, 245); ctx.lineTo(x + 345, 485); ctx.fill();
        ctx.fillStyle = '#c98b54'; ctx.beginPath(); ctx.moveTo(x + 155, 245); ctx.lineTo(x + 205, 485); ctx.lineTo(x + 345, 485); ctx.fill();
      }
      ctx.fillStyle = '#8e9462';
      for (const x of [98, 605, 790]) {
        ctx.fillRect(x, 355, 12, 130); ctx.fillRect(x - 19, 385, 22, 10);
        ctx.fillRect(x - 19, 368, 9, 22); ctx.fillRect(x + 10, 402, 23, 10); ctx.fillRect(x + 25, 382, 8, 26);
      }
    } else if (layout.theme === 'snow') {
      ctx.fillStyle = 'rgba(31,51,115,.24)'; ctx.fillRect(0, 0, 960, 540);
      for (let x = -100; x < 1100; x += 230) {
        ctx.fillStyle = '#8cb4d2'; ctx.beginPath(); ctx.moveTo(x, 490); ctx.lineTo(x + 145, 155); ctx.lineTo(x + 330, 490); ctx.fill();
        ctx.fillStyle = '#d9eff4'; ctx.beginPath(); ctx.moveTo(x + 103, 252); ctx.lineTo(x + 145, 155);
        ctx.lineTo(x + 199, 252); ctx.lineTo(x + 158, 231); ctx.lineTo(x + 139, 250); ctx.lineTo(x + 123, 233); ctx.fill();
      }
      ctx.fillStyle = '#d3edf5';
      for (let index = 0; index < 65; index++) ctx.fillRect(28 + index * 137 % 905, 100 + index * 71 % 383, 3, 3);
    } else {
      for (const x of [90, 310, 580, 820]) {
        ctx.fillStyle = '#967467'; ctx.fillRect(x, 230, 40, 280);
        ctx.fillStyle = '#b08671'; ctx.fillRect(x - 8, 225, 56, 16);
        ctx.strokeStyle = '#82685e'; ctx.lineWidth = 2;
        for (let y = 260; y < 510; y += 32) { ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + 40, y); ctx.stroke(); }
      }
    }
    ctx.restore();
  }
}

function drawPlatform(ctx, platform, palette) {
  const x = n(platform.x), y = n(platform.y), w = n(platform.w), h = n(platform.h);
  if (w <= 0 || h <= 0) return;
  ctx.fillStyle = palette[0]; ctx.fillRect(x, y, w, h);
  ctx.fillStyle = palette[1]; ctx.fillRect(x, y + 8, w, Math.max(0, h - 8));
  ctx.fillStyle = palette[2]; ctx.fillRect(x, y, w, Math.min(9, h));
  ctx.fillStyle = palette[3]; ctx.fillRect(x, y + 1, w, Math.min(5, Math.max(0, h - 1)));
  ctx.strokeStyle = palette[4]; ctx.lineWidth = 2;
  for (let localY = 17; localY < h; localY += 15) {
    for (let localX = 7 + (localY % 2) * 4; localX < w; localX += 18) {
      ctx.beginPath(); ctx.moveTo(x + localX, y + localY); ctx.lineTo(x + localX + 6, y + localY + 2); ctx.stroke();
    }
    ctx.strokeStyle = palette[5]; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(x + 2, y + localY + 5); ctx.lineTo(x + w - 4, y + localY + 5); ctx.stroke();
    ctx.strokeStyle = palette[4]; ctx.lineWidth = 2;
  }
}

function drawCoin(ctx, point) {
  const p = pointOf(point);
  ctx.fillStyle = '#d67d1f'; ctx.beginPath(); ctx.arc(p.x, p.y, 14, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = '#ffcc40'; ctx.beginPath(); ctx.arc(p.x, p.y, 11, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = '#fff5a3'; ctx.fillRect(p.x - 2, p.y - 7, 5, 14);
}

function drawWorldItems(ctx, layout, elapsed, events) {
  for (const platform of layout.platforms) drawPlatform(ctx, platform, themes[layout.theme].platform);
  for (const trap of layout.trampolines) {
    const p = pointOf(trap);
    if (!drawSprite(ctx, 'trampoline', 28, 28, p.x, p.y)) drawMarker(ctx, p, '#e18b7e', 'T', 13);
  }
  for (const saw of layout.saws) {
    const p = pointOf(saw);
    if (!drawSprite(ctx, 'saw', 38, 38, p.x, p.y, 0, elapsed < 0 ? 0 : elapsed * 5.2)) drawMarker(ctx, p, '#dce6e6', '✺', 17);
  }
  const pickups = elapsed < 0 ? [] : events.filter((event) =>
    (event.event_type === 'fruit_collected' || event.event_type === 'coin_collected') && n(event.seconds) <= elapsed);
  const collected = (type, point) => pickups.some((event) => {
    if (event.event_type !== type) return false;
    const p = pointOf(event.details);
    return Math.hypot(p.x - n(point.x), p.y - n(point.y)) < 14;
  });
  for (const fruit of layout.fruits) {
    const p = pointOf(fruit), bob = elapsed < 0 ? 0 : Math.sin(elapsed * 3.5 + p.x * .02) * 3;
    ctx.globalAlpha = collected('fruit_collected', fruit) ? .23 : 1;
    if (!drawSprite(ctx, `fruit-${layout.fruitTheme}`, 32, 32, p.x, p.y + bob)) drawMarker(ctx, p, '#ff9c76', '◆', 11);
    ctx.globalAlpha = 1;
  }
  for (const coin of layout.coins) {
    ctx.globalAlpha = collected('coin_collected', coin) ? .23 : 1;
    drawCoin(ctx, coin); ctx.globalAlpha = 1;
  }
  const goal = pointOf(layout.goal), spawn = pointOf(layout.spawn);
  if (!drawSprite(ctx, 'goal', 64, 64, goal.x, goal.y)) drawMarker(ctx, goal, '#ffe07b', '⚑', 20);
  if (!drawSprite(ctx, 'start', 64, 64, spawn.x, spawn.y)) drawMarker(ctx, spawn, '#b5ead2', 'S', 20);
}

function playerFrame(samples, elapsed) {
  let previous = null, current = null;
  for (const sample of samples) {
    if (sample.seconds > elapsed) { current = sample; break; }
    previous = sample;
  }
  if (!previous || !current || current.breakBefore || current.seconds <= previous.seconds) return { key: 'player-idle', frame: Math.floor(elapsed * 5), flip: false };
  const vx = (current.x - previous.x) / (current.seconds - previous.seconds);
  const vy = (current.y - previous.y) / (current.seconds - previous.seconds);
  if (vy < -35) return { key: 'player-jump', frame: 0, flip: vx < -10 };
  if (vy > 45) return { key: 'player-fall', frame: 0, flip: vx < -10 };
  if (Math.abs(vx) > 15) return { key: 'player-run', frame: Math.floor(elapsed * 13), flip: vx < 0 };
  return { key: 'player-idle', frame: Math.floor(elapsed * 5), flip: vx < 0 };
}

// `fullMap` conserva las coordenadas originales para superponer datos analíticos.
function drawScene(canvas, rawLayout, { position = null, elapsed = -1, samples = [], events = [], fullMap = false } = {}) {
  const layout = normalizeLayout(rawLayout);
  if (!layout) return 0;
  const ctx = canvas.getContext('2d');
  const viewpoint = position || pointOf(layout.spawn);
  const camera = fullMap ? 0 : cameraFor(layout, viewpoint, canvas);
  const scale = fullMap ? canvas.width / layout.width : canvas.height / layout.height;
  const visible = fullMap ? layout.width : canvas.width / scale;
  ctx.imageSmoothingEnabled = false;
  ctx.fillStyle = themes[layout.theme].sky; ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.save(); ctx.scale(scale, scale); ctx.translate(-camera, 0);
  drawScenery(ctx, layout, camera, visible);
  drawWorldItems(ctx, layout, elapsed, events);
  if (samples.length && elapsed >= 0) {
    ctx.strokeStyle = '#fbe494'; ctx.lineWidth = 5; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.shadowColor = '#fbe494'; ctx.shadowBlur = 10; ctx.beginPath();
    let started = false;
    for (const sample of samples) {
      if (sample.seconds > elapsed) break;
      if (!started || sample.breakBefore) ctx.moveTo(sample.x, sample.y);
      else ctx.lineTo(sample.x, sample.y);
      started = true;
    }
    if (position && started) ctx.lineTo(position.x, position.y);
    ctx.stroke(); ctx.shadowBlur = 0;
    for (const event of events) {
      if (n(event.seconds) > elapsed || !['death', 'respawn'].includes(event.event_type)) continue;
      if (!Number.isFinite(Number(event.details?.x))) continue;
      const p = pointOf(event.details);
      if (event.event_type === 'death') {
        ctx.strokeStyle = '#ff8b7d'; ctx.lineWidth = 5; ctx.beginPath();
        ctx.moveTo(p.x - 12, p.y - 12); ctx.lineTo(p.x + 12, p.y + 12);
        ctx.moveTo(p.x + 12, p.y - 12); ctx.lineTo(p.x - 12, p.y + 12); ctx.stroke();
      } else drawMarker(ctx, p, '#a9e6d6', '↺', 11);
    }
    const death = [...events].reverse().find((event) => event.event_type === 'death' && n(event.seconds) <= elapsed);
    const respawn = [...events].reverse().find((event) => event.event_type === 'respawn' && n(event.seconds) <= elapsed);
    const dead = death && (!respawn || n(respawn.seconds) < n(death.seconds));
    if (position && !dead) {
      const pose = playerFrame(samples, elapsed);
      ctx.shadowColor = '#b8fff0'; ctx.shadowBlur = 10;
      if (!drawSprite(ctx, pose.key, 32, 32, position.x, position.y, pose.frame, 0, pose.flip)) drawMarker(ctx, position, '#b8fff0', 'P', 14);
      ctx.shadowBlur = 0;
    }
    if (death && elapsed - n(death.seconds) < 1.3 && dead) {
      ctx.fillStyle = '#c65953'; ctx.fillRect(camera + visible / 2 - 132, 43, 264, 50);
      ctx.fillStyle = '#fff5df'; ctx.textAlign = 'center'; ctx.font = 'bold 22px sans-serif';
      ctx.fillText('MUERTE · REGRESARÁ', camera + visible / 2, 76);
    }
  }
  ctx.restore();
  return camera;
}

function drawOverview(layout, elapsed, position, camera) {
  const canvas = $('replay-overview'), ctx = canvas.getContext('2d');
  if (!layout) { ctx.clearRect(0, 0, canvas.width, canvas.height); return; }
  const palette = themes[layout.theme];
  ctx.fillStyle = palette.sky; ctx.fillRect(0, 0, canvas.width, canvas.height);
  const sx = canvas.width / layout.width, sy = canvas.height / layout.height;
  ctx.fillStyle = palette.platform[1];
  for (const p of layout.platforms) ctx.fillRect(n(p.x) * sx, n(p.y) * sy, Math.max(1, n(p.w) * sx), Math.max(2, n(p.h) * sy));
  ctx.strokeStyle = '#ffe093'; ctx.lineWidth = 2; ctx.beginPath();
  let started = false;
  for (const sample of replaySamples) {
    if (sample.seconds > elapsed) break;
    if (!started || sample.breakBefore) ctx.moveTo(sample.x * sx, sample.y * sy);
    else ctx.lineTo(sample.x * sx, sample.y * sy);
    started = true;
  }
  ctx.stroke();
  if (position) { ctx.fillStyle = '#c4fff1'; ctx.beginPath(); ctx.arc(position.x * sx, position.y * sy, 5, 0, Math.PI * 2); ctx.fill(); }
  ctx.strokeStyle = '#fff2c3'; ctx.lineWidth = 2;
  const viewWidth = $('replay-canvas').width * layout.height / $('replay-canvas').height;
  ctx.strokeRect(camera * sx, 2, Math.min(layout.width, viewWidth) * sx, canvas.height - 4);
}

function movementSamples(detail, layout) {
  const result = [{ seconds: 0, ...pointOf(layout.spawn), breakBefore: true }];
  const events = [...(detail?.events || [])].sort((a, b) => n(a.seconds) - n(b.seconds) || n(a.id) - n(b.id));
  for (const event of events) {
    if (!['position_snapshot', 'death', 'respawn', 'level_started', 'map_test_started', 'level_completed', 'map_test_completed'].includes(event.event_type)) continue;
    let point = event.details;
    if (event.event_type === 'respawn' && !Number.isFinite(Number(point?.x))) point = layout.spawn;
    if (['level_completed', 'map_test_completed'].includes(event.event_type) && !Number.isFinite(Number(point?.x))) point = layout.goal;
    if (!Number.isFinite(Number(point?.x)) || !Number.isFinite(Number(point?.y))) continue;
    result.push({ seconds: n(event.seconds), ...pointOf(point), breakBefore: event.event_type === 'respawn' });
  }
  return result.sort((a, b) => a.seconds - b.seconds);
}

function positionAt(seconds) {
  if (!replaySamples.length) return null;
  let previous = replaySamples[0];
  for (let index = 1; index < replaySamples.length; index++) {
    const next = replaySamples[index];
    if (next.seconds > seconds) {
      if (next.breakBefore || next.seconds <= previous.seconds) return { x: previous.x, y: previous.y };
      const ratio = Math.max(0, Math.min(1, (seconds - previous.seconds) / (next.seconds - previous.seconds)));
      return { x: previous.x + (next.x - previous.x) * ratio, y: previous.y + (next.y - previous.y) * ratio };
    }
    previous = next;
  }
  return { x: previous.x, y: previous.y };
}

function eventDescription(event) {
  const details = event.details || {};
  if (event.event_type === 'death') return `Causa: ${details.cause || 'desconocida'} · vuelve al inicio sin reiniciar el reloj`;
  if (event.event_type === 'fruit_collected' || event.event_type === 'coin_collected') return `Posición ${Math.round(n(details.x))}, ${Math.round(n(details.y))}`;
  if (event.event_type === 'respawn') return 'Reaparece en el punto de inicio';
  if (event.event_type === 'level_completed' || event.event_type === 'map_test_completed') return 'Terminó el recorrido';
  if (event.event_type === 'jump') return details.jump_number === 2 ? 'Segundo salto' : 'Primer salto';
  return details.x != null && details.y != null ? `Posición ${Math.round(n(details.x))}, ${Math.round(n(details.y))}` : '';
}

function renderEventList() {
  const list = $('replay-events');
  list.replaceChildren();
  const visibleEvents = (replayDetail?.events || []).filter((event) => event.event_type !== 'position_snapshot');
  if (!visibleEvents.length) { list.append(messageNode('Sin hitos registrados.')); return; }
  for (const event of visibleEvents) {
    const li = document.createElement('li');
    li.dataset.eventId = String(event.id);
    li.className = `event-${event.event_type}`;
    const button = document.createElement('button'); button.type = 'button';
    const stamp = document.createElement('span'); stamp.className = 'event-stamp'; stamp.textContent = time(event.seconds);
    const label = document.createElement('span'); label.className = 'event-label';
    const strong = document.createElement('strong'); strong.textContent = eventLabels[event.event_type] || event.event_type.replaceAll('_', ' ');
    const small = document.createElement('small'); small.textContent = eventDescription(event);
    label.append(strong, small); button.append(stamp, label); li.append(button);
    button.addEventListener('click', () => { pauseReplay(); setReplayTime(n(event.seconds)); });
    list.append(li);
  }
}

function updateActiveEvent() {
  if (!replayDetail) return;
  const events = replayDetail.events.filter((event) => event.event_type !== 'position_snapshot' && n(event.seconds) <= currentTime);
  const activeId = events.length ? String(events[events.length - 1].id) : null;
  if (activeId === lastActiveEventId) return;
  lastActiveEventId = activeId;
  for (const node of $('replay-events').querySelectorAll('li[data-event-id]')) node.classList.toggle('current', node.dataset.eventId === activeId);
}

function renderReplay() {
  if (!replayLayout) return;
  const position = positionAt(currentTime);
  const camera = drawScene($('replay-canvas'), replayLayout, {
    position, elapsed: currentTime, samples: replaySamples, events: replayDetail?.events || [],
  });
  drawOverview(replayLayout, currentTime, position, camera);
  $('replay-clock').textContent = `${time(currentTime)} / ${time(replayDuration)}`;
  $('replay-seek').value = replayDuration ? String(Math.round(currentTime / replayDuration * 1000)) : '0';
  const events = (replayDetail?.events || []).filter((event) => n(event.seconds) <= currentTime);
  const latest = events.at(-1);
  const fruit = latest?.fruits_collected ?? 0, coin = latest?.coins_collected ?? 0;
  const deaths = events.filter((event) => event.event_type === 'death').length;
  $('replay-summary').replaceChildren();
  for (const [label, value] of [['TIEMPO', time(currentTime)], ['FRUTAS', fmt(fruit)], ['MONEDAS', fmt(coin)], ['MUERTES', fmt(deaths)]]) {
    const block = document.createElement('div');
    const caption = document.createElement('span'); caption.textContent = label;
    const number = document.createElement('strong'); number.textContent = value;
    block.append(caption, number); $('replay-summary').append(block);
  }
  updateActiveEvent();
}

function setReplayTime(seconds) {
  currentTime = Math.max(0, Math.min(replayDuration, seconds));
  renderReplay();
}

function pauseReplay() {
  playing = false;
  $('replay-play').textContent = '▶ REPRODUCIR';
  $('replay-play').setAttribute('aria-label', 'Reproducir recorrido');
}

function animationFrame(timestamp) {
  if (playing && replayDetail) {
    if (lastAnimationTime) setReplayTime(currentTime + Math.min(.1, (timestamp - lastAnimationTime) / 1000) * n($('replay-speed').value, 1));
    lastAnimationTime = timestamp;
    if (currentTime >= replayDuration) pauseReplay();
  }
  requestAnimationFrame(animationFrame);
}

function replayName(row) { return row.map_name || levelName(row.level_id); }

function filteredReplays() {
  const value = $('replay-map-filter').value;
  const player = $('replay-player-filter').value.trim().toLocaleLowerCase('es-MX');
  return replayRows.filter((row) => {
    if (player && !String(row.name || '').toLocaleLowerCase('es-MX').includes(player)) return false;
    if (value.startsWith('level:')) return Number(row.level_id) === Number(value.slice(6));
    if (value.startsWith('map:')) return Number(row.map_id) === Number(value.slice(4));
    return true;
  });
}

function renderReplayList() {
  const list = $('replay-list'); list.replaceChildren();
  const rows = filteredReplays();
  if (!rows.length) {
    list.append(messageNode(replayRows.length ? 'No hay partidas con este filtro.' : 'Todavía no hay recorridos registrados. Juega un nivel para verlos aquí.'));
    return;
  }
  for (const row of rows) {
    const button = document.createElement('button'); button.type = 'button';
    button.className = 'replay-list-item'; button.classList.toggle('selected', String(row.id) === String(selectedReplayId));
    const top = document.createElement('span'); top.className = 'replay-list-top';
    const name = document.createElement('strong'); name.textContent = row.name || 'Jugador';
    const stamp = document.createElement('small'); stamp.textContent = date(row.started_at);
    top.append(name, stamp);
    const map = document.createElement('span'); map.textContent = replayName(row);
    const bottom = document.createElement('span'); bottom.className = 'replay-list-bottom';
    const status = document.createElement('span'); status.textContent = row.completed ? 'TERMINADA' : 'EN CURSO / INCOMPLETA';
    const duration = document.createElement('b'); duration.textContent = row.seconds == null ? '—' : time(row.seconds);
    bottom.append(status, duration); button.append(top, map, bottom);
    button.addEventListener('click', () => openReplay(row.id, false));
    list.append(button);
  }
}

async function loadReplays() {
  try {
    const rows = await getJson('/api/replays');
    replayRows = Array.isArray(rows) ? rows : [];
    renderReplayList();
    if (!selectedReplayId && replayRows.length) openReplay(replayRows[0].id, false);
  } catch {
    $('replay-list').replaceChildren(messageNode('No se pudieron consultar los recorridos.'));
  }
}

async function openReplay(id, scroll = false) {
  pauseReplay();
  const serial = ++replayRequestSerial;
  selectedReplayId = String(id);
  renderReplayList();
  $('replay-stage-message').hidden = false;
  $('replay-stage-message').textContent = 'Cargando recorrido…';
  if (scroll) $('replays').scrollIntoView({ behavior: 'smooth', block: 'start' });
  try {
    const detail = await getJson(`/api/replays/${encodeURIComponent(id)}`);
    if (serial !== replayRequestSerial) return;
    const attempt = detail.attempt || {};
    const custom = attempt.mode === 'map_test' || detail.map?.data != null || attempt.map_id != null;
    const layout = custom
      ? normalizeLayout(detail.map?.data || communityMaps.find((map) => Number(map.id) === Number(attempt.map_id))?.data)
      : normalizeLayout(officialLayouts.find((level) => Number(level.level_id) === Number(attempt.level_id)) || officialLayouts[attempt.level_id - 1]);
    if (!layout) throw new Error('Mapa no disponible');
    replayDetail = detail;
    replayDetail.events = [...(detail.events || [])].sort((a, b) => n(a.seconds) - n(b.seconds) || n(a.id) - n(b.id));
    replayLayout = layout;
    replaySamples = movementSamples(replayDetail, layout);
    replayDuration = Math.max(0, n(detail.run?.seconds), n(attempt.seconds), ...replayDetail.events.map((event) => n(event.seconds)));
    currentTime = 0; lastActiveEventId = null;
    $('replay-title').textContent = `${attempt.name || 'Jugador'} · ${attempt.map_name || levelName(attempt.level_id)}`;
    $('replay-subtitle').textContent = `${date(attempt.started_at)} · ${attempt.mode === 'story' ? 'Modo historia' : custom ? 'Mapa de prueba' : 'Juego libre'} · ${replayDetail.events.length} eventos`;
    $('replay-result').textContent = detail.run?.category === 'all_fruits' ? 'TODAS LAS FRUTAS' : detail.run ? 'ANY%' : attempt.completed ? 'COMPLETADA' : 'INCOMPLETA';
    $('replay-result').classList.toggle('completed', Boolean(attempt.completed || detail.run));
    $('replay-play').disabled = replayDuration <= 0;
    $('replay-seek').disabled = replayDuration <= 0;
    $('replay-stage-message').hidden = true;
    renderEventList(); renderReplay(); renderReplayList();
  } catch {
    if (serial !== replayRequestSerial) return;
    replayDetail = null; replayLayout = null; replaySamples = [];
    $('replay-title').textContent = 'No se pudo abrir la partida';
    $('replay-subtitle').textContent = 'Comprueba que la API esté en línea y vuelve a intentarlo.';
    $('replay-stage-message').hidden = false;
    $('replay-stage-message').textContent = 'No hay mapa o recorrido disponible para esta partida.';
    $('replay-play').disabled = true; $('replay-seek').disabled = true;
    $('replay-events').replaceChildren(messageNode('Sin datos disponibles.'));
  }
}

function updateMapFilter() {
  const select = $('replay-map-filter'), selected = select.value;
  for (const option of [...select.querySelectorAll('option[data-community]')]) option.remove();
  for (const map of communityMaps) {
    const option = document.createElement('option'); option.dataset.community = 'true';
    option.value = `map:${map.id}`; option.textContent = `Comunidad · ${map.name}`; select.append(option);
  }
  select.value = [...select.options].some((option) => option.value === selected) ? selected : 'all';
}

function selectCommunityMap(id) {
  selectedMapId = Number(id);
  const map = communityMaps.find((entry) => Number(entry.id) === selectedMapId);
  if (!map) return;
  $('map-detail').hidden = false;
  $('map-detail-number').textContent = `MAPA #${String(map.id).padStart(3, '0')}`;
  $('map-detail-title').textContent = map.name;
  const data = normalizeLayout(map.data);
  $('map-detail-meta').textContent = `${themeNames[data.theme].toUpperCase()} · ${data.fruits.length} frutas · ${data.coins.length} monedas · ${data.saws.length} obstáculos`;
  drawScene($('map-detail-canvas'), data);
  for (const card of $('maps-list').querySelectorAll('.map-card')) card.classList.toggle('selected', Number(card.dataset.mapId) === selectedMapId);
}

$('replay-map-filter').addEventListener('change', renderReplayList);
$('replay-player-filter').addEventListener('input', renderReplayList);
$('replay-play').addEventListener('click', () => {
  if (!replayDetail || replayDuration <= 0) return;
  if (playing) pauseReplay();
  else {
    if (currentTime >= replayDuration) setReplayTime(0);
    playing = true; lastAnimationTime = 0;
    $('replay-play').textContent = 'Ⅱ PAUSAR';
    $('replay-play').setAttribute('aria-label', 'Pausar recorrido');
  }
});
$('replay-seek').addEventListener('input', () => { pauseReplay(); setReplayTime(n($('replay-seek').value) / 1000 * replayDuration); });
$('map-detail-replays').addEventListener('click', () => {
  if (selectedMapId == null) return;
  $('replay-map-filter').value = `map:${selectedMapId}`;
  renderReplayList();
  $('replays').scrollIntoView({ behavior: 'smooth', block: 'start' });
});
document.addEventListener('visibilitychange', () => { if (document.hidden) pauseReplay(); });
requestAnimationFrame(animationFrame);
loadGameAssets().then(() => Promise.all([loadOfficialLayouts(), loadMaps()])).then(() => loadReplays());
loadDashboard(); loadLeaderboard();
setInterval(() => { loadDashboard(); loadLeaderboard(); loadMaps(); loadReplays(); }, 30000);
