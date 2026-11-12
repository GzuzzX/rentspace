import '../data/app_store.dart';
import '../models/domain.dart';

/// ชั้นกลางระหว่าง controller กับที่เก็บข้อมูล (AppStore)
///
/// controller ไม่เรียก AppStore ตรง ๆ อีกต่อไป แต่เรียกผ่าน service
/// ทำให้ในเทสต์สลับ service เป็น mock ได้ (ดู test/service_mock_test.dart)
abstract class StoreService {
  StoreService(this.store);

  final AppStore store;

  DateTime clock() => store.clock();

  AppUser? get currentUser => store.currentUser;

  List<AppUser> get users => store.users;

  AppUser user(String id) => store.user(id);

  AppUser requireUser([UserRole? role]) => store.requireUser(role);

  String nextId(String prefix) => store.nextId(prefix);

  void changed(String action, {String? actor}) =>
      store.changed(action, actor: actor);

  bool conflicts(
    String spaceId,
    DateTime date,
    int start,
    int end, {
    int days = 1,
    String? excluding,
  }) => store.conflicts(
    spaceId,
    date,
    start,
    end,
    days: days,
    excluding: excluding,
  );

  /// ยกเลิกอัตโนมัติเมื่อเลยกำหนด และจบรายการที่ยืนยันแล้วเมื่อเลยเวลาสิ้นสุด
  void sweepExpired() {
    final now = clock();
    for (final booking in store.bookings) {
      final reason = _expirationReason(booking, now);
      if (reason != null) {
        _expire(booking, reason);
        continue;
      }
      if (booking.status == BookingStatus.confirmed &&
          now.isAfter(booking.autoCompleteAt)) {
        booking.moveTo(BookingStatus.completed);
        booking.completedAt = now;
        changed(
          '${booking.id}: จบรายการอัตโนมัติหลังสิ้นสุดเวลา',
          actor: 'ระบบ',
        );
      }
    }
  }

  String? _expirationReason(Booking booking, DateTime now) =>
      switch (booking.status) {
        BookingStatus.ownerReview
            when _isPastDeadline(
              booking.startsAt,
              booking.ownerResponseDeadline,
              now,
            ) =>
          'หมดเวลาตอบรับจากเจ้าของ',
        BookingStatus.paymentDue
            when _isPastDeadline(
              booking.startsAt,
              booking.paymentDeadline,
              now,
            ) =>
          'ไม่ชำระเงินภายในกำหนด',
        BookingStatus.slipRejected
            when _isPastDeadline(
              booking.startsAt,
              booking.slipResubmitDeadline,
              now,
            ) =>
          'ไม่ส่งสลิปใหม่ภายในกำหนด',
        _ => null,
      };

  bool _isPastDeadline(DateTime startsAt, DateTime? deadline, DateTime now) =>
      !startsAt.isAfter(now) || (deadline != null && now.isAfter(deadline));

  void _expire(Booking booking, String reason) {
    booking.moveTo(BookingStatus.canceled);
    booking.reason = reason;
    booking.reasonKind = ReasonKind.expiredBySystem;
    changed('${booking.id}: ยกเลิกอัตโนมัติ ($reason)', actor: 'ระบบ');
  }
}
