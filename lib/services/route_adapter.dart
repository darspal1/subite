import '../widgets/route_result_card.dart';
import '../widgets/route_results_list.dart';
import 'otp_service.dart';
import 'route_grouping_service.dart';

class RouteAdapter {
  // Método principal mejorado que agrupa rutas por paradas
  static List<RouteResult> convertOTPRoutesToRouteResults(List<OTPRoute> otpRoutes) {
    // Usar el nuevo servicio de agrupación
    final groupedRoutes = RouteGroupingService.groupRoutesByStops(otpRoutes);
    return RouteGroupingService.convertGroupedRoutesToRouteResults(groupedRoutes);
  }

  // Método legacy para compatibilidad (mantener por si se necesita)
  static List<RouteResult> convertOTPRoutesToRouteResultsLegacy(List<OTPRoute> otpRoutes) {
    final List<RouteResult> routes = [];
    
    for (int i = 0; i < otpRoutes.length; i++) {
      final otpRoute = otpRoutes[i];
      final segments = _convertLegsToSegments(otpRoute.legs);
      
      final routeResult = RouteResult(
        id: i.toString(),
        segments: segments,
        totalDuration: otpRoute.durationInMinutes,
        totalDistance: otpRoute.walkDistance,
        startLocation: 'Mi ubicación',
        endLocation: 'Destino seleccionado',
      );
      
      routes.add(routeResult);
    }
    
    return routes;
  }
  
  static List<RouteSegment> _convertLegsToSegments(List<OTPLeg> legs) {
    final List<RouteSegment> segments = [];
    
    for (final leg in legs) {
      if (leg.isWalk) {
        // Agregar segmento de caminata
        segments.add(RouteSegment(
          type: SegmentType.walk,
          duration: leg.durationInMinutes,
        ));
      } else if (leg.isTransit) {
        // Agregar segmento de transporte público
        final busLines = <String>[];
        
        // Usar routeShortName si está disponible
        if (leg.routeShortName != null && leg.routeShortName!.isNotEmpty) {
          busLines.add(leg.routeShortName!);
        } else if (leg.routeLongName != null && leg.routeLongName!.isNotEmpty) {
          busLines.add(leg.routeLongName!);
        } else {
          // Fallback genérico
          busLines.add('Bus');
        }
        
        // Calcular ETAs estáticos para esta línea
        final staticETAs = _calculateStaticETAsForLeg(leg);
        
        segments.add(RouteSegment(
          type: SegmentType.bus,
          busLines: busLines,
          duration: leg.durationInMinutes,
          departureStopName: leg.from?.name ?? 'Parada',
          departureStopId: leg.from?.stopId, // Agregar ID de parada para consultar ETAs del backend
          staticETAs: staticETAs,
          departureTime: leg.startTime,
          arrivalTime: leg.endTime,
        ));
      }
    }
    
    // Combinar segmentos consecutivos del mismo tipo si es necesario
    return _combineConsecutiveSegments(segments);
  }

  // Calcular ETAs estáticos para un leg de transporte público
  static Map<String, List<int>>? _calculateStaticETAsForLeg(OTPLeg leg) {
    if (!leg.isTransit || leg.routeShortName == null) return null;
    
    // Generar ETAs simulados basados en el horario programado
    // En una implementación real, esto vendría de los datos GTFS
    final now = DateTime.now();
    final departureTime = leg.startTime;
    
    if (departureTime.isBefore(now)) {
      return null; // No mostrar ETAs para horarios pasados
    }
    
    final minutesUntilDeparture = departureTime.difference(now).inMinutes;
    
    // Generar 2-3 horarios adicionales después del programado
    final etas = <int>[
      minutesUntilDeparture,
      if (minutesUntilDeparture + 15 <= 120) minutesUntilDeparture + 15,
      if (minutesUntilDeparture + 30 <= 120) minutesUntilDeparture + 30,
    ].where((eta) => eta > 0 && eta <= 120).toList();
    
    if (etas.isEmpty) return null;
    
    return {
      leg.routeShortName!: etas,
    };
  }
  
  static List<RouteSegment> _combineConsecutiveSegments(List<RouteSegment> segments) {
    if (segments.isEmpty) return segments;
    
    final List<RouteSegment> combinedSegments = [];
    RouteSegment? currentSegment;
    
    for (final segment in segments) {
      if (currentSegment == null) {
        currentSegment = segment;
      } else if (currentSegment.type == segment.type && 
                 currentSegment.type == SegmentType.bus) {
        // Combinar líneas de bus consecutivas
        final combinedBusLines = <String>[
          ...currentSegment.busLines,
          ...segment.busLines,
        ];
        
        currentSegment = RouteSegment(
          type: SegmentType.bus,
          busLines: combinedBusLines,
          duration: (currentSegment.duration ?? 0) + (segment.duration ?? 0),
        );
      } else {
        // Agregar el segmento actual y comenzar uno nuevo
        combinedSegments.add(currentSegment);
        currentSegment = segment;
      }
    }
    
    // Agregar el último segmento
    if (currentSegment != null) {
      combinedSegments.add(currentSegment);
    }
    
    return combinedSegments;
  }
}