import 'dart:async';
import 'package:timezone/timezone.dart' as tz;
import 'static_eta_service.dart';
import 'otp_service.dart';

class RealtimeETAService {
  static Timer? _updateTimer;
  static final Map<String, StreamController<List<RealtimeETA>>> _controllers = {};
  static final Map<String, List<RealtimeETA>> _cachedETAs = {};

  // Inicializar actualizaciones en tiempo real para una ruta específica
  static Stream<List<RealtimeETA>> startRealtimeUpdates({
    required String routeId,
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    DateTime? dateTime,
  }) {
    // Crear controller si no existe
    if (!_controllers.containsKey(routeId)) {
      _controllers[routeId] = StreamController<List<RealtimeETA>>.broadcast();
    }

    // Iniciar actualizaciones periódicas si no están activas
    _startPeriodicUpdates();

    // Realizar primera consulta inmediatamente
    _updateETAsForRoute(routeId, fromLat, fromLon, toLat, toLon, dateTime);

    return _controllers[routeId]!.stream;
  }

  // Detener actualizaciones para una ruta específica
  static void stopRealtimeUpdates(String routeId) {
    if (_controllers.containsKey(routeId)) {
      _controllers[routeId]!.close();
      _controllers.remove(routeId);
      _cachedETAs.remove(routeId);
    }

    // Si no hay más controllers activos, detener el timer
    if (_controllers.isEmpty) {
      _updateTimer?.cancel();
      _updateTimer = null;
    }
  }

  // Iniciar actualizaciones periódicas cada 40 segundos
  static void _startPeriodicUpdates() {
    if (_updateTimer != null) return;

    _updateTimer = Timer.periodic(const Duration(seconds: 40), (_) {
      _updateAllActiveRoutes();
    });
  }

  // Actualizar todas las rutas activas
  static void _updateAllActiveRoutes() {
    for (final routeId in _controllers.keys) {
      // Aquí necesitarías almacenar los parámetros de cada ruta
      // Por simplicidad, solo actualizamos si hay datos cached
      if (_cachedETAs.containsKey(routeId)) {
        _updateCachedETAs(routeId);
      }
    }
  }

  // Actualizar ETAs para una ruta específica
  static Future<void> _updateETAsForRoute(
    String routeId,
    double fromLat,
    double fromLon,
    double toLat,
    double toLon,
    DateTime? dateTime,
  ) async {
    try {
      // Obtener rutas actualizadas de OTP (con datos en tiempo real)
      final routes = await OTPService.planRoute(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: toLat,
        toLon: toLon,
        dateTime: dateTime,
        registerRealtimeInterest: false, // Ya registrado anteriormente
      );

      // Convertir a ETAs en tiempo real
      final realtimeETAs = _convertOTPRoutesToRealtimeETAs(routes);
      
      // Actualizar cache y notificar listeners
      _cachedETAs[routeId] = realtimeETAs;
      if (_controllers.containsKey(routeId)) {
        _controllers[routeId]!.add(realtimeETAs);
      }

    } catch (e) {
      print('Error actualizando ETAs en tiempo real: $e');
    }
  }

  // Actualizar ETAs cached (decrementar minutos)
  static void _updateCachedETAs(String routeId) {
    final cachedETAs = _cachedETAs[routeId];
    if (cachedETAs == null) return;

    final now = tz.TZDateTime.now(tz.getLocation('America/Montevideo'));
    final updatedETAs = <RealtimeETA>[];

    for (final eta in cachedETAs) {
      final minutesUntil = eta.departureTime.difference(now).inMinutes;
      
      if (minutesUntil > 0) {
        updatedETAs.add(eta.copyWith(minutesUntil: minutesUntil));
      }
    }

    // Actualizar cache y notificar
    _cachedETAs[routeId] = updatedETAs;
    if (_controllers.containsKey(routeId)) {
      _controllers[routeId]!.add(updatedETAs);
    }
  }

  // Convertir rutas OTP a ETAs en tiempo real
  static List<RealtimeETA> _convertOTPRoutesToRealtimeETAs(List<OTPRoute> routes) {
    final List<RealtimeETA> realtimeETAs = [];
    
    for (final route in routes) {
      for (final leg in route.legs) {
        if (leg.isTransit && leg.routeShortName != null) {
          final now = tz.TZDateTime.now(tz.getLocation('America/Montevideo'));
          final minutesUntil = leg.startTime.difference(now).inMinutes;
          
          if (minutesUntil > 0 && minutesUntil <= 120) {
            realtimeETAs.add(RealtimeETA(
              routeShortName: leg.routeShortName!,
              routeLongName: leg.routeLongName,
              stopName: leg.from?.name ?? 'Parada',
              departureTime: tz.TZDateTime.from(leg.startTime, tz.getLocation('America/Montevideo')),
              minutesUntil: minutesUntil,
              isRealtime: true, // Datos de OTP con tiempo real
              realtimeState: 'SCHEDULED', // Por defecto
            ));
          }
        }
      }
    }

    // Ordenar por tiempo de salida
    realtimeETAs.sort((a, b) => a.departureTime.compareTo(b.departureTime));
    
    return realtimeETAs;
  }

  // Limpiar todos los recursos
  static void dispose() {
    _updateTimer?.cancel();
    _updateTimer = null;
    
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _cachedETAs.clear();
  }
}

class RealtimeETA {
  final String routeShortName;
  final String? routeLongName;
  final String stopName;
  final tz.TZDateTime departureTime;
  final int minutesUntil;
  final bool isRealtime;
  final String realtimeState; // SCHEDULED, UPDATED, CANCELED

  RealtimeETA({
    required this.routeShortName,
    this.routeLongName,
    required this.stopName,
    required this.departureTime,
    required this.minutesUntil,
    required this.isRealtime,
    required this.realtimeState,
  });

  RealtimeETA copyWith({
    String? routeShortName,
    String? routeLongName,
    String? stopName,
    tz.TZDateTime? departureTime,
    int? minutesUntil,
    bool? isRealtime,
    String? realtimeState,
  }) {
    return RealtimeETA(
      routeShortName: routeShortName ?? this.routeShortName,
      routeLongName: routeLongName ?? this.routeLongName,
      stopName: stopName ?? this.stopName,
      departureTime: departureTime ?? this.departureTime,
      minutesUntil: minutesUntil ?? this.minutesUntil,
      isRealtime: isRealtime ?? this.isRealtime,
      realtimeState: realtimeState ?? this.realtimeState,
    );
  }

  String get formattedTime => StaticETAService.formatArrivalTime(departureTime);
  
  String get formattedMinutes {
    if (minutesUntil <= 0) return 'Llegando';
    if (minutesUntil == 1) return '1 min';
    return '$minutesUntil min';
  }

  bool get isCanceled => realtimeState == 'CANCELED';
  bool get isDelayed => realtimeState == 'UPDATED' && isRealtime;
}