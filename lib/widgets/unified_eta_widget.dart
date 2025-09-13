import 'package:flutter/material.dart';
import '../services/unified_eta_service.dart';

/// Widget que muestra ETAs unificados (estáticos + tiempo real) para una parada específica
class UnifiedETAWidget extends StatefulWidget {
  final String stopId;
  final String stopName;
  final List<String>? filterRoutes; // Filtrar solo ciertas líneas
  final int maxResults;
  final bool showHeader;

  const UnifiedETAWidget({
    Key? key,
    required this.stopId,
    required this.stopName,
    this.filterRoutes,
    this.maxResults = 5,
    this.showHeader = true,
  }) : super(key: key);

  @override
  State<UnifiedETAWidget> createState() => _UnifiedETAWidgetState();
}

class _UnifiedETAWidgetState extends State<UnifiedETAWidget> {
  List<UnifiedETA> _etas = [];
  bool _isLoading = true;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _loadETAs();
  }

  @override
  void dispose() {
    // Limpiar stream si es necesario
    super.dispose();
  }

  Future<void> _loadETAs() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final etas = await UnifiedETAService.getETAsForStop(
        stopId: widget.stopId,
        maxResults: widget.maxResults,
      );
      
      // Filtrar por rutas si se especifica
      final filteredETAs = widget.filterRoutes != null
          ? etas.where((eta) => widget.filterRoutes!.contains(eta.routeShortName)).toList()
          : etas;

      if (mounted) {
        setState(() {
          _etas = filteredETAs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          if (widget.showHeader) _buildHeader(),
          
          // Content
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_errorMessage != null)
            _buildErrorState()
          else if (_etas.isEmpty)
            _buildEmptyState()
          else
            _buildETAsList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0A1639),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.schedule,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Próximos buses',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.stopName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadETAs,
            icon: const Icon(
              Icons.refresh,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 48,
          ),
          const SizedBox(height: 8),
          const Text(
            'Error al cargar horarios',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.schedule_outlined,
              color: Colors.grey,
              size: 48,
            ),
            SizedBox(height: 8),
            Text(
              'No hay buses programados',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildETAsList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _etas.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final eta = _etas[index];
        return _buildETAItem(eta);
      },
    );
  }

  Widget _buildETAItem(UnifiedETA eta) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Línea de bus
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _parseColor(eta.routeColor) ?? const Color(0xFF0A1639),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              eta.displayName,
              style: TextStyle(
                color: _parseColor(eta.routeTextColor) ?? Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Destino y estado
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eta.displayHeadsign,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    // Indicador de fuente de datos
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: eta.statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      eta.statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: eta.statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Indicadores adicionales
                    if (eta.hasSignificantDelay) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.schedule,
                        size: 14,
                        color: eta.statusColor,
                      ),
                    ],
                    if (eta.isCanceled) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.cancel,
                        size: 14,
                        color: Color(0xFFD32F2F),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          
          // Tiempo
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                eta.formattedMinutes,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: eta.minutesUntil <= 5 ? Colors.red : Colors.black,
                ),
              ),
              Text(
                '${eta.departureTime.hour.toString().padLeft(2, '0')}:${eta.departureTime.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color? _parseColor(String? colorString) {
    if (colorString == null || colorString.isEmpty) return null;
    
    try {
      String hex = colorString.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (e) {
      // Error silencioso
    }
    
    return null;
  }
}