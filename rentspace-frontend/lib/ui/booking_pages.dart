import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../controllers/booking_controller.dart';
import '../controllers/space_controller.dart';
import '../data/app_store.dart';
import '../models/domain.dart';
import 'booking_detail_page.dart';
import 'common.dart';

export 'booking_detail_page.dart';

class ReservePage extends StatefulWidget {
  const ReservePage({super.key, required this.store, required this.space});
  final AppStore store;
  final Space space;
  @override
  State<ReservePage> createState() => _ReservePageState();
}

class _ReservePageState extends State<ReservePage> {
  late DateTime date = dateOnly(
    widget.store.clock(),
  ).add(const Duration(days: 1));
  int start = 600, end = 720, days = 1, attendees = 1;
  bool multiDayMode = false;
  String zone = 'โซนหลัก (พื้นที่มาตรฐาน)';
  final noteCtrl = TextEditingController();

  static const _zones = [
    'โซนหลัก (พื้นที่มาตรฐาน)',
    'ห้องส่วนตัว / ประชุมย่อย',
    'โซนเงียบพิเศษ',
  ];

  static const _notePrompts = [
    'ขอโปรเจกเตอร์/จอภาพ',
    'จัดโต๊ะประชุม',
    'ขอปลั๊กพ่วงเพิ่ม',
    'เข้าเตรียมงานก่อน 15 นาที',
  ];

  @override
  void dispose() {
    noteCtrl.dispose();
    super.dispose();
  }

  void _toggleNotePrompt(String prompt) {
    final current = noteCtrl.text.trim();
    if (current.isEmpty) {
      noteCtrl.text = prompt;
    } else if (!current.contains(prompt)) {
      noteCtrl.text = '$current, $prompt';
    }
    setState(() {});
  }

  Future<void> pickTime(bool isStart) async {
    final m = isStart ? start : end;
    final v = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (v != null && mounted) {
      setState(() {
        if (isStart) {
          start = v.hour * 60 + v.minute;
        } else {
          end = v.hour * 60 + v.minute;
        }
      });
    }
  }

  void _selectFullDayHours(DayHours dayHours) {
    if (!dayHours.open) return;
    final maxEnd = (dayHours.start + BookingController.maxDurationMinutes)
        .clamp(dayHours.start + 60, dayHours.end);
    setState(() {
      start = dayHours.start;
      end = maxEnd;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.space;
    final theme = Theme.of(context);
    final controller = BookingController(widget.store);
    final dayHours = s.availability.days[date.weekday - 1];
    final endDate = date.add(Duration(days: days - 1));
    final busyLabels = controller.busySlotLabels(s.id, date);
    final slots = controller.hourlySlots(s, date);
    final durationError = BookingController.durationError(start, end);
    final valid = durationError == null;
    final available =
        valid && controller.isSlotAvailable(s.id, date, start, end, days: days);
    final amount = valid
        ? BookingController.rent(s.price, start, end, days: days)
        : 0;
    final hoursPerDay = valid ? ((end - start) / 60).ceil() : 0;
    final statusColor = available
        ? toneColor(context, BadgeTone.success)
        : toneColor(context, BadgeTone.danger);
    return Scaffold(
      appBar: AppBar(
        title: const Text('รายละเอียดและสรุปการจอง'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: StatusBadge('ขั้นตอน 1/2', tone: BadgeTone.info),
            ),
          ),
        ],
      ),
      body: PageBody(
        children: [
          heading(s.name, '${s.location} • รองรับ ${s.capacity} คน'),
          if (s.hasImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: s.imageBytes != null
                  ? Image.memory(
                      s.imageBytes!,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Image.network(
                      s.image,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 120,
                        child: Icon(Icons.home_work_outlined, size: 64),
                      ),
                    ),
            ),
          if (s.hasImage) const SizedBox(height: 12),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.description, style: theme.textTheme.bodyMedium),
                if (s.amenities.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: s.amenities.map((a) => StatusBadge(a)).toList(),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '${bahtLabel(s.price)} / ชั่วโมง • เศษชั่วโมงปัดขึ้น',
                  style: theme.textTheme.bodySmall,
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Icon(
                      Icons.phone_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ผู้ให้เช่า: ${widget.store.user(s.ownerId).name} • โทร: ${widget.store.user(s.ownerId).phoneLabel}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SurfaceCard(
            title: 'เลือกวันและเวลา',
            subtitle:
                'จองได้ 60 นาที–12 ชั่วโมง/วัน • รองรับทั้งรายชั่วโมงและเหมาหลายวันต่อเนื่อง',
            action: StatusBadge(
              dayHours.open
                  ? 'เปิด ${timeLabel(dayHours.start)}–${timeLabel(dayHours.end)}'
                  : 'ปิดทำการ',
              tone: dayHours.open ? BadgeTone.info : BadgeTone.danger,
              icon: Icons.schedule_outlined,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabStrip(
                  labels: const [
                    'รายชั่วโมง (1 วัน)',
                    'เหมาหลายวัน (ต่อเนื่อง)',
                  ],
                  selected: multiDayMode ? 1 : 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  onChanged: (idx) {
                    setState(() {
                      multiDayMode = idx == 1;
                      days = multiDayMode ? (days < 2 ? 2 : days) : 1;
                    });
                  },
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final today = dateOnly(widget.store.clock());
                    final v = await showDatePicker(
                      context: context,
                      initialDate: date.isBefore(today) ? today : date,
                      firstDate: today,
                      lastDate: today.add(const Duration(days: 365)),
                    );
                    if (v != null && mounted) setState(() => date = v);
                  },
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: Text(
                    days > 1
                        ? '${dateLabel(date)} – ${dateLabel(endDate)} ($days วัน)'
                        : dateLabel(date),
                  ),
                ),
                if (multiDayMode) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final preset in const [2, 3, 5, 7])
                        ChoiceChip(
                          key: ValueKey('days-preset-$preset'),
                          label: Text('$preset วัน'),
                          selected: days == preset,
                          onSelected: (_) => setState(() => days = preset),
                        ),
                      IconButton.outlined(
                        key: const ValueKey('days-decrement'),
                        tooltip: 'ลดจำนวนวัน',
                        onPressed: days > 2
                            ? () => setState(() => days--)
                            : null,
                        icon: const Icon(Icons.remove, size: 16),
                      ),
                      Text(
                        '$days วัน',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton.outlined(
                        key: const ValueKey('days-increment'),
                        tooltip: 'เพิ่มจำนวนวัน',
                        onPressed: days < BookingController.maxBookingDays
                            ? () => setState(() => days++)
                            : null,
                        icon: const Icon(Icons.add, size: 16),
                      ),
                      if (dayHours.open)
                        TextButton.icon(
                          onPressed: () => _selectFullDayHours(dayHours),
                          icon: const Icon(Icons.wb_sunny_outlined, size: 16),
                          label: const Text('ใช้เวลาเต็มวัน'),
                        ),
                    ],
                  ),
                ],
                if (busyLabels.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final label in busyLabels)
                        StatusBadge(
                          label,
                          tone: BadgeTone.warning,
                          icon: Icons.event_busy_outlined,
                        ),
                    ],
                  ),
                ],
                if (slots.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (slotStart, slotEnd) in slots)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              key: ValueKey('slot-$slotStart-$slotEnd'),
                              label: Text(
                                '${timeLabel(slotStart)}–${timeLabel(slotEnd)}',
                              ),
                              selected:
                                  start <= slotStart &&
                                  end >= slotEnd &&
                                  end > start,
                              onSelected:
                                  controller.isSlotAvailable(
                                    s.id,
                                    date,
                                    slotStart,
                                    slotEnd,
                                    days: days,
                                  )
                                  ? (_) {
                                      final next = controller
                                          .selectOrExtendSlot(
                                            spaceId: s.id,
                                            date: date,
                                            currentStart: start,
                                            currentEnd: end,
                                            slotStart: slotStart,
                                            slotEnd: slotEnd,
                                          );
                                      setState(() {
                                        start = next.$1;
                                        end = next.$2;
                                      });
                                    }
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pickTime(true),
                        child: Text('เริ่ม ${timeLabel(start)}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pickTime(false),
                        child: Text('สิ้นสุด ${timeLabel(end)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        available
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 16,
                        color: statusColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          durationError ??
                              (available
                                  ? (days > 1
                                        ? 'ช่วงเวลานี้ว่างครบทั้ง $days วัน'
                                        : 'ช่วงเวลานี้ว่าง')
                                  : 'ช่วงเวลานี้ไม่ว่าง / นอกเวลาเปิด'),
                          style: TextStyle(fontSize: 12, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'จำนวนผู้เข้าร่วม (สูงสุด ${s.capacity} ท่าน)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      key: const ValueKey('attendees-decrement'),
                      tooltip: 'ลดจำนวนคน',
                      onPressed: attendees > 1
                          ? () => setState(() => attendees--)
                          : null,
                      icon: const Icon(Icons.remove, size: 16),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        '$attendees ท่าน',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      key: const ValueKey('attendees-increment'),
                      tooltip: 'เพิ่มจำนวนคน',
                      onPressed: attendees < s.capacity
                          ? () => setState(() => attendees++)
                          : null,
                      icon: const Icon(Icons.add, size: 16),
                    ),
                  ],
                ),
                if (s.capacity > 1) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final preset in {
                        1,
                        if (s.capacity >= 4)
                          (s.capacity ~/ 2).clamp(2, s.capacity),
                        s.capacity,
                      })
                        ChoiceChip(
                          key: ValueKey('attendees-preset-$preset'),
                          label: Text(
                            preset == s.capacity
                                ? 'เต็มความจุ ($preset ท่าน)'
                                : '$preset ท่าน',
                          ),
                          selected: attendees == preset,
                          onSelected: (_) => setState(() => attendees = preset),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'เลือกห้อง / โซนที่ต้องการใช้งาน',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final z in _zones)
                      ChoiceChip(
                        label: Text(z),
                        selected: zone == z,
                        onSelected: (_) => setState(() => zone = z),
                      ),
                  ],
                ),
                const Divider(height: 24),
                Text(
                  'หมายเหตุถึงเจ้าของพื้นที่ (ไม่บังคับ)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final prompt in _notePrompts)
                      ActionChip(
                        label: Text(
                          prompt,
                          style: const TextStyle(fontSize: 12),
                        ),
                        avatar: const Icon(Icons.add, size: 14),
                        onPressed: () => _toggleNotePrompt(prompt),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                formInput(
                  noteCtrl,
                  'ระบุความต้องการเพิ่มเติม เช่น อุปกรณ์ เวลาเข้าเตรียมงาน',
                  lines: 2,
                ),
              ],
            ),
          ),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ยอดรวม', style: theme.textTheme.bodySmall),
                Text(
                  bahtLabel(amount),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  days > 1
                      ? 'คำนวณ: ${bahtLabel(s.price)}/ชม. × $hoursPerDay ชม./วัน × $days วัน ($amount บาท)'
                      : 'คำนวณ: ${bahtLabel(s.price)}/ชม. × $hoursPerDay ชม. ($amount บาท)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ผู้เช่าไม่มีค่าบริการเพิ่ม • ยกเลิกฟรีก่อนแนบสลิป',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: !available
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookingConfirmationPage(
                            store: widget.store,
                            space: s,
                            date: date,
                            startMinute: start,
                            endMinute: end,
                            days: days,
                            attendeesCount: attendees,
                            zoneName: zone,
                            renterNote: noteCtrl.text.trim(),
                          ),
                        ),
                      );
                    },
              child: const Text('ส่งคำขอจอง'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                final detail = await askReason(context, 'รายงานปัญหาพื้นที่');
                if (detail != null && context.mounted) {
                  perform(
                    context,
                    () => SpaceController(widget.store).report(s.name, detail),
                    'ส่งรายงานแล้ว',
                  );
                }
              },
              child: const Text('รายงานปัญหาพื้นที่'),
            ),
          ),
          if (SpaceController(widget.store).reviewedBookings(s.id)
              case final reviews when reviews.isNotEmpty) ...[
            const SizedBox(height: 8),
            SurfaceCard(
              title: 'รีวิวจากผู้เช่า (${reviews.length})',
              action: StatusBadge(
                '★ ${SpaceController(widget.store).averageRating(s.id)!.toStringAsFixed(1)}',
                tone: BadgeTone.warning,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, item) in reviews.indexed) ...[
                    if (i > 0) const Divider(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.store.user(item.renterId).name,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          '★' * item.review!.rating,
                          style: TextStyle(
                            fontSize: 13,
                            color: toneColor(context, BadgeTone.warning),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.review!.comment,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class BookingConfirmationPage extends StatefulWidget {
  const BookingConfirmationPage({
    super.key,
    required this.store,
    required this.space,
    required this.date,
    required this.startMinute,
    required this.endMinute,
    this.days = 1,
    this.attendeesCount = 1,
    this.zoneName = 'โซนหลัก (พื้นที่มาตรฐาน)',
    this.renterNote = '',
  });

  final AppStore store;
  final Space space;
  final DateTime date;
  final int startMinute;
  final int endMinute;
  final int days;
  final int attendeesCount;
  final String zoneName;
  final String renterNote;

  @override
  State<BookingConfirmationPage> createState() =>
      _BookingConfirmationPageState();
}

class _BookingConfirmationPageState extends State<BookingConfirmationPage> {
  bool _acceptedTerms = false;
  bool _submitting = false;

  Future<void> _handleConfirmBooking(
    Space space,
    DateTime date,
    int start,
    int end,
  ) async {
    if (!_acceptedTerms || _submitting) return;
    final renter = widget.store.currentUser;
    if (renter == null || renter.phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาระบุเบอร์โทรศัพท์สำหรับติดต่อก่อนยืนยันการจอง'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    Booking? created;
    final success = perform(
      context,
      () => created = BookingController(widget.store).create(
        space.id,
        date,
        start,
        end,
        days: widget.days,
        attendees: widget.attendeesCount,
        zone: widget.zoneName,
        renterNote: widget.renterNote,
      ),
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (success && created != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งคำขอจอง ${created!.id} สำเร็จแล้ว')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) =>
              BookingPage(store: widget.store, bookingId: created!.id),
        ),
        (route) => route.isFirst,
      );
    }
  }

  Future<void> _openEditProfileDialog(BuildContext context) async {
    final user = widget.store.currentUser;
    if (user == null) return;
    final nameCtrl = TextEditingController(text: user.name);
    final phoneCtrl = TextEditingController(text: user.phone);
    final emailCtrl = TextEditingController(text: user.email);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขข้อมูลผู้จอง'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              formInput(nameCtrl, 'ชื่อ-นามสกุล'),
              formInput(
                phoneCtrl,
                'เบอร์โทรศัพท์',
                keyboardType: TextInputType.phone,
              ),
              formInput(
                emailCtrl,
                'อีเมล',
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              if (perform(
                ctx,
                () => AuthController(widget.store).updateProfile(
                  nameCtrl.text,
                  emailCtrl.text,
                  phoneCtrl.text,
                  user.bankInfo,
                ),
                'บันทึกข้อมูลแล้ว',
              )) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => _buildReviewFormView(context),
  );

  Widget _buildReviewFormView(BuildContext context) {
    final space = widget.space;
    final date = widget.date;
    final start = widget.startMinute;
    final end = widget.endMinute;
    final days = widget.days;
    final theme = Theme.of(context);
    final hours = ((end - start) / 60).ceil();
    final baseRent = space.price * hours * days;
    final renter = widget.store.currentUser;
    final hasValidPhone = renter?.phone.trim().isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ยืนยันการจอง'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'ย้อนกลับ',
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: StatusBadge('ขั้นตอน 2/2', tone: BadgeTone.primary),
            ),
          ),
        ],
      ),
      body: PageBody(
        children: [
          Builder(
            builder: (context) {
              final controller = SpaceController(widget.store);
              return _PreBookingSpaceCard(
                space: space,
                averageRating: controller.averageRating(space.id),
                reviewCount: controller.reviewedBookings(space.id).length,
              );
            },
          ),
          _PreBookingDetailsCard(
            date: date,
            start: start,
            end: end,
            hours: hours,
            days: days,
            attendees: widget.attendeesCount,
            zone: widget.zoneName,
            renterNote: widget.renterNote,
            capacity: space.capacity,
          ),
          _PreBookingPriceCard(
            baseRent: baseRent,
            hours: hours,
            days: days,
            hourlyRate: space.price,
          ),
          _PreBookingRenterCard(
            renter: renter,
            onEdit: () => _openEditProfileDialog(context),
          ),
          CheckboxListTile(
            value: _acceptedTerms,
            onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
            title: const Text('ฉันยอมรับเงื่อนไขการจองและกฎการใช้สถานที่'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ยังไม่ต้องชำระเงินทันที! เจ้าของพื้นที่จะตอบรับคำขอภายใน 24 ชม. เมื่อได้รับการอนุมัติแล้วจึงจะเข้าสู่ขั้นตอนแนบสลิปชำระเงิน',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('confirm-booking-btn'),
            onPressed: (_acceptedTerms && hasValidPhone && !_submitting)
                ? () => _handleConfirmBooking(space, date, start, end)
                : null,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('ยืนยันการจอง (${bahtLabel(baseRent)})'),
          ),
          OutlinedButton(
            onPressed: _submitting ? null : () => Navigator.pop(context),
            child: const Text('กลับไปแก้ไขข้อมูลการจอง'),
          ),
        ],
      ),
    );
  }
}

String _ratingLabel(double avg) {
  if (avg >= 4.5) return 'ดีเยี่ยม';
  if (avg >= 3.5) return 'ดีมาก';
  if (avg >= 2.5) return 'พอใช้';
  return 'ควรปรับปรุง';
}

class _PreBookingSpaceCard extends StatelessWidget {
  const _PreBookingSpaceCard({
    required this.space,
    this.averageRating,
    this.reviewCount = 0,
  });
  final Space space;
  final double? averageRating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 96,
              height: 72,
              child: !space.hasImage
                  ? Container(
                      color: scheme.surfaceContainerHigh,
                      child: const Icon(Icons.meeting_room_outlined, size: 32),
                    )
                  : space.imageBytes != null
                      ? Image.memory(
                          space.imageBytes!,
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          space.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: scheme.surfaceContainerHigh,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              size: 28,
                            ),
                          ),
                          loadingBuilder: (ctx, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                        ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  space.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        space.location,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${space.category} • รองรับได้ ${space.capacity} คน',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                if (averageRating case final avg?) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          avg.toStringAsFixed(1),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_ratingLabel(avg)} • $reviewCount รีวิว',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreBookingDetailsCard extends StatelessWidget {
  const _PreBookingDetailsCard({
    required this.date,
    required this.start,
    required this.end,
    required this.hours,
    required this.days,
    required this.attendees,
    required this.zone,
    required this.renterNote,
    required this.capacity,
  });

  final DateTime date;
  final int start, end, hours, days, attendees, capacity;
  final String zone, renterNote;

  @override
  Widget build(BuildContext context) {
    final endDate = date.add(Duration(days: days - 1));
    return SurfaceCard(
      title: 'สรุปการจอง',
      child: Column(
        children: [
          BookingInfoRow(
            'วันที่',
            days > 1
                ? '${dateLabel(date)} – ${dateLabel(endDate)} ($days วันต่อเนื่อง)'
                : dateLabel(date),
          ),
          BookingInfoRow(
            'เวลา',
            days > 1
                ? '${timeLabel(start)} – ${timeLabel(end)} ($hours ชม./วัน · รวม ${hours * days} ชม.)'
                : '${timeLabel(start)} – ${timeLabel(end)} ($hours ชั่วโมง)',
          ),
          BookingInfoRow(
            'ผู้เข้าร่วม',
            '$attendees ท่าน (รองรับสูงสุด $capacity ท่าน)',
          ),
          BookingInfoRow('ห้อง / โซน', zone),
          BookingInfoRow(
            'หมายเหตุถึงเจ้าของ',
            renterNote.trim().isEmpty ? 'ไม่มีหมายเหตุเพิ่มเติม' : renterNote,
          ),
        ],
      ),
    );
  }
}

class _PreBookingPriceCard extends StatelessWidget {
  const _PreBookingPriceCard({
    required this.baseRent,
    required this.hours,
    required this.days,
    required this.hourlyRate,
  });

  final int baseRent, hours, days, hourlyRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SurfaceCard(
      title: 'สรุปราคา',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _priceLine(
            days > 1
                ? 'ค่าเช่าพื้นที่ (${bahtLabel(hourlyRate)} × $hours ชม./วัน × $days วัน)'
                : 'ค่าเช่าพื้นที่ (${bahtLabel(hourlyRate)} × $hours ชม.)',
            bahtLabel(baseRent),
            theme,
          ),
          _priceLine('ค่าบริการระบบ (5%)', '฿0 (ฟรีสำหรับผู้เช่า)', theme),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ยอดชำระสุทธิ',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                bahtLabel(baseRent),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '*ราคาดังกล่าวรวมภาษีและไม่มีค่าธรรมเนียมแอบแฝง',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceLine(String label, String value, ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        const SizedBox(width: 8),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _PreBookingRenterCard extends StatelessWidget {
  const _PreBookingRenterCard({required this.renter, required this.onEdit});

  final AppUser? renter;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhone = renter?.phone.trim().isNotEmpty ?? false;

    return SurfaceCard(
      title: 'ข้อมูลผู้จอง',
      action: TextButton.icon(
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('แก้ไข'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookingInfoRow('ชื่อผู้จอง', renter?.name ?? 'ไม่ระบุ'),
          BookingInfoRow('เบอร์โทรศัพท์', renter?.phoneLabel ?? 'ไม่ระบุ'),
          BookingInfoRow('อีเมล', renter?.email ?? 'ไม่ระบุ'),
          if (!hasPhone) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: toneColor(
                  context,
                  BadgeTone.warning,
                ).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: toneColor(
                    context,
                    BadgeTone.warning,
                  ).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: toneColor(context, BadgeTone.warning),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'กรุณาระบุเบอร์โทรศัพท์สำหรับให้เจ้าของพื้นที่ติดต่อ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: toneColor(context, BadgeTone.warning),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(onPressed: onEdit, child: const Text('ระบุเบอร์')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
