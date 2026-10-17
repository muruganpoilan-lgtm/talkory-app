import 'package:geolocator/geolocator.dart';
import 'api.dart';

/// Asks for location ("While using the app") once the person is signed in, then shares an approximate position
/// (the server rounds it to about 1 km). Quietly does nothing if the person says no.
class LocationShare {
  static DateTime? _last;

  static Future<void> share(Api api) async {
    try {
      final now = DateTime.now();
      if (_last != null && now.difference(_last!) < const Duration(hours: 6)) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)));
      await api.saveLocation(p.latitude, p.longitude);
      _last = now;
    } catch (_) {}
  }
}
