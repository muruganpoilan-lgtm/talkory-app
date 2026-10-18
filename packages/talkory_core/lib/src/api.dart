import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Override at build time: flutter run --dart-define=API_URL=https://api.example.com
/// 10.0.2.2 is the host machine as seen from the Android emulator.
const kBaseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000');

/// Keep in sync with LANGUAGES in backend/src/partners.js
const kLanguages = ['Hindi', 'English', 'Tamil', 'Telugu', 'Bengali', 'Marathi', 'Odia', 'Bhojpuri', 'Malayalam', 'Kannada', 'Gujarati', 'Punjabi', 'Urdu', 'Assamese'];

/// Coins shown to users: 1 coin = ₹1, kept in paise on the server. 3000 -> "30", 70 -> "0.7", 1850 -> "18.5".
String formatCoins(int paise) {
  if (paise % 100 == 0) return '${paise ~/ 100}';
  if (paise % 10 == 0) return (paise / 100).toStringAsFixed(1);
  return (paise / 100).toStringAsFixed(2);
}

/// What one chat message costs a user, in paise (0.3 coins). Keep in sync with MESSAGE_COST in backend/src/chat.js
const kMessageCostPaise = 30;

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class CallSession {
  CallSession({required this.callId, required this.appId, required this.channel, required this.token, required this.uid});
  final String callId, appId, channel, token;
  final int uid;

  factory CallSession.fromJson(Map<String, dynamic> j) => CallSession(
        callId: j['callId'] as String,
        appId: j['appId'] as String,
        channel: j['channel'] as String,
        token: j['token'] as String,
        uid: j['uid'] as int,
      );
}

class Partner {
  Partner.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['display_name'],
        bio = j['bio'] ?? '',
        tagline = j['tagline'] ?? '',
        languages = List<String>.from(j['languages'] ?? []),
        ratePerMin = j['rate_per_min'],
        rating = double.tryParse('${j['rating_avg']}') ?? 0,
        ratingCount = j['rating_count'] ?? 0,
        busy = j['busy'] == true,
        status = (j['status'] as String?) ?? (j['busy'] == true ? 'busy' : 'online'),
        avatarUrl = j['avatar_url'],
        introUrl = j['intro_url'],
        verified = j['verified'] == true;
  final String id, name, bio, tagline;
  final String? introUrl; // approved voice intro, path like /intros/abc.m4a
  final String? avatarUrl; // path like /avatars/abc.jpg, prefix with Api.baseUrl
  final List<String> languages;
  final int ratePerMin, ratingCount;
  final double rating;
  final bool busy, verified;
  final String status; // 'online' | 'busy' | 'offline'
}

class Api {
  Api([this.baseUrl = kBaseUrl]);
  final String baseUrl;
  String? token;

  Future<void> load() async => token = (await SharedPreferences.getInstance()).getString('token');

  Future<void> logout() async {
    token = null;
    await (await SharedPreferences.getInstance()).remove('token');
  }

  Future<dynamic> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final payload = jsonEncode(body ?? {});
    final res = switch (method) {
      'GET' => await http.get(uri, headers: headers),
      'PUT' => await http.put(uri, headers: headers, body: payload),
      _ => await http.post(uri, headers: headers, body: payload),
    };
    final data = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, (data is Map ? data['error'] : null)?.toString() ?? 'Request failed');
    }
    return data;
  }

  // ---- auth
  Future<void> requestOtp(String phone) => _send('POST', '/auth/request-otp', {'phone': phone});

  Future<void> verifyOtp({
    required String phone,
    required String code,
    required String role,
    String? displayName,
    bool isAdult = false,
    bool acceptedTerms = false,
  }) async {
    final data = await _send('POST', '/auth/verify-otp', {
      'phone': phone,
      'code': code,
      'role': role,
      'displayName': displayName,
      'isAdult': isAdult,
      'acceptedTerms': acceptedTerms,
    });
    token = data['token'];
    await (await SharedPreferences.getInstance()).setString('token', token!);
  }

  // ---- user app
  Future<List<Partner>> listPartners({String? language, String? query}) async {
    final params = <String, String>{'all': '1', if (language != null) 'language': language, if (query != null && query.isNotEmpty) 'q': query};
    final q = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    final data = await _send('GET', '/partners$q') as List;
    return data.map((e) => Partner.fromJson(e)).toList();
  }

  /// Hosts this user has called before (answered or missed) who are online right now, most recent first.
  Future<List<Partner>> bestFriendsOnline() async {
    final data = await _send('GET', '/partners/best-friends') as List;
    return data.map((e) => Partner.fromJson(e)).toList();
  }

  Future<CallSession> startCall(String partnerId) async =>
      CallSession.fromJson(await _send('POST', '/calls', {'partnerId': partnerId}));

  /// {available: bool, seconds: 120, nextAt: ISO time or null}: the free 2-minute call (one every 2 hours)
  Future<Map<String, dynamic>> freeCallStatus() async => Map<String, dynamic>.from(await _send('GET', '/calls/free-status') as Map);

  // ---- host-started calls
  /// Host: ring a user who has messaged them.
  Future<CallSession> hostCall(String userId) async =>
      CallSession.fromJson(await _send('POST', '/host-calls', {'userId': userId}));

  /// User: returns {id, partner_name} while a host is ringing, else null.
  Future<Map<String, dynamic>?> hostCallIncoming() async =>
      (await _send('GET', '/host-calls/incoming')) as Map<String, dynamic>?;

  Future<CallSession> acceptHostCall(String id) async =>
      CallSession.fromJson(await _send('POST', '/host-calls/$id/accept'));

  Future<void> rejectHostCall(String id) => _send('POST', '/host-calls/$id/reject');

  /// Host side: {available, seconds, nextAt} for the free 2-minute call to this user.
  Future<Map<String, dynamic>> hostFreeStatus(String userId) async =>
      Map<String, dynamic>.from(await _send('GET', '/host-calls/free-status?userId=$userId'));

  // ---- partner app
  Future<void> setOnline(bool online) => _send('POST', '/partners/online', {'online': online});

  /// status: 'online' | 'busy' | 'offline'
  Future<void> setStatus(String status) => _send('POST', '/partners/online', {'status': status, 'online': status != 'offline'});

  /// Returns {id, user_name} or null.
  Future<Map<String, dynamic>?> incomingCall() async =>
      (await _send('GET', '/calls/incoming')) as Map<String, dynamic>?;

  // ---- admin app: generic calls to the admin endpoints, and starting video calls
  Future<dynamic> adminGet(String path) => _send('GET', path);
  Future<dynamic> adminPost(String path, [Map<String, dynamic>? body]) => _send('POST', path, body);
  Future<List<int>> adminBytes(String path) async {
    final res = await http.get(Uri.parse('$baseUrl$path'), headers: {if (token != null) 'Authorization': 'Bearer $token'});
    if (res.statusCode >= 400) throw ApiException(res.statusCode, 'File not found');
    return res.bodyBytes;
  }
  Future<CallSession> adminStartVideo(String accountId) async =>
      CallSession.fromJson(await _send('POST', '/admin/video-calls', {'accountId': accountId}));
  Future<String> adminVideoStatus(String id) async => (await _send('GET', '/admin/video-calls/$id') as Map)['status'] as String;
  Future<void> adminEndVideo(String id) => _send('POST', '/admin/video-calls/$id/end');

  // ---- video calls started by the Talkory team from the admin panel (apps can only answer them)
  Future<Map<String, dynamic>?> adminCallIncoming() async => (await _send('GET', '/admin-calls/incoming')) as Map<String, dynamic>?;
  Future<CallSession> acceptAdminCall(String id) async => CallSession.fromJson(await _send('POST', '/admin-calls/$id/accept'));
  Future<void> rejectAdminCall(String id) => _send('POST', '/admin-calls/$id/reject');
  Future<void> endAdminCall(String id) => _send('POST', '/admin-calls/$id/end');
  Future<String> adminCallStatus(String id) async => (await _send('GET', '/admin-calls/$id/status') as Map)['status'] as String;

  // ---- group meetings (free; only admins create them)
  Future<List<dynamic>> liveMeetings() async => ((await _send('GET', '/meetings/live')) as List?) ?? [];
  Future<CallSession> joinMeeting(String id) async => CallSession.fromJson(await _send('POST', '/meetings/$id/join'));
  Future<String> meetingStatus(String id) async => (await _send('GET', '/meetings/$id/status') as Map)['status'] as String;
  Future<Map<String, dynamic>> adminCreateMeeting({required String title, required String audience, List<String> accountIds = const [], DateTime? scheduledAt}) async =>
      Map<String, dynamic>.from(await _send('POST', '/admin/meetings', {
        'title': title,
        'audience': audience,
        if (accountIds.isNotEmpty) 'accountIds': accountIds,
        if (scheduledAt != null) 'scheduledAt': scheduledAt.toUtc().toIso8601String(),
      }) as Map);
  Future<CallSession> adminJoinMeeting(String id) async => CallSession.fromJson(await _send('POST', '/admin/meetings/$id/join'));
  Future<String> adminMeetingStatus(String id) async => (await _send('GET', '/admin/meetings/$id') as Map)['status'] as String;
  Future<void> adminEndMeeting(String id) => _send('POST', '/admin/meetings/$id/end');

  Future<CallSession> acceptCall(String id) async =>
      CallSession.fromJson(await _send('POST', '/calls/$id/accept'));

  Future<void> rejectCall(String id) => _send('POST', '/calls/$id/reject');

  // ---- wallet (amounts in paise)
  /// Activity feed, 30 per page: [{kind: topup|call|refund|adjustment, id, amount (paise, negative = spent), at, counterpart, seconds}]
  Future<List<Map<String, dynamic>>> walletHistory(int page) async =>
      (await _send('GET', '/wallet/history?page=$page') as List).map((e) => Map<String, dynamic>.from(e)).toList();

  Future<int> walletBalance() async => (await _send('GET', '/wallet'))['balance'] as int;

  /// Returns {orderId, keyId, amount, currency} for Razorpay checkout.
  Future<Map<String, dynamic>> createTopup(int amountRupees) async =>
      Map<String, dynamic>.from(await _send('POST', '/wallet/topup', {'amountRupees': amountRupees}));

  /// Sends the checkout result for server-side signature verification. Returns the new balance.
  Future<int> verifyTopup({required String orderId, required String paymentId, required String signature}) async =>
      (await _send('POST', '/wallet/topup/verify', {'orderId': orderId, 'paymentId': paymentId, 'signature': signature}))['balance'] as int;

  // ---- partner earnings & payouts (amounts in paise)
  Future<Map<String, dynamic>> partnerEarnings() async =>
      Map<String, dynamic>.from(await _send('GET', '/partner/earnings'));

  Future<void> setPayoutMethod(String upiId) => _send('PUT', '/partner/payout-method', {'upiId': upiId});

  Future<void> requestPayout(int amountRupees) => _send('POST', '/partner/payouts', {'amountRupees': amountRupees});

  // ---- push token registration (platform: 'android' | 'ios')
  Future<void> registerDevice({required String platform, required String pushToken, String? voipToken}) =>
      _send('POST', '/devices', {'platform': platform, 'pushToken': pushToken, 'voipToken': voipToken});

  Future<void> unregisterDevice(String pushToken) => _send('POST', '/devices/unregister', {'pushToken': pushToken});

  // ---- post-call (the server works out who the other party is from the call)
  Future<void> rateCall(String callId, int stars, String comment) =>
      _send('POST', '/calls/$callId/rate', {'stars': stars, 'comment': comment});
  Future<void> reportCall(String callId, String reason) => _send('POST', '/calls/$callId/report', {'reason': reason});
  Future<void> blockCall(String callId) => _send('POST', '/calls/$callId/block');

  /// {status, secondsLeft}: secondsLeft is null for the partner side.
  Future<Map<String, dynamic>> callStatus(String callId) async =>
      Map<String, dynamic>.from(await _send('GET', '/calls/$callId/status'));

  // ---- partner profile
  Future<void> uploadAvatar(String imageBase64) => _send('POST', '/partner/avatar', {'imageBase64': imageBase64});
  Future<void> removeAvatar() => _send('POST', '/partner/avatar/remove');

  Future<Map<String, dynamic>> myProfile() async => Map<String, dynamic>.from(await _send('GET', '/partners/me'));

  Future<void> saveProfile({required String displayName, String tagline = '', required String bio, required List<String> languages, required int rateRupees}) =>
      _send('PUT', '/partners/me', {'displayName': displayName, 'tagline': tagline, 'bio': bio, 'languages': languages, 'rateRupees': rateRupees});

  // ---- partner KYC
  /// {status: pending|approved|rejected, submitted, note, docs: [id_front, selfie]}
  Future<Map<String, dynamic>> kycStatus() async => Map<String, dynamic>.from(await _send('GET', '/partner/kyc/status'));

  Future<void> uploadKycDocument(String kind, String imageBase64) =>
      _send('POST', '/partner/kyc/documents', {'kind': kind, 'imageBase64': imageBase64});

  Future<void> submitKyc() => _send('POST', '/partner/kyc/submit');

  /// {role, displayName, phone, avatarUrl, supportEmail}
  Future<Map<String, dynamic>> accountMe() async => Map<String, dynamic>.from(await _send('GET', '/account/me'));

  /// Approximate position, shared only after the person allowed location in the phone's permission box.
  Future<void> saveLocation(double lat, double lng) => _send('PUT', '/account/location', {'lat': lat, 'lng': lng});

  Future<void> setGst(String gstin) => _send('PUT', '/account/gst', {'gstNumber': gstin});

  // ---- user's own photo (only they see it)
  Future<void> uploadUserAvatar(String imageBase64) => _send('POST', '/account/avatar', {'imageBase64': imageBase64});
  Future<void> removeUserAvatar() => _send('POST', '/account/avatar/remove');

  // ---- partner voice intro (reviewed by admin before users can hear it)
  Future<void> uploadIntro(String audioBase64) => _send('POST', '/partner/intro', {'audioBase64': audioBase64});
  Future<void> removeIntro() => _send('POST', '/partner/intro/remove');

  // ---- chat. Users pay 0.3 coins per message they send; host replies are free.
  /// [{id (other person), name, avatar_url, last_body, last_at, unread}]
  Future<List<Map<String, dynamic>>> chatThreads() async =>
      (await _send('GET', '/chat/threads') as List).map((e) => Map<String, dynamic>.from(e)).toList();

  Future<int> chatUnread() async => (await _send('GET', '/chat/unread'))['unread'] as int;

  /// [{id, body, created_at, mine}] oldest first. Pass [after] to get only newer messages.
  Future<List<Map<String, dynamic>>> chatMessages(String otherId, {int after = 0}) async =>
      (await _send('GET', '/chat/$otherId/messages?after=$after') as List).map((e) => Map<String, dynamic>.from(e)).toList();

  /// True once this user and host have had more than 5 answered calls together.
  Future<bool> isBestFriend(String otherId) async => (await _send('GET', '/chat/$otherId/info') as Map)['bestFriend'] == true;

  /// Returns the stored message (plus `balance` in paise for users). Throws ApiException(402) when out of coins.
  Future<Map<String, dynamic>> sendMessage(String otherId, String body) async =>
      Map<String, dynamic>.from(await _send('POST', '/chat/$otherId', {'body': body}));

  Future<void> reportChat(String otherId, String reason) => _send('POST', '/chat/$otherId/report', {'reason': reason});
  Future<void> blockChat(String otherId) => _send('POST', '/chat/$otherId/block');

  // ---- customer support tickets (both apps)
  /// [{id, subject, status, customer_unread, updated_at, last_body}]
  Future<List<Map<String, dynamic>>> supportTickets() async =>
      (await _send('GET', '/support-tickets') as List).map((e) => Map<String, dynamic>.from(e)).toList();

  Future<void> createSupportTicket(String subject, String body) => _send('POST', '/support-tickets', {'subject': subject, 'body': body});

  /// {ticket: {id, subject, status}, messages: [{id, from_admin, body, created_at}]}
  Future<Map<String, dynamic>> supportTicket(String id) async => Map<String, dynamic>.from(await _send('GET', '/support-tickets/$id'));

  Future<void> replySupportTicket(String id, String body) => _send('POST', '/support-tickets/$id/reply', {'body': body});

  Future<void> deleteAccount() => _send('POST', '/account/delete', {'confirm': 'DELETE'});

  // ---- both
  Future<void> endCall(String id) => _send('POST', '/calls/$id/end');
}
