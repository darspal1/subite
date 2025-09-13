import 'dart:convert';
import 'package:http/http.dart' as http;

class RealtimeInterestService {
  static const String _proxyBaseUrl = 'https://stmapi.ddns.net'; // Puerto 8081 para el proxy Python
  
  // Validar si una línea es válida para STM (evitar líneas con caracteres problemáticos)
  static bool _isValidSTMLine(String line) {
    // Permitir solo líneas que:
    // - Sean completamente numéricas (ej: "180", "121")
    // - O tengan formato simple con letras al final (ej: "CA1", "D1") pero sin espacios
    final validPattern = RegExp(r'^[A-Z0-9]+$');
    return validPattern.hasMatch(line) && !line.contains(' ');
  }
  
  // Registrar interés en líneas y paradas específicas
  static Future<bool> registerInterest({
    required List<String> lines,
    required List<String> stops,
  }) async {
    try {
      // Limpiar y validar líneas - filtrar solo líneas válidas para STM
      final cleanLines = lines
          .where((line) => line.isNotEmpty)
          .map((line) => line.trim())
          .where((line) => _isValidSTMLine(line))
          .toSet()
          .toList();
      
      // Limpiar y validar paradas (solo números)
      final cleanStops = stops
          .where((stop) => stop.isNotEmpty && RegExp(r'^\d+$').hasMatch(stop.trim()))
          .map((stop) => stop.trim())
          .toSet()
          .toList();

      if (cleanLines.isEmpty && cleanStops.isEmpty) {
        return false;
      }
      
      final requestBody = json.encode({
        'lines': cleanLines,
        'stops': cleanStops,
      });
      
      final response = await http.post(
        Uri.parse('$_proxyBaseUrl/register-interest'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: requestBody,
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  // Registrar interés basado en rutas OTP
  static Future<bool> registerInterestFromOTPRoutes(List<dynamic> otpRoutes) async {
    final Set<String> lines = {};
    final Set<String> stops = {};

    print('🔍 DEBUG: Procesando ${otpRoutes.length} rutas OTP...');

    // Extraer líneas y paradas de las rutas OTP
    for (final route in otpRoutes) {
      if (route.legs != null) {
        for (final leg in route.legs) {
          // Agregar líneas de bus
          if (leg.isTransit && leg.routeShortName != null) {
            lines.add(leg.routeShortName!);
            print('🚌 Línea agregada: ${leg.routeShortName}');
          }

          // Agregar paradas
          if (leg.from?.stopId != null) {
            // Extraer solo el número de la parada del GTFS ID
            final stopId = extractStopId(leg.from!.stopId!);
            if (stopId != null) {
              stops.add(stopId);
              print('🚏 Parada FROM agregada: $stopId');
            }
          }
          if (leg.to?.stopId != null) {
            final stopId = extractStopId(leg.to!.stopId!);
            if (stopId != null) {
              stops.add(stopId);
              print('🚏 Parada TO agregada: $stopId');
            }
          }
        }
      }
    }

    print('📊 Resumen: ${lines.length} líneas únicas, ${stops.length} paradas únicas');

    if (lines.isEmpty && stops.isEmpty) {
      print('⚠️ No se encontraron líneas o paradas para registrar interés');
      return false;
    }

    return await registerInterest(
      lines: lines.toList(),
      stops: stops.toList(),
    );
  }

  // Extraer ID numérico de parada desde GTFS ID (ej: "STM:1234" -> "1234")
  static String? extractStopId(String gtfsId) {
    try {
      print('🔍 Extrayendo stop ID de: $gtfsId');
      
      // Formato típico: "STM:1234" o "1:1234"
      if (gtfsId.contains(':')) {
        final extracted = gtfsId.split(':').last;
        print('✂️ Extraído: $extracted');
        return extracted;
      }
      
      // Si ya es numérico, devolverlo
      if (RegExp(r'^\d+$').hasMatch(gtfsId)) {
        print('🔢 Ya es numérico: $gtfsId');
        return gtfsId;
      }
      
      print('❓ No se pudo extraer ID de: $gtfsId');
    } catch (e) {
      print('💥 Error extrayendo stop ID de $gtfsId: $e');
    }
    return null;
  }

  // Limpiar interés (opcional, para optimizar recursos)
  static Future<bool> clearInterest() async {
    return await registerInterest(lines: [], stops: []);
  }
}