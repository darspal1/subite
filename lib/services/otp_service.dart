import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'realtime_interest_service.dart';

class OTPService {
  static const String _baseUrl = 'https://stmapi.ddns.net';
  static const String _endpoint = '/otp/gtfs/v1';
  
  static Future<List<OTPRoute>> planRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    DateTime? dateTime,
    int numItineraries = 6, // Más rutas
    int maxWalkDistance = 1000, // Distancia máxima caminando
    bool registerRealtimeInterest = true, // Registrar interés para datos en tiempo real
  }) async {
    try {
      final DateTime planDateTime = dateTime ?? DateTime.now();
      
      // Debug logs removidos para producción
      
      final String isoDateTime = '${planDateTime.year}-${planDateTime.month.toString().padLeft(2, '0')}-${planDateTime.day.toString().padLeft(2, '0')}T${planDateTime.hour.toString().padLeft(2, '0')}:${planDateTime.minute.toString().padLeft(2, '0')}:00-03:00';
      
      final String graphqlQuery = '''
      {
        planConnection(
          origin: {
            location: { coordinate: { latitude: $fromLat, longitude: $fromLon } }
          }
          destination: {
            location: { coordinate: { latitude: $toLat, longitude: $toLon } }
          }
          dateTime: { earliestDeparture: "$isoDateTime" }
          modes: {
            direct: [WALK]
            transit: { transit: [{ mode: BUS }] }
			
          }
          first: $numItineraries
        ) {
          edges {
            node {
              start
              end
              duration
              walkTime
              legs {
                mode
                from {
                  name
                  lat
                  lon
                  stop {
                    gtfsId
                    code
                    name
                  }
                  departure {
                    scheduledTime
                    estimated { time delay }
                  }
                }
                to {
                  name
                  lat
                  lon
                  stop {
                    gtfsId
                    code
                    name
                  }
                  arrival {
                    scheduledTime
                    estimated { time delay }
                  }
                }
                duration
                distance
                legGeometry {
                  points
                }
                steps {
                  distance
                  relativeDirection
                  streetName
                  absoluteDirection
                }
                route {
                  shortName
                  longName
                  color
                  textColor
                  agency {
                    name
                  }
                }
                trip {
                  tripHeadsign
                  route {
                    shortName
                    longName
                    color
                    textColor
                    agency {
                      name
                    }
                  }
                  pattern {
                    stops {
                      gtfsId
                      name
                      code
                      lat
                      lon
                    }
                  }
                }
              }
            }
          }
        }
      }
      ''';

      final requestBody = {
        'query': graphqlQuery,
      };


      
      final response = await http.post(
        Uri.parse('$_baseUrl$_endpoint'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      print('OTP Response Status: ${response.statusCode}');
      print('OTP Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = _parseGraphQLResponse(data);
        print('Parsed routes count: ${routes.length}');
        for (int i = 0; i < routes.length; i++) {
          final route = routes[i];
          print('Route $i: ${route.legs.length} legs');
          for (int j = 0; j < route.legs.length; j++) {
            final leg = route.legs[j];
            print('  Leg $j: mode=${leg.mode}, routeShortName=${leg.routeShortName}');
          }
        }

        // Registrar interés para datos en tiempo real
        if (registerRealtimeInterest && routes.isNotEmpty) {
          _registerInterestForRoutes(routes);
        }

        return routes;
      } else {
        throw Exception('Error en la respuesta del servidor: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error al conectar con el servicio de rutas: $e');
    }
  }

  static List<OTPRoute> _parseGraphQLResponse(Map<String, dynamic> data) {
    final List<OTPRoute> routes = [];
    
    try {
      final planConn = data['data']?['planConnection'];
      if (planConn != null && planConn['edges'] != null) {
        final edges = planConn['edges'] as List;
        
        for (final edge in edges) {
          final node = edge['node'];
          if (node != null) {
            final route = _parseItinerary(node);
            if (route != null) {
              routes.add(route);
            }
          }
        }
      }
    } catch (e) {
      // Error silencioso para mejor UX en producción
    }
    
    return routes;
  }

  static OTPRoute? _parseItinerary(Map<String, dynamic> itinerary) {
    try {
      final legs = itinerary['legs'] as List? ?? [];
      final List<OTPLeg> otpLegs = [];
      
      for (final leg in legs) {
        final otpLeg = _parseLeg(leg);
        if (otpLeg != null) {
          otpLegs.add(otpLeg);
        }
      }
      
      return OTPRoute(
        duration: (itinerary['duration'] as num?)?.toInt() ?? 0,
        walkTime: (itinerary['walkTime'] as num?)?.toInt() ?? 0,
        transitTime: 0, // Calculado a partir de legs de tránsito
        waitingTime: 0, // waitTime field not available in this OTP version
        walkDistance: otpLegs.where((l) => l.isWalk).fold(0.0, (sum, l) => sum + l.distance),
        startTime: _parseTimestamp(itinerary['start']),
        endTime: _parseTimestamp(itinerary['end']),
        legs: otpLegs,
      );
    } catch (e) {
      return null;
    }
  }

  static OTPLeg? _parseLeg(Map<String, dynamic> leg) {
    try {
      // Extraer información de la ruta desde trip.route
      String? routeShortName;
      String? routeLongName;
      String? agencyName;
      String? tripHeadsign;
      String? routeColor;
      String? routeTextColor;
      
      if (leg['trip'] != null) {
        tripHeadsign = leg['trip']['tripHeadsign'] as String?;
        
        if (leg['trip']['route'] != null) {
          final route = leg['trip']['route'];
          routeShortName = route['shortName'] as String?;
          routeLongName = route['longName'] as String?;
          routeColor = route['color'] as String?;
          routeTextColor = route['textColor'] as String?;
          
          print('Route data: shortName=$routeShortName, longName=$routeLongName');
          
          if (route['agency'] != null) {
            agencyName = route['agency']['name'] as String?;
          }
        }
      } else if (leg['route'] != null) {
        // Intentar extraer directamente desde leg.route
        final route = leg['route'];
        routeShortName = route['shortName'] as String?;
        routeLongName = route['longName'] as String?;
        routeColor = route['color'] as String?;
        routeTextColor = route['textColor'] as String?;
        
        print('Direct route data: shortName=$routeShortName, longName=$routeLongName');
        
        if (route['agency'] != null) {
          agencyName = route['agency']['name'] as String?;
        }
      }
      
      // Extraer geometría
      String? legGeometry;
      if (leg['legGeometry'] != null && leg['legGeometry']['points'] != null) {
        legGeometry = leg['legGeometry']['points'] as String?;
      }
      
      // Extraer pasos de navegación
      final List<OTPStep> steps = [];
      if (leg['steps'] != null) {
        final stepsList = leg['steps'] as List;
        for (final step in stepsList) {
          final otpStep = _parseStep(step);
          if (otpStep != null) {
            steps.add(otpStep);
          }
        }
      }
      
      // Extraer paradas del recorrido completo
      final List<OTPStop> routeStops = [];
      if (leg['trip'] != null && 
          leg['trip']['pattern'] != null && 
          leg['trip']['pattern']['stops'] != null) {
        final stopsList = leg['trip']['pattern']['stops'] as List;
        for (final stop in stopsList) {
          final otpStop = _parseStop(stop);
          if (otpStop != null) {
            routeStops.add(otpStop);
          }
        }
      }
      
      return OTPLeg(
        mode: leg['mode'] as String? ?? '',
        routeShortName: routeShortName,
        routeLongName: routeLongName,
        agencyName: agencyName,
        tripHeadsign: tripHeadsign,
        routeColor: routeColor,
        routeTextColor: routeTextColor,
        duration: (leg['duration'] as num?)?.toInt() ?? 0,
        distance: (leg['distance'] as num?)?.toDouble() ?? 0.0,
        startTime: _parseTimestamp(leg['from']?['departure']?['scheduledTime']),
        endTime: _parseTimestamp(leg['to']?['arrival']?['scheduledTime']),
        from: _parsePlace(leg['from']),
        to: _parsePlace(leg['to']),
        legGeometry: legGeometry,
        steps: steps,
        routeStops: routeStops,
      );
    } catch (e) {
      return null;
    }
  }

  static OTPStep? _parseStep(Map<String, dynamic> step) {
    try {
      return OTPStep(
        distance: (step['distance'] as num?)?.toDouble() ?? 0.0,
        relativeDirection: step['relativeDirection'] as String?,
        streetName: step['streetName'] as String?,
        absoluteDirection: step['absoluteDirection'] as String?,
      );
    } catch (e) {
      return null;
    }
  }

  static OTPStop? _parseStop(Map<String, dynamic> stop) {
    try {
      return OTPStop(
        gtfsId: stop['gtfsId'] as String? ?? '',
        name: stop['name'] as String? ?? '',
        code: stop['code'] as String?,
        lat: (stop['lat'] as num?)?.toDouble() ?? 0.0,
        lon: (stop['lon'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      return null;
    }
  }

  static OTPPlace? _parsePlace(Map<String, dynamic>? place) {
    if (place == null) return null;
    
    try {
      String? stopId;
      String? stopCode;
      
      if (place['stop'] != null) {
        stopId = place['stop']['gtfsId'] as String?;
        stopCode = place['stop']['code'] as String?;
      }
      
      return OTPPlace(
        name: place['name'] as String? ?? '',
        lat: (place['lat'] as num?)?.toDouble() ?? 0.0,
        lon: (place['lon'] as num?)?.toDouble() ?? 0.0,
        stopId: stopId,
        stopCode: stopCode,
      );
    } catch (e) {
      return null;
    }
  }

  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    
    try {
      if (timestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is String) {
        return DateTime.parse(timestamp);
      }
    } catch (e) {
      // Error silencioso
    }
    
    return DateTime.now();
  }

  // Registrar interés para datos en tiempo real
  static void _registerInterestForRoutes(List<OTPRoute> routes) {
    final Set<String> lines = {};
    final Set<String> stops = {};

    for (final route in routes) {
      for (final leg in route.legs) {
        // Agregar líneas de bus
        if (leg.isTransit && leg.routeShortName != null) {
          lines.add(leg.routeShortName!);
        }

        // Agregar paradas
        if (leg.from?.stopId != null) {
          final stopId = RealtimeInterestService.extractStopId(leg.from!.stopId!);
          if (stopId != null) {
            stops.add(stopId);
          }
        }
        if (leg.to?.stopId != null) {
          final stopId = RealtimeInterestService.extractStopId(leg.to!.stopId!);
          if (stopId != null) {
            stops.add(stopId);
          }
        }
      }
    }

    // Registrar interés de forma asíncrona (no bloquear la respuesta)
    if (lines.isNotEmpty || stops.isNotEmpty) {
      print('🔍 DEBUG: Intentando registrar interés...');
      print('📍 Líneas extraídas: $lines');
      print('🚏 Paradas extraídas: $stops');
      
      RealtimeInterestService.registerInterest(
        lines: lines.toList(),
        stops: stops.toList(),
      ).then((success) {
        if (success) {
          print('✅ Interés registrado exitosamente: ${lines.length} líneas, ${stops.length} paradas');
        } else {
          print('❌ Error: No se pudo registrar interés');
        }
      }).catchError((error) {
        print('💥 Error registrando interés: $error');
      });
    } else {
      print('⚠️ No se encontraron líneas ni paradas para registrar interés');
    }
  }

  // Stream para actualizaciones en tiempo real (re-query cada 40s)
  static Stream<List<OTPRoute>> streamRouteUpdates({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    DateTime? dateTime,
    int numItineraries = 6,
    int maxWalkDistance = 1000,
  }) {
    return Stream.periodic(const Duration(seconds: 40), (_) {
      return planRoute(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: toLat,
        toLon: toLon,
        dateTime: dateTime,
        numItineraries: numItineraries,
        maxWalkDistance: maxWalkDistance,
        registerRealtimeInterest: false, // No re-registrar en cada actualización
      );
    }).asyncMap((future) => future);
  }
}

// Modelos de datos para OTP
class OTPRoute {
  final int duration; // en segundos
  final int walkTime; // en segundos
  final int transitTime; // en segundos
  final int waitingTime; // en segundos
  final double walkDistance; // en metros
  final DateTime startTime;
  final DateTime endTime;
  final List<OTPLeg> legs;

  OTPRoute({
    required this.duration,
    required this.walkTime,
    required this.transitTime,
    required this.waitingTime,
    required this.walkDistance,
    required this.startTime,
    required this.endTime,
    required this.legs,
  });

  // Duración total en minutos
  int get durationInMinutes => (duration / 60).round();
  
  // Distancia total en kilómetros
  double get totalDistanceInKm => walkDistance / 1000;
}

class OTPLeg {
  final String mode; // WALK, BUS, etc.
  final String? routeShortName;
  final String? routeLongName;
  final String? agencyName;
  final String? tripHeadsign;
  final String? routeColor;
  final String? routeTextColor;
  final int duration; // en segundos
  final double distance; // en metros
  final DateTime startTime;
  final DateTime endTime;
  final OTPPlace? from;
  final OTPPlace? to;
  final String? legGeometry; // Polyline encoded
  final List<OTPStep> steps; // Pasos de navegación
  final List<OTPStop> routeStops; // Paradas del recorrido completo

  OTPLeg({
    required this.mode,
    this.routeShortName,
    this.routeLongName,
    this.agencyName,
    this.tripHeadsign,
    this.routeColor,
    this.routeTextColor,
    required this.duration,
    required this.distance,
    required this.startTime,
    required this.endTime,
    this.from,
    this.to,
    this.legGeometry,
    this.steps = const [],
    this.routeStops = const [],
  });

  // Duración en minutos
  int get durationInMinutes => (duration / 60).round();
  
  // Es un segmento de transporte público
  bool get isTransit => mode != 'WALK';
  
  // Es un segmento de caminata
  bool get isWalk => mode == 'WALK';
  
  // Obtener dirección del bus (headsign)
  String get busDirection => tripHeadsign ?? routeLongName ?? 'Sin destino';
}

class OTPPlace {
  final String name;
  final double lat;
  final double lon;
  final String? stopId;
  final String? stopCode;

  OTPPlace({
    required this.name,
    required this.lat,
    required this.lon,
    this.stopId,
    this.stopCode,
  });
}

class OTPStep {
  final double distance;
  final String? relativeDirection;
  final String? streetName;
  final String? absoluteDirection;

  OTPStep({
    required this.distance,
    this.relativeDirection,
    this.streetName,
    this.absoluteDirection,
  });

  // Obtener instrucción de navegación en español
  String get instruction {
    if (streetName != null && streetName!.isNotEmpty) {
      final direction = _getDirectionInSpanish(relativeDirection);
      if (direction.isNotEmpty) {
        return '$direction por $streetName';
      }
      return 'Continúa por $streetName';
    }
    return 'Continúa ${(distance).round()}m';
  }

  String _getDirectionInSpanish(String? direction) {
    switch (direction?.toUpperCase()) {
      case 'LEFT':
        return 'Gira a la izquierda';
      case 'RIGHT':
        return 'Gira a la derecha';
      case 'SLIGHTLY_LEFT':
        return 'Gira ligeramente a la izquierda';
      case 'SLIGHTLY_RIGHT':
        return 'Gira ligeramente a la derecha';
      case 'HARD_LEFT':
        return 'Gira fuertemente a la izquierda';
      case 'HARD_RIGHT':
        return 'Gira fuertemente a la derecha';
      case 'CONTINUE':
        return 'Continúa';
      case 'UTURN_LEFT':
        return 'Da vuelta en U a la izquierda';
      case 'UTURN_RIGHT':
        return 'Da vuelta en U a la derecha';
      default:
        return '';
    }
  }
}

class OTPStop {
  final String gtfsId;
  final String name;
  final String? code;
  final double lat;
  final double lon;

  OTPStop({
    required this.gtfsId,
    required this.name,
    this.code,
    required this.lat,
    required this.lon,
  });

  // Nombre para mostrar (prioriza el nombre sobre el código)
  String get displayName {
    if (name.isNotEmpty && name != 'null') {
      return name;
    } else if (code != null && code!.isNotEmpty) {
      return 'Parada $code';
    }
    return 'Parada';
  }
}