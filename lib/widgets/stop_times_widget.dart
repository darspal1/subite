import 'package:flutter/material.dart';
import '../services/stop_times_service.dart';

class StopTimesWidget extends StatefulWidget {
  final String stopId;
  final String stopName;

  const StopTimesWidget({
    Key? key,
    required this.stopId,
    required this.stopName,
  }) : super(key: key);

  @override
  State<StopTimesWidget> createState() => _StopTimesWidgetState();
}

class _StopTimesWidgetState extends State<StopTimesWidget> {
  List<StopTime> stopTimes = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStopTimes();
  }

  Future<void> _loadStopTimes() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final times = await StopTimesService.getStopTimes(stopId: widget.stopId);
      
      setState(() {
        stopTimes = times;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.toString();
      });
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1639),
              borderRadius: const BorderRadius.only(
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
                  onPressed: _loadStopTimes,
                  icon: const Icon(
                    Icons.refresh,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Error al cargar horarios',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          else if (stopTimes.isEmpty)
            const Padding(
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
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: stopTimes.length > 10 ? 10 : stopTimes.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final stopTime = stopTimes[index];
                return _buildStopTimeItem(stopTime);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStopTimeItem(StopTime stopTime) {
    final minutesUntil = stopTime.minutesUntilDeparture;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Línea de bus
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _parseColor(stopTime.routeColor) ?? const Color(0xFF0A1639),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              stopTime.displayName,
              style: TextStyle(
                color: _parseColor(stopTime.routeTextColor) ?? Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Destino
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stopTime.displayHeadsign,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  stopTime.statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: stopTime.isRealtime ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          
          // Tiempo
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                minutesUntil == 0 ? 'Ahora' : '${minutesUntil} min',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: minutesUntil <= 5 ? Colors.red : Colors.black,
                ),
              ),
              Text(
                '${stopTime.departureTime.hour.toString().padLeft(2, '0')}:${stopTime.departureTime.minute.toString().padLeft(2, '0')}',
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