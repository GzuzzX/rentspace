import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/services/api_client.dart';
import 'package:rentspace/ui/booking_pages.dart';
import 'package:rentspace/ui/home_page.dart';

import '../fixtures/mock_controllers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerMockControllerFallbacks();
    await setupTestChannels();
  });

  group('ReservePage & BookingConfirmationPage (Mocktail)', () {
    testWidgets(
      '1. Selecting date, hours & attendees leads to confirmation, handles 409 conflict then succeeds via MockBookingController',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1002');
        final targetSpace = store.space('2001');
        final mocks = ControllerBundle(store);
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
        ).thenAnswer((inv) async {
          attemptCount++;
          if (attemptCount == 1) {
            throw ApiError('ช่วงเวลานี้มีการจองแล้ว', 409);
          }
          final createdBooking =
              Booking(
                  id: '3999',
                  spaceId: inv.positionalArguments[0] as String,
                  ownerId: targetSpace.ownerId,
                  renterId: '1002',
                  spaceName: targetSpace.name,
                  date: inv.positionalArguments[1] as DateTime,
                  startMinutes: inv.positionalArguments[2] as int,
                  endMinutes: inv.positionalArguments[3] as int,
                  rentAmount: targetSpace.price * 2,
                  days: inv.namedArguments[#days] as int,
                  attendees: inv.namedArguments[#attendees] as int,
                  zone: inv.namedArguments[#zone] as String,
                  renterNote: inv.namedArguments[#renterNote] as String,
                  status: BookingStatus.ownerReview,
                )
                ..createdAt = mockClockNow;
          store.bookings.insert(0, createdBooking);
          store.notify();
          return createdBooking;
        });

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th', 'TH'),
            supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
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

        await scrollToAndTap(tester, find.byIcon(Icons.calendar_month));
        await scrollToAndTap(tester, find.text('17'));
        await scrollToAndTap(tester, find.text('ตกลง'));

        await scrollToAndTap(tester, find.byKey(const ValueKey('slot-780-840')));
        await scrollToAndTap(tester, find.byKey(const ValueKey('slot-840-900')));
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
            any(),
            780,
            900,
            days: 1,
            attendees: 2,
            zone: any(named: 'zone'),
            renterNote: any(named: 'renterNote'),
          ),
        ).called(2);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '2. Renter exercises multi-day, time dialogs, attendees, zone, note prompts, missing phone edit & back home',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1004');
        store.currentUser!.phone = '';
        final mocks = ControllerBundle(store);
        var attemptCount = 0;

        when(
          () => mocks.space.reportAsync(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => mocks.auth.updateProfileAsync(any(), any(), any(), any()),
        ).thenAnswer((inv) async {
          final currentRenter = store.currentUser!;
          currentRenter.name = inv.positionalArguments[0] as String;
          currentRenter.email = inv.positionalArguments[1] as String;
          currentRenter.phone = inv.positionalArguments[2] as String;
          store.notify();
        });
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
          attemptCount++;
          if (attemptCount == 1) {
            throw ApiError('ช่วงเวลานี้มีการจองแล้ว', 409);
          }
          final bookedSpace = store.space(inv.positionalArguments[0] as String);
          final createdBooking =
              Booking(
                  id: '4001',
                  spaceId: bookedSpace.id,
                  ownerId: bookedSpace.ownerId,
                  renterId: '1004',
                  spaceName: bookedSpace.name,
                  date: inv.positionalArguments[1] as DateTime,
                  startMinutes: inv.positionalArguments[2] as int,
                  endMinutes: inv.positionalArguments[3] as int,
                  rentAmount: bookedSpace.price * 2,
                  days: inv.namedArguments[#days] as int,
                  attendees: inv.namedArguments[#attendees] as int,
                  zone: inv.namedArguments[#zone] as String,
                  renterNote: inv.namedArguments[#renterNote] as String,
                  status: BookingStatus.ownerReview,
                )
                ..createdAt = mockClockNow;
          store.bookings.insert(0, createdBooking);
          store.notify();
          return createdBooking;
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
          find.widgetWithText(FilledButton, 'ดูรายละเอียดและจอง').first,
        );
        expect(find.byType(ReservePage), findsOneWidget);

        await scrollToAndTap(tester, find.byIcon(Icons.calendar_month));
        await scrollToAndTap(tester, find.text('17'));
        await scrollToAndTap(tester, find.text('ตกลง'));

        await scrollToAndTap(tester, find.text('เหมาหลายวัน (ต่อเนื่อง)'));
        await scrollToAndTap(tester, find.byKey(const ValueKey('days-preset-3')));
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

        await scrollToAndTap(tester, find.byKey(const ValueKey('slot-780-840')));
        await scrollToAndTap(tester, find.byKey(const ValueKey('slot-840-900')));

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
        await scrollToAndTap(tester, find.byKey(const ValueKey('slot-780-840')));

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
        await scrollToAndTap(tester, find.widgetWithText(FilledButton, 'บันทึก'));
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
        await unmountApp(tester);
      },
    );
  });
}
