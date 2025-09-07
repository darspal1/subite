import 'dart:convert';
import 'package:http/http.dart' as http;

class AlertsService {
  static const String _baseUrl = 'http://api.stmapi.xo.je';
  static const String _endpoint = '/otp/routers/default/index/graphql';

  // Obtener alertas para rutas específicas
  static Future<List<ServiceAlert>> getAlertsForRoutes(List<String> routeIds) async {
    try {
      final String routeFilter = routeIds.map((id) => '"$id"').join(', ');
      
      final String graphqlQuery = '''
      {
        alerts(feeds: ["alerts"]) {
          alertHeaderText
          alertDescriptionText
          alertUrl
          effectiveStartDate
          effectiveEndDate
          alertSeverityLevel
          entities {
            __typename
            ... on Route {
              gtfsId
              shortName
              longName
            }
            ... on Stop {
              gtfsId
              name
              code
            }
          }
        }
      }
      ''';

      final requestBody = {'query': graphqlQuery};

      final response = await http.post(
        Uri.parse('$_baseUrl$_endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseAlertsResponse(data, routeIds);
      } else {
        throw Exception('Error al obtener alertas: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error al conectar con el servicio de alertas: $e');
    }
  }

  static List<ServiceAlert> _parseAlertsResponse(Map<String, dynamic> data, List<String> routeIds) {
    final List<ServiceAlert> alerts = [];
    
    try {
      if (data['data']?['alerts'] != null) {
        final alertsList = data['data']['alerts'] as List;
        
        for (final alert in alertsList) {
          // Verificar si la alerta afecta a alguna de nuestras rutas
          bool affectsOurRoutes = false;
          final List<String> affectedRoutes = [];
          final List<String> affectedStops = [];
          
          if (alert['entities'] != null) {
            final entities = alert['entities'] as List;
            
            for (final entity in entities) {
              if (entity['__typename'] == 'Route') {
                final routeId = entity['gtfsId'] as String?;
                if (routeId != null && routeIds.contains(routeId)) {
                  affectsOurRoutes = true;
                  affectedRoutes.add(entity['shortName'] ?? entity['longName'] ?? routeId);
                }
              } else if (entity['__typename'] == 'Stop') {
                affectedStops.add(entity['name'] ?? entity['code'] ?? 'Parada');
              }
            }
          }
          
          if (affectsOurRoutes) {
            alerts.add(ServiceAlert(
              headerText: alert['alertHeaderText'] as String? ?? 'Alerta de servicio',
              descriptionText: alert['alertDescriptionText'] as String? ?? '',
              url: alert['alertUrl'] as String?,
              effectiveStartDate: _parseTimestamp(alert['effectiveStartDate']),
              effectiveEndDate: _parseTimestamp(alert['effectiveEndDate']),
              severityLevel: _parseSeverityLevel(alert['alertSeverityLevel']),
              affectedRoutes: affectedRoutes,
              affectedStops: affectedStops,
            ));
          }
        }
      }
    } catch (e) {
      // Error silencioso
    }
    
    // Ordenar por severidad y fecha
    alerts.sort((a, b) {
      final severityComparison = b.severityLevel.index.compareTo(a.severityLevel.index);
      if (severityComparison != 0) return severityComparison;
      return b.effectiveStartDate.compareTo(a.effectiveStartDate);
    });
    
    return alerts;
  }

  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    
    try {
      if (timestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      } else if (timestamp is String) {
        return DateTime.parse(timestamp);
      }
    } catch (e) {
      // Error silencioso
    }
    
    return DateTime.now();
  }

  static AlertSeverityLevel _parseSeverityLevel(dynamic level) {
    switch (level?.toString().toUpperCase()) {
      case 'SEVERE':
        return AlertSeverityLevel.severe;
      case 'WARNING':
        return AlertSeverityLevel.warning;
      case 'INFO':
        return AlertSeverityLevel.info;
      default:
        return AlertSeverityLevel.unknown;
    }
  }
}

enum AlertSeverityLevel {
  severe,
  warning,
  info,
  unknown,
}

class ServiceAlert {
  final String headerText;
  final String descriptionText;
  final String? url;
  final DateTime effectiveStartDate;
  final DateTime effectiveEndDate;
  final AlertSeverityLevel severityLevel;
  final List<String> affectedRoutes;
  final List<String> affectedStops;

  ServiceAlert({
    required this.headerText,
    required this.descriptionText,
    this.url,
    required this.effectiveStartDate,
    required this.effectiveEndDate,
    required this.severityLevel,
    required this.affectedRoutes,
    required this.affectedStops,
  });

  // Verificar si la alerta está activa
  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(effectiveStartDate) && now.isBefore(effectiveEndDate);
  }
  
  // Color según la severidad
  String get severityColor {
    switch (severityLevel) {
      case AlertSeverityLevel.severe:
        return '#FF0000'; // Rojo
      case AlertSeverityLevel.warning:
        return '#FF8C00'; // Naranja
      case AlertSeverityLevel.info:
        return '#0066CC'; // Azul
      case AlertSeverityLevel.unknown:
        return '#666666'; // Gris
    }
  }
  
  // Icono según la severidad
  String get severityIcon {
    switch (severityLevel) {
      case AlertSeverityLevel.severe:
        return 'error';
      case AlertSeverityLevel.warning:
        return 'warning';
      case AlertSeverityLevel.info:
        return 'info';
      case AlertSeverityLevel.unknown:
        return 'help';
    }
  }
  
  // Texto de las rutas afectadas
  String get affectedRoutesText {
    if (affectedRoutes.isEmpty) return '';
    return 'Líneas: ${affectedRoutes.join(', ')}';
  }
}