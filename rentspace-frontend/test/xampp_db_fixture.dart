import 'dart:convert';
import 'dart:io';

import 'package:rentspace/data/app_store.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/services/remote_store.dart';

const String _backendOrigin = 'http://127.0.0.1:3001/api';

/// Loads a snapshot of the XAMPP-backed `rent_space` database from the live
/// Express API when available, falling back to the checked-in XAMPP export.
Future<Map<String, dynamic>> loadXamppSnapshot({bool allowLiveApi = true}) async {
  if (allowLiveApi) {
    final liveSnapshot = await _fetchLiveSnapshot();
    if (liveSnapshot != null) return liveSnapshot;
  }
  final fixtureFile = _resolveFixtureFile();
  final rawText = await fixtureFile.readAsString();
  return Map<String, dynamic>.from(jsonDecode(rawText) as Map);
}

File _resolveFixtureFile() {
  for (final candidate in const [
    'test/fixtures/xampp_state_snapshot.json',
    'rentspace-frontend/test/fixtures/xampp_state_snapshot.json',
  ]) {
    final file = File(candidate);
    if (file.existsSync()) return file;
  }
  throw StateError('Missing test/fixtures/xampp_state_snapshot.json');
}

Future<Map<String, dynamic>?> _fetchLiveSnapshot() async {
  final previousOverrides = HttpOverrides.current;
  HttpOverrides.global = null;
  final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 500);
  try {
    final healthOk = await _isHealthy(client);
    if (!healthOk) return null;
    final token = await _loginAdminToken(client);
    if (token == null || token.isEmpty) return null;
    return await _getStateMap(client, token);
  } on Object {
    return null;
  } finally {
    client.close(force: true);
    HttpOverrides.global = previousOverrides;
  }
}

Future<bool> _isHealthy(HttpClient client) async {
  final request = await client
      .getUrl(Uri.parse('$_backendOrigin/health'))
      .timeout(const Duration(milliseconds: 500));
  final response = await request.close().timeout(const Duration(milliseconds: 500));
  await response.drain<void>();
  return response.statusCode == 200;
}

Future<String?> _loginAdminToken(HttpClient client) async {
  final request = await client
      .postUrl(Uri.parse('$_backendOrigin/auth/login'))
      .timeout(const Duration(seconds: 2));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'email': 'admin01@rentspace.test', 'password': 'password'}));
  final response = await request.close().timeout(const Duration(seconds: 2));
  final bodyText = await utf8.decodeStream(response);
  if (response.statusCode != 200) return null;
  final decoded = jsonDecode(bodyText) as Map<String, dynamic>;
  return decoded['token'] as String?;
}

Future<Map<String, dynamic>?> _getStateMap(HttpClient client, String token) async {
  final request = await client
      .getUrl(Uri.parse('$_backendOrigin/state'))
      .timeout(const Duration(seconds: 2));
  request.headers.set('Authorization', 'Bearer $token');
  final response = await request.close().timeout(const Duration(seconds: 2));
  final bodyText = await utf8.decodeStream(response);
  if (response.statusCode != 200) return null;
  return Map<String, dynamic>.from(jsonDecode(bodyText) as Map);
}

/// Hydrates [store] via [applySnapshot] using a deep clone of [sourceSnapshot].
void populateStoreFromXamppSnapshot(
  AppStore store,
  Map<String, dynamic> sourceSnapshot, {
  required String viewerId,
}) {
  final clonedSnapshot = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(sourceSnapshot)) as Map,
  );
  clonedSnapshot['userId'] = viewerId;
  applySnapshot(store, clonedSnapshot);
}

/// Finds an existing DB booking in [status] matching optional filters, or inserts
/// one bound to the real DB space (`2001`) when no row currently sits in [status].
Booking findOrSeedBooking(
  AppStore store, {
  required BookingStatus status,
  String? preferredId,
  String? spaceId,
  String? renterId,
  DateTime? overrideDate,
  int startMinutes = 540,
  int endMinutes = 660,
  bool requirePendingPayout = false,
}) {
  for (final existing in store.bookings) {
    final matchesId = preferredId == null || existing.id == preferredId;
    final matchesSpace = spaceId == null || existing.spaceId == spaceId;
    final matchesRenter = renterId == null || existing.renterId == renterId;
    final matchesPayout = !requirePendingPayout || existing.paidOutAt == null;
    if (existing.status == status &&
        matchesId &&
        matchesSpace &&
        matchesRenter &&
        matchesPayout) {
      return existing;
    }
  }
  final targetSpace = store.space(spaceId ?? '2001');
  final seededId = preferredId ?? '39${status.index}0';
  final created = Booking(
    id: seededId,
    spaceId: targetSpace.id,
    ownerId: targetSpace.ownerId,
    renterId: renterId ?? '1002',
    spaceName: targetSpace.name,
    date: overrideDate ?? store.clock().add(const Duration(days: 5)),
    startMinutes: startMinutes,
    endMinutes: endMinutes,
    rentAmount: targetSpace.price * 2,
    status: status,
  )..createdAt = store.clock();
  store.bookings.add(created);
  return created;
}
