import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/controllers/auth_controller.dart';
import 'package:rentspace/controllers/booking_controller.dart';
import 'package:rentspace/controllers/payment_controller.dart';
import 'package:rentspace/controllers/space_controller.dart';
import 'package:rentspace/data/app_store.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/services/api_client.dart';
import 'package:rentspace/services/token_service.dart';

// mock TokenService class (แบบเดียวกับ MockAuthService ในแล็บอาจารย์)
class MockTokenService extends Mock implements TokenService {}

Future<bool> _probeLiveBackend() async {
  const forceLive = bool.fromEnvironment('RUN_LIVE_TESTS');
  if (forceLive) return true;
  final client = ApiClient();
  try {
    await client.request('GET', '/health').timeout(const Duration(seconds: 2));
    return true;
  } catch (_) {
    return false;
  } finally {
    client.client.close();
  }
}

Future<String> _loginToken(String email) async {
  final client = ApiClient();
  try {
    final json =
        await client.request('POST', '/auth/login', {
              'email': email,
              'password': 'password',
            })
            as Map<String, dynamic>;
    return json['token'] as String;
  } finally {
    client.client.close();
  }
}

Future<void> main() async {
  final liveBackendReady = await _probeLiveBackend();
  final Object liveSkipReason = liveBackendReady
      ? false
      : 'Live backend unavailable at http://localhost:3001/api';

  late String tokenRenter;
  late String tokenOwner;
  late String tokenAdmin;

  setUpAll(() async {
    if (!liveBackendReady) return;
    tokenRenter = await _loginToken('renter01@rentspace.test');
    tokenOwner = await _loginToken('owner01@rentspace.test');
    tokenAdmin = await _loginToken('admin01@rentspace.test');
  });

  group('Login Test (Live Backend API)', skip: liveSkipReason, () {
    test('1. Login correctly should return user role', () async {
      final mockTokenService = MockTokenService();
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});

      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );

      // renter login
      await authController.loginAsync('renter01@rentspace.test', 'password');
      expect(store.currentUser?.role, UserRole.renter);

      // owner login
      await authController.loginAsync('owner01@rentspace.test', 'password');
      expect(store.currentUser?.role, UserRole.owner);

      // admin login
      await authController.loginAsync('admin01@rentspace.test', 'password');
      expect(store.currentUser?.role, UserRole.admin);
    });

    test('2. Login incorrectly should throw error and keep currentUser null', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );

      await expectLater(
        authController.loginAsync('renter01@rentspace.test', '1234'),
        throwsA(isA<DomainError>()),
      );
      expect(store.currentUser, isNull);
    });
  });

  group('User & Space Test (Using JWT token from API)', skip: liveSkipReason, () {
    test('3. Fetch spaces with Renter token should return spaces from DB', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );

      // mock loadToken method คืนค่า token จาก API Test
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});

      final user = await authController.restoreSessionAsync();
      expect(user, isNotNull);
      expect(user?.role, UserRole.renter);
      expect(store.spaces, isNotEmpty);
      expect(
        store.spaces.any((s) => s.name.contains('ห้องประชุมสว่างใจ')),
        isTrue,
      );
    });

    test('4. Add new space with Owner token should have new space in DB', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );
      final spaceController = SpaceController(store);

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenOwner);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});

      // โหลดข้อมูลก่อนเพิ่ม (before)
      await authController.restoreSessionAsync();
      final int before = store.spaces.length;

      // เพิ่มพื้นที่ใหม่ (after)
      final created = await spaceController.saveAsync(
        name: 'Lab Test Studio',
        category: 'สตูดิโอ',
        location: 'เชียงราย มฟล.',
        price: 550,
        capacity: 12,
        description: 'ห้องทดสอบจาก Unit Test',
        amenities: ['Wi-Fi', 'เครื่องปรับอากาศ'],
      );

      expect(store.spaces.length, before + 1);
      expect(created.name, 'Lab Test Studio');
      expect(created.price, 550);
    });

    test('5. Edit space title with Owner token should have the updated title', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );
      final spaceController = SpaceController(store);

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenOwner);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});

      await authController.restoreSessionAsync();
      final target = store.spaces.last;

      // แก้ไขชื่อพื้นที่
      final updated = await spaceController.saveAsync(
        id: target.id,
        name: 'Updated Lab Studio',
        category: target.category,
        location: target.location,
        price: target.price,
        capacity: target.capacity,
        description: target.description,
        amenities: target.amenities,
      );

      expect(updated.name, 'Updated Lab Studio');
    });

    test('6. Toggle favorite space with Renter token should update favorite status', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );
      final spaceController = SpaceController(store);

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});

      await authController.restoreSessionAsync();
      final String targetSpaceId = store.spaces.first.id;
      final bool wasFavorite = store.currentUser!.favorites.contains(targetSpaceId);

      // toggle favorite ครั้งที่ 1
      await spaceController.favoriteAsync(targetSpaceId);
      expect(store.currentUser!.favorites.contains(targetSpaceId), !wasFavorite);

      // toggle favorite กลับคืน
      await spaceController.favoriteAsync(targetSpaceId);
      expect(store.currentUser!.favorites.contains(targetSpaceId), wasFavorite);
    });
  });

  group('Admin Test (Using Admin JWT token from API)', skip: liveSkipReason, () {
    test('7. Admin token should load all users and toggle user active status', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenAdmin);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});

      await authController.restoreSessionAsync();
      expect(store.currentUser?.role, UserRole.admin);
      expect(store.users.length, greaterThanOrEqualTo(4));

      // ทดสอบสลับสถานะผู้ใช้ (เหมือน toggleRole ในแล็บอาจารย์)
      final targetUser = store.users.firstWhere((u) => u.id == '1004');
      final bool beforeActive = targetUser.active;

      await authController.toggleUserAsync('1004');
      final afterToggle = store.users.firstWhere((u) => u.id == '1004');
      expect(afterToggle.active, !beforeActive);

      // สลับกลับคืนค่าเดิม
      await authController.toggleUserAsync('1004');
      final restored = store.users.firstWhere((u) => u.id == '1004');
      expect(restored.active, beforeActive);
    });

    test('8. Admin token should approve pending space', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );
      final spaceController = SpaceController(store);

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenAdmin);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});

      await authController.restoreSessionAsync();
      final targetSpace = store.spaces.last;

      await spaceController.reviewAsync(targetSpace.id, true, '');
      expect(store.space(targetSpace.id).status, SpaceStatus.approved);
    });
  });

  group('Booking & Payment Test (Using Renter & Owner JWT tokens)', skip: liveSkipReason, () {
    test('9. Create booking -> Owner approve -> Upload slip -> Confirm -> Complete & Review', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );
      final bookingController = BookingController(store);
      final paymentController = PaymentController(store);

      // 1) Renter สร้างคำขอจองใหม่
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});
      await authController.restoreSessionAsync();

      final approvedSpace = store.spaces.lastWhere(
        (s) => s.status == SpaceStatus.approved,
      );
      final int beforeBookings = store.bookings.length;
      final DateTime futureDate = DateTime(2027, 5, 10);

      final createdBooking = await bookingController.createAsync(
        approvedSpace.id,
        futureDate,
        600,
        720,
        attendees: 4,
        renterNote: 'จองทดสอบจาก Unit Test',
      );
      expect(store.bookings.length, beforeBookings + 1);
      expect(createdBooking.status, BookingStatus.ownerReview);

      // 2) Owner อนุมัติคำขอจอง (ownerReview -> paymentDue)
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenOwner);
      await authController.restoreSessionAsync();
      await bookingController.ownerReviewAsync(
        createdBooking.id,
        true,
        'อนุมัติให้เข้าใช้งาน',
      );
      expect(
        store.booking(createdBooking.id).status,
        BookingStatus.paymentDue,
      );

      // 3) Renter อัปโหลดสลิปโอนเงิน (paymentDue -> slipReview)
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      await authController.restoreSessionAsync();
      final validPngBytes = Uint8List.fromList([
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 1,
      ]);
      await paymentController.submitAsync(
        createdBooking.id,
        'slip.png',
        validPngBytes,
        'โอนเงินเรียบร้อย',
      );
      expect(
        store.booking(createdBooking.id).status,
        BookingStatus.slipReview,
      );

      // 4) Owner ตรวจสลิปผ่าน (slipReview -> confirmed)
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenOwner);
      await authController.restoreSessionAsync();
      await paymentController.reviewAsync(createdBooking.id, true, '');
      expect(
        store.booking(createdBooking.id).status,
        BookingStatus.confirmed,
      );

      // 5) จบงาน (complete) และ Renter เขียนรีวิว 5 ดาว
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      await authController.restoreSessionAsync();
      await bookingController.completeAsync(createdBooking.id);
      expect(
        store.booking(createdBooking.id).status,
        BookingStatus.completed,
      );

      await bookingController.submitReviewAsync(
        createdBooking.id,
        5,
        'ห้องสะอาด บริการดีมาก',
      );
      expect(store.booking(createdBooking.id).review?.rating, 5);
    });

    test('10. Cancel booking with Renter token should change status to canceled', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );
      final bookingController = BookingController(store);

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});
      await authController.restoreSessionAsync();

      final approvedSpace = store.spaces.lastWhere(
        (s) => s.status == SpaceStatus.approved,
      );
      final created = await bookingController.createAsync(
        approvedSpace.id,
        DateTime(2027, 6, 15),
        780,
        900,
      );

      await bookingController.cancelAsync(created.id, 'เปลี่ยนแผนการเดินทาง');
      expect(store.booking(created.id).status, BookingStatus.canceled);
    });

    test('11. Owner reject booking & Slip rejection + resubmit flow', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );
      final bookingController = BookingController(store);
      final paymentController = PaymentController(store);

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});
      await authController.restoreSessionAsync();

      final approvedSpace = store.spaces.lastWhere(
        (s) => s.status == SpaceStatus.approved,
      );
      final int dayOffset = 12;

      // กรณีที่ 1: Owner ปฏิเสธคำขอจอง (ownerReview -> ownerRejected)
      final bReject = await bookingController.createAsync(
        approvedSpace.id,
        DateTime(2028, 3, dayOffset),
        540,
        660,
      );
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenOwner);
      await authController.restoreSessionAsync();
      await bookingController.ownerReviewAsync(
        bReject.id,
        false,
        'ห้องติดซ่อมระบบไฟ',
      );
      expect(store.booking(bReject.id).status, BookingStatus.ownerRejected);
      expect(store.booking(bReject.id).reason, 'ห้องติดซ่อมระบบไฟ');

      // กรณีที่ 2: สลิปไม่ผ่าน -> ส่งสลิปใหม่ -> อนุมัติ -> โอนเงินให้เจ้าของ (Payout)
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      await authController.restoreSessionAsync();
      final bSlip = await bookingController.createAsync(
        approvedSpace.id,
        DateTime(2028, 4, dayOffset),
        600,
        720,
      );

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenOwner);
      await authController.restoreSessionAsync();
      await bookingController.ownerReviewAsync(bSlip.id, true, '');

      final pngBytes = Uint8List.fromList([
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 1,
      ]);
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      await authController.restoreSessionAsync();
      await paymentController.submitAsync(bSlip.id, 'slip1.png', pngBytes, 'รอบแรก');

      // Owner ปฏิเสธสลิป (slipReview -> slipRejected)
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenOwner);
      await authController.restoreSessionAsync();
      await paymentController.reviewAsync(bSlip.id, false, 'ยอดเงินไม่ตรง');
      expect(store.booking(bSlip.id).status, BookingStatus.slipRejected);
      expect(store.booking(bSlip.id).reason, 'ยอดเงินไม่ตรง');

      // Renter ส่งสลิปใหม่ (slipRejected -> slipReview)
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      await authController.restoreSessionAsync();
      await paymentController.submitAsync(bSlip.id, 'slip2.png', pngBytes, 'ส่งใหม่ครบถ้วน');
      expect(store.booking(bSlip.id).status, BookingStatus.slipReview);

      // Admin อนุมัติสลิป -> เจ้าของยืนยันจบงาน -> Admin โอนเงินให้เจ้าของ (Payout)
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenAdmin);
      await authController.restoreSessionAsync();
      await paymentController.reviewAsync(bSlip.id, true, '');
      expect(store.booking(bSlip.id).status, BookingStatus.confirmed);

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenOwner);
      await authController.restoreSessionAsync();
      await bookingController.completeAsync(bSlip.id);
      expect(store.booking(bSlip.id).status, BookingStatus.completed);

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenAdmin);
      await authController.restoreSessionAsync();
      await paymentController.payoutAsync(bSlip.id);
      expect(store.booking(bSlip.id).paidOutAt, isNotNull);

      await paymentController.payoutAsync(
        bSlip.id,
        fileName: 'payout_slip.png',
        bytes: pngBytes,
        note: 'โอนเงินครบตามยอดสุทธิแล้ว',
      );
      final paidOutBooking = store.booking(bSlip.id);
      expect(paidOutBooking.paidOutAt, isNotNull);
      expect(paidOutBooking.payoutSlip, isNotNull);
      expect(paidOutBooking.payoutSlip!.name, 'payout_slip.png');
      expect(paidOutBooking.payoutSlip!.note, 'โอนเงินครบตามยอดสุทธิแล้ว');
      expect(paidOutBooking.payoutSlip!.imageUrl, contains('/uploads/payout_'));
    });
  });

  group('Profile, Password, Availability, Issues & Validation Logic Test', skip: liveSkipReason, () {
    test('12. Update profile & Change password with Renter token', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});
      await authController.restoreSessionAsync();

      final originalName = store.currentUser!.name;
      final originalEmail = store.currentUser!.email;

      await authController.updateProfileAsync(
        'ณัฐ วงศ์ดี (Updated)',
        originalEmail,
        '081-234-5678',
        'SCB 123-456-7890',
      );
      expect(store.currentUser!.name, 'ณัฐ วงศ์ดี (Updated)');
      expect(store.currentUser!.bankInfo, 'SCB 123-456-7890');

      // คืนค่าชื่อเดิม
      await authController.updateProfileAsync(
        originalName,
        originalEmail,
        '081-234-5678',
        'SCB 123-456-7890',
      );

      // ทดสอบเปลี่ยนรหัสผ่านและเปลี่ยนกลับเป็น password
      await authController.changePasswordAsync(
        'password',
        'newpass1234',
        'newpass1234',
      );
      await authController.changePasswordAsync(
        'newpass1234',
        'password',
        'password',
      );
    });

    test('13. Owner availability schedule & Room block periods', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );
      final spaceController = SpaceController(store);

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenOwner);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});
      await authController.restoreSessionAsync();

      final targetSpace = store.spaces.last;
      final customAvailability = Availability(
        days: List.generate(
          7,
          (_) => DayHours(open: true, start: 480, end: 1200),
        ),
        blocks: [
          BlockedPeriod(
            id: 'blk-1',
            start: DateTime(2029, 1, 10, 9),
            end: DateTime(2029, 1, 11, 18),
            reason: 'ทำความสะอาดประจำปี',
          ),
        ],
      );

      await spaceController.saveAvailabilityAsync(
        targetSpace.id,
        customAvailability,
      );
      final reloaded = store.space(targetSpace.id);
      expect(reloaded.availability.days.first.start, 480);
      expect(reloaded.availability.blocks, isNotEmpty);
      expect(reloaded.availability.blocks.first.reason, 'ทำความสะอาดประจำปี');
    });

    test('14. Report issue with Renter token & Close issue with Admin token', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );
      final spaceController = SpaceController(store);

      // Renter แจ้งปัญหาการใช้งาน
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});
      await authController.restoreSessionAsync();

      final int beforeIssues = store.issues.length;
      await spaceController.reportAsync(
        'แอร์ไม่เย็น',
        'ห้องประชุมชั้น 2 แอร์ไม่ทำงาน',
      );
      expect(store.issues.length, beforeIssues + 1);
      final createdIssue = store.issues.first;
      expect(createdIssue.closed, isFalse);

      // Admin ปิดงานแจ้งปัญหาและบันทึกผลแก้ไข
      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenAdmin);
      await authController.restoreSessionAsync();
      await spaceController.closeIssueAsync(
        createdIssue.id,
        'ส่งช่างเข้าซ่อมเรียบร้อยแล้ว',
      );
      final closedIssue = store.issues.firstWhere(
        (i) => i.id == createdIssue.id,
      );
      expect(closedIssue.closed, isTrue);
      expect(closedIssue.resolution, 'ส่งช่างเข้าซ่อมเรียบร้อยแล้ว');
    });

    test('15. Admin suspend & reactivate space', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );
      final spaceController = SpaceController(store);

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenAdmin);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});
      await authController.restoreSessionAsync();

      final targetSpace = store.spaces.last;
      await spaceController.suspendSpaceAsync(
        targetSpace.id,
        'รูปภาพไม่ชัดเจน',
      );
      expect(store.space(targetSpace.id).status, SpaceStatus.rejected);
      expect(store.space(targetSpace.id).reviewReason, 'รูปภาพไม่ชัดเจน');

      await spaceController.activateSpaceAsync(targetSpace.id);
      expect(store.space(targetSpace.id).status, SpaceStatus.approved);
    });

    test('16. Search/filter/sort spaces, rent pricing, slot rules & slip validation', () async {
      final mockTokenService = MockTokenService();
      final store = AppStore();
      final authController = AuthController(
        store,
        tokenService: mockTokenService,
      );
      final spaceController = SpaceController(store);
      final bookingController = BookingController(store);

      when(() => mockTokenService.loadToken()).thenAnswer((_) async => tokenRenter);
      when(() => mockTokenService.saveToken(any())).thenAnswer((_) async {});
      await authController.restoreSessionAsync();

      // ทดสอบค้นหา กรองราคา ความจุ และเรียงลำดับราคาจากน้อยไปมาก
      final sortedAsc = spaceController.filterSpaces(
        sort: SpaceSort.priceAsc,
        maxPrice: 5000,
        minCapacity: 2,
      );
      expect(sortedAsc, isNotEmpty);
      if (sortedAsc.length >= 2) {
        expect(sortedAsc.first.price <= sortedAsc.last.price, isTrue);
      }

      // ทดสอบสูตรคำนวณค่าเช่าและค่าธรรมเนียมแพลตฟอร์ม 5%
      expect(BookingController.rent(350, 540, 720, days: 2), 2100);
      expect(BookingController.durationError(600, 630), isNotNull); // น้อยกว่า 60 นาที
      expect(BookingController.durationError(600, 720), isNull);

      // ทดสอบการเลือกและขยายช่วงเวลารายชั่วโมง (selectOrExtendSlot)
      final slots = bookingController.hourlySlots(
        sortedAsc.first,
        DateTime(2027, 8, 15),
      );
      expect(slots, isNotEmpty);

      // ทดสอบตรวจสอบไฟล์สลิป PNG/JPG (validateSlip)
      expect(
        () => PaymentController.validateSlip(
          'virus.exe',
          Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<DomainError>()),
      );
    });
  });

  group('Offline Domain Rules Test (Always runs without backend)', () {
    test('17. Rent calculation, duration bounds, and slip byte validation', () {
      expect(BookingController.rent(350, 540, 720, days: 2), 2100);
      expect(BookingController.durationError(600, 630), isNotNull);
      expect(BookingController.durationError(600, 720), isNull);

      final validPng = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]);
      expect(() => PaymentController.validateSlip('slip.png', validPng), returnsNormally);
      expect(
        () => PaymentController.validateSlip('virus.png', Uint8List.fromList([1, 2, 3])),
        throwsA(isA<DomainError>()),
      );
    });
  });
}
