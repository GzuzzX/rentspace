import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/controllers/payment_controller.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/ui/booking_pages.dart';
import 'package:rentspace/ui/common.dart';
import 'package:rentspace/ui/home_page.dart';

import '../fixtures/mock_controllers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerMockControllerFallbacks();
    await setupTestChannels();
  });

  group('BookingPage, SlipPage & Admin Payout (Mocktail)', () {
    testWidgets(
      '1. Action buttons reflect booking status & role across ownerReview, confirmed, admin cancel & ownerRejected',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1002');
        final reviewBooking = findBookingByStatus(
          store,
          status: BookingStatus.ownerReview,
          spaceId: '2001',
          renterId: '1002',
        );
        final pastConfirmedBooking = findBookingByStatus(
          store,
          status: BookingStatus.confirmed,
          preferredId: '3001',
          spaceId: '2001',
        );
        final futureConfirmedBooking = findBookingByStatus(
          store,
          status: BookingStatus.confirmed,
          preferredId: '3002',
          spaceId: '2002',
        );
        final rejectedBooking = findBookingByStatus(
          store,
          status: BookingStatus.ownerRejected,
          preferredId: '3020',
          spaceId: '2001',
        );

        final mocks = ControllerBundle(store);
        when(
          () => mocks.booking.ownerReviewAsync(reviewBooking.id, true, ''),
        ).thenAnswer((_) async {
          reviewBooking.status = BookingStatus.paymentDue;
          reviewBooking.approvedAt = mockClockNow;
          store.notify();
        });
        when(
          () => mocks.booking.completeAsync(pastConfirmedBooking.id),
        ).thenAnswer((_) async {
          pastConfirmedBooking.status = BookingStatus.completed;
          pastConfirmedBooking.completedAt = mockClockNow;
          store.notify();
        });
        when(
          () => mocks.booking.cancelAsync(futureConfirmedBooking.id, any()),
        ).thenAnswer((inv) async {
          futureConfirmedBooking.status = BookingStatus.canceled;
          futureConfirmedBooking.reason = inv.positionalArguments[1] as String;
          store.notify();
        });

        await tester.pumpWidget(
          MaterialApp(
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
        expect(find.text('ปฏิเสธคำขอ'), findsNothing);
        expect(find.text('ทำเครื่องหมายว่าใช้บริการแล้ว'), findsNothing);

        store.currentUser = store.user('1001');
        store.notify();
        await tester.pumpAndSettle();

        expect(find.text('อนุมัติคำขอ'), findsOneWidget);
        expect(find.text('ปฏิเสธคำขอ'), findsOneWidget);
        expect(find.text('ยกเลิกคำขอ'), findsNothing);

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'อนุมัติคำขอ'),
        );
        verify(
          () => mocks.booking.ownerReviewAsync(reviewBooking.id, true, ''),
        ).called(1);
        expect(find.text('รอชำระเงิน'), findsOneWidget);

        await unmountApp(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: BookingPage(
              store: store,
              bookingId: futureConfirmedBooking.id,
              bookingController: mocks.booking,
              paymentController: mocks.payment,
              spaceController: mocks.space,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final earlyBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ทำเครื่องหมายว่าใช้บริการแล้ว'),
        );
        expect(earlyBtn.onPressed, isNull);

        store.currentUser = store.user('1003');
        store.notify();
        await tester.pumpAndSettle();
        await scrollToAndTap(
          tester,
          find.widgetWithText(TextButton, 'Admin ยกเลิกการจอง'),
        );
        await submitReasonDialog(tester, 'แอดมินยกเลิกตามคำขอ');
        expect(futureConfirmedBooking.status, BookingStatus.canceled);

        store.currentUser = store.user('1001');
        store.notify();
        await unmountApp(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: BookingPage(
              store: store,
              bookingId: pastConfirmedBooking.id,
              bookingController: mocks.booking,
              paymentController: mocks.payment,
              spaceController: mocks.space,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ทำเครื่องหมายว่าใช้บริการแล้ว'),
        );
        verify(
          () => mocks.booking.completeAsync(pastConfirmedBooking.id),
        ).called(1);

        await unmountApp(tester);
        await tester.pumpWidget(
          MaterialApp(
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
        expect(find.text('ปฏิเสธคำขอ'), findsNothing);
        expect(find.text('ยกเลิกคำขอ'), findsNothing);
        expect(find.text('ทำเครื่องหมายว่าใช้บริการแล้ว'), findsNothing);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '2. Clipboard copy, Slip upload, Admin reject with reason, resubmit & slip zoom dialog work via MockPaymentController',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1002');
        final targetBooking = findBookingByStatus(
          store,
          status: BookingStatus.paymentDue,
          spaceId: '2001',
          renterId: '1002',
        );
        final targetBookingId = targetBooking.id;
        final mocks = ControllerBundle(store);
        final slipPickQueue = Queue<SlipPickResult>.from([
          (name: 'slip1.png', bytes: validMockPngBytes),
          (name: 'slip2.png', bytes: validMockPngBytes),
        ]);

        when(
          () => mocks.payment.submitAsync(any(), any(), any(), any()),
        ).thenAnswer((inv) async {
          targetBooking.slips.add(
            PaymentSlip(
              name: inv.positionalArguments[1] as String,
              bytes: inv.positionalArguments[2] as Uint8List,
              submittedAt: mockClockNow,
              note: inv.positionalArguments[3] as String,
            ),
          );
          targetBooking.status = BookingStatus.slipReview;
          store.notify();
        });
        when(
          () => mocks.payment.reviewAsync(
            targetBookingId,
            false,
            'สลิปเบลอ ยอดไม่ตรง',
          ),
        ).thenAnswer((_) async {
          targetBooking.status = BookingStatus.slipRejected;
          targetBooking.reason = 'สลิปเบลอ ยอดไม่ตรง';
          targetBooking.slipRejectedAt = mockClockNow;
          if (targetBooking.slips.isNotEmpty) {
            targetBooking.slips.last.rejectionReason = 'สลิปเบลอ ยอดไม่ตรง';
          }
          store.notify();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: BookingPage(
              store: store,
              bookingId: targetBookingId,
              pickSlip: (_) async =>
                  slipPickQueue.isEmpty ? null : slipPickQueue.removeFirst(),
              bookingController: mocks.booking,
              paymentController: mocks.payment,
              spaceController: mocks.space,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('copy-booking-id-btn')),
        );
        expect(lastMockClipboard, targetBookingId);
        await dismissSnackBars(tester);

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('copy-booking-evidence-btn')),
        );
        expect(lastMockClipboard, contains(targetBookingId));
        await dismissSnackBars(tester);

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('copy-account-btn')),
        );
        expect(lastMockClipboard, '000-0-00000-0');
        await dismissSnackBars(tester);

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'แนบ / ส่งสลิปใหม่'),
        );
        final firstSubmitBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ส่งสลิปเพื่อตรวจสอบ'),
        );
        expect(firstSubmitBtn.onPressed, isNull);

        await scrollToAndTap(
          tester,
          find.widgetWithText(OutlinedButton, 'เลือกภาพสลิป'),
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('หมายเหตุ (ไม่บังคับ)'),
          'โอนรอบแรกแล้ว',
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ส่งสลิปเพื่อตรวจสอบ'),
        );
        await dismissSnackBars(tester);

        store.currentUser = store.user('1003');
        store.notify();
        await tester.pumpAndSettle();

        await scrollToAndTap(
          tester,
          find.widgetWithText(OutlinedButton, 'ปฏิเสธสลิป'),
        );
        await submitReasonDialog(tester, 'สลิปเบลอ ยอดไม่ตรง');

        store.currentUser = store.user('1002');
        store.notify();
        await tester.pumpAndSettle();

        expect(find.textContaining('สลิปเบลอ ยอดไม่ตรง'), findsWidgets);

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'แนบ / ส่งสลิปใหม่'),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(OutlinedButton, 'เลือกภาพสลิป'),
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('หมายเหตุ (ไม่บังคับ)'),
          'ส่งสลิปใหม่ชัดแล้ว',
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ส่งสลิปเพื่อตรวจสอบ'),
        );
        await dismissSnackBars(tester);

        expect(targetBooking.slips.length, 2);
        await scrollToAndTap(tester, find.text('ประวัติสลิปก่อนหน้า (1 รายการ)'));

        await scrollToAndTap(tester, find.byType(SlipImage).first);
        expect(find.byIcon(Icons.close), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        verify(
          () => mocks.payment.submitAsync(any(), any(), any(), any()),
        ).called(2);
        verify(
          () => mocks.payment.reviewAsync(
            targetBookingId,
            false,
            'สลิปเบลอ ยอดไม่ตรง',
          ),
        ).called(1);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '3. Admin quick slip approval, payout dialog with slip & renter review flow call Mocktail controllers',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1003');
        final slipReviewBooking = findBookingByStatus(
          store,
          status: BookingStatus.slipReview,
          spaceId: '2001',
          renterId: '1002',
        );
        if (slipReviewBooking.slips.isEmpty) {
          slipReviewBooking.slips.add(
            PaymentSlip(
              name: 'quick_slip.png',
              bytes: validMockPngBytes,
              submittedAt: mockClockNow,
            ),
          );
        }
        final completedReviewBooking = findBookingByStatus(
          store,
          status: BookingStatus.completed,
          spaceId: '2002',
          renterId: '1002',
          requirePendingPayout: true,
        )..review = null;

        final mocks = ControllerBundle(store);
        when(
          () => mocks.payment.reviewAsync(slipReviewBooking.id, true, ''),
        ).thenAnswer((_) async {
          slipReviewBooking.status = BookingStatus.confirmed;
          slipReviewBooking.confirmedAt = mockClockNow;
          store.notify();
        });
        when(
          () => mocks.payment.payoutAsync(
            completedReviewBooking.id,
            fileName: any(named: 'fileName'),
            bytes: any(named: 'bytes'),
            note: any(named: 'note'),
          ),
        ).thenAnswer((inv) async {
          completedReviewBooking.paidOutAt = mockClockNow;
          completedReviewBooking.payoutSlip = PaymentSlip(
            name: inv.namedArguments[#fileName] as String,
            bytes: inv.namedArguments[#bytes] as Uint8List,
            submittedAt: mockClockNow,
            note: inv.namedArguments[#note] as String,
          );
          store.notify();
        });
        when(
          () => mocks.booking.submitReviewAsync(
            completedReviewBooking.id,
            4,
            'ห้องสะอาด บริการดีมาก',
          ),
        ).thenAnswer((_) async {
          completedReviewBooking.review = SpaceReview(
            rating: 4,
            comment: 'ห้องสะอาด บริการดีมาก',
            createdAt: mockClockNow,
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

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('การเงิน'),
          ),
        );
        await tester.pumpAndSettle();

        final slipReviewIndex = store.bookings
            .where((entry) => entry.status == BookingStatus.slipReview)
            .toList()
            .indexWhere((entry) => entry.id == slipReviewBooking.id);
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ตรวจสลิปด่วน').at(slipReviewIndex),
        );
        expect(
          find.text('ตรวจสลิปด่วน (#${slipReviewBooking.id})'),
          findsOneWidget,
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'อนุมัติสลิป'),
        );
        expect(slipReviewBooking.status, BookingStatus.confirmed);

        showAdminPayoutDialog(
          tester.element(find.byType(NavigationBar)),
          store: store,
          booking: completedReviewBooking,
          paymentController: mocks.payment,
          pickSlip: (_) async =>
              (name: 'payout_slip.png', bytes: validMockPngBytes),
        );
        await tester.pumpAndSettle();

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('payout-pick-slip-btn')),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('payout-clear-slip-btn')),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('payout-pick-slip-btn')),
        );
        await scrollToAndEnter(
          tester,
          find.byKey(const ValueKey('payout-note-field')),
          'โอนปิดยอด ${completedReviewBooking.id}',
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('payout-confirm-btn')),
        );
        await dismissSnackBars(tester);
        expect(completedReviewBooking.payoutSlip, isNotNull);

        await unmountApp(tester);

        store.currentUser = store.user('1002');
        await tester.pumpWidget(
          MaterialApp(
            home: BookingPage(
              store: store,
              bookingId: completedReviewBooking.id,
              bookingController: mocks.booking,
              paymentController: mocks.payment,
              spaceController: mocks.space,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('สลิปโอนเงินให้เจ้าของ (Admin)'), findsNothing);
        await scrollToAndTap(tester, find.byTooltip('4 ดาว'));
        await scrollToAndEnter(
          tester,
          fieldByLabel('ความคิดเห็นหลังใช้งาน'),
          'ห้องสะอาด บริการดีมาก',
        );
        await scrollToAndTap(tester, find.widgetWithText(FilledButton, 'ส่งรีวิว'));
        await dismissSnackBars(tester);

        expect(completedReviewBooking.review?.rating, 4);
        verify(
          () => mocks.booking.submitReviewAsync(
            completedReviewBooking.id,
            4,
            'ห้องสะอาด บริการดีมาก',
          ),
        ).called(1);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '4. Secondary BookingPage actions, bank info copy on InfoRow, and SlipPage null/invalid pick handling',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1002');
        store.user('1001').bankInfo = 'SCB 999-111-2222';
        final mocks = ControllerBundle(store);

        when(
          () => mocks.space.reportAsync(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => mocks.booking.cancelAsync('3003', any()),
        ).thenAnswer((_) async {});
        when(
          () => mocks.booking.ownerReviewAsync('3003', false, any()),
        ).thenAnswer((_) async {});
        when(
          () => mocks.payment.reviewAsync('3005', true, ''),
        ).thenAnswer((_) async {
          store.booking('3005').status = BookingStatus.confirmed;
          store.notify();
        });

        // 1) Renter opens RentSpaceApp -> การจอง tab -> taps card -> Home tooltip
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

        await scrollToAndTap(tester, find.text('ห้องประชุมสว่างใจ').first);
        expect(find.byType(BookingPage), findsOneWidget);
        await tester.tap(find.byTooltip('กลับหน้าหลัก'));
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);
        await unmountApp(tester);

        // 2) On BookingPage('3003'): Renter reports & cancels; Owner rejects
        await tester.pumpWidget(
          MaterialApp(
            home: BookingPage(
              store: store,
              bookingId: '3003',
              bookingController: mocks.booking,
              paymentController: mocks.payment,
              spaceController: mocks.space,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.text('แจ้งปัญหาการจอง'));
        await submitReasonDialog(tester, 'ติดต่อเจ้าของไม่ได้');
        verify(
          () => mocks.space.reportAsync('3003', 'ติดต่อเจ้าของไม่ได้'),
        ).called(1);
        await dismissSnackBars(tester);

        await scrollToAndTap(tester, find.text('ยกเลิกคำขอ'));
        await submitReasonDialog(tester, 'เปลี่ยนแผนการเดินทาง');
        verify(
          () => mocks.booking.cancelAsync('3003', 'เปลี่ยนแผนการเดินทาง'),
        ).called(1);
        await dismissSnackBars(tester);

        store.currentUser = store.user('1001');
        store.notify();
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.text('ปฏิเสธคำขอ'));
        await submitReasonDialog(tester, 'ห้องติดซ่อมบำรุง');
        verify(
          () => mocks.booking.ownerReviewAsync('3003', false, 'ห้องติดซ่อมบำรุง'),
        ).called(1);
        await dismissSnackBars(tester);
        await unmountApp(tester);

        // 3) Admin on 3005: copies bankInfo on InfoRow & approves slip; on 3006 opens payout dialog & cancels
        store.currentUser = store.user('1003');
        await tester.pumpWidget(
          MaterialApp(
            home: BookingPage(
              store: store,
              bookingId: '3005',
              bookingController: mocks.booking,
              paymentController: mocks.payment,
              spaceController: mocks.space,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.byIcon(Icons.copy_outlined).last);
        expect(lastMockClipboard, 'SCB 999-111-2222');
        await dismissSnackBars(tester);

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ตรวจแล้ว ยืนยันการจอง'),
        );
        verify(() => mocks.payment.reviewAsync('3005', true, '')).called(1);
        await dismissSnackBars(tester);
        await unmountApp(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: BookingPage(
              store: store,
              bookingId: '3006',
              bookingController: mocks.booking,
              paymentController: mocks.payment,
              spaceController: mocks.space,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกจ่ายเจ้าของ (แนบสลิป)'),
        );
        expect(find.text('ยืนยันบันทึกโอนเงินให้เจ้าของ'), findsOneWidget);
        await scrollToAndTap(tester, find.widgetWithText(TextButton, 'ยกเลิก'));
        verifyNever(
          () => mocks.payment.payoutAsync(
            any(),
            fileName: any(named: 'fileName'),
            bytes: any(named: 'bytes'),
            note: any(named: 'note'),
          ),
        );
        await unmountApp(tester);

        // 4) SlipPage with real PaymentController: 1st pick null, 2nd pick invalid.txt
        store.currentUser = store.user('1002');
        var pickCall = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: SlipPage(
              store: store,
              booking: store.booking('3004'),
              paymentController: PaymentController(store),
              pickSlip: (_) async {
                pickCall++;
                if (pickCall == 1) return null;
                return (name: 'invalid.txt', bytes: corruptMockImageBytes);
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await scrollToAndTap(
          tester,
          find.widgetWithText(OutlinedButton, 'เลือกภาพสลิป'),
        );
        final submitAfterNull = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ส่งสลิปเพื่อตรวจสอบ'),
        );
        expect(submitAfterNull.onPressed, isNull);

        await scrollToAndTap(
          tester,
          find.widgetWithText(OutlinedButton, 'เลือกภาพสลิป'),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ส่งสลิปเพื่อตรวจสอบ'),
        );
        expect(find.text('รองรับภาพ JPG และ PNG เท่านั้น'), findsOneWidget);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '5. Admin payout dialog copy/validation error and BookingPage missing/forbidden guards',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1003');
        store.user('1001').bankInfo = 'KBANK 777-888-9999';
        final completedBooking = store.booking('3006');

        // 1) showAdminPayoutDialog: copy bank account, pick bad.txt, confirm -> validation error, then cancel
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => showAdminPayoutDialog(
                    context,
                    store: store,
                    booking: completedBooking,
                    paymentController: PaymentController(store),
                    pickSlip: (_) async =>
                        (name: 'bad.txt', bytes: corruptMockImageBytes),
                  ),
                  child: const Text('Open Payout Dialog'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Payout Dialog'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('คัดลอกบัญชีรับเงิน'));
        await tester.pumpAndSettle();
        expect(lastMockClipboard, 'KBANK 777-888-9999');
        await dismissSnackBars(tester);

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('payout-pick-slip-btn')),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('payout-confirm-btn')),
        );
        expect(find.text('รองรับภาพ JPG และ PNG เท่านั้น'), findsOneWidget);
        expect(find.text('ยืนยันบันทึกโอนเงินให้เจ้าของ'), findsOneWidget);
        await dismissSnackBars(tester);

        await scrollToAndTap(tester, find.widgetWithText(TextButton, 'ยกเลิก'));
        expect(find.text('ยืนยันบันทึกโอนเงินให้เจ้าของ'), findsNothing);
        await unmountApp(tester);

        // 2) BookingPage with missing bookingId -> 'ไม่พบการจอง'
        await tester.pumpWidget(
          MaterialApp(
            home: BookingPage(store: store, bookingId: 'missing-booking-id'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('ไม่พบการจอง'), findsOneWidget);
        await unmountApp(tester);

        // 3) BookingPage with unauthorized user ('1004') -> 'ไม่มีสิทธิ์ดูรายการนี้'
        store.currentUser = store.user('1004');
        await tester.pumpWidget(
          MaterialApp(
            home: BookingPage(store: store, bookingId: '3003'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('ไม่มีสิทธิ์ดูรายการนี้'), findsOneWidget);
        await unmountApp(tester);
      },
    );
  });
}
