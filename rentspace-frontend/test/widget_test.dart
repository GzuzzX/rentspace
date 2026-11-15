import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/controllers/auth_controller.dart';
import 'package:rentspace/controllers/booking_controller.dart';
import 'package:rentspace/controllers/payment_controller.dart';
import 'package:rentspace/controllers/space_controller.dart';
import 'package:rentspace/data/app_store.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/services/api_client.dart';
import 'package:rentspace/ui/booking_pages.dart';
import 'package:rentspace/ui/common.dart';
import 'package:rentspace/ui/home_page.dart';
import 'package:rentspace/ui/login_page.dart';
import 'package:rentspace/ui/space_form.dart';

import 'xampp_db_fixture.dart';

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

final _clockNow = DateTime(2026, 11, 16, 12, 0);

final _validPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

final _corruptImageBytes = Uint8List.fromList([1, 2, 3, 4]);

late Map<String, dynamic> _xamppSnapshot;

TestStore _createSeededStore({
  String viewerId = '1002',
  bool signedIn = true,
}) {
  final store = TestStore(clock: () => _clockNow);
  populateStoreFromXamppSnapshot(store, _xamppSnapshot, viewerId: viewerId);
  if (!signedIn) {
    store.currentUser = null;
  }
  return store;
}

class _ControllerBundle {
  _ControllerBundle(this.store)
    : auth = MockAuthController(),
      space = MockSpaceController(),
      booking = MockBookingController(),
      payment = MockPaymentController() {
    _stubDefaults();
  }

  final TestStore store;
  final MockAuthController auth;
  final MockSpaceController space;
  final MockBookingController booking;
  final MockPaymentController payment;

  void _stubDefaults() {
    final realSpace = SpaceController(store);
    final realBooking = BookingController(store);
    final realAuth = AuthController(store);

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

void _registerFallbacks() {
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

Future<void> _setPhoneViewport(
  WidgetTester tester, {
  Size size = const Size(430, 932),
  FakeViewPadding viewInsets = FakeViewPadding.zero,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = viewInsets;
}

void _resetViewport(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.view.resetViewInsets();
}

Finder _textFieldByLabel(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      (widget.decoration?.labelText == label ||
          widget.decoration?.hintText == label),
);

Future<void> _tapWidget(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enterText(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

Future<void> _dismissSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> _unmountTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    _registerFallbacks();
    _xamppSnapshot = await loadXamppSnapshot();
  });

  testWidgets(
    '1. At first, session restore shows CircularProgressIndicator then LoginPage',
    (WidgetTester tester) async {
      await _setPhoneViewport(tester);
      addTearDown(() => _resetViewport(tester));

      final store = _createSeededStore(signedIn: false);
      final mocks = _ControllerBundle(store);
      final restoreCompleter = Completer<AppUser?>();
      when(
        () => mocks.auth.restoreSessionAsync(),
      ).thenAnswer((_) => restoreCompleter.future);

      await tester.pumpWidget(
        RentSpaceApp(
          store: store,
          authController: mocks.auth,
          spaceController: mocks.space,
          bookingController: mocks.booking,
          paymentController: mocks.payment,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      restoreCompleter.complete(null);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);

      await _unmountTree(tester);
    },
  );

  testWidgets(
    '2. At Login page, empty fields, wrong password & unreachable server should show errors',
    (WidgetTester tester) async {
      await _setPhoneViewport(tester);
      addTearDown(() => _resetViewport(tester));

      final store = _createSeededStore(signedIn: false);
      final mocks = _ControllerBundle(store);

      when(
        () => mocks.auth.loginAsync('', ''),
      ).thenThrow(DomainError('กรุณากรอกอีเมลและรหัสผ่าน'));
      when(
        () => mocks.auth.loginAsync('renter01@rentspace.test', 'wrongpass'),
      ).thenThrow(ApiError('อีเมลหรือรหัสผ่านไม่ถูกต้อง', 401));
      when(
        () => mocks.auth.loginAsync('renter01@rentspace.test', 'password'),
      ).thenThrow(
        ApiError(
          'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาตรวจสอบเครือข่ายและ API_BASE_URL',
          0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('th'),
          home: LoginPage(store: store, authController: mocks.auth),
        ),
      );
      await tester.pumpAndSettle();

      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'),
      );
      expect(find.text('กรุณากรอกอีเมลและรหัสผ่าน'), findsOneWidget);
      await _dismissSnackBars(tester);

      await _enterText(
        tester,
        _textFieldByLabel('อีเมล'),
        'renter01@rentspace.test',
      );
      await _enterText(
        tester,
        _textFieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
        'wrongpass',
      );
      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'),
      );
      expect(find.text('อีเมลหรือรหัสผ่านไม่ถูกต้อง'), findsOneWidget);
      await _dismissSnackBars(tester);

      await _enterText(
        tester,
        _textFieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
        'password',
      );
      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'),
      );
      expect(
        find.text(
          'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาตรวจสอบเครือข่ายและ API_BASE_URL',
        ),
        findsOneWidget,
      );
      expect(find.byType(LoginPage), findsOneWidget);
    },
  );

  testWidgets(
    '3. At Login page, valid credentials show HomePage with menus for each role',
    (WidgetTester tester) async {
      await _setPhoneViewport(tester);
      addTearDown(() => _resetViewport(tester));

      final store = _createSeededStore(signedIn: false);
      final userIdByEmail = {
        for (final raw in _xamppSnapshot['users'] as List)
          raw['email'] as String: '${raw['id']}',
      };
      final mocks = _ControllerBundle(store);

      when(() => mocks.auth.loginAsync(any(), any())).thenAnswer((inv) async {
        final email = inv.positionalArguments[0] as String;
        final viewerId = userIdByEmail[email]!;
        populateStoreFromXamppSnapshot(
          store,
          _xamppSnapshot,
          viewerId: viewerId,
        );
        store.notify();
      });

      await tester.pumpWidget(
        RentSpaceApp(
          store: store,
          authController: mocks.auth,
          spaceController: mocks.space,
          bookingController: mocks.booking,
          paymentController: mocks.payment,
        ),
      );
      await tester.pumpAndSettle();

      for (final (email, expectedTabs) in [
        (
          'renter01@rentspace.test',
          ['ค้นหา', 'การจอง', 'รายการโปรด', 'โปรไฟล์'],
        ),
        (
          'owner01@rentspace.test',
          ['ภาพรวม', 'พื้นที่', 'การจอง', 'รายรับ', 'โปรไฟล์'],
        ),
        (
          'admin01@rentspace.test',
          ['ภาพรวม', 'ตรวจสอบ', 'การเงิน', 'ผู้ใช้', 'โปรไฟล์'],
        ),
      ]) {
        await _enterText(tester, _textFieldByLabel('อีเมล'), email);
        await _enterText(
          tester,
          _textFieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'password',
        );
        await _tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'),
        );

        expect(find.byType(HomePage), findsOneWidget);
        for (final tab in expectedTabs) {
          expect(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(tab),
            ),
            findsOneWidget,
          );
        }

        await _tapWidget(tester, find.byTooltip('ออกจากระบบ'));
        expect(find.byType(LoginPage), findsOneWidget);
      }

      verify(() => mocks.auth.loginAsync(any(), 'password')).called(3);
      verify(() => mocks.auth.logoutAsync()).called(3);
      await _unmountTree(tester);
    },
  );

  testWidgets(
    '4. At HomePage, loaded spaces show and search/filter/empty state work via MockSpaceController',
    (WidgetTester tester) async {
      await _setPhoneViewport(tester);
      addTearDown(() => _resetViewport(tester));

      final store = _createSeededStore(viewerId: '1002');
      final mocks = _ControllerBundle(store);

      await tester.pumpWidget(
        RentSpaceApp(
          store: store,
          authController: mocks.auth,
          spaceController: mocks.space,
          bookingController: mocks.booking,
          paymentController: mocks.payment,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('ห้องประชุมสว่างใจ'), findsOneWidget);
      expect(find.text('The Quiet Nook (ห้องอ่านหนังสือ)'), findsOneWidget);

      await _enterText(
        tester,
        _textFieldByLabel('ค้นหาชื่อ / ที่อยู่ / สิ่งอำนวยความสะดวก'),
        'ไม่พบชื่อนี้แน่นอน',
      );
      expect(
        find.text('ไม่พบพื้นที่ ลองเปลี่ยนคำค้นหาหรือประเภท'),
        findsOneWidget,
      );

      await _tapWidget(tester, find.byTooltip('ล้างคำค้นหา'));
      await _tapWidget(tester, find.byKey(const ValueKey('open-filter-btn')));
      await _tapWidget(tester, find.widgetWithText(ChoiceChip, 'meeting_room'));
      await _tapWidget(tester, find.text('ไม่เกิน ฿600'));
      await _tapWidget(tester, find.text('8+ คน'));
      await _tapWidget(tester, find.widgetWithText(FilledButton, 'ดูผลลัพธ์'));

      expect(find.text('ตัวกรอง (3)'), findsOneWidget);
      expect(find.text('ห้องประชุมสว่างใจ'), findsOneWidget);
      expect(find.text('The Quiet Nook (ห้องอ่านหนังสือ)'), findsNothing);
      expect(find.text('ห้อง nitro'), findsNothing);

      verify(
        () => mocks.space.filterSpaces(
          favoritesOnly: any(named: 'favoritesOnly'),
          category: any(named: 'category'),
          query: any(named: 'query'),
          sort: any(named: 'sort'),
          maxPrice: any(named: 'maxPrice'),
          minCapacity: any(named: 'minCapacity'),
        ),
      ).called(greaterThanOrEqualTo(3));

      await _unmountTree(tester);
    },
  );

  testWidgets(
    '5. Owner add & edit space in SpaceForm call MockSpaceController and update HomePage list',
    (WidgetTester tester) async {
      await _setPhoneViewport(tester);
      addTearDown(() => _resetViewport(tester));

      final store = _createSeededStore(viewerId: '1001');
      final mocks = _ControllerBundle(store);

      when(
        () => mocks.space.saveAsync(
          id: any(named: 'id'),
          name: any(named: 'name'),
          category: any(named: 'category'),
          location: any(named: 'location'),
          price: any(named: 'price'),
          capacity: any(named: 'capacity'),
          description: any(named: 'description'),
          amenities: any(named: 'amenities'),
          image: any(named: 'image'),
          imageBytes: any(named: 'imageBytes'),
        ),
      ).thenAnswer((inv) async {
        final id = inv.namedArguments[#id] as String?;
        final name = inv.namedArguments[#name] as String;
        final price = inv.namedArguments[#price] as int;
        final capacity = inv.namedArguments[#capacity] as int;
        if (name.trim().isEmpty || price <= 0 || capacity <= 0) {
          throw DomainError('กรอกข้อมูลให้ครบ ราคาและความจุต้องมากกว่า 0');
        }
        if (id == null) {
          final created = Space(
            id: '2099',
            ownerId: '1001',
            name: name.trim(),
            category: inv.namedArguments[#category] as String,
            location: inv.namedArguments[#location] as String,
            price: price,
            capacity: capacity,
            description: inv.namedArguments[#description] as String,
            status: SpaceStatus.pending,
          );
          store.spaces.add(created);
          store.notify();
          return created;
        }
        final existing = store.space(id);
        existing.name = name.trim();
        store.notify();
        return existing;
      });

      await tester.pumpWidget(
        RentSpaceApp(
          store: store,
          authController: mocks.auth,
          spaceController: mocks.space,
          bookingController: mocks.booking,
          paymentController: mocks.payment,
        ),
      );
      await tester.pumpAndSettle();

      await _tapWidget(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('พื้นที่'),
        ),
      );
      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'เพิ่มพื้นที่'),
      );
      expect(find.byType(SpaceForm), findsOneWidget);

      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'บันทึกและส่งตรวจสอบ'),
      );
      expect(
        find.text('กรอกข้อมูลให้ครบ ราคาและความจุต้องมากกว่า 0'),
        findsOneWidget,
      );
      await _dismissSnackBars(tester);

      await _enterText(tester, _textFieldByLabel('ชื่อพื้นที่'), 'ห้องประชุม ใหม่');
      await _enterText(tester, _textFieldByLabel('ที่อยู่'), 'สีลม');
      await _enterText(tester, _textFieldByLabel('ราคา / ชั่วโมง (บาท)'), '550');
      await _enterText(tester, _textFieldByLabel('ความจุ (คน)'), '12');
      await _enterText(
        tester,
        _textFieldByLabel('คำอธิบาย'),
        'พร้อมจอและไมโครโฟน',
      );
      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'บันทึกและส่งตรวจสอบ'),
      );

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('ห้องประชุม ใหม่'), findsOneWidget);

      await _tapWidget(tester, find.widgetWithText(OutlinedButton, 'แก้ไข').first);
      expect(find.byType(SpaceForm), findsOneWidget);
      await _enterText(
        tester,
        _textFieldByLabel('ชื่อพื้นที่'),
        'ห้องประชุมสว่างใจ (แก้ไขแล้ว)',
      );
      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'บันทึกและส่งตรวจสอบ'),
      );

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('ห้องประชุมสว่างใจ (แก้ไขแล้ว)'), findsOneWidget);

      await _unmountTree(tester);
    },
  );

  testWidgets(
    '6. Renter ReservePage picks date/time/attendees and BookingConfirmationPage handles 409 conflict',
    (WidgetTester tester) async {
      await _setPhoneViewport(tester);
      addTearDown(() => _resetViewport(tester));

      final store = _createSeededStore(viewerId: '1002');
      final targetSpace = store.space('2001');
      final mocks = _ControllerBundle(store);

      var createCalls = 0;
      when(
        () => mocks.booking.createAsync(
          any(),
          any(),
          any(),
          any(),
          days: any(named: 'days'),
          attendees: any(named: 'attendees'),
          zone: any(named: 'zone'),
          renterNote: any(named: 'renterNote'),
        ),
      ).thenAnswer((inv) async {
        createCalls++;
        if (createCalls == 1) {
          throw ApiError('ช่วงเวลานี้มีการจองแล้ว', 409);
        }
        final booking = Booking(
          id: '3999',
          spaceId: inv.positionalArguments[0] as String,
          ownerId: targetSpace.ownerId,
          renterId: '1002',
          spaceName: targetSpace.name,
          date: inv.positionalArguments[1] as DateTime,
          startMinutes: inv.positionalArguments[2] as int,
          endMinutes: inv.positionalArguments[3] as int,
          rentAmount: targetSpace.price * 2,
          attendees: inv.namedArguments[#attendees] as int? ?? 1,
          zone: inv.namedArguments[#zone] as String? ?? 'โซนหลัก (พื้นที่มาตรฐาน)',
          status: BookingStatus.ownerReview,
        )..createdAt = _clockNow;
        store.bookings.add(booking);
        store.notify();
        return booking;
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('th'),
          supportedLocales: const [Locale('th'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ReservePage(
            store: store,
            space: targetSpace,
            bookingController: mocks.booking,
            spaceController: mocks.space,
            authController: mocks.auth,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapWidget(tester, find.byIcon(Icons.calendar_month));
      await _tapWidget(tester, find.text('17'));
      await _tapWidget(tester, find.text('ตกลง'));
      await _tapWidget(tester, find.byKey(const ValueKey('slot-780-840')));
      await _tapWidget(tester, find.byKey(const ValueKey('slot-840-900')));
      await _tapWidget(tester, find.byKey(const ValueKey('attendees-increment')));

      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'ส่งคำขอจอง'),
      );
      expect(find.byType(BookingConfirmationPage), findsOneWidget);

      final confirmBtn = find.byKey(const ValueKey('confirm-booking-btn'));
      expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);
      await _tapWidget(
        tester,
        find.text('ฉันยอมรับเงื่อนไขการจองและกฎการใช้สถานที่'),
      );
      expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);

      await _tapWidget(tester, confirmBtn);
      expect(find.text('ช่วงเวลานี้มีการจองแล้ว'), findsOneWidget);
      await _dismissSnackBars(tester);

      await _tapWidget(tester, confirmBtn);
      expect(find.byType(BookingPage), findsOneWidget);
      expect(find.text('รหัสการจอง: 3999'), findsOneWidget);

      verify(
        () => mocks.booking.createAsync(
          '2001',
          any(),
          780,
          900,
          days: 1,
          attendees: 2,
          zone: any(named: 'zone'),
          renterNote: any(named: 'renterNote'),
        ),
      ).called(2);

      await _unmountTree(tester);
    },
  );

  testWidgets(
    '7. BookingPage shows Approve/Reject/Cancel/Complete buttons by status & calls MockBookingController',
    (WidgetTester tester) async {
      await _setPhoneViewport(tester);
      addTearDown(() => _resetViewport(tester));

      final store = _createSeededStore(viewerId: '1002');
      final reviewBooking = findOrSeedBooking(
        store,
        status: BookingStatus.ownerReview,
        spaceId: '2001',
        renterId: '1002',
      );
      final confirmedBooking = findOrSeedBooking(
        store,
        status: BookingStatus.confirmed,
        preferredId: '3001',
        spaceId: '2001',
        overrideDate: _clockNow.subtract(const Duration(days: 1)),
      );
      final rejectedBooking = findOrSeedBooking(
        store,
        status: BookingStatus.ownerRejected,
        preferredId: '3020',
        spaceId: '2001',
      );
      final mocks = _ControllerBundle(store);

      when(
        () => mocks.booking.ownerReviewAsync(reviewBooking.id, true, ''),
      ).thenAnswer((_) async {
        reviewBooking.status = BookingStatus.paymentDue;
        reviewBooking.approvedAt = _clockNow;
        store.notify();
      });
      when(() => mocks.booking.completeAsync(confirmedBooking.id)).thenAnswer((
        _,
      ) async {
        confirmedBooking.status = BookingStatus.completed;
        confirmedBooking.completedAt = _clockNow;
        store.notify();
      });

      store.currentUser = store.user(reviewBooking.renterId);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('th'),
          home: BookingPage(
            store: store,
            bookingId: reviewBooking.id,
            bookingController: mocks.booking,
            paymentController: mocks.payment,
            spaceController: mocks.space,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ยกเลิกคำขอ'), findsOneWidget);
      expect(find.text('อนุมัติคำขอ'), findsNothing);
      expect(find.text('แนบ / ส่งสลิปใหม่'), findsNothing);
      await _unmountTree(tester);

      store.currentUser = store.user(reviewBooking.ownerId);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('th'),
          home: BookingPage(
            store: store,
            bookingId: reviewBooking.id,
            bookingController: mocks.booking,
            paymentController: mocks.payment,
            spaceController: mocks.space,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('อนุมัติคำขอ'), findsOneWidget);
      expect(find.text('ปฏิเสธคำขอ'), findsOneWidget);
      await _tapWidget(tester, find.widgetWithText(FilledButton, 'อนุมัติคำขอ'));
      verify(
        () => mocks.booking.ownerReviewAsync(reviewBooking.id, true, ''),
      ).called(1);
      expect(find.text('อนุมัติคำขอ'), findsNothing);
      await _unmountTree(tester);

      store.currentUser = store.user(confirmedBooking.ownerId);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('th'),
          home: BookingPage(
            store: store,
            bookingId: confirmedBooking.id,
            bookingController: mocks.booking,
            paymentController: mocks.payment,
            spaceController: mocks.space,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'ทำเครื่องหมายว่าใช้บริการแล้ว'),
      );
      verify(() => mocks.booking.completeAsync(confirmedBooking.id)).called(1);
      expect(find.text('เสร็จสิ้น'), findsWidgets);
      await _unmountTree(tester);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('th'),
          home: BookingPage(
            store: store,
            bookingId: rejectedBooking.id,
            bookingController: mocks.booking,
            paymentController: mocks.payment,
            spaceController: mocks.space,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('อนุมัติคำขอ'), findsNothing);
      expect(find.text('ยกเลิกคำขอ'), findsNothing);
      await _unmountTree(tester);
    },
  );

  testWidgets(
    '8. Slip submission, admin rejection & renter resubmit flow work via MockPaymentController',
    (WidgetTester tester) async {
      await _setPhoneViewport(tester);
      addTearDown(() => _resetViewport(tester));

      final store = _createSeededStore(viewerId: '1003');
      final paymentDueBooking = findOrSeedBooking(
        store,
        status: BookingStatus.paymentDue,
        preferredId: '3034',
        spaceId: '2001',
      );
      final targetBookingId = paymentDueBooking.id;
      final mocks = _ControllerBundle(store);

      when(
        () => mocks.payment.submitAsync(targetBookingId, any(), any(), any()),
      ).thenAnswer((inv) async {
        paymentDueBooking.slips.add(
          PaymentSlip(
            name: inv.positionalArguments[1] as String,
            bytes: inv.positionalArguments[2] as Uint8List,
            submittedAt: _clockNow,
            note: inv.positionalArguments[3] as String,
          ),
        );
        paymentDueBooking.status = BookingStatus.slipReview;
        store.notify();
      });
      when(
        () => mocks.payment.reviewAsync(
          targetBookingId,
          false,
          'สลิปเบลอ ยอดไม่ตรง',
        ),
      ).thenAnswer((_) async {
        paymentDueBooking.status = BookingStatus.slipRejected;
        paymentDueBooking.reason = 'สลิปเบลอ ยอดไม่ตรง';
        paymentDueBooking.reasonKind = ReasonKind.slipRejected;
        paymentDueBooking.slips.last.rejectionReason = 'สลิปเบลอ ยอดไม่ตรง';
        paymentDueBooking.slipRejectedAt = _clockNow;
        store.notify();
      });

      store.currentUser = store.user(paymentDueBooking.renterId);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('th'),
          home: BookingPage(
            store: store,
            bookingId: targetBookingId,
            pickSlip: (_) async => (name: 'slip1.png', bytes: _validPngBytes),
            bookingController: mocks.booking,
            paymentController: mocks.payment,
            spaceController: mocks.space,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'แนบ / ส่งสลิปใหม่'),
      );
      expect(find.byType(SlipPage), findsOneWidget);
      await _tapWidget(
        tester,
        find.widgetWithText(OutlinedButton, 'เลือกภาพสลิป'),
      );
      await _enterText(
        tester,
        _textFieldByLabel('หมายเหตุ (ไม่บังคับ)'),
        'รอบที่ 1',
      );
      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'ส่งสลิปเพื่อตรวจสอบ'),
      );
      expect(paymentDueBooking.status, BookingStatus.slipReview);
      await _unmountTree(tester);

      store.currentUser = store.user('1003');
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('th'),
          home: BookingPage(
            store: store,
            bookingId: targetBookingId,
            bookingController: mocks.booking,
            paymentController: mocks.payment,
            spaceController: mocks.space,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapWidget(
        tester,
        find.widgetWithText(OutlinedButton, 'ปฏิเสธสลิป'),
      );
      await _enterText(
        tester,
        _textFieldByLabel('เหตุผล / รายละเอียด'),
        'สลิปเบลอ ยอดไม่ตรง',
      );
      await _tapWidget(tester, find.widgetWithText(FilledButton, 'ยืนยัน'));
      expect(paymentDueBooking.status, BookingStatus.slipRejected);
      await _unmountTree(tester);

      store.currentUser = store.user(paymentDueBooking.renterId);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('th'),
          home: BookingPage(
            store: store,
            bookingId: targetBookingId,
            pickSlip: (_) async => (name: 'slip2.png', bytes: _validPngBytes),
            bookingController: mocks.booking,
            paymentController: mocks.payment,
            spaceController: mocks.space,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('สลิปเบลอ ยอดไม่ตรง'), findsWidgets);

      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'แนบ / ส่งสลิปใหม่'),
      );
      await _tapWidget(
        tester,
        find.widgetWithText(OutlinedButton, 'เลือกภาพสลิป'),
      );
      await _tapWidget(
        tester,
        find.widgetWithText(FilledButton, 'ส่งสลิปเพื่อตรวจสอบ'),
      );

      expect(paymentDueBooking.slips.length, 2);
      expect(find.text('ประวัติสลิปก่อนหน้า (1 รายการ)'), findsOneWidget);
      verify(
        () => mocks.payment.submitAsync(targetBookingId, any(), any(), any()),
      ).called(2);
      verify(
        () => mocks.payment.reviewAsync(
          targetBookingId,
          false,
          'สลิปเบลอ ยอดไม่ตรง',
        ),
      ).called(1);

      await _unmountTree(tester);
    },
  );

  testWidgets(
    '9. Broken image bytes & failing network URL render fallback widgets without throwing',
    (WidgetTester tester) async {
      await _setPhoneViewport(tester);
      addTearDown(() => _resetViewport(tester));

      final corruptSpace = Space(
        id: '2999',
        ownerId: '1001',
        name: 'ห้องภาพเสีย',
        category: 'meeting_room',
        location: 'กรุงเทพ',
        price: 300,
        capacity: 6,
        description: 'ทดสอบภาพเสีย',
        imageBytes: _corruptImageBytes,
        status: SpaceStatus.approved,
      );
      final corruptSlip = PaymentSlip(
        name: 'corrupt.png',
        bytes: _corruptImageBytes,
        submittedAt: _clockNow,
      );
      final invalidUrlSlip = PaymentSlip(
        name: 'missing.png',
        bytes: Uint8List(0),
        submittedAt: _clockNow,
        imageUrl: 'https://invalid.example.invalid/missing.png',
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('th'),
          home: Scaffold(
            body: Column(
              children: [
                SpaceImage(
                  corruptSpace,
                  height: 80,
                  fallback: const Text('ภาพพื้นที่สำรอง'),
                ),
                SlipImage(corruptSlip, height: 80),
                SlipImage(invalidUrlSlip, height: 80),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ภาพพื้นที่สำรอง'), findsOneWidget);
      expect(find.text('ไม่สามารถเปิดภาพได้'), findsNWidgets(2));
    },
  );

  testWidgets(
    '10. Load failure displays retry banner and tapping retry clears syncError',
    (WidgetTester tester) async {
      await _setPhoneViewport(tester);
      addTearDown(() => _resetViewport(tester));

      final store = _createSeededStore(viewerId: '1002');
      store.failNextRefresh = true;
      final mocks = _ControllerBundle(store);

      await tester.pumpWidget(
        RentSpaceApp(
          store: store,
          authController: mocks.auth,
          spaceController: mocks.space,
          bookingController: mocks.booking,
          paymentController: mocks.payment,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('เชื่อมต่อข้อมูลไม่สำเร็จ'), findsOneWidget);
      await _tapWidget(tester, find.widgetWithText(TextButton, 'ลองใหม่'));

      expect(store.refreshCalls, 2);
      expect(store.syncError, isNull);
      expect(find.text('ลองใหม่'), findsNothing);

      await _unmountTree(tester);
    },
  );

  testWidgets(
    '11. Small 360x740 viewport with open keyboard and long Thai text renders with zero overflow',
    (WidgetTester tester) async {
      await _setPhoneViewport(
        tester,
        size: const Size(360, 740),
        viewInsets: const FakeViewPadding(bottom: 300),
      );
      addTearDown(() => _resetViewport(tester));

      final longThai = List.filled(18, 'ข้อความทดสอบหน้าจอเล็กแบบยาว').join(' ');
      final store = _createSeededStore(viewerId: '1002');
      final featuredSpace = store.space('2001');
      featuredSpace.name = longThai;
      featuredSpace.location = longThai;
      final mocks = _ControllerBundle(store);

      await tester.pumpWidget(
        RentSpaceApp(
          store: store,
          authController: mocks.auth,
          spaceController: mocks.space,
          bookingController: mocks.booking,
          paymentController: mocks.payment,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('th'),
          home: SpaceForm(
            store: store,
            space: featuredSpace,
            spaceController: mocks.space,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _unmountTree(tester);
    },
  );

  testWidgets(
    '12. System back (PopScope), route back arrow and logout call MockAuthController cleanly',
    (WidgetTester tester) async {
      await _setPhoneViewport(tester);
      addTearDown(() => _resetViewport(tester));

      final store = _createSeededStore(viewerId: '1002');
      final approvedCount = store.spaces
          .where((s) => s.status == SpaceStatus.approved)
          .length;
      final mocks = _ControllerBundle(store);

      await tester.pumpWidget(
        RentSpaceApp(
          store: store,
          authController: mocks.auth,
          spaceController: mocks.space,
          bookingController: mocks.booking,
          paymentController: mocks.payment,
        ),
      );
      await tester.pumpAndSettle();

      await _tapWidget(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('การจอง'),
        ),
      );
      expect(find.text('การจองของฉัน'), findsOneWidget);

      final homeContext = tester.element(find.byType(HomePage));
      await Navigator.of(homeContext).maybePop();
      await tester.pumpAndSettle();
      expect(find.text('พบ $approvedCount พื้นที่ที่ตรงกับเงื่อนไข'), findsOneWidget);

      await _tapWidget(tester, find.text('ดูรายละเอียดและจอง').first);
      expect(find.byType(ReservePage), findsOneWidget);
      await _tapWidget(tester, find.byIcon(Icons.arrow_back));
      expect(find.byType(HomePage), findsOneWidget);

      await _tapWidget(tester, find.byTooltip('ออกจากระบบ'));
      verify(() => mocks.auth.logoutAsync()).called(1);
      expect(store.currentUser, isNull);
      expect(find.byType(LoginPage), findsOneWidget);

      await _unmountTree(tester);
    },
  );
}
