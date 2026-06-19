import 'dart:convert';
import 'dart:io';

/// Geocodes UK postcodes using the free postcodes.io public API.
/// No API key required.
class PostcodeGeocoder {
  PostcodeGeocoder._();

  static final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  // Full UK postcode: outward (1-4 chars) + space + inward (3 chars)
  static final _pattern = RegExp(
    r'^[A-Z]{1,2}[0-9][0-9A-Z]?\s*[0-9][A-Z]{2}$',
    caseSensitive: false,
  );

  static bool isPostcode(String query) => _pattern.hasMatch(query.trim());

  /// Returns [lat, lon] for [postcode], or null if lookup fails.
  static Future<({double lat, double lon})?> geocode(String postcode) async {
    final pc = postcode.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    try {
      final req = await _client.getUrl(
        Uri.https('api.postcodes.io', '/postcodes/$pc'),
      );
      req.headers.set('Accept', 'application/json');
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if ((json['status'] as int) != 200) return null;
      final r = json['result'] as Map<String, dynamic>;
      return (
        lat: (r['latitude']  as num).toDouble(),
        lon: (r['longitude'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
