import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'realtime_interest_service.dart';

// --- MODELOS DE DATOS (DEFINIDOS PRIMERO PARA CLARIDAD) ---

class OTPRoute {
  final int duration; // en segundos
  final int walkTime; // en segundos
  final double walkDistance; // en metros
  final DateTime startTime;
  final DateTime endTime;
  final List<OTPLeg> legs;

  OTPRoute({
    required this.duration,
    required this.walkTime,
    required this.walkDistance,
    required this.startTime,
    required this.endTime,
    required this.legs,
  });

  int get durationInMinutes => (duration / 60).round();
}

class OTPLeg {
  final String mode; // WALK, BUS, etc.
  final String? routeShortName;
  final String? routeLongName;
  final String? agencyName;
  final String? tripHeadsign;
  final String? routeColor;
  final String? routeTextColor;
  final int duration;
  final double distance;
  final DateTime startTime;
  final DateTime endTime;
  final OTPPlace? from;
  final OTPPlace? to;
  final String? legGeometry;
  final bool isRealtime; // Para saber si el horario es en vivo

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
    this.isRealtime = false,
  });

  bool get isTransit => mode == 'BUS';
  bool get isWalk => mode == 'WALK';
  bool get isBicycle => mode == 'BICYCLE';
  int get durationInMinutes => (duration / 60).round();
}

class OTPPlace {
  final String name;
  final double lat;
  final double lon;
  final String? stopId;

  OTPPlace({
    required this.name,
    required this.lat,
    required this.lon,
    this.stopId,
  });
}

// --- SERVICIO OTP ---

class OTPService {
  static const String _baseUrl = 'https://stmapi.ddns.net';
  static const String _endpoint = '/otp/gtfs/v1';

  static Future<List<OTPRoute>> planRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    DateTime? dateTime,
    int numItineraries = 20,
    int maxWalkDistance = 800, // 800m como valor por defecto
  }) async {
    print('OTP planRoute llamado: $fromLat,$fromLon -> $toLat,$toLon');
    try {
      final DateTime planDateTime = dateTime ?? DateTime.now();
      final String isoDateTime =
          '${planDateTime.year}-${planDateTime.month.toString().padLeft(2, '0')}-${planDateTime.day.toString().padLeft(2, '0')}T${planDateTime.hour.toString().padLeft(2, '0')}:${planDateTime.minute.toString().padLeft(2, '0')}:00-03:00';
      
      final int transferPenaltySeconds = 280; // 15 minutos de penalización por transbordo

      final String graphqlQuery = '''
      {
        planConnection(
          origin: { location: { coordinate: { latitude: $fromLat, longitude: $fromLon } } }
          destination: { location: { coordinate: { latitude: $toLat, longitude: $toLon } } }
          dateTime: { earliestDeparture: "$isoDateTime" }
          modes: { transit: { transit: [{ mode: BUS }] } }
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
                  stop { gtfsId }
                  departure { scheduledTime estimated { time delay } }
                }
                to {
                  name
                  lat
                  lon
                  stop { gtfsId }
                  arrival { scheduledTime estimated { time delay } }
                }
                duration
                distance
                legGeometry { points }
                route { shortName longName color textColor agency { name } }
                trip { tripHeadsign }
              }
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
        print('OTP respuesta recibida, parseando...');
        print('Respuesta OTP: ${json.encode(data)}');
        final routes = _parseGraphQLResponse(data);
        print('OTP rutas parseadas: ${routes.length}');

        // Registrar interés después de obtener una respuesta exitosa
        if (routes.isNotEmpty) {
          _registerInterestForRoutes(routes);
        }

        return routes;
      } else {
        print('ERROR OTP: ${response.statusCode} - ${response.body}');
        throw Exception(
            'Error en la respuesta del servidor: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('EXCEPCIÓN EN OTP planRoute: $e');
      throw Exception('Error al conectar con el servicio de rutas: $e');
    }
  }

  static List<OTPRoute> _parseGraphQLResponse(Map<String, dynamic> data) {
    final List<OTPRoute> routes = [];
    try {
      final planConn = data['data']?['planConnection'];
      if (planConn != null && planConn['edges'] != null) {
        for (final edge in (planConn['edges'] as List)) {
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
      print('--- ERROR DE PARSEO EN _parseGraphQLResponse ---');
      print('Error: $e');
      print('Datos que causaron el fallo: ${jsonEncode(data)}');
    }
    return routes;
  }

  static OTPRoute? _parseItinerary(Map<String, dynamic> itinerary) {
    try {
      final legsData = itinerary['legs'] as List? ?? [];
      final List<OTPLeg> otpLegs = [];
      for (final legData in legsData) {
        final otpLeg = _parseLeg(legData);
        if (otpLeg != null) {
          otpLegs.add(otpLeg);
        }
      }
      if (otpLegs.isEmpty && legsData.isNotEmpty) return null;

      return OTPRoute(
        duration: (itinerary['duration'] as num?)?.toInt() ?? 0,
        walkTime: (itinerary['walkTime'] as num?)?.toInt() ?? 0,
        walkDistance: otpLegs.where((l) => l.isWalk).fold(0.0, (sum, l) => sum + l.distance),
        startTime: _parseTimestamp(itinerary['start']),
        endTime: _parseTimestamp(itinerary['end']),
        legs: otpLegs,
      );
    } catch (e) {
      print('--- ERROR DE PARSEO EN _parseItinerary ---');
      print('Error: $e');
      print('Datos del "itinerary" que causaron el fallo: ${jsonEncode(itinerary)}');
      return null;
    }
  }

  static OTPLeg? _parseLeg(Map<String, dynamic> leg) {
    try {
      final routeData = leg['route'];
      
      final departureTimestamp = leg['from']?['departure']?['estimated']?['time'] ?? leg['from']?['departure']?['scheduledTime'];
      final arrivalTimestamp = leg['to']?['arrival']?['estimated']?['time'] ?? leg['to']?['arrival']?['scheduledTime'];
      final isRealtime = leg['to']?['arrival']?['estimated'] != null || leg['from']?['departure']?['estimated'] != null;

      return OTPLeg(
        mode: leg['mode'] as String? ?? '',
        routeShortName: routeData?['shortName'] as String?,
        routeLongName: routeData?['longName'] as String?,
        agencyName: routeData?['agency']?['name'] as String?,
        tripHeadsign: leg['trip']?['tripHeadsign'] as String?,
        routeColor: routeData?['color'] as String?,
        routeTextColor: routeData?['textColor'] as String?,
        duration: (leg['duration'] as num?)?.toInt() ?? 0,
        distance: (leg['distance'] as num?)?.toDouble() ?? 0.0,
        startTime: _parseTimestamp(departureTimestamp),
        endTime: _parseTimestamp(arrivalTimestamp),
        from: _parsePlace(leg['from']),
        to: _parsePlace(leg['to']),
        legGeometry: leg['legGeometry']?['points'] as String?,
        isRealtime: isRealtime,
      );
    } catch (e) {
      print('--- ERROR DE PARSEO EN _parseLeg ---');
      print('Error: $e');
      print('Datos del "leg" que causó el fallo: ${jsonEncode(leg)}');
      return null;
    }
  }
  
  static OTPPlace? _parsePlace(Map<String, dynamic>? place) {
    if (place == null) return null;
    try {
      return OTPPlace(
        name: place['name'] as String? ?? '',
        lat: (place['lat'] as num?)?.toDouble() ?? 0.0,
        lon: (place['lon'] as num?)?.toDouble() ?? 0.0,
        stopId: place['stop']?['gtfsId'] as String?,
      );
    } catch (e) { return null; }
  }

  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    try {
      if (timestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is String) {
        return DateTime.parse(timestamp);
      }
    } catch (e) { /* silent */ }
    return DateTime.now();
  }

  // Planificar ruta solo en bicicleta
  static Future<List<OTPRoute>> planBicycleRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    DateTime? dateTime,
  }) async {
    return await _planRouteWithMode(
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
      dateTime: dateTime,
      mode: 'BICYCLE',
    );
  }

  // Planificar ruta solo caminando
  static Future<List<OTPRoute>> planWalkRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    DateTime? dateTime,
  }) async {
    return await _planRouteWithMode(
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
      dateTime: dateTime,
      mode: 'WALK',
    );
  }

  // Método genérico para planificar rutas con modo específico
  static Future<List<OTPRoute>> _planRouteWithMode({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    DateTime? dateTime,
    required String mode,
  }) async {
    try {
      final DateTime planDateTime = dateTime ?? DateTime.now();
      final String isoDateTime =
          '${planDateTime.year}-${planDateTime.month.toString().padLeft(2, '0')}-${planDateTime.day.toString().padLeft(2, '0')}T${planDateTime.hour.toString().padLeft(2, '0')}:${planDateTime.minute.toString().padLeft(2, '0')}:00-03:00';

      final String graphqlQuery = '''
      {
        planConnection(
          origin: { location: { coordinate: { latitude: $fromLat, longitude: $fromLon } } }
          destination: { location: { coordinate: { latitude: $toLat, longitude: $toLon } } }
          dateTime: { earliestDeparture: "$isoDateTime" }
          modes: { direct: [$mode] }
          first: 1
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
                  stop { gtfsId }
                  departure { scheduledTime estimated { time delay } }
                }
                to {
                  name
                  lat
                  lon
                  stop { gtfsId }
                  arrival { scheduledTime estimated { time delay } }
                }
                duration
                distance
                legGeometry { points }
                route { shortName longName color textColor agency { name } }
                trip { tripHeadsign }
              }
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
        return _parseGraphQLResponse(data);
      } else {
        throw Exception('Error OTP: ${response.statusCode}');
      }
    } catch (e) {
      return [];
    }
  }

  static void _registerInterestForRoutes(List<OTPRoute> routes) {
    final Set<String> lines = {};

    final transitRoutes = routes.where((route) => route.legs.any((leg) => leg.isTransit));
    if (transitRoutes.isEmpty) return;

    for (final route in transitRoutes) {
      for (final leg in route.legs) {
        if (leg.isTransit && leg.routeShortName != null) {
          lines.add(leg.routeShortName!);
        }
      }
    }

    if (lines.isNotEmpty) {
      RealtimeInterestService.registerInterest(
        lines: lines.toList(),
        stops: [],
      );
    }
  }
}