import '../data/app_store.dart';
import '../models/domain.dart';

/// ควบคุมการเลือกเวลา สร้างคำขอ และเปลี่ยนสถานะการจองผ่าน backend API
class BookingController {
  BookingController(this._store);

  final AppStore _store;

  static const minDurationMinutes = 60;
  static const maxDurationMinutes = 12 * 60;
  static const maxBookingDays = 14;

  Future<Booking> createAsync(
    String spaceId,
    DateTime date,
    int start,
    int end, {
    int days = 1,
    int attendees = 1,
    String zone = 'โซนหลัก (พื้นที่มาตรฐาน)',
    String renterNote = '',
  }) async {
    final space = _store.space(spaceId);
    _validateBookingInput(space, days, attendees, start, end);
    _validateCreateSlot(space, date, start, end, days);
    final created = await _store.mutate('POST', '/bookings', {
      'spaceId': spaceId,
      'date': dateOnly(date).toIso8601String().substring(0, 10),
      'startMinutes': start,
      'endMinutes': end,
      'days': days,
      'attendees': attendees,
      'zone': zone.trim().isEmpty ? 'โซนหลัก (พื้นที่มาตรฐาน)' : zone.trim(),
      'renterNote': renterNote.trim(),
    });
    return _store.booking(created['id'] as String);
  }

  Future<void> ownerReviewAsync(String id, bool approve, String reason) async {
    if (!approve && reason.trim().isEmpty) {
      throw DomainError('กรุณาระบุเหตุผล');
    }
    await _store.mutate(
      'POST',
      '/bookings/$id/${approve ? 'approve' : 'reject'}',
      {'reason': reason.trim()},
    );
  }

  Future<void> cancelAsync(String id, String reason) async {
    if (reason.trim().isEmpty) {
      throw DomainError('กรุณาระบุเหตุผลยกเลิก');
    }
    await _store.mutate('POST', '/bookings/$id/cancel', {
      'reason': reason.trim(),
    });
  }

  Future<void> completeAsync(String id) async {
    await _store.mutate('POST', '/bookings/$id/complete');
  }

  Future<void> submitReviewAsync(
    String bookingId,
    int rating,
    String comment,
  ) async {
    if (rating < 1 || rating > 5 || comment.trim().isEmpty) {
      throw DomainError('กรุณาเลือกคะแนน 1–5 ดาว และระบุความคิดเห็น');
    }
    await _store.mutate('POST', '/bookings/$bookingId/review', {
      'rating': rating,
      'comment': comment.trim(),
    });
  }

  static String? durationError(int start, int end) {
    if (start < 0 || end > 1440 || end <= start) {
      return 'เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่ม';
    }
    final minutes = end - start;
    if (minutes < minDurationMinutes) {
      return 'จองขั้นต่ำ $minDurationMinutes นาที';
    }
    if (minutes > maxDurationMinutes) {
      return 'จองได้ไม่เกิน ${maxDurationMinutes ~/ 60} ชั่วโมงต่อครั้ง';
    }
    return null;
  }

  static void validateDuration(int start, int end) {
    final message = durationError(start, end);
    if (message != null) throw DomainError(message);
  }

  static int rent(int price, int start, int end, {int days = 1}) {
    if (price <= 0 || start < 0 || end > 1440 || end <= start || days < 1) {
      throw DomainError('ราคาและช่วงเวลาไม่ถูกต้อง');
    }
    return price * ((end - start) / 60).ceil() * days;
  }

  List<(int, int)> hourlySlots(Space space, DateTime date) {
    final day = space.availability.days[date.weekday - 1];
    if (!day.open) return const [];
    return [
      for (var minute = day.start; minute + 60 <= day.end; minute += 60)
        (minute, minute + 60),
    ];
  }

  bool isSlotAvailable(
    String spaceId,
    DateTime date,
    int start,
    int end, {
    int days = 1,
  }) {
    if (days < 1 || days > maxBookingDays) return false;
    final space = _store.space(spaceId);
    return atMinute(date, start).isAfter(_store.clock()) &&
        space.availability.acceptsRange(date, start, end, days: days) &&
        !_store.conflicts(spaceId, date, start, end, days: days);
  }

  List<String> busySlotLabels(String spaceId, DateTime date) {
    final targetDay = dateOnly(date);
    final booked = _store.busySlots.where((slot) {
      if (slot['space_id'] != spaceId) return false;
      final first = dateOnly(DateTime.parse('${slot['booking_date']}'));
      final daysCount = (slot['days_count'] as num).toInt();
      final last = first.add(Duration(days: daysCount - 1));
      return !targetDay.isBefore(first) && !targetDay.isAfter(last);
    }).toList()
      ..sort(
        (a, b) =>
            (a['start_minutes'] as num).compareTo(b['start_minutes'] as num),
      );
    return [
      for (final slot in booked) _formatBusySlotLabel(slot),
      ..._blockedLabelsOnDate(_store.space(spaceId), targetDay),
    ];
  }

  String _formatBusySlotLabel(Map<String, dynamic> slot) {
    final start = (slot['start_minutes'] as num).toInt();
    final end = (slot['end_minutes'] as num).toInt();
    final daysCount = (slot['days_count'] as num).toInt();
    final suffix = daysCount > 1 ? ' ($daysCount วัน)' : '';
    return 'คิวจอง ${timeLabel(start)}–${timeLabel(end)}$suffix';
  }

  List<String> _blockedLabelsOnDate(Space space, DateTime targetDay) {
    final dayEnd = targetDay.add(const Duration(days: 1));
    return [
      for (final block in space.availability.blocks)
        if (block.start.isBefore(dayEnd) && block.end.isAfter(targetDay))
          'ปิดพื้นที่ (${block.reason})',
    ];
  }

  (int, int) selectOrExtendSlot({
    required String spaceId,
    required DateTime date,
    required int currentStart,
    required int currentEnd,
    required int slotStart,
    required int slotEnd,
    int days = 1,
  }) {
    if (slotStart == currentEnd &&
        _canSelectRange(spaceId, date, currentStart, slotEnd, days: days)) {
      return (currentStart, slotEnd);
    }
    if (slotEnd == currentStart &&
        _canSelectRange(spaceId, date, slotStart, currentEnd, days: days)) {
      return (slotStart, currentEnd);
    }
    return (slotStart, slotEnd);
  }

  bool _canSelectRange(
    String spaceId,
    DateTime date,
    int start,
    int end, {
    int days = 1,
  }) =>
      durationError(start, end) == null &&
      isSlotAvailable(spaceId, date, start, end, days: days);

  void _validateBookingInput(
    Space space,
    int days,
    int attendees,
    int start,
    int end,
  ) {
    if (days < 1 || days > maxBookingDays) {
      throw DomainError('จองต่อเนื่องได้ 1–$maxBookingDays วัน');
    }
    if (attendees < 1 || attendees > space.capacity) {
      throw DomainError(
        'จำนวนผู้เข้าใช้งานต้องอยู่ระหว่าง 1–${space.capacity} ท่าน',
      );
    }
    validateDuration(start, end);
  }

  void _validateCreateSlot(
    Space space,
    DateTime date,
    int start,
    int end,
    int days,
  ) {
    if (space.status != SpaceStatus.approved ||
        !_store.user(space.ownerId).active) {
      throw DomainError('พื้นที่นี้ยังไม่เปิดรับจอง');
    }
    if (!atMinute(date, start).isAfter(_store.clock())) {
      throw DomainError('ต้องเลือกเวลาในอนาคต');
    }
    if (!space.availability.acceptsRange(date, start, end, days: days)) {
      throw DomainError('อยู่นอกเวลาเปิดหรือเป็นช่วงปิด');
    }
    if (_store.conflicts(space.id, date, start, end, days: days)) {
      throw DomainError('ช่วงเวลานี้มีการจองแล้ว');
    }
  }
}
