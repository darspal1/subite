import 'dart:convert';
import 'package:http/http.dart' as http;

class OTPDebugService {
  static const String _baseUrl = 'https://stmapi.ddns.net';
  static const String _endpoint = '/otp/gtfs/v1';
  
  // Test basic connectivity
  static Future<void> testConnectivity() async {
    try {
      print('Testing connectivity to: $_baseUrl$_endpoint');
      
      final response = await http.post(
        Uri.parse('$_baseUrl$_endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'query': '{ __schema { queryType { name } } }'
        }),
      ).timeout(Duration(seconds: 10));
      
      print('Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');
      
    } catch (e) {
      print('Connection Error: $e');
    }
  }
  
  // Test simple plan query (old API)
  static Future<void> testPlanQuery() async {
    try {
      final query = '''
      {
        plan(
          from: { lat: -34.9011, lon: -56.1645 }
          to: { lat: -34.9033, lon: -56.1882 }
          date: "2024-01-15"
          time: "14:00"
          transportModes: [{ mode: WALK }, { mode: BUS }]
          numItineraries: 3
        ) {
          itineraries {
            duration
            walkTime
            legs {
              mode
              from { name }
              to { name }
            }
          }
        }
      }
      ''';
      
      final response = await http.post(
        Uri.parse('$_baseUrl$_endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'query': query}),
      );
      
      print('Plan Query Status: ${response.statusCode}');
      print('Plan Query Response: ${response.body}');
      
    } catch (e) {
      print('Plan Query Error: $e');
    }
  }
  
  // Test planConnection query (new API)
  static Future<void> testPlanConnectionQuery() async {
    try {
      final query = '''
      {
        planConnection(
          origin: {
            location: { coordinate: { latitude: -34.9011, longitude: -56.1645 } }
          }
          destination: {
            location: { coordinate: { latitude: -34.9033, longitude: -56.1882 } }
          }
          dateTime: { earliestDeparture: "2024-01-15T14:00:00-03:00" }
          modes: {
            direct: [WALK]
            transit: { transit: [{ mode: BUS }] }
          }
          first: 3
        ) {
          edges {
            node {
              duration
              walkTime
              legs {
                mode
                from { name }
                to { name }
              }
            }
          }
        }
      }
      ''';
      
      final response = await http.post(
        Uri.parse('$_baseUrl$_endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'query': query}),
      );
      
      print('PlanConnection Query Status: ${response.statusCode}');
      print('PlanConnection Query Response: ${response.body}');
      
    } catch (e) {
      print('PlanConnection Query Error: $e');
    }
  }
  
  // Test alternative endpoints
  static Future<void> testAlternativeEndpoints() async {
    final endpoints = [
      '/otp/routers/default/index/graphql',
      '/otp/gtfs/v1',
      '/otp/v1/routers/default/index/graphql',
      '/graphql'
    ];
    
    for (final endpoint in endpoints) {
      try {
        print('\nTesting endpoint: $endpoint');
        final response = await http.post(
          Uri.parse('$_baseUrl$endpoint'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'query': '{ __schema { queryType { name } } }'
          }),
        ).timeout(Duration(seconds: 5));
        
        print('Status: ${response.statusCode}');
        if (response.statusCode == 200) {
          print('✅ Endpoint works: $endpoint');
          print('Response: ${response.body.substring(0, 200)}...');
        }
        
      } catch (e) {
        print('❌ Endpoint failed: $endpoint - $e');
      }
    }
  }
  
  // Test with real Montevideo coordinates
  static Future<void> testRealCoordinates() async {
    try {
      // 18 de Julio y Rio Branco to Pocitos Shopping
      final query = '''
      {
        planConnection(
          origin: {
            location: { coordinate: { latitude: -34.9042, longitude: -56.1910 } }
          }
          destination: {
            location: { coordinate: { latitude: -34.9214, longitude: -56.1591 } }
          }
          dateTime: { earliestDeparture: "2024-01-15T14:00:00-03:00" }
          modes: {
            direct: [WALK]
            transit: { transit: [{ mode: BUS }] }
          }
          first: 5
        ) {
          edges {
            node {
              duration
              walkTime
              legs {
                mode
                from { name lat lon stop { name code } }
                to { name lat lon stop { name code } }
                route { shortName longName }
                trip { tripHeadsign }
              }
            }
          }
        }
      }
      ''';
      
      final response = await http.post(
        Uri.parse('$_baseUrl$_endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'query': query}),
      );
      
      print('Real Coordinates Test Status: ${response.statusCode}');
      print('Real Coordinates Response: ${response.body}');
      
    } catch (e) {
      print('Real Coordinates Test Error: $e');
    }
  }
  
  // Test if GTFS data is loaded
  static Future<void> testGTFSData() async {
    try {
      final query = '''
      {
        agencies {
          gtfsId
          name
        }
        routes {
          gtfsId
          shortName
          longName
        }
      }
      ''';
      
      final response = await http.post(
        Uri.parse('$_baseUrl$_endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'query': query}),
      );
      
      print('GTFS Data Test Status: ${response.statusCode}');
      print('GTFS Data Response: ${response.body}');
      
    } catch (e) {
      print('GTFS Data Test Error: $e');
    }
  }
}