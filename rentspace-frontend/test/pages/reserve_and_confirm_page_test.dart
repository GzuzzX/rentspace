import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/controllers/booking_controller.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/services/api_client.dart';
import 'package:rentspace/ui/booking_pages.dart';
import 'package:rentspace/ui/home_page.dart';

import '../fixtures/mock_controllers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerMockControllerFallbacks);

  setUp(() async {
    await setupTestChannels();
  });

  group('ReservePage & BookingConfirmationPage (Mocktail)', () {
    testWidgets(
      '1. Selecting date, hours & attendees leads to confirmation, handles 409 conflict then succeeds via MockBookingController',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() async {
          await unmountApp(tester);
          resetMobileViewport(tester);
        });

        final store = createMockStore(viewerId: '1002');
        final targetSpace = store.space('2001');
        final mocks = ControllerBundle(store);
        final expectedDate = DateTime(
          mockClockNow.year,
          mockClockNow.month,
          mockClockNow.day + 1,
        );
        _stubConflictThenSuccess(
          mocks,
          store,
          bookingId: '3999',
          renterId: '1002',
        );

        await tester.pumpWidget(
          _localizedApp(
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

        await _selectCalendarDay(tester, '17');
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('slot-780-840')),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('slot-840-900')),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('attendees-increment')),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ส่งคำขอจอง'),
        );

        expect(find.byType(BookingConfirmationPage), findsOneWidget);

        await scrollToAndTap(
          tester,
          find.text('ฉันยอมรับเงื่อนไขการจองและกฎการใช้สถานที่'),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('confirm-booking-btn')),
        );
        expect(find.text('ช่วงเวลานี้มีการจองแล้ว'), findsOneWidget);
        await dismissSnackBars(tester);

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('confirm-booking-btn')),
        );
        expect(find.byType(BookingPage), findsOneWidget);
        expect(find.text('รหัสการจอง: 3999'), findsOneWidget);

        verify(
          () => mocks.booking.createAsync(
            '2001',
            expectedDate,
            780,
            900,
            days: 1,
            attendees: 2,
            zone: 'โซนหลัก (พื้นที่มาตรฐาน)',
            renterNote: '',
          ),
        ).called(2);
      },
    );

    testWidgets(
      '2. Renter exercises multi-day, time dialogs, attendees, zone, note prompts, missing phone edit & back home',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() async {
          await unmountApp(tester);
          resetMobileViewport(tester);
        });

        final store = createMockStore(viewerId: '1004');
        store.currentUser!.phone = '';
        final mocks = ControllerBundle(store);

        when(
          () => mocks.space.reportAsync(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => mocks.auth.updateProfileAsync(any(), any(), any(), any()),
        ).thenAnswer((invocation) async {
          final currentRenter = store.currentUser!;
          currentRenter.name = invocation.positionalArguments[0] as String;
          currentRenter.email = invocation.positionalArguments[1] as String;
          currentRenter.phone = invocation.positionalArguments[2] as String;
          store.notify();
        });
        _stubConflictThenSuccess(
          mocks,
          store,
          bookingId: '4001',
          renterId: '1004',
        );

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
          find.widgetWithText(FilledButton, 'ดูรายละเอียดและจอง').first,
        );
        expect(find.byType(ReservePage), findsOneWidget);

        await _selectCalendarDay(tester, '17');

        await scrollToAndTap(tester, find.text('เหมาหลายวัน (ต่อเนื่อง)'));
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('days-preset-3')),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('days-increment')),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('days-decrement')),
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(TextButton, 'ใช้เวลาเต็มวัน'),
        );
        await scrollToAndTap(tester, find.text('รายชั่วโมง (1 วัน)'));

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('slot-780-840')),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('slot-840-900')),
        );

        await scrollToAndTap(tester, find.text('เริ่ม 13:00'));
        await scrollToAndTap(
          tester,
          find.descendant(
            of: find.byType(SimpleDialog),
            matching: find.text('14:00'),
          ),
        );
        await scrollToAndTap(tester, find.text('สิ้นสุด 15:00'));
        await scrollToAndTap(
          tester,
          find.descendant(
            of: find.byType(SimpleDialog),
            matching: find.text('24:00'),
          ),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('slot-780-840')),
        );

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('attendees-increment')),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('attendees-decrement')),
        );
        final reserveWidget = tester.widget<ReservePage>(
          find.byType(ReservePage),
        );
        final presetTarget = reserveWidget.space.capacity >= 10
            ? (reserveWidget.space.capacity == 10 ||
                      reserveWidget.space.capacity == 20
                  ? 10
                  : reserveWidget.space.capacity)
            : reserveWidget.space.capacity;
        if (find
            .byKey(ValueKey('attendees-preset-$presetTarget'))
            .evaluate()
            .isNotEmpty) {
          await scrollToAndTap(
            tester,
            find.byKey(ValueKey('attendees-preset-$presetTarget')),
          );
        }

        await scrollToAndTap(tester, find.text('ห้องส่วนตัว / ประชุมย่อย'));
        await scrollToAndTap(tester, find.text('ขอโปรเจกเตอร์/จอภาพ'));

        await scrollToAndTap(tester, find.text('รายงานปัญหาพื้นที่'));
        await submitReasonDialog(tester, 'ทดสอบแจ้งปัญหาพื้นที่');
        expect(find.text('ส่งรายงานแล้ว'), findsOneWidget);
        await dismissSnackBars(tester);

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ส่งคำขอจอง'),
        );
        expect(find.byType(BookingConfirmationPage), findsOneWidget);

        await scrollToAndTap(
          tester,
          find.widgetWithText(TextButton, 'ระบุเบอร์'),
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('เบอร์โทรศัพท์'),
          '089-888-7777',
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'บันทึก'),
        );
        await dismissSnackBars(tester);

        await scrollToAndTap(
          tester,
          find.text('ฉันยอมรับเงื่อนไขการจองและกฎการใช้สถานที่'),
        );
        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('confirm-booking-btn')),
        );
        expect(find.text('ช่วงเวลานี้มีการจองแล้ว'), findsOneWidget);
        await dismissSnackBars(tester);

        await scrollToAndTap(
          tester,
          find.byKey(const ValueKey('confirm-booking-btn')),
        );
        expect(find.text('รายละเอียดการจอง'), findsOneWidget);
        expect(find.text('รหัสการจอง: 4001'), findsOneWidget);

        await tester.tap(find.byTooltip('กลับหน้าหลัก'));
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);

        verify(() => mocks.space.reportAsync(any(), any())).called(1);
        verify(
          () => mocks.auth.updateProfileAsync(
            any(),
            any(),
            '089-888-7777',
            any(),
          ),
        ).called(1);
      },
    );

    testWidgets(
      '3. Closed-day ReservePage disables submit button, shows busy warning, and BookingConfirmationPage back/dialog-cancel buttons work',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() async {
          await unmountApp(tester);
          resetMobileViewport(tester);
        });

        final store = createMockStore(viewerId: '1002');
        final closedSpace = store.space('2001');
        for (final dayHours in closedSpace.availability.days) {
          dayHours.open = false;
        }
        final targetDate = mockClockNow.add(const Duration(days: 1));
        store.busySlots.add({
          'space_id': '2001',
          'booking_date': targetDate.toIso8601String().substring(0, 10),
          'start_minutes': 600,
          'end_minutes': 720,
          'days_count': 1,
        });

        final mocks = ControllerBundle(store);
        await tester.pumpWidget(
          _localizedApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReservePage(
                          store: store,
                          space: closedSpace,
                          bookingController: mocks.booking,
                          spaceController: mocks.space,
                          authController: mocks.auth,
                        ),
                      ),
                    ),
                    child: const Text('เปิดหน้าจอง'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('เปิดหน้าจอง'));
        await tester.pumpAndSettle();

        expect(find.byType(ReservePage), findsOneWidget);
        expect(find.text('คิวจอง 10:00–12:00'), findsOneWidget);
        expect(find.text('ช่วงเวลานี้ไม่ว่าง / นอกเวลาเปิด'), findsOneWidget);

        final nextStepBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'ส่งคำขอจอง'),
        );
        expect(nextStepBtn.onPressed, isNull);

        await unmountApp(tester);
        await tester.pumpWidget(
          _localizedApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BookingConfirmationPage(
                          store: store,
                          space: store.space('2002'),
                          date: targetDate,
                          startMinute: 600,
                          endMinute: 720,
                          authController: mocks.auth,
                          bookingController: mocks.booking,
                          spaceController: mocks.space,
                        ),
                      ),
                    ),
                    child: const Text('ไปหน้ายืนยัน'),
                  ),
                ),
              ),
            ),
          ),
        );
        when(
          () => mocks.auth.updateProfileAsync(any(), any(), '', any()),
        ).thenThrow(
          DomainError('กรุณาระบุชื่อ อีเมล และเบอร์โทรศัพท์ที่ถูกต้อง'),
        );

        await tester.tap(find.text('ไปหน้ายืนยัน'));
        await tester.pumpAndSettle();

        expect(find.byType(BookingConfirmationPage), findsOneWidget);
        final disabledConfirmBtn = tester.widget<FilledButton>(
          find.byKey(const ValueKey('confirm-booking-btn')),
        );
        expect(disabledConfirmBtn.onPressed, isNull);

        await scrollToAndTap(tester, find.widgetWithText(TextButton, 'แก้ไข'));
        expect(find.text('แก้ไขข้อมูลผู้จอง'), findsOneWidget);
        await tester.enterText(fieldByLabel('เบอร์โทรศัพท์'), '');
        await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
        await tester.pumpAndSettle();
        expect(
          find.text('กรุณาระบุชื่อ อีเมล และเบอร์โทรศัพท์ที่ถูกต้อง'),
          findsOneWidget,
        );
        expect(find.text('แก้ไขข้อมูลผู้จอง'), findsOneWidget);
        await dismissSnackBars(tester);

        await tester.tap(find.widgetWithText(TextButton, 'ยกเลิก'));
        await tester.pumpAndSettle();
        expect(find.text('แก้ไขข้อมูลผู้จอง'), findsNothing);
        verify(
          () => mocks.auth.updateProfileAsync(any(), any(), '', any()),
        ).called(1);
        verifyNever(
          () => mocks.auth.updateProfileAsync(
            any(),
            any(),
            '081-234-5678',
            any(),
          ),
        );

        await tester.tap(find.byTooltip('ย้อนกลับ'));
        await tester.pumpAndSettle();
        expect(find.byType(BookingConfirmationPage), findsNothing);
      },
    );
  });
}

Widget _localizedApp({required Widget home}) => MaterialApp(
  locale: const Locale('th', 'TH'),
  supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

Future<void> _selectCalendarDay(WidgetTester tester, String dayLabel) async {
  await scrollToAndTap(tester, find.byIcon(Icons.calendar_month));
  await scrollToAndTap(tester, find.text(dayLabel));
  await scrollToAndTap(tester, find.text('ตกลง'));
}

void _stubConflictThenSuccess(
  ControllerBundle mocks,
  TestStore store, {
  required String bookingId,
  required String renterId,
}) {
  var attemptCount = 0;
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
  ).thenAnswer((invocation) async {
    attemptCount++;
    if (attemptCount == 1) {
      throw ApiError('ช่วงเวลานี้มีการจองแล้ว', 409);
    }

    final spaceId = invocation.positionalArguments[0] as String;
    final date = invocation.positionalArguments[1] as DateTime;
    final startMinutes = invocation.positionalArguments[2] as int;
    final endMinutes = invocation.positionalArguments[3] as int;
    final days = invocation.namedArguments[#days] as int;
    final attendees = invocation.namedArguments[#attendees] as int;
    final zone = invocation.namedArguments[#zone] as String;
    final renterNote = invocation.namedArguments[#renterNote] as String;
    final bookedSpace = store.space(spaceId);
    final createdBooking = Booking(
      id: bookingId,
      spaceId: bookedSpace.id,
      ownerId: bookedSpace.ownerId,
      renterId: renterId,
      spaceName: bookedSpace.name,
      date: date,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      rentAmount: BookingController.rent(
        bookedSpace.price,
        startMinutes,
        endMinutes,
        days: days,
      ),
      days: days,
      attendees: attendees,
      zone: zone,
      renterNote: renterNote,
      status: BookingStatus.ownerReview,
    )..createdAt = mockClockNow;
    store.bookings.insert(0, createdBooking);
    store.notify();
    return createdBooking;
  });
}
