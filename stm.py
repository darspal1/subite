import logging
import os
import time
import requests
import threading
import zipfile
import csv
from flask import Flask, Response, request, jsonify
from cachetools import TTLCache
from google.transit import gtfs_realtime_pb2
from datetime import datetime, timezone, timedelta
import json


# --- Configuración ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)
app = Flask(__name__)

# --- SEMÁFORO GLOBAL ---
# Creamos un Lock para evitar que múltiples hilos llamen a la API a la vez
fetch_lock = threading.Lock()

# Credenciales y URLs
CLIENT_ID = os.getenv('STM_CLIENT_ID', 'ae27362c')
CLIENT_SECRET = os.getenv('STM_CLIENT_SECRET', 'f38daf1e8c2ee131d93ee31a6b2a79ab')
TOKEN_URL = 'https://mvdapi-auth.montevideo.gub.uy/token'
STM_BASE_URL = 'https://api.montevideo.gub.uy/api/transportepublico'
POLL_INTERVAL = 30

# --- Lógica de Mapeo de GTFS ---
GTFS_ZIP_PATH = 'gtfs.zip'
routes_map = {}

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
    """
    Realiza una única llamada a la API, ahora protegida por un Lock.
    """
    # Intentamos adquirir el semáforo. Si está ocupado, salimos.
    if not fetch_lock.acquire(blocking=False):
        logger.info("Ya hay una consulta a la API en progreso. Saltando este ciclo.")
        return

    try:
        token = get_token()
        if not token: return

        if not active_lines:
            data_cache['vehicle_positions'] = []
            return

        headers = {'Authorization': f'Bearer {token}', 'User-Agent': 'Mozilla/5.0'}
        lines_str = ','.join(list(active_lines.keys()))
        
        positions_url = f'{STM_BASE_URL}/buses?lines={lines_str}&format=json'
        try:
            resp = requests.get(positions_url, headers=headers, timeout=30)
            resp.raise_for_status()
            data_cache['vehicle_positions'] = resp.json()
            logger.info(f"Posiciones de vehículos obtenidas para {len(active_lines)} líneas activas.")
        except requests.exceptions.RequestException as e:
            logger.error(f"Error al obtener posiciones de vehículos: {e}")
            data_cache['vehicle_positions'] = []
    finally:
        # ¡IMPORTANTE! Siempre liberamos el semáforo al final.
        fetch_lock.release()

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
        for line in data.get('lines', []):
            active_lines[str(line)] = True
        logger.info(f"Interés registrado para {len(data.get('lines', []))} líneas.")
        threading.Thread(target=fetch_stm_data).start()
    return jsonify({'status': 'ok'}), 200

# --- Endpoints GTFS-RT (sin cambios) ---

@app.route('/gtfs-rt/trip-updates', methods=['GET'])
def trip_updates():
    return Response(b'', status=204)

@app.route('/gtfs-rt/vehicle-positions', methods=['GET'])
def vehicle_positions():
    if not data_cache['vehicle_positions']:
        return Response(b'', status=204)
    
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.header.gtfs_realtime_version = "2.0"
    feed.header.incrementality = gtfs_realtime_pb2.FeedHeader.FULL_DATASET
    feed.header.timestamp = int(time.time())
    
    for item in data_cache['vehicle_positions']:
        line_short_name = item.get('line')
        gtfs_ids = routes_map.get(line_short_name)
        if not gtfs_ids:
            continue

        vehicle_id = str(item.get('busId'))
        if not vehicle_id or vehicle_id == 'None':
            continue

        entity = feed.entity.add()
        entity.id = vehicle_id
        
        vehicle_pos = entity.vehicle
        vehicle_pos.vehicle.id = vehicle_id
        
        position = vehicle_pos.position
        coords = item.get('location', {}).get('coordinates', [0, 0])
        position.longitude = coords[0]
        position.latitude = coords[1]
        
        if 'speed' in item and item['speed'] is not None:
            try:
                speed_kmh = float(item['speed'])
                position.speed = speed_kmh / 3.6
            except (ValueError, TypeError):
                pass
        
        api_timestamp_str = item.get('timestamp')
        if api_timestamp_str:
            try:
                if len(api_timestamp_str) > 5 and api_timestamp_str[-3] in ('+', '-'):
                    if ':' not in api_timestamp_str[-3:]:
                        api_timestamp_str += ':00'
                
                dt_object = datetime.fromisoformat(api_timestamp_str)
                vehicle_pos.timestamp = int(dt_object.timestamp())
            except (ValueError, TypeError):
                logger.warning(f"No se pudo parsear el timestamp corregido: {api_timestamp_str}")
        
        trip = vehicle_pos.trip
        trip.route_id = gtfs_ids['route_id']
        trip.trip_id = gtfs_ids['trip_id']
    
    return Response(feed.SerializeToString(), mimetype='application/protobuf')

if __name__ != '__main__':
    load_gtfs_mapping()
    threading.Thread(target=poll_stm, daemon=True).start()