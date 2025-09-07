import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class StaticETAService {
  static bool _initialized = false;
  static late tz.Location _montevideoLocation;

  // Inicializar la timezone database una vez
  static void initialize() {
    if (!_initialized) {
      tz.initializeTimeZones();
      _montevideoLocation = tz.getLocation('America/Montevideo');
      _initialized = true;
    }
  }

  // Calcular ETAs estáticos para una parada específica
  static List<StaticETA> calculateStaticETAs({
    required String stopId,
    required List<StopTime> stopTimes,
    DateTime? referenceTime,
  }) {
    initialize();
    
    final List<StaticETA> etas = [];
    
    for (final stopTime in stopTimes) {
      final arrivalTime = stopTime.effectiveArrivalTime;
      if (arrivalTime == null) continue;
      
      // Solo incluir horarios futuros (próximos 2 horas)
      final minutesUntil = stopTime.minutesUntilArrival;
      if (minutesUntil != null && minutesUntil > 0 && minutesUntil <= 120) {
        etas.add(StaticETA(
          routeShortName: stopTime.routeShortName,
          routeLongName: stopTime.routeLongName,
          tripHeadsign: stopTime.tripHeadsign,
          arrivalTime: arrivalTime,
          minutesUntil: minutesUntil,
          isRealtime: stopTime.realtimeArrival != null,
        ));
      }
    }
    
    // Ordenar por tiempo de llegada
    etas.sort((a, b) => a.arrivalTime.compareTo(b.arrivalTime));
    
    return etas;
  }

  // Obtener próximos horarios para múltiples líneas
  static Map<String, List<int>> getUpcomingMinutesForRoutes({
    required List<StopTime> stopTimes,
    required List<String> routeNames,
    DateTime? referenceTime,
    int maxResults = 3,
  }) {
    initialize();
    
    final Map<String, List<int>> routeMinutes = {};
    
    for (final routeName in routeNames) {
      final routeStopTimes = stopTimes
          .where((st) => st.routeShortName == routeName)
          .toList();
      
      final etas = calculateStaticETAs(
        stopId: '', // No necesario para este cálculo
        stopTimes: routeStopTimes,
        referenceTime: referenceTime,
      );
      
      routeMinutes[routeName] = etas
          .take(maxResults)
          .map((eta) => eta.minutesUntil)
          .toList();
    }
    
    return routeMinutes;
  }

  // Formatear tiempo para mostrar en UI
  static String formatArrivalTime(tz.TZDateTime arrivalTime) {
    return '${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}';
  }

  // Formatear minutos hasta llegada
  static String formatMinutesUntil(int minutes) {
    if (minutes == 0) return 'Llegando';
    if (minutes == 1) return '1 min';
    return '$minutes min';
  }
}

class StopTime {
  final int serviceDay;  // Unix seconds para medianoche del día de servicio
  final int scheduledArrival;
  final int? realtimeArrival;
  final int? arrivalDelay;
  final String? realtimeState;
  final String routeShortName;
  final String? routeLongName;
  final String? tripHeadsign;

  StopTime({
    required this.serviceDay,
    required this.scheduledArrival,
    this.realtimeArrival,
    this.arrivalDelay,
    this.realtimeState,
    required this.routeShortName,
    this.routeLongName,
    this.tripHeadsign,
  });

  tz.TZDateTime? get effectiveArrivalTime {
    StaticETAService.initialize();
    
    // Prioriza realtime si disponible; fallback a scheduled + delay
    final effectiveSeconds = realtimeArrival ?? (scheduledArrival + (arrivalDelay ?? 0));
    
    // Calcula timestamp absoluto en segundos
    final absoluteTimestamp = serviceDay + effectiveSeconds;
    
    // Crea TZDateTime desde milliseconds since epoch
    return tz.TZDateTime.fromMillisecondsSinceEpoch(
      StaticETAService._montevideoLocation, 
      absoluteTimestamp * 1000
    );
  }

  int? get minutesUntilArrival {
    if (realtimeState == 'CANCELED') {
      return null;
    }

    final arrival = effectiveArrivalTime;
    if (arrival == null) return null;

    final now = tz.TZDateTime.now(StaticETAService._montevideoLocation);
    final difference = arrival.difference(now);
    final minutes = difference.inMinutes;

    // Si es negativo, retorna 0 (ya llegó)
    return minutes > 0 ? minutes : 0;
  }

  factory StopTime.fromOTPData(Map<String, dynamic> data) {
    return StopTime(
      serviceDay: data['serviceDay'] ?? 0,
      scheduledArrival: data['scheduledArrival'] ?? 0,
      realtimeArrival: data['realtimeArrival'],
      arrivalDelay: data['arrivalDelay'],
      realtimeState: data['realtimeState'],
      routeShortName: data['route']?['shortName'] ?? '',
      routeLongName: data['route']?['longName'],
      tripHeadsign: data['trip']?['tripHeadsign'],
    );
  }
}

class StaticETA {
  final String routeShortName;
  final String? routeLongName;
  final String? tripHeadsign;
  final tz.TZDateTime arrivalTime;
  final int minutesUntil;
  final bool isRealtime;

  StaticETA({
    required this.routeShortName,
    this.routeLongName,
    this.tripHeadsign,
    required this.arrivalTime,
    required this.minutesUntil,
    required this.isRealtime,
  });

  String get formattedTime => StaticETAService.formatArrivalTime(arrivalTime);
  String get formattedMinutes => StaticETAService.formatMinutesUntil(minutesUntil);
}