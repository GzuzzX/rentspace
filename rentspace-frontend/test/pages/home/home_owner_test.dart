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

  group('HomePage — Owner Role (Mocktail)', () {
    testWidgets(
      '1. Logging in as Owner shows exact NavigationBar menus & clean logout',
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

        await tester.enterText(fieldByLabel('อีเมล'), 'owner01@rentspace.test');
        await tester.enterText(
          fieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'password',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
        await tester.pumpAndSettle();

        expect(find.byType(HomePage), findsOneWidget);
        for (final tabLabel in [
          'ภาพรวม',
          'พื้นที่',
          'การจอง',
          'รายรับ',
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
          () => mocks.auth.loginAsync('owner01@rentspace.test', 'password'),
        ).called(1);
        verify(() => mocks.auth.logoutAsync()).called(1);
        await unmountApp(tester);
      },
    );

    testWidgets(
      '2. Owner dashboard missing bank warning, urgent chips, calendar & payout clipboard work via MockAuthController',
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
        expect(
          find.text('คำขอรออนุมัติ ($pendingReviewCount)'),
          findsOneWidget,
        );
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
      '3. Owner urgent complete chip, inline booking approve/reject/complete buttons, and CalendarDatePicker day selection',
      (tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1001');
        final mocks = ControllerBundle(store);
        when(
          () => mocks.auth.restoreSessionAsync(),
        ).thenAnswer((_) async => null);
        when(
          () => mocks.booking.completeAsync('3001'),
        ).thenAnswer((_) async {});
        when(
          () => mocks.booking.ownerReviewAsync('3003', true, ''),
        ).thenAnswer((_) async {});
        when(
          () => mocks.booking.ownerReviewAsync(
            '3003',
            false,
            'ห้องไม่พร้อมใช้งาน',
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

        await scrollToAndTap(tester, find.text('รอกดยืนยันจบงาน (1)'));
        await scrollToAndTap(tester, find.text('ยืนยันจบงาน (ใช้บริการแล้ว)'));
        verify(() => mocks.booking.completeAsync('3001')).called(1);
        store.booking('3001').status = BookingStatus.completed;
        store.notify();
        await tester.pumpAndSettle();
        await dismissSnackBars(tester);

        await tester.tap(find.widgetWithText(TextButton, 'ล้าง'));
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.text('อนุมัติคำขอ').first);
        verify(
          () => mocks.booking.ownerReviewAsync('3003', true, ''),
        ).called(1);
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

        await scrollToAndTap(tester, find.text('ปฏิทิน'));
        expect(find.byType(CalendarDatePicker), findsOneWidget);
        await scrollToAndTap(tester, find.text('20'));
        expect(find.text('รายการวันที่ 20/11/2569'), findsOneWidget);

        await scrollToAndTap(tester, find.text('ประวัติ'));

        await unmountApp(tester);
      },
    );

    testWidgets(
      '4. Owner Dashboard 4 StatTiles and Earnings completed card tap opens BookingPage',
      (tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

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
