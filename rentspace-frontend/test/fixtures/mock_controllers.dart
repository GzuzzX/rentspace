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

import '../xampp_db_fixture.dart';

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

TestStore createSeededMockStore(
  Map<String, dynamic> xamppSnapshot, {
  String viewerId = '1002',
  bool signedIn = true,
}) {
  final store = TestStore(clock: () => mockClockNow);
  populateStoreFromXamppSnapshot(store, xamppSnapshot, viewerId: viewerId);
  if (!signedIn) {
    store.currentUser = null;
  }
  return store;
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
