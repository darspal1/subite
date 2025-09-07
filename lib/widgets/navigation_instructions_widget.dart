import 'package:flutter/material.dart';
import '../services/navigation_service.dart';
import '../services/otp_service.dart';

class NavigationInstructionsWidget extends StatelessWidget {
  final OTPRoute route;

  const NavigationInstructionsWidget({
    Key? key,
    required this.route,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final instructions = NavigationService.generateInstructions(route);
    
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
                  Icons.navigation,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Instrucciones de navegación',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${route.durationInMinutes} min',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Instructions list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: instructions.length,
            separatorBuilder: (context, index) => _buildConnector(instructions[index].type),
            itemBuilder: (context, index) {
              final instruction = instructions[index];
              return _buildInstructionItem(instruction, index);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(NavigationInstruction instruction, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number and icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getInstructionColor(instruction.type),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: _getInstructionIcon(instruction.type),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Instruction content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  instruction.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  instruction.description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                
                // Route info for transit instructions
                if (instruction.routeInfo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildRouteInfo(instruction.routeInfo!),
                  ),
                
                // Duration and distance
                if (instruction.duration > 0 || instruction.distance > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        if (instruction.duration > 0) ...[
                          const Icon(
                            Icons.access_time,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${instruction.durationInMinutes} min',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                        if (instruction.duration > 0 && instruction.distance > 0)
                          const SizedBox(width: 16),
                        if (instruction.distance > 0) ...[
                          const Icon(
                            Icons.straighten,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            instruction.distanceText,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnector(NavigationInstructionType type) {
    return Container(
      margin: const EdgeInsets.only(left: 36),
      child: Container(
        width: 2,
        height: 20,
        color: Colors.grey.shade300,
      ),
    );
  }

  Widget _buildRouteInfo(RouteInfo routeInfo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _parseColor(routeInfo.color) ?? const Color(0xFF0A1639),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        routeInfo.shortName ?? routeInfo.longName ?? 'Bus',
        style: TextStyle(
          color: _parseColor(routeInfo.textColor) ?? Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _getInstructionColor(NavigationInstructionType type) {
    switch (type) {
      case NavigationInstructionType.walkStart:
      case NavigationInstructionType.walkStep:
      case NavigationInstructionType.walkTransfer:
        return Colors.green;
      case NavigationInstructionType.boardBus:
      case NavigationInstructionType.stayOnBus:
      case NavigationInstructionType.alightBus:
        return const Color(0xFF0A1639);
      case NavigationInstructionType.arrival:
        return Colors.red;
    }
  }

  Widget _getInstructionIcon(NavigationInstructionType type) {
    IconData iconData;
    
    switch (type) {
      case NavigationInstructionType.walkStart:
      case NavigationInstructionType.walkStep:
      case NavigationInstructionType.walkTransfer:
        iconData = Icons.directions_walk;
        break;
      case NavigationInstructionType.boardBus:
        iconData = Icons.directions_bus;
        break;
      case NavigationInstructionType.stayOnBus:
        iconData = Icons.airline_seat_recline_normal;
        break;
      case NavigationInstructionType.alightBus:
        iconData = Icons.exit_to_app;
        break;
      case NavigationInstructionType.arrival:
        iconData = Icons.place;
        break;
    }
    
    return Icon(
      iconData,
      color: Colors.white,
      size: 20,
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