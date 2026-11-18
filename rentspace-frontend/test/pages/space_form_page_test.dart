import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rentspace/app.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/ui/common.dart';
import 'package:rentspace/ui/home_page.dart';
import 'package:rentspace/ui/space_form.dart';

import '../fixtures/mock_controllers.dart';

final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile({required this.fileName, required this.fileBytes});

  final String fileName;
  final Uint8List fileBytes;

  @override
  String get name => fileName;

  @override
  Uri get uri => Uri.dataFromBytes(fileBytes, mimeType: 'image/png');

  @override
  int lengthSync() => fileBytes.length;

  @override
  Future<int?> length() async => fileBytes.length;

  @override
  Future<Uint8List> readAsBytes() async => fileBytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(fileBytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFilePickerPlatform extends FilePickerPlatform {
  _FakeFilePickerPlatform(this.pickedQueue);

  final List<PlatformFile?> pickedQueue;
  FileType? lastType;
  List<String>? lastAllowedExtensions;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    lastType = type;
    lastAllowedExtensions = allowedExtensions;
    return pickedQueue.isEmpty ? null : pickedQueue.removeAt(0);
  }
}

Future<(TestStore, ControllerBundle)> _pumpOwnerSpacesTab(
  WidgetTester tester,
) async {
  configureMobileViewport(tester);
  addTearDown(() async {
    await unmountApp(tester);
    resetMobileViewport(tester);
  });

  final store = createMockStore(viewerId: '1001');
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
      matching: find.text('พื้นที่'),
    ),
  );
  await tester.pumpAndSettle();
  return (store, mocks);
}

void _stubSpaceSave(ControllerBundle mocks, TestStore store) {
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
  ).thenAnswer((invocation) async {
    final args = invocation.namedArguments;
    final id = args[#id] as String?;
    final name = (args[#name] as String).trim();
    final category = (args[#category] as String).trim();
    final location = (args[#location] as String).trim();
    final price = args[#price] as int;
    final capacity = args[#capacity] as int;
    final description = (args[#description] as String).trim();
    final amenities = (args[#amenities] as List)
        .map((entry) => '$entry'.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    final image = (args[#image] as String).trim();
    final imageBytes = args[#imageBytes] as Uint8List?;

    if ([name, category, location, description].any((text) => text.isEmpty) ||
        price <= 0 ||
        capacity <= 0) {
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
        category: category,
        location: location,
        price: price,
        capacity: capacity,
        description: description,
        amenities: amenities,
        image: image,
        imageBytes: imageBytes,
        status: SpaceStatus.pending,
      );
      store.spaces.add(createdSpace);
      store.notify();
      return createdSpace;
    }

    final existingSpace = store.space(id);
    existingSpace
      ..name = name
      ..category = category
      ..location = location
      ..price = price
      ..capacity = capacity
      ..description = description
      ..amenities = amenities
      ..image = image
      ..imageBytes = imageBytes
      ..status = SpaceStatus.pending;
    store.notify();
    return existingSpace;
  });
}

Future<void> _fillSpaceFields(
  WidgetTester tester, {
  required String name,
  required String category,
  required String location,
  required String price,
  required String capacity,
  required String description,
  List<String> amenities = const [],
}) async {
  await scrollToAndEnter(tester, fieldByLabel('ชื่อพื้นที่'), name);
  await scrollToAndTap(tester, find.widgetWithText(ChoiceChip, category));
  await scrollToAndEnter(tester, fieldByLabel('ที่อยู่'), location);
  await scrollToAndEnter(tester, fieldByLabel('ราคา / ชั่วโมง (บาท)'), price);
  await scrollToAndEnter(tester, fieldByLabel('ความจุ (คน)'), capacity);
  await scrollToAndEnter(tester, fieldByLabel('คำอธิบาย'), description);
  for (final amenity in amenities) {
    await scrollToAndTap(tester, find.widgetWithText(FilterChip, amenity));
  }
}

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
        final (store, mocks) = await _pumpOwnerSpacesTab(tester);
        final firstOwnedSpace = store.spaces.firstWhere(
          (space) => space.ownerId == '1001',
        );
        final originalFirstName = firstOwnedSpace.name;
        _stubSpaceSave(mocks, store);

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

        await _fillSpaceFields(
          tester,
          name: 'ห้องสร้างใหม่ ทดสอบ',
          category: 'สตูดิโอ',
          location: 'เอกมัย กรุงเทพ',
          price: '500',
          capacity: '15',
          description: 'พื้นที่สว่าง โปร่งโล่ง',
          amenities: const ['Wi-Fi', 'ไวท์บอร์ด'],
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
        final createdSpace = store.space('2099');
        expect(createdSpace.name, 'ห้องสร้างใหม่ ทดสอบ');
        expect(createdSpace.category, 'สตูดิโอ');
        expect(createdSpace.amenities, ['Wi-Fi', 'ไวท์บอร์ด']);
        expect(createdSpace.status, SpaceStatus.pending);

        final createdCardFinder = find.ancestor(
          of: find.text('ห้องสร้างใหม่ ทดสอบ'),
          matching: find.byType(SurfaceCard),
        );
        await scrollToAndTap(
          tester,
          find.descendant(
            of: createdCardFinder,
            matching: find.widgetWithText(OutlinedButton, 'แก้ไข'),
          ),
        );
        expect(find.byType(SpaceForm), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'ลบภาพ'), findsNothing);

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
        expect(store.space('2099').name, 'ห้องประชุมสว่างใจ (อัปเดต)');
        expect(firstOwnedSpace.name, originalFirstName);

        verify(
          () => mocks.space.saveAsync(
            id: '2099',
            name: 'ห้องประชุมสว่างใจ (อัปเดต)',
            category: 'สตูดิโอ',
            location: 'เอกมัย กรุงเทพ',
            price: 500,
            capacity: 15,
            description: 'พื้นที่สว่าง โปร่งโล่ง',
            amenities: any(
              named: 'amenities',
              that: isA<List<String>>().having(
                (entries) => entries.map((entry) => entry.trim()).toList(),
                'trimmed',
                ['Wi-Fi', 'ไวท์บอร์ด'],
              ),
            ),
            image: '',
            imageBytes: null,
          ),
        ).called(1);
        verify(
          () => mocks.space.saveAsync(
            id: null,
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
        ).called(3);
        verifyNever(
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
        );
      },
    );

    testWidgets(
      '2. Owner manages open days, adds blocked date range with reason & saves AvailabilityPage via MockSpaceController',
      (WidgetTester tester) async {
        final (store, mocks) = await _pumpOwnerSpacesTab(tester);
        final targetSpace = store.spaces.firstWhere(
          (space) => space.ownerId == '1001',
        );
        Availability? savedAvailability;

        when(
          () => mocks.space.saveAvailabilityAsync(targetSpace.id, any()),
        ).thenAnswer((invocation) async {
          final draftCopy = (invocation.positionalArguments[1] as Availability)
              .copy();
          savedAvailability = draftCopy;
          targetSpace.availability = draftCopy;
          store.notify();
        });

        await scrollToAndTap(
          tester,
          find.widgetWithText(OutlinedButton, 'ตั้งเวลาว่าง / วันปิด').first,
        );
        expect(find.byType(AvailabilityPage), findsOneWidget);

        final firstSwitchFinder = find.byType(SwitchListTile).first;
        await scrollToAndTap(tester, firstSwitchFinder);
        expect(tester.widget<SwitchListTile>(firstSwitchFinder).value, isFalse);
        await scrollToAndTap(tester, firstSwitchFinder);
        expect(tester.widget<SwitchListTile>(firstSwitchFinder).value, isTrue);

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
          () => mocks.space.saveAvailabilityAsync(targetSpace.id, any()),
        ).called(1);
        expect(savedAvailability?.days.first.open, isTrue);
        expect(
          savedAvailability?.blocks.any(
            (block) => block.reason == 'ล้างพรมประจำเดือน',
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      '3. SpaceForm image picker/replace/remove buttons and AvailabilityPage time pickers, block removal & save error handling',
      (WidgetTester tester) async {
        final originalPicker = FilePickerPlatform.instance;
        final picker = _FakeFilePickerPlatform([
          _FakePlatformFile(
            fileName: 'bad.png',
            fileBytes: corruptMockImageBytes,
          ),
          null,
          _FakePlatformFile(
            fileName: 'studio_cover.png',
            fileBytes: validMockPngBytes,
          ),
          _FakePlatformFile(
            fileName: 'studio_alt.png',
            fileBytes: validMockPngBytes,
          ),
        ]);
        FilePickerPlatform.instance = picker;
        addTearDown(() => FilePickerPlatform.instance = originalPicker);

        final (store, mocks) = await _pumpOwnerSpacesTab(tester);
        final targetSpace = store.spaces.firstWhere(
          (space) => space.ownerId == '1001',
        );
        targetSpace.availability.blocks.add(
          BlockedPeriod(
            id: 'BLK-REMOVE',
            start: mockClockNow.add(const Duration(days: 15, hours: 1)),
            end: mockClockNow.add(const Duration(days: 15, hours: 3)),
            reason: 'ตรวจระบบไฟฟ้า',
          ),
        );

        Availability? capturedAvailability;
        when(
          () => mocks.space.saveAvailabilityAsync(targetSpace.id, any()),
        ).thenAnswer((invocation) async {
          capturedAvailability =
              (invocation.positionalArguments[1] as Availability).copy();
          throw DomainError(
            'เวลาที่ตั้งทับรายการจองเดิม กรุณาจัดการการจองก่อน',
          );
        });

        await scrollToAndTap(tester, find.text('เพิ่มพื้นที่'));
        expect(find.byType(SpaceForm), findsOneWidget);

        await scrollToAndTap(tester, find.text('เลือกภาพพื้นที่'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
        expect(find.text('เปิดไฟล์ภาพไม่ได้ กรุณาลองใหม่'), findsOneWidget);
        expect(find.text('เลือกภาพพื้นที่'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        await dismissSnackBars(tester);

        await scrollToAndTap(tester, find.text('เลือกภาพพื้นที่'));
        expect(find.text('เลือกภาพพื้นที่'), findsOneWidget);
        expect(find.byType(Image), findsNothing);

        await scrollToAndTap(tester, find.text('เลือกภาพพื้นที่'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
        expect(find.text('studio_cover.png'), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        expect(find.text('เปลี่ยนภาพ'), findsOneWidget);
        expect(find.text('ลบภาพ'), findsOneWidget);

        await scrollToAndTap(tester, find.text('เปลี่ยนภาพ'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
        expect(find.text('studio_alt.png'), findsOneWidget);
        expect(find.text('studio_cover.png'), findsNothing);
        expect(find.text('เปลี่ยนภาพ'), findsOneWidget);

        expect(picker.pickedQueue, isEmpty);
        expect(picker.lastType, FileType.custom);
        expect(picker.lastAllowedExtensions, ['jpg', 'jpeg', 'png']);

        await scrollToAndTap(tester, find.text('ลบภาพ'));
        expect(find.text('เลือกภาพพื้นที่'), findsOneWidget);
        expect(find.text('ลบภาพ'), findsNothing);
        expect(find.text('studio_alt.png'), findsNothing);
        expect(find.byType(Image), findsNothing);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await scrollToAndTap(tester, find.text('ตั้งเวลาว่าง / วันปิด').first);
        expect(find.byType(AvailabilityPage), findsOneWidget);

        await scrollToAndTap(tester, find.text('เปิด 09:00').first);
        await tester.tap(find.text('ตกลง'));
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.text('ปิด 18:00').first);
        await tester.tap(find.text('ตกลง'));
        await tester.pumpAndSettle();

        await scrollToAndTap(tester, find.byType(SwitchListTile).first);
        expect(find.text('ตรวจระบบไฟฟ้า'), findsOneWidget);
        await scrollToAndTap(tester, find.byTooltip('ลบช่วงปิด').first);
        expect(find.text('ตรวจระบบไฟฟ้า'), findsNothing);

        await scrollToAndTap(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกการตั้งค่า'),
        );
        verify(
          () => mocks.space.saveAvailabilityAsync(targetSpace.id, any()),
        ).called(1);
        expect(capturedAvailability?.days.first.open, isFalse);
        expect(
          capturedAvailability?.blocks.any((block) => block.id == 'BLK-REMOVE'),
          isFalse,
        );
        expect(
          find.text('เวลาที่ตั้งทับรายการจองเดิม กรุณาจัดการการจองก่อน'),
          findsOneWidget,
        );
        expect(find.byType(AvailabilityPage), findsOneWidget);
      },
    );
  });
}
