import 'dart:convert';
import 'package:http/http.dart' as http;

class PlacesService {
  static const String _apiKey = 'AIzaSyDvSmbzjHJawciAvTXiNC8n0MHlN5lHBfY';
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/place';
  
  // Coordenadas de Montevideo para filtrar resultados
  static const String _montevideoLocation = '-34.9011,-56.1645';
  static const int _radiusMeters = 30000; // 30km radius around Montevideo (más específico)

  static Future<List<PlacePrediction>> getPlacePredictions(String input) async {
    if (input.isEmpty) return [];

    // Hacer múltiples búsquedas para obtener diferentes tipos de POI
    final List<PlacePrediction> allPredictions = [];
    
    // Búsquedas en paralelo para mejor rendimiento
    final futures = [
      _searchByType(input, 'establishment'), // POI, comercios, restaurantes, etc.
      _searchByType(input, 'geocode'),       // Direcciones y lugares geográficos
    ];
    
    final results = await Future.wait(futures);
    for (final predictions in results) {
      allPredictions.addAll(predictions);
    }
    
    // Remover duplicados basado en place_id
    final uniquePredictions = <String, PlacePrediction>{};
    for (final prediction in allPredictions) {
      uniquePredictions[prediction.placeId] = prediction;
    }
    
    // Filtrar y priorizar resultados de Montevideo
    final filteredPredictions = uniquePredictions.values
        .where((prediction) => _isInMontevideo(prediction))
        .toList();
    
    // Ordenar por relevancia: POI importantes primero, luego por proximidad a Montevideo
    filteredPredictions.sort((a, b) {
      final aScore = _calculateRelevanceScore(a, input);
      final bScore = _calculateRelevanceScore(b, input);
      return bScore.compareTo(aScore); // Orden descendente
    });
    
    return filteredPredictions.take(8).toList();
  }
  
  static int _calculateRelevanceScore(PlacePrediction prediction, String input) {
    int score = 0;
    final description = prediction.description.toLowerCase();
    final mainText = prediction.mainText.toLowerCase();
    final inputLower = input.toLowerCase();
    
    // Puntuación por coincidencia exacta en el texto principal
    if (mainText.startsWith(inputLower)) score += 100;
    else if (mainText.contains(inputLower)) score += 50;
    
    // Puntuación por tipo de lugar (POI importantes para transporte)
    if (_isTransportRelevantPOI(description)) score += 30;
    
    // Puntuación por mencionar "Montevideo" explícitamente
    if (description.contains('montevideo')) score += 20;
    
    // Puntuación por barrios centrales
    if (_isCentralNeighborhood(description)) score += 15;
    
    return score;
  }
  
  static bool _isTransportRelevantPOI(String description) {
    final transportPOIs = [
      'shopping', 'mall', 'centro comercial', 'hospital', 'universidad',
      'aeropuerto', 'terminal', 'estación', 'puerto', 'mercado',
      'plaza', 'parque', 'museo', 'teatro', 'estadio', 'cine',
      'banco', 'farmacia', 'supermercado', 'hotel', 'restaurante'
    ];
    
    return transportPOIs.any((poi) => description.contains(poi));
  }
  
  static bool _isCentralNeighborhood(String description) {
    final centralNeighborhoods = [
      'ciudad vieja', 'centro', 'cordón', 'tres cruces', 'pocitos',
      'punta carretas', 'parque rodó', 'palermo', 'barrio sur'
    ];
    
    return centralNeighborhoods.any((neighborhood) => 
        description.contains(neighborhood));
  }
  
  static Future<List<PlacePrediction>> _searchByType(String input, String type) async {
    final String url = '$_baseUrl/autocomplete/json'
        '?input=${Uri.encodeComponent(input)}'
        '&key=$_apiKey'
        '&location=$_montevideoLocation'
        '&radius=$_radiusMeters'
        '&strictbounds=true'
        '&components=country:uy'
        '&language=es'
        '&types=$type';

    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List;
          return predictions
              .map((prediction) => PlacePrediction.fromJson(prediction))
              .toList();
        }
      }
    } catch (e) {
      // Error silencioso para mejor UX
    }
    
    return [];
  }
  
  static bool _isInMontevideo(PlacePrediction prediction) {
    final description = prediction.description.toLowerCase();
    
    // Verificar si contiene "montevideo" o "uruguay"
    if (description.contains('montevideo') || description.contains('uruguay')) {
      return true;
    }
    
    // Verificar si contiene barrios conocidos de Montevideo
    final montevideoNeighborhoods = [
      'ciudad vieja', 'centro', 'barrio sur', 'aguada', 'villa muñoz',
      'la teja', 'prado', 'capurro', 'bella vista', 'goes', 'reducto',
      'atahualpa', 'jacinto vera', 'la figurita', 'larrañaga', 'la blanqueada',
      'parque rodó', 'tres cruces', 'la comercial', 'cordón', 'palermo',
      'barrio norte', 'paso molino', 'belvedere', 'punta carretas', 'pocitos',
      'buceo', 'parque batlle', 'villa dolores', 'malvín', 'malvín norte',
      'punta gorda', 'carrasco', 'carrasco norte', 'bañados de carrasco',
      'flor de maroñas', 'maroñas', 'villa española', 'ituzaingó', 'cerrito',
      'peñarol', 'sayago', 'conciliación', 'belvedere', 'nuevo parís',
      'cerro', 'casabó', 'pajas blancas', 'la paloma', 'tomkinson'
    ];
    
    return montevideoNeighborhoods.any((neighborhood) => 
        description.contains(neighborhood));
  }
}

class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    return PlacePrediction(
      placeId: json['place_id'] ?? '',
      description: json['description'] ?? '',
      mainText: json['structured_formatting']?['main_text'] ?? '',
      secondaryText: json['structured_formatting']?['secondary_text'] ?? '',
    );
  }
  
  // Función para obtener una versión simplificada del destino
  String get simplifiedDestination {
    // Si el mainText no está vacío, usarlo (es más conciso)
    if (mainText.isNotEmpty) {
      return mainText;
    }
    
    // Si no, simplificar la descripción completa
    final parts = description.split(',');
    if (parts.isNotEmpty) {
      return parts.first.trim();
    }
    
    return description;
  }
}