import '../widgets/route_results_list.dart';
import '../widgets/route_result_card.dart';

class RouteGroupingService {
  static const int _durationToleranceSeconds = 60; // 1 minuto de tolerancia

  /// Agrupa rutas similares basándose en duración y paradas de subida/bajada
  static List<RouteResult> groupSimilarRoutes(List<RouteResult> routes) {
    if (routes.isEmpty) return routes;

    final List<RouteGroup> groups = [];
    
    for (final route in routes) {
      final groupKey = _generateGroupKey(route);
      if (groupKey == null) {
        // Si no se puede agrupar, agregar como ruta individual
        groups.add(RouteGroup(
          key: 'individual_${route.id}',
          routes: [route],
          representativeRoute: route,
        ));
        continue;
      }

      // Buscar grupo existente
      RouteGroup? existingGroup;
      for (final group in groups) {
        if (_canJoinGroup(route, group, groupKey)) {
          existingGroup = group;
          break;
        }
      }

      if (existingGroup != null) {
        existingGroup.routes.add(route);
        // Actualizar ruta representativa si es necesario
        if (_isBetterRepresentative(route, existingGroup.representativeRoute)) {
          existingGroup.representativeRoute = route;
        }
      } else {
        // Crear nuevo grupo
        groups.add(RouteGroup(
          key: groupKey,
          routes: [route],
          representativeRoute: route,
        ));
      }
    }

    // Convertir grupos a rutas finales
    return groups.map((group) => _createGroupedRoute(group)).toList();
  }

  /// Genera clave única para agrupar rutas similares
  static String? _generateGroupKey(RouteResult route) {
    final busSegments = route.segments.where((s) => s.type == SegmentType.bus).toList();
    if (busSegments.isEmpty) return null;

    final firstBusSegment = busSegments.first;
    final lastBusSegment = busSegments.last;

    // Clave: duración_parada-origen_parada-destino
    final durationKey = route.totalDuration; // Usar duración en minutos
    final originStop = firstBusSegment.departureStopId ?? firstBusSegment.departureStopName ?? 'unknown';
    final destinationStop = lastBusSegment.departureStopId ?? lastBusSegment.departureStopName ?? 'unknown';

    return '${durationKey}_${originStop}_${destinationStop}';
  }

  /// Verifica si una ruta puede unirse a un grupo existente
  static bool _canJoinGroup(RouteResult route, RouteGroup group, String routeKey) {
    // Verificar clave base
    if (group.key != routeKey) return false;

    // Verificar tolerancia de duración más estricta
    final durationDiff = (route.totalDuration - group.representativeRoute.totalDuration).abs();
    return durationDiff <= (_durationToleranceSeconds / 60); // Convertir a minutos
  }

  /// Determina si una ruta es mejor representativa que la actual
  static bool _isBetterRepresentative(RouteResult candidate, RouteResult current) {
    // Priorizar rutas con más líneas de bus (más opciones)
    final candidateBusLines = candidate.segments
        .where((s) => s.type == SegmentType.bus)
        .expand((s) => s.busLines)
        .length;
    
    final currentBusLines = current.segments
        .where((s) => s.type == SegmentType.bus)
        .expand((s) => s.busLines)
        .length;

    if (candidateBusLines != currentBusLines) {
      return candidateBusLines > currentBusLines;
    }

    // Si tienen igual número de líneas, priorizar la más rápida
    return candidate.totalDuration < current.totalDuration;
  }

  /// Crea una ruta agrupada combinando múltiples rutas similares
  static RouteResult _createGroupedRoute(RouteGroup group) {
    if (group.routes.length == 1) {
      return group.routes.first;
    }

    final representative = group.representativeRoute;
    final allBusLines = <String>{};
    
    // Combinar todas las líneas de bus del grupo
    for (final route in group.routes) {
      for (final segment in route.segments) {
        if (segment.type == SegmentType.bus) {
          allBusLines.addAll(segment.busLines);
        }
      }
    }

    // Crear segmentos agrupados
    final groupedSegments = <RouteSegment>[];
    for (int i = 0; i < representative.segments.length; i++) {
      final segment = representative.segments[i];
      
      if (segment.type == SegmentType.bus) {
        // Para segmentos de bus, combinar todas las líneas del grupo
        final busSegmentsAtPosition = group.routes
            .where((r) => i < r.segments.length && r.segments[i].type == SegmentType.bus)
            .map((r) => r.segments[i])
            .toList();

        final combinedBusLines = <String>{};
        Map<String, List<int>>? combinedETAs;
        
        for (final busSegment in busSegmentsAtPosition) {
          combinedBusLines.addAll(busSegment.busLines);
          
          // ETAs se manejan ahora directamente desde departureTime
        }

        groupedSegments.add(RouteSegment(
          type: SegmentType.bus,
          busLines: combinedBusLines.toList()..sort(),
          duration: segment.duration,
          departureStopName: segment.departureStopName,
          departureStopId: segment.departureStopId,
          departureTime: segment.departureTime,
          arrivalTime: segment.arrivalTime,
          distance: segment.distance,
        ));
      } else {
        // Para segmentos no-bus, usar el representativo
        groupedSegments.add(segment);
      }
    }

    return RouteResult(
      id: 'grouped_${group.key}',
      segments: groupedSegments,
      totalDuration: representative.totalDuration,
      totalDistance: representative.totalDistance,
      startLocation: representative.startLocation,
      endLocation: representative.endLocation,
      routeDetails: representative.routeDetails,
    );
  }
}

/// Clase auxiliar para manejar grupos de rutas
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