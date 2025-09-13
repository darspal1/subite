import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'realtime_interest_service.dart';

/// Servicio unificado que combina ETAs estáticos (GTFS) y en tiempo real (STM + OTP)
class UnifiedETAService {
  static const String _otpBaseUrl = 'https://stmapi.ddns.net';
  static const String _otpEndpoint = '/otp/gtfs/v1';
  
  static Timer? _updateTimer;
  static final Map<String, StreamController<List<UnifiedETA>>> _controllers = {};
  static final Map<String, List<UnifiedETA>> _cachedETAs = {};

  /// Obtener ETAs para una parada específica (combina estático + tiempo real)
  static Future<List<UnifiedETA>> getETAsForStop({
    required String stopId,
    DateTime? referenceTime,
    int maxResults = 10,
  }) async {
    try {
      // 1. Registrar interés en la parada para datos en tiempo real
      await RealtimeInterestService.registerInterest(
        lines: [], // Se extraerán de los resultados
        stops: [stopId],
      );

      // 2. Obtener datos de OTP (incluye tanto estáticos como tiempo real)
      final otpETAs = await _getOTPStopTimes(stopId, referenceTime);
      
      // 3. Si no hay datos de tiempo real, usar estáticos como fallback
      if (otpETAs.isEmpty) {
        final staticETAs = await _getStaticETAsForStop(stopId, referenceTime);
        return staticETAs;
      }

      return otpETAs;
    } catch (e) {
      print('Error obteniendo ETAs unificados: $e');
      // Fallback a ETAs estáticos
      return await _getStaticETAsForStop(stopId, referenceTime);
    }
  }

  /// Stream de ETAs en tiempo real para una parada
  static Stream<List<UnifiedETA>> streamETAsForStop({
    required String stopId,
    DateTime? referenceTime,
    int maxResults = 10,
  }) {
    final streamKey = 'stop_$stopId';
    
    if (!_controllers.containsKey(streamKey)) {
      _controllers[streamKey] = StreamController<List<UnifiedETA>>.broadcast();
    }

    // Iniciar actualizaciones periódicas
    _startPeriodicUpdates();

    // Primera consulta inmediata
    getETAsForStop(
      stopId: stopId, 
      referenceTime: referenceTime, 
      maxResults: maxResults
    ).then((etas) {
      _cachedETAs[streamKey] = etas;
      if (_controllers.containsKey(streamKey)) {
        _controllers[streamKey]!.add(etas);
      }
    });

    return _controllers[streamKey]!.stream;
  }

  /// Obtener ETAs para múltiples líneas en una ruta
  static Future<Map<String, List<UnifiedETA>>> getETAsForRoute({
    required List<String> routeLines,
    required List<String> stopIds,
    DateTime? referenceTime,
  }) async {
    try {
      // Registrar interés en todas las líneas y paradas
      await RealtimeInterestService.registerInterest(
        lines: routeLines,
        stops: stopIds,
      );

      final Map<String, List<UnifiedETA>> routeETAs = {};

      // Obtener ETAs para cada parada
      for (final stopId in stopIds) {
        final stopETAs = await getETAsForStop(
          stopId: stopId,
          referenceTime: referenceTime,
        );
        
        // Filtrar solo las líneas de interés
        final filteredETAs = stopETAs.where((eta) => 
          routeLines.contains(eta.routeShortName)
        ).toList();
        
        if (filteredETAs.isNotEmpty) {
          routeETAs[stopId] = filteredETAs;
        }
      }

      return routeETAs;
    } catch (e) {
      print('Error obteniendo ETAs para ruta: $e');
      return {};
    }
  }

  /// Obtener datos de OTP (incluye tiempo real si está disponible)
  static Future<List<UnifiedETA>> _getOTPStopTimes(
    String stopId, 
    DateTime? referenceTime
  ) async {
    final DateTime queryDate = referenceTime ?? DateTime.now();
    
    final String graphqlQuery = '''
    {
      stop(id: "STM-MVD:$stopId") {
        name
        code
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
            arrivalDelay
            departureDelay
            realtime
            realtimeState
            serviceDay
            trip {
              tripHeadsign
            }
          }
        }
      }
    }
    ''';

    final response = await http.post(
      Uri.parse('$_otpBaseUrl$_otpEndpoint'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'query': graphqlQuery}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return _parseOTPStopTimes(data);
    } else {
      throw Exception('Error OTP: ${response.statusCode}');
    }
  }

  /// Parsear respuesta de OTP a ETAs unificados
  static List<UnifiedETA> _parseOTPStopTimes(Map<String, dynamic> data) {
    final List<UnifiedETA> etas = [];
    
    try {
      final stoptimesData = data['data']?['stop']?['stoptimesForServiceDate'] as List? ?? [];
      
      for (final patternData in stoptimesData) {
        final pattern = patternData['pattern'];
        final route = pattern?['route'];
        final headsign = pattern?['headsign'] as String?;
        
        final stoptimes = patternData['stoptimes'] as List? ?? [];
        
        for (final stoptime in stoptimes) {
          final eta = _createUnifiedETAFromOTP(stoptime, route, headsign);
          if (eta != null) {
            etas.add(eta);
          }
        }
      }
    } catch (e) {
      print('Error parseando OTP response: $e');
    }
    
    // Filtrar ETAs futuros y ordenar
    final now = tz.TZDateTime.now(tz.getLocation('America/Montevideo'));
    final futureETAs = etas.where((eta) => 
      eta.departureTime.isAfter(now) && 
      eta.minutesUntil <= 120
    ).toList();
    
    futureETAs.sort((a, b) => a.departureTime.compareTo(b.departureTime));
    
    return futureETAs.take(10).toList();
  }

  /// Crear ETA unificado desde datos OTP
  static UnifiedETA? _createUnifiedETAFromOTP(
    Map<String, dynamic> stoptime,
    Map<String, dynamic>? route,
    String? headsign,
  ) {
    try {
      final serviceDay = stoptime['serviceDay'] as int? ?? 0;
      final scheduledDeparture = stoptime['scheduledDeparture'] as int? ?? 0;
      final realtimeDeparture = stoptime['realtimeDeparture'] as int?;
      final departureDelay = stoptime['departureDelay'] as int? ?? 0;
      final isRealtime = stoptime['realtime'] as bool? ?? false;
      final realtimeState = stoptime['realtimeState'] as String? ?? 'SCHEDULED';

      // Calcular tiempo de salida efectivo
      final effectiveDeparture = realtimeDeparture ?? (scheduledDeparture + departureDelay);
      final departureTimestamp = serviceDay + effectiveDeparture;
      
      final departureTime = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.getLocation('America/Montevideo'),
        departureTimestamp * 1000,
      );

      final now = tz.TZDateTime.now(tz.getLocation('America/Montevideo'));
      final minutesUntil = departureTime.difference(now).inMinutes;

      if (minutesUntil <= 0) return null; // Filtrar horarios pasados

      return UnifiedETA(
        routeShortName: route?['shortName'] as String? ?? '',
        routeLongName: route?['longName'] as String?,
        routeColor: route?['color'] as String?,
        routeTextColor: route?['textColor'] as String?,
        headsign: headsign ?? stoptime['trip']?['tripHeadsign'] as String?,
        departureTime: departureTime,
        minutesUntil: minutesUntil,
        isRealtime: isRealtime,
        realtimeState: realtimeState,
        dataSource: isRealtime ? ETADataSource.realtimeSTM : ETADataSource.staticGTFS,
        delay: departureDelay,
      );
    } catch (e) {
      print('Error creando ETA desde OTP: $e');
      return null;
    }
  }

  /// Fallback a ETAs estáticos usando el servicio existente
  static Future<List<UnifiedETA>> _getStaticETAsForStop(
    String stopId, 
    DateTime? referenceTime
  ) async {
    try {
      // Aquí necesitarías implementar la consulta a GTFS estático
      // Por ahora retornamos lista vacía como placeholder
      return [];
    } catch (e) {
      print('Error obteniendo ETAs estáticos: $e');
      return [];
    }
  }

  /// Iniciar actualizaciones periódicas
  static void _startPeriodicUpdates() {
    if (_updateTimer != null) return;

    _updateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updateAllCachedETAs();
    });
  }

  /// Actualizar todos los ETAs cacheados
  static void _updateAllCachedETAs() {
    for (final entry in _cachedETAs.entries) {
      final streamKey = entry.key;
      
      if (streamKey.startsWith('stop_')) {
        final stopId = streamKey.substring(5);
        
        getETAsForStop(stopId: stopId).then((etas) {
          _cachedETAs[streamKey] = etas;
          if (_controllers.containsKey(streamKey)) {
            _controllers[streamKey]!.add(etas);
          }
        }).catchError((error) {
          print('Error actualizando ETAs para $stopId: $error');
        });
      }
    }
  }

  /// Detener actualizaciones para un stream específico
  static void stopUpdates(String streamKey) {
    if (_controllers.containsKey(streamKey)) {
      _controllers[streamKey]!.close();
      _controllers.remove(streamKey);
      _cachedETAs.remove(streamKey);
    }

    if (_controllers.isEmpty) {
      _updateTimer?.cancel();
      _updateTimer = null;
    }
  }

  /// Limpiar todos los recursos
  static void dispose() {
    _updateTimer?.cancel();
    _updateTimer = null;
    
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _cachedETAs.clear();
  }

  static String _formatDate(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }
}

/// Modelo unificado de ETA que combina datos estáticos y tiempo real
class UnifiedETA {
  final String routeShortName;
  final String? routeLongName;
  final String? routeColor;
  final String? routeTextColor;
  final String? headsign;
  final tz.TZDateTime departureTime;
  final int minutesUntil;
  final bool isRealtime;
  final String realtimeState; // SCHEDULED, UPDATED, CANCELED
  final ETADataSource dataSource;
  final int delay; // en segundos

  UnifiedETA({
    required this.routeShortName,
    this.routeLongName,
    this.routeColor,
    this.routeTextColor,
    this.headsign,
    required this.departureTime,
    required this.minutesUntil,
    required this.isRealtime,
    required this.realtimeState,
    required this.dataSource,
    this.delay = 0,
  });

  /// Nombre para mostrar en UI
  String get displayName => routeShortName.isNotEmpty ? routeShortName : (routeLongName ?? 'Bus');
  
  /// Destino para mostrar
  String get displayHeadsign => headsign ?? 'Sin destino';
  
  /// Texto del estado
  String get statusText {
    switch (dataSource) {
      case ETADataSource.realtimeSTM:
        if (realtimeState == 'CANCELED') return 'Cancelado';
        if (delay > 60) return 'Retrasado ${(delay / 60).round()} min';
        if (delay < -60) return 'Adelantado ${(-delay / 60).round()} min';
        return 'Tiempo real';
      case ETADataSource.staticGTFS:
        return 'Programado';
    }
  }

  /// Color del estado
  Color get statusColor {
    switch (dataSource) {
      case ETADataSource.realtimeSTM:
        if (realtimeState == 'CANCELED') return const Color(0xFFD32F2F);
        if (delay.abs() > 60) return const Color(0xFFFF9800);
        return const Color(0xFF388E3C);
      case ETADataSource.staticGTFS:
        return const Color(0xFF757575);
    }
  }


  /// Minutos formateados
  String get formattedMinutes {
    if (minutesUntil <= 0) return 'Llegando';
    if (minutesUntil == 1) return '1 min';
    return '$minutesUntil min';
  }

  /// Es cancelado
  bool get isCanceled => realtimeState == 'CANCELED';
  
  /// Tiene retraso significativo
  bool get hasSignificantDelay => delay.abs() > 120; // más de 2 minutos
}

/// Fuente de datos del ETA
enum ETADataSource {
  staticGTFS,    // Horarios programados de GTFS
  realtimeSTM,   // Posición real de buses STM + OTP
}