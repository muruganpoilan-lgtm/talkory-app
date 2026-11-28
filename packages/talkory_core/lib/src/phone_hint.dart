import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_auth/smart_auth.dart';

/// Google's "Choose a phone number" sheet (Android). It lists the SIM numbers on this phone;
/// tapping one fills the number in, so nobody has to type it. Returns 10 digits, or null if
/// the person closed the sheet, the phone has no number to offer, or this is not Android.
Future<String?> pickPhoneNumber() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final res = await SmartAuth.instance.requestPhoneNumberHint();
    if (!res.hasData) return null;
    return tenDigits(res.data);
  } catch (_) {
    return null; // no Google Play services, or the sheet failed: typing still works
  }
}

/// "+91 93457 77130", "093457 77130" or "9345777130" -> "9345777130". Null if it is not an Indian mobile.
String? tenDigits(String? raw) {
  var d = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  return RegExp(r'^[6-9]\d{9}$').hasMatch(d) ? d : null;
}

/// The last number that signed in on this phone, per app role, so the next login is one tap.
Future<String?> lastPhone(String role) async => (await SharedPreferences.getInstance()).getString('lastPhone:$role');
Future<void> saveLastPhone(String role, String tenDigitPhone) async =>
    (await SharedPreferences.getInstance()).setString('lastPhone:$role', tenDigitPhone);
Future<void> forgetLastPhone(String role) async => (await SharedPreferences.getInstance()).remove('lastPhone:$role');
