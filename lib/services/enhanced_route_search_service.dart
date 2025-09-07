import 'otp_service.dart';
import 'route_grouping_service.dart';
import '../widgets/route_results_list.dart';
import '../widgets/route_result_card.dart';

class EnhancedRouteSearchService {
  // Realizar múltiples búsquedas para obtener más opciones de rutas
  static Future<List<RouteResult>> searchMultipleRouteOptions({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    DateTime? dateTime,
  }) async {
    final List<OTPRoute> allRoutes = [];
    
    try {
      // Realizar múltiples búsquedas con diferentes parámetros
      final searchFutures = [
        // Búsqueda 1: Optimizada por tiempo (rápida)
        OTPService.planRoute(
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          dateTime: dateTime,
          numItineraries: 5,
          maxWalkDistance: 800,
        ),
        
        // Búsqueda 2: Más opciones de caminata
        OTPService.planRoute(
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          dateTime: dateTime,
          numItineraries: 4,
          maxWalkDistance: 1200,
        ),
        
        // Búsqueda 3: Menos caminata (para usuarios con movilidad reducida)
        OTPService.planRoute(
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          dateTime: dateTime,
          numItineraries: 3,
          maxWalkDistance: 500,
        ),
      ];
      
      // Ejecutar búsquedas en paralelo
      final results = await Future.wait(searchFutures);
      
      // Combinar todos los resultados
      for (final routeList in results) {
        allRoutes.addAll(routeList);
      }
      
      // Buscar rutas adicionales con horarios diferentes
      if (dateTime != null) {
        final additionalRoutes = await _searchWithTimeVariations(
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          baseTime: dateTime,
        );
        allRoutes.addAll(additionalRoutes);
      }
      
    } catch (e) {
      // Si falla alguna búsqueda, continuar con las que funcionaron
      print('Error en búsqueda múltiple: $e');
    }
    
    // Eliminar duplicados y agrupar por paradas
    final uniqueRoutes = _removeDuplicateRoutes(allRoutes);
    final groupedRoutes = RouteGroupingService.groupRoutesByStops(uniqueRoutes);
    
    // Convertir a formato de la aplicación
    final routeResults = RouteGroupingService.convertGroupedRoutesToRouteResults(groupedRoutes);
    
    // Ordenar por duración y limitar resultados
    routeResults.sort((a, b) => a.totalDuration.compareTo(b.totalDuration));
    
    return routeResults.take(8).toList(); // Máximo 8 opciones
  }
  
  // Buscar rutas con variaciones de tiempo para obtener más opciones
  static Future<List<OTPRoute>> _searchWithTimeVariations({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required DateTime baseTime,
  }) async {
    final List<OTPRoute> routes = [];
    
    try {
      // Buscar 10 minutos antes
      final earlierRoutes = await OTPService.planRoute(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: toLat,
        toLon: toLon,
        dateTime: baseTime.subtract(const Duration(minutes: 10)),
        numItineraries: 3,
        maxWalkDistance: 1000,
      );
      routes.addAll(earlierRoutes);
      
      // Buscar 10 minutos después
      final laterRoutes = await OTPService.planRoute(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: toLat,
        toLon: toLon,
        dateTime: baseTime.add(const Duration(minutes: 10)),
        numItineraries: 3,
        maxWalkDistance: 1000,
      );
      routes.addAll(laterRoutes);
      
    } catch (e) {
      // Error silencioso
    }
    
    return routes;
  }
  
  // Eliminar rutas duplicadas basándose en criterios similares
  static List<OTPRoute> _removeDuplicateRoutes(List<OTPRoute> routes) {
    final Map<String, OTPRoute> uniqueRoutes = {};
    
    for (final route in routes) {
      final key = _generateRouteKey(route);
      
      // Mantener la ruta más rápida si hay duplicados
      if (!uniqueRoutes.containsKey(key) || 
          route.durationInMinutes < uniqueRoutes[key]!.durationInMinutes) {
        uniqueRoutes[key] = route;
      }
    }
    
    return uniqueRoutes.values.toList();
  }
  
  // Generar clave única para identificar rutas similares
  static String _generateRouteKey(OTPRoute route) {
    final List<String> keyParts = [];
    
    for (final leg in route.legs) {
      if (leg.isTransit) {
        // Usar línea de bus y paradas principales
        final routeName = leg.routeShortName ?? leg.routeLongName ?? 'bus';
        final fromStop = leg.from?.stopId ?? leg.from?.name ?? 'unknown';
        final toStop = leg.to?.stopId ?? leg.to?.name ?? 'unknown';
        keyParts.add('$routeName:$fromStop-$toStop');
      } else if (leg.isWalk) {
        // Agrupar caminatas por distancia aproximada
        final walkDistance = (leg.distance / 200).round() * 200; // Redondear a 200m
        keyParts.add('walk:$walkDistance');
      }
    }
    
    return keyParts.join('|');
  }
  
  // Obtener estadísticas de las rutas encontradas
  static RouteSearchStats getSearchStats(List<RouteResult> routes) {
    if (routes.isEmpty) {
      return RouteSearchStats(
        totalRoutes: 0,
        averageDuration: 0,
        shortestDuration: 0,
        longestDuration: 0,
        totalBusLines: 0,
        uniqueStops: 0,
      );
    }
    
    final durations = routes.map((r) => r.totalDuration).toList();
    final allBusLines = <String>{};
    final allStops = <String>{};
    
    for (final route in routes) {
      for (final segment in route.segments) {
        if (segment.type == SegmentType.bus) {
          allBusLines.addAll(segment.busLines);
        }
      }
    }
    
    return RouteSearchStats(
      totalRoutes: routes.length,
      averageDuration: (durations.reduce((a, b) => a + b) / durations.length).round(),
      shortestDuration: durations.reduce((a, b) => a < b ? a : b),
      longestDuration: durations.reduce((a, b) => a > b ? a : b),
      totalBusLines: allBusLines.length,
      uniqueStops: allStops.length,
    );
  }
}

class RouteSearchStats {
  final int totalRoutes;
  final int averageDuration;
  final int shortestDuration;
  final int longestDuration;
  final int totalBusLines;
  final int uniqueStops;
  
  RouteSearchStats({
    required this.totalRoutes,
    required this.averageDuration,
    required this.shortestDuration,
    required this.longestDuration,
    required this.totalBusLines,
    required this.uniqueStops,
  });
  
  @override
  String toString() {
    return 'Encontradas $totalRoutes rutas • $totalBusLines líneas disponibles • ${shortestDuration}-${longestDuration} min';
  }
}