import 'otp_service.dart';
import '../widgets/route_result_card.dart';
import '../widgets/route_results_list.dart';

class RouteGroupingService {
  // Agrupar rutas por paradas de origen y destino
  static List<GroupedRoute> groupRoutesByStops(List<OTPRoute> otpRoutes) {
    final Map<String, GroupedRoute> groupedRoutes = {};
    
    for (final route in otpRoutes) {
      final groupKey = _generateGroupKey(route);
      
      if (groupedRoutes.containsKey(groupKey)) {
        // Agregar líneas adicionales a la ruta existente
        groupedRoutes[groupKey]!.addAlternativeRoute(route);
      } else {
        // Crear nueva ruta agrupada
        groupedRoutes[groupKey] = GroupedRoute.fromOTPRoute(route);
      }
    }
    
    // Convertir a lista y ordenar por duración
    final List<GroupedRoute> result = groupedRoutes.values.toList();
    result.sort((a, b) => a.totalDuration.compareTo(b.totalDuration));
    
    return result;
  }
  
  // Generar clave única para agrupar rutas similares
  static String _generateGroupKey(OTPRoute route) {
    final List<String> keyParts = [];
    
    for (final leg in route.legs) {
      if (leg.isTransit) {
        // Usar parada de origen y destino para agrupar
        final fromStop = leg.from?.stopId ?? leg.from?.name ?? 'unknown';
        final toStop = leg.to?.stopId ?? leg.to?.name ?? 'unknown';
        keyParts.add('$fromStop-$toStop');
      } else if (leg.isWalk) {
        // Agrupar caminatas por distancia aproximada
        final walkDistance = (leg.distance / 100).round() * 100; // Redondear a 100m
        keyParts.add('walk-$walkDistance');
      }
    }
    
    return keyParts.join('|');
  }
  
  // Convertir rutas agrupadas a formato de la aplicación
  static List<RouteResult> convertGroupedRoutesToRouteResults(List<GroupedRoute> groupedRoutes) {
    final List<RouteResult> routes = [];
    
    for (int i = 0; i < groupedRoutes.length; i++) {
      final groupedRoute = groupedRoutes[i];
      final segments = _convertGroupedRouteToSegments(groupedRoute);
      final routeDetails = _extractRouteDetails(groupedRoute);
      
      final routeResult = RouteResult(
        id: i.toString(),
        segments: segments,
        totalDuration: groupedRoute.totalDuration,
        totalDistance: groupedRoute.totalDistance,
        startLocation: 'Mi ubicación',
        endLocation: 'Destino seleccionado',
        routeDetails: routeDetails, // Nueva información de recorridos
      );
      
      routes.add(routeResult);
    }
    
    return routes;
  }
  
  // Extraer detalles de recorridos de las líneas de bus
  static List<BusRouteDetails> _extractRouteDetails(GroupedRoute groupedRoute) {
    final Map<String, BusRouteDetails> uniqueRoutes = {};
    
    // Recorrer todas las rutas alternativas para obtener información completa
    for (final route in groupedRoute.alternativeRoutes) {
      for (final leg in route.legs) {
        if (leg.isTransit && leg.routeShortName != null && leg.routeStops.isNotEmpty) {
          final routeKey = leg.routeShortName!;
          
          if (!uniqueRoutes.containsKey(routeKey)) {
            // Extraer nombres de paradas y filtrar solo las relevantes para este viaje
            final allStops = leg.routeStops
                .map((stop) => stop.displayName)
                .where((name) => name.isNotEmpty && name != 'Parada')
                .toList();
            
            // Filtrar paradas para mostrar solo las del trayecto actual
            final relevantStops = _filterRelevantStops(allStops, leg);
            
            if (relevantStops.isNotEmpty) {
              uniqueRoutes[routeKey] = BusRouteDetails(
                busLine: leg.routeShortName!,
                stops: relevantStops,
                color: leg.routeColor,
                textColor: leg.routeTextColor,
              );
            }
          }
        }
      }
    }
    
    return uniqueRoutes.values.toList();
  }
  
  // Filtrar paradas para mostrar solo las del trayecto actual
  static List<String> _filterRelevantStops(List<String> allStops, OTPLeg leg) {
    if (allStops.isEmpty) return [];
    
    final fromStopName = leg.from?.name;
    final toStopName = leg.to?.name;
    
    // Si no tenemos información de paradas de origen y destino, mostrar todas
    if (fromStopName == null || toStopName == null) {
      return allStops;
    }
    
    // Encontrar índices de las paradas de origen y destino
    final fromIndex = allStops.indexWhere((stop) => stop.contains(fromStopName));
    final toIndex = allStops.indexWhere((stop) => stop.contains(toStopName));
    
    // Si no encontramos las paradas exactas, mostrar todas
    if (fromIndex == -1 || toIndex == -1) {
      return allStops;
    }
    
    // Determinar la dirección del viaje
    if (fromIndex < toIndex) {
      // Viaje hacia adelante: desde fromIndex hasta toIndex inclusive
      return allStops.sublist(fromIndex, toIndex + 1);
    } else {
      // Viaje hacia atrás: desde toIndex hasta fromIndex inclusive
      return allStops.sublist(toIndex, fromIndex + 1).reversed.toList();
    }
  }
  
  static List<RouteSegment> _convertGroupedRouteToSegments(GroupedRoute groupedRoute) {
    final List<RouteSegment> segments = [];
    
    for (final segment in groupedRoute.segments) {
      if (segment.isWalk) {
        segments.add(RouteSegment(
          type: SegmentType.walk,
          duration: segment.duration,
        ));
      } else if (segment.isTransit) {
        // Agrupar todas las líneas disponibles para esta parada
        final allLines = segment.getAllAvailableLines();
        
        // Calcular ETAs estáticos para este segmento
        final staticETAs = _calculateStaticETAsForSegment(segment, groupedRoute);
        
        segments.add(RouteSegment(
          type: SegmentType.bus,
          busLines: allLines,
          duration: segment.duration,
          departureStopName: segment.fromStopText,
          departureStopId: segment.fromStopId, // Agregar ID de parada para consultar ETAs del backend
          staticETAs: staticETAs,
          departureTime: groupedRoute.startTime,
          arrivalTime: groupedRoute.endTime,
        ));
      }
    }
    
    return segments;
  }

  // Calcular ETAs estáticos para un segmento agrupado
  static Map<String, List<int>>? _calculateStaticETAsForSegment(
    GroupedSegment segment, 
    GroupedRoute groupedRoute
  ) {
    if (!segment.isTransit || segment.busLines.isEmpty) return null;
    
    final now = DateTime.now();
    final Map<String, List<int>> etasByRoute = {};
    final Set<int> allETAsForSegment = {}; // Para combinar ETAs de todas las líneas
    
    // Para cada línea de bus en el segmento
    for (final busLine in segment.busLines) {
      final etas = <int>[];
      
      // Buscar horarios de todas las rutas alternativas para esta línea
      for (final route in groupedRoute.alternativeRoutes) {
        for (final leg in route.legs) {
          if (leg.isTransit && 
              leg.routeShortName == busLine.shortName &&
              leg.startTime.isAfter(now)) {
            
            final minutesUntil = leg.startTime.difference(now).inMinutes;
            if (minutesUntil > 0 && minutesUntil <= 120) {
              etas.add(minutesUntil);
              allETAsForSegment.add(minutesUntil);
            }
          }
        }
      }
      
      // Generar ETAs adicionales simulados si no hay suficientes datos reales
      if (etas.isEmpty) {
        final baseMinutes = groupedRoute.startTime.difference(now).inMinutes;
        if (baseMinutes > 0 && baseMinutes <= 120) {
          // Generar horarios simulados con variación por línea
          final lineIndex = segment.busLines.indexOf(busLine);
          final variation = lineIndex * 5; // Variación de 5 min entre líneas
          
          final simulatedETAs = [
            baseMinutes + variation,
            if (baseMinutes + variation + 12 <= 120) baseMinutes + variation + 12,
            if (baseMinutes + variation + 25 <= 120) baseMinutes + variation + 25,
          ].where((eta) => eta > 0 && eta <= 120).toList();
          
          etas.addAll(simulatedETAs);
          allETAsForSegment.addAll(simulatedETAs);
        }
      }
      
      // Ordenar y limitar a 3 ETAs por línea
      etas.sort();
      if (etas.isNotEmpty) {
        etasByRoute[busLine.shortName] = etas.take(3).toList();
      }
    }
    
    // Si hay múltiples líneas agrupadas, crear una entrada combinada
    if (segment.busLines.length > 1 && allETAsForSegment.isNotEmpty) {
      final combinedETAs = allETAsForSegment.toList()..sort();
      final combinedKey = segment.busLines.map((line) => line.shortName).join('/');
      etasByRoute[combinedKey] = combinedETAs.take(4).toList(); // Más ETAs para líneas combinadas
    }
    
    return etasByRoute.isNotEmpty ? etasByRoute : null;
  }
}

class GroupedRoute {
  final List<GroupedSegment> segments;
  final int totalDuration; // en minutos
  final double totalDistance; // en metros
  final DateTime startTime;
  final DateTime endTime;
  final List<OTPRoute> alternativeRoutes; // Rutas alternativas con las mismas paradas
  
  GroupedRoute({
    required this.segments,
    required this.totalDuration,
    required this.totalDistance,
    required this.startTime,
    required this.endTime,
    required this.alternativeRoutes,
  });
  
  factory GroupedRoute.fromOTPRoute(OTPRoute route) {
    final List<GroupedSegment> segments = [];
    
    for (final leg in route.legs) {
      segments.add(GroupedSegment.fromOTPLeg(leg));
    }
    
    return GroupedRoute(
      segments: segments,
      totalDuration: route.durationInMinutes,
      totalDistance: route.walkDistance,
      startTime: route.startTime,
      endTime: route.endTime,
      alternativeRoutes: [route],
    );
  }
  
  // Agregar ruta alternativa que usa las mismas paradas
  void addAlternativeRoute(OTPRoute route) {
    alternativeRoutes.add(route);
    
    // Actualizar segmentos con nuevas líneas de bus
    for (int i = 0; i < segments.length && i < route.legs.length; i++) {
      final leg = route.legs[i];
      if (leg.isTransit && segments[i].isTransit) {
        segments[i].addAlternativeLine(leg);
      }
    }
  }
  
  // Obtener el mejor tiempo (más rápido entre las alternativas)
  int get bestDuration {
    return alternativeRoutes
        .map((r) => r.durationInMinutes)
        .reduce((a, b) => a < b ? a : b);
  }
  
  // Obtener todas las líneas únicas disponibles
  List<String> get allAvailableLines {
    final Set<String> lines = {};
    
    for (final segment in segments) {
      if (segment.isTransit) {
        lines.addAll(segment.getAllAvailableLines());
      }
    }
    
    return lines.toList()..sort();
  }
}

class GroupedSegment {
  final String mode;
  final int duration; // en minutos
  final double distance; // en metros
  final String? fromStopName;
  final String? toStopName;
  final String? fromStopId;
  final String? toStopId;
  final List<BusLineInfo> busLines; // Todas las líneas disponibles para este segmento
  
  GroupedSegment({
    required this.mode,
    required this.duration,
    required this.distance,
    this.fromStopName,
    this.toStopName,
    this.fromStopId,
    this.toStopId,
    this.busLines = const [],
  });
  
  factory GroupedSegment.fromOTPLeg(OTPLeg leg) {
    final List<BusLineInfo> busLines = [];
    
    if (leg.isTransit && leg.routeShortName != null) {
      busLines.add(BusLineInfo(
        shortName: leg.routeShortName!,
        longName: leg.routeLongName,
        headsign: leg.tripHeadsign,
        color: leg.routeColor,
        textColor: leg.routeTextColor,
      ));
    }
    
    return GroupedSegment(
      mode: leg.mode,
      duration: leg.durationInMinutes,
      distance: leg.distance,
      fromStopName: leg.from?.name,
      toStopName: leg.to?.name,
      fromStopId: leg.from?.stopId,
      toStopId: leg.to?.stopId,
      busLines: busLines,
    );
  }
  
  // Agregar línea alternativa para el mismo segmento
  void addAlternativeLine(OTPLeg leg) {
    if (leg.isTransit && leg.routeShortName != null) {
      // Verificar que no esté duplicada
      final exists = busLines.any((line) => line.shortName == leg.routeShortName);
      
      if (!exists) {
        busLines.add(BusLineInfo(
          shortName: leg.routeShortName!,
          longName: leg.routeLongName,
          headsign: leg.tripHeadsign,
          color: leg.routeColor,
          textColor: leg.routeTextColor,
        ));
      }
    }
  }
  
  bool get isWalk => mode == 'WALK';
  bool get isTransit => mode != 'WALK';
  
  // Obtener todas las líneas disponibles como lista de strings
  List<String> getAllAvailableLines() {
    return busLines.map((line) => line.shortName).toList()..sort();
  }
  
  // Obtener texto de parada de origen
  String get fromStopText {
    return fromStopName ?? 'Parada de origen';
  }
  
  // Obtener texto de parada de destino
  String get toStopText {
    return toStopName ?? 'Parada de destino';
  }
}

class BusLineInfo {
  final String shortName;
  final String? longName;
  final String? headsign;
  final String? color;
  final String? textColor;
  
  BusLineInfo({
    required this.shortName,
    this.longName,
    this.headsign,
    this.color,
    this.textColor,
  });
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BusLineInfo && other.shortName == shortName;
  }
  
  @override
  int get hashCode => shortName.hashCode;
}