import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'widgets/places_autocomplete_field.dart';
import 'services/places_service.dart';
import 'services/geocoding_service.dart';
import 'screens/route_search_results_screen.dart';

void main() {
  // Inicializar timezone database
  tz.initializeTimeZones();
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Color(0xFF0A1639), // bottom bar color
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarColor: Color(0xFF0A1639), // top bar color (optional, already set by AppBar)
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const UrbanMobilityApp());
}

class UrbanMobilityApp extends StatelessWidget {
  const UrbanMobilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Movilidad Urbana',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF3F2F1),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A1639),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(
            fontFamily: 'Arial',
            color: Color(0xFF0A0A0A),
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Arial',
            color: Color(0xFF0A0A0A),
          ),
          titleLarge: TextStyle(
            fontFamily: 'Arial',
            color: Color(0xFF0A0A0A),
            fontWeight: FontWeight.bold,
          ),
        ),
        fontFamily: 'Arial',
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _destinationController = TextEditingController();
  bool _isSearching = false;
  bool _showSuggestions = false;
  bool _isGettingLocation = false;
  String _locationStatus = 'Mi ubicación';
  PlacePrediction? _selectedPlace;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
      _locationStatus = 'Obteniendo ubicación...';
    });

    try {
      final location = await GeocodingService.getCurrentLocation();
      if (location != null) {
        setState(() {
          _locationStatus = 'Mi ubicación';
          _isGettingLocation = false;
        });
      } else {
        setState(() {
          _locationStatus = 'Ubicación no disponible';
          _isGettingLocation = false;
        });
      }
    } catch (e) {
      setState(() {
        _locationStatus = 'Error al obtener ubicación';
        _isGettingLocation = false;
      });
    }
  }

  void _onPlaceSelected(PlacePrediction place) {
    setState(() {
      _selectedPlace = place;
      _showSuggestions = false;
    });
    
    // Búsqueda automática al seleccionar un lugar con feedback inmediato
    _searchRoute();
  }

  void _onSuggestionsChanged(bool showSuggestions) {
    setState(() {
      _showSuggestions = showSuggestions;
    });
  }

  void _searchRoute() {
    if (_destinationController.text.trim().isEmpty) return;
    
    setState(() {
      _isSearching = true;
    });

    // Delay más corto y navegación más fluida
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
        
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => RouteSearchResultsScreen(
              origin: 'Mi ubicación',
              destination: _selectedPlace?.simplifiedDestination ?? _destinationController.text,
              destinationPlace: _selectedPlace,
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              // Transición suave de deslizamiento
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Subite!',
          style: TextStyle(fontFamily: 'Arial'),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Indicador de ubicación actual
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    _isGettingLocation ? Icons.location_searching : Icons.my_location,
                    color: _isGettingLocation ? Colors.orange : 
                           _locationStatus == 'Mi ubicación' ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Desde:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF666666),
                          ),
                        ),
                        Text(
                          _locationStatus,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0A0A0A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isGettingLocation)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    ),
                  if (!_isGettingLocation && _locationStatus != 'Mi ubicación')
                    IconButton(
                      onPressed: _getCurrentLocation,
                      icon: const Icon(Icons.refresh),
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '¿A dónde vas?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0A0A0A),
              ),
            ),
            const SizedBox(height: 8),
            PlacesAutocompleteField(
              controller: _destinationController,
              hintText: 'Ingresa tu destino',
              onPlaceSelected: _onPlaceSelected,
              onSuggestionsChanged: _onSuggestionsChanged,
              isLoading: _isSearching,
            ),
            const SizedBox(height: 24),
            // Solo mostrar el botón si no se están mostrando sugerencias
            if (!_showSuggestions)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSearching ? null : _searchRoute,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A1639),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Buscar Rutas',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                ],
              )
          ],
        ),
      ),
    );
  }
}

class RouteOptionsPage extends StatelessWidget {
  final String destination;
  
  const RouteOptionsPage({
    super.key,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Opciones de Ruta',
          style: TextStyle(fontFamily: 'Arial'),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Destino:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF666666),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Color(0xFF0A1639),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        destination,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0A0A0A),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              separatorBuilder: (context, index) => Container(
                height: 1,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(vertical: 8),
              ),
              itemBuilder: (context, index) {
                return RouteOptionCard(
                  routeNumber: index + 1,
                  onTap: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const NavigationPage(),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          // Transición suave de deslizamiento
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
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class RouteOptionCard extends StatelessWidget {
  final int routeNumber;
  final VoidCallback onTap;

  const RouteOptionCard({
    super.key,
    required this.routeNumber,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              // Triangular indicator
              Container(
                width: 0,
                height: 0,
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(width: 8, color: Colors.transparent),
                    right: BorderSide(width: 8, color: Colors.transparent),
                    bottom: BorderSide(width: 12, color: Color(0xFF0A1639)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ruta $routeNumber',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0A0A0A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tiempo estimado',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF666666),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Distancia',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Color(0xFF0A1639),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NavigationPage extends StatefulWidget {
  final dynamic selectedRoute;
  
  const NavigationPage({
    super.key,
    this.selectedRoute,
  });

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Navegación',
          style: TextStyle(fontFamily: 'Arial'),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              Navigator.popUntil(context, (route) => route.isFirst);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(
              icon: Icon(Icons.map),
              text: 'Mapa',
            ),
            Tab(
              icon: Icon(Icons.list),
              text: 'Pasos',
            ),
            Tab(
              icon: Icon(Icons.schedule),
              text: 'Horarios',
            ),
          ],
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFF3F2F1),
        child: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Mapa
            _buildMapTab(),
            
            // Tab 2: Instrucciones paso a paso
            _buildInstructionsTab(),
            
            // Tab 3: Horarios de paradas
            _buildSchedulesTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildMapTab() {
    return Column(
      children: [
        // Información de la ruta seleccionada
        if (widget.selectedRoute != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ruta Seleccionada:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0A0A0A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Duración: ${widget.selectedRoute?.totalDuration ?? 0} minutos',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF666666),
                  ),
                ),
                Text(
                  'Distancia: ${widget.selectedRoute != null ? (widget.selectedRoute.totalDistance / 1000).toStringAsFixed(1) : '0'} km',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
          ),
        
        // Área del mapa
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.map,
                    size: 80,
                    color: Color(0xFF0A1639),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Mapa de Navegación',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0A0A0A),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Próximamente: Mapa interactivo con la ruta',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF0A0A0A),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionsTab() {
    if (widget.selectedRoute == null) {
      return const Center(
        child: Text(
          'No hay ruta seleccionada',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey,
          ),
        ),
      );
    }

    // Aquí necesitarías convertir selectedRoute a OTPRoute
    // Por ahora mostramos un placeholder
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.navigation,
            size: 80,
            color: Color(0xFF0A1639),
          ),
          SizedBox(height: 16),
          Text(
            'Instrucciones de Navegación',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0A0A0A),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Próximamente: Instrucciones paso a paso',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF0A0A0A),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSchedulesTab() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.schedule,
            size: 80,
            color: Color(0xFF0A1639),
          ),
          SizedBox(height: 16),
          Text(
            'Horarios de Paradas',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0A0A0A),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Próximamente: Horarios en tiempo real',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF0A0A0A),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
