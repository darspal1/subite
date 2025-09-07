import 'dart:convert';
import 'package:http/http.dart' as http;

class StopTimesService {
  static const String _baseUrl = 'http://api.stmapi.xo.je';
  static const String _endpoint = '/otp/routers/default/index/graphql';

  // Obtener horarios de una parada específica
  static Future<List<StopTime>> getStopTimes({
    required String stopId,
    DateTime? date,
    int numberOfDepartures = 10,
  }) async {
    try {
      final DateTime queryDate = date ?? DateTime.now();
      
      final String graphqlQuery = '''
      {
        stop(id: "$stopId") {
          name
          code
          lat
          lon
          stoptimesForServiceDate(date: "${_formatDate(queryDate)}") {
            pattern {
              route {
                shortName
                longName
                color
                textColor
              }
              headsign
            }
            stoptimes {
              scheduledArrival
              scheduledDeparture
              realtimeArrival
              realtimeDeparture
              realtime
              serviceDay
              trip {
                tripHeadsign
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
        return _parseStopTimesResponse(data);
      } else {
        throw Exception('Error al obtener horarios: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error al conectar con el servicio de horarios: $e');
    }
  }

  static List<StopTime> _parseStopTimesResponse(Map<String, dynamic> data) {
    final List<StopTime> stopTimes = [];
    
    try {
      if (data['data']?['stop']?['stoptimesForServiceDate'] != null) {
        final stoptimesData = data['data']['stop']['stoptimesForServiceDate'] as List;
        
        for (final patternData in stoptimesData) {
          final pattern = patternData['pattern'];
          final route = pattern?['route'];
          final headsign = pattern?['headsign'] as String?;
          
          if (patternData['stoptimes'] != null) {
            final stoptimes = patternData['stoptimes'] as List;
            
            for (final stoptime in stoptimes) {
              final stopTime = StopTime(
                routeShortName: route?['shortName'] as String?,
                routeLongName: route?['longName'] as String?,
                routeColor: route?['color'] as String?,
                routeTextColor: route?['textColor'] as String?,
                headsign: headsign ?? stoptime['trip']?['tripHeadsign'] as String?,
                scheduledArrival: _parseTimeOfDay(stoptime['scheduledArrival']),
                scheduledDeparture: _parseTimeOfDay(stoptime['scheduledDeparture']),
                realtimeArrival: _parseTimeOfDay(stoptime['realtimeArrival']),
                realtimeDeparture: _parseTimeOfDay(stoptime['realtimeDeparture']),
                isRealtime: stoptime['realtime'] as bool? ?? false,
                serviceDay: DateTime.fromMillisecondsSinceEpoch(
                  (stoptime['serviceDay'] as int? ?? 0) * 1000
                ),
              );
              
              stopTimes.add(stopTime);
            }
          }
        }
      }
    } catch (e) {
      // Error silencioso
    }
    
    // Ordenar por hora de salida
    stopTimes.sort((a, b) => a.departureTime.compareTo(b.departureTime));
    
    return stopTimes;
  }

  static DateTime _parseTimeOfDay(dynamic timeOfDay) {
    if (timeOfDay == null) return DateTime.now();
    
    try {
      if (timeOfDay is int) {
        // timeOfDay viene en segundos desde medianoche
        final now = DateTime.now();
        final midnight = DateTime(now.year, now.month, now.day);
        return midnight.add(Duration(seconds: timeOfDay));
      }
    } catch (e) {
      // Error silencioso
    }
    
    return DateTime.now();
  }

  static String _formatDate(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }
}

class StopTime {
  final String? routeShortName;
  final String? routeLongName;
  final String? routeColor;
  final String? routeTextColor;
  final String? headsign;
  final DateTime scheduledArrival;
  final DateTime scheduledDeparture;
  final DateTime realtimeArrival;
  final DateTime realtimeDeparture;
  final bool isRealtime;
  final DateTime serviceDay;

  StopTime({
    this.routeShortName,
    this.routeLongName,
    this.routeColor,
    this.routeTextColor,
    this.headsign,
    required this.scheduledArrival,
    required this.scheduledDeparture,
    required this.realtimeArrival,
    required this.realtimeDeparture,
    required this.isRealtime,
    required this.serviceDay,
  });

  // Obtener la hora de salida (tiempo real si está disponible)
  DateTime get departureTime => isRealtime ? realtimeDeparture : scheduledDeparture;
  
  // Obtener la hora de llegada (tiempo real si está disponible)
  DateTime get arrivalTime => isRealtime ? realtimeArrival : scheduledArrival;
  
  // Minutos hasta la salida
  int get minutesUntilDeparture {
    final now = DateTime.now();
    final diff = departureTime.difference(now).inMinutes;
    return diff > 0 ? diff : 0;
  }
  
  // Texto del estado (tiempo real o programado)
  String get statusText => isRealtime ? 'Tiempo real' : 'Programado';
  
  // Nombre de la línea para mostrar
  String get displayName => routeShortName ?? routeLongName ?? 'Bus';
  
  // Destino para mostrar
  String get displayHeadsign => headsign ?? 'Sin destino';
}