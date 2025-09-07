import 'package:flutter/material.dart';
import '../widgets/route_results_list.dart';
import '../main.dart';
import '../services/geocoding_service.dart';
import '../services/enhanced_route_search_service.dart';
import '../services/places_service.dart';

class RouteSearchResultsScreen extends StatefulWidget {
  final String origin;
  final String destination;
  final PlacePrediction? destinationPlace;

  const RouteSearchResultsScreen({
    Key? key,
    required this.origin,
    required this.destination,
    this.destinationPlace,
  }) : super(key: key);

  @override
  State<RouteSearchResultsScreen> createState() => _RouteSearchResultsScreenState();
}

class _RouteSearchResultsScreenState extends State<RouteSearchResultsScreen> {
  List<RouteResult> routes = [];
  bool isLoading = true;
  String? errorMessage;
  PlacePrediction? destinationPlace;
  RouteSearchStats? searchStats;

  @override
  void initState() {
    super.initState();
    destinationPlace = widget.destinationPlace;
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      // Obtener coordenadas de origen (ubicación actual)
      final originCoords = await GeocodingService.getCurrentLocation();
      if (originCoords == null) {
        throw Exception('No se pudo obtener la ubicación actual');
      }
      // Obtener coordenadas de destino
      PlaceCoordinates? destinationCoords;
      
      // Si tenemos un placeId del destino, usarlo para obtener coordenadas precisas
      if (destinationPlace?.placeId != null) {
        destinationCoords = await GeocodingService.getPlaceCoordinates(
          destinationPlace!.placeId
        );
      }
      
      // Si no tenemos coordenadas del destino, intentar geocodificar la dirección
      if (destinationCoords == null) {
        destinationCoords = await GeocodingService.geocodeAddress(widget.destination);
      }
      
      if (destinationCoords == null) {
        throw Exception('No se pudo encontrar la ubicación del destino');
      }


      // Usar el servicio de búsqueda múltiple para obtener más opciones
      final convertedRoutes = await EnhancedRouteSearchService.searchMultipleRouteOptions(
        fromLat: originCoords.latitude,
        fromLon: originCoords.longitude,
        toLat: destinationCoords.latitude,
        toLon: destinationCoords.longitude,
        dateTime: DateTime.now(),
      );

      // Generar estadísticas de búsqueda
      final stats = EnhancedRouteSearchService.getSearchStats(convertedRoutes);

      setState(() {
        routes = convertedRoutes;
        searchStats = stats;
        isLoading = false;
      });

    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.toString();
        routes = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Resultados de Búsqueda',
          style: TextStyle(fontFamily: 'Arial'),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Header con información de la búsqueda
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.origin,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.destination,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Estadísticas de búsqueda
                if (searchStats != null && !isLoading) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1639).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Color(0xFF0A1639),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            searchStats.toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF0A1639),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Lista de resultados
          Expanded(
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Buscando rutas...'),
                      ],
                    ),
                  )
                : errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error al buscar rutas',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadRoutes,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : RouteResultsList(
                        routes: routes,
                        onRouteSelected: _onRouteSelected,
                      ),
          ),
        ],
      ),
    );
  }

  void _onRouteSelected(RouteResult route) {
    // Navegar directamente al modo navegación
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => NavigationPage(
          selectedRoute: route,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;

          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }
}