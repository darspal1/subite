import 'otp_service.dart';

class NavigationService {
  // Generar instrucciones de navegación paso a paso
  static List<NavigationInstruction> generateInstructions(OTPRoute route) {
    final List<NavigationInstruction> instructions = [];
    
    for (int i = 0; i < route.legs.length; i++) {
      final leg = route.legs[i];
      
      if (leg.isWalk) {
        instructions.addAll(_generateWalkingInstructions(leg, i == 0));
      } else if (leg.isTransit) {
        instructions.addAll(_generateTransitInstructions(leg));
      }
    }
    
    // Agregar instrucción final
    if (route.legs.isNotEmpty) {
      final lastLeg = route.legs.last;
      instructions.add(NavigationInstruction(
        type: NavigationInstructionType.arrival,
        title: 'Has llegado a tu destino',
        description: lastLeg.to?.name ?? 'Destino',
        distance: 0,
        duration: 0,
      ));
    }
    
    return instructions;
  }
  
  static List<NavigationInstruction> _generateWalkingInstructions(OTPLeg leg, bool isFirst) {
    final List<NavigationInstruction> instructions = [];
    
    // Instrucción inicial de caminata
    if (isFirst) {
      instructions.add(NavigationInstruction(
        type: NavigationInstructionType.walkStart,
        title: 'Comienza caminando',
        description: 'Dirígete hacia ${leg.to?.name ?? "tu destino"}',
        distance: leg.distance,
        duration: leg.duration,
      ));
    } else {
      instructions.add(NavigationInstruction(
        type: NavigationInstructionType.walkTransfer,
        title: 'Camina hasta la siguiente parada',
        description: 'Dirígete a ${leg.to?.name ?? "la parada"}',
        distance: leg.distance,
        duration: leg.duration,
      ));
    }
    
    // Agregar pasos detallados si están disponibles
    for (final step in leg.steps) {
      if (step.streetName != null && step.streetName!.isNotEmpty) {
        instructions.add(NavigationInstruction(
          type: NavigationInstructionType.walkStep,
          title: step.instruction,
          description: '${step.distance.round()}m',
          distance: step.distance,
          duration: (step.distance / 1.4).round(), // ~1.4 m/s velocidad de caminata
        ));
      }
    }
    
    return instructions;
  }
  
  static List<NavigationInstruction> _generateTransitInstructions(OTPLeg leg) {
    final List<NavigationInstruction> instructions = [];
    
    // Instrucción de abordar
    instructions.add(NavigationInstruction(
      type: NavigationInstructionType.boardBus,
      title: 'Sube al ${leg.routeShortName ?? "bus"}',
      description: 'Dirección: ${leg.busDirection}\nParada: ${leg.from?.name ?? "Parada"}',
      distance: 0,
      duration: 0,
      routeInfo: RouteInfo(
        shortName: leg.routeShortName,
        longName: leg.routeLongName,
        headsign: leg.tripHeadsign,
        color: leg.routeColor,
        textColor: leg.routeTextColor,
      ),
    ));
    
    // Instrucción de viaje en bus
    instructions.add(NavigationInstruction(
      type: NavigationInstructionType.stayOnBus,
      title: 'Permanece en el ${leg.routeShortName ?? "bus"}',
      description: 'Viaja ${leg.durationInMinutes} minutos hasta ${leg.to?.name ?? "tu parada"}',
      distance: leg.distance,
      duration: leg.duration,
      routeInfo: RouteInfo(
        shortName: leg.routeShortName,
        longName: leg.routeLongName,
        headsign: leg.tripHeadsign,
        color: leg.routeColor,
        textColor: leg.routeTextColor,
      ),
    ));
    
    // Instrucción de bajar
    instructions.add(NavigationInstruction(
      type: NavigationInstructionType.alightBus,
      title: 'Baja del ${leg.routeShortName ?? "bus"}',
      description: 'En la parada: ${leg.to?.name ?? "Parada de destino"}',
      distance: 0,
      duration: 0,
    ));
    
    return instructions;
  }
}

enum NavigationInstructionType {
  walkStart,
  walkStep,
  walkTransfer,
  boardBus,
  stayOnBus,
  alightBus,
  arrival,
}

class NavigationInstruction {
  final NavigationInstructionType type;
  final String title;
  final String description;
  final double distance; // en metros
  final int duration; // en segundos
  final RouteInfo? routeInfo;

  NavigationInstruction({
    required this.type,
    required this.title,
    required this.description,
    required this.distance,
    required this.duration,
    this.routeInfo,
  });

  // Duración en minutos
  int get durationInMinutes => (duration / 60).round();
  
  // Distancia en formato legible
  String get distanceText {
    if (distance < 1000) {
      return '${distance.round()}m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)}km';
    }
  }
  
  // Icono según el tipo de instrucción
  String get iconName {
    switch (type) {
      case NavigationInstructionType.walkStart:
      case NavigationInstructionType.walkStep:
      case NavigationInstructionType.walkTransfer:
        return 'directions_walk';
      case NavigationInstructionType.boardBus:
        return 'directions_bus';
      case NavigationInstructionType.stayOnBus:
        return 'airline_seat_recline_normal';
      case NavigationInstructionType.alightBus:
        return 'exit_to_app';
      case NavigationInstructionType.arrival:
        return 'place';
    }
  }
}

class RouteInfo {
  final String? shortName;
  final String? longName;
  final String? headsign;
  final String? color;
  final String? textColor;

  RouteInfo({
    this.shortName,
    this.longName,
    this.headsign,
    this.color,
    this.textColor,
  });
}