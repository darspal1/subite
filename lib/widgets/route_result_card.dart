import 'dart:async';
import 'package:flutter/material.dart';
import '../services/unified_eta_service.dart';

class RouteResultCard extends StatefulWidget {
  final List<RouteSegment> segments;
  final int? totalDuration;
  final double? totalDistance;
  final VoidCallback? onTap;
  final List<BusRouteDetails>? routeDetails;

  const RouteResultCard({
    Key? key,
    required this.segments,
    this.totalDuration,
    this.totalDistance,
    this.onTap,
    this.routeDetails,
  }) : super(key: key);

  @override
  State<RouteResultCard> createState() => _RouteResultCardState();
}

class _RouteResultCardState extends State<RouteResultCard> {
  bool _isExpanded = false;
  List<UnifiedETA>? _realtimeETAs;
  bool _loadingRealtimeETAs = false;
  StreamSubscription<List<UnifiedETA>>? _etaStreamSubscription;

  @override
  void initState() {
    super.initState();
    _loadRealtimeETAs();
  }

  @override
  void dispose() {
    // Cancelar stream de ETAs en tiempo real
    _etaStreamSubscription?.cancel();
    super.dispose();
  }

  void _loadRealtimeETAs() {
    final busSegment = widget.segments.firstWhere(
      (segment) => segment.type == SegmentType.bus && 
                   segment.departureStopId != null,
      orElse: () => RouteSegment(type: SegmentType.walk),
    );

    if (busSegment.type == SegmentType.bus && 
        busSegment.departureStopId != null && 
        !_loadingRealtimeETAs) {
      setState(() {
        _loadingRealtimeETAs = true;
      });

      // Cancelar stream anterior si existe
      _etaStreamSubscription?.cancel();

      // Iniciar stream de actualizaciones en tiempo real
      _etaStreamSubscription = UnifiedETAService.streamETAsForStop(
        stopId: busSegment.departureStopId!,
        maxResults: 5,
      ).listen(
        (etas) {
          if (mounted) {
            setState(() {
              _realtimeETAs = etas.where((eta) => 
                busSegment.busLines.contains(eta.routeShortName)
              ).toList();
              _loadingRealtimeETAs = false;
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _loadingRealtimeETAs = false;
            });
          }
          print('Error en stream de ETAs en tiempo real: $error');
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.totalDuration != null || widget.totalDistance != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          if (widget.totalDuration != null) ...[
                            Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text('${widget.totalDuration!} min',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey[700])),
                          ],
                          if (widget.totalDuration != null && widget.totalDistance != null)
                            const SizedBox(width: 16),
                          if (widget.totalDistance != null) ...[
                            Icon(Icons.straighten, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text('${(widget.totalDistance! / 1000).toStringAsFixed(1)} km',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey[700])),
                          ],
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: _buildRouteSegments(),
                          ),
                        ),
                      ),
                      if (widget.routeDetails != null && widget.routeDetails!.isNotEmpty)
                        IconButton(
                          onPressed: () => setState(() => _isExpanded = !_isExpanded),
                          icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, color: const Color(0xFF0A1639)),
                          tooltip: _isExpanded ? 'Ocultar recorridos' : 'Ver recorridos',
                        ),
                    ],
                  ),
                  _buildETAInformation(),
                ],
              ),
            ),
          ),
          if (_isExpanded && widget.routeDetails != null) _buildRouteDetailsPanel(),
        ],
      ),
    );
  }

  List<Widget> _buildRouteSegments() {
    List<Widget> widgets = [];
    for (int i = 0; i < widget.segments.length; i++) {
      final segment = widget.segments[i];
      widgets.add(_buildSegmentIcon(segment.type));
      if (segment.type == SegmentType.bus) {
        widgets.add(const SizedBox(width: 8));
        widgets.add(_buildBusNumbers(segment.busLines));
      }
      if (i < widget.segments.length - 1) {
        widgets.add(const SizedBox(width: 12));
        widgets.add(const Icon(Icons.chevron_right, color: Colors.grey, size: 20));
        widgets.add(const SizedBox(width: 12));
      }
    }
    return widgets;
  }

  Widget _buildSegmentIcon(SegmentType type) {
    switch (type) {
      case SegmentType.walk:
        return Icon(Icons.directions_walk, color: Colors.grey[600], size: 24);
      case SegmentType.bus:
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey[300]!, width: 1),
          ),
          child: const Icon(Icons.directions_bus, color: Colors.black, size: 16),
        );
    }
  }

  Widget _buildBusNumbers(List<String> busLines) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: busLines.map((line) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey[300]!, width: 1),
        ),
        child: Text(line, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
      )).toList(),
    );
  }

  Widget _buildRouteDetailsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.route, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text('Recorridos de las líneas',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
              ],
            ),
          ),
          ...widget.routeDetails!.map((routeDetail) => _buildRouteDetailItem(routeDetail)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildRouteDetailItem(BusRouteDetails routeDetail) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _parseColor(routeDetail.color) ?? const Color(0xFF0A1639),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(routeDetail.busLine,
                    style: TextStyle(
                        color: _parseColor(routeDetail.textColor) ?? Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Text('${routeDetail.stops.length} paradas',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: routeDetail.stops.asMap().entries.map((entry) {
                final index = entry.key;
                final stop = entry.value;
                final isLast = index == routeDetail.stops.length - 1;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A1639),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        if (!isLast)
                          Container(width: 2, height: 20, color: Colors.grey[300]),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                        child: Text(_formatStopName(stop),
                            style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildETAInformation() {
    final busSegment = widget.segments.firstWhere(
      (segment) => segment.type == SegmentType.bus && 
                   segment.staticETAs != null && 
                   segment.departureStopName != null,
      orElse: () => RouteSegment(type: SegmentType.walk),
    );

    if (busSegment.type != SegmentType.bus || 
        busSegment.staticETAs == null || 
        busSegment.departureStopName == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: Colors.grey[200], margin: const EdgeInsets.only(bottom: 12)),
          _buildDepartureInfo(busSegment),
        ],
      ),
    );
  }

  Widget _buildDepartureInfo(RouteSegment busSegment) {
    final stopName = _formatStopName(busSegment.departureStopName!);
    
    // Priorizar ETAs del backend si están disponibles
    List<int> displayETAs = [];
    bool hasRealtimeData = false;
    
    if (_realtimeETAs != null && _realtimeETAs!.isNotEmpty) {
      // Usar ETAs del backend (tiempo real)
      displayETAs = _realtimeETAs!
          .where((eta) => busSegment.busLines.contains(eta.routeShortName))
          .map((eta) => eta.minutesUntil)
          .where((minutes) => minutes > 0)
          .take(3)
          .toList();
      hasRealtimeData = displayETAs.isNotEmpty;
    }
    
    // Fallback a ETAs estáticos si no hay datos del backend
    if (!hasRealtimeData && busSegment.staticETAs != null) {
      final Set<int> allETAsSet = {};
      for (final etas in busSegment.staticETAs!.values) {
        allETAsSet.addAll(etas);
      }
      displayETAs = allETAsSet.toList()..sort();
      displayETAs = displayETAs.take(3).toList();
    }
    
    if (displayETAs.isEmpty) {
      // Mostrar indicador de carga si está cargando
      if (_loadingRealtimeETAs) {
        return Row(
          children: [
            const Text('Salida en ', style: TextStyle(color: Colors.grey, fontSize: 14)),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
              ),
            ),
            const SizedBox(width: 8),
            Text(' desde $stopName', style: const TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        );
      }
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Colors.black87, fontFamily: 'Arial'),
            children: [
              const TextSpan(text: 'Salida en ', style: TextStyle(color: Colors.grey)),
              ...displayETAs.asMap().entries.expand((entry) {
                final index = entry.key;
                final eta = entry.value;
                final isLast = index == displayETAs.length - 1;
                return [
                  TextSpan(
                    text: '$eta', 
                    style: TextStyle(
                      fontWeight: FontWeight.w600, 
                      color: hasRealtimeData ? const Color(0xFF388E3C) : Colors.black, // Verde si es tiempo real
                    )
                  ),
                  if (!isLast) const TextSpan(text: ', ', style: TextStyle(color: Colors.grey)),
                ];
              }),
              const TextSpan(text: ' min desde ', style: TextStyle(color: Colors.grey)),
              TextSpan(text: stopName, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87)),
            ],
          ),
        ),
        // Mostrar indicador de tiempo real si aplica
        if (hasRealtimeData)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF388E3C),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Tiempo real',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF388E3C),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }



  String _formatStopName(String stopName) {
    if (stopName.isEmpty) return stopName;
    
    String formatted = stopName.toLowerCase().trim().split(' ').map((word) {
      if (word.isEmpty) return word;
      if (RegExp(r'^\d+$').hasMatch(word)) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
    
    formatted = formatted
        .replaceAllMapped(RegExp(r'\b(y|de|del|la|el|las|los|en|con|por|para|desde|hasta)\b'), 
            (match) => match.group(0)!)
        .replaceAllMapped(RegExp(r'^(de|del|la|el|las|los|y|en|con)'), 
            (match) => match.group(0)![0].toUpperCase() + match.group(0)!.substring(1))
        .replaceAllMapped(RegExp(r'(\d+)\s+(de|del|la|el|las|los|y)'), 
            (match) => '${match.group(1)} ${match.group(2)![0].toUpperCase()}${match.group(2)!.substring(1)}');
    
    return formatted
        .replaceAll('18 de julio', '18 de Julio')
        .replaceAll('8 de octubre', '8 de Octubre')
        .replaceAll('25 de mayo', '25 de Mayo')
        .replaceAll('19 de abril', '19 de Abril')
        .replaceAll('21 de setiembre', '21 de Setiembre')
        .replaceAll('plaza independencia', 'Plaza Independencia')
        .replaceAll('plaza matriz', 'Plaza Matriz')
        .replaceAll('plaza cagancha', 'Plaza Cagancha')
        .replaceAll('tres cruces', 'Tres Cruces')
        .replaceAll('ciudad vieja', 'Ciudad Vieja')
        .replaceAll('punta carretas', 'Punta Carretas')
        .replaceAll('parque rodó', 'Parque Rodó')
        .replaceAll('parque batlle', 'Parque Batlle');
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

class RouteSegment {
  final SegmentType type;
  final List<String> busLines;
  final int? duration;
  final String? departureStopName;
  final String? departureStopId; // ID de la parada para consultar ETAs del backend
  final Map<String, List<int>>? staticETAs;
  final DateTime? departureTime;
  final DateTime? arrivalTime;
  
  RouteSegment({
    required this.type,
    this.busLines = const [],
    this.duration,
    this.departureStopName,
    this.departureStopId,
    this.staticETAs,
    this.departureTime,
    this.arrivalTime,
  });
}

enum SegmentType { walk, bus }

class BusRouteDetails {
  final String busLine;
  final List<String> stops;
  final String? color;
  final String? textColor;

  BusRouteDetails({
    required this.busLine,
    required this.stops,
    this.color,
    this.textColor,
  });

  BusRouteDetails copyWith({
    String? busLine,
    List<String>? stops,
    String? color,
    String? textColor,
  }) {
    return BusRouteDetails(
      busLine: busLine ?? this.busLine,
      stops: stops ?? this.stops,
      color: color ?? this.color,
      textColor: textColor ?? this.textColor,
    );
  }
}