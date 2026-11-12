import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/controllers/auth_controller.dart';
import 'package:rentspace/controllers/booking_controller.dart';
import 'package:rentspace/controllers/payment_controller.dart';
import 'package:rentspace/controllers/space_controller.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/services/auth_service.dart';
import 'package:rentspace/services/booking_service.dart';
import 'package:rentspace/services/payment_service.dart';
import 'package:rentspace/services/space_service.dart';
import 'package:rentspace/services/token_service.dart';

// ─── Mock ของ service ที่เขียนเองในโปรเจกต์ (ไม่ใช่ของไลบรารีภายนอก) ──────────
class MockAuthService extends Mock implements AuthService {}

class MockBookingService extends Mock implements BookingService {}

class MockPaymentService extends Mock implements PaymentService {}

class MockSpaceService extends Mock implements SpaceService {}

class MockTokenService extends Mock implements TokenService {}

AppUser fakeUser(
  String id,
  UserRole role, {
  String? email,
  bool active = true,
}) => AppUser(
  id: id,
  name: 'ผู้ใช้ $id',
  email: email ?? '$id@demo.com',
  password: 'demo1234',
  role: role,
  phone: '081-234-5678',
  active: active,
);

Booking fakeBooking({
  String id = 'RS-1',
  String ownerId = 'owner-1',
  String renterId = 'renter-1',
  BookingStatus status = BookingStatus.ownerReview,
  DateTime? date,
}) => Booking(
  id: id,
  spaceId: 'space-1',
  ownerId: ownerId,
  renterId: renterId,
  spaceName: 'พื้นที่ space-1',
  date: date ?? DateTime(2026, 11, 20),
  startMinutes: 600,
  endMinutes: 720,
  rentAmount: 850,
  status: status,
);

Space fakeSpace(String id, SpaceStatus status) => Space(
  id: id,
  ownerId: 'owner-1',
  name: 'พื้นที่ $id',
  category: 'สตูดิโอ',
  location: 'สุขุมวิท',
  price: 850,
  capacity: 8,
  description: 'รายละเอียดทดสอบ',
  status: status,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall methodCall) async => null,
        );
    registerFallbackValue(fakeUser('fallback', UserRole.renter));
  });

  late String token; // ผู้เช่า
  late String ownerToken; // เจ้าของพื้นที่
  late String adminToken; // แอดมิน
  setUp(() {
    token =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJzdWIiOiJyZW50ZXItMSIsImlhdCI6MTc5NDQ3MDU2NiwiZXhwIjoxNzk1MDc1MzY2fQ.'
        'XohBKJs7KbfaFJQgEwsRr8v9vNpmzsSkBJr-_uNa8Io';
    ownerToken =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJzdWIiOiJvd25lci0xIiwiaWF0IjoxNzk0NDcwNjU5LCJleHAiOjE3OTUwNzU0NTl9.'
        'ToQYpkXn7tu6wx6KQBhC9f5oa6WM723qMdqID4ROIjw';
    adminToken =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJzdWIiOiJhZG1pbi0xIiwiaWF0IjoxNzk0NDcwODI0LCJleHAiOjE3OTUwNzU2MjR9.'
        '_YlyYuqqBLe42ix3WPxiZpe2l_zxSwHgklZeQ2jRwpg';
  });

  group('AuthController + MockAuthService', () {
    test('login สำเร็จ: ค้นหาบัญชีผ่าน service แล้วเปิดเซสชัน', () {
      final svc = MockAuthService();
      final renter = fakeUser(
        'renter-1',
        UserRole.renter,
        email: 'renter@demo.com',
      );
      when(
        () => svc.matchCredentials('renter@demo.com', 'demo1234'),
      ).thenReturn([renter]);
      when(() => svc.signIn(renter)).thenAnswer((_) {});
      when(() => svc.changed('เข้าสู่ระบบ')).thenAnswer((_) {});
      when(() => svc.sweepExpired()).thenAnswer((_) {});

      AuthController.withService(svc).login('renter@demo.com', 'demo1234');

      verify(
        () => svc.matchCredentials('renter@demo.com', 'demo1234'),
      ).called(1);
      verify(() => svc.signIn(renter)).called(1);
      verify(() => svc.sweepExpired()).called(1);
    });

    test('login ล้มเหลว: service ไม่คืนบัญชี ต้องไม่เปิดเซสชัน', () {
      final svc = MockAuthService();
      when(() => svc.matchCredentials(any(), any())).thenReturn([]);

      expect(
        () => AuthController.withService(svc).login('x@y.com', 'bad'),
        throwsA(isA<DomainError>()),
      );
      verifyNever(() => svc.signIn(any()));
    });

    test('login: บัญชีถูกระงับ ต้องไม่เปิดเซสชัน', () {
      final svc = MockAuthService();
      final suspended = fakeUser(
        'renter-1',
        UserRole.renter,
        email: 'renter@demo.com',
        active: false,
      );
      when(
        () => svc.matchCredentials('renter@demo.com', 'demo1234'),
      ).thenReturn([suspended]);

      expect(
        () => AuthController.withService(svc).login('renter@demo.com', 'demo1234'),
        throwsA(isA<DomainError>()),
      );
      verifyNever(() => svc.signIn(any()));
    });

    test('logout: สั่ง service ปิดเซสชันและบันทึกเหตุการณ์', () {
      final svc = MockAuthService();
      when(() => svc.signOut()).thenAnswer((_) {});
      when(() => svc.changed('ออกจากระบบ')).thenAnswer((_) {});

      AuthController.withService(svc).logout();

      verify(() => svc.signOut()).called(1);
      verify(() => svc.changed('ออกจากระบบ')).called(1);
    });
  });

  group('BookingController + MockBookingService', () {
    test('create: service บอกว่าช่วงเวลาชน ต้องโยน DomainError', () {
      final svc = MockBookingService();
      final day = DateTime(2026, 11, 7);
      when(() => svc.requireUser(UserRole.renter)).thenReturn(
        fakeUser('renter-1', UserRole.renter),
      );
      when(() => svc.space('space-1')).thenReturn(
        fakeSpace('space-1', SpaceStatus.approved),
      );
      when(() => svc.user('owner-1')).thenReturn(
        fakeUser('owner-1', UserRole.owner),
      );
      when(() => svc.clock()).thenReturn(DateTime(2026, 11, 6, 8));
      when(() => svc.sweepExpired()).thenAnswer((_) {});
      when(
        () => svc.conflicts('space-1', day, 600, 720, days: 1),
      ).thenReturn(true);

      expect(
        () => BookingController.withService(
          svc,
        ).create('space-1', day, 600, 720),
        throwsA(isA<DomainError>()),
      );
      verify(() => svc.conflicts('space-1', day, 600, 720, days: 1)).called(1);
      verifyNever(() => svc.nextId('RS'));
    });

    test('isSlotAvailable: ใช้ clock และ conflicts จาก service', () {
      final svc = MockBookingService();
      final day = DateTime(2026, 11, 7);
      when(() => svc.space('space-1')).thenReturn(
        fakeSpace('space-1', SpaceStatus.approved),
      );
      when(() => svc.clock()).thenReturn(DateTime(2026, 11, 6, 8));
      when(
        () => svc.conflicts('space-1', day, 600, 720, days: 1),
      ).thenReturn(false);

      final controller = BookingController.withService(svc);

      expect(controller.isSlotAvailable('space-1', day, 600, 720), isTrue);

      when(
        () => svc.conflicts('space-1', day, 600, 720, days: 1),
      ).thenReturn(true);
      expect(controller.isSlotAvailable('space-1', day, 600, 720), isFalse);
    });
  });

  group('PaymentController + MockPaymentService', () {
    test('review: service ปฏิเสธสิทธิ์ ต้องไม่แตะรายการจอง', () {
      final svc = MockPaymentService();
      when(
        () => svc.requireUser(UserRole.admin),
      ).thenThrow(DomainError('บัญชีนี้ไม่มีสิทธิ์ทำรายการ'));

      expect(
        () => PaymentController.withService(svc).review('RS-1', true, ''),
        throwsA(isA<DomainError>()),
      );
      verifyNever(() => svc.booking(any()));
    });
  });

  group('SpaceController + MockSpaceService', () {
    test('filterSpaces: ใช้รายการพื้นที่และสถานะเจ้าของจาก service', () {
      final svc = MockSpaceService();
      when(() => svc.spaces).thenReturn([
        fakeSpace('space-1', SpaceStatus.approved),
        fakeSpace('space-2', SpaceStatus.pending),
      ]);
      when(() => svc.user('owner-1')).thenReturn(
        fakeUser('owner-1', UserRole.owner),
      );

      final result = SpaceController.withService(svc).filterSpaces();

      expect(result.map((s) => s.id), ['space-1']);
    });

    test('filterSpaces: เจ้าของถูกระงับ ประกาศต้องไม่ขึ้น', () {
      final svc = MockSpaceService();
      when(() => svc.spaces).thenReturn([
        fakeSpace('space-1', SpaceStatus.approved),
      ]);
      when(() => svc.user('owner-1')).thenReturn(
        fakeUser('owner-1', UserRole.owner, active: false),
      );

      expect(SpaceController.withService(svc).filterSpaces(), isEmpty);
    });
  });

  // ─── token service: บันทึก/อ่าน/ลบ session token (แบบเดียวกับตัวอย่างอาจารย์) ──
  group('AuthController + MockTokenService', () {
    test('1. login สำเร็จต้องบันทึก token ผ่าน tokenService', () {
      final tokens = MockTokenService();
      final svc = MockAuthService();
      final renter = fakeUser('renter-1', UserRole.renter);

      when(() => svc.matchCredentials(any(), any())).thenReturn([renter]);
      when(() => svc.signIn(renter)).thenAnswer((_) {});
      when(() => svc.changed(any())).thenAnswer((_) {});
      when(() => svc.sweepExpired()).thenAnswer((_) {});
      when(() => tokens.saveToken('renter-1')).thenAnswer((_) async {});

      AuthController.withService(
        svc,
        tokenService: tokens,
      ).login('renter@demo.com', 'demo1234');

      verify(() => tokens.saveToken('renter-1')).called(1);
    });

    test('2. logout ต้องลบ token ผ่าน tokenService', () {
      final tokens = MockTokenService();
      final svc = MockAuthService();

      when(() => svc.changed(any())).thenAnswer((_) {});
      when(() => svc.signOut()).thenAnswer((_) {});
      when(() => tokens.deleteToken()).thenAnswer((_) async {});

      AuthController.withService(svc, tokenService: tokens).logout();

      verify(() => tokens.deleteToken()).called(1);
    });

    test('3. restoreSession: มี token ในเครื่อง ต้องล็อกอินกลับให้', () async {
      final tokens = MockTokenService();
      final svc = MockAuthService();
      final renter = fakeUser('renter-1', UserRole.renter);

      when(() => tokens.loadToken()).thenAnswer((_) async => token);
      when(() => svc.user('renter-1')).thenReturn(renter);
      when(() => svc.signIn(renter)).thenAnswer((_) {});
      when(() => svc.changed('คืนเซสชันผู้ใช้')).thenAnswer((_) {});

      final result = await AuthController.withService(
        svc,
        tokenService: tokens,
      ).restoreSession();

      expect(result?.id, 'renter-1');
      verify(() => svc.signIn(renter)).called(1);
    });

    test('4. restoreSession: ไม่มี token ต้องไม่ล็อกอิน', () async {
      final tokens = MockTokenService();
      final svc = MockAuthService();

      when(() => tokens.loadToken()).thenAnswer((_) async => null);

      final result = await AuthController.withService(
        svc,
        tokenService: tokens,
      ).restoreSession();

      expect(result, isNull);
      verifyNever(() => svc.signIn(any()));
    });

    test('5. restoreSession: token ชี้บัญชีที่ไม่มีแล้ว ต้องลบทิ้ง', () async {
      final tokens = MockTokenService();
      final svc = MockAuthService();

      when(() => tokens.loadToken()).thenAnswer((_) async => 'ghost-1');
      when(() => svc.user('ghost-1')).thenThrow(DomainError('ไม่พบข้อมูล'));
      when(() => tokens.deleteToken()).thenAnswer((_) async {});

      final result = await AuthController.withService(
        svc,
        tokenService: tokens,
      ).restoreSession();

      expect(result, isNull);
      verify(() => tokens.deleteToken()).called(1);
    });

    test('6. restoreSession: บัญชีถูกระงับ ต้องไม่ล็อกอินกลับ', () async {
      final tokens = MockTokenService();
      final svc = MockAuthService();
      final suspended = fakeUser('renter-1', UserRole.renter, active: false);

      when(() => tokens.loadToken()).thenAnswer((_) async => 'renter-1');
      when(() => svc.user('renter-1')).thenReturn(suspended);

      final result = await AuthController.withService(
        svc,
        tokenService: tokens,
      ).restoreSession();

      expect(result, isNull);
      verifyNever(() => svc.signIn(any()));
    });

    test('7. restoreSession: token ของเจ้าของพื้นที่และแอดมินก็คืนเซสชันได้', () async {
      final cases = <(String, String, UserRole)>[
        (ownerToken, 'owner-1', UserRole.owner),
        (adminToken, 'admin-1', UserRole.admin),
      ];

      for (final (jwt, id, role) in cases) {
        final tokens = MockTokenService();
        final svc = MockAuthService();
        final account = fakeUser(id, role);

        when(() => tokens.loadToken()).thenAnswer((_) async => jwt);
        when(() => svc.user(id)).thenReturn(account);
        when(() => svc.signIn(account)).thenAnswer((_) {});
        when(() => svc.changed(any())).thenAnswer((_) {});

        final result = await AuthController.withService(
          svc,
          tokenService: tokens,
        ).restoreSession();

        expect(result?.id, id, reason: 'id ของ $role');
        expect(result?.role, role, reason: 'บทบาท $role');
        verify(() => svc.signIn(account)).called(1);
      }
    });
  });

  // ─── เมธอดที่เหลือของ BookingController ─────────────────────────────────────
  group('BookingController: ownerReview / cancel / complete / review', () {
    test('ownerReview: ไม่ใช่เจ้าของพื้นที่ ต้องตรวจไม่ได้', () {
      final svc = MockBookingService();
      when(
        () => svc.requireUser(UserRole.owner),
      ).thenReturn(fakeUser('owner-1', UserRole.owner));
      when(
        () => svc.booking('RS-1'),
      ).thenReturn(fakeBooking(ownerId: 'owner-2'));
      when(() => svc.sweepExpired()).thenAnswer((_) {});

      expect(
        () => BookingController.withService(
          svc,
        ).ownerReview('RS-1', true, ''),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'ไม่สามารถตรวจคำขอนี้ได้',
          ),
        ),
      );
    });

    test('ownerReview: ปฏิเสธโดยไม่ระบุเหตุผล ต้องไม่ผ่าน', () {
      final svc = MockBookingService();
      when(
        () => svc.requireUser(UserRole.owner),
      ).thenReturn(fakeUser('owner-1', UserRole.owner));
      when(() => svc.booking('RS-1')).thenReturn(fakeBooking());
      when(() => svc.sweepExpired()).thenAnswer((_) {});

      expect(
        () => BookingController.withService(
          svc,
        ).ownerReview('RS-1', false, ''),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'กรุณาระบุเหตุผล',
          ),
        ),
      );
    });

    test('cancel: ผู้เช่ายกเลิกรายการที่รอตรวจสลิปไม่ได้', () {
      final svc = MockBookingService();
      when(
        () => svc.requireUser(),
      ).thenReturn(fakeUser('renter-1', UserRole.renter));
      when(
        () => svc.booking('RS-1'),
      ).thenReturn(fakeBooking(status: BookingStatus.slipReview));
      when(() => svc.sweepExpired()).thenAnswer((_) {});

      expect(
        () => BookingController.withService(svc).cancel('RS-1', 'ไม่สะดวก'),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'รายการที่ชำระเงินหรือรอตรวจสลิปต้องให้ Admin จัดการ',
          ),
        ),
      );
    });

    test('complete: จบรายการก่อนถึงเวลาสิ้นสุดไม่ได้', () {
      final svc = MockBookingService();
      when(
        () => svc.requireUser(UserRole.owner),
      ).thenReturn(fakeUser('owner-1', UserRole.owner));
      when(
        () => svc.booking('RS-1'),
      ).thenReturn(fakeBooking(status: BookingStatus.confirmed));
      when(() => svc.clock()).thenReturn(DateTime(2026, 11, 6, 8));
      when(() => svc.sweepExpired()).thenAnswer((_) {});

      expect(
        () => BookingController.withService(svc).complete('RS-1'),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'ต้องรอจนสิ้นสุดเวลาใช้บริการ',
          ),
        ),
      );
    });

    test('submitReview: คะแนนนอกช่วง 1-5 ต้องถูกปฏิเสธ', () {
      final svc = MockBookingService();
      when(
        () => svc.requireUser(UserRole.renter),
      ).thenReturn(fakeUser('renter-1', UserRole.renter));
      when(
        () => svc.booking('RS-1'),
      ).thenReturn(fakeBooking(status: BookingStatus.completed));

      expect(
        () => BookingController.withService(svc).submitReview('RS-1', 0, 'ดี'),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'กรุณาเลือกคะแนน 1–5 ดาว และระบุความคิดเห็น',
          ),
        ),
      );
    });
  });

  // ─── เมธอดที่เหลือของ PaymentController ─────────────────────────────────────
  group('PaymentController: submit / payout', () {
    test('submit: ผู้เช่าคนอื่นส่งสลิปแทนไม่ได้', () {
      final svc = MockPaymentService();
      when(
        () => svc.requireUser(UserRole.renter),
      ).thenReturn(fakeUser('renter-1', UserRole.renter));
      when(
        () => svc.booking('RS-1'),
      ).thenReturn(fakeBooking(renterId: 'renter-2', status: BookingStatus.paymentDue));
      when(() => svc.sweepExpired()).thenAnswer((_) {});

      expect(
        () => PaymentController.withService(
          svc,
        ).submit('RS-1', 'slip.png', Uint8List(0), ''),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'รายการนี้ยังไม่พร้อมส่งสลิป',
          ),
        ),
      );
    });

    test('payout: จ่ายได้เฉพาะรายการที่จบแล้ว', () {
      final svc = MockPaymentService();
      when(
        () => svc.requireUser(UserRole.admin),
      ).thenReturn(fakeUser('admin-1', UserRole.admin));
      when(
        () => svc.booking('RS-1'),
      ).thenReturn(fakeBooking(status: BookingStatus.confirmed));
      when(() => svc.sweepExpired()).thenAnswer((_) {});

      expect(
        () => PaymentController.withService(svc).payout('RS-1'),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'รายการนี้ยังจ่ายไม่ได้หรือจ่ายแล้ว',
          ),
        ),
      );
    });
  });

  // ─── เมธอดที่เหลือของ SpaceController ───────────────────────────────────────
  group('SpaceController: review / suspend / favorite / report / issue', () {
    test('review: ผู้ที่ไม่ใช่แอดมินตรวจประกาศไม่ได้', () {
      final svc = MockSpaceService();
      when(
        () => svc.requireUser(UserRole.admin),
      ).thenThrow(DomainError('บัญชีนี้ไม่มีสิทธิ์ทำรายการ'));

      expect(
        () => SpaceController.withService(svc).review('space-1', true, ''),
        throwsA(isA<DomainError>()),
      );
      verifyNever(() => svc.space(any()));
    });

    test('review: ประกาศที่ตรวจแล้ว ตรวจซ้ำไม่ได้', () {
      final svc = MockSpaceService();
      when(
        () => svc.requireUser(UserRole.admin),
      ).thenReturn(fakeUser('admin-1', UserRole.admin));
      when(
        () => svc.space('space-1'),
      ).thenReturn(fakeSpace('space-1', SpaceStatus.approved));

      expect(
        () => SpaceController.withService(svc).review('space-1', true, ''),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'ประกาศนี้ได้รับการตรวจแล้ว',
          ),
        ),
      );
    });

    test('suspendSpace: ระงับโดยไม่ระบุเหตุผลไม่ได้', () {
      final svc = MockSpaceService();
      when(
        () => svc.requireUser(UserRole.admin),
      ).thenReturn(fakeUser('admin-1', UserRole.admin));
      when(
        () => svc.space('space-1'),
      ).thenReturn(fakeSpace('space-1', SpaceStatus.approved));

      expect(
        () => SpaceController.withService(svc).suspendSpace('space-1', ''),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'กรุณาระบุเหตุผลการระงับพื้นที่',
          ),
        ),
      );
    });

    test('favorite: กดซ้ำต้องเป็นการถอดรายการโปรด', () {
      final svc = MockSpaceService();
      final renter = fakeUser('renter-1', UserRole.renter);
      when(() => svc.requireUser(UserRole.renter)).thenReturn(renter);
      when(() => svc.space('space-1')).thenReturn(
        fakeSpace('space-1', SpaceStatus.approved),
      );
      when(() => svc.changed(any())).thenAnswer((_) {});

      final controller = SpaceController.withService(svc);
      controller.favorite('space-1');
      expect(renter.favorites, contains('space-1'));

      controller.favorite('space-1');
      expect(renter.favorites, isNot(contains('space-1')));
    });

    test('report: แจ้งปัญหาโดยไม่มีรายละเอียดไม่ได้', () {
      final svc = MockSpaceService();
      when(
        () => svc.requireUser(),
      ).thenReturn(fakeUser('renter-1', UserRole.renter));

      expect(
        () => SpaceController.withService(svc).report('พื้นที่', '   '),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'กรุณาระบุรายละเอียด',
          ),
        ),
      );
    });

    test('closeIssue: ปิดรายงานที่ปิดแล้วซ้ำไม่ได้', () {
      final svc = MockSpaceService();
      when(
        () => svc.requireUser(UserRole.admin),
      ).thenReturn(fakeUser('admin-1', UserRole.admin));
      final issue = Issue(
        id: 'ISSUE-1',
        reporterId: 'renter-1',
        subject: 'พื้นที่',
        detail: 'รูปไม่ตรง',
      )..closed = true;
      when(() => svc.issues).thenReturn([issue]);

      expect(
        () => SpaceController.withService(svc).closeIssue('ISSUE-1', 'แก้แล้ว'),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'รายงานนี้ปิดแล้ว',
          ),
        ),
      );
    });

    test('saveAvailability: ตั้งเวลาปิดก่อนเปิดไม่ได้', () {
      final svc = MockSpaceService();
      when(
        () => svc.requireUser(UserRole.owner),
      ).thenReturn(fakeUser('owner-1', UserRole.owner));
      when(
        () => svc.space('space-1'),
      ).thenReturn(fakeSpace('space-1', SpaceStatus.approved));
      when(() => svc.sweepExpired()).thenAnswer((_) {});
      final bad = Availability();
      bad.days[0].start = 1080;
      bad.days[0].end = 540;

      expect(
        () => SpaceController.withService(svc).saveAvailability('space-1', bad),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'เวลาปิดต้องอยู่หลังเวลาเปิด',
          ),
        ),
      );
    });
  });

  // ─── เมธอดที่เหลือของ AuthController ────────────────────────────────────────
  group('AuthController: register / password / users', () {
    test('register: สมัครเป็นแอดมินเองไม่ได้', () {
      final svc = MockAuthService();

      expect(
        () => AuthController.withService(
          svc,
        ).register('ใหม่', 'new@x.com', 'password1', UserRole.admin, '0812345678'),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'ไม่สามารถสมัครบัญชี Admin',
          ),
        ),
      );
    });

    test('register: รหัสผ่านสั้นกว่า 8 ตัวอักษรไม่ได้', () {
      final svc = MockAuthService();
      when(() => svc.users).thenReturn([]);

      expect(
        () => AuthController.withService(
          svc,
        ).register('ใหม่', 'new@x.com', 'short', UserRole.renter, '0812345678'),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร',
          ),
        ),
      );
    });

    test('changePassword: รหัสผ่านปัจจุบันผิดไม่ได้', () {
      final svc = MockAuthService();
      when(
        () => svc.requireUser(),
      ).thenReturn(fakeUser('renter-1', UserRole.renter));

      expect(
        () => AuthController.withService(
          svc,
        ).changePassword('wrong', 'newpass123', 'newpass123'),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'รหัสผ่านปัจจุบันไม่ถูกต้อง',
          ),
        ),
      );
    });

    test('toggleUser: ระงับบัญชีแอดมินไม่ได้', () {
      final svc = MockAuthService();
      when(
        () => svc.requireUser(UserRole.admin),
      ).thenReturn(fakeUser('admin-1', UserRole.admin));
      when(
        () => svc.user('admin-2'),
      ).thenReturn(fakeUser('admin-2', UserRole.admin));

      expect(
        () => AuthController.withService(svc).toggleUser('admin-2'),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'ไม่สามารถระงับบัญชี Admin',
          ),
        ),
      );
    });

    test('filterUsers: กรองตามบทบาทและคำค้น', () {
      final svc = MockAuthService();
      final owner = fakeUser('owner-1', UserRole.owner, email: 'owner@x.com');
      final renter = fakeUser('renter-1', UserRole.renter, email: 'a@x.com');
      when(() => svc.users).thenReturn([owner, renter]);

      final controller = AuthController.withService(svc);

      expect(controller.filterUsers(role: UserRole.owner).map((u) => u.id), [
        'owner-1',
      ]);
      expect(controller.filterUsers(query: 'owner@x').map((u) => u.id), [
        'owner-1',
      ]);
      expect(controller.filterUsers().length, 2);
    });
  });

  // ─── เมธอดสุดท้ายที่ยังไม่มีเทสต์ mock ──────────────────────────────────────
  group('เมธอดที่เหลือ: demo / profile / slots / save / activate / rating', () {
    test('demo: ล็อกอินด้วยบัญชีตัวอย่างตามบทบาท', () {
      final svc = MockAuthService();
      final tokens = MockTokenService();
      final renter = fakeUser('renter-1', UserRole.renter);

      when(() => svc.user('renter-1')).thenReturn(renter);
      when(() => svc.matchCredentials(any(), any())).thenReturn([renter]);
      when(() => svc.signIn(renter)).thenAnswer((_) {});
      when(() => svc.changed(any())).thenAnswer((_) {});
      when(() => svc.sweepExpired()).thenAnswer((_) {});
      when(() => tokens.saveToken('renter-1')).thenAnswer((_) async {});

      AuthController.withService(svc, tokenService: tokens).demo(UserRole.renter);

      verify(() => svc.signIn(renter)).called(1);
    });

    test('validateProfile: อีเมลซ้ำกับบัญชีอื่นไม่ได้', () {
      final svc = MockAuthService();
      when(() => svc.users).thenReturn([
        fakeUser('renter-2', UserRole.renter, email: 'taken@x.com'),
      ]);

      expect(
        () => AuthController.withService(
          svc,
        ).validateProfile('ใหม่', 'taken@x.com', '0812345678'),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'อีเมลนี้ถูกใช้งานแล้ว',
          ),
        ),
      );
    });

    test('updateProfile: แก้ชื่อและเบอร์แล้วบันทึก', () {
      final svc = MockAuthService();
      final renter = fakeUser('renter-1', UserRole.renter);
      when(() => svc.requireUser()).thenReturn(renter);
      when(() => svc.users).thenReturn([renter]);
      when(() => svc.changed('บันทึกโปรไฟล์')).thenAnswer((_) {});

      AuthController.withService(
        svc,
      ).updateProfile('ชื่อใหม่', 'renter@demo.com', '0899999999');

      expect(renter.name, 'ชื่อใหม่');
      expect(renter.phone, '0899999999');
      verify(() => svc.changed('บันทึกโปรไฟล์')).called(1);
    });

    test('busySlotLabels: แสดงช่วงเวลาที่ถูกจองแล้ว', () {
      final svc = MockBookingService();
      final day = DateTime(2026, 11, 20);
      when(() => svc.bookings).thenReturn([
        fakeBooking(status: BookingStatus.paymentDue, date: day),
      ]);
      when(() => svc.space('space-1')).thenReturn(
        fakeSpace('space-1', SpaceStatus.approved),
      );

      final labels = BookingController.withService(
        svc,
      ).busySlotLabels('space-1', day);

      expect(labels.length, 1);
      expect(labels.first, contains('10:00–12:00'));
    });

    test('save: สร้างประกาศใหม่แล้วได้สถานะ pending', () {
      final svc = MockSpaceService();
      final owner = fakeUser('owner-1', UserRole.owner);
      final list = <Space>[];
      when(() => svc.requireUser(UserRole.owner)).thenReturn(owner);
      when(() => svc.nextId('SPACE')).thenReturn('SPACE-9');
      when(() => svc.spaces).thenReturn(list);
      when(() => svc.changed(any())).thenAnswer((_) {});

      final space = SpaceController.withService(svc).save(
        name: 'ห้องใหม่',
        category: 'ห้องประชุม',
        location: 'อารีย์',
        price: 500,
        capacity: 6,
        description: 'ห้องทดสอบ',
        amenities: ['Wi-Fi'],
      );

      expect(space.id, 'SPACE-9');
      expect(space.status, SpaceStatus.pending);
      expect(list.length, 1);
    });

    test('save: บันทึกประกาศพร้อมแนบรูปภาพเป็น bytes ได้', () {
      final svc = MockSpaceService();
      final owner = fakeUser('owner-1', UserRole.owner);
      final list = <Space>[];
      final mockBytes = Uint8List.fromList([1, 2, 3, 4]);
      when(() => svc.requireUser(UserRole.owner)).thenReturn(owner);
      when(() => svc.nextId('SPACE')).thenReturn('SPACE-10');
      when(() => svc.spaces).thenReturn(list);
      when(() => svc.changed(any())).thenAnswer((_) {});

      final space = SpaceController.withService(svc).save(
        name: 'ห้องสตูดิโอพร้อมรูป',
        category: 'สตูดิโอ',
        location: 'สุขุมวิท',
        price: 1200,
        capacity: 10,
        description: 'ห้องถ่ายภาพสวย',
        amenities: ['ไฟสตูดิโอ'],
        imageBytes: mockBytes,
      );

      expect(space.id, 'SPACE-10');
      expect(space.hasImage, isTrue);
      expect(space.imageBytes, equals(mockBytes));
      expect(space.status, SpaceStatus.pending);
      expect(list.length, 1);
    });

    test('activateSpace: แอดมินเปิดประกาศที่ถูกระงับกลับมาได้', () {
      final svc = MockSpaceService();
      final space = fakeSpace('space-1', SpaceStatus.rejected);
      when(
        () => svc.requireUser(UserRole.admin),
      ).thenReturn(fakeUser('admin-1', UserRole.admin));
      when(() => svc.space('space-1')).thenReturn(space);
      when(() => svc.changed(any())).thenAnswer((_) {});

      SpaceController.withService(svc).activateSpace('space-1');

      expect(space.status, SpaceStatus.approved);
    });

    test('averageRating: เฉลี่ยจากรายการที่รีวิวแล้วเท่านั้น', () {
      final svc = MockSpaceService();
      final day = DateTime(2026, 11, 20);
      when(() => svc.bookings).thenReturn([
        fakeBooking(id: 'RS-1', date: day, status: BookingStatus.completed)
          ..review = SpaceReview(rating: 4, comment: 'ดี', createdAt: day),
        fakeBooking(id: 'RS-2', date: day, status: BookingStatus.completed)
          ..review = SpaceReview(rating: 2, comment: 'พอใช้', createdAt: day),
        fakeBooking(id: 'RS-3', date: day, status: BookingStatus.confirmed),
      ]);

      expect(SpaceController.withService(svc).averageRating('space-1'), 3.0);
    });

    test('sweep: สั่ง service ตรวจรายการหมดอายุ', () {
      final svc = MockBookingService();
      when(() => svc.sweepExpired()).thenAnswer((_) {});

      BookingController.withService(svc).sweep();

      verify(() => svc.sweepExpired()).called(1);
    });

    test('reviewedBookings: คืนเฉพาะรายการที่รีวิวแล้วของพื้นที่นั้น', () {
      final svc = MockSpaceService();
      final day = DateTime(2026, 11, 20);
      when(() => svc.bookings).thenReturn([
        fakeBooking(id: 'RS-1', date: day, status: BookingStatus.completed)
          ..review = SpaceReview(rating: 5, comment: 'ดีมาก', createdAt: day),
        fakeBooking(id: 'RS-2', date: day, status: BookingStatus.completed),
      ]);

      final result = SpaceController.withService(
        svc,
      ).reviewedBookings('space-1');

      expect(result.map((b) => b.id), ['RS-1']);
    });
  });
}
