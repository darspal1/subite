import 'otp_service.dart';
import 'realtime_interest_service.dart';
import 'enhanced_route_grouping_service.dart';
import '../widgets/route_results_list.dart';
import '../widgets/route_result_card.dart';

class RouteConverterService {
  // Convertir rutas OTP directamente a RouteResult
  static List<RouteResult> convertOTPRoutesToRouteResults(List<OTPRoute> otpRoutes) {
    final List<RouteResult> routes = [];
    
    // Registrar interés adicional para todas las paradas
    _registerInterestForAllRoutes(otpRoutes);
    
    for (int i = 0; i < otpRoutes.length; i++) {
      final otpRoute = otpRoutes[i];
      final segments = _convertOTPRouteToSegments(otpRoute);
      
      // Solo agregar rutas válidas (con segmentos de bus o solo caminata/bicicleta)
      final hasTransitSegments = segments.any((s) => s.type == SegmentType.bus);
      final isNonTransitRoute = segments.every((s) => 
        s.type == SegmentType.walk || s.type == SegmentType.bicycle
      );
      
      if (hasTransitSegments || isNonTransitRoute) {
        final routeResult = RouteResult(
          id: i.toString(),
          segments: segments,
          totalDuration: otpRoute.durationInMinutes,
          totalDistance: otpRoute.walkDistance,
          startLocation: 'Mi ubicación',
          endLocation: 'Destino seleccionado',
          routeDetails: null,
        );
        
        routes.add(routeResult);
      }
    }
    
    // No aplicar agrupación aquí - se hace en EnhancedRouteSearchService
    return routes;
  }
  
  static List<RouteSegment> _convertOTPRouteToSegments(OTPRoute otpRoute) {
    final List<RouteSegment> segments = [];
    
    for (final leg in otpRoute.legs) {
      if (leg.isWalk) {
        segments.add(RouteSegment(
          type: SegmentType.walk,
          duration: leg.durationInMinutes,
          distance: leg.distance,
        ));
      } else if (leg.isBicycle) {
        segments.add(RouteSegment(
          type: SegmentType.bicycle,
          duration: leg.durationInMinutes,
          distance: leg.distance,
        ));
      } else if (leg.isTransit) {
        segments.add(RouteSegment(
          type: SegmentType.bus,
          busLines: leg.routeShortName != null ? [leg.routeShortName!] : [],
          duration: leg.durationInMinutes,
          departureStopName: leg.from?.name,
          departureStopId: leg.from?.stopId,
          departureTime: leg.startTime,
          arrivalTime: leg.endTime,
        ));
      }
    }
    
    return segments;
  }
  

  
  // Registrar interés para todas las líneas y paradas
  static void _registerInterestForAllRoutes(List<OTPRoute> routes) {
    final Set<String> lines = {};
    final Set<String> stops = {};
    
    for (final route in routes) {
      for (final leg in route.legs) {
        if (leg.isTransit) {
          if (leg.routeShortName != null) {
            lines.add(leg.routeShortName!);
          }
          if (leg.from?.stopId != null) {
            final stopId = leg.from!.stopId!;
            final numericStopId = stopId.contains(':') ? stopId.split(':').last : stopId;
            stops.add(numericStopId);
          }
        }
      }
    }
    
    if (lines.isNotEmpty || stops.isNotEmpty) {
      RealtimeInterestService.registerInterest(
        lines: lines.toList(),
        stops: stops.toList(),
      );
    }
  }
}