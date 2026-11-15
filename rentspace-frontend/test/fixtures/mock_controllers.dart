import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/controllers/auth_controller.dart';
import 'package:rentspace/controllers/booking_controller.dart';
import 'package:rentspace/controllers/payment_controller.dart';
import 'package:rentspace/controllers/space_controller.dart';
import 'package:rentspace/data/app_store.dart';
import 'package:rentspace/models/domain.dart';

class MockAuthController extends Mock implements AuthController {}

class MockSpaceController extends Mock implements SpaceController {}

class MockBookingController extends Mock implements BookingController {}

class MockPaymentController extends Mock implements PaymentController {}

class TestStore extends AppStore {
  TestStore({super.clock});

  bool failNextRefresh = false;
  int refreshCalls = 0;

  void notify() => notifyListeners();

  @override
  Future<void> refresh() async {
    refreshCalls++;
    if (failNextRefresh) {
      failNextRefresh = false;
      throw DomainError('เชื่อมต่อข้อมูลไม่สำเร็จ');
    }
    syncError = null;
    notifyListeners();
  }
}

final DateTime mockClockNow = DateTime(2026, 11, 16, 12, 0);

final Uint8List validMockPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

final Uint8List corruptMockImageBytes = Uint8List.fromList([1, 2, 3, 4]);

String? lastMockClipboard;

Future<void> setupTestChannels() async {
  lastMockClipboard = null;
  FlutterSecureStorage.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<dynamic, dynamic>?;
          lastMockClipboard = args?['text'] as String?;
        }
        return null;
      });
}

void configureMobileViewport(
  WidgetTester tester, {
  Size size = const Size(430, 932),
  FakeViewPadding viewInsets = FakeViewPadding.zero,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = viewInsets;
}

void resetMobileViewport(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.view.resetViewInsets();
}

Finder fieldByLabel(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      (widget.decoration?.labelText == label ||
          widget.decoration?.hintText == label),
);

Future<void> scrollToAndTap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollableFinder = find.byType(Scrollable);
    if (scrollableFinder.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(
        finder,
        260,
        scrollable: scrollableFinder.first,
      );
    }
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder, findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> scrollToAndEnter(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  if (finder.evaluate().isEmpty) {
    final scrollableFinder = find.byType(Scrollable);
    if (scrollableFinder.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(
        finder,
        260,
        scrollable: scrollableFinder.first,
      );
    }
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

Future<void> submitReasonDialog(WidgetTester tester, String reasonText) async {
  await scrollToAndEnter(
    tester,
    fieldByLabel('เหตุผล / รายละเอียด'),
    reasonText,
  );
  await scrollToAndTap(tester, find.widgetWithText(FilledButton, 'ยืนยัน'));
}

Future<void> dismissSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

List<AppUser> _buildMockUsers() => [
  AppUser(
    id: '1001',
    name: 'ภูมิ ศรีสุข (Owner)',
    email: 'owner01@rentspace.test',
    password: 'password',
    role: UserRole.owner,
    phone: '089-876-5432',
    bankInfo: '',
    active: true,
  ),
  AppUser(
    id: '1002',
    name: 'ณัฐ วงศ์ดี (Renter)',
    email: 'renter01@rentspace.test',
    password: 'password',
    role: UserRole.renter,
    phone: '081-234-5678',
    bankInfo: 'SCB 123-456-7890',
    active: true,
  ),
  AppUser(
    id: '1003',
    name: 'ผู้ดูแลระบบ (Admin)',
    email: 'admin01@rentspace.test',
    password: 'password',
    role: UserRole.admin,
    phone: '02-999-8888',
    bankInfo: '',
    active: true,
  ),
  AppUser(
    id: '1004',
    name: 'มินท์ กมลวรรณ',
    email: 'mint@rentspace.test',
    password: 'password',
    role: UserRole.renter,
    phone: '082-333-4444',
    bankInfo: '',
    active: true,
  ),
  AppUser(
    id: '1005',
    name: 'แพรว ใจงาม',
    email: 'owner02@rentspace.test',
    password: 'password',
    role: UserRole.owner,
    phone: '086-555-7777',
    bankInfo: '',
    active: false,
  ),
];

List<Space> _buildMockSpaces() => [
  Space(
    id: '2001',
    ownerId: '1001',
    name: 'ห้องประชุมสว่างใจ',
    category: 'meeting_room',
    location: '88 ซ.อารีย์ 4 พญาไท กรุงเทพฯ',
    price: 350,
    capacity: 10,
    description: 'ห้องประชุมพร้อมจอสมาร์ททีวีและอินเทอร์เน็ตความเร็วสูง',
    imageBytes: validMockPngBytes,
    amenities: ['Wi-Fi'],
    status: SpaceStatus.approved,
    dbRating: 4.8,
    dbReviewCount: 2,
  ),
  Space(
    id: '2002',
    ownerId: '1001',
    name: 'The Quiet Nook (ห้องอ่านหนังสือ)',
    category: 'study_room',
    location: '12 ถ.พระราม 4 ปทุมวัน กรุงเทพฯ',
    price: 120,
    capacity: 4,
    description: 'ห้องอ่านหนังสือเงียบสงบ แสงธรรมชาติ เหมาะสำหรับอ่านหนังสือหรือติวสอบ',
    amenities: ['Wi-Fi', 'เครื่องปรับอากาศ'],
    status: SpaceStatus.approved,
    dbRating: 4.9,
    dbReviewCount: 3,
  ),
  Space(
    id: '2005',
    ownerId: '1001',
    name: 'พื้นที่จัดเวิร์กช็อป',
    category: 'event_space',
    location: 'เชียงใหม่ นิมมานเหมินท์',
    price: 3200,
    capacity: 30,
    description: 'พื้นที่อเนกประสงค์สำหรับกิจกรรมกลุ่ม เวิร์กช็อป และสัมมนา',
    amenities: ['Wi-Fi', 'เครื่องปรับอากาศ'],
    status: SpaceStatus.pending,
    dbRating: 4.5,
    dbReviewCount: 1,
  ),
  Space(
    id: '2098',
    ownerId: '1001',
    name: 'พื้นที่ปรับปรุงภาพถ่าย',
    category: 'meeting_room',
    location: 'พญาไท กรุงเทพฯ',
    price: 350,
    capacity: 10,
    description: 'รออัปเดตภาพ',
    amenities: ['Wi-Fi'],
    status: SpaceStatus.rejected,
  )..reviewReason = 'ภาพไม่ชัด',
];

List<Booking> _buildMockBookings() => [
  Booking(
    id: '3001',
    spaceId: '2001',
    ownerId: '1001',
    renterId: '1002',
    spaceName: 'ห้องประชุมสว่างใจ',
    date: mockClockNow.subtract(const Duration(days: 1)),
    startMinutes: 540,
    endMinutes: 660,
    rentAmount: 700,
    status: BookingStatus.confirmed,
  )
    ..createdAt = mockClockNow.subtract(const Duration(days: 3))
    ..confirmedAt = mockClockNow.subtract(const Duration(days: 2)),
  Booking(
    id: '3002',
    spaceId: '2002',
    ownerId: '1001',
    renterId: '1002',
    spaceName: 'The Quiet Nook (ห้องอ่านหนังสือ)',
    date: mockClockNow.add(const Duration(days: 4)),
    startMinutes: 540,
    endMinutes: 660,
    rentAmount: 240,
    status: BookingStatus.confirmed,
  )
    ..createdAt = mockClockNow.subtract(const Duration(days: 1))
    ..confirmedAt = mockClockNow,
  Booking(
    id: '3003',
    spaceId: '2001',
    ownerId: '1001',
    renterId: '1002',
    spaceName: 'ห้องประชุมสว่างใจ',
    date: mockClockNow.add(const Duration(days: 5)),
    startMinutes: 540,
    endMinutes: 660,
    rentAmount: 700,
    status: BookingStatus.ownerReview,
  )..createdAt = mockClockNow,
  Booking(
    id: '3004',
    spaceId: '2001',
    ownerId: '1001',
    renterId: '1002',
    spaceName: 'ห้องประชุมสว่างใจ',
    date: mockClockNow.add(const Duration(days: 6)),
    startMinutes: 540,
    endMinutes: 660,
    rentAmount: 700,
    status: BookingStatus.paymentDue,
  )
    ..createdAt = mockClockNow.subtract(const Duration(hours: 2))
    ..approvedAt = mockClockNow,
  Booking(
    id: '3005',
    spaceId: '2001',
    ownerId: '1001',
    renterId: '1002',
    spaceName: 'ห้องประชุมสว่างใจ',
    date: mockClockNow.add(const Duration(days: 7)),
    startMinutes: 540,
    endMinutes: 660,
    rentAmount: 700,
    status: BookingStatus.slipReview,
  )
    ..createdAt = mockClockNow.subtract(const Duration(hours: 3))
    ..approvedAt = mockClockNow.subtract(const Duration(hours: 2))
    ..slips.add(
      PaymentSlip(
        name: 'quick_slip.png',
        bytes: validMockPngBytes,
        submittedAt: mockClockNow,
      ),
    ),
  Booking(
    id: '3006',
    spaceId: '2002',
    ownerId: '1001',
    renterId: '1002',
    spaceName: 'The Quiet Nook (ห้องอ่านหนังสือ)',
    date: mockClockNow.subtract(const Duration(days: 4)),
    startMinutes: 540,
    endMinutes: 660,
    rentAmount: 240,
    status: BookingStatus.completed,
  )
    ..createdAt = mockClockNow.subtract(const Duration(days: 6))
    ..completedAt = mockClockNow.subtract(const Duration(days: 3)),
  Booking(
    id: '3007',
    spaceId: '2001',
    ownerId: '1001',
    renterId: '1004',
    spaceName: 'ห้องประชุมสว่างใจ',
    date: mockClockNow.add(const Duration(days: 8)),
    startMinutes: 540,
    endMinutes: 660,
    rentAmount: 700,
    status: BookingStatus.canceled,
  )
    ..createdAt = mockClockNow.subtract(const Duration(days: 2))
    ..reason = 'ผู้เช่ายกเลิกเอง',
  Booking(
    id: '3020',
    spaceId: '2001',
    ownerId: '1001',
    renterId: '1002',
    spaceName: 'ห้องประชุมสว่างใจ',
    date: mockClockNow.add(const Duration(days: 9)),
    startMinutes: 540,
    endMinutes: 660,
    rentAmount: 700,
    status: BookingStatus.ownerRejected,
  )
    ..createdAt = mockClockNow.subtract(const Duration(days: 2))
    ..reason = 'ช่วงเวลาไม่สะดวก',
];

void populateMockStore(
  TestStore store, {
  String viewerId = '1002',
  bool signedIn = true,
}) {
  store.users
    ..clear()
    ..addAll(_buildMockUsers());
  store.spaces
    ..clear()
    ..addAll(_buildMockSpaces());
  store.bookings
    ..clear()
    ..addAll(_buildMockBookings());
  store.issues
    ..clear()
    ..add(
      Issue(
        id: 'iss_open_1',
        reporterId: '1002',
        subject: 'แอร์ไม่เย็น',
        detail: 'ห้องประชุมชั้น 2 แอร์ไม่เย็น',
      ),
    );
  store.logs.clear();
  store.busySlots.clear();
  store.publicReviews.clear();
  store.syncError = null;
  store.currentUser = signedIn ? store.user(viewerId) : null;
}

TestStore createMockStore({
  String viewerId = '1002',
  bool signedIn = true,
}) {
  final store = TestStore(clock: () => mockClockNow);
  populateMockStore(store, viewerId: viewerId, signedIn: signedIn);
  return store;
}

Booking findBookingByStatus(
  AppStore store, {
  required BookingStatus status,
  String? preferredId,
  String? spaceId,
  String? renterId,
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
  throw StateError('Missing mock booking for $status');
}

class ControllerBundle {
  ControllerBundle(this.store)
    : auth = MockAuthController(),
      space = MockSpaceController(),
      booking = MockBookingController(),
      payment = MockPaymentController() {
    _stubAuthDefaults(AuthController(store));
    _stubSpaceDefaults(SpaceController(store));
    _stubBookingDefaults(BookingController(store));
  }

  final TestStore store;
  final MockAuthController auth;
  final MockSpaceController space;
  final MockBookingController booking;
  final MockPaymentController payment;

  void _stubAuthDefaults(AuthController realAuth) {
    when(() => auth.restoreSessionAsync()).thenAnswer((_) async => null);
    when(() => auth.logoutAsync()).thenAnswer((_) async {
      store.clearSession();
    });
    when(
      () => auth.filterUsers(
        query: any(named: 'query'),
        role: any(named: 'role'),
      ),
    ).thenAnswer(
      (inv) => realAuth.filterUsers(
        query: inv.namedArguments[#query] as String? ?? '',
        role: inv.namedArguments[#role] as UserRole?,
      ),
    );
  }

  void _stubSpaceDefaults(SpaceController realSpace) {
    when(
      () => space.filterSpaces(
        favoritesOnly: any(named: 'favoritesOnly'),
        category: any(named: 'category'),
        query: any(named: 'query'),
        sort: any(named: 'sort'),
        maxPrice: any(named: 'maxPrice'),
        minCapacity: any(named: 'minCapacity'),
      ),
    ).thenAnswer(
      (inv) => realSpace.filterSpaces(
        favoritesOnly: inv.namedArguments[#favoritesOnly] as bool? ?? false,
        category: inv.namedArguments[#category] as String? ?? 'ทั้งหมด',
        query: inv.namedArguments[#query] as String? ?? '',
        sort: inv.namedArguments[#sort] as SpaceSort? ?? SpaceSort.recommended,
        maxPrice: inv.namedArguments[#maxPrice] as int?,
        minCapacity: inv.namedArguments[#minCapacity] as int?,
      ),
    );
    when(() => space.averageRating(any())).thenAnswer(
      (inv) => realSpace.averageRating(inv.positionalArguments[0] as String),
    );
    when(() => space.reviewCountFor(any())).thenAnswer(
      (inv) => realSpace.reviewCountFor(inv.positionalArguments[0] as String),
    );
    when(() => space.reviewsFor(any())).thenAnswer(
      (inv) => realSpace.reviewsFor(inv.positionalArguments[0] as String),
    );
  }

  void _stubBookingDefaults(BookingController realBooking) {
    when(() => booking.busySlotLabels(any(), any())).thenAnswer(
      (inv) => realBooking.busySlotLabels(
        inv.positionalArguments[0] as String,
        inv.positionalArguments[1] as DateTime,
      ),
    );
    when(() => booking.hourlySlots(any(), any())).thenAnswer(
      (inv) => realBooking.hourlySlots(
        inv.positionalArguments[0] as Space,
        inv.positionalArguments[1] as DateTime,
      ),
    );
    when(
      () => booking.isSlotAvailable(
        any(),
        any(),
        any(),
        any(),
        days: any(named: 'days'),
      ),
    ).thenAnswer(
      (inv) => realBooking.isSlotAvailable(
        inv.positionalArguments[0] as String,
        inv.positionalArguments[1] as DateTime,
        inv.positionalArguments[2] as int,
        inv.positionalArguments[3] as int,
        days: inv.namedArguments[#days] as int? ?? 1,
      ),
    );
    when(
      () => booking.selectOrExtendSlot(
        spaceId: any(named: 'spaceId'),
        date: any(named: 'date'),
        currentStart: any(named: 'currentStart'),
        currentEnd: any(named: 'currentEnd'),
        slotStart: any(named: 'slotStart'),
        slotEnd: any(named: 'slotEnd'),
        days: any(named: 'days'),
      ),
    ).thenAnswer(
      (inv) => realBooking.selectOrExtendSlot(
        spaceId: inv.namedArguments[#spaceId] as String,
        date: inv.namedArguments[#date] as DateTime,
        currentStart: inv.namedArguments[#currentStart] as int,
        currentEnd: inv.namedArguments[#currentEnd] as int,
        slotStart: inv.namedArguments[#slotStart] as int,
        slotEnd: inv.namedArguments[#slotEnd] as int,
        days: inv.namedArguments[#days] as int? ?? 1,
      ),
    );
  }
}

void registerMockControllerFallbacks() {
  registerFallbackValue(SpaceSort.recommended);
  registerFallbackValue(UserRole.renter);
  registerFallbackValue(DateTime(2026, 6, 15));
  registerFallbackValue(Uint8List(0));
  registerFallbackValue(Availability());
  registerFallbackValue(
    Space(
      id: 'fallback',
      ownerId: '1002',
      name: 'fallback',
      category: 'ห้องประชุม',
      location: 'กรุงเทพ',
      price: 100,
      capacity: 1,
      description: 'fallback',
    ),
  );
}
