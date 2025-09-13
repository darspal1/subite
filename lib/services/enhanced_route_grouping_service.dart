import '../widgets/route_results_list.dart';
import '../widgets/route_result_card.dart';

class EnhancedRouteGroupingService {
  /// Agrupa rutas por similitud de itinerario (paradas clave + líneas)
  static List<RouteResult> groupByItinerarySimilarity(List<RouteResult> routes) {
    if (routes.isEmpty) return routes;

    final Map<String, RouteGroup> groups = {};
    
    for (final route in routes) {
      final itineraryKey = _generateItineraryKey(route);
      
      if (groups.containsKey(itineraryKey)) {
        groups[itineraryKey]!.routes.add(route);

        // Mantener la ruta más rápida como representativa
        if (route.totalDuration < groups[itineraryKey]!.representativeRoute.totalDuration) {
          groups[itineraryKey]!.representativeRoute = route;
        }
      } else {
        groups[itineraryKey] = RouteGroup(
          key: itineraryKey,
          routes: [route],
          representativeRoute: route,
        );
      }
    }

    return groups.values.map((group) => _createGroupedRoute(group)).toList();
  }

  /// Genera clave única basada en la secuencia completa de paradas de bus
  static String _generateItineraryKey(RouteResult route) {
    final busStops = <String>[];
    
    // Extraer secuencia completa de paradas de todos los tramos de bus
    for (final segment in route.segments) {
      if (segment.type == SegmentType.bus) {
        final departureStop = _normalizeStopId(segment.departureStopId ?? segment.departureStopName ?? '');
        if (departureStop.isNotEmpty) {
          busStops.add(departureStop);
        }
      }
    }
    
    // Si no hay paradas de bus, usar tipo de ruta (walk/bicycle)
    if (busStops.isEmpty) {
      final nonBusTypes = route.segments
          .where((s) => s.type != SegmentType.bus)
          .map((s) => s.type.toString())
          .toSet()
          .join('_');
      return 'non_transit:$nonBusTypes';
    }
    
    final key = 'transit:${busStops.join('>')}'; 

    return key;
  }
  
  /// Normaliza ID de parada para agrupación consistente
  static String _normalizeStopId(String stopId) {
    if (stopId.isEmpty) return '';
    
    // Extraer número de parada si tiene formato "STM-MVD:123" o similar
    if (stopId.contains(':')) {
      return stopId.split(':').last;
    }
    
    // Limpiar nombre de parada para usar como clave
    return stopId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Crea ruta agrupada combinando múltiples horarios para todos los tramos
  static RouteResult _createGroupedRoute(RouteGroup group) {
    if (group.routes.length == 1) {
      return group.routes.first;
    }

    final representative = group.representativeRoute;
    final combinedSegments = <RouteSegment>[];
    
    // Agrupar por cada segmento, considerando todos los tramos de bus
    for (int i = 0; i < representative.segments.length; i++) {
      final segment = representative.segments[i];
      
      if (segment.type == SegmentType.bus) {
        // Combinar líneas de todas las rutas del grupo para este tramo específico
        final allBusLines = <String>{};
        final allETAs = <String, Set<int>>{};
        
        for (final route in group.routes) {
          if (i < route.segments.length && route.segments[i].type == SegmentType.bus) {
            final routeSegment = route.segments[i];
            
            // Solo agrupar si es la misma parada de salida
            final sameStop = _normalizeStopId(routeSegment.departureStopId ?? routeSegment.departureStopName ?? '') ==
                           _normalizeStopId(segment.departureStopId ?? segment.departureStopName ?? '');
            
            if (sameStop) {
              allBusLines.addAll(routeSegment.busLines);
              
              // ETAs se manejan ahora directamente desde departureTime
            }
          }
        }
        
        combinedSegments.add(RouteSegment(
          type: segment.type,
          busLines: allBusLines.toList()..sort(),
          duration: segment.duration,
          departureStopName: segment.departureStopName,
          departureStopId: segment.departureStopId,
          departureTime: segment.departureTime,
          arrivalTime: segment.arrivalTime,
          distance: segment.distance,
        ));
      } else {
        combinedSegments.add(segment);
      }
    }

    return RouteResult(
      id: 'grouped_${group.key}',
      segments: combinedSegments,
      totalDuration: representative.totalDuration,
      totalDistance: representative.totalDistance,
      startLocation: representative.startLocation,
      endLocation: representative.endLocation,
      routeDetails: representative.routeDetails,
    );
  }


}

class RouteGroup {
  final String key;
  final List<RouteResult> routes;
  RouteResult representativeRoute;

  RouteGroup({
    required this.key,
    required this.routes,
    required this.representativeRoute,
  });
}