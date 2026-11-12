import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/booking_controller.dart';
import '../controllers/payment_controller.dart';
import '../controllers/space_controller.dart';
import '../data/app_store.dart';
import '../models/domain.dart';
import 'common.dart';

class BookingInfoRow extends StatelessWidget {
  const BookingInfoRow(this.label, this.value, {super.key, this.trailing});
  final String label, value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
          ?trailing,
        ],
      ),
    );
  }
}

class _BookingProgressBar extends StatelessWidget {
  const _BookingProgressBar({required this.status});
  final BookingStatus status;

  static const _steps = ['ส่งคำขอ', 'ชำระเงิน', 'ตรวจสลิป', 'ยืนยัน'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeStep = status.progressStep;
    final activeColor = toneColor(context, bookingTone(status));
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i <= activeStep
                          ? activeColor
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${i + 1}. ${_steps[i]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == activeStep
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: i <= activeStep
                          ? scheme.onSurface
                          : scheme.onSurface.withValues(alpha: 0.45),
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

class BookingPage extends StatefulWidget {
  const BookingPage({super.key, required this.store, required this.bookingId});
  final AppStore store;
  final String bookingId;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  AppStore get store => widget.store;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) BookingController(widget.store).sweep();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> reasonAction(
    BuildContext context,
    String title,
    void Function(String) action,
  ) async {
    final reason = await askReason(context, title);
    if (reason != null && context.mounted) {
      perform(context, () => action(reason));
    }
  }

  Widget _buildSlipCard(BuildContext context, int index, PaymentSlip slip) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ครั้งที่ ${index + 1}: ${slip.name}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              StatusBadge(
                slip.rejectionReason.isEmpty ? 'ส่งแล้ว' : 'ไม่ผ่าน',
                tone: slip.rejectionReason.isEmpty
                    ? BadgeTone.info
                    : BadgeTone.danger,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ส่ง ${dateLabel(slip.submittedAt)} ${timeLabel(slip.submittedAt.hour * 60 + slip.submittedAt.minute)}',
            style: theme.textTheme.bodySmall,
          ),
          if (slip.note.isNotEmpty)
            Text('หมายเหตุ: ${slip.note}', style: theme.textTheme.bodySmall),
          if (slip.rejectionReason.isNotEmpty)
            Text(
              'เหตุผลไม่ผ่าน: ${slip.rejectionReason}',
              style: TextStyle(
                fontSize: 12,
                color: toneColor(context, BadgeTone.danger),
              ),
            ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => Dialog(
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                    Expanded(
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Image.memory(
                          slip.bytes,
                          errorBuilder: (_, _, _) =>
                              const Text('ไม่สามารถเปิดภาพได้'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                slip.bytes,
                height: 200,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Text('ไม่สามารถเปิดภาพได้'),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('แตะภาพเพื่อขยาย', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final b = widget.store.booking(widget.bookingId),
          u = widget.store.requireUser();
      final allowed =
          u.role == UserRole.admin ||
          (u.role == UserRole.owner ? b.ownerId == u.id : b.renterId == u.id);
      if (!allowed) {
        return Scaffold(
          appBar: AppBar(),
          body: PageBody(children: [empty('ไม่มีสิทธิ์ดูรายการนี้')]),
        );
      }
      final theme = Theme.of(context);
      final booking = BookingController(widget.store),
          payment = PaymentController(widget.store);
      final renter = widget.store.user(b.renterId);
      final owner = widget.store.user(b.ownerId);

      return Scaffold(
        appBar: AppBar(
          title: const Text('รายละเอียดการจอง'),
          actions: [
            IconButton(
              tooltip: 'กลับหน้าหลัก',
              icon: const Icon(Icons.home_outlined),
              onPressed: () =>
                  Navigator.popUntil(context, (route) => route.isFirst),
            ),
          ],
        ),
        body: PageBody(
          children: [
            heading(b.spaceName, 'รหัสการจอง: ${b.id}'),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(b.status.label, tone: bookingTone(b.status)),
            ),
            if (b.deadlineHint(widget.store.clock()) case final hint?) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(
                  hint,
                  tone: b.status == BookingStatus.slipRejected
                      ? BadgeTone.danger
                      : BadgeTone.warning,
                  icon: Icons.schedule,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _BookingProgressBar(status: b.status),
            const SizedBox(height: 12),
            SurfaceCard(
              title: 'หลักฐานและรหัสอ้างอิงการจอง',
              subtitle:
                  'แสดงรหัสนี้ต่อผู้เช่า / เจ้าของพื้นที่เพื่อยืนยันสิทธิ์เข้าใช้งาน',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.verified_outlined,
                          size: 26,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'รหัสการจอง (Booking Pass)',
                                style: theme.textTheme.labelSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                b.id,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('copy-booking-id-btn'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: b.id));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('คัดลอกรหัสการจอง ${b.id} แล้ว'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_outlined, size: 16),
                        label: const Text('คัดลอกรหัสจอง'),
                      ),
                      FilledButton.tonalIcon(
                        key: const ValueKey('copy-booking-evidence-btn'),
                        onPressed: () async {
                          final summary =
                              'หลักฐานการจอง rentSPACE\n'
                              'รหัสการจอง: ${b.id}\n'
                              'สถานที่: ${b.spaceName}\n'
                              'ช่วงเวลา: ${bookingWhen(b)}\n'
                              'ผู้เข้าร่วม: ${b.attendees} ท่าน (${b.zone})\n'
                              '${b.renterNote.isNotEmpty ? 'หมายเหตุถึงเจ้าของ: ${b.renterNote}\n' : ''}'
                              'ผู้เช่า: ${renter.name} (${renter.phoneLabel})\n'
                              'เจ้าของพื้นที่: ${owner.name} (${owner.phoneLabel})\n'
                              'สถานะ: ${b.status.label}\n'
                              'ยอดชำระ: ${bahtLabel(b.rentAmount)}';
                          await Clipboard.setData(ClipboardData(text: summary));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'คัดลอกหลักฐานการจองพร้อมส่งต่อแล้ว',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.receipt_long_outlined, size: 16),
                        label: const Text('คัดลอกใบหลักฐานการจอง'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (u.role == UserRole.renter &&
                [
                  BookingStatus.paymentDue,
                  BookingStatus.slipRejected,
                ].contains(b.status)) ...[
              SurfaceCard(
                title: 'การชำระเงินจำลอง',
                subtitle: 'บัญชีนี้เป็นตัวอย่าง ห้ามโอนเงินจริง',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (b.status == BookingStatus.paymentDue &&
                        b.paymentDeadline != null) ...[
                      Builder(
                        builder: (context) {
                          final diff = b.paymentDeadline!.difference(
                            store.clock(),
                          );
                          final remaining = diff.isNegative
                              ? 'หมดเวลาชำระแล้ว'
                              : (diff.inMinutes > 0
                                    ? 'เหลือเวลาอีก ${diff.inMinutes} นาที'
                                    : 'เหลือเวลาไม่ถึง 1 นาที');
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: toneColor(
                                context,
                                BadgeTone.warning,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 16,
                                  color: toneColor(context, BadgeTone.warning),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'กรุณาชำระภายใน ${dateTimeLabel(b.paymentDeadline!)} ($remaining)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: toneColor(
                                        context,
                                        BadgeTone.warning,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                    if (b.status == BookingStatus.slipRejected &&
                        b.effectiveSlipResubmitDeadline != null) ...[
                      Builder(
                        builder: (context) {
                          final diff = b.effectiveSlipResubmitDeadline!
                              .difference(store.clock());
                          final remaining = diff.isNegative
                              ? 'หมดเวลาส่งสลิปแล้ว'
                              : (diff.inHours > 0
                                    ? 'เหลือเวลาอีก ${diff.inHours} ชั่วโมง'
                                    : 'เหลือเวลาอีก ${diff.inMinutes} นาที');
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: toneColor(
                                context,
                                BadgeTone.danger,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 16,
                                  color: toneColor(context, BadgeTone.danger),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'ส่งสลิปใหม่ภายใน ${dateTimeLabel(b.effectiveSlipResubmitDeadline!)} ($remaining)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: toneColor(
                                        context,
                                        BadgeTone.danger,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'ธนาคาร DEMO • เลขบัญชี 000-0-00000-0',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        TextButton.icon(
                          key: const ValueKey('copy-account-btn'),
                          onPressed: () {
                            Clipboard.setData(
                              const ClipboardData(text: '000-0-00000-0'),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'คัดลอกเลขบัญชี 000-0-00000-0 แล้ว',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_outlined, size: 15),
                          label: const Text('คัดลอก'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.qr_code_2_rounded,
                            size: 56,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'QR พร้อมเพย์จำลอง • ${bahtLabel(b.rentAmount)}',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'อ้างอิง: ${b.id}',
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (b.status == BookingStatus.slipRejected) ...[
                      const SizedBox(height: 8),
                      Text(
                        'ยังกันช่วงเวลานี้ไว้ให้คุณ กรุณาส่งสลิปใหม่ภายในกำหนด (มิฉะนั้นระบบจะยกเลิกอัตโนมัติ) หรือกดยกเลิกเพื่อคืนช่วงเวลา',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SlipPage(store: store, booking: b),
                          ),
                        ),
                        icon: const Icon(Icons.upload, size: 18),
                        label: const Text('แนบ / ส่งสลิปใหม่'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SurfaceCard(
              title: 'ข้อมูลการใช้งาน',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BookingInfoRow('ช่วงเวลา', bookingWhen(b)),
                  BookingInfoRow('ผู้เข้าร่วม', '${b.attendees} ท่าน'),
                  BookingInfoRow('ห้อง / โซน', b.zone),
                  if (b.renterNote.isNotEmpty)
                    BookingInfoRow('หมายเหตุผู้เช่า', b.renterNote),
                ],
              ),
            ),
            SurfaceCard(
              title: 'ข้อมูลติดต่อและค่าบริการ',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (u.role != UserRole.renter) ...[
                    BookingInfoRow('ผู้เช่า', renter.name),
                    BookingInfoRow('เบอร์ผู้เช่า', renter.phoneLabel),
                  ],
                  BookingInfoRow('เจ้าของพื้นที่', owner.name),
                  BookingInfoRow('เบอร์ผู้ให้เช่า', owner.phoneLabel),
                  BookingInfoRow('ยอดชำระ', bahtLabel(b.rentAmount)),
                  if (u.role != UserRole.renter) ...[
                    BookingInfoRow(
                      'เจ้าของได้รับ',
                      '${bahtLabel(b.ownerNet)} (ค่าบริการ ${bahtLabel(b.platformFee)})',
                    ),
                    if (owner.bankInfo.isNotEmpty)
                      BookingInfoRow(
                        'บัญชีรับเงิน',
                        owner.bankInfo,
                        trailing: InkWell(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: owner.bankInfo),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'คัดลอกเลขบัญชี ${owner.bankInfo} แล้ว',
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.copy_outlined,
                              size: 15,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                  if (b.status == BookingStatus.ownerReview &&
                      b.ownerResponseDeadline != null)
                    BookingInfoRow(
                      'ตอบรับภายใน',
                      dateTimeLabel(b.ownerResponseDeadline!),
                    ),
                  if (b.status == BookingStatus.paymentDue &&
                      b.paymentDeadline != null)
                    BookingInfoRow(
                      'ชำระภายใน',
                      dateTimeLabel(b.paymentDeadline!),
                    ),
                  if (b.status == BookingStatus.slipRejected &&
                      b.effectiveSlipResubmitDeadline != null)
                    BookingInfoRow(
                      'ส่งสลิปใหม่ภายใน',
                      dateTimeLabel(b.effectiveSlipResubmitDeadline!),
                    ),
                  if (b.status == BookingStatus.confirmed)
                    BookingInfoRow(
                      'จบอัตโนมัติ',
                      dateTimeLabel(b.autoCompleteAt),
                    ),
                  if (b.paidOutAt != null)
                    BookingInfoRow(
                      'จ่ายเจ้าของ',
                      'จำลองแล้ว ${dateLabel(b.paidOutAt!)}',
                    ),
                  if (b.reason.isNotEmpty) BookingInfoRow('เหตุผล', b.reason),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (u.role == UserRole.renter &&
                    [
                      BookingStatus.ownerReview,
                      BookingStatus.paymentDue,
                      BookingStatus.slipRejected,
                    ].contains(b.status))
                  OutlinedButton(
                    onPressed: () => reasonAction(
                      context,
                      'ยกเลิกคำขอจอง',
                      (r) => booking.cancel(b.id, r),
                    ),
                    child: const Text('ยกเลิกคำขอ'),
                  ),
                if (u.role == UserRole.owner &&
                    b.status == BookingStatus.ownerReview) ...[
                  FilledButton(
                    onPressed: () => perform(
                      context,
                      () => booking.ownerReview(b.id, true, ''),
                    ),
                    child: const Text('อนุมัติคำขอ'),
                  ),
                  OutlinedButton(
                    onPressed: () => reasonAction(
                      context,
                      'เหตุผลปฏิเสธคำขอ',
                      (r) => booking.ownerReview(b.id, false, r),
                    ),
                    child: const Text('ปฏิเสธคำขอ'),
                  ),
                ],
                if (u.role == UserRole.owner &&
                    b.status == BookingStatus.confirmed)
                  FilledButton(
                    onPressed: () =>
                        perform(context, () => booking.complete(b.id)),
                    child: const Text('ทำเครื่องหมายว่าใช้บริการแล้ว'),
                  ),
                if (u.role == UserRole.admin &&
                    b.status == BookingStatus.slipReview) ...[
                  FilledButton(
                    onPressed: () =>
                        perform(context, () => payment.review(b.id, true, '')),
                    child: const Text('ตรวจแล้ว ยืนยันการจอง'),
                  ),
                  OutlinedButton(
                    onPressed: () => reasonAction(
                      context,
                      'เหตุผลที่สลิปไม่ผ่าน',
                      (r) => payment.review(b.id, false, r),
                    ),
                    child: const Text('ปฏิเสธสลิป'),
                  ),
                ],
                if (u.role == UserRole.admin &&
                    b.status == BookingStatus.completed &&
                    b.paidOutAt == null)
                  FilledButton(
                    onPressed: () async {
                      final r = await askReason(
                        context,
                        'ยืนยันบันทึกจ่ายเจ้าของจำลอง ${bahtLabel(b.ownerNet)}',
                      );
                      if (r != null && context.mounted) {
                        perform(context, () => payment.payout(b.id));
                      }
                    },
                    child: const Text('บันทึกจ่ายเจ้าของ (จำลอง)'),
                  ),
              ],
            ),
            if (u.role == UserRole.owner && b.status == BookingStatus.confirmed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'ทำรายการได้เมื่อถึงเวลาสิ้นสุดการจองเท่านั้น',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (b.slips.isNotEmpty) ...[
              const SizedBox(height: 8),
              const SectionHeader(
                'หลักฐานการโอน',
                subtitle: 'แสดงสลิปล่าสุดเป็นหลัก',
              ),
              _buildSlipCard(context, b.slips.length - 1, b.slips.last),
              if (b.slips.length > 1)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ExpansionTile(
                    title: Text(
                      'ประวัติสลิปก่อนหน้า (${b.slips.length - 1} รายการ)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      for (var i = 0; i < b.slips.length - 1; i++)
                        _buildSlipCard(context, i, b.slips[i]),
                    ],
                  ),
                ),
            ],
            if (b.review != null)
              SurfaceCard(
                title: 'รีวิวการใช้บริการ',
                action: StatusBadge(
                  '★ ${b.review!.rating}.0',
                  tone: BadgeTone.warning,
                ),
                child: Text(
                  b.review!.comment,
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else if (u.role == UserRole.renter &&
                b.status == BookingStatus.completed)
              _ReviewFormCard(store: store, bookingId: b.id),
            if (u.role == UserRole.admin &&
                ![
                  BookingStatus.completed,
                  BookingStatus.canceled,
                  BookingStatus.ownerRejected,
                ].contains(b.status))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => reasonAction(
                    context,
                    'ยกเลิกการจอง',
                    (r) => booking.cancel(b.id, r),
                  ),
                  child: const Text('Admin ยกเลิกการจอง'),
                ),
              ),
            if (u.role != UserRole.admin)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => reasonAction(
                    context,
                    'แจ้งปัญหา / ขอให้ Admin ช่วยเหลือ',
                    (r) => SpaceController(store).report(b.id, r),
                  ),
                  child: const Text('แจ้งปัญหาการจอง'),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class SlipPage extends StatefulWidget {
  const SlipPage({super.key, required this.store, required this.booking});
  final AppStore store;
  final Booking booking;
  @override
  State<SlipPage> createState() => _SlipPageState();
}

class _SlipPageState extends State<SlipPage> {
  final note = TextEditingController();
  Uint8List? bytes;
  String filename = '';
  bool busy = false;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> choose() async {
    setState(() => busy = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );
      if (file == null) return;
      final size = await file.length();
      if (size == null || size > PaymentController.maxBytes) {
        throw DomainError('อ่านขนาดไฟล์ไม่ได้ หรือไฟล์เกิน 5 MB');
      }
      final data = await file.readAsBytes();
      PaymentController.validateSlip(file.name, data);
      // Decode before accepting so a renamed or corrupt file cannot be submitted.
      final codec = await ui.instantiateImageCodec(data, targetWidth: 1600);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (mounted) {
        setState(() {
          bytes = data;
          filename = file.name;
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
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('แนบสลิป')),
      body: PageBody(
        children: [
          heading(
            widget.booking.spaceName,
            'ยอดชำระจำลอง ${bahtLabel(widget.booking.rentAmount)}',
          ),
          SurfaceCard(
            title: 'อัปโหลดสลิป',
            subtitle: 'JPG / PNG ไม่เกิน 5 MB',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Column(
                    children: [
                      if (bytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            bytes!,
                            height: 260,
                            fit: BoxFit.contain,
                          ),
                        )
                      else ...[
                        Icon(
                          Icons.image_outlined,
                          size: 34,
                          color: scheme.onSurface.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'เลือกภาพ JPG / PNG ไม่เกิน 5 MB\n'
                          'ที่แสดงยอด วันเวลา และเลขอ้างอิง',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      if (filename.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(filename, style: theme.textTheme.labelSmall),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : choose,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(busy ? 'กำลังอ่านภาพ...' : 'เลือกภาพสลิป'),
                ),
              ],
            ),
          ),
          SurfaceCard(
            title: 'หมายเหตุ',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                formInput(note, 'หมายเหตุ (ไม่บังคับ)', lines: 3),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: busy || bytes == null
                        ? null
                        : () {
                            setState(() => busy = true);
                            final ok = perform(
                              context,
                              () => PaymentController(widget.store).submit(
                                widget.booking.id,
                                filename,
                                bytes!,
                                note.text,
                              ),
                              'ส่งสลิปแล้ว รอ Admin ตรวจสอบ',
                            );
                            if (ok) {
                              Navigator.pop(context);
                            } else {
                              setState(() => busy = false);
                            }
                          },
                    child: const Text('ส่งสลิปเพื่อตรวจสอบ'),
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

class _ReviewFormCard extends StatefulWidget {
  const _ReviewFormCard({required this.store, required this.bookingId});
  final AppStore store;
  final String bookingId;
  @override
  State<_ReviewFormCard> createState() => _ReviewFormCardState();
}

class _ReviewFormCardState extends State<_ReviewFormCard> {
  int rating = 5;
  final comment = TextEditingController();

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      title: 'ให้คะแนนและรีวิวพื้นที่',
      subtitle: 'บอกเล่าประสบการณ์ใช้งานของคุณ (1–5 ดาว)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 4,
            children: List.generate(5, (index) {
              final star = index + 1;
              return IconButton(
                tooltip: '$star ดาว',
                onPressed: () => setState(() => rating = star),
                icon: Icon(
                  star <= rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: star <= rating
                      ? toneColor(context, BadgeTone.warning)
                      : scheme.onSurface.withValues(alpha: 0.4),
                  size: 28,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          formInput(comment, 'ความคิดเห็นหลังใช้งาน', lines: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => perform(
                context,
                () => BookingController(
                  widget.store,
                ).submitReview(widget.bookingId, rating, comment.text),
                'บันทึกรีวิวเรียบร้อยแล้ว',
              ),
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: const Text('ส่งรีวิว'),
            ),
          ),
        ],
      ),
    );
  }
}
