## Proyecto que combina el sistema Montevideo STM API, GTFS-STM Montevideo y OpenTripPlanner 2.7.0 para calcular ETAs según posicionamiento de líneas de buses en backend.



** router-config.json


```{
  "updaters": [
    {
      "type": "vehicle-positions",
      "url": "http://localhost:8081/gtfs-rt/vehicle-positions",
      "feedId": "STM-MVD",
      "frequency": "PT30S" 
    }
  ]
}```



** Código stm.py

```import logging
import os
import time
import requests
import threading
import zipfile
import csv
from flask import Flask, Response, request, jsonify
from cachetools import TTLCache
from google.transit import gtfs_realtime_pb2 # Importación corregida para estar disponible globalmente

# --- Configuración ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)
app = Flask(__name__)

# Credenciales y URLs
CLIENT_ID = os.getenv('STM_CLIENT_ID', '06c797f6')
CLIENT_SECRET = os.getenv('STM_CLIENT_SECRET', '2ff26f6bd1af7ab56644622099f2cd4e')
TOKEN_URL = 'https://mvdapi-auth.montevideo.gub.uy/token'
STM_BASE_URL = 'https://api.montevideo.gub.uy/api/transportepublico'
POLL_INTERVAL = 30

# --- Lógica de Mapeo de GTFS ---
GTFS_ZIP_PATH = 'gtfs.zip'
routes_map = {}  # Mapa de route_short_name -> { route_id, primer_trip_id }

def load_gtfs_mapping():
    trips_temp = {}
    try:
        with zipfile.ZipFile(GTFS_ZIP_PATH, 'r') as z:
            with z.open('trips.txt') as f:
                reader = csv.DictReader(f.read().decode('utf-8').splitlines())
                for row in reader:
                    route_id = row.get('route_id')
                    if route_id and route_id not in trips_temp:
                        trips_temp[route_id] = row['trip_id']
            
            with z.open('routes.txt') as f:
                reader = csv.DictReader(f.read().decode('utf-8').splitlines())
                for row in reader:
                    route_id = row['route_id']
                    short_name = row['route_short_name']
                    if short_name and route_id in trips_temp:
                        routes_map[short_name] = {
                            'route_id': route_id,
                            'trip_id': trips_temp[route_id]
                        }
        logger.info(f"Mapeo de GTFS cargado: {len(routes_map)} rutas encontradas.")
    except Exception as e:
        logger.error(f"FATAL: No se pudo cargar el mapeo de GTFS: {e}")

# --- Cachés Dinámicos ---
token_cache = {'token': None, 'expiry': 0}
data_cache = {'vehicle_positions': []}
active_lines = TTLCache(maxsize=1000, ttl=600)

def get_token():
    current_time = time.time()
    if token_cache['token'] and current_time < token_cache['expiry']:
        return token_cache['token']
    payload = {'grant_type': 'client_credentials'}
    auth = (CLIENT_ID, CLIENT_SECRET)
    headers = {'User-Agent': 'Mozilla/5.0'}
    try:
        response = requests.post(TOKEN_URL, data=payload, auth=auth, headers=headers)
        response.raise_for_status()
        data = response.json()
        token_cache['token'] = data['access_token']
        token_cache['expiry'] = current_time + data.get('expires_in', 3600) - 60
        return token_cache['token']
    except requests.exceptions.RequestException as e:
        logger.error(f"No se pudo obtener el token: {e}")
        return None

def fetch_stm_data():
    token = get_token()
    if not token: return

    if not active_lines:
        data_cache['vehicle_positions'] = []
        return

    headers = {'Authorization': f'Bearer {token}', 'User-Agent': 'Mozilla/5.0'}
    lines_str = ','.join(list(active_lines.keys()))
    
    # --- UNA SOLA LLAMADA A LA API ---
    positions_url = f'{STM_BASE_URL}/buses?lines={lines_str}&format=json'
    try:
        resp = requests.get(positions_url, headers=headers, timeout=15)
        resp.raise_for_status()
        data_cache['vehicle_positions'] = resp.json()
        logger.info(f"Posiciones de vehículos obtenidas para {len(active_lines)} líneas.")
    except requests.exceptions.RequestException as e:
        logger.error(f"Error al obtener posiciones: {e}")
        data_cache['vehicle_positions'] = []

def poll_stm():
    time.sleep(5)
    while True:
        try:
            fetch_stm_data()
        except Exception as e:
            logger.error(f"Error en ciclo de polling: {e}")
        time.sleep(POLL_INTERVAL)

@app.route('/register-interest', methods=['POST'])
def register_interest():
    data = request.json
    if data:
        for line in data.get('lines', []): active_lines[str(line)] = 1
        logger.info(f"Interés registrado para {len(data.get('lines', []))} líneas.")
        threading.Thread(target=fetch_stm_data).start()
    return jsonify({'status': 'ok'}), 200

# --- Ya no necesitamos el endpoint de trip-updates ---
@app.route('/gtfs-rt/trip-updates', methods=['GET'])
def trip_updates():
    return Response(b'', status=204)

@app.route('/gtfs-rt/vehicle-positions', methods=['GET'])
def vehicle_positions():
    if not data_cache['vehicle_positions']: return Response(b'', status=204)
    
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.header.gtfs_realtime_version = "2.0"
    feed.header.incrementality = gtfs_realtime_pb2.FeedHeader.FULL_DATASET
    feed.header.timestamp = int(time.time())
    
    for item in data_cache['vehicle_positions']:
        line_short_name = item.get('line')
        gtfs_ids = routes_map.get(line_short_name)
        if not gtfs_ids:
            continue

        # --- CAMBIO CLAVE: Usar 'busId' como identificador ---
        # Obtenemos el busId de la respuesta de la API.
        vehicle_id = str(item.get('busId'))
        
        # Si por alguna razón no hay busId, saltamos esta actualización para no causar errores.
        if not vehicle_id or vehicle_id == 'None':
            continue

        entity = feed.entity.add()
        # Usamos el busId como el ID único de la entidad y del vehículo.
        entity.id = vehicle_id
        vehicle_pos = entity.vehicle
        vehicle_pos.vehicle.id = vehicle_id
        
        position = vehicle_pos.position
        coords = item.get('location', {}).get('coordinates', [0, 0])
        position.longitude = coords[0]
        position.latitude = coords[1]
        
        trip = vehicle_pos.trip
        trip.route_id = gtfs_ids['route_id']
        trip.trip_id = gtfs_ids['trip_id']
    
    return Response(feed.SerializeToString(), mimetype='application/protobuf')

if __name__ != '__main__':
    load_gtfs_mapping()
    threading.Thread(target=poll_stm, daemon=True).start()```
	
	
	
	** LOGS stm proxy python:

ubuntu@stmapi:~$ sudo journalctl -u stm_proxy.service -f
-- Logs begin at Wed 2025-08-27 23:59:01 UTC. --
Sep 02 23:53:50 stmapi gunicorn[81173]: 2025-09-02 23:53:50,140 [INFO] Posiciones de vehículos obtenidas para 7 líneas.
Sep 02 23:54:21 stmapi gunicorn[81173]: 2025-09-02 23:54:21,740 [INFO] Posiciones de vehículos obtenidas para 7 líneas.
Sep 02 23:54:52 stmapi gunicorn[81173]: 2025-09-02 23:54:52,784 [INFO] Posiciones de vehículos obtenidas para 7 líneas.
Sep 02 23:55:24 stmapi gunicorn[81173]: 2025-09-02 23:55:24,012 [INFO] Posiciones de vehículos obtenidas para 7 líneas.
Sep 02 23:55:55 stmapi gunicorn[81173]: 2025-09-02 23:55:55,166 [INFO] Posiciones de vehículos obtenidas para 7 líneas.
Sep 02 23:56:26 stmapi gunicorn[81173]: 2025-09-02 23:56:26,562 [INFO] Posiciones de vehículos obtenidas para 7 líneas.
Sep 02 23:56:57 stmapi gunicorn[81173]: 2025-09-02 23:56:57,588 [INFO] Posiciones de vehículos obtenidas para 7 líneas.
Sep 02 23:57:29 stmapi gunicorn[81173]: 2025-09-02 23:57:29,634 [INFO] Posiciones de vehículos obtenidas para 7 líneas.
Sep 02 23:58:02 stmapi gunicorn[81173]: 2025-09-02 23:58:02,157 [INFO] Posiciones de vehículos obtenidas para 7 líneas.
Sep 02 23:58:33 stmapi gunicorn[81173]: 2025-09-02 23:58:33,535 [INFO] Posiciones de vehículos obtenidas para 7 líneas.
Sep 03 01:53:23 stmapi gunicorn[81173]: 2025-09-03 01:53:23,219 [INFO] Interés registrado para 4 líneas.
Sep 03 01:53:23 stmapi gunicorn[81173]: 2025-09-03 01:53:23,289 [INFO] Interés registrado para 2 líneas.
Sep 03 01:53:23 stmapi gunicorn[81173]: 2025-09-03 01:53:23,308 [INFO] Interés registrado para 3 líneas.
Sep 03 01:53:23 stmapi gunicorn[81173]: 2025-09-03 01:53:23,727 [INFO] Posiciones de vehículos obtenidas para 4 líneas.
Sep 03 01:53:23 stmapi gunicorn[81173]: 2025-09-03 01:53:23,898 [INFO] Posiciones de vehículos obtenidas para 4 líneas.
Sep 03 01:53:23 stmapi gunicorn[81173]: 2025-09-03 01:53:23,910 [INFO] Posiciones de vehículos obtenidas para 4 líneas.
Sep 03 01:53:23 stmapi gunicorn[81172]: 2025-09-03 01:53:23,971 [INFO] Interés registrado para 3 líneas.
Sep 03 01:53:24 stmapi gunicorn[81172]: 2025-09-03 01:53:24,518 [INFO] Posiciones de vehículos obtenidas para 3 líneas.
Sep 03 01:53:24 stmapi gunicorn[81173]: 2025-09-03 01:53:24,916 [INFO] Interés registrado para 2 líneas.
Sep 03 01:53:25 stmapi gunicorn[81173]: 2025-09-03 01:53:25,393 [INFO] Posiciones de vehículos obtenidas para 5 líneas.
Sep 03 01:53:43 stmapi gunicorn[81173]: 2025-09-03 01:53:43,316 [INFO] Posiciones de vehículos obtenidas para 5 líneas.
Sep 03 01:53:53 stmapi gunicorn[81172]: 2025-09-03 01:53:53,359 [INFO] Posiciones de vehículos obtenidas para 3 líneas.
Sep 03 01:54:13 stmapi gunicorn[81173]: 2025-09-03 01:54:13,727 [INFO] Posiciones de vehículos obtenidas para 5 líneas.
Sep 03 01:54:24 stmapi gunicorn[81172]: 2025-09-03 01:54:24,112 [INFO] Posiciones de vehículos obtenidas para 3 líneas.
Sep 03 01:54:44 stmapi gunicorn[81173]: 2025-09-03 01:54:44,248 [INFO] Posiciones de vehículos obtenidas para 5 líneas.
Sep 03 01:54:54 stmapi gunicorn[81172]: 2025-09-03 01:54:54,710 [INFO] Posiciones de vehículos obtenidas para 3 líneas.
Sep 03 01:55:14 stmapi gunicorn[81173]: 2025-09-03 01:55:14,671 [INFO] Posiciones de vehículos obtenidas para 5 líneas.
Sep 03 01:55:25 stmapi gunicorn[81172]: 2025-09-03 01:55:25,221 [INFO] Posiciones de vehículos obtenidas para 3 líneas.
Sep 03 01:55:45 stmapi gunicorn[81173]: 2025-09-03 01:55:45,128 [INFO] Posiciones de vehículos obtenidas para 5 líneas.
Sep 03 01:55:55 stmapi gunicorn[81172]: 2025-09-03 01:55:55,853 [INFO] Posiciones de vehículos obtenidas para 3 líneas.
Sep 03 01:56:15 stmapi gunicorn[81173]: 2025-09-03 01:56:15,676 [INFO] Posiciones de vehículos obtenidas para 5 líneas.
Sep 03 01:56:26 stmapi gunicorn[81172]: 2025-09-03 01:56:26,453 [INFO] Posiciones de vehículos obtenidas para 3 líneas.
Sep 03 01:56:46 stmapi gunicorn[81173]: 2025-09-03 01:56:46,181 [INFO] Posiciones de vehículos obtenidas para 5 líneas.
Sep 03 01:56:57 stmapi gunicorn[81172]: 2025-09-03 01:56:57,042 [INFO] Posiciones de vehículos obtenidas para 3 líneas.
Sep 03 01:57:16 stmapi gunicorn[81173]: 2025-09-03 01:57:16,667 [INFO] Posiciones de vehículos obtenidas para 5 líneas.
Sep 03 01:57:27 stmapi gunicorn[81172]: 2025-09-03 01:57:27,598 [INFO] Posiciones de vehículos obtenidas para 3 líneas.



** OTP SERVICE LOGS:



Sep 03 01:53:09 stmapi java[81062]: 01:53:09.678 INFO [graph-writer]  (ResultLogger.java:32) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] Feed did not contain any updates
Sep 03 01:53:39 stmapi java[81062]: 01:53:39.680 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 13 of 13 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:54:09 stmapi java[81062]: 01:54:09.683 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 13 of 13 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:54:39 stmapi java[81062]: 01:54:39.685 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 19 of 19 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:55:09 stmapi java[81062]: 01:55:09.687 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 19 of 19 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:55:39 stmapi java[81062]: 01:55:39.690 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 19 of 19 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:56:09 stmapi java[81062]: 01:56:09.692 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 13 of 13 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:56:39 stmapi java[81062]: 01:56:39.694 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 19 of 19 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:57:09 stmapi java[81062]: 01:57:09.696 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 19 of 19 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:57:39 stmapi java[81062]: 01:57:39.698 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 13 of 13 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:58:09 stmapi java[81062]: 01:58:09.701 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 19 of 19 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:58:39 stmapi java[81062]: 01:58:39.703 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 19 of 19 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:59:09 stmapi java[81062]: 01:59:09.706 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 19 of 19 update messages were applied successfully (success rate: 100.0%)
Sep 03 01:59:39 stmapi java[81062]: 01:59:39.708 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 18 of 18 update messages were applied successfully (success rate: 100.0%)
Sep 03 02:00:09 stmapi java[81062]: 02:00:09.710 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 12 of 12 update messages were applied successfully (success rate: 100.0%)
Sep 03 02:00:39 stmapi java[81062]: 02:00:39.712 INFO [graph-writer]  (ResultLogger.java:21) [feedId=STM-MVD, type=gtfs-rt-vehicle-positions] 18 of 18 update messages were applied successfully (success rate: 100.0%)



