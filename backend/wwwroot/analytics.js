(() => {
  'use strict';

  const byId = (id) => document.getElementById(id);
  const number = (value) => new Intl.NumberFormat('es-MX').format(Number(value) || 0);
  const duration = (seconds) => {
    if (seconds == null || !Number.isFinite(Number(seconds))) return '—';
    const ms = Math.max(0, Math.round(Number(seconds) * 1000));
    return `${String(Math.floor(ms / 60000)).padStart(2, '0')}:${String(Math.floor(ms % 60000 / 1000)).padStart(2, '0')}.${String(ms % 1000).padStart(3, '0')}`;
  };
  const dateTime = (value) => {
    const date = new Date(value);
    return value && !Number.isNaN(date.getTime())
      ? new Intl.DateTimeFormat('es-MX', { dateStyle: 'short', timeStyle: 'short' }).format(date)
      : 'Fecha no disponible';
  };
  const withText = (tag, value, className = '') => {
    const element = document.createElement(tag);
    element.textContent = value;
    if (className) element.className = className;
    return element;
  };
  const empty = (message) => withText('p', message, 'empty');
  const mapKey = (entry) => Number(entry?.level_id) > 0
    ? `level:${entry.level_id}` : entry?.map_id != null || entry?.id != null
      ? `map:${entry.map_id ?? entry.id}` : `unsaved:${entry?.map_name || ''}`;
  const mapIdentity = (entry) => entry.level_id != null
    ? `Nivel ${String(entry.level_id).padStart(2, '0')}`
    : entry.map_id != null || entry.id != null
      ? `Comunidad #${entry.map_id ?? entry.id}` : 'Mapa sin guardar';

  let maps = [];
  let selectedKey = 'level:1';
  let selectedStats = null;
  let globalStats = null;
  let attempts = [];
  let attemptTotal = 0;
  let layer = 'deaths';
  let mapRequest = 0;
  let playerRequest = 0;
  let playerTimer = null;

  async function json(url) {
    const response = await fetch(url, { cache: 'no-store' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  }

  function selectedMap() { return maps.find((entry) => entry.key === selectedKey) || null; }

  function mapLabel(key) {
    const local = maps.find((entry) => entry.key === key);
    return local?.name || key.replace('level:', 'Nivel ').replace('map:', 'Mapa #');
  }

  async function loadReferences() {
    const [officialResult, customResult] = await Promise.allSettled([
      json('/official_levels.json'), json('/api/maps'),
    ]);
    const official = officialResult.status === 'fulfilled'
      ? (Array.isArray(officialResult.value) ? officialResult.value : officialResult.value.levels || [])
      : [];
    const custom = customResult.status === 'fulfilled' && Array.isArray(customResult.value)
      ? customResult.value : [];
    maps = [
      ...official.map((layout) => ({ key: `level:${layout.level_id}`, level_id: layout.level_id,
        name: layout.name || `Nivel ${layout.level_id}`, layout })),
      ...custom.map((entry) => ({ key: `map:${entry.id}`, map_id: entry.id,
        name: entry.name || `Mapa #${entry.id}`, layout: entry.data })),
    ];
    const select = byId('analytics-map-select');
    select.replaceChildren();
    for (const entry of maps) {
      const option = withText('option', `${entry.level_id != null ? String(entry.level_id).padStart(2, '0') : '◆'} · ${entry.name}`);
      option.value = entry.key;
      select.append(option);
    }
    if (!maps.some((entry) => entry.key === selectedKey)) selectedKey = maps[0]?.key || '';
    select.value = selectedKey;
    if (globalStats) { renderMapTimes(); renderComparison(); }
    if (!maps.length) {
      byId('analytics-scope').textContent = 'No se pudieron cargar los diseños de los mapas.';
      byId('analytics-map-times').replaceChildren(empty('No hay mapas disponibles.'));
    }
  }

  function queryForMap(includePlayer = false) {
    const params = new URLSearchParams();
    if (selectedKey.startsWith('level:')) params.set('level_id', selectedKey.slice(6));
    else if (selectedKey.startsWith('map:')) params.set('map_id', selectedKey.slice(4));
    if (includePlayer && byId('analytics-player-search').value.trim())
      params.set('player_name', byId('analytics-player-search').value.trim());
    return `/api/analytics?${params}`;
  }

  async function loadGlobalStats() {
    try {
      globalStats = await json('/api/analytics');
      renderMapTimes();
      renderComparison();
    } catch {
      globalStats = null;
      byId('analytics-map-times').replaceChildren(empty('No se pudieron consultar los tiempos por mapa.'));
      byId('analytics-comparison-chart').replaceChildren(empty('No se pudo cargar la comparación entre mapas.'));
    }
  }

  function setLoading() {
    byId('analytics-scope').textContent = `Consultando ${mapLabel(selectedKey)}…`;
    for (const id of ['analytics-deaths-total', 'analytics-bounces-total', 'analytics-attempts-total', 'analytics-avg-time'])
      byId(id).textContent = '—';
    byId('analytics-hotspot-list').replaceChildren(withText('li', 'Cargando zonas…', 'empty'));
    byId('analytics-attempt-times').replaceChildren();
    const row = document.createElement('tr'), cell = withText('td', 'Cargando partidas…', 'empty');
    cell.colSpan = 5; row.append(cell); byId('analytics-attempt-times').append(row);
    drawMap();
  }

  async function loadMapStats() {
    const serial = ++mapRequest;
    ++playerRequest;
    setLoading();
    try {
      const data = await json(queryForMap());
      if (serial !== mapRequest) return;
      selectedStats = data;
      renderKpis();
      renderHotspots();
      drawMap();
      if (byId('analytics-player-search').value.trim()) loadPlayerTimes();
      else {
        attempts = Array.isArray(data.attempt_times) ? data.attempt_times : [];
        attemptTotal = Number(data.attempt_times_total ?? attempts.length);
        renderAttemptTimes();
      }
    } catch {
      if (serial !== mapRequest) return;
      selectedStats = null;
      byId('analytics-scope').textContent = `No se pudieron consultar los datos de ${mapLabel(selectedKey)}.`;
      byId('analytics-hotspot-list').replaceChildren(withText('li', 'Datos no disponibles.', 'empty'));
      byId('analytics-attempt-times').replaceChildren();
      const row = document.createElement('tr'), cell = withText('td', 'No se pudieron cargar las partidas.', 'empty');
      cell.colSpan = 5; row.append(cell); byId('analytics-attempt-times').append(row);
      drawMap();
    }
  }

  async function loadPlayerTimes() {
    if (!selectedStats) return;
    const serial = ++playerRequest;
    const key = selectedKey;
    const search = byId('analytics-player-search').value.trim();
    if (!search) {
      attempts = Array.isArray(selectedStats.attempt_times) ? selectedStats.attempt_times : [];
      attemptTotal = Number(selectedStats.attempt_times_total ?? attempts.length);
      renderAttemptTimes();
      return;
    }
    try {
      const data = await json(queryForMap(true));
      if (serial !== playerRequest || key !== selectedKey) return;
      attempts = Array.isArray(data.attempt_times) ? data.attempt_times : [];
      attemptTotal = Number(data.attempt_times_total ?? attempts.length);
      renderAttemptTimes();
    } catch {
      if (serial !== playerRequest) return;
      byId('analytics-attempt-range').textContent = 'Búsqueda no disponible';
    }
  }

  function layerRows() {
    const rows = layer === 'deaths' ? selectedStats?.death_hotspots : selectedStats?.trampolines;
    const valid = Array.isArray(rows) ? rows.filter((point) =>
      Number.isFinite(Number(point.x)) && Number.isFinite(Number(point.y)) && Number(point.count) > 0)
      : [];
    if (layer !== 'trampolines') return valid.sort((a, b) => Number(b.count) - Number(a.count));
    const layout = selectedMap()?.layout;
    const trampolines = Array.isArray(layout?.trampolines) ? layout.trampolines : [];
    if (!trampolines.length) return valid.sort((a, b) => Number(b.count) - Number(a.count));
    const centers = trampolines.map((entry) => ({
      x: Number(entry.x ?? entry[0]), y: Number(entry.y ?? entry[1]),
    })).filter((point) => Number.isFinite(point.x) && Number.isFinite(point.y));
    const groups = new Map();
    for (const point of valid) {
      const nearest = centers.map((center, index) => ({ center, index,
        distance: (center.x - point.x) ** 2 + (center.y - point.y) ** 2 }))
        .sort((a, b) => a.distance - b.distance)[0];
      const matched = nearest && nearest.distance <= 90 ** 2;
      const key = matched ? `trampoline:${nearest.index}` : `zone:${point.x}:${point.y}`;
      const existing = groups.get(key);
      if (existing) existing.count += Number(point.count);
      else groups.set(key, { ...point, x: matched ? nearest.center.x : Number(point.x),
        y: matched ? nearest.center.y : Number(point.y), count: Number(point.count),
        trampoline: Boolean(matched) });
    }
    return [...groups.values()].sort((a, b) => Number(b.count) - Number(a.count));
  }

  function renderKpis() {
    if (!selectedStats) return;
    const deaths = (selectedStats.map_event_totals || []).reduce((sum, row) => sum + Number(row.deaths || 0), 0);
    const bounces = (selectedStats.map_event_totals || []).reduce((sum, row) => sum + Number(row.bounces || 0), 0);
    const map = (selectedStats.map_times || []).find((row) => mapKey(row) === selectedKey);
    byId('analytics-deaths-total').textContent = number(deaths);
    byId('analytics-bounces-total').textContent = number(bounces);
    byId('analytics-attempts-total').textContent = number(selectedStats.attempt_times_total ?? selectedStats.attempt_times?.length);
    byId('analytics-avg-time').textContent = map?.completed_count > 0 ? duration(map.avg_seconds) : '—';
    byId('analytics-scope').textContent = `${mapLabel(selectedKey)} · ${map?.completed_count || 0} partida${map?.completed_count === 1 ? '' : 's'} terminada${map?.completed_count === 1 ? '' : 's'}`;
  }

  function renderHotspots() {
    const list = byId('analytics-hotspot-list');
    list.replaceChildren();
    document.querySelector('.analytics-hotspot-panel').dataset.activeLayer = layer;
    byId('analytics-hotspot-title').textContent = layer === 'deaths' ? 'Muertes por zona' : 'Trampolines más usados';
    byId('analytics-map-note').textContent = layer === 'deaths'
      ? 'Cada círculo representa una zona aproximada de 64 píxeles; su tamaño y número indican cuántos eventos ocurrieron allí. Las caídas fuera del mapa aparecen en el borde inferior.'
      : 'Los rebotes se agrupan en el trampolín más cercano del mapa. Los eventos antiguos que no se pueden asociar permanecen como zonas aproximadas de 64 píxeles.';
    const rows = layerRows();
    if (!rows.length) {
      list.append(withText('li', layer === 'deaths'
        ? 'Aún no hay muertes con coordenadas en este mapa.'
        : 'Aún no hay rebotes con coordenadas en este mapa.', 'empty'));
      return;
    }
    rows.slice(0, 8).forEach((point, index) => {
      const item = document.createElement('li');
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'analytics-hotspot-button';
      const place = layer === 'trampolines' && point.trampoline ? 'trampolín' : 'zona';
      button.setAttribute('aria-label', `Ir a ${place} ${index + 1}, coordenadas ${Math.round(point.x)}, ${Math.round(point.y)}`);
      const description = document.createElement('span'); description.className = 'analytics-hotspot-description';
      description.append(withText('strong', `${place === 'trampolín' ? 'Trampolín' : 'Zona'} ${index + 1}`),
        withText('small', `X ${Math.round(point.x)} · Y ${Math.round(point.y)}`));
      button.append(withText('span', String(index + 1).padStart(2, '0'), 'analytics-hotspot-rank'),
        description, withText('b', number(point.count), 'analytics-hotspot-count'));
      button.addEventListener('click', () => {
        const map = selectedMap(); if (!map) return;
        const canvas = byId('analytics-map-canvas'), scroll = byId('analytics-map-scroll');
        const px = Number(point.x) * canvas.width / Number(map.layout.width || 1);
        scroll.scrollTo({ left: Math.max(0, px - scroll.clientWidth / 2), behavior: 'smooth' });
      });
      item.append(button); list.append(item);
    });
  }

  function drawMap() {
    const canvas = byId('analytics-map-canvas'), map = selectedMap();
    if (!map?.layout) {
      canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
      return;
    }
    const layout = typeof normalizeLayout === 'function' ? normalizeLayout(map.layout) : map.layout;
    if (!layout) return;
    const worldWidth = Math.max(1, Number(layout.width) || 960);
    const worldHeight = Math.max(1, Number(layout.height) || 540);
    const width = Math.round(Math.min(1600, Math.max(960, worldWidth / 2)));
    const height = Math.max(1, Math.round(width * worldHeight / worldWidth));
    if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
    canvas.style.width = `${width}px`;
    if (typeof drawScene === 'function') drawScene(canvas, layout, { fullMap: true });
    else {
      const context = canvas.getContext('2d');
      context.fillStyle = '#315d54'; context.fillRect(0, 0, width, height);
    }
    canvas.setAttribute('aria-label', `${map.name}: ${layer === 'deaths' ? 'zonas de muertes' : 'zonas de rebote'}`);
    const ctx = canvas.getContext('2d');
    const scale = width / worldWidth;
    const color = layer === 'deaths' ? [255, 120, 99] : [117, 242, 211];
    for (const point of layerRows()) {
      const x = Math.max(22, Math.min(width - 22, Number(point.x) * scale));
      const outsideBottom = Number(point.y) > worldHeight;
      const y = Math.max(22, Math.min(height - 22, Number(point.y) * scale));
      const count = Number(point.count);
      const radius = Math.min(43, 12 + Math.sqrt(count) * 6);
      const glow = ctx.createRadialGradient(x, y, 0, x, y, radius * 1.8);
      glow.addColorStop(0, `rgba(${color.join(',')},.83)`);
      glow.addColorStop(.4, `rgba(${color.join(',')},.40)`);
      glow.addColorStop(1, `rgba(${color.join(',')},0)`);
      ctx.fillStyle = glow; ctx.beginPath(); ctx.arc(x, y, radius * 1.8, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = `rgb(${color.join(',')})`;
      ctx.strokeStyle = '#172d29'; ctx.lineWidth = 2.5;
      ctx.beginPath(); ctx.arc(x, y, radius, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
      ctx.fillStyle = '#14302b'; ctx.font = '700 13px system-ui, sans-serif';
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(number(count), x, y + 1);
      if (outsideBottom) {
        ctx.fillStyle = '#fff2cf'; ctx.font = '700 13px system-ui, sans-serif';
        ctx.fillText('↓', x, Math.min(height - 4, y + radius + 9));
      }
    }
  }

  function renderMapTimes() {
    const container = byId('analytics-map-times');
    container.replaceChildren();
    if (!globalStats) return;
    const rows = Array.isArray(globalStats.map_times) ? globalStats.map_times : [];
    const all = [...maps];
    for (const row of rows) if (!all.some((item) => item.key === mapKey(row)))
      all.push({ key: mapKey(row), name: row.map_name || mapIdentity(row), layout: null });
    if (!all.length) { container.append(empty('Aún no hay mapas disponibles.')); return; }
    const byKey = new Map(rows.map((row) => [mapKey(row), row]));
    const maxAverage = Math.max(1, ...rows.map((row) => Number(row.avg_seconds) || 0));
    for (const map of all) {
      const row = byKey.get(map.key);
      const completed = Number(row?.completed_count) || 0;
      const button = document.createElement('button'); button.type = 'button';
      button.className = `analytics-map-time-row${map.key === selectedKey ? ' selected' : ''}`;
      button.disabled = !maps.some((entry) => entry.key === map.key);
      const heading = document.createElement('span'); heading.className = 'analytics-map-time-heading';
      heading.append(withText('strong', map.name), withText('span', `${number(completed)} ${completed === 1 ? 'terminada' : 'terminadas'}`));
      const track = document.createElement('span'); track.className = 'analytics-map-time-track';
      const fill = document.createElement('span');
      fill.style.width = completed ? `${Math.max(3, Math.min(100, Number(row.avg_seconds) / maxAverage * 100))}%` : '0';
      track.append(fill);
      const values = document.createElement('span'); values.className = 'analytics-map-time-values';
      values.append(withText('span', `PROMEDIO ${completed ? duration(row.avg_seconds) : '—'}`),
        withText('b', `MEJOR ${completed ? duration(row.best_seconds) : '—'}`));
      button.append(heading, track, values);
      button.addEventListener('click', () => { byId('analytics-map-select').value = map.key; changeMap(map.key); });
      container.append(button);
    }
  }

  function renderComparison() {
    const container = byId('analytics-comparison-chart');
    container.replaceChildren();
    if (!globalStats) return;
    const metric = byId('analytics-chart-metric').value;
    const isTime = metric === 'average' || metric === 'best';
    const notes = {
      average: 'Tiempo promedio de las partidas terminadas. Cada barra indica cuántas partidas forman ese promedio.',
      best: 'La mejor marca registrada en cada mapa. Una sola partida puede fijar este valor.',
      completed: 'Cantidad de partidas que llegaron a la meta en cada mapa.',
      deaths: 'Número total de eventos de muerte registrados por mapa. Incluye repeticiones de un mismo jugador.',
      bounces: 'Número total de usos de trampolines registrados por mapa. Incluye repeticiones de un mismo jugador.',
    };
    byId('analytics-chart-description').textContent = notes[metric];
    byId('analytics-comparison-footnote').textContent = isTime
      ? 'Selecciona una barra para explorar ese mapa. Un mayor tiempo puede indicar un nivel más largo o más difícil; compara también muertes y tamaño de muestra.'
      : metric === 'completed'
        ? 'Selecciona una barra para explorar ese mapa. La cantidad de llegadas depende de cuántas personas jugaron; no mide por sí sola la facilidad.'
        : 'Selecciona una barra para explorar ese mapa. Los eventos pueden repetirse en una misma partida; compáralos con las partidas y los tiempos.';
    const timeRows = Array.isArray(globalStats.map_times) ? globalStats.map_times : [];
    const eventRows = Array.isArray(globalStats.map_event_totals) ? globalStats.map_event_totals : [];
    const timeByKey = new Map(timeRows.map((row) => [mapKey(row), row]));
    const eventByKey = new Map(eventRows.map((row) => [mapKey(row), row]));
    const all = [...maps];
    if (!all.length) { container.append(empty('Aún no hay mapas para comparar.')); return; }

    const data = all.map((map) => {
      const time = timeByKey.get(map.key);
      const event = eventByKey.get(map.key);
      const completed = Number(time?.completed_count) || 0;
      const value = metric === 'average' ? (completed ? Number(time.avg_seconds) : null)
        : metric === 'best' ? (completed ? Number(time.best_seconds) : null)
        : metric === 'completed' ? completed
        : metric === 'deaths' ? Number(event?.deaths) || 0
        : Number(event?.bounces) || 0;
      return { map, value, completed };
    });
    const max = Math.max(1, ...data.map((item) => item.value ?? 0));
    const axis = document.createElement('div'); axis.className = 'analytics-comparison-axis';
    axis.append(withText('span', '0'), withText('span', isTime ? duration(max) : number(max)));
    container.append(axis);
    for (const item of data) {
      const button = document.createElement('button'); button.type = 'button';
      button.className = `analytics-comparison-row${item.map.key === selectedKey ? ' selected' : ''}`;
      button.disabled = !maps.some((entry) => entry.key === item.map.key);
      button.setAttribute('aria-pressed', String(item.map.key === selectedKey));
      button.setAttribute('aria-label', `${item.map.name}: ${item.value == null ? 'sin partidas terminadas' : isTime ? duration(item.value) : number(item.value)}${isTime ? `, ${number(item.completed)} ${item.completed === 1 ? 'partida terminada' : 'partidas terminadas'}` : ''}. Seleccionar mapa.`);
      const label = document.createElement('span'); label.className = 'analytics-comparison-label';
      label.append(withText('strong', item.map.name),
        withText('small', `${number(item.completed)} ${item.completed === 1 ? 'partida terminada' : 'partidas terminadas'}`));
      const track = document.createElement('span'); track.className = 'analytics-comparison-track';
      const fill = document.createElement('span'); fill.className = 'analytics-comparison-fill';
      fill.style.width = item.value == null || item.value <= 0
        ? '0%' : `${Math.max(2, item.value / max * 100)}%`;
      track.append(fill);
      const value = withText('span', item.value == null ? 'SIN DATOS'
        : isTime ? duration(item.value) : number(item.value), 'analytics-comparison-value');
      button.append(label, track, value);
      button.addEventListener('click', () => changeMap(item.map.key));
      container.append(button);
    }
  }

  function renderAttemptTimes() {
    const body = byId('analytics-attempt-times');
    body.replaceChildren();
    byId('analytics-attempt-range').textContent = `Mostrando ${number(attempts.length)} de ${number(attemptTotal)} registros`;
    if (!attempts.length) {
      const row = document.createElement('tr'), cell = withText('td',
        byId('analytics-player-search').value.trim()
          ? 'No hay partidas de ese jugador en este mapa.'
          : 'Aún no hay partidas registradas en este mapa.', 'empty');
      cell.colSpan = 5; row.append(cell); body.append(row); return;
    }
    const maxTime = Math.max(1, ...attempts.map((run) => Number(run.seconds) || 0));
    for (const run of attempts) {
      const row = document.createElement('tr');
      const player = document.createElement('td');
      player.append(withText('strong', run.name || 'Jugador'),
        withText('small', `${dateTime(run.started_at || run.ended_at)}${run.mode === 'historical' ? ' · registro anterior' : ''}`));
      const elapsed = document.createElement('td');
      elapsed.append(withText('span', duration(run.seconds)));
      if (run.seconds != null) {
        const bar = document.createElement('span'); bar.className = 'analytics-time-bar';
        bar.style.width = `${Math.max(3, Number(run.seconds) / maxTime * 100)}%`;
        elapsed.append(bar);
      }
      const result = document.createElement('td');
      result.append(withText('span', run.completed ? 'TERMINÓ' : 'SIN META',
        `analytics-result-badge${run.completed ? '' : ' incomplete'}`));
      const events = withText('td', run.death_count == null || run.trampoline_count == null
        ? 'Sin detalle' : `${number(run.death_count)} ✕   ${number(run.trampoline_count)} ↥`);
      events.title = run.death_count == null || run.trampoline_count == null
        ? 'No se pueden asociar eventos a esta partida histórica.'
        : `${number(run.death_count)} muertes, ${number(run.trampoline_count)} rebotes`;
      const route = document.createElement('td');
      if (run.attempt_id) {
        const link = withText('button', 'VER ↗'); link.type = 'button';
        link.addEventListener('click', () => {
          if (typeof openReplay === 'function') openReplay(run.attempt_id, true);
          else location.hash = '#replays';
        });
        route.append(link);
      } else route.textContent = 'Histórica';
      row.append(player, elapsed, result, events, route); body.append(row);
    }
  }

  function changeMap(key) {
    if (!maps.some((entry) => entry.key === key)) return;
    selectedKey = key;
    byId('analytics-map-select').value = key;
    selectedStats = null;
    renderMapTimes();
    renderComparison();
    loadMapStats();
  }

  byId('analytics-map-select').addEventListener('change', (event) => changeMap(event.target.value));
  byId('analytics-chart-metric').addEventListener('change', renderComparison);
  byId('analytics-refresh').addEventListener('click', () => {
    Promise.all([loadReferences(), loadGlobalStats()]).then(() => loadMapStats());
  });
  byId('analytics-player-search').addEventListener('input', () => {
    clearTimeout(playerTimer);
    playerTimer = setTimeout(loadPlayerTimes, 250);
  });
  document.querySelectorAll('[data-analytics-layer]').forEach((button) => {
    button.addEventListener('click', () => {
      layer = button.dataset.analyticsLayer;
      document.querySelectorAll('[data-analytics-layer]').forEach((option) => {
        const active = option === button;
        option.classList.toggle('active', active);
        option.setAttribute('aria-pressed', String(active));
      });
      renderHotspots(); drawMap();
    });
  });
  window.addEventListener('game-assets-loaded', drawMap);

  loadReferences().then(() => Promise.all([loadGlobalStats(), loadMapStats()]));
  setInterval(() => {
    if (!document.hidden) Promise.all([loadGlobalStats(), loadMapStats()]);
  }, 60000);
})();
