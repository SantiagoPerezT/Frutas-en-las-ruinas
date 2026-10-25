# API y panel de datos (SQL Server)

El juego envía sus datos a esta API local. La API guarda sesiones, eventos, tiempos terminados y mapas en la base `DB` de SQL Server. El navegador muestra el panel en `http://127.0.0.1:8000/`.

## Arranque

1. En SQL Server crea una base de datos llamada `DB` si aún no existe. La cuenta SQL necesita permisos de lectura, escritura y creación de tablas e índices en esa base (`db_datareader`, `db_datawriter`, `db_ddladmin` para este proyecto local).
2. En PowerShell, desde la raíz del juego, ejecuta `./run_backend.ps1`. El script usa la instancia local `lpc:.`, la base `DB` y el usuario `Codex`, y solicita la contraseña sin guardarla en archivos.
3. Si prefieres iniciar la API manualmente, define `SQL_USER` y `SQL_PASSWORD` como variables de entorno y ejecuta `dotnet run --project .\backend\Platformer.Api.csproj --no-launch-profile`. También puedes definir `SQL_SERVER` (por defecto `lpc:.`) y `SQL_DATABASE` (por defecto `DB`).
4. Abre `http://127.0.0.1:8000/`. `http://127.0.0.1:8000/api/health` confirma la conexión a SQL Server.

La primera vez, el servidor aplica `schema.sql` automáticamente. También puede aplicarse manualmente desde SQL Server Management Studio. El script es idempotente y conserva las filas existentes. La migración del recorrido añade `LevelAttempts` y referencias opcionales en eventos/tiempos; los registros anteriores siguen visibles, aunque no tienen animación vinculada. La API solo escucha en `127.0.0.1`; el juego y el navegador deben ejecutarse en la misma computadora. Para vaciar solo los récords, ejecuta manualmente `reset_leaderboard.sql` en la base `DB`; no hay botón de reinicio en el juego.

## Contrato JSON

Las rutas comienzan en `http://127.0.0.1:8000/api`. Los identificadores `client_*_id` son UUID generados por el juego para que un reintento de envío no cree filas duplicadas.

| Método y ruta | Cuerpo / respuesta principal |
| --- | --- |
| `POST /sessions` | `{ "player_name": "Ana", "client_session_id": "UUID" }` → `{ "id": "UUID", "player_name": "Ana" }` |
| `POST /attempts` | `{ "client_attempt_id": "UUID", "session_id": "UUID", "level_id": 1, "map_id": null, "mode": "story", "map_name": null, "map_data": null }` → `{ "id": "UUID", "started_at": "fecha UTC" }`. Para `map_test`, `level_id` es `null` y `map_data` contiene una copia del mapa. |
| `POST /events` | `{ "client_event_id": "UUID", "session_id": "UUID", "attempt_id": "UUID", "level_id": 1, "event_type": "fruit_collected", "elapsed_seconds": 12.345, "fruits_collected": 2, "coins_collected": 1, "details": {"x": 120, "y": 300} }` → `{ "id": 1 }` |
| `POST /runs` | `{ "client_run_id": "UUID", "session_id": "UUID", "attempt_id": "UUID", "level_id": 1, "elapsed_seconds": 42.1, "fruits_collected": 3, "fruits_total": 13, "coins_collected": 2 }` → `{ "id": 1, "category": "any_percent" }` |
| `GET /leaderboards?level_id=1&category=any_percent` | Lista de los diez tiempos menores; cada elemento incluye `name`, `seconds`, `fruits_collected`, `coins_collected`, `run_id` y `attempt_id`. `attempt_id` es `null` para registros históricos. |
| `GET /replays?level_id=1` o `GET /replays?map_id=2` | Hasta 100 intentos recientes con jugador, estado, tiempo, categoría, conteos y `id` UUID. Sin filtros, lista todos los niveles y mapas. |
| `GET /replays/{UUID}` | `{ "attempt": {...}, "run": {...} | null, "events": [...], "map": {...} | null }`. Los eventos van ordenados por tiempo de juego y contienen `seconds`, `event_type` y `details`. `map.data` es la copia de un mapa comunitario tal como se jugó. |
| `GET /analytics?level_id=1` o `GET /analytics?map_id=2` | `{ "death_hotspots": [...], "trampolines": [...], "attempt_times": [...], "attempt_times_total": 0, "map_times": [...], "map_event_totals": [...] }`. Sin filtro, incluye niveles y mapas. `player_name=Ana` busca coincidencias parciales de nombre solo en `attempt_times`. |
| `GET /dashboard` | Conteos generales y listas `recent_runs` y `recent_events` para el panel web. |
| `GET /maps` y `GET /maps/{id}` | Lista o mapa `{ "id": 1, "name": "...", "data": { ... } }`. |
| `POST /maps` y `PUT /maps/{id}` | `{ "name": "Mi mapa", "data": { ... } }` → mapa guardado. |

`level_id` es 1, 2, 3 o 4 para los niveles oficiales. En eventos de prueba de un mapa creado, puede ser `null`; `details` puede incluir `map_id` y `map_name`. Estas pruebas no entran en los récords oficiales. El servidor clasifica una partida terminada como `all_fruits` cuando `fruits_collected == fruits_total`; cualquier cantidad menor se clasifica como `any_percent`.

Las tablas guardan **todas** las llegadas; la consulta del leaderboard devuelve los diez tiempos más rápidos de cada nivel y categoría. Cada carga o reinicio de nivel crea otro intento. Morir y reaparecer mantiene el mismo intento y el reloj continúa: los eventos `death` y `respawn` muestran ambos momentos dentro de la animación. Los eventos `position_snapshot` registran aproximadamente cinco posiciones por segundo; no se registran movimientos cuadro por cuadro. Al completar un nivel oficial, el resultado del leaderboard queda vinculado al mismo intento. Una prueba de mapa comunitario puede terminar con `map_test_completed` sin entrar en los récords oficiales. Los tiempos se almacenan en milisegundos y las fechas en UTC. El plano de los cuatro niveles oficiales está en `wwwroot/official_levels.json`.

## Análisis de recorridos y tiempos

`GET /analytics` devuelve las zonas con más eventos `death` y `trampoline_bounce`. Cada punto tiene `level_id` o `map_id`, `map_name` cuando procede, coordenadas `x`,`y` y `count`. **El conteo es de eventos, no de jugadores distintos.** Las muertes se agrupan en celdas de 64 píxeles. Los nuevos rebotes conservan el centro exacto del trampolín; los registros antiguos, que solo tenían la posición del jugador, se agrupan en celdas de 64 píxeles y la web los asocia al trampolín más cercano cuando es posible. Cada lista espacial está limitada a las 300 zonas más frecuentes. Se incluyen eventos antiguos si contienen coordenadas y permiten asociar un nivel o mapa.

`attempt_times` contiene los 200 intentos más recientes según su fecha de inicio. Para cada uno entrega jugador, nivel o mapa, duración en segundos, fecha, `completed`, categoría y coleccionables, además de los conteos de muertes y rebotes vinculados al intento. Un intento no terminado muestra el último tiempo registrado, pero no cuenta en las estadísticas de finalización. `attempt_times_total` indica cuántas filas coinciden con los filtros. Los tiempos oficiales anteriores al registro de recorridos también aparecen como `mode: "historical"`, `attempt_id: null`, `started_at: null` y `completed: true`; sus muertes y rebotes son `null` porque no se pueden asociar con certeza.

`map_times` agrega **solo partidas terminadas** por nivel oficial o mapa personalizado: `completed_count`, `avg_seconds`, `best_seconds` y `total_seconds`. En niveles oficiales usa `LevelRuns`, una fila por llegada, aunque exista además el evento `level_completed`. En pruebas de mapas usa el último evento `map_test_completed` de cada intento, pues estas pruebas no generan un `LevelRun`. Las pruebas antiguas sin identificador de intento se cuentan por evento de finalización. Las estadísticas de muerte y rebote se filtran por nivel o mapa, pero `player_name` solo afecta la lista de partidas.

`map_event_totals` reúne `deaths` y `bounces` por mapa sin el límite de 300 zonas del visor espacial. La gráfica web permite alternar entre tiempo promedio, mejor tiempo, partidas terminadas, muertes y rebotes, y elegir un mapa desde cualquiera de sus barras. Los tiempos se calculan solo de partidas terminadas; cada barra muestra su tamaño de muestra.
