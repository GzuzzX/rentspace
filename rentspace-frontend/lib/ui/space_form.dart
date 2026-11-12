import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/space_controller.dart';
import '../data/app_store.dart';
import '../models/domain.dart';
import 'common.dart';

class SpaceForm extends StatefulWidget {
  const SpaceForm({super.key, required this.store, this.space});
  final AppStore store;
  final Space? space;
  @override
  State<SpaceForm> createState() => _SpaceFormState();
}

class _SpaceFormState extends State<SpaceForm> {
  static const _presetCategories = [
    'ห้องประชุม',
    'สตูดิโอ',
    'Co-working',
    'พื้นที่อีเวนต์',
  ];
  static const _presetAmenities = [
    'Wi-Fi',
    'โปรเจกเตอร์',
    'ไวท์บอร์ด',
    'ไฟสตูดิโอ',
    'ที่จอดรถ',
  ];
  static const int _maxImageBytes = 5 * 1024 * 1024;

  Uint8List? _attachedBytes;
  String _fileName = '';
  bool _busy = false;
  bool _showUrlOption = false;

  late final fields = [
    widget.space?.name ?? '',
    widget.space?.category ?? 'ห้องประชุม',
    widget.space?.location ?? '',
    widget.space?.price.toString() ?? '',
    widget.space?.capacity.toString() ?? '',
    widget.space?.description ?? '',
    widget.space?.amenities.join(', ') ?? '',
    widget.space?.image ?? '',
  ].map((s) => TextEditingController(text: s)).toList();

  Set<String> get _selectedAmenities => fields[6].text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();

  void _toggleAmenity(String amenity) {
    final current = _selectedAmenities;
    if (!current.add(amenity)) current.remove(amenity);
    setState(() => fields[6].text = current.join(', '));
  }

  @override
  void initState() {
    super.initState();
    _attachedBytes = widget.space?.imageBytes;
    if (widget.space != null && widget.space!.image.isNotEmpty) {
      _showUrlOption = true;
    }
    for (final index in [1, 6, 7]) {
      fields[index].addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    for (final c in fields) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseImage() async {
    setState(() => _busy = true);
    try {
      final pickedFile = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );
      if (pickedFile == null) return;
      final fileLength = await pickedFile.length();
      if (fileLength == null || fileLength > _maxImageBytes) {
        throw DomainError('ขนาดไฟล์เกิน 5 MB');
      }
      final rawBytes = await pickedFile.readAsBytes();
      if (rawBytes.isEmpty) {
        throw DomainError('ไฟล์รูปภาพว่างเปล่า');
      }
      final codec = await ui.instantiateImageCodec(rawBytes, targetWidth: 1600);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (mounted) {
        setState(() {
          _attachedBytes = rawBytes;
          _fileName = pickedFile.name;
          fields[7].text = '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is DomainError ? e.message : 'เปิดไฟล์ภาพไม่ได้ กรุณาลองใหม่',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearImage() {
    setState(() {
      _attachedBytes = null;
      _fileName = '';
      fields[7].text = '';
    });
  }

  int _parsePositiveNumber(String rawText) {
    final digitsOnly = rawText.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digitsOnly) ?? 0;
  }

  void _submitForm() {
    final parsedPrice = _parsePositiveNumber(fields[3].text);
    final parsedCapacity = _parsePositiveNumber(fields[4].text);
    final selectedImage = _attachedBytes != null ? '' : fields[7].text.trim();
    final saved = perform(
      context,
      () => SpaceController(widget.store).save(
        id: widget.space?.id,
        name: fields[0].text,
        category: fields[1].text,
        location: fields[2].text,
        price: parsedPrice,
        capacity: parsedCapacity,
        description: fields[5].text,
        amenities: fields[6].text.split(','),
        image: selectedImage,
        imageBytes: _attachedBytes,
      ),
      'ส่งประกาศให้ Admin แล้ว',
    );
    if (saved) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.space == null ? 'เพิ่มพื้นที่' : 'แก้ไขพื้นที่'),
      ),
      body: PageBody(
        children: [
          heading(
            widget.space == null ? 'เพิ่มพื้นที่' : 'แก้ไขพื้นที่',
            'ประกาศใหม่และประกาศที่แก้ไขจะรอ Admin ตรวจสอบก่อนแสดงต่อผู้เช่า',
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outline),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'การจองเดิมยังคงอยู่ และจะไม่ถูกยกเลิกจากการแก้ไขประกาศ',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, label) in [
                  'ชื่อพื้นที่',
                  'ประเภท',
                  'ที่อยู่',
                  'ราคา / ชั่วโมง (บาท)',
                  'ความจุ (คน)',
                  'คำอธิบาย',
                  'สิ่งอำนวยความสะดวก (คั่นด้วย ,)',
                ].indexed) ...[
                  formInput(
                    fields[i],
                    label,
                    number: i == 3 || i == 4,
                    lines: i == 5 ? 3 : 1,
                  ),
                  if (i == 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final preset in _presetCategories)
                            ChoiceChip(
                              label: Text(preset),
                              selected: fields[1].text.trim() == preset,
                              onSelected: (_) =>
                                  setState(() => fields[1].text = preset),
                            ),
                        ],
                      ),
                    ),
                  if (i == 6)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final amenity in _presetAmenities)
                            FilterChip(
                              label: Text(amenity),
                              selected: _selectedAmenities.contains(amenity),
                              onSelected: (_) => _toggleAmenity(amenity),
                            ),
                        ],
                      ),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'รูปภาพพื้นที่ (ไม่บังคับ)',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: scheme.outline),
                        ),
                        child: Column(
                          children: [
                            if (_attachedBytes != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  _attachedBytes!,
                                  height: 220,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                ),
                              )
                            else if (fields[7].text.trim().startsWith('https://'))
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  fields[7].text.trim(),
                                  height: 220,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => Container(
                                    height: 100,
                                    alignment: Alignment.center,
                                    child: Text(
                                      'ไม่สามารถโหลดตัวอย่างภาพจากลิงก์นี้',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ),
                              )
                            else ...[
                              Icon(
                                Icons.image_outlined,
                                size: 36,
                                color: scheme.onSurface.withValues(alpha: 0.35),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'เลือกภาพ JPG / PNG ไม่เกิน 5 MB\nเพื่อแสดงในหน้าค้นหาและรายละเอียดพื้นที่',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            if (_fileName.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(_fileName, style: theme.textTheme.labelSmall),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _chooseImage,
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: Text(
                              _busy
                                  ? 'กำลังอ่านภาพ...'
                                  : (_attachedBytes != null ||
                                          fields[7].text.trim().isNotEmpty
                                      ? 'เปลี่ยนภาพ'
                                      : 'เลือกภาพพื้นที่'),
                            ),
                          ),
                          if (_attachedBytes != null ||
                              fields[7].text.trim().isNotEmpty)
                            TextButton.icon(
                              onPressed: _busy ? null : _clearImage,
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('ลบภาพ'),
                            ),
                          if (!_showUrlOption)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _showUrlOption = true),
                              child: const Text('หรือใช้ลิงก์ภาพ URL'),
                            ),
                        ],
                      ),
                      if (_showUrlOption) ...[
                        const SizedBox(height: 12),
                        formInput(
                          fields[7],
                          'ลิงก์ภาพ https:// (ไม่บังคับ)',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _busy ? null : _submitForm,
                    child: const Text('บันทึกและส่งตรวจสอบ'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AvailabilityPage extends StatefulWidget {
  const AvailabilityPage({super.key, required this.store, required this.space});
  final AppStore store;
  final Space space;
  @override
  State<AvailabilityPage> createState() => _AvailabilityPageState();
}

class _AvailabilityPageState extends State<AvailabilityPage> {
  late final draft = widget.space.availability.copy();
  static const days = [
    'จันทร์',
    'อังคาร',
    'พุธ',
    'พฤหัสบดี',
    'ศุกร์',
    'เสาร์',
    'อาทิตย์',
  ];
  Future<void> pick(int i, bool start) async {
    final day = draft.days[i],
        m = start ? draft.days[i].start : draft.days[i].end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        day.start = picked.hour * 60 + picked.minute;
      } else {
        day.end = picked.hour * 60 + picked.minute;
      }
    });
  }

  Future<void> addBlock() async {
    final today = dateOnly(widget.store.clock());
    final date = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );
    if (end == null || !mounted) return;
    final reason = await askReason(context, 'เหตุผลปิดพื้นที่');
    if (reason == null || !mounted) return;
    final from = atMinute(date, start.hour * 60 + start.minute),
        to = atMinute(date, end.hour * 60 + end.minute);
    if (!to.isAfter(from)) {
      perform(
        context,
        () => throw DomainError('เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่ม'),
      );
      return;
    }
    setState(
      () => draft.blocks.add(
        BlockedPeriod(
          id: widget.store.nextId('BLOCK'),
          start: from,
          end: to,
          reason: reason,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeBookings = widget.store.bookings
        .where(
          (b) =>
              b.spaceId == widget.space.id &&
              b.status.holdsTime &&
              b.status != BookingStatus.completed,
        )
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งเวลาว่าง')),
      body: PageBody(
        children: [
          heading(
            widget.space.name,
            'ตั้งค่าเฉพาะพื้นที่นี้ • กดบันทึกเพื่อยืนยันการเปลี่ยนแปลง',
          ),
          if (activeBookings.isNotEmpty)
            SurfaceCard(
              title: 'คิวจองที่ผูกกับพื้นที่นี้ (${activeBookings.length})',
              subtitle: 'ห้ามตั้งเวลาทำการหรือช่วงปิดทับกับคิวจองเหล่านี้',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final b in activeBookings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${bookingWhen(b)} • ${widget.store.user(b.renterId).name}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          StatusBadge(
                            b.status.label,
                            tone: bookingTone(b.status),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          SurfaceCard(
            title: 'เวลาทำการ',
            subtitle: 'เปิด/ปิดแต่ละวัน และกำหนดช่วงเวลารับจอง',
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, day) in draft.days.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  SwitchListTile(
                    title: Text(days[i], style: theme.textTheme.titleSmall),
                    value: day.open,
                    onChanged: (v) => setState(() => day.open = v),
                  ),
                  if (day.open)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => pick(i, true),
                              child: Text('เปิด ${timeLabel(day.start)}'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => pick(i, false),
                              child: Text('ปิด ${timeLabel(day.end)}'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          const SectionHeader('วัน / ช่วงเวลาปิด'),
          if (draft.blocks.isEmpty) empty('ยังไม่มีช่วงปิดเพิ่มเติม'),
          for (final b in draft.blocks)
            SurfaceCard(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  const IconBox(Icons.event_busy_outlined, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.reason, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          '${dateLabel(b.start)} ${timeLabel(b.start.hour * 60 + b.start.minute)}–${timeLabel(b.end.hour * 60 + b.end.minute)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'ลบช่วงปิด',
                    onPressed: () => setState(() => draft.blocks.remove(b)),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: addBlock,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('เพิ่มช่วงปิด'),
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () {
                if (perform(
                  context,
                  () => SpaceController(
                    widget.store,
                  ).saveAvailability(widget.space.id, draft),
                  'บันทึกเวลาว่างแล้ว',
                )) {
                  Navigator.pop(context);
                }
              },
              child: const Text('บันทึกการตั้งค่า'),
            ),
          ),
        ],
      ),
    );
  }
}
