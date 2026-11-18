import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/ui/booking_pages.dart';
import 'package:rentspace/ui/common.dart';
import 'package:rentspace/ui/space_form.dart';

import '../fixtures/mock_controllers.dart';

Future<void> _settleBrokenImageFrames(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerMockControllerFallbacks();
    await setupTestChannels();
  });

  group('Broken Image Fallback & Small Viewport Responsiveness (Mocktail)', () {
    testWidgets(
      '1. Broken memory & network images show fallbacks across SpaceImage, SlipImage & SpaceForm with zero crash',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1002');
        final brokenSpace = store.space('2001')
          ..image = ''
          ..imageBytes = corruptMockImageBytes;
        final brokenMemorySlip = PaymentSlip(
          name: 'broken.png',
          bytes: corruptMockImageBytes,
          submittedAt: mockClockNow,
        );
        final brokenNetworkSlip = PaymentSlip(
          name: 'missing.png',
          bytes: Uint8List(0),
          submittedAt: mockClockNow,
          imageUrl: 'https://invalid.example.invalid/missing.png',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SpaceImage(
                    brokenSpace,
                    height: 120,
                    width: 240,
                    fallback: const Text('ภาพพื้นที่สำรอง'),
                  ),
                  SlipImage(brokenMemorySlip, height: 120, width: 240),
                  SlipImage(brokenNetworkSlip, height: 120, width: 240),
                ],
              ),
            ),
          ),
        );
        await _settleBrokenImageFrames(tester);
        expect(find.text('ภาพพื้นที่สำรอง'), findsOneWidget);
        expect(find.text('ไม่สามารถเปิดภาพได้'), findsNWidgets(2));

        await unmountApp(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: SpaceForm(store: store, space: brokenSpace),
          ),
        );
        await _settleBrokenImageFrames(tester);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '2. Small viewport (360x740), open keyboard & very long Thai text cause zero overflow across pages',
      (WidgetTester tester) async {
        configureMobileViewport(
          tester,
          size: const Size(360, 740),
          viewInsets: const FakeViewPadding(bottom: 300),
        );
        addTearDown(() => resetMobileViewport(tester));

        final longThai = List.filled(
          16,
          'ทดสอบหน้าจอแคบคีย์บอร์ดเปิดข้อความยาว',
        ).join(' ');
        final store = createMockStore(viewerId: '1002');
        final longSpace = Space(
          id: '2888',
          ownerId: '1001',
          name: longThai,
          category: 'meeting_room',
          location: longThai,
          price: 650,
          capacity: 14,
          description: longThai,
          amenities: ['Wi-Fi', 'โปรเจกเตอร์'],
          status: SpaceStatus.approved,
        );
        store.spaces.add(longSpace);
        final rejectedBooking = findBookingByStatus(
          store,
          status: BookingStatus.ownerRejected,
          spaceId: '2001',
          renterId: '1002',
        );
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
        expect(tester.takeException(), isNull);

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'ดูรายละเอียดและจอง').last,
        );
        expect(tester.takeException(), isNull);

        await unmountApp(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: SpaceForm(store: store, space: longSpace),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await unmountApp(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: BookingPage(store: store, bookingId: rejectedBooking.id),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await unmountApp(tester);
      },
    );
  });
}
