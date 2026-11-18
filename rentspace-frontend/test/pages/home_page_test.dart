import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/ui/booking_pages.dart';
import 'package:rentspace/ui/common.dart';
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
        expect(fieldByLabel('เบอร์โทรศัพท์'), findsOneWidget);
        expect(find.text('เบอร์โทรศัพท์ (ไม่บังคับ)'), findsNothing);

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

        expect(find.text('ประวัติการดำเนินการล่าสุด'), findsOneWidget);
        expect(find.text('ยังไม่มีประวัติการดำเนินการ'), findsOneWidget);
        store.logs.add(
          AuditEntry(
            mockClockNow,
            'admin01',
            'APPROVE_SPACE: อนุมัติพื้นที่ #2001',
          ),
        );
        store.notify();
        await tester.pumpAndSettle();
        expect(find.text('APPROVE_SPACE: อนุมัติพื้นที่ #2001'), findsOneWidget);
        expect(find.textContaining('โดย admin01'), findsOneWidget);

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

    testWidgets(
      '7. Renter filter reset, urgent booking banner, booking tabs/status sheet, booking card nav, and ProfilePanel password toggle/save',
      (tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1002');
        final mocks = ControllerBundle(store);
        when(() => mocks.auth.restoreSessionAsync()).thenAnswer((_) async => null);
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

        // Filter sheet: choose sort option then tap ล้างค่าทั้งหมด
        await tester.tap(find.byKey(const ValueKey('open-filter-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sort-priceAsc')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ล้างค่าทั้งหมด'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.text('ล้างตัวกรอง'), findsNothing);

        // Bookings tab: urgent banner 'ดำเนินการ' -> BookingPage -> back home
        await tester.tap(find.text('การจอง').last);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'ดำเนินการ'));
        await tester.pumpAndSettle();
        expect(find.byType(BookingPage), findsOneWidget);
        await tester.tap(find.byTooltip('กลับหน้าหลัก'));
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);

        // Switch TabStrip ('ประวัติ' -> 'ทั้งหมด' -> 'กำลังดำเนินการ')
        await tester.tap(find.textContaining('ประวัติ ('));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('ทั้งหมด ('));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('กำลังดำเนินการ ('));
        await tester.pumpAndSettle();

        // Status filter bottom sheet + 'ล้าง' reset button
        await tester.tap(find.byKey(const ValueKey('booking-status-filter-btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'รอเจ้าของอนุมัติ'));
        await tester.pumpAndSettle();
        expect(find.text('สถานะ: รอเจ้าของอนุมัติ'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'ล้าง'));
        await tester.pumpAndSettle();
        expect(find.text('ตัวกรองสถานะ'), findsOneWidget);

        // Tap booking card opens BookingPage -> return home
        await tester.tap(find.text('ห้องประชุมสว่างใจ').first);
        await tester.pumpAndSettle();
        expect(find.byType(BookingPage), findsOneWidget);
        await tester.tap(find.byTooltip('กลับหน้าหลัก'));
        await tester.pumpAndSettle();

        // Profile tab: toggle password visibility & change password error/success
        await tester.tap(find.text('โปรไฟล์').last);
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.byTooltip('แสดงรหัสผ่าน'));
        expect(find.byTooltip('ซ่อนรหัสผ่าน'), findsOneWidget);

        await scrollToAndTap(tester, find.text('บันทึกรหัสผ่านใหม่'));
        expect(find.text('กรุณากรอกรหัสผ่านปัจจุบัน'), findsOneWidget);
        await dismissSnackBars(tester);

        await scrollToAndEnter(tester, fieldByLabel('รหัสผ่านปัจจุบัน'), 'oldpass123');
        await scrollToAndEnter(
          tester,
          fieldByLabel('รหัสผ่านใหม่ (อย่างน้อย 8 ตัวอักษร)'),
          'newpass123',
        );
        await scrollToAndEnter(tester, fieldByLabel('ยืนยันรหัสผ่านใหม่'), 'newpass123');
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
      '8. Owner urgent complete chip, inline booking approve/reject/complete buttons, and CalendarDatePicker day selection',
      (tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1001');
        final mocks = ControllerBundle(store);
        when(() => mocks.auth.restoreSessionAsync()).thenAnswer((_) async => null);
        when(() => mocks.booking.completeAsync('3001')).thenAnswer((_) async {});
        when(
          () => mocks.booking.ownerReviewAsync('3003', true, ''),
        ).thenAnswer((_) async {});
        when(
          () => mocks.booking.ownerReviewAsync('3003', false, 'ห้องไม่พร้อมใช้งาน'),
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

        // Urgent chip jumps to Bookings filtered to confirmed -> inline completeAsync
        await scrollToAndTap(tester, find.text('รอกดยืนยันจบงาน (1)'));
        await scrollToAndTap(tester, find.text('ยืนยันจบงาน (ใช้บริการแล้ว)'));
        verify(() => mocks.booking.completeAsync('3001')).called(1);
        store.booking('3001').status = BookingStatus.completed;
        store.notify();
        await tester.pumpAndSettle();
        await dismissSnackBars(tester);

        // Reset filter to see ownerReview booking 3003 inline approve/reject
        await tester.tap(find.widgetWithText(TextButton, 'ล้าง'));
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.text('อนุมัติคำขอ').first);
        verify(() => mocks.booking.ownerReviewAsync('3003', true, '')).called(1);
        await dismissSnackBars(tester);

        await scrollToAndTap(tester, find.text('ปฏิเสธคำขอ').first);
        await submitReasonDialog(tester, 'ห้องไม่พร้อมใช้งาน');
        verify(
          () => mocks.booking.ownerReviewAsync(
            '3003',
            false,
            'ห้องไม่พร้อมใช้งาน',
          ),
        ).called(1);
        await dismissSnackBars(tester);

        // Switch to ปฏิทิน tab and select day 20 on CalendarDatePicker
        await scrollToAndTap(tester, find.text('ปฏิทิน'));
        expect(find.byType(CalendarDatePicker), findsOneWidget);
        await scrollToAndTap(tester, find.text('20'));
        expect(find.text('รายการวันที่ 20/11/2569'), findsOneWidget);

        await scrollToAndTap(tester, find.text('ประวัติ'));

        await unmountApp(tester);
      },
    );

    testWidgets(
      '9. Admin urgent chips, moderation reject/all-spaces chips/suspend, quick slip close/reject, finance chips/copy/payout, and user role chips/copy',
      (tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1003');
        store.user('1001').bankInfo = 'KBANK 777-8-99999-0';
        final mocks = ControllerBundle(store);
        when(() => mocks.auth.restoreSessionAsync()).thenAnswer((_) async => null);
        when(
          () => mocks.space.reviewAsync('2005', false, 'ข้อมูลไม่ครบ'),
        ).thenAnswer((_) async {});
        when(
          () => mocks.space.suspendSpaceAsync('2001', 'ฝ่าฝืนข้อกำหนด'),
        ).thenAnswer((_) async {});
        when(
          () => mocks.payment.reviewAsync('3005', false, 'ยอดเงินไม่ถูกต้อง'),
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

        // Dashboard urgent chips
        await scrollToAndTap(tester, find.text('สลิปรอตรวจ (1)'));
        expect(find.text('การจองและการเงิน'), findsOneWidget);
        await tester.tap(find.text('ภาพรวม').last);
        await tester.pumpAndSettle();
        await scrollToAndTap(tester, find.text('รอโอนให้เจ้าของ (1)'));
        expect(find.text('การจองและการเงิน'), findsOneWidget);

        // Moderation tab: reject pending space 2005, filter all-spaces chips, suspend 2001
        await tester.tap(find.text('ตรวจสอบ').last);
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.text('ปฏิเสธประกาศ').first);
        await submitReasonDialog(tester, 'ข้อมูลไม่ครบ');
        verify(
          () => mocks.space.reviewAsync('2005', false, 'ข้อมูลไม่ครบ'),
        ).called(1);
        await dismissSnackBars(tester);

        await scrollToAndTap(tester, find.textContaining('พื้นที่ทั้งหมด ('));
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'เปิดใช้งาน (2)'),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ถูกระงับ (1)'),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'รอตรวจ (1)'),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ทั้งหมด (4)'),
        );

        await scrollToAndTap(tester, find.text('ระงับประกาศ').first);
        await submitReasonDialog(tester, 'ฝ่าฝืนข้อกำหนด');
        verify(
          () => mocks.space.suspendSpaceAsync('2001', 'ฝ่าฝืนข้อกำหนด'),
        ).called(1);
        await dismissSnackBars(tester);

        // Finance tab: StatTiles, ChoiceChips, สถานะอื่นๆ sheet, quick slip close/reject, copy bank, payout dialog cancel
        await tester.tap(find.text('การเงิน').last);
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.text('สลิปรอตรวจ'));
        await scrollToAndTap(tester, find.widgetWithText(ChoiceChip, 'ทั้งหมด'));
        await scrollToAndTap(tester, find.text('รอโอนให้เจ้าของ'));
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'รอตรวจสลิป (1)'),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'รอจ่ายเจ้าของ (1)'),
        );

        await scrollToAndTap(tester, find.text('สถานะอื่นๆ'));
        await tester.tap(find.widgetWithText(ChoiceChip, 'เสร็จสิ้น').last);
        await tester.pumpAndSettle();
        await scrollToAndTap(tester, find.widgetWithText(ChoiceChip, 'ทั้งหมด'));

        // Quick Slip Dialog: 'ปิด' then reopen -> 'ปฏิเสธสลิป'
        await scrollToAndTap(tester, find.text('ตรวจสลิปด่วน'));
        await tester.tap(find.widgetWithText(TextButton, 'ปิด'));
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.text('ตรวจสลิปด่วน'));
        await tester.tap(find.text('ปฏิเสธสลิป'));
        await tester.pumpAndSettle();
        await submitReasonDialog(tester, 'ยอดเงินไม่ถูกต้อง');
        verify(
          () => mocks.payment.reviewAsync('3005', false, 'ยอดเงินไม่ถูกต้อง'),
        ).called(1);
        await dismissSnackBars(tester);

        // Finance card bank copy InkWell + quick payout open & cancel
        await scrollToAndTap(
          tester,
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is Icon &&
                    widget.icon == Icons.copy_outlined &&
                    widget.size == 13,
              )
              .first,
        );
        expect(lastMockClipboard, 'KBANK 777-8-99999-0');
        await dismissSnackBars(tester);

        await scrollToAndTap(tester, find.textContaining('โอนให้เจ้าของ ('));
        expect(find.byKey(const ValueKey('payout-confirm-btn')), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'ยกเลิก'));
        await tester.pumpAndSettle();

        // Users tab: role ChoiceChips + owner bank copy
        await tester.tap(find.text('ผู้ใช้').last);
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.widgetWithText(ChoiceChip, 'ผู้เช่า'));
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ผู้ดูแลระบบ'),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'เจ้าของพื้นที่'),
        );
        lastMockClipboard = null;
        await scrollToAndTap(tester, find.byIcon(Icons.copy_outlined).first);
        expect(lastMockClipboard, 'KBANK 777-8-99999-0');
        await dismissSnackBars(tester);

        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ทุกบทบาท'),
        );

        await unmountApp(tester);
      },
    );

    testWidgets(
      '10. Dashboard StatTiles (Owner & Admin), card-body taps (Explore/Earnings/Finance), and remaining FilterSheet chips',
      (tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        // Part A: Renter FilterSheet remaining chips + tapping SpaceCard body directly
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
        await scrollToAndTap(tester, find.widgetWithText(ChoiceChip, 'ทุกราคา'));
        await scrollToAndTap(tester, find.widgetWithText(ChoiceChip, 'ทุกความจุ'));
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

        // Part B: Owner Dashboard 4 StatTiles & Earnings completed card tap
        final ownerStore = createMockStore(viewerId: '1001');
        final ownerMocks = ControllerBundle(ownerStore);
        when(
          () => ownerMocks.auth.restoreSessionAsync(),
        ).thenAnswer((_) async => null);

        await tester.pumpWidget(
          RentSpaceApp(
            store: ownerStore,
            authController: ownerMocks.auth,
            spaceController: ownerMocks.space,
            bookingController: ownerMocks.booking,
            paymentController: ownerMocks.payment,
          ),
        );
        await tester.pumpAndSettle();

        for (final (tileLabel, expectedHeading) in [
          ('พื้นที่', 'พื้นที่ของฉัน'),
          ('คำขอรออนุมัติ', 'สถานะ: รอเจ้าของอนุมัติ'),
          ('คิวจองที่ยืนยันแล้ว', 'สถานะ: ยืนยันแล้ว'),
          ('รายรับสุทธิที่เสร็จสิ้น', 'รายรับและการจ่าย'),
        ]) {
          await scrollToAndTap(
            tester,
            find.descendant(
              of: find.byType(StatTile),
              matching: find.text(tileLabel),
            ),
          );
          expect(find.textContaining(expectedHeading), findsWidgets);
          if (tileLabel != 'รายรับสุทธิที่เสร็จสิ้น') {
            await tester.tap(
              find.descendant(
                of: find.byType(NavigationBar),
                matching: find.text('ภาพรวม'),
              ),
            );
            await tester.pumpAndSettle();
          }
        }

        // On Owner Earnings tab -> tap completed card body -> opens BookingPage
        await scrollToAndTap(
          tester,
          find.text('The Quiet Nook (ห้องอ่านหนังสือ)').first,
        );
        expect(find.byType(BookingPage), findsOneWidget);
        await tester.tap(find.byTooltip('กลับหน้าหลัก'));
        await tester.pumpAndSettle();

        await unmountApp(tester);

        // Part C: Admin Dashboard 4 StatTiles & Finance booking card tap
        final adminStore = createMockStore(viewerId: '1003');
        final adminMocks = ControllerBundle(adminStore);
        when(
          () => adminMocks.auth.restoreSessionAsync(),
        ).thenAnswer((_) async => null);

        await tester.pumpWidget(
          RentSpaceApp(
            store: adminStore,
            authController: adminMocks.auth,
            spaceController: adminMocks.space,
            bookingController: adminMocks.booking,
            paymentController: adminMocks.payment,
          ),
        );
        await tester.pumpAndSettle();

        for (final (tileLabel, expectedMarker) in [
          ('พื้นที่', 'อนุมัติประกาศพื้นที่ รายงานปัญหา และระงับประกาศ'),
          ('คำขอรออนุมัติ', 'สถานะ: รอเจ้าของอนุมัติ'),
          ('สลิปรอตรวจ', 'การจองและการเงิน'),
          ('รายรับสุทธิที่เสร็จสิ้น', 'การจองและการเงิน'),
        ]) {
          await scrollToAndTap(
            tester,
            find.descendant(
              of: find.byType(StatTile),
              matching: find.text(tileLabel),
            ),
          );
          expect(find.textContaining(expectedMarker), findsWidgets);
          if (tileLabel != 'รายรับสุทธิที่เสร็จสิ้น') {
            await tester.tap(
              find.descendant(
                of: find.byType(NavigationBar),
                matching: find.text('ภาพรวม'),
              ),
            );
            await tester.pumpAndSettle();
          }
        }

        expect(find.text('รอเจ้าของอนุมัติ'), findsNothing);
        await scrollToAndTap(
          tester,
          find.text('The Quiet Nook (ห้องอ่านหนังสือ)').first,
        );
        expect(find.byType(BookingPage), findsOneWidget);
        await tester.tap(find.byTooltip('กลับหน้าหลัก'));
        await tester.pumpAndSettle();

        await unmountApp(tester);
      },
    );
  });
}
