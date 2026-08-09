```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class DirectionsService {
  // Keep your existing Google Maps API key here for now.
  // IMPORTANT: Restrict this key in Google Cloud Console.
  static const String googleApiKey =
      'AIzaSyApq8kEfTzaC7Nb4PDYO1W-V3s-I9ZbMkI';

  /// Gets directions between two locations.
  ///
  /// [origin] example: "0.5143,35.2698"
  /// [destination] example: "0.5200,35.2800"
  ///
  /// [alternatives] requests alternative routes when true.
  static Future<Map<String, dynamic>> getDirections({
    required String origin,
    required String destination,
    bool alternatives = false,
  }) async {
    if (origin.trim().isEmpty || destination.trim().isEmpty) {
      throw Exception('Missing origin or destination');
    }

    try {
      final queryParameters = <String, String>{
        'origin': origin,
        'destination': destination,
        'key': googleApiKey,
        'departure_time': 'now',
        'traffic_model': 'best_guess',
      };

      if (alternatives) {
        queryParameters['alternatives'] = 'true';
      }

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/directions/json',
        queryParameters,
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to fetch directions. HTTP ${response.statusCode}',
        );
      }

      final Map<String, dynamic> data = jsonDecode(response.body);

      // Google Directions API can return an HTTP 200 while
      // still reporting an API-level error.
      final status = data['status'];

      if (status != null && status != 'OK' && status != 'ZERO_RESULTS') {
        final errorMessage =
            data['error_message']?.toString() ?? 'Directions API error';

        throw Exception('$status: $errorMessage');
      }

      return data;
    } catch (e) {
      throw Exception('Failed to fetch directions: $e');
    }
  }
}
```
