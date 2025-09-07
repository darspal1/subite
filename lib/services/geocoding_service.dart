import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class GeocodingService {
  static const String _apiKey = 'AIzaSyDvSmbzjHJawciAvTXiNC8n0MHlN5lHBfY';
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/place';

  static Future<PlaceCoordinates?> getPlaceCoordinates(String placeId) async {
    try {
      final String url = '$_baseUrl/details/json'
          '?place_id=$placeId'
          '&fields=geometry'
          '&key=$_apiKey';

      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['result'] != null) {
          final geometry = data['result']['geometry'];
          if (geometry != null && geometry['location'] != null) {
            final location = geometry['location'];
            return PlaceCoordinates(
              latitude: (location['lat'] as num).toDouble(),
              longitude: (location['lng'] as num).toDouble(),
            );
          }
        }
      }
    } catch (e) {
      // Error silencioso para mejor UX
    }
    
    return null;
  }

  // Obtener coordenadas de la ubicación actual
  static Future<PlaceCoordinates?> getCurrentLocation() async {
    try {
      // Verificar si el servicio de ubicación está habilitado
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Solicitar al usuario que habilite el servicio de ubicación
        return _getFallbackLocation();
      }

      // Verificar permisos de ubicación
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return _getFallbackLocation();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // Los permisos están denegados permanentemente
        return _getFallbackLocation();
      }

      // Obtener la ubicación actual
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return PlaceCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      // En caso de error, usar ubicación de fallback
      return _getFallbackLocation();
    }
  }

  // Ubicación de fallback (centro de Montevideo)
  static PlaceCoordinates _getFallbackLocation() {
    return PlaceCoordinates(
      latitude: -34.9011,
      longitude: -56.1645,
    );
  }

  // Geocodificar una dirección de texto
  static Future<PlaceCoordinates?> geocodeAddress(String address) async {
    try {
      final String url = 'https://maps.googleapis.com/maps/api/geocode/json'
          '?address=${Uri.encodeComponent(address)}'
          '&components=country:UY'
          '&key=$_apiKey';

      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['results'] != null) {
          final results = data['results'] as List;
          if (results.isNotEmpty) {
            final location = results[0]['geometry']['location'];
            return PlaceCoordinates(
              latitude: (location['lat'] as num).toDouble(),
              longitude: (location['lng'] as num).toDouble(),
            );
          }
        }
      }
    } catch (e) {
      // Error silencioso para mejor UX
    }
    
    return null;
  }
}

class PlaceCoordinates {
  final double latitude;
  final double longitude;

  PlaceCoordinates({
    required this.latitude,
    required this.longitude,
  });

  @override
  String toString() {
    return 'PlaceCoordinates(lat: $latitude, lng: $longitude)';
  }
}