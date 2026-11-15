import 'dart:convert';
import 'dart:typed_data';
import '../data/app_store.dart';
import '../models/domain.dart';

String _str(dynamic v) => v == null ? '' : '$v';
List<dynamic> _list(dynamic v) =>
    v is String ? jsonDecode(v) as List : (v as List? ?? []);
int _int(dynamic v) => v is num ? v.toInt() : int.parse('$v');
bool _bool(dynamic v) => v == true || v == 1;
DateTime? _time(dynamic v) => v == null ? null : DateTime.parse('$v');
String _camel(String v) =>
    v.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());

ReasonKind _parseReasonKind(dynamic rawKind, BookingStatus status) {
  final text = _str(rawKind);
  if (text.isNotEmpty) {
    final mapped = ReasonKind.values.asNameMap()[_camel(text)];
    if (mapped != null) return mapped;
  }
  return switch (status) {
    BookingStatus.ownerRejected => ReasonKind.ownerRejected,
    BookingStatus.slipRejected => ReasonKind.slipRejected,
    BookingStatus.canceled => ReasonKind.canceledByUser,
    _ => ReasonKind.none,
  };
}

String _resolveMediaUrl(AppStore store, String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('/')) return trimmed;
  return Uri.parse(store.api.baseUrl).resolve(trimmed).toString();
}

void applySnapshot(AppStore store, Map<String, dynamic> data) {
  final users = (data['users'] as List)
      .map(
        (u) => AppUser(
          id: _str(u['id']),
          name: _str(u['name']),
          email: u['email'] ?? '',
          password: '',
          role: UserRole.values.byName(_str(u['role'])),
          phone: u['phone'] ?? '',
          bankInfo: u['bank_info'] ?? '',
          active: _bool(u['active']),
        ),
      )
      .toList();
  final currentId = _str(data['userId']);
  final current = users.firstWhere((u) => u.id == currentId);
  current.favorites.addAll((data['favorites'] as List).map(_str));
  final spaces = (data['spaces'] as List).map((s) {
    final spaceId = _str(s['id']);
    final rawImage = s['image'] as String? ?? '';
    final space = Space(
      id: spaceId,
      ownerId: _str(s['owner_id']),
      name: _str(s['name']),
      category: _str(s['category']),
      location: _str(s['location']),
      price: _int(s['price']),
      capacity: _int(s['capacity']),
      description: _str(s['description']),
      image: rawImage.startsWith('data:')
          ? ''
          : _resolveMediaUrl(store, rawImage),
      imageBytes: rawImage.startsWith('data:')
          ? base64Decode(rawImage.split(',').last)
          : null,
      amenities: List<String>.from(_list(s['amenities'])),
      status: SpaceStatus.values.byName(_str(s['status'])),
      availability: Availability(
        days: _list(s['hours'])
            .map(
              (d) => DayHours(
                open: _bool(d['open']),
                start: _int(d['start']),
                end: _int(d['end']),
              ),
            )
            .toList(),
        blocks: (data['blocks'] as List)
            .where((b) => _str(b['space_id']) == spaceId)
            .map(
              (b) => BlockedPeriod(
                id: _str(b['id']),
                start: _time(b['start_at'])!,
                end: _time(b['end_at'])!,
                reason: _str(b['reason']),
              ),
            )
            .toList(),
      ),
      dbRating: s['avg_rating'] == null
          ? null
          : (s['avg_rating'] as num).toDouble(),
      dbReviewCount: _int(s['review_count'] ?? 0),
    );
    space.reviewReason = s['review_reason'] ?? '';
    return space;
  }).toList();
  SpaceReview review(dynamic r) => SpaceReview(
    rating: _int(r['rating']),
    comment: r['comment'] ?? '',
    createdAt: _time(r['created_at'])!,
  );
  final bookings = (data['bookings'] as List).map((b) {
    final booking = Booking(
      id: _str(b['id']),
      spaceId: _str(b['space_id']),
      ownerId: _str(b['owner_id']),
      renterId: _str(b['renter_id']),
      spaceName: _str(b['space_name']),
      date: _time(b['booking_date'])!,
      startMinutes: _int(b['start_minutes']),
      endMinutes: _int(b['end_minutes']),
      rentAmount: _int(b['rent_amount']),
      platformFee: b['platform_fee'] == null ? null : _int(b['platform_fee']),
      days: _int(b['days_count']),
      attendees: _int(b['attendees']),
      zone: _str(b['zone']),
      renterNote: b['renter_note'] ?? '',
      status: BookingStatus.values.byName(_camel(_str(b['status']))),
    );
    booking.reason = b['reason'] ?? '';
    booking.createdAt = _time(b['created_at']);
    booking.approvedAt = _time(b['approved_at']);
    booking.slipRejectedAt = _time(b['slip_rejected_at']);
    booking.confirmedAt = _time(b['confirmed_at']);
    booking.completedAt = _time(b['completed_at']);
    booking.paidOutAt = _time(b['paid_out_at']);
    final payoutName = _str(b['payout_slip_name']);
    final payoutData = b['payout_slip_data'] as String? ?? '';
    final payoutUrl = _resolveMediaUrl(
      store,
      b['payout_slip_url'] as String? ?? '',
    );
    final payoutNote = b['payout_note'] as String? ?? '';
    if (booking.paidOutAt != null &&
        (payoutName.isNotEmpty ||
            payoutData.isNotEmpty ||
            payoutUrl.isNotEmpty ||
            payoutNote.isNotEmpty)) {
      booking.payoutSlip = PaymentSlip(
        name: payoutName.isEmpty ? 'payout_slip.jpg' : payoutName,
        bytes: payoutData.isNotEmpty
            ? base64Decode(payoutData)
            : Uint8List(0),
        submittedAt: booking.paidOutAt!,
        note: payoutNote,
        imageUrl: payoutUrl,
      );
    }
    booking.reasonKind = _parseReasonKind(b['reason_kind'], booking.status);
    for (final s in data['slips']) {
      if (_str(s['booking_id']) != booking.id) continue;
      final imageData = s['image_data'] as String? ?? '';
      final imageUrl = _resolveMediaUrl(store, s['image_url'] as String? ?? '');
      booking.slips.add(
        PaymentSlip(
          name: _str(s['file_name']),
          bytes: imageData.isNotEmpty
              ? base64Decode(imageData)
              : Uint8List(0),
          submittedAt: _time(s['submitted_at'])!,
          note: s['note'] ?? '',
          imageUrl: imageUrl,
        )..rejectionReason = s['rejection_reason'] ?? '',
      );
    }
    for (final r in data['reviews']) {
      if (_str(r['booking_id']) == booking.id) booking.review = review(r);
    }
    return booking;
  }).toList();
  final issues = (data['issues'] as List)
      .map(
        (i) =>
            Issue(
                id: _str(i['id']),
                reporterId: _str(i['reporter_id']),
                subject: _str(i['subject']),
                detail: _str(i['detail']),
              )
              ..closed = _bool(i['closed'])
              ..resolution = i['resolution'] ?? '',
      )
      .toList();
  store.users
    ..clear()
    ..addAll(users);
  store.spaces
    ..clear()
    ..addAll(spaces);
  store.bookings
    ..clear()
    ..addAll(bookings);
  store.issues
    ..clear()
    ..addAll(issues);
  store.busySlots
    ..clear()
    ..addAll(
      (data['busy'] as List).map((raw) {
        final busy = Map<String, dynamic>.from(raw as Map);
        busy['space_id'] = _str(busy['space_id']);
        return busy;
      }),
    );
  store.publicReviews.clear();
  for (final r in data['reviews']) {
    store.publicReviews.putIfAbsent(_str(r['space_id']), () => []).add(review(r));
  }
  store.logs
    ..clear()
    ..addAll(
      (data['logs'] as List? ?? []).map(
        (l) => AuditEntry(_time(l['acted_at'])!, l['actor'], l['action']),
      ),
    );
  store.currentUser = current;
}
