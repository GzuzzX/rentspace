import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/data/app_store.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/services/api_client.dart';
import 'package:rentspace/services/remote_store.dart';
import 'package:rentspace/services/token_service.dart';
import 'package:rentspace/ui/theme.dart';

import '../fixtures/mock_controllers.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

Map<String, dynamic> _sampleSnapshotMap() => {
  'userId': 1002,
  'favorites': [2001],
  'users': [
    {
      'id': 1001,
      'name': 'เจ้าของพื้นที่',
      'email': 'owner@test.local',
      'role': 'owner',
      'phone': '089-111-2222',
      'bank_info': 'KBANK 111-2-33333-4',
      'active': 1,
    },
    {
      'id': 1002,
      'name': 'ผู้เช่าตัวอย่าง',
      'email': 'renter@test.local',
      'role': 'renter',
      'phone': '',
      'bank_info': '',
      'active': true,
    },
  ],
  'spaces': [
    {
      'id': 2001,
      'owner_id': 1001,
      'name': 'ห้องอารีย์',
      'category': 'meeting_room',
      'location': 'กรุงเทพฯ',
      'price': 400,
      'capacity': 12,
      'description': 'ห้องประชุมโปร่งสบาย',
      'image': '/api/spaces/2001/image',
      'amenities': jsonEncode(['Wi-Fi', 'โปรเจกเตอร์']),
      'status': 'approved',
      'hours': jsonEncode(
        List.generate(
          7,
          (_) => {'open': true, 'start': 540, 'end': 1080},
        ),
      ),
      'avg_rating': 4.5,
      'review_count': 1,
    },
    {
      'id': 2002,
      'owner_id': 1001,
      'name': 'สตูดิโอลายเส้น',
      'category': 'studio',
      'location': 'สยาม',
      'price': 600,
      'capacity': 6,
      'description': 'ภาพฝัง base64',
      'image': 'data:image/png;base64,${base64Encode(validMockPngBytes)}',
      'amenities': ['ไฟสตูดิโอ'],
      'status': 'rejected',
      'review_reason': 'รูปไม่ชัด',
      'hours': List.generate(
        7,
        (_) => {'open': true, 'start': 600, 'end': 1020},
      ),
      'avg_rating': null,
      'review_count': 0,
    },
  ],
  'blocks': [
    {
      'id': 'blk-1',
      'space_id': 2001,
      'start_at': '2026-11-20T12:00:00',
      'end_at': '2026-11-20T14:00:00',
      'reason': 'ซ่อมบำรุง',
    },
  ],
  'bookings': [
    {
      'id': 3001,
      'space_id': 2001,
      'owner_id': 1001,
      'renter_id': 1002,
      'space_name': 'ห้องอารีย์',
      'booking_date': '2026-11-18',
      'start_minutes': 540,
      'end_minutes': 660,
      'rent_amount': 800,
      'platform_fee': 40,
      'days_count': 1,
      'attendees': 4,
      'zone': 'โซนหลัก (พื้นที่มาตรฐาน)',
      'renter_note': 'ขอปลั๊กเพิ่ม',
      'status': 'completed',
      'reason': '',
      'reason_kind': '',
      'created_at': '2026-11-15T10:00:00',
      'approved_at': '2026-11-15T11:00:00',
      'confirmed_at': '2026-11-15T12:00:00',
      'completed_at': '2026-11-18T11:00:00',
      'paid_out_at': '2026-11-18T15:00:00',
      'payout_slip_name': 'payout.png',
      'payout_slip_data': base64Encode(validMockPngBytes),
      'payout_slip_url': '/api/bookings/3001/payout-slip',
      'payout_note': 'โอนเรียบร้อย',
    },
    {
      'id': 3002,
      'space_id': 2001,
      'owner_id': 1001,
      'renter_id': 1002,
      'space_name': 'ห้องอารีย์',
      'booking_date': '2026-11-19',
      'start_minutes': 720,
      'end_minutes': 780,
      'rent_amount': 400,
      'platform_fee': null,
      'days_count': 1,
      'attendees': 2,
      'zone': 'โซนเงียบพิเศษ',
      'renter_note': '',
      'status': 'slip_rejected',
      'reason': 'ยอดไม่ตรง',
      'reason_kind': null,
      'created_at': '2026-11-16T09:00:00',
      'approved_at': '2026-11-16T10:00:00',
      'slip_rejected_at': '2026-11-16T11:00:00',
    },
  ],
  'slips': [
    {
      'booking_id': 3002,
      'file_name': 'slip.png',
      'image_data': base64Encode(validMockPngBytes),
      'image_url': '/api/bookings/3002/slip',
      'submitted_at': '2026-11-16T10:30:00',
      'note': 'โอนแล้ว',
      'rejection_reason': 'ยอดไม่ตรง',
    },
  ],
  'reviews': [
    {
      'booking_id': 3001,
      'space_id': 2001,
      'rating': 5,
      'comment': 'สะอาดมาก',
      'created_at': '2026-11-18T12:00:00',
    },
  ],
  'issues': [
    {
      'id': 'iss-1',
      'reporter_id': 1002,
      'subject': 'เสียงรบกวน',
      'detail': 'ชั้นบนซ่อมแอร์',
      'closed': 0,
      'resolution': '',
    },
  ],
  'busy': [
    {
      'space_id': 2001,
      'booking_date': '2026-11-21',
      'start_minutes': 600,
      'end_minutes': 720,
      'days_count': 2,
    },
  ],
  'logs': [
    {
      'acted_at': '2026-11-18T15:00:00',
      'actor': 'Admin',
      'action': 'โอนเงินเจ้าของพื้นที่',
    },
  ],
};

void main() {
  group('Domain models, state transitions, and Thai formatters', () {
    test('enum labels, holdsTime, and progressStep cover every value', () {
      expect(UserRole.renter.label, 'ผู้เช่า');
      expect(UserRole.owner.label, 'เจ้าของพื้นที่');
      expect(UserRole.admin.label, 'ผู้ดูแลระบบ');

      expect(SpaceStatus.pending.label, 'รอตรวจประกาศ');
      expect(SpaceStatus.approved.label, 'อนุมัติแล้ว');
      expect(SpaceStatus.rejected.label, 'ไม่ผ่านการตรวจ');

      expect(SpaceSort.recommended.label, 'แนะนำ');
      expect(SpaceSort.priceAsc.label, 'ราคาต่ำ→สูง');
      expect(SpaceSort.priceDesc.label, 'ราคาสูง→ต่ำ');
      expect(SpaceSort.capacityDesc.label, 'ความจุมาก→น้อย');

      expect(BookingStatus.ownerReview.label, 'รอเจ้าของอนุมัติ');
      expect(BookingStatus.paymentDue.label, 'รอชำระเงิน');
      expect(BookingStatus.slipReview.label, 'รอตรวจสลิป');
      expect(BookingStatus.confirmed.label, 'ยืนยันแล้ว');
      expect(BookingStatus.slipRejected.label, 'สลิปไม่ผ่าน');
      expect(BookingStatus.ownerRejected.label, 'เจ้าของปฏิเสธ');
      expect(BookingStatus.completed.label, 'เสร็จสิ้น');
      expect(BookingStatus.canceled.label, 'ยกเลิกแล้ว');

      expect(BookingStatus.ownerReview.holdsTime, isTrue);
      expect(BookingStatus.paymentDue.holdsTime, isTrue);
      expect(BookingStatus.slipReview.holdsTime, isTrue);
      expect(BookingStatus.slipRejected.holdsTime, isTrue);
      expect(BookingStatus.confirmed.holdsTime, isTrue);
      expect(BookingStatus.completed.holdsTime, isTrue);
      expect(BookingStatus.ownerRejected.holdsTime, isFalse);
      expect(BookingStatus.canceled.holdsTime, isFalse);

      expect(BookingStatus.ownerReview.progressStep, 0);
      expect(BookingStatus.ownerRejected.progressStep, 0);
      expect(BookingStatus.canceled.progressStep, 0);
      expect(BookingStatus.paymentDue.progressStep, 1);
      expect(BookingStatus.slipRejected.progressStep, 1);
      expect(BookingStatus.slipReview.progressStep, 2);
      expect(BookingStatus.confirmed.progressStep, 3);
      expect(BookingStatus.completed.progressStep, 3);

      expect(ReasonKind.none.label, isEmpty);
      expect(ReasonKind.ownerRejected.label, 'เจ้าของปฏิเสธ');
      expect(ReasonKind.slipRejected.label, 'สลิปไม่ผ่าน');
      expect(ReasonKind.canceledByUser.label, 'ยกเลิกโดยผู้ใช้');
      expect(ReasonKind.expiredBySystem.label, 'หมดเวลาอัตโนมัติ');
    });

    test('BookingStatusFlow transitions enforce valid and invalid moves', () {
      final booking = Booking(
        id: 'B-1',
        spaceId: 'S-1',
        ownerId: 'O-1',
        renterId: 'R-1',
        spaceName: 'ห้องทดสอบ',
        date: DateTime(2026, 11, 20),
        startMinutes: 540,
        endMinutes: 660,
        rentAmount: 700,
      );

      expect(booking.status, BookingStatus.ownerReview);
      expect(booking.status.canTransitionTo(BookingStatus.paymentDue), isTrue);
      expect(booking.status.canTransitionTo(BookingStatus.completed), isFalse);

      expect(
        () => booking.moveTo(BookingStatus.confirmed),
        throwsA(isA<DomainError>()),
      );

      booking.moveTo(BookingStatus.paymentDue);
      booking.moveTo(BookingStatus.slipReview);
      booking.moveTo(BookingStatus.slipRejected);
      booking.moveTo(BookingStatus.slipReview);
      booking.moveTo(BookingStatus.confirmed);
      booking.moveTo(BookingStatus.completed);

      expect(booking.status, BookingStatus.completed);
      expect(booking.status.nextStates, isEmpty);
      expect(BookingStatus.canceled.nextStates, isEmpty);
      expect(BookingStatus.ownerRejected.nextStates, isEmpty);
    });

    test('Booking fee, dates, deadlines, and deadlineHint calculations', () {
      final booking = Booking(
        id: 'B-FEE',
        spaceId: 'S-1',
        ownerId: 'O-1',
        renterId: 'R-1',
        spaceName: 'ห้องทดสอบ',
        date: DateTime(2026, 11, 20, 15, 30),
        startMinutes: 540,
        endMinutes: 660,
        rentAmount: 750,
        days: 3,
      )
        ..createdAt = DateTime(2026, 11, 18, 10, 0)
        ..approvedAt = DateTime(2026, 11, 19, 12, 0);

      expect(booking.platformFee, 38);
      expect(booking.ownerNet, 712);
      expect(booking.endDate, DateTime(2026, 11, 22));
      expect(booking.startsAt, DateTime(2026, 11, 20, 9, 0));
      expect(booking.endsAt, DateTime(2026, 11, 22, 11, 0));
      expect(booking.autoCompleteAt, DateTime(2026, 11, 23, 11, 0));
      expect(booking.coversDate(DateTime(2026, 11, 19)), isFalse);
      expect(booking.coversDate(DateTime(2026, 11, 20)), isTrue);
      expect(booking.coversDate(DateTime(2026, 11, 22)), isTrue);
      expect(booking.coversDate(DateTime(2026, 11, 23)), isFalse);

      expect(booking.ownerResponseDeadline, DateTime(2026, 11, 19, 10, 0));
      // approvedAt + 24h = Nov 20 12:00, which is after startsAt (Nov 20 09:00)
      expect(booking.paymentDeadline, DateTime(2026, 11, 20, 9, 0));

      expect(
        booking.deadlineHint(DateTime(2026, 11, 19, 8, 30)),
        'รอเจ้าของตอบรับ · เหลือ 1 ชม. 30 น.',
      );
      expect(
        booking.deadlineHint(DateTime(2026, 11, 19, 9, 45)),
        'รอเจ้าของตอบรับ · เหลือ 15 น.',
      );
      expect(
        booking.deadlineHint(DateTime(2026, 11, 19, 10, 5)),
        'รอเจ้าของตอบรับ · เกินกำหนดแล้ว',
      );

      booking.status = BookingStatus.paymentDue;
      expect(
        booking.deadlineHint(DateTime(2026, 11, 20, 8, 0)),
        'รอชำระเงิน · เหลือ 1 ชม. 0 น.',
      );

      booking.status = BookingStatus.slipRejected;
      booking.slipRejectedAt = DateTime(2026, 11, 19, 10, 0);
      expect(booking.slipResubmitDeadline, DateTime(2026, 11, 20, 10, 0));
      expect(
        booking.effectiveSlipResubmitDeadline,
        DateTime(2026, 11, 20, 9, 0),
      );
      expect(
        booking.deadlineHint(DateTime(2026, 11, 20, 8, 30)),
        'รอส่งสลิปใหม่ · เหลือ 30 น.',
      );

      booking.status = BookingStatus.confirmed;
      expect(booking.deadlineHint(DateTime(2026, 11, 19, 8, 0)), isNull);
    });

    test('Availability.accepts, acceptsRange, and copy respect days and blocks', () {
      final availability = Availability(
        days: [
          for (var weekday = 1; weekday <= 7; weekday++)
            DayHours(open: weekday != 7, start: 540, end: 1080),
        ],
        blocks: [
          BlockedPeriod(
            id: 'BLK-1',
            start: DateTime(2026, 11, 18, 12, 0),
            end: DateTime(2026, 11, 18, 14, 0),
            reason: 'พักเที่ยง',
          ),
        ],
      );

      // Monday (open 09:00-18:00)
      final monday = DateTime(2026, 11, 16);
      expect(availability.accepts(monday, 540, 1080), isTrue);
      expect(availability.accepts(monday, -1, 600), isFalse);
      expect(availability.accepts(monday, 600, 1441), isFalse);
      expect(availability.accepts(monday, 600, 600), isFalse);
      expect(availability.accepts(monday, 480, 600), isFalse);
      expect(availability.accepts(monday, 1020, 1140), isFalse);

      // Wednesday (Nov 18): blocked 12:00-14:00 (720-840)
      final wednesday = DateTime(2026, 11, 18);
      expect(availability.accepts(wednesday, 600, 720), isTrue);
      expect(availability.accepts(wednesday, 660, 780), isFalse);
      expect(availability.accepts(wednesday, 840, 960), isTrue);

      // Sunday (Nov 22): closed
      expect(availability.accepts(DateTime(2026, 11, 22), 600, 720), isFalse);

      // Multi-day range bounds & Sunday crossing
      expect(availability.acceptsRange(monday, 600, 720, days: 0), isFalse);
      expect(availability.acceptsRange(monday, 600, 720, days: 31), isFalse);
      expect(availability.acceptsRange(monday, 600, 720, days: 2), isTrue);
      expect(availability.acceptsRange(monday, 660, 780, days: 4), isFalse);
      expect(
        availability.acceptsRange(DateTime(2026, 11, 21), 600, 720, days: 2),
        isFalse,
      );

      // Deep copy mutating copy leaves original intact
      final cloned = availability.copy();
      cloned.days[0].open = false;
      expect(availability.days[0].open, isTrue);
    });

    test('AppUser.phoneLabel, Space.hasImage, and Thai formatting helpers', () {
      final blankPhoneUser = AppUser(
        id: 'U-1',
        name: 'ก',
        email: 'a@b.c',
        password: '',
        role: UserRole.renter,
        phone: '   ',
      );
      final trimmedPhoneUser = AppUser(
        id: 'U-2',
        name: 'ข',
        email: 'b@b.c',
        password: '',
        role: UserRole.renter,
        phone: ' 081-222-3333 ',
      );
      expect(blankPhoneUser.phoneLabel, 'ไม่ระบุ');
      expect(trimmedPhoneUser.phoneLabel, '081-222-3333');

      final emptySpace = Space(
        id: 'S-0',
        ownerId: 'U-1',
        name: 'ห้องเปล่า',
        category: 'meeting_room',
        location: 'กทม',
        price: 100,
        capacity: 2,
        description: '-',
      );
      expect(emptySpace.hasImage, isFalse);
      emptySpace.imageBytes = Uint8List(0);
      expect(emptySpace.hasImage, isFalse);
      emptySpace.imageBytes = validMockPngBytes;
      expect(emptySpace.hasImage, isTrue);

      final urlSpace = Space(
        id: 'S-1',
        ownerId: 'U-1',
        name: 'ห้องมีรูป',
        category: 'meeting_room',
        location: 'กทม',
        price: 100,
        capacity: 2,
        description: '-',
        image: 'https://example.com/room.png',
      );
      expect(urlSpace.hasImage, isTrue);

      expect(dateOnly(DateTime(2026, 11, 16, 14, 45)), DateTime(2026, 11, 16));
      expect(atMinute(DateTime(2026, 11, 16), 90), DateTime(2026, 11, 16, 1, 30));
      expect(dateLabel(DateTime(2026, 11, 16)), '16/11/2569');
      expect(timeLabel(90), '01:30');
      expect(dateTimeLabel(DateTime(2026, 11, 16, 9, 5)), '16/11/2569 09:05');
      expect(bahtLabel(0), '฿0');
      expect(bahtLabel(1234567), '฿1,234,567');
      expect(bahtLabel(-1500), '-฿1,500');

      final oneDayBooking = Booking(
        id: 'B-1D',
        spaceId: 'S-1',
        ownerId: 'O-1',
        renterId: 'R-1',
        spaceName: 'ห้อง',
        date: DateTime(2026, 11, 16),
        startMinutes: 540,
        endMinutes: 660,
        rentAmount: 200,
      );
      final multiDayBooking = Booking(
        id: 'B-3D',
        spaceId: 'S-1',
        ownerId: 'O-1',
        renterId: 'R-1',
        spaceName: 'ห้อง',
        date: DateTime(2026, 11, 16),
        startMinutes: 540,
        endMinutes: 660,
        rentAmount: 600,
        days: 3,
      );
      expect(bookingWhen(oneDayBooking), '16/11/2569 · 09:00–11:00');
      expect(
        bookingWhen(multiDayBooking),
        '16/11/2569–18/11/2569 (3 วัน) · 09:00–11:00',
      );
    });
  });

  group('AppStore lookups, role scoping, badges, conflicts, and sync', () {
    test('requireUser, lookups, and visibleBookings enforce role scoping', () {
      final store = createMockStore(signedIn: false);
      expect(() => store.requireUser(), throwsA(isA<DomainError>()));

      // Disabled account throws DomainError
      store.currentUser = store.user('1005');
      expect(() => store.requireUser(), throwsA(isA<DomainError>()));

      // Renter only sees own bookings
      store.currentUser = store.user('1002');
      expect(
        () => store.requireUser(UserRole.admin),
        throwsA(isA<DomainError>()),
      );
      expect(store.visibleBookings().every((b) => b.renterId == '1002'), isTrue);

      // Owner sees bookings for their spaces
      store.currentUser = store.user('1001');
      expect(store.visibleBookings().every((b) => b.ownerId == '1001'), isTrue);

      // Admin sees all bookings including canceled renter 1004
      store.currentUser = store.user('1003');
      expect(store.visibleBookings().length, store.bookings.length);

      expect(() => store.space('missing'), throwsA(isA<DomainError>()));
      expect(() => store.booking('missing'), throwsA(isA<DomainError>()));
      expect(() => store.user('missing'), throwsA(isA<DomainError>()));
      expect(store.maybeBooking('missing'), isNull);
      expect(store.maybeUser('missing'), isNull);
    });

    test('navBadges computes unread action counts per role', () {
      final store = createMockStore(signedIn: false);
      expect(store.navBadges(), isEmpty);

      // Renter 1002 has booking 3004 (paymentDue) and add one slipRejected
      store.currentUser = store.user('1002');
      store.bookings.add(
        Booking(
          id: '3999',
          spaceId: '2001',
          ownerId: '1001',
          renterId: '1002',
          spaceName: 'ห้องประชุมสว่างใจ',
          date: mockClockNow.add(const Duration(days: 10)),
          startMinutes: 540,
          endMinutes: 660,
          rentAmount: 700,
          status: BookingStatus.slipRejected,
        ),
      );
      expect(store.navBadges(), [0, 2, 0, 0]);

      // Owner 1001: 1 rejected space (2098), 1 ownerReview (3003), 1 completed unpaid (3006)
      store.currentUser = store.user('1001');
      expect(store.navBadges(), [0, 1, 1, 1, 0]);

      // Admin 1003: 1 pending space (2005) + 1 open issue = 2; 1 slipReview (3005) + 1 completed unpaid (3006) = 2
      store.currentUser = store.user('1003');
      expect(store.navBadges(), [0, 2, 2, 0, 0]);
    });

    test('conflicts checks both busySlots and held bookings with excluding', () {
      final store = createMockStore();
      store.busySlots.add({
        'space_id': '2001',
        'booking_date': '2026-11-28',
        'start_minutes': 600,
        'end_minutes': 720,
        'days_count': 2,
      });

      // busySlots triggers conflict on Nov 29 (second day)
      expect(
        store.conflicts('2001', DateTime(2026, 11, 29), 660, 780),
        isTrue,
      );
      // excluding skips busySlots check and checks local bookings only
      expect(
        store.conflicts(
          '2001',
          DateTime(2026, 11, 29),
          660,
          780,
          excluding: 'none',
        ),
        isFalse,
      );

      // In-memory booking 3003 holds 2001 on mockClockNow + 5 days 09:00-11:00
      final targetDate = mockClockNow.add(const Duration(days: 5));
      expect(store.conflicts('2001', targetDate, 540, 600), isTrue);
      expect(
        store.conflicts('2001', targetDate, 540, 600, excluding: '3003'),
        isFalse,
      );
      // Canceled booking 3007 does not hold time
      final canceledDate = mockClockNow.add(const Duration(days: 8));
      expect(store.conflicts('2001', canceledDate, 540, 660), isFalse);
    });

    test('refresh, poll, mutate, toggleTheme, and clearSession behavior', () async {
      final mockApi = _MockApiClient();
      var currentToken = '';
      when(() => mockApi.baseUrl).thenReturn('http://localhost:3001/api');
      when(() => mockApi.token).thenAnswer((_) => currentToken.isEmpty ? null : currentToken);
      when(() => mockApi.token = any()).thenAnswer((invocation) {
        currentToken = invocation.positionalArguments.first as String? ?? '';
        return currentToken.isEmpty ? null : currentToken;
      });

      final store = AppStore(api: mockApi, clock: () => mockClockNow);
      var notifications = 0;
      store.addListener(() => notifications++);

      store.toggleTheme();
      expect(store.darkMode, isTrue);
      expect(notifications, 1);

      // Without token refresh is a no-op
      await store.refresh();
      verifyNever(() => mockApi.request('GET', '/state'));

      store.beginSession('tok-1');
      when(
        () => mockApi.request('GET', '/state'),
      ).thenAnswer((_) async => _sampleSnapshotMap());

      await store.poll();
      expect(store.currentUser?.id, '1002');
      expect(store.spaces.length, 2);
      expect(store.syncError, isNull);

      // Failed poll sets syncError instead of throwing
      when(
        () => mockApi.request('GET', '/state'),
      ).thenThrow(DomainError('เครือข่ายขัดข้อง'));
      await store.poll();
      expect(store.syncError, 'เครือข่ายขัดข้อง');

      // mutate succeeds on write but throws recovery message if refresh fails
      when(
        () => mockApi.request('POST', '/bookings/3001/complete', any()),
      ).thenAnswer((_) async => {'ok': true});
      await expectLater(
        store.mutate('POST', '/bookings/3001/complete', {'ok': true}),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            contains('บันทึกแล้ว แต่โหลดข้อมูลล่าสุดไม่ได้'),
          ),
        ),
      );

      store.clearSession();
      expect(store.currentUser, isNull);
      expect(store.users, isEmpty);
      expect(store.spaces, isEmpty);
      expect(store.bookings, isEmpty);
      expect(store.syncError, isNull);
    });
  });

  group('RemoteStore snapshot mapper', () {
    test('decodeImageSafely handles valid, whitespace, empty, and corrupt base64', () {
      expect(decodeImageSafely(''), isNull);
      expect(decodeImageSafely('   '), isNull);
      expect(decodeImageSafely('not!valid!base64==='), isNull);
      expect(
        decodeImageSafely('  ${base64Encode(validMockPngBytes)}  '),
        validMockPngBytes,
      );
    });

    test('applySnapshot parses spaces, bookings, slips, reviews, logs, busy, and URLs', () {
      final store = AppStore(
        api: ApiClient(baseUrl: 'https://api.rentspace.example/api'),
        clock: () => mockClockNow,
      );
      applySnapshot(store, _sampleSnapshotMap());

      expect(store.currentUser?.id, '1002');
      expect(store.currentUser?.favorites, {'2001'});

      final urlSpace = store.space('2001');
      expect(urlSpace.image, 'https://api.rentspace.example/api/spaces/2001/image');
      expect(urlSpace.amenities, ['Wi-Fi', 'โปรเจกเตอร์']);
      expect(urlSpace.availability.blocks.single.reason, 'ซ่อมบำรุง');

      final embeddedSpace = store.space('2002');
      expect(embeddedSpace.image, isEmpty);
      expect(embeddedSpace.imageBytes, validMockPngBytes);
      expect(embeddedSpace.reviewReason, 'รูปไม่ชัด');

      final completedBooking = store.booking('3001');
      expect(completedBooking.status, BookingStatus.completed);
      expect(completedBooking.platformFee, 40);
      expect(completedBooking.payoutSlip?.name, 'payout.png');
      expect(
        completedBooking.payoutSlip?.imageUrl,
        'https://api.rentspace.example/api/bookings/3001/payout-slip',
      );
      expect(completedBooking.review?.rating, 5);

      final rejectedSlipBooking = store.booking('3002');
      expect(rejectedSlipBooking.status, BookingStatus.slipRejected);
      expect(rejectedSlipBooking.reasonKind, ReasonKind.slipRejected);
      expect(rejectedSlipBooking.slips.single.rejectionReason, 'ยอดไม่ตรง');
      expect(store.publicReviews['2001']?.single.comment, 'สะอาดมาก');
      expect(store.issues.single.closed, isFalse);
      expect(store.busySlots.single['space_id'], '2001');
      expect(store.logs.single.actor, 'Admin');

      // Fallback & explicit ReasonKind mappings + invalid base64 space image safety
      final reasonKindSnapshot = Map<String, dynamic>.from(_sampleSnapshotMap());
      reasonKindSnapshot['spaces'] = [
        {
          'id': 2099,
          'owner_id': 1001,
          'name': 'ภาพเสีย',
          'category': 'studio',
          'location': 'กทม',
          'price': 100,
          'capacity': 2,
          'description': '-',
          'image': 'data:image/png;base64,!!!not-base64!!!',
          'amenities': <String>[],
          'status': 'approved',
          'hours': List.generate(7, (_) => {'open': true, 'start': 540, 'end': 1080}),
        },
      ];
      reasonKindSnapshot['bookings'] = [
        {
          'id': 3901,
          'space_id': 2099,
          'owner_id': 1001,
          'renter_id': 1002,
          'space_name': 'ภาพเสีย',
          'booking_date': '2026-11-22',
          'start_minutes': 540,
          'end_minutes': 600,
          'rent_amount': 100,
          'days_count': 1,
          'attendees': 2,
          'zone': '',
          'status': 'owner_rejected',
          'reason': 'ไม่สะดวก',
        },
        {
          'id': 3902,
          'space_id': 2099,
          'owner_id': 1001,
          'renter_id': 1002,
          'space_name': 'ภาพเสีย',
          'booking_date': '2026-11-22',
          'start_minutes': 600,
          'end_minutes': 660,
          'rent_amount': 100,
          'days_count': 1,
          'attendees': 2,
          'zone': '',
          'status': 'canceled',
          'reason': 'ยกเลิก',
        },
        {
          'id': 3903,
          'space_id': 2099,
          'owner_id': 1001,
          'renter_id': 1002,
          'space_name': 'ภาพเสีย',
          'booking_date': '2026-11-22',
          'start_minutes': 660,
          'end_minutes': 720,
          'rent_amount': 100,
          'days_count': 1,
          'attendees': 2,
          'zone': '',
          'status': 'canceled',
          'reason': 'หมดเวลา',
          'reason_kind': 'expired_by_system',
        },
      ];
      applySnapshot(store, reasonKindSnapshot);
      expect(store.space('2099').imageBytes, isNull);
      expect(store.booking('3901').reasonKind, ReasonKind.ownerRejected);
      expect(store.booking('3902').reasonKind, ReasonKind.canceledByUser);
      expect(store.booking('3903').reasonKind, ReasonKind.expiredBySystem);

      // UTC timestamps from backend are normalized to local time
      final utcSnapshot = Map<String, dynamic>.from(_sampleSnapshotMap());
      utcSnapshot['bookings'] = [
        {
          'id': 3904,
          'space_id': 2001,
          'owner_id': 1001,
          'renter_id': 1002,
          'space_name': 'ห้องอารีย์',
          'booking_date': '2026-11-22',
          'start_minutes': 600,
          'end_minutes': 720,
          'rent_amount': 400,
          'days_count': 1,
          'attendees': 2,
          'zone': 'โซนหลัก',
          'status': 'owner_review',
          'created_at': '2026-11-16T02:30:00.000Z',
        },
      ];
      applySnapshot(store, utcSnapshot);
      expect(store.booking('3904').createdAt?.isUtc, isFalse);

      final orphanSnapshot = Map<String, dynamic>.from(_sampleSnapshotMap());
      orphanSnapshot['userId'] = 9999;
      expect(
        () => applySnapshot(store, orphanSnapshot),
        throwsA(isA<DomainError>()),
      );
    });
  });

  group('ApiClient, TokenService, and AppTheme', () {
    test('ApiClient sends Bearer JSON & multipart uploads and maps server/network errors', () async {
      late http.Request capturedJsonRequest;
      late String capturedUploadAuth;
      var scenario = 'ok';

      final mockHttp = MockClient((request) async {
        if (scenario == 'network') {
          throw http.ClientException('connection refused');
        }
        if (scenario == 'invalid_json') {
          return http.Response('<html>502</html>', 502);
        }
        if (scenario == 'api_error') {
          return http.Response.bytes(
            utf8.encode('{"error":"ไม่มีสิทธิ์เข้าถึง"}'),
            403,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        capturedJsonRequest = request;
        return http.Response('{"ok":true}', 200);
      });

      final client = ApiClient(client: mockHttp, baseUrl: 'http://localhost:3001/api/')
        ..token = 'jwt-abc';
      expect(client.baseUrl, 'http://localhost:3001/api');

      final okBody = await client.request('POST', '/spaces', {'name': 'ห้อง'});
      expect(okBody['ok'], isTrue);
      expect(capturedJsonRequest.headers['Authorization'], 'Bearer jwt-abc');
      expect(capturedJsonRequest.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(capturedJsonRequest.body)['name'], 'ห้อง');

      // Test upload multipart request
      final multipartClient = MockClient.streaming((streamedRequest, byteStream) async {
        capturedUploadAuth = streamedRequest.headers['Authorization'] ?? '';
        await byteStream.toBytes();
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"uploaded":true}')),
          200,
        );
      });
      final uploadApi = ApiClient(client: multipartClient, baseUrl: 'http://localhost:3001/api')
        ..token = 'jwt-up';
      final uploadResponse = await uploadApi.upload(
        '/bookings/1/slip',
        'receipt.png',
        validMockPngBytes,
        'หมายเหตุทดสอบ',
      );
      expect(uploadResponse['uploaded'], isTrue);
      expect(capturedUploadAuth, 'Bearer jwt-up');

      scenario = 'invalid_json';
      await expectLater(
        client.request('GET', '/state'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 502)),
      );

      scenario = 'api_error';
      await expectLater(
        client.request('GET', '/state'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 403)),
      );

      final emptyMock = MockClient((_) async => http.Response('', 204));
      final emptyApi = ApiClient(client: emptyMock, baseUrl: 'http://localhost:3001/api');
      await expectLater(
        emptyApi.request('DELETE', '/spaces/1'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 204)),
      );

      scenario = 'network';
      await expectLater(
        client.request('GET', '/state'),
        throwsA(isA<DomainError>()),
      );
    });

    test('TokenService reads, writes, deletes, and handles storage failures gracefully', () async {
      final storage = _MockSecureStorage();
      when(
        () => storage.write(key: TokenService.tokenKey, value: 'tok-99'),
      ).thenAnswer((_) async {});
      when(
        () => storage.read(key: TokenService.tokenKey),
      ).thenAnswer((_) async => 'tok-99');
      when(
        () => storage.delete(key: TokenService.tokenKey),
      ).thenAnswer((_) async {});

      final tokenService = TokenService(storage: storage);
      await tokenService.saveToken('tok-99');
      expect(await tokenService.loadToken(), 'tok-99');
      await tokenService.deleteToken();

      verifyInOrder([
        () => storage.write(key: TokenService.tokenKey, value: 'tok-99'),
        () => storage.read(key: TokenService.tokenKey),
        () => storage.delete(key: TokenService.tokenKey),
      ]);

      // Storage exceptions should be caught rather than crashing login/startup
      when(
        () => storage.write(key: any(named: 'key'), value: any(named: 'value')),
      ).thenThrow(Exception('keystore locked'));
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenThrow(Exception('keystore locked'));
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenThrow(Exception('keystore locked'));

      await tokenService.saveToken('tok-fail');
      expect(await tokenService.loadToken(), isNull);
      await tokenService.deleteToken();
    });

    test('buildAppTheme builds distinct light and dark Material 3 themes', () {
      final lightTheme = buildAppTheme(Brightness.light);
      final darkTheme = buildAppTheme(Brightness.dark);

      expect(lightTheme.brightness, Brightness.light);
      expect(darkTheme.brightness, Brightness.dark);
      expect(lightTheme.colorScheme.primary, const Color(0xFF3C61A7));
      expect(darkTheme.colorScheme.primary, const Color(0xFF6991DC));
      expect(
        lightTheme.scaffoldBackgroundColor != darkTheme.scaffoldBackgroundColor,
        isTrue,
      );
      expect(lightTheme.textTheme.headlineMedium?.letterSpacing, isNull);
      expect(lightTheme.textTheme.labelMedium?.letterSpacing, isNull);
    });
  });
}
