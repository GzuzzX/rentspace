import 'dart:typed_data';

enum UserRole { renter, owner, admin }

extension RoleLabel on UserRole {
  String get label => switch (this) {
    UserRole.renter => 'ผู้เช่า',
    UserRole.owner => 'เจ้าของพื้นที่',
    UserRole.admin => 'ผู้ดูแลระบบ',
  };
}

enum SpaceStatus { pending, approved, rejected }

enum SpaceSort { recommended, priceAsc, priceDesc, capacityDesc }

extension SpaceSortLabel on SpaceSort {
  String get label => switch (this) {
    SpaceSort.recommended => 'แนะนำ',
    SpaceSort.priceAsc => 'ราคาต่ำ→สูง',
    SpaceSort.priceDesc => 'ราคาสูง→ต่ำ',
    SpaceSort.capacityDesc => 'ความจุมาก→น้อย',
  };
}

extension SpaceLabel on SpaceStatus {
  String get label => switch (this) {
    SpaceStatus.pending => 'รอตรวจประกาศ',
    SpaceStatus.approved => 'อนุมัติแล้ว',
    SpaceStatus.rejected => 'ไม่ผ่านการตรวจ',
  };
}

enum BookingStatus {
  ownerReview,
  paymentDue,
  slipReview,
  confirmed,
  slipRejected,
  ownerRejected,
  completed,
  canceled,
}

extension BookingLabel on BookingStatus {
  String get label => switch (this) {
    BookingStatus.ownerReview => 'รอเจ้าของอนุมัติ',
    BookingStatus.paymentDue => 'รอชำระเงิน',
    BookingStatus.slipReview => 'รอตรวจสลิป',
    BookingStatus.confirmed => 'ยืนยันแล้ว',
    BookingStatus.slipRejected => 'สลิปไม่ผ่าน',
    BookingStatus.ownerRejected => 'เจ้าของปฏิเสธ',
    BookingStatus.completed => 'เสร็จสิ้น',
    BookingStatus.canceled => 'ยกเลิกแล้ว',
  };
  bool get holdsTime =>
      this != BookingStatus.ownerRejected && this != BookingStatus.canceled;
  int get progressStep => switch (this) {
    BookingStatus.ownerReview ||
    BookingStatus.ownerRejected ||
    BookingStatus.canceled => 0,
    BookingStatus.paymentDue || BookingStatus.slipRejected => 1,
    BookingStatus.slipReview => 2,
    BookingStatus.confirmed || BookingStatus.completed => 3,
  };
}

/// เจ้าของต้องตอบรับคำขอ และผู้เช่าต้องชำระเงินภายใน 24 ชั่วโมง
const ownerResponseWindow = Duration(hours: 24);
const paymentWindow = Duration(hours: 24);
const slipResubmitWindow = Duration(hours: 24);

/// รายการที่ยืนยันแล้วจะจบอัตโนมัติเมื่อเลยเวลาสิ้นสุด 24 ชั่วโมง
const autoCompleteWindow = Duration(hours: 24);

/// ค่าบริการที่หักจากเจ้าของ — คำนวณครั้งเดียวตอนสร้าง booking แล้วเก็บเป็น snapshot
const platformFeePercent = 5;

/// ตารางการเปลี่ยนสถานะกลาง: ที่เดียวที่ตอบได้ว่าสถานะไหนไปต่อได้
/// กันไม่ให้แต่ละคอนโทรลเลอร์ตั้งกฎของตัวเองแล้วขัดกันภายหลัง
extension BookingStatusFlow on BookingStatus {
  Set<BookingStatus> get nextStates => switch (this) {
    BookingStatus.ownerReview => {
      BookingStatus.paymentDue,
      BookingStatus.ownerRejected,
      BookingStatus.canceled,
    },
    BookingStatus.paymentDue => {
      BookingStatus.slipReview,
      BookingStatus.canceled,
    },
    BookingStatus.slipReview => {
      BookingStatus.confirmed,
      BookingStatus.slipRejected,
      BookingStatus.canceled,
    },
    BookingStatus.slipRejected => {
      BookingStatus.slipReview,
      BookingStatus.canceled,
    },
    BookingStatus.confirmed => {
      BookingStatus.completed,
      BookingStatus.canceled,
    },
    BookingStatus.completed ||
    BookingStatus.ownerRejected ||
    BookingStatus.canceled => const <BookingStatus>{},
  };

  bool canTransitionTo(BookingStatus next) => nextStates.contains(next);
}

/// ที่มาของ [Booking.reason] — ฟิลด์ reason เคยใช้ร่วมกับ 4 ความหมาย
/// แยกไว้เพื่อให้ตรวจสอบได้โดยไม่ต้องเดาจาก status
enum ReasonKind {
  none,
  ownerRejected,
  slipRejected,
  canceledByUser,
  expiredBySystem;

  String get label => switch (this) {
    ReasonKind.none => '',
    ReasonKind.ownerRejected => 'เจ้าของปฏิเสธ',
    ReasonKind.slipRejected => 'สลิปไม่ผ่าน',
    ReasonKind.canceledByUser => 'ยกเลิกโดยผู้ใช้',
    ReasonKind.expiredBySystem => 'หมดเวลาอัตโนมัติ',
  };
}

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    this.phone = '',
    this.bankInfo = '',
    this.active = true,
  });
  final String id;
  final UserRole role;
  String name, email, phone, bankInfo, password;
  bool active;
  final Set<String> favorites = {};
  String get phoneLabel => phone.trim().isEmpty ? 'ไม่ระบุ' : phone.trim();
}

class DayHours {
  DayHours({this.open = true, this.start = 540, this.end = 1080});
  bool open;
  int start, end;
  DayHours copy() => DayHours(open: open, start: start, end: end);
}

class BlockedPeriod {
  BlockedPeriod({
    required this.id,
    required this.start,
    required this.end,
    required this.reason,
  });
  final String id, reason;
  final DateTime start, end;
}

class Availability {
  Availability({List<DayHours>? days, List<BlockedPeriod>? blocks})
    : days = days ?? List.generate(7, (_) => DayHours()),
      blocks = blocks ?? [];
  final List<DayHours> days;
  final List<BlockedPeriod> blocks;
  Availability copy() => Availability(
    days: days.map((d) => d.copy()).toList(),
    blocks: [...blocks],
  );
  bool accepts(DateTime date, int start, int end) {
    if (start < 0 || end > 1440 || end <= start) return false;
    final day = days[date.weekday - 1];
    final from = atMinute(date, start), to = atMinute(date, end);
    return day.open &&
        start >= day.start &&
        end <= day.end &&
        !blocks.any((b) => from.isBefore(b.end) && to.isAfter(b.start));
  }

  bool acceptsRange(DateTime date, int start, int end, {int days = 1}) {
    if (days < 1 || days > 30) return false;
    for (var i = 0; i < days; i++) {
      if (!accepts(dateOnly(date).add(Duration(days: i)), start, end)) {
        return false;
      }
    }
    return true;
  }
}

class Space {
  Space({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.category,
    required this.location,
    required this.price,
    required this.capacity,
    required this.description,
    this.image = '',
    Uint8List? imageBytes,
    List<String>? amenities,
    this.status = SpaceStatus.pending,
    Availability? availability,
  }) : imageBytes = imageBytes != null ? Uint8List.fromList(imageBytes) : null,
       amenities = amenities ?? [],
       availability = availability ?? Availability();
  final String id, ownerId;
  String name, category, location, description, image;
  Uint8List? imageBytes;
  int price, capacity;
  List<String> amenities;
  SpaceStatus status;
  String reviewReason = '';
  Availability availability;

  bool get hasImage =>
      (imageBytes != null && imageBytes!.isNotEmpty) || image.trim().isNotEmpty;
}

class PaymentSlip {
  PaymentSlip({
    required this.name,
    required Uint8List bytes,
    required this.submittedAt,
    this.note = '',
  }) : bytes = Uint8List.fromList(bytes);
  final String name, note;
  final Uint8List bytes;
  final DateTime submittedAt;
  String rejectionReason = '';
}

class SpaceReview {
  SpaceReview({
    required this.rating,
    required this.comment,
    required this.createdAt,
  });
  final int rating;
  final String comment;
  final DateTime createdAt;
}

class Booking {
  Booking({
    required this.id,
    required this.spaceId,
    required this.ownerId,
    required this.renterId,
    required this.spaceName,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.rentAmount,
    int? platformFee,
    this.days = 1,
    this.attendees = 1,
    this.zone = 'โซนหลัก (พื้นที่มาตรฐาน)',
    this.renterNote = '',
    this.status = BookingStatus.ownerReview,
    this.review,
  }) : platformFee =
           platformFee ?? (rentAmount * platformFeePercent / 100).round();
  final String id, spaceId, ownerId, renterId, spaceName, zone, renterNote;
  final DateTime date;
  final int startMinutes, endMinutes, rentAmount, days, attendees;

  /// เก็บไว้ ณ เวลาที่จอง — เปลี่ยนอัตราค่าบริการภายหลังไม่กระทบรายการเก่า
  final int platformFee;

  /// ที่มาของ [reason] (ดู [ReasonKind])
  ReasonKind reasonKind = ReasonKind.none;
  BookingStatus status;
  SpaceReview? review;
  final List<PaymentSlip> slips = [];
  PaymentSlip? get latestSlip => slips.isEmpty ? null : slips.last;
  String reason = '';
  DateTime? paidOutAt;
  DateTime? createdAt, approvedAt, slipRejectedAt, confirmedAt, completedAt;
  DateTime? get ownerResponseDeadline => createdAt?.add(ownerResponseWindow);
  DateTime? get paymentDeadline => approvedAt?.add(paymentWindow);
  DateTime? get slipResubmitDeadline => slipRejectedAt?.add(slipResubmitWindow);
  DateTime? get effectiveSlipResubmitDeadline {
    final deadline = slipResubmitDeadline;
    if (deadline == null) return null;
    return startsAt.isBefore(deadline) ? startsAt : deadline;
  }

  DateTime get endDate => dateOnly(date).add(Duration(days: days - 1));
  DateTime get autoCompleteAt => endsAt.add(autoCompleteWindow);

  /// เปลี่ยนสถานะโดยตรวจกับตารางกลาง [BookingStatusFlow]
  void moveTo(BookingStatus next) {
    if (!status.canTransitionTo(next)) {
      throw DomainError(
        'เปลี่ยนสถานะจาก ${status.label} เป็น ${next.label} ไม่ได้',
      );
    }
    status = next;
  }

  int get ownerNet => rentAmount - platformFee;

  /// ข้อความบอกเวลาที่เหลือของขั้นตอนที่กำลังดำเนินอยู่ (null = ไม่มีกำหนด)
  String? deadlineHint(DateTime now) {
    final (deadline, verb) = switch (status) {
      BookingStatus.ownerReview => (ownerResponseDeadline, 'รอเจ้าของตอบรับ'),
      BookingStatus.paymentDue => (paymentDeadline, 'รอชำระเงิน'),
      BookingStatus.slipRejected => (
        effectiveSlipResubmitDeadline,
        'รอส่งสลิปใหม่',
      ),
      _ => (null, ''),
    };
    if (deadline == null) return null;
    final left = deadline.difference(now);
    if (left.isNegative) return '$verb · เกินกำหนดแล้ว';
    final hours = left.inHours;
    final minutes = left.inMinutes % 60;
    final span = hours > 0 ? '$hours ชม. $minutes น.' : '$minutes น.';
    return '$verb · เหลือ $span';
  }

  DateTime get startsAt => atMinute(date, startMinutes);
  DateTime get endsAt => atMinute(endDate, endMinutes);
  bool coversDate(DateTime target) {
    final d = dateOnly(target), from = dateOnly(date), to = endDate;
    return !d.isBefore(from) && !d.isAfter(to);
  }
}

class Issue {
  Issue({
    required this.id,
    required this.reporterId,
    required this.subject,
    required this.detail,
  });
  final String id, reporterId, subject, detail;
  bool closed = false;
  String resolution = '';
}

class AuditEntry {
  AuditEntry(this.at, this.actor, this.action);
  final DateTime at;
  final String actor, action;
}

class DomainError implements Exception {
  DomainError(this.message);
  final String message;
  @override
  String toString() => message;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime atMinute(DateTime d, int m) => dateOnly(d).add(Duration(minutes: m));

/// ปี พ.ศ. = ค.ศ. + 543
const buddhistYearOffset = 543;

/// วันที่แบบไทยย่อ: 12/11/2569 (ปี พ.ศ.)
String dateLabel(DateTime d) =>
    '${d.day}/${d.month}/${d.year + buddhistYearOffset}';

/// เงินบาทพร้อมตัวคั่นหลักพัน: 1045 → '฿1,045'
String bahtLabel(num amount) {
  final rounded = amount.round();
  final digits = rounded.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '${rounded < 0 ? '-' : ''}฿$grouped';
}

String timeLabel(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
String dateTimeLabel(DateTime d) =>
    '${dateLabel(d)} ${timeLabel(d.hour * 60 + d.minute)}';
String bookingWhen(Booking b) => b.days > 1
    ? '${dateLabel(b.date)}–${dateLabel(b.endDate)} (${b.days} วัน) · ${timeLabel(b.startMinutes)}–${timeLabel(b.endMinutes)}'
    : '${dateLabel(b.date)} · ${timeLabel(b.startMinutes)}–${timeLabel(b.endMinutes)}';
