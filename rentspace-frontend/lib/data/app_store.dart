import 'package:flutter/foundation.dart';

import '../models/domain.dart';
import '../services/api_client.dart';
import '../services/remote_store.dart';

class AppStore extends ChangeNotifier {
  AppStore({DateTime Function()? clock, ApiClient? api})
    : clock = clock ?? DateTime.now,
      api = api ?? ApiClient();
  final ApiClient api;
  final List<Map<String, dynamic>> busySlots = [];
  final Map<String, List<SpaceReview>> publicReviews = {};
  String? syncError;
  Future<void> _refreshTail = Future.value();
  Future<void>? _activePoll;
  int sessionVersion = 0;
  Future<void> refresh() {
    final version = sessionVersion;
    final pending = _refreshTail.then((_) => _loadSnapshot(version));
    _refreshTail = pending.catchError((Object _) {});
    return pending;
  }

  int beginSession(String token) {
    final session = ++sessionVersion;
    _refreshTail = Future.value();
    _activePoll = null;
    api.token = token;
    return session;
  }

  Future<void> _loadSnapshot(int version) async {
    if (api.token == null || version != sessionVersion) return;
    final snapshot = await api.request('GET', '/state');
    if (version != sessionVersion) return;
    applySnapshot(this, snapshot);
    syncError = null;
    notifyListeners();
  }

  Future<void> poll() {
    final inFlight = _activePoll;
    if (inFlight != null) return inFlight;
    final future = () async {
      try {
        await refresh();
      } on DomainError catch (e) {
        syncError = e.message;
        notifyListeners();
      } finally {
        _activePoll = null;
      }
    }();
    _activePoll = future;
    return future;
  }

  Future<dynamic> mutate(String method, String path, [Object? body]) async {
    final response = await api.request(method, path, body);
    try {
      await refresh();
    } on DomainError {
      throw DomainError(
        'บันทึกแล้ว แต่โหลดข้อมูลล่าสุดไม่ได้ กรุณารีเฟรชก่อนทำรายการซ้ำ',
      );
    }
    return response;
  }

  void clearSession() {
    sessionVersion++;
    _refreshTail = Future.value();
    _activePoll = null;
    api.token = null;
    currentUser = null;
    users.clear();
    spaces.clear();
    bookings.clear();
    issues.clear();
    logs.clear();
    busySlots.clear();
    publicReviews.clear();
    syncError = null;
    notifyListeners();
  }

  final DateTime Function() clock;
  final List<AppUser> users = [];
  final List<Space> spaces = [];
  final List<Booking> bookings = [];
  final List<Issue> issues = [];
  final List<AuditEntry> logs = [];
  AppUser? currentUser;

  /// Explicit light/dark preference. Starts in light mode; the toggle in the
  /// app bar and sidebar flips it without touching the business data.
  bool darkMode = false;
  void toggleTheme() {
    darkMode = !darkMode;
    notifyListeners();
  }

  AppUser requireUser([UserRole? role]) {
    final user = currentUser;
    if (user == null || !user.active) {
      throw DomainError('กรุณาเข้าสู่ระบบด้วยบัญชีที่ใช้งานได้');
    }
    if (role != null && role != user.role) {
      throw DomainError('บัญชีนี้ไม่มีสิทธิ์ทำรายการ');
    }
    return user;
  }

  Space space(String id) => spaces.firstWhere(
    (s) => s.id == id,
    orElse: () => throw DomainError('ไม่พบพื้นที่'),
  );
  Booking booking(String id) => bookings.firstWhere(
    (b) => b.id == id,
    orElse: () => throw DomainError('ไม่พบการจอง'),
  );
  Booking? maybeBooking(String id) {
    for (final entry in bookings) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  AppUser user(String id) => users.firstWhere(
    (u) => u.id == id,
    orElse: () => throw DomainError('ไม่พบบัญชี'),
  );
  AppUser? maybeUser(String id) {
    for (final entry in users) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  List<Booking> visibleBookings() {
    final u = requireUser();
    return bookings
        .where(
          (b) =>
              u.role == UserRole.admin ||
              (u.role == UserRole.owner
                  ? b.ownerId == u.id
                  : b.renterId == u.id),
        )
        .toList();
  }

  List<int> navBadges() {
    final u = currentUser;
    if (u == null) return const [];
    return switch (u.role) {
      UserRole.renter => _renterBadges(u.id),
      UserRole.owner => _ownerBadges(u.id),
      UserRole.admin => _adminBadges(),
    };
  }

  List<int> _renterBadges(String userId) {
    final actionNeeded = bookings
        .where(
          (b) =>
              b.renterId == userId &&
              (b.status == BookingStatus.paymentDue ||
                  b.status == BookingStatus.slipRejected),
        )
        .length;
    return [0, actionNeeded, 0, 0];
  }

  List<int> _ownerBadges(String userId) {
    final rejectedSpaces = spaces
        .where((s) => s.ownerId == userId && s.status == SpaceStatus.rejected)
        .length;
    final pendingRequests = bookings
        .where(
          (b) => b.ownerId == userId && b.status == BookingStatus.ownerReview,
        )
        .length;
    final readyPayouts = bookings
        .where(
          (b) =>
              b.ownerId == userId &&
              b.status == BookingStatus.completed &&
              b.paidOutAt == null,
        )
        .length;
    return [0, rejectedSpaces, pendingRequests, readyPayouts, 0];
  }

  List<int> _adminBadges() {
    final moderationCount =
        spaces.where((s) => s.status == SpaceStatus.pending).length +
        issues.where((i) => !i.closed).length;
    final financeCount = bookings
        .where(
          (b) =>
              b.status == BookingStatus.slipReview ||
              (b.status == BookingStatus.completed && b.paidOutAt == null),
        )
        .length;
    return [0, moderationCount, financeCount, 0, 0];
  }

  bool conflicts(
    String spaceId,
    DateTime date,
    int start,
    int end, {
    int days = 1,
    String? excluding,
  }) {
    if (excluding == null) {
      for (final slot in busySlots) {
        final first = DateTime.parse('${slot['booking_date']}');
        final last = first.add(
          Duration(days: (slot['days_count'] as num).toInt() - 1),
        );
        final requestedLast = dateOnly(date).add(Duration(days: days - 1));
        if (slot['space_id'] == spaceId &&
            !dateOnly(date).isAfter(last) &&
            !requestedLast.isBefore(first) &&
            (slot['start_minutes'] as num).toInt() < end &&
            (slot['end_minutes'] as num).toInt() > start) {
          return true;
        }
      }
    }
    for (var i = 0; i < days; i++) {
      final dayDate = dateOnly(date).add(Duration(days: i));
      if (_conflictsOnDay(spaceId, dayDate, start, end, excluding)) {
        return true;
      }
    }
    return false;
  }

  bool _conflictsOnDay(
    String spaceId,
    DateTime dayDate,
    int start,
    int end,
    String? excluding,
  ) => bookings.any(
    (b) =>
        b.id != excluding &&
        b.spaceId == spaceId &&
        b.status.holdsTime &&
        b.coversDate(dayDate) &&
        b.startMinutes < end &&
        b.endMinutes > start,
  );
}
