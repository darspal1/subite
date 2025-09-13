import 'otp_service.dart';
import 'route_converter_service.dart';
import 'enhanced_route_grouping_service.dart';
import 'nearby_stops_service.dart';
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
    print('=== INICIANDO BÚSQUEDA DE RUTAS ===');
    print('Origen: $fromLat, $fromLon');
    print('Destino: $toLat, $toLon');
    
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
          numItineraries: 15,
          maxWalkDistance: 600,
        ),
        
        // Búsqueda 3: Menos caminata (para usuarios con movilidad reducida)
        OTPService.planRoute(
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          dateTime: dateTime,
          numItineraries: 8,
          maxWalkDistance: 400,
        ),
        
        // Búsqueda 4: Con tiempo diferente para obtener más variedad
        OTPService.planRoute(
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          dateTime: dateTime?.add(const Duration(minutes: 15)),
          numItineraries: 10,
          maxWalkDistance: 700,
        ),
      ];
      
      // Ejecutar búsquedas en paralelo
      final results = await Future.wait(searchFutures);
      print('Búsquedas completadas: ${results.length}');
      
      // Combinar todos los resultados
      for (int i = 0; i < results.length; i++) {
        final routeList = results[i];
        print('Búsqueda ${i + 1}: ${routeList.length} rutas');
        allRoutes.addAll(routeList);
      }
      
      print('Total rutas encontradas: ${allRoutes.length}');
      
      // Agregar rutas adicionales (bicicleta y caminata)
      try {
        final bicycleRoute = await OTPService.planBicycleRoute(
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          dateTime: dateTime,
        );
        allRoutes.addAll(bicycleRoute);
      } catch (e) {
        // Error silencioso
      }
      
      try {
        final walkRoute = await OTPService.planWalkRoute(
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          dateTime: dateTime,
        );
        allRoutes.addAll(walkRoute);
      } catch (e) {
        // Error silencioso
      }
      
    } catch (e) {
      // Si falla alguna búsqueda, continuar con las que funcionaron
      print('ERROR EN BÚSQUEDA MÚLTIPLE: $e');
      print('Stack trace: ${StackTrace.current}');
    }
    
    // Convertir TODAS las rutas (sin eliminar duplicados aún)
    final routeResults = RouteConverterService.convertOTPRoutesToRouteResults(allRoutes);
    print('Rutas convertidas: ${routeResults.length} (antes de agrupación)');
    
    // Filtrar rutas con caminatas iniciales excesivas (más de 15 minutos)
    final filteredRoutes = routeResults.where((route) {
      if (route.segments.isEmpty) return false;
      final firstSegment = route.segments.first;
      if (firstSegment.type == SegmentType.walk && firstSegment.duration != null) {
        return firstSegment.duration! <= 15; // Máximo 15 minutos de caminata inicial
      }
      return true;
    }).toList();
    
    // Separar rutas por tipo
    final transitRoutes = filteredRoutes.where((r) => r.segments.any((s) => s.type == SegmentType.bus)).toList();
    final bicycleRoutes = filteredRoutes.where((r) => r.segments.any((s) => s.type == SegmentType.bicycle)).toList();
    final walkRoutes = filteredRoutes.where((r) => r.segments.every((s) => s.type == SegmentType.walk)).toList();
    
    print('Rutas de tránsito antes de agrupación: ${transitRoutes.length}');
    
    // APLICAR AGRUPACIÓN SOLO A RUTAS DE TRÁNSITO
    final groupedTransitRoutes = EnhancedRouteGroupingService.groupByItinerarySimilarity(transitRoutes);
    print('Rutas de tránsito después de agrupación: ${groupedTransitRoutes.length}');
    
    // Ordenar por duración
    groupedTransitRoutes.sort((a, b) => a.totalDuration.compareTo(b.totalDuration));
    bicycleRoutes.sort((a, b) => a.totalDuration.compareTo(b.totalDuration));
    walkRoutes.sort((a, b) => a.totalDuration.compareTo(b.totalDuration));
    
    final finalResults = <RouteResult>[];
    finalResults.addAll(groupedTransitRoutes.take(8));
    
    // Crear tarjeta combinada si hay rutas de bicicleta y/o caminata
    if (bicycleRoutes.isNotEmpty || walkRoutes.isNotEmpty) {
      final combinedRoute = _createCombinedAlternativeRoute(
        bicycleRoute: bicycleRoutes.isNotEmpty ? bicycleRoutes.first : null,
        walkRoute: walkRoutes.isNotEmpty ? walkRoutes.first : null,
      );
      finalResults.add(combinedRoute);
    }
    
    print('=== BÚSQUEDA COMPLETADA: ${finalResults.length} rutas ===');
    return finalResults;
  }
  
  // Crear tarjeta combinada para rutas alternativas
  static RouteResult _createCombinedAlternativeRoute({
    RouteResult? bicycleRoute,
    RouteResult? walkRoute,
  }) {
    final segments = <RouteSegment>[];
    
    // Agregar segmento de bicicleta si existe
    if (bicycleRoute != null) {
      segments.addAll(bicycleRoute.segments);
    }
    
    // Agregar separador
    segments.add(RouteSegment(type: SegmentType.separator));
    
    // Agregar segmento de caminata si existe
    if (walkRoute != null) {
      segments.addAll(walkRoute.segments);
    }
    
    return RouteResult(
      id: 'combined_alternatives',
      segments: segments,
      totalDuration: 0, // No mostrar duración total
      totalDistance: 0, // No mostrar distancia total
      startLocation: 'Mi ubicación',
      endLocation: 'Destino seleccionado',
      routeDetails: null,
    );
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
        groupedRoutes: 0,
      );
    }
    
    final durations = routes.map((r) => r.totalDuration).toList();
    final allBusLines = <String>{};
    int groupedCount = 0;
    
    for (final route in routes) {
      for (final segment in route.segments) {
        if (segment.type == SegmentType.bus) {
          allBusLines.addAll(segment.busLines);
          // Contar como agrupada si tiene más de una línea en el mismo segmento
          if (segment.busLines.length > 1) {
            groupedCount++;
            break;
          }
        }
      }
    }
    
    return RouteSearchStats(
      totalRoutes: routes.length,
      averageDuration: (durations.reduce((a, b) => a + b) / durations.length).round(),
      shortestDuration: durations.reduce((a, b) => a < b ? a : b),
      longestDuration: durations.reduce((a, b) => a > b ? a : b),
      totalBusLines: allBusLines.length,
      uniqueStops: 0,
      groupedRoutes: groupedCount,
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
  final int groupedRoutes;
  
  RouteSearchStats({
    required this.totalRoutes,
    required this.averageDuration,
    required this.shortestDuration,
    required this.longestDuration,
    required this.totalBusLines,
    required this.uniqueStops,
    required this.groupedRoutes,
  });
  
  @override
  String toString() {
    final groupText = groupedRoutes > 0 ? ' • $groupedRoutes agrupadas' : '';
    return 'Encontradas $totalRoutes rutas • $totalBusLines líneas disponibles$groupText • ${shortestDuration}-${longestDuration} min';
  }
}