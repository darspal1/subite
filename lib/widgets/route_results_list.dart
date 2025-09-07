import 'package:flutter/material.dart';
import 'route_result_card.dart';

class RouteResultsList extends StatelessWidget {
  final List<RouteResult> routes;
  final Function(RouteResult)? onRouteSelected;

  const RouteResultsList({
    Key? key,
    required this.routes,
    this.onRouteSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No se encontraron rutas',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: routes.length,
      itemBuilder: (context, index) {
        final route = routes[index];
        return RouteResultCard(
          segments: route.segments,
          totalDuration: route.totalDuration,
          totalDistance: route.totalDistance,
          routeDetails: route.routeDetails,
          onTap: () => onRouteSelected?.call(route),
        );
      },
    );
  }
}

// Modelo para una ruta completa
class RouteResult {
  final String id;
  final List<RouteSegment> segments;
  final int totalDuration; // en minutos
  final double totalDistance; // en metros
  final String startLocation;
  final String endLocation;
  final List<BusRouteDetails>? routeDetails; // Nueva información de recorridos

  RouteResult({
    required this.id,
    required this.segments,
    required this.totalDuration,
    required this.totalDistance,
    required this.startLocation,
    required this.endLocation,
    this.routeDetails,
  });


}