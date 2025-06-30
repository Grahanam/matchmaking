import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class LinkUtils {
  // Expand maps.app.goo.gl link
  static Future<String?> expandShortGoogleMapsUrl(String shortUrl) async {
    try {
      final client = http.Client();
      final response = await client.get(
        Uri.parse(shortUrl),
        headers: {
          HttpHeaders.userAgentHeader: 'Mozilla/5.0',
        },
      );
      print('Resolved URL: ${response.request?.url}');
      final resolvedUrl = response.request?.url.toString();
      print('$resolvedUrl');
      return resolvedUrl;
    } catch (e) {
      return null;
    }
  }

  // Extract coordinates from final URL
  static GeoPoint? extractCoordinates(String url) {
    try {
      final atPattern = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)');
      final atMatch = atPattern.firstMatch(url);
      if (atMatch != null) {
        return GeoPoint(
          double.parse(atMatch.group(1)!),
          double.parse(atMatch.group(2)!),
        );
      }

      final llPattern = RegExp(r'll=(-?\d+\.\d+),(-?\d+\.\d+)');
      final llMatch = llPattern.firstMatch(url);
      if (llMatch != null) {
        return GeoPoint(
          double.parse(llMatch.group(1)!),
          double.parse(llMatch.group(2)!),
        );
      }

      final coordPattern = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)');
      final match = coordPattern.firstMatch(url);
      if (match != null) {
        return GeoPoint(
          double.parse(match.group(1)!),
          double.parse(match.group(2)!),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
