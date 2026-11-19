import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/ui/booking_pages.dart';
import 'package:rentspace/ui/common.dart';
import 'package:rentspace/ui/home_page.dart';
import 'package:rentspace/ui/login_page.dart';

import '../../fixtures/mock_controllers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerMockControllerFallbacks();
    await setupTestChannels();
  });

  group('HomePage — Admin Role (Mocktail)', () {
    testWidgets(
      '1. Logging in as Admin shows exact NavigationBar menus & clean logout',
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

        await tester.enterText(fieldByLabel('อีเมล'), 'admin01@rentspace.test');
        await tester.enterText(
          fieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'password',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
        await tester.pumpAndSettle();

        expect(find.byType(HomePage), findsOneWidget);
        for (final tabLabel in [
          'ภาพรวม',
          'ตรวจสอบ',
          'การเงิน',
          'ผู้ใช้',
          'โปรไฟล์',
        ]) {
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
          () => mocks.auth.loginAsync('admin01@rentspace.test', 'password'),
        ).called(1);
        verify(() => mocks.auth.logoutAsync()).called(1);
        await unmountApp(tester);
      },
    );

    testWidgets(
      '2. Admin dashboard moderates spaces, closes issues, filters finance & toggles users via Mocktail',
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
        if (!store.spaces.any(
          (entry) => entry.status == SpaceStatus.rejected,
        )) {
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
        when(() => mocks.space.reviewAsync(any(), any(), any())).thenAnswer((
          inv,
        ) async {
          final targetSpace = store.space(inv.positionalArguments[0] as String);
          final approve = inv.positionalArguments[1] as bool;
          targetSpace.status = approve
              ? SpaceStatus.approved
              : SpaceStatus.rejected;
          targetSpace.reviewReason = inv.positionalArguments[2] as String;
          store.notify();
        });
        when(() => mocks.space.closeIssueAsync(any(), any())).thenAnswer((
          inv,
        ) async {
          final issue = store.issues.firstWhere(
            (entry) => entry.id == inv.positionalArguments[0] as String,
          );
          issue.closed = true;
          issue.resolution = inv.positionalArguments[1] as String;
          store.notify();
        });
        when(() => mocks.space.activateSpaceAsync(any())).thenAnswer((
          inv,
        ) async {
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
        expect(
          find.text('APPROVE_SPACE: อนุมัติพื้นที่ #2001'),
          findsOneWidget,
        );
        expect(find.textContaining('โดย admin01'), findsOneWidget);

        await scrollToAndTap(tester, find.text('ประกาศรอตรวจ ($pendingCount)'));
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
        expect(find.text('ไม่พบบัญชีผู้ใช้ที่ตรงกับเงื่อนไข'), findsOneWidget);
        await tester.tap(find.byTooltip('ล้างคำค้นหา'));
        await tester.pumpAndSettle();

        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ผู้เช่า'),
        );
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
      '3. Admin urgent chips, moderation reject/all-spaces chips/suspend, quick slip close/reject, finance chips/copy/payout, and user role chips/copy',
      (tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1003');
        store.user('1001').bankInfo = 'KBANK 777-8-99999-0';
        final mocks = ControllerBundle(store);
        when(
          () => mocks.auth.restoreSessionAsync(),
        ).thenAnswer((_) async => null);
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

        await scrollToAndTap(tester, find.text('สลิปรอตรวจ (1)'));
        expect(find.text('การจองและการเงิน'), findsOneWidget);
        await tester.tap(find.text('ภาพรวม').last);
        await tester.pumpAndSettle();
        await scrollToAndTap(tester, find.text('รอโอนให้เจ้าของ (1)'));
        expect(find.text('การจองและการเงิน'), findsOneWidget);

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

        await tester.tap(find.text('การเงิน').last);
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.text('สลิปรอตรวจ'));
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ทั้งหมด'),
        );
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
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ทั้งหมด'),
        );

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
        expect(
          find.byKey(const ValueKey('payout-confirm-btn')),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'ยกเลิก'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('ผู้ใช้').last);
        await tester.pumpAndSettle();

        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'ผู้เช่า'),
        );
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
      '4. Admin Dashboard 4 StatTiles and Finance booking card tap opens BookingPage',
      (tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

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
