import 'dart:convert';
import 'package:http/http.dart' as http;

class NearbyStopsService {
  static const String _baseUrl = 'http://api.stmapi.xo.je';
  static const String _endpoint = '/otp/routers/default/index/graphql';

  // Obtener paradas cercanas a una ubicación
  static Future<List<NearbyStop>> getNearbyStops({
    required double lat,
    required double lon,
    int maxResults = 10,
    int maxDistance = 500, // metros
  }) async {
    try {
      final String graphqlQuery = '''
      {
        nearest(
          lat: $lat
          lon: $lon
          maxResults: $maxResults
          maxDistance: $maxDistance
          filterByPlaceTypes: [STOP]
        ) {
          edges {
            node {
              place {
                ... on Stop {
                  gtfsId
                  name
                  code
                  lat
                  lon
                  routes {
                    shortName
                    longName
                    color
                    textColor
                    agency {
                      name
                    }
                  }
                }
              }
              distance
            }
          }
        }
      }
      ''';

      final requestBody = {'query': graphqlQuery};

      final response = await http.post(
        Uri.parse('$_baseUrl$_endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseNearbyStopsResponse(data);
      } else {
        throw Exception('Error al obtener paradas cercanas: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error al conectar con el servicio de paradas: $e');
    }
  }

  static List<NearbyStop> _parseNearbyStopsResponse(Map<String, dynamic> data) {
    final List<NearbyStop> nearbyStops = [];
    
    try {
      if (data['data']?['nearest']?['edges'] != null) {
        final edges = data['data']['nearest']['edges'] as List;
        
        for (final edge in edges) {
          final node = edge['node'];
          final place = node?['place'];
          final distance = (node?['distance'] as num?)?.toDouble() ?? 0.0;
          
          if (place != null) {
            final routes = <RouteAtStop>[];
            
            if (place['routes'] != null) {
              final routesList = place['routes'] as List;
              for (final route in routesList) {
                routes.add(RouteAtStop(
                  shortName: route['shortName'] as String?,
                  longName: route['longName'] as String?,
                  color: route['color'] as String?,
                  textColor: route['textColor'] as String?,
                  agencyName: route['agency']?['name'] as String?,
                ));
              }
            }
            
            nearbyStops.add(NearbyStop(
              gtfsId: place['gtfsId'] as String? ?? '',
              name: place['name'] as String? ?? 'Parada sin nombre',
              code: place['code'] as String?,
              lat: (place['lat'] as num?)?.toDouble() ?? 0.0,
              lon: (place['lon'] as num?)?.toDouble() ?? 0.0,
              distance: distance,
              routes: routes,
            ));
          }
        }
      }
    } catch (e) {
      // Error silencioso
    }
    
    // Ordenar por distancia
    nearbyStops.sort((a, b) => a.distance.compareTo(b.distance));
    
    return nearbyStops;
  }
}

class NearbyStop {
  final String gtfsId;
  final String name;
  final String? code;
  final double lat;
  final double lon;
  final double distance; // en metros
  final List<RouteAtStop> routes;

  NearbyStop({
    required this.gtfsId,
    required this.name,
    this.code,
    required this.lat,
    required this.lon,
    required this.distance,
    required this.routes,
  });

  // Distancia en formato legible
  String get distanceText {
    if (distance < 1000) {
      return '${distance.round()}m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)}km';
    }
  }
  
  // Tiempo estimado caminando (asumiendo 1.4 m/s)
  int get walkingTimeMinutes => (distance / 1.4 / 60).round();
  
  // Texto del tiempo caminando
  String get walkingTimeText {
    final minutes = walkingTimeMinutes;
    if (minutes < 1) return 'Menos de 1 min';
    return '${minutes} min caminando';
  }
  
  // Lista de líneas que pasan por esta parada
  String get routesText {
    if (routes.isEmpty) return 'Sin líneas';
    return routes.map((r) => r.displayName).join(', ');
  }
}

class RouteAtStop {
  final String? shortName;
  final String? longName;
  final String? color;
  final String? textColor;
  final String? agencyName;

  RouteAtStop({
    this.shortName,
    this.longName,
    this.color,
    this.textColor,
    this.agencyName,
  });

  String get displayName => shortName ?? longName ?? 'Línea';
}