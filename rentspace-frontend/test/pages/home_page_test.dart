import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/ui/booking_pages.dart';
import 'package:rentspace/ui/home_page.dart';
import 'package:rentspace/ui/login_page.dart';

import '../fixtures/mock_controllers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerMockControllerFallbacks();
    await setupTestChannels();
  });

  group('HomePage Roles, Search, Dashboards & Navigation (Mocktail)', () {
    testWidgets(
      '1. Logging in per role shows exact NavigationBar menus, profile shortcuts & logout',
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
          await tester.enterText(fieldByLabel('อีเมล'), email);
          await tester.enterText(
            fieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
            'password',
          );
          await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
          await tester.pumpAndSettle();

          expect(find.byType(HomePage), findsOneWidget);
          for (final tabLabel in expectedTabs) {
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
        }

        verify(() => mocks.auth.loginAsync(any(), 'password')).called(3);
        verify(() => mocks.auth.logoutAsync()).called(3);
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
        expect(
          find.text('The Quiet Nook (ห้องอ่านหนังสือ)'),
          findsNothing,
        );

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
        expect(
          find.text('ยังไม่มีรายการโปรดที่ตรงกับตัวกรอง'),
          findsOneWidget,
        );
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
      '3. Owner dashboard missing bank warning, urgent chips, calendar & payout clipboard work via MockAuthController',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1001');
        store.user('1001').bankInfo = '';
        findBookingByStatus(
          store,
          status: BookingStatus.ownerReview,
          spaceId: '2001',
          renterId: '1002',
        );
        findBookingByStatus(
          store,
          status: BookingStatus.confirmed,
          preferredId: '3001',
          spaceId: '2001',
        );
        final ownerBookings = store.bookings
            .where((entry) => entry.ownerId == '1001')
            .toList();
        final pendingReviewCount = ownerBookings
            .where((entry) => entry.status == BookingStatus.ownerReview)
            .length;
        final readyCompleteCount = ownerBookings
            .where(
              (entry) =>
                  entry.status == BookingStatus.confirmed &&
                  !mockClockNow.isBefore(entry.endsAt),
            )
            .length;
        final totalUrgentCount = pendingReviewCount + readyCompleteCount;

        final mocks = ControllerBundle(store);
        when(
          () => mocks.auth.updateProfileAsync(any(), any(), any(), any()),
        ).thenAnswer((inv) async {
          final currentOwner = store.currentUser!;
          currentOwner.name = inv.positionalArguments[0] as String;
          currentOwner.email = inv.positionalArguments[1] as String;
          currentOwner.phone = inv.positionalArguments[2] as String;
          currentOwner.bankInfo =
              inv.positionalArguments[3] as String? ?? currentOwner.bankInfo;
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

        await scrollToAndTap(tester, find.text('ยังไม่ได้ระบุบัญชีรับเงิน'));
        expect(find.text('โปรไฟล์ของฉัน'), findsOneWidget);

        await scrollToAndEnter(
          tester,
          fieldByLabel('บัญชีธนาคารรับเงินโอน (เช่น กสิกรไทย 123-4-56789-0)'),
          'กสิกรไทย 123-4-56789-0',
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกโปรไฟล์'),
        );
        await dismissSnackBars(tester);
        verify(
          () => mocks.auth.updateProfileAsync(
            any(),
            any(),
            any(),
            'กสิกรไทย 123-4-56789-0',
          ),
        ).called(1);

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('ภาพรวม'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('แจ้งเตือนผู้ให้เช่า ($totalUrgentCount รายการ)'),
          findsOneWidget,
        );
        expect(find.text('คำขอรออนุมัติ ($pendingReviewCount)'), findsOneWidget);
        expect(
          find.text('รอกดยืนยันจบงาน ($readyCompleteCount)'),
          findsOneWidget,
        );

        await scrollToAndTap(
          tester,
          find.text('คำขอรออนุมัติ ($pendingReviewCount)'),
        );
        expect(find.text('การจองพื้นที่'), findsOneWidget);
        await scrollToAndTap(tester, find.text('ปฏิทิน'));
        expect(find.byType(CalendarDatePicker), findsOneWidget);
        await scrollToAndTap(tester, find.text('ประวัติ'));
        expect(find.text('ห้องประชุมสว่างใจ'), findsWidgets);

        await tester.tap(find.text('รายรับ'));
        await tester.pumpAndSettle();
        await scrollToAndTap(tester, find.text('คัดลอกสรุปรายรับ'));
        expect(find.text('คัดลอกสรุปรายรับลง Clipboard แล้ว'), findsOneWidget);
        expect(lastMockClipboard, contains('รายงานรายรับ RentSpace'));
        await dismissSnackBars(tester);

        await scrollToAndTap(tester, find.byTooltip('คัดลอกเลขบัญชี'));
        expect(lastMockClipboard, 'กสิกรไทย 123-4-56789-0');
        await dismissSnackBars(tester);

        await scrollToAndTap(
          tester,
          find.widgetWithText(TextButton, 'แก้ไขบัญชี'),
        );
        expect(find.text('โปรไฟล์ของฉัน'), findsOneWidget);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '4. Admin dashboard moderates spaces, closes issues, filters finance & toggles users via Mocktail',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1003');
        if (!store.issues.any((entry) => !entry.closed)) {
          store.issues.add(
            Issue(
              id: 'iss_open_1',
              reporterId: '1002',
              subject: 'แอร์ไม่เย็น',
              detail: 'ห้องประชุมชั้น 2 แอร์ไม่เย็น',
            ),
          );
        }
        if (!store.spaces.any((entry) => entry.status == SpaceStatus.rejected)) {
          store.spaces.add(
            Space(
              id: '2098',
              ownerId: '1001',
              name: 'พื้นที่ปรับปรุงภาพถ่าย',
              category: 'meeting_room',
              location: 'พญาไท กรุงเทพฯ',
              price: 350,
              capacity: 10,
              description: 'รออัปเดตภาพ',
              status: SpaceStatus.rejected,
            )..reviewReason = 'ภาพไม่ชัด',
          );
        }
        final pendingSpace = store.spaces.firstWhere(
          (entry) => entry.status == SpaceStatus.pending,
        );
        final rejectedSpace = store.spaces.firstWhere(
          (entry) => entry.status == SpaceStatus.rejected,
        );
        final pendingCount = store.spaces
            .where((entry) => entry.status == SpaceStatus.pending)
            .length;
        final openIssuesCount = store.issues
            .where((entry) => !entry.closed)
            .length;
        final totalSpacesCount = store.spaces.length;
        final rejectedCount = store.spaces
            .where((entry) => entry.status == SpaceStatus.rejected)
            .length;

        final mocks = ControllerBundle(store);
        when(
          () => mocks.space.reviewAsync(any(), any(), any()),
        ).thenAnswer((inv) async {
          final targetSpace = store.space(inv.positionalArguments[0] as String);
          final approve = inv.positionalArguments[1] as bool;
          targetSpace.status = approve
              ? SpaceStatus.approved
              : SpaceStatus.rejected;
          targetSpace.reviewReason = inv.positionalArguments[2] as String;
          store.notify();
        });
        when(
          () => mocks.space.closeIssueAsync(any(), any()),
        ).thenAnswer((inv) async {
          final issue = store.issues.firstWhere(
            (entry) => entry.id == inv.positionalArguments[0] as String,
          );
          issue.closed = true;
          issue.resolution = inv.positionalArguments[1] as String;
          store.notify();
        });
        when(() => mocks.space.activateSpaceAsync(any())).thenAnswer((inv) async {
          store.space(inv.positionalArguments[0] as String).status =
              SpaceStatus.approved;
          store.notify();
        });
        when(() => mocks.auth.toggleUserAsync(any())).thenAnswer((inv) async {
          final targetUser = store.user(inv.positionalArguments[0] as String);
          targetUser.active = !targetUser.active;
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

        await scrollToAndTap(
          tester,
          find.text('ประกาศรอตรวจ ($pendingCount)'),
        );
        expect(find.text(pendingSpace.name), findsWidgets);
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'อนุมัติประกาศ').first,
        );
        expect(pendingSpace.status, SpaceStatus.approved);

        await scrollToAndTap(
          tester,
          find.text('รายงานปัญหา ($openIssuesCount)'),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(TextButton, 'บันทึกผลและปิดรายงาน').first,
        );
        await submitReasonDialog(tester, 'ล้างแอร์เรียบร้อยแล้ว');
        expect(find.text('ผลการแก้ไข: ล้างแอร์เรียบร้อยแล้ว'), findsWidgets);

        await scrollToAndTap(
          tester,
          find.text('พื้นที่ทั้งหมด ($totalSpacesCount)'),
        );
        await scrollToAndTap(tester, find.text('ถูกระงับ ($rejectedCount)'));
        expect(find.text(rejectedSpace.name), findsOneWidget);
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'เปิดใช้งานใหม่').first,
        );
        expect(rejectedSpace.status, SpaceStatus.approved);

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('การเงิน'),
          ),
        );
        await tester.pumpAndSettle();
        await scrollToAndTap(tester, find.text('คัดลอกสรุปการเงิน'));
        expect(lastMockClipboard, contains('รายงานสรุปการเงิน RentSpace'));
        await dismissSnackBars(tester);

        await scrollToAndTap(tester, find.text('สถานะอื่นๆ'));
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ยกเลิกแล้ว'),
        );
        expect(find.text('สถานะ: ยกเลิกแล้ว'), findsWidgets);
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ทั้งหมด').first,
        );

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('ผู้ใช้'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('user-search-field')),
          'ไม่มีคนนี้แน่นอน',
        );
        await tester.pumpAndSettle();
        expect(
          find.text('ไม่พบบัญชีผู้ใช้ที่ตรงกับเงื่อนไข'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('ล้างคำค้นหา'));
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.widgetWithText(ChoiceChip, 'ผู้เช่า'));
        await tester.enterText(
          find.byKey(const ValueKey('user-search-field')),
          'มินท์ กมลวรรณ',
        );
        await tester.pumpAndSettle();
        await scrollToAndTap(tester, find.byType(Switch).first);
        await scrollToAndTap(tester, find.byType(Switch).first);
        verify(() => mocks.auth.toggleUserAsync(any())).called(2);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '5. Load failure displays retry banner and tapping retry clears syncError',
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
      '6. System back (PopScope), route back from Confirmation -> Reserve -> Home & clean logout work',
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
  });
}
