import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/ui/home_page.dart';
import 'package:rentspace/ui/space_form.dart';

import '../fixtures/mock_controllers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerMockControllerFallbacks();
    await setupTestChannels();
  });

  group('SpaceForm & AvailabilityPage (Mocktail)', () {
    testWidgets(
      '1. Owner validates form fields, tests image URLs, adds & edits space via MockSpaceController',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1001');
        final mocks = ControllerBundle(store);

        when(
          () => mocks.space.saveAsync(
            id: any(named: 'id'),
            name: any(named: 'name'),
            category: any(named: 'category'),
            location: any(named: 'location'),
            price: any(named: 'price'),
            capacity: any(named: 'capacity'),
            description: any(named: 'description'),
            amenities: any(named: 'amenities'),
            image: any(named: 'image'),
            imageBytes: any(named: 'imageBytes'),
          ),
        ).thenAnswer((inv) async {
          final id = inv.namedArguments[#id] as String?;
          final name = (inv.namedArguments[#name] as String).trim();
          final location = (inv.namedArguments[#location] as String).trim();
          final price = inv.namedArguments[#price] as int;
          final capacity = inv.namedArguments[#capacity] as int;
          final image = (inv.namedArguments[#image] as String).trim();
          if (name.isEmpty || location.isEmpty || price <= 0 || capacity <= 0) {
            throw DomainError('กรอกข้อมูลให้ครบ ราคาและความจุต้องมากกว่า 0');
          }
          if (image.isNotEmpty &&
              !image.startsWith('https://') &&
              !image.startsWith('http://localhost')) {
            throw DomainError('ลิงก์ภาพต้องขึ้นต้นด้วย https://');
          }
          if (id == null) {
            final createdSpace = Space(
              id: '2099',
              ownerId: '1001',
              name: name,
              category: inv.namedArguments[#category] as String,
              location: location,
              price: price,
              capacity: capacity,
              description: inv.namedArguments[#description] as String,
              amenities: List<String>.from(
                inv.namedArguments[#amenities] as List,
              ),
              image: image,
              status: SpaceStatus.pending,
            );
            store.spaces.add(createdSpace);
            store.notify();
            return createdSpace;
          }
          final existingSpace = store.space(id);
          existingSpace.name = name;
          existingSpace.image = image;
          existingSpace.status = SpaceStatus.pending;
          store.notify();
          return existingSpace;
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
            matching: find.text('พื้นที่'),
          ),
        );
        await tester.pumpAndSettle();
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'เพิ่มพื้นที่'),
        );
        expect(find.byType(SpaceForm), findsOneWidget);

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกและส่งตรวจสอบ'),
        );
        expect(
          find.text('กรอกข้อมูลให้ครบ ราคาและความจุต้องมากกว่า 0'),
          findsOneWidget,
        );
        await dismissSnackBars(tester);

        await scrollToAndEnter(
          tester,
          fieldByLabel('ชื่อพื้นที่'),
          'ห้องสร้างใหม่ ทดสอบ',
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(ChoiceChip, 'สตูดิโอ'),
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('ที่อยู่'),
          'เอกมัย กรุงเทพ',
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('ราคา / ชั่วโมง (บาท)'),
          '500',
        );
        await scrollToAndEnter(tester, fieldByLabel('ความจุ (คน)'), '15');
        await scrollToAndEnter(
          tester,
          fieldByLabel('คำอธิบาย'),
          'พื้นที่สว่าง โปร่งโล่ง',
        );
        await scrollToAndTap(tester, find.widgetWithText(FilterChip, 'Wi-Fi'));
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilterChip, 'ไวท์บอร์ด'),
        );

        await scrollToAndTap(
          tester,
          find.widgetWithText(TextButton, 'หรือใช้ลิงก์ภาพ URL'),
        );
        await scrollToAndEnter(
          tester,
          fieldByLabel('ลิงก์ภาพ URL (https:// หรือ http://localhost)'),
          'http://insecure.example.com/room.jpg',
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกและส่งตรวจสอบ'),
        );
        expect(find.text('ลิงก์ภาพต้องขึ้นต้นด้วย https://'), findsOneWidget);
        await dismissSnackBars(tester);

        await scrollToAndEnter(
          tester,
          fieldByLabel('ลิงก์ภาพ URL (https:// หรือ http://localhost)'),
          'https://cdn.example.invalid/space.jpg',
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('ไม่สามารถโหลดตัวอย่างภาพจากลิงก์นี้'),
          findsOneWidget,
        );

        await scrollToAndTap(tester, find.widgetWithText(TextButton, 'ลบภาพ'));
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกและส่งตรวจสอบ'),
        );

        expect(find.byType(HomePage), findsOneWidget);
        await scrollToAndTap(tester, find.text('ห้องสร้างใหม่ ทดสอบ'));
        expect(find.text('ห้องสร้างใหม่ ทดสอบ'), findsOneWidget);

        await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await scrollToAndTap(
          tester,
          find.widgetWithText(OutlinedButton, 'แก้ไข').first,
        );
        expect(find.byType(SpaceForm), findsOneWidget);

        await scrollToAndTap(tester, find.widgetWithText(TextButton, 'ลบภาพ'));
        await scrollToAndEnter(
          tester,
          fieldByLabel('ชื่อพื้นที่'),
          'ห้องประชุมสว่างใจ (อัปเดต)',
        );
        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกและส่งตรวจสอบ'),
        );

        expect(find.text('ห้องประชุมสว่างใจ (อัปเดต)'), findsOneWidget);
        verify(
          () => mocks.space.saveAsync(
            id: any(named: 'id'),
            name: any(named: 'name'),
            category: any(named: 'category'),
            location: any(named: 'location'),
            price: any(named: 'price'),
            capacity: any(named: 'capacity'),
            description: any(named: 'description'),
            amenities: any(named: 'amenities'),
            image: any(named: 'image'),
            imageBytes: any(named: 'imageBytes'),
          ),
        ).called(4);

        await unmountApp(tester);
      },
    );

    testWidgets(
      '2. Owner manages open days, adds blocked date range with reason & saves AvailabilityPage via MockSpaceController',
      (WidgetTester tester) async {
        configureMobileViewport(tester);
        addTearDown(() => resetMobileViewport(tester));

        final store = createMockStore(viewerId: '1001');
        final mocks = ControllerBundle(store);

        when(
          () => mocks.space.saveAvailabilityAsync(any(), any()),
        ).thenAnswer((inv) async {
          final targetSpace = store.space(inv.positionalArguments[0] as String);
          targetSpace.availability = inv.positionalArguments[1] as Availability;
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
            matching: find.text('พื้นที่'),
          ),
        );
        await tester.pumpAndSettle();

        await scrollToAndTap(
          tester,
          find.widgetWithText(OutlinedButton, 'ตั้งเวลาว่าง / วันปิด').first,
        );
        expect(find.byType(AvailabilityPage), findsOneWidget);

        await scrollToAndTap(tester, find.byType(SwitchListTile).first);
        await scrollToAndTap(tester, find.byType(SwitchListTile).first);

        await scrollToAndTap(
          tester,
          find.widgetWithText(OutlinedButton, 'เพิ่มช่วงปิด'),
        );
        await scrollToAndTap(tester, find.text('ตกลง'));
        await scrollToAndTap(tester, find.text('ตกลง'));
        await scrollToAndTap(tester, find.text('ตกลง'));
        await submitReasonDialog(tester, 'ล้างพรมประจำเดือน');
        expect(find.textContaining('ล้างพรมประจำเดือน'), findsOneWidget);

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกการตั้งค่า'),
        );
        expect(find.text('พื้นที่ของฉัน'), findsOneWidget);

        verify(
          () => mocks.space.saveAvailabilityAsync(any(), any()),
        ).called(1);

        await unmountApp(tester);
      },
    );
  });
}
