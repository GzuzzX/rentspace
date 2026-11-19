import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/ui/booking_pages.dart';
import 'package:rentspace/ui/home_page.dart';
import 'package:rentspace/ui/login_page.dart';

import '../../fixtures/mock_controllers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerMockControllerFallbacks();
    await setupTestChannels();
  });

  group('HomePage — Renter Role (Mocktail)', () {
    testWidgets(
      '1. Logging in as Renter shows exact NavigationBar menus & clean logout',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(signedIn: false);
        final userIdByEmail = {
          for (final entry in store.users) entry.email: entry.id,
        };
        final mocks = ControllerBundle(store);

        when(() => mocks.auth.loginAsync(any(), any())).thenAnswer((inv) async {
          final email = inv.positionalArguments[0] as String;
          populateMockStore(store, viewerId: userIdByEmail[email]!);
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
        await tester.pumpAndSettle();

        expect(find.byType(HomePage), findsOneWidget);
        for (final tabLabel in ['ค้นหา', 'การจอง', 'รายการโปรด', 'โปรไฟล์']) {
          expect(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(tabLabel),
            ),
            findsOneWidget,
          );
        }

        await tester.tap(find.byTooltip('ออกจากระบบ'));
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsOneWidget);

        verify(
          () => mocks.auth.loginAsync('renter01@rentspace.test', 'password'),
        ).called(1);
        verify(() => mocks.auth.logoutAsync()).called(1);
        await unmountApp(tester);
      },
    );

    testWidgets(
      '2. Renter search, filter sheet, empty results, theme toggle & favorites call MockSpaceController',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1002');
        store.currentUser!.favorites.clear();
        final approvedCount = store.spaces
            .where((entry) => entry.status == SpaceStatus.approved)
            .length;
        final mocks = ControllerBundle(store);

        when(() => mocks.space.favoriteAsync(any())).thenAnswer((inv) async {
          final spaceId = inv.positionalArguments[0] as String;
          if (!store.currentUser!.favorites.remove(spaceId)) {
            store.currentUser!.favorites.add(spaceId);
          }
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

        expect(
          find.text('พบ $approvedCount พื้นที่ที่ตรงกับเงื่อนไข'),
          findsOneWidget,
        );
        expect(find.text('ห้องประชุมสว่างใจ'), findsOneWidget);
        expect(find.text('The Quiet Nook (ห้องอ่านหนังสือ)'), findsOneWidget);

        await tester.tap(find.byTooltip('โหมดมืด'));
        await tester.pumpAndSettle();
        expect(store.darkMode, isTrue);
        await tester.tap(find.byTooltip('โหมดสว่าง'));
        await tester.pumpAndSettle();
        expect(store.darkMode, isFalse);

        final searchFinder = fieldByLabel(
          'ค้นหาชื่อ / ที่อยู่ / สิ่งอำนวยความสะดวก',
        );
        await tester.enterText(searchFinder, 'ไม่พบชื่อนี้แน่นอน');
        await tester.pumpAndSettle();
        expect(
          find.text('ไม่พบพื้นที่ ลองเปลี่ยนคำค้นหาหรือประเภท'),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('ล้างคำค้นหา'));
        await tester.pumpAndSettle();
        await tester.enterText(searchFinder, 'The Quiet Nook');
        await tester.pumpAndSettle();
        expect(find.text('พบ 1 พื้นที่ที่ตรงกับเงื่อนไข'), findsOneWidget);
        await tester.tap(find.byTooltip('ล้างคำค้นหา'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('open-filter-btn')));
        await tester.pumpAndSettle();
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'meeting_room'),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('sort-priceAsc')),
        );
        await scrollToAndTap(tester, find.text('ไม่เกิน ฿600'));
        await scrollToAndTap(tester, find.text('8+ คน'));
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ดูผลลัพธ์'),
        );

        expect(find.text('ตัวกรอง (4)'), findsOneWidget);
        expect(find.text('ห้องประชุมสว่างใจ'), findsOneWidget);
        expect(find.text('The Quiet Nook (ห้องอ่านหนังสือ)'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('open-filter-btn')));
        await tester.pumpAndSettle();
        await scrollToAndTap(tester, find.text('12+ คน'));
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ดูผลลัพธ์'),
        );
        expect(
          find.text('ไม่พบพื้นที่ ลองเปลี่ยนคำค้นหาหรือประเภท'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(TextButton, 'ล้างตัวกรอง'));
        await tester.pumpAndSettle();
        expect(
          find.text('พบ $approvedCount พื้นที่ที่ตรงกับเงื่อนไข'),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('รายการโปรด').first);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('รายการโปรด'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('รายการโปรด (1 รายการ)'), findsOneWidget);

        await tester.tap(find.byTooltip('รายการโปรด').first);
        await tester.pumpAndSettle();
        expect(find.text('ยังไม่มีรายการโปรดที่ตรงกับตัวกรอง'), findsOneWidget);
        verify(() => mocks.space.favoriteAsync(any())).called(2);

        final renterTooltip = '${store.user('1002').name} (ผู้เช่า)';
        await tester.tap(find.byTooltip(renterTooltip));
        await tester.pumpAndSettle();
        expect(find.text('โปรไฟล์ของฉัน'), findsOneWidget);
        await tester.tap(find.text('rentSPACE'));
        await tester.pumpAndSettle();
        expect(
          find.text('พบ $approvedCount พื้นที่ที่ตรงกับเงื่อนไข'),
          findsOneWidget,
        );

        await unmountApp(tester);
      },
    );

    testWidgets(
      '3. Load failure displays retry banner and tapping retry clears syncError',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1002');
        store.failNextRefresh = true;
        final mocks = ControllerBundle(store);

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
        await tester.tap(find.widgetWithText(TextButton, 'ลองใหม่'));
        await tester.pumpAndSettle();

        expect(store.refreshCalls, 2);
        expect(store.syncError, isNull);
        expect(find.text('ลองใหม่'), findsNothing);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '4. System back (PopScope), route back from Confirmation -> Reserve -> Home & clean logout work',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1002');
        final approvedCount = store.spaces
            .where((entry) => entry.status == SpaceStatus.approved)
            .length;
        final mocks = ControllerBundle(store);

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

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('การจอง'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('การจองของฉัน'), findsOneWidget);

        await Navigator.of(tester.element(find.byType(HomePage))).maybePop();
        await tester.pumpAndSettle();
        expect(
          find.text('พบ $approvedCount พื้นที่ที่ตรงกับเงื่อนไข'),
          findsOneWidget,
        );

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ดูรายละเอียดและจอง').first,
        );
        expect(find.byType(ReservePage), findsOneWidget);
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ส่งคำขอจอง'),
        );
        expect(find.text('ยืนยันการจอง'), findsOneWidget);

        await scrollToAndTap(
          tester,
          find.widgetWithText(OutlinedButton, 'กลับไปแก้ไขข้อมูลการจอง'),
        );
        expect(find.text('รายละเอียดและสรุปการจอง'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(
          find.text('พบ $approvedCount พื้นที่ที่ตรงกับเงื่อนไข'),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('ออกจากระบบ'));
        await tester.pumpAndSettle();
        verify(() => mocks.auth.logoutAsync()).called(1);
        expect(store.currentUser, isNull);
        expect(store.bookings, isEmpty);
        expect(find.byType(LoginPage), findsOneWidget);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '5. Renter filter reset, urgent booking banner, booking tabs/status sheet, booking card nav, and ProfilePanel password toggle/save',
      (tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1002');
        final mocks = ControllerBundle(store);
        when(
          () => mocks.auth.restoreSessionAsync(),
        ).thenAnswer((_) async => null);
        when(
          () => mocks.auth.changePasswordAsync('', '', ''),
        ).thenThrow(DomainError('กรุณากรอกรหัสผ่านปัจจุบัน'));
        when(
          () => mocks.auth.changePasswordAsync(
            'oldpass123',
            'newpass123',
            'newpass123',
          ),
        ).thenAnswer((_) async {});

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

        await tester.tap(find.byKey(const ValueKey('open-filter-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sort-priceAsc')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ล้างค่าทั้งหมด'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.text('ล้างตัวกรอง'), findsNothing);

        await tester.tap(find.text('การจอง').last);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'ดำเนินการ'));
        await tester.pumpAndSettle();
        expect(find.byType(BookingPage), findsOneWidget);
        await tester.tap(find.byTooltip('กลับหน้าหลัก'));
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);

        await tester.tap(find.textContaining('ประวัติ ('));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('ทั้งหมด ('));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('กำลังดำเนินการ ('));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('booking-status-filter-btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'รอเจ้าของอนุมัติ'));
        await tester.pumpAndSettle();
        expect(find.text('สถานะ: รอเจ้าของอนุมัติ'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'ล้าง'));
        await tester.pumpAndSettle();
        expect(find.text('ตัวกรองสถานะ'), findsOneWidget);

        await tester.tap(find.text('ห้องประชุมสว่างใจ').first);
        await tester.pumpAndSettle();
        expect(find.byType(BookingPage), findsOneWidget);
        await tester.tap(find.byTooltip('กลับหน้าหลัก'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('โปรไฟล์').last);
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.byTooltip('แสดงรหัสผ่าน'));
        expect(find.byTooltip('ซ่อนรหัสผ่าน'), findsOneWidget);

        await scrollToAndTap(tester, find.text('บันทึกรหัสผ่านใหม่'));
        expect(find.text('กรุณากรอกรหัสผ่านปัจจุบัน'), findsOneWidget);
        await dismissSnackBars(tester);

        await scrollToAndEnter(
          tester,
          fieldByLabel('รหัสผ่านปัจจุบัน'),
          'oldpass123',
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('รหัสผ่านใหม่ (อย่างน้อย 8 ตัวอักษร)'),
          'newpass123',
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('ยืนยันรหัสผ่านใหม่'),
          'newpass123',
        );
        await scrollToAndTap(tester, find.text('บันทึกรหัสผ่านใหม่'));

        verify(
          () => mocks.auth.changePasswordAsync(
            'oldpass123',
            'newpass123',
            'newpass123',
          ),
        ).called(1);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '6. Renter FilterSheet remaining chips and tapping SpaceCard body opens ReservePage',
      (tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final renterStore = createMockStore(viewerId: '1002');
        final renterMocks = ControllerBundle(renterStore);
        when(
          () => renterMocks.auth.restoreSessionAsync(),
        ).thenAnswer((_) async => null);

        await tester.pumpWidget(
          RentSpaceApp(
            store: renterStore,
            authController: renterMocks.auth,
            spaceController: renterMocks.space,
            bookingController: renterMocks.booking,
            paymentController: renterMocks.payment,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('open-filter-btn')));
        await tester.pumpAndSettle();
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('sort-priceDesc')),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('sort-capacityDesc')),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('sort-recommended')),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ทุกราคา'),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ทุกความจุ'),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ทั้งหมด').first,
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ดูผลลัพธ์'),
        );

        await scrollToAndTap(tester, find.text('ห้องประชุมสว่างใจ').first);
        expect(find.byType(ReservePage), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);

        await unmountApp(tester);
      },
    );
  });
}
