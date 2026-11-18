import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/services/api_client.dart';
import 'package:rentspace/ui/home_page.dart';
import 'package:rentspace/ui/login_page.dart';

import '../fixtures/mock_controllers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerMockControllerFallbacks();
    await setupTestChannels();
  });

  group('LoginPage & Auth Flows (Mocktail)', () {
    testWidgets(
      '1. At first, session restore shows CircularProgressIndicator then LoginPage or HomePage',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(signedIn: false);
        final mocks = ControllerBundle(store);
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

        await unmountApp(tester);

        final savedStore = createMockStore(signedIn: false);
        final savedMocks = ControllerBundle(savedStore);
        final savedCompleter = Completer<AppUser?>();
        when(
          () => savedMocks.auth.restoreSessionAsync(),
        ).thenAnswer((_) => savedCompleter.future);

        await tester.pumpWidget(
          RentSpaceApp(
            store: savedStore,
            authController: savedMocks.auth,
            spaceController: savedMocks.space,
            bookingController: savedMocks.booking,
            paymentController: savedMocks.payment,
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        populateMockStore(savedStore, viewerId: '1002');
        savedStore.notify();
        savedCompleter.complete(savedStore.currentUser);
        await tester.pumpAndSettle();

        expect(find.byType(HomePage), findsOneWidget);
        expect(find.text('ค้นหา'), findsWidgets);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '2. Empty inputs, wrong password, suspended account, network failure & password toggles show expected feedback',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(signedIn: false);
        final mocks = ControllerBundle(store);
        final suspendedUser = store.users.firstWhere(
          (entry) => !entry.active,
          orElse: () => store.user('1001'),
        );

        when(
          () => mocks.auth.loginAsync('', ''),
        ).thenThrow(DomainError('กรุณากรอกอีเมลและรหัสผ่าน'));
        when(
          () => mocks.auth.loginAsync('renter01@rentspace.test', 'wrongpass'),
        ).thenThrow(ApiError('อีเมลหรือรหัสผ่านไม่ถูกต้อง', 401));
        when(
          () => mocks.auth.loginAsync(suspendedUser.email, 'password'),
        ).thenThrow(ApiError('บัญชีนี้ถูกระงับการใช้งาน', 403));
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

        await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
        await tester.pumpAndSettle();
        expect(find.text('กรุณากรอกอีเมลและรหัสผ่าน'), findsOneWidget);
        await dismissSnackBars(tester);

        await tester.enterText(
          fieldByLabel('อีเมล'),
          'renter01@rentspace.test',
        );
        await tester.enterText(
          fieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'wrongpass',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
        await tester.pumpAndSettle();
        expect(find.text('อีเมลหรือรหัสผ่านไม่ถูกต้อง'), findsOneWidget);
        expect(store.currentUser, isNull);
        await dismissSnackBars(tester);

        await tester.tap(find.byTooltip('แสดงรหัสผ่าน'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('ซ่อนรหัสผ่าน'));
        await tester.pumpAndSettle();

        await tester.enterText(fieldByLabel('อีเมล'), suspendedUser.email);
        await tester.enterText(
          fieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'password',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
        await tester.pumpAndSettle();
        expect(find.text('บัญชีนี้ถูกระงับการใช้งาน'), findsOneWidget);
        await dismissSnackBars(tester);

        await tester.enterText(
          fieldByLabel('อีเมล'),
          'renter01@rentspace.test',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
        await tester.pumpAndSettle();
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
      '3. Valid login shows loading spinner, HomePage, poll sync retry banner & clean logout',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(signedIn: false);
        final mocks = ControllerBundle(store);
        final loginCompleter = Completer<void>();

        when(
          () => mocks.auth.loginAsync('renter01@rentspace.test', 'password'),
        ).thenAnswer((_) async {
          await loginCompleter.future;
          populateMockStore(store, viewerId: '1002');
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

        await tester.enterText(
          fieldByLabel('อีเมล'),
          'renter01@rentspace.test',
        );
        await tester.enterText(
          fieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'password',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        loginCompleter.complete();
        await tester.pumpAndSettle();

        expect(find.byType(HomePage), findsOneWidget);
        expect(store.currentUser?.id, '1002');

        store.failNextRefresh = true;
        await store.poll();
        await tester.pumpAndSettle();
        expect(find.text('เชื่อมต่อข้อมูลไม่สำเร็จ'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'ลองใหม่'), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'ลองใหม่'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextButton, 'ลองใหม่'), findsNothing);

        await tester.tap(find.byTooltip('ออกจากระบบ'));
        await tester.pumpAndSettle();
        verify(() => mocks.auth.logoutAsync()).called(1);
        expect(store.currentUser, isNull);
        expect(find.byType(LoginPage), findsOneWidget);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '4. Register tab validates inputs, toggles confirm password & registers owner via MockAuthController',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(signedIn: false);
        final mocks = ControllerBundle(store);

        when(
          () => mocks.auth.registerAsync('', '', '', UserRole.renter, '', ''),
        ).thenThrow(DomainError('กรุณาระบุชื่อและอีเมลที่ถูกต้อง'));
        when(
          () => mocks.auth.registerAsync(
            'สมาชิก ทดสอบ',
            'newmember@rentspace.test',
            'password123',
            UserRole.owner,
            '089-999-9999',
            'password123',
          ),
        ).thenAnswer((_) async {
          final createdUser = AppUser(
            id: '1999',
            name: 'สมาชิก ทดสอบ',
            email: 'newmember@rentspace.test',
            password: 'password123',
            role: UserRole.owner,
            phone: '089-999-9999',
          );
          store.users.add(createdUser);
          store.currentUser = createdUser;
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

        await scrollToAndTap(tester, find.text('สมัครสมาชิก'));
        await scrollToAndTap(tester, find.byTooltip('แสดงยืนยันรหัสผ่าน'));
        await scrollToAndTap(tester, find.byTooltip('ซ่อนยืนยันรหัสผ่าน'));
        await scrollToAndTap(tester, find.text('สร้างบัญชี'));
        expect(find.text('กรุณาระบุชื่อและอีเมลที่ถูกต้อง'), findsOneWidget);
        await dismissSnackBars(tester);

        await scrollToAndEnter(
          tester,
          fieldByLabel('ชื่อ-นามสกุล'),
          'สมาชิก ทดสอบ',
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('อีเมล'),
          'newmember@rentspace.test',
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('เบอร์โทรศัพท์ติดต่อ (เช่น 081-234-5678)'),
          '089-999-9999',
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'password123',
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('ยืนยันรหัสผ่าน'),
          'password123',
        );
        await scrollToAndTap(
          tester,
          find.byType(DropdownButtonFormField<UserRole>),
        );
        await scrollToAndTap(tester, find.text('เจ้าของพื้นที่').last);
        await scrollToAndTap(tester, find.text('สร้างบัญชี'));

        expect(store.currentUser?.role, UserRole.owner);
        expect(find.byType(HomePage), findsOneWidget);
        expect(find.text('ภาพรวม'), findsWidgets);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '5. ThemeToggle switch flips dark mode and TextInputAction.done submits login & registration',
      (tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(signedIn: false);
        final mocks = ControllerBundle(store);
        when(() => mocks.auth.restoreSessionAsync()).thenAnswer((_) async => null);
        when(
          () => mocks.auth.loginAsync('renter01@rentspace.test', 'password123'),
        ).thenAnswer((_) async {
          populateMockStore(store, viewerId: '1002');
          store.notify();
        });
        when(
          () => mocks.auth.registerAsync(
            'ผู้เช่าคีย์บอร์ด',
            'kb@rentspace.test',
            'password123',
            UserRole.renter,
            '081-222-3333',
            'password123',
          ),
        ).thenAnswer((_) async {
          populateMockStore(store, viewerId: '1002');
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

        // Toggle dark theme on and off via top-bar ThemeToggle buttons
        expect(store.darkMode, isFalse);
        await tester.tap(find.byTooltip('โหมดมืด'));
        await tester.pumpAndSettle();
        expect(store.darkMode, isTrue);
        await tester.tap(find.byTooltip('โหมดสว่าง'));
        await tester.pumpAndSettle();
        expect(store.darkMode, isFalse);

        // Toggle password eye icon and submit login via keyboard done action
        await tester.tap(find.byTooltip('แสดงรหัสผ่าน'));
        await tester.pump();
        expect(find.byTooltip('ซ่อนรหัสผ่าน'), findsOneWidget);
        await tester.enterText(
          fieldByLabel('อีเมล'),
          'renter01@rentspace.test',
        );
        await tester.enterText(
          fieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'password123',
        );
        await tester.showKeyboard(fieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        verify(
          () => mocks.auth.loginAsync('renter01@rentspace.test', 'password123'),
        ).called(1);
        expect(find.byType(HomePage), findsOneWidget);

        // Return to LoginPage to test registration keyboard done + confirm eye toggle
        store.currentUser = null;
        store.notify();
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsOneWidget);

        await tester.tap(find.text('สมัครสมาชิก'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('แสดงยืนยันรหัสผ่าน'));
        await tester.pump();
        expect(find.byTooltip('ซ่อนยืนยันรหัสผ่าน'), findsOneWidget);

        await tester.enterText(fieldByLabel('ชื่อ-นามสกุล'), 'ผู้เช่าคีย์บอร์ด');
        await tester.enterText(fieldByLabel('อีเมล'), 'kb@rentspace.test');
        await tester.enterText(
          fieldByLabel('เบอร์โทรศัพท์ติดต่อ (เช่น 081-234-5678)'),
          '081-222-3333',
        );
        await tester.enterText(
          fieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'password123',
        );
        await tester.enterText(fieldByLabel('ยืนยันรหัสผ่าน'), 'password123');
        await tester.showKeyboard(fieldByLabel('ยืนยันรหัสผ่าน'));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        verify(
          () => mocks.auth.registerAsync(
            'ผู้เช่าคีย์บอร์ด',
            'kb@rentspace.test',
            'password123',
            UserRole.renter,
            '081-222-3333',
            'password123',
          ),
        ).called(1);
        expect(find.byType(HomePage), findsOneWidget);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '6. Desktop _MobileFrame constrains width > 430 and restoreSessionAsync error falls back to LoginPage with syncError',
      (tester) async {
        configureMobileViewport(tester, size: const Size(1280, 1024));
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(signedIn: false);
        final mocks = ControllerBundle(store);
        when(
          () => mocks.auth.restoreSessionAsync(),
        ).thenThrow(DomainError('session expired offline'));

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

        expect(find.byType(LoginPage), findsOneWidget);
        expect(store.syncError, 'session expired offline');
        expect(tester.getSize(find.byType(LoginPage)).width, kMobileMaxWidth - 2);
        expect(tester.getSize(find.byType(LoginPage)).height, kMobileMaxHeight - 2);

        configureMobileViewport(tester, size: const Size(800, 700));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(LoginPage)).width, kMobileMaxWidth - 2);
        expect(tester.getSize(find.byType(LoginPage)).height, 700);
        expect(tester.takeException(), isNull);

        await unmountApp(tester);
      },
    );
  });
}
