import 'dart:async';
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

import '../fixtures/mock_controllers.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockTokenService extends Mock implements TokenService {}

class _ControllerTestStore extends AppStore {
  _ControllerTestStore({required super.clock, required super.api});

  @override
  Future<void> refresh() async {
    syncError = null;
    notifyListeners();
  }
}

({
  _ControllerTestStore store,
  _MockApiClient api,
  _MockTokenService tokens,
}) _createWiredStore({String viewerId = '1002', bool signedIn = true}) {
  final mockApi = _MockApiClient();
  final mockTokens = _MockTokenService();
  var activeToken = 'mock-jwt';

  when(() => mockApi.baseUrl).thenReturn('http://localhost:3001/api');
  when(
    () => mockApi.token,
  ).thenAnswer((_) => activeToken.isEmpty ? null : activeToken);
  when(() => mockApi.token = any()).thenAnswer((invocation) {
    activeToken = invocation.positionalArguments.first as String? ?? '';
    return activeToken.isEmpty ? null : activeToken;
  });

  when(() => mockTokens.saveToken(any())).thenAnswer((_) async {});
  when(() => mockTokens.loadToken()).thenAnswer((_) async => 'saved-jwt');
  when(() => mockTokens.deleteToken()).thenAnswer((_) async {});

  final seed = createMockStore(viewerId: viewerId, signedIn: signedIn);
  final store = _ControllerTestStore(clock: () => mockClockNow, api: mockApi);
  store.users.addAll(seed.users);
  store.spaces.addAll(seed.spaces);
  store.bookings.addAll(seed.bookings);
  store.issues.addAll(seed.issues);
  store.currentUser = seed.currentUser;

  return (store: store, api: mockApi, tokens: mockTokens);
}

final Uint8List _validJpegHeader = Uint8List.fromList([
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
]);

void main() {
  setUpAll(() {
    registerMockControllerFallbacks();
  });

  group('AuthController validation, session restore, and filtering', () {
    test('loginAsync, registerAsync, restoreSessionAsync, and logoutAsync flows', () async {
      final setup = _createWiredStore(signedIn: false);
      final auth = AuthController(setup.store, tokenService: setup.tokens);

      // Validation guards before API calls
      await expectLater(
        auth.loginAsync('  ', 'password'),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        auth.loginAsync('a@b.c', ''),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        auth.registerAsync(
          'แอดมิน',
          'newadmin@test.local',
          'password123',
          UserRole.admin,
          '081-111-2222',
        ),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        auth.registerAsync(
          'สั้นไป',
          'short@test.local',
          '1234567',
          UserRole.renter,
          '081-111-2222',
          '1234567',
        ),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        auth.registerAsync(
          'ว่างยืนยัน',
          'empty@test.local',
          '12345678',
          UserRole.renter,
          '081-111-2222',
          '',
        ),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        auth.registerAsync(
          'ไม่ตรง',
          'mismatch@test.local',
          '12345678',
          UserRole.renter,
          '081-111-2222',
          '87654321',
        ),
        throwsA(isA<DomainError>()),
      );
      verifyNever(() => setup.api.request(any(), any(), any()));

      // Successful login saves token & refreshes store
      when(
        () => setup.api.request('POST', '/auth/login', any()),
      ).thenAnswer((_) async => {'token': 'login-jwt'});
      await auth.loginAsync(' renter01@rentspace.test ', 'password');
      verify(() => setup.tokens.saveToken('login-jwt')).called(1);

      await expectLater(
        auth.registerAsync(
          'ผู้เช่า',
          'user@test.local',
          'password123',
          UserRole.renter,
          '081-111-2222',
          '',
        ),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        auth.registerAsync(
          'ผู้เช่า',
          'user@test.local',
          'password123',
          UserRole.renter,
          '081-111-2222',
          'mismatch123',
        ),
        throwsA(isA<DomainError>()),
      );

      // Successful register sends role name and saves token
      when(
        () => setup.api.request('POST', '/auth/register', any()),
      ).thenAnswer((_) async => {'token': 'reg-jwt'});
      await auth.registerAsync(
        'ผู้เช่าใหม่',
        'fresh@rentspace.test',
        'password123',
        UserRole.renter,
        '081-555-6666',
        'password123',
      );
      verify(
        () => setup.api.request('POST', '/auth/register', {
          'name': 'ผู้เช่าใหม่',
          'email': 'fresh@rentspace.test',
          'password': 'password123',
          'role': 'renter',
          'phone': '081-555-6666',
        }),
      ).called(1);
      verify(() => setup.tokens.saveToken('reg-jwt')).called(1);

      // Logout clears session even if backend /auth/logout throws
      when(
        () => setup.api.request('POST', '/auth/logout', any()),
      ).thenThrow(DomainError('offline'));
      await auth.logoutAsync();
      expect(setup.store.currentUser, isNull);
      verify(() => setup.tokens.deleteToken()).called(1);
    });

    test('restoreSessionAsync clears token on 401 and rethrows non-401 ApiError', () async {
      final setup = _createWiredStore(signedIn: false);
      final auth = AuthController(setup.store, tokenService: setup.tokens);

      // Null token -> returns null
      when(() => setup.tokens.loadToken()).thenAnswer((_) async => null);
      expect(await auth.restoreSessionAsync(), isNull);

      // Wait for real store refresh throwing 401 ApiError
      final realStore = AppStore(api: setup.api, clock: () => mockClockNow);
      final realAuth = AuthController(realStore, tokenService: setup.tokens);
      when(() => setup.tokens.loadToken()).thenAnswer((_) async => 'expired');
      when(
        () => setup.api.request('GET', '/state'),
      ).thenThrow(ApiError('หมดอายุ', 401));
      expect(await realAuth.restoreSessionAsync(), isNull);
      verify(() => setup.tokens.deleteToken()).called(1);

      // Non-401 error (500) rethrows instead of deleting saved token
      when(() => setup.tokens.loadToken()).thenAnswer((_) async => 'valid-but-500');
      when(
        () => setup.api.request('GET', '/state'),
      ).thenThrow(ApiError('เซิร์ฟเวอร์ขัดข้อง', 500));
      await expectLater(
        realAuth.restoreSessionAsync(),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 500)),
      );

      // Logout while loadToken is still pending invalidates stale restore
      final loadCompleter = Completer<String?>();
      when(() => setup.tokens.loadToken()).thenAnswer((_) => loadCompleter.future);
      when(
        () => setup.api.request('POST', '/auth/logout', any()),
      ).thenAnswer((_) async => {'ok': true});
      final pendingRestore = realAuth.restoreSessionAsync();
      await realAuth.logoutAsync();
      loadCompleter.complete('stale-token');
      expect(await pendingRestore, isNull);
      expect(realStore.currentUser, isNull);
    });

    test('validateProfile, updateProfileAsync, changePasswordAsync, toggleUserAsync, and filterUsers', () async {
      final setup = _createWiredStore(viewerId: '1002');
      final auth = AuthController(setup.store, tokenService: setup.tokens);

      expect(AuthController.validEmail('user@example.com'), isTrue);
      expect(AuthController.validEmail('bad-email'), isFalse);

      expect(
        () => auth.validateProfile('', 'ok@test.local', '081-234-5678'),
        throwsA(isA<DomainError>()),
      );
      expect(
        () => auth.validateProfile('ชื่อ', 'not-email', '081-234-5678'),
        throwsA(isA<DomainError>()),
      );
      expect(
        () => auth.validateProfile('ชื่อ', 'owner01@rentspace.test', '081-234-5678'),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'อีเมลนี้ถูกใช้งานแล้ว',
          ),
        ),
      );
      // Updating own email allowed when excluding own id
      auth.validateProfile(
        'ชื่อ',
        'renter01@rentspace.test',
        '081-234-5678',
        excluding: '1002',
      );
      expect(
        () => auth.validateProfile('ชื่อ', 'new@test.local', '123'),
        throwsA(isA<DomainError>()),
      );

      when(
        () => setup.api.request('PUT', '/auth/profile', any()),
      ).thenAnswer((_) async => {'ok': true});
      await auth.updateProfileAsync(
        'ณัฐ ปรับปรุง',
        'renter01@rentspace.test',
        '081-999-0000',
        'KBANK 999',
      );
      verify(
        () => setup.api.request('PUT', '/auth/profile', {
          'name': 'ณัฐ ปรับปรุง',
          'email': 'renter01@rentspace.test',
          'phone': '081-999-0000',
          'bankInfo': 'KBANK 999',
        }),
      ).called(1);

      await expectLater(
        auth.changePasswordAsync('', 'newpass12', 'newpass12'),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        auth.changePasswordAsync('oldpass', 'short', 'short'),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        auth.changePasswordAsync('oldpass', 'newpass12', 'different'),
        throwsA(isA<DomainError>()),
      );

      when(
        () => setup.api.request('PUT', '/auth/password', any()),
      ).thenAnswer((_) async => {'ok': true});
      await auth.changePasswordAsync('oldpass1', 'newpass12', 'newpass12');
      verify(
        () => setup.api.request('PUT', '/auth/password', {
          'currentPassword': 'oldpass1',
          'newPassword': 'newpass12',
          'confirmPassword': 'newpass12',
        }),
      ).called(1);

      when(
        () => setup.api.request('PUT', '/admin/users/1005/toggle', any()),
      ).thenAnswer((_) async => {'ok': true});
      await auth.toggleUserAsync('1005');
      verify(
        () => setup.api.request('PUT', '/admin/users/1005/toggle', any()),
      ).called(1);

      expect(auth.filterUsers().length, 5);
      expect(auth.filterUsers(role: UserRole.owner).length, 2);
      expect(
        auth.filterUsers(query: 'MINT', role: UserRole.renter).single.id,
        '1004',
      );
    });
  });

  group('BookingController calculations, slots, and mutations', () {
    test('rent, durationError, and validateDuration cover all bounds', () {
      expect(BookingController.durationError(600, 600), isNotNull);
      expect(BookingController.durationError(-1, 600), isNotNull);
      expect(BookingController.durationError(600, 1500), isNotNull);
      expect(BookingController.durationError(600, 630), contains('60 นาที'));
      expect(BookingController.durationError(480, 1260), contains('12 ชั่วโมง'));
      expect(BookingController.durationError(540, 660), isNull);

      expect(
        () => BookingController.validateDuration(540, 570),
        throwsA(isA<DomainError>()),
      );

      expect(BookingController.rent(350, 540, 660, days: 2), 1400);
      expect(BookingController.rent(350, 540, 630), 700);
      expect(
        () => BookingController.rent(0, 540, 660),
        throwsA(isA<DomainError>()),
      );
    });

    test('hourlySlots, isSlotAvailable, busySlotLabels, and selectOrExtendSlot', () {
      final setup = _createWiredStore();
      final controller = BookingController(setup.store);
      final targetSpace = setup.store.space('2001');
      final targetDate = mockClockNow.add(const Duration(days: 10));

      // Disable Sunday (weekday 7) and verify empty slots on Sunday
      final sunday = DateTime(2026, 11, 22);
      targetSpace.availability.days[6].open = false;
      expect(controller.hourlySlots(targetSpace, sunday), isEmpty);
      expect(controller.isSlotAvailable('2001', sunday, 600, 660), isFalse);

      // Open Monday slots (09:00-18:00 -> 9 one-hour slots)
      expect(controller.hourlySlots(targetSpace, targetDate).length, 9);
      expect(
        controller.isSlotAvailable('2001', targetDate, 600, 660),
        isTrue,
      );
      expect(
        controller.isSlotAvailable('2001', targetDate, 600, 660, days: 0),
        isFalse,
      );
      expect(
        controller.isSlotAvailable('2001', targetDate, 600, 660, days: 15),
        isFalse,
      );

      // Extend adjacent slot forward and backward, and reset on non-adjacent tap
      expect(
        controller.selectOrExtendSlot(
          spaceId: '2001',
          date: targetDate,
          currentStart: 600,
          currentEnd: 660,
          slotStart: 660,
          slotEnd: 720,
        ),
        (600, 720),
      );
      expect(
        controller.selectOrExtendSlot(
          spaceId: '2001',
          date: targetDate,
          currentStart: 600,
          currentEnd: 720,
          slotStart: 540,
          slotEnd: 600,
        ),
        (540, 720),
      );
      expect(
        controller.selectOrExtendSlot(
          spaceId: '2001',
          date: targetDate,
          currentStart: 540,
          currentEnd: 720,
          slotStart: 840,
          slotEnd: 900,
        ),
        (840, 900),
      );

      // Busy slots & blocked periods sorted and labeled
      setup.store.busySlots.add({
        'space_id': '2001',
        'booking_date': '2026-11-26',
        'start_minutes': 720,
        'end_minutes': 840,
        'days_count': 2,
      });
      targetSpace.availability.blocks.add(
        BlockedPeriod(
          id: 'BLK-L',
          start: DateTime(2026, 11, 26, 15, 0),
          end: DateTime(2026, 11, 26, 17, 0),
          reason: 'ทำความสะอาด',
        ),
      );
      expect(controller.busySlotLabels('2001', targetDate), [
        'คิวจอง 12:00–14:00 (2 วัน)',
        'ปิดพื้นที่ (ทำความสะอาด)',
      ]);
    });

    test('createAsync validation guards and booking lifecycle mutations', () async {
      final setup = _createWiredStore();
      final controller = BookingController(setup.store);
      final futureDate = mockClockNow.add(const Duration(days: 12));

      await expectLater(
        controller.createAsync('2001', futureDate, 600, 660, days: 15),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        controller.createAsync('2001', futureDate, 600, 660, attendees: 99),
        throwsA(isA<DomainError>()),
      );
      // Pending space rejected
      await expectLater(
        controller.createAsync('2005', futureDate, 600, 660),
        throwsA(isA<DomainError>()),
      );
      // Past slot rejected
      await expectLater(
        controller.createAsync(
          '2001',
          mockClockNow.subtract(const Duration(days: 1)),
          600,
          660,
        ),
        throwsA(isA<DomainError>()),
      );
      // Outside open hours rejected
      await expectLater(
        controller.createAsync('2001', futureDate, 420, 480),
        throwsA(isA<DomainError>()),
      );
      // Conflicting date with 3003 (mockClockNow + 5 days, 09:00-11:00) rejected
      await expectLater(
        controller.createAsync(
          '2001',
          mockClockNow.add(const Duration(days: 5)),
          540,
          600,
        ),
        throwsA(isA<DomainError>()),
      );

      when(
        () => setup.api.request('POST', '/bookings', any()),
      ).thenAnswer((_) async => {'id': '3003'});
      final returnedBooking = await controller.createAsync(
        '2001',
        futureDate,
        600,
        720,
        attendees: 3,
        zone: '',
        renterNote: '  ขอโปรเจกเตอร์  ',
      );
      expect(returnedBooking.id, '3003');
      verify(
        () => setup.api.request('POST', '/bookings', {
          'spaceId': '2001',
          'date': '2026-11-28',
          'startMinutes': 600,
          'endMinutes': 720,
          'days': 1,
          'attendees': 3,
          'zone': 'โซนหลัก (พื้นที่มาตรฐาน)',
          'renterNote': 'ขอโปรเจกเตอร์',
        }),
      ).called(1);

      // Owner review, cancel, complete, submitReview
      await expectLater(
        controller.ownerReviewAsync('3003', false, '   '),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        controller.cancelAsync('3003', ''),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        controller.submitReviewAsync('3006', 0, 'ดี'),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        controller.submitReviewAsync('3006', 5, '   '),
        throwsA(isA<DomainError>()),
      );

      when(
        () => setup.api.request('POST', any(), any()),
      ).thenAnswer((_) async => {'ok': true});
      await controller.ownerReviewAsync('3003', true, '');
      await controller.ownerReviewAsync('3003', false, 'ติดภารกิจ');
      await controller.cancelAsync('3003', 'เปลี่ยนแผน');
      await controller.completeAsync('3001');
      await controller.submitReviewAsync('3006', 5, 'ประทับใจ');

      verify(
        () => setup.api.request('POST', '/bookings/3003/approve', {'reason': ''}),
      ).called(1);
      verify(
        () => setup.api.request('POST', '/bookings/3003/reject', {
          'reason': 'ติดภารกิจ',
        }),
      ).called(1);
      verify(
        () => setup.api.request('POST', '/bookings/3003/cancel', {
          'reason': 'เปลี่ยนแผน',
        }),
      ).called(1);
      verify(
        () => setup.api.request('POST', '/bookings/3001/complete', any()),
      ).called(1);
      verify(
        () => setup.api.request('POST', '/bookings/3006/review', {
          'rating': 5,
          'comment': 'ประทับใจ',
        }),
      ).called(1);
    });
  });

  group('SpaceController filtering, ratings, validation, and mutations', () {
    test('filterSpaces, reviewsFor, reviewCountFor, and averageRating', () {
      final setup = _createWiredStore();
      // Add another approved space with active owner (1001) and one with inactive owner (1005)
      setup.store.spaces.addAll([
        Space(
          id: '2010',
          ownerId: '1001',
          name: 'สตูดิโอแสงธรรมชาติ',
          category: 'studio',
          location: 'สุขุมวิท',
          price: 900,
          capacity: 15,
          description: 'สตูดิโอถ่ายภาพ',
          amenities: ['ไฟสตูดิโอ', 'ที่จอดรถ'],
          status: SpaceStatus.approved,
        ),
        Space(
          id: '2011',
          ownerId: '1005',
          name: 'ห้องเจ้าของถูกระงับ',
          category: 'meeting_room',
          location: 'กรุงเทพฯ',
          price: 100,
          capacity: 50,
          description: 'ต้องไม่แสดงในรายการ',
          status: SpaceStatus.approved,
        ),
      ]);
      setup.store.user('1002').favorites.add('2002');
      setup.store.publicReviews['2001'] = [
        SpaceReview(rating: 5, comment: 'เยี่ยม', createdAt: mockClockNow),
        SpaceReview(rating: 3, comment: 'พอใช้', createdAt: mockClockNow),
      ];

      final controller = SpaceController(setup.store);

      // Approved active-owner spaces = 2001 (350), 2002 (120), 2010 (900)
      final recommended = controller.filterSpaces();
      expect(recommended.map((s) => s.id).toList(), ['2001', '2002', '2010']);

      expect(
        controller
            .filterSpaces(sort: SpaceSort.priceAsc)
            .map((s) => s.id)
            .toList(),
        ['2002', '2001', '2010'],
      );
      expect(
        controller
            .filterSpaces(sort: SpaceSort.priceDesc)
            .map((s) => s.id)
            .toList(),
        ['2010', '2001', '2002'],
      );
      expect(
        controller
            .filterSpaces(sort: SpaceSort.capacityDesc)
            .map((s) => s.id)
            .toList(),
        ['2010', '2001', '2002'],
      );
      expect(
        controller.filterSpaces(favoritesOnly: true).map((s) => s.id).toList(),
        ['2002'],
      );
      expect(
        controller
            .filterSpaces(
              category: 'studio',
              query: 'ที่จอดรถ',
              maxPrice: 900,
              minCapacity: 15,
            )
            .single
            .id,
        '2010',
      );

      // Reviews & ratings fallback vs publicReviews
      expect(controller.reviewsFor('2001').length, 2);
      expect(controller.reviewCountFor('2001'), 2);
      expect(controller.averageRating('2001'), 4.0);
      expect(controller.reviewCountFor('2002'), 3);
      expect(controller.averageRating('2002'), 4.9);
      expect(controller.averageRating('2010'), isNull);
    });

    test('saveAsync, saveAvailabilityAsync, moderation, favorites, and issues', () async {
      final setup = _createWiredStore();
      final controller = SpaceController(setup.store);

      await expectLater(
        controller.saveAsync(
          name: '',
          category: 'meeting_room',
          location: 'กทม',
          price: 300,
          capacity: 5,
          description: 'desc',
          amenities: [],
        ),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        controller.saveAsync(
          name: 'ห้อง',
          category: 'meeting_room',
          location: 'กทม',
          price: 300,
          capacity: 5,
          description: 'desc',
          amenities: [],
          imageBytes: corruptMockImageBytes,
        ),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        controller.saveAsync(
          name: 'ห้อง',
          category: 'meeting_room',
          location: 'กทม',
          price: 300,
          capacity: 5,
          description: 'desc',
          amenities: [],
          image: 'http://evil.example.com/a.png',
        ),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'message',
            'ลิงก์ภาพต้องขึ้นต้นด้วย https://',
          ),
        ),
      );

      when(
        () => setup.api.request('POST', '/spaces', any()),
      ).thenAnswer((_) async => {'id': '2001'});
      await controller.saveAsync(
        name: 'ห้องใหม่',
        category: 'meeting_room',
        location: 'อารีย์',
        price: 500,
        capacity: 8,
        description: 'ห้องประชุม',
        amenities: ['Wi-Fi', '  '],
        imageBytes: validMockPngBytes,
      );
      verify(
        () => setup.api.request(
          'POST',
          '/spaces',
          any(
            that: isA<Map<String, dynamic>>().having(
              (m) => '${m['image']}',
              'image',
              startsWith('data:image/png;base64,'),
            ),
          ),
        ),
      ).called(1);

      // Edit existing space uses PUT and accepts relative /api/spaces/ path
      when(
        () => setup.api.request('PUT', '/spaces/2001', any()),
      ).thenAnswer((_) async => {'id': '2001'});
      final edited = await controller.saveAsync(
        id: '2001',
        name: 'ห้องปรับปรุง',
        category: 'meeting_room',
        location: 'อารีย์',
        price: 550,
        capacity: 10,
        description: 'รายละเอียด',
        amenities: ['Wi-Fi'],
        image: '/api/spaces/2001/image',
      );
      expect(edited.id, '2001');

      // Availability validation: invalid day hours, invalid block reason, booking overlap
      final badHours = Availability()..days[0].end = 400;
      await expectLater(
        controller.saveAvailabilityAsync('2001', badHours),
        throwsA(isA<DomainError>()),
      );

      final badBlock = Availability(
        blocks: [
          BlockedPeriod(
            id: 'b1',
            start: mockClockNow.add(const Duration(days: 20)),
            end: mockClockNow.add(const Duration(days: 21)),
            reason: '   ',
          ),
        ],
      );
      await expectLater(
        controller.saveAvailabilityAsync('2001', badBlock),
        throwsA(isA<DomainError>()),
      );

      // Adding a block overlapping future held booking 3003 fails
      final overlappingBlock = Availability(
        blocks: [
          BlockedPeriod(
            id: 'b2',
            start: mockClockNow.add(const Duration(days: 5)),
            end: mockClockNow.add(const Duration(days: 5, hours: 23)),
            reason: 'ปิดซ่อม',
          ),
        ],
      );
      await expectLater(
        controller.saveAvailabilityAsync('2001', overlappingBlock),
        throwsA(isA<DomainError>()),
      );

      when(
        () => setup.api.request('PUT', '/spaces/2001/availability', any()),
      ).thenAnswer((_) async => {'ok': true});
      await controller.saveAvailabilityAsync('2001', Availability());

      // Moderation, favorites, report, closeIssue
      await expectLater(
        controller.reviewAsync('2005', false, ''),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        controller.suspendSpaceAsync('2001', '  '),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        controller.reportAsync('หัวข้อ', '  '),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        controller.closeIssueAsync('iss_open_1', ''),
        throwsA(isA<DomainError>()),
      );

      when(
        () => setup.api.request(any(), any(), any()),
      ).thenAnswer((_) async => {'ok': true});
      await controller.reviewAsync('2005', true, '');
      await controller.suspendSpaceAsync('2001', 'ข้อมูลไม่ครบ');
      await controller.activateSpaceAsync('2098');
      await controller.favoriteAsync('2001');
      await controller.reportAsync('ความสะอาด', 'พบขยะในห้อง');
      await controller.closeIssueAsync('iss_open_1', 'ส่งแม่บ้านทำความสะอาดแล้ว');

      verify(
        () => setup.api.request('PUT', '/admin/spaces/2005/approve', {'reason': ''}),
      ).called(1);
      verify(
        () => setup.api.request('PUT', '/admin/spaces/2001/reject', {
          'reason': 'ข้อมูลไม่ครบ',
        }),
      ).called(1);
      verify(
        () => setup.api.request('PUT', '/admin/spaces/2098/activate', any()),
      ).called(1);
      verify(
        () => setup.api.request('POST', '/spaces/2001/favorite', any()),
      ).called(1);
      verify(
        () => setup.api.request('POST', '/admin/issues', {
          'subject': 'ความสะอาด',
          'detail': 'พบขยะในห้อง',
        }),
      ).called(1);
      verify(
        () => setup.api.request('PUT', '/admin/issues/iss_open_1/close', {
          'resolution': 'ส่งแม่บ้านทำความสะอาดแล้ว',
        }),
      ).called(1);
    });
  });

  group('PaymentController slip validation and payout logic', () {
    test('validateSlip enforces non-empty, <= 5 MB, extension, and magic bytes', () {
      expect(
        () => PaymentController.validateSlip('empty.png', Uint8List(0)),
        throwsA(isA<DomainError>()),
      );
      expect(
        () => PaymentController.validateSlip(
          'huge.png',
          Uint8List(PaymentController.maxBytes + 1),
        ),
        throwsA(isA<DomainError>()),
      );
      expect(
        () => PaymentController.validateSlip('fake.png', _validJpegHeader),
        throwsA(isA<DomainError>()),
      );
      expect(
        () => PaymentController.validateSlip('slip.gif', validMockPngBytes),
        throwsA(isA<DomainError>()),
      );
      expect(
        () => PaymentController.validateSlip(
          'short.png',
          Uint8List.fromList([0x89, 0x50, 0x4E]),
        ),
        throwsA(isA<DomainError>()),
      );
      expect(
        () => PaymentController.validateSlip(
          'short.jpg',
          Uint8List.fromList([0xFF, 0xD8]),
        ),
        throwsA(isA<DomainError>()),
      );

      PaymentController.validateSlip('ok.PNG', validMockPngBytes);
      PaymentController.validateSlip('ok.jpg', _validJpegHeader);
      PaymentController.validateSlip('ok.jpeg', _validJpegHeader);
    });

    test('submitAsync, reviewAsync, and payoutAsync hit expected API methods', () async {
      final setup = _createWiredStore();
      final controller = PaymentController(setup.store);

      when(
        () => setup.api.upload(any(), any(), any(), any()),
      ).thenAnswer((_) async => {'ok': true});
      when(
        () => setup.api.request(any(), any(), any()),
      ).thenAnswer((_) async => {'ok': true});

      await controller.submitAsync('3004', 'slip.png', validMockPngBytes, '  โอนแล้ว  ');
      verify(
        () => setup.api.upload(
          '/payments/3004/slip',
          'slip.png',
          validMockPngBytes,
          'โอนแล้ว',
        ),
      ).called(1);

      await expectLater(
        controller.reviewAsync('3005', false, '   '),
        throwsA(isA<DomainError>()),
      );
      await controller.reviewAsync('3005', true, '');
      verify(
        () => setup.api.request('POST', '/payments/3005/review', {
          'approve': true,
          'reason': '',
        }),
      ).called(1);

      // Payout with slip upload vs note-only vs no note
      await controller.payoutAsync(
        '3006',
        fileName: 'payout.png',
        bytes: validMockPngBytes,
        note: '  REF-88  ',
      );
      verify(
        () => setup.api.upload(
          '/payments/3006/payout',
          'payout.png',
          validMockPngBytes,
          'REF-88',
        ),
      ).called(1);

      await controller.payoutAsync('3006', note: '  จ่ายแล้ว  ');
      verify(
        () => setup.api.request('POST', '/payments/3006/payout', {'note': 'จ่ายแล้ว'}),
      ).called(1);

      await controller.payoutAsync('3006');
      verify(
        () => setup.api.request('POST', '/payments/3006/payout', null),
      ).called(1);
    });
  });
}
