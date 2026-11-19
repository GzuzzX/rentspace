import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

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

typedef SlipPickResult = PickedImageFile;
typedef SlipPickerFn = Future<SlipPickResult?> Function(BuildContext context);

/// เลือกรูปภาพสลิป JPG/PNG และตรวจความถูกต้องของขนาดและไฟล์ก่อนใช้งาน
Future<SlipPickResult?> pickValidatedSlipImage(BuildContext context) =>
    pickValidatedImageBytes(
      context,
      maxBytes: PaymentController.maxBytes,
      validate: PaymentController.validateSlip,
    );

/// เปิดหน้าต่างให้แอดมินตรวจสอบยอด/บัญชีเจ้าของ แนบสลิปการโอน และยืนยันจ่ายเงิน
Future<void> showAdminPayoutDialog(
  BuildContext context, {
  required AppStore store,
  required Booking booking,
  SlipPickerFn? pickSlip,
  PaymentController? paymentController,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AdminPayoutDialog(
    store: store,
    booking: booking,
    pickSlip: pickSlip ?? pickValidatedSlipImage,
    paymentController: paymentController,
  ),
);

class _AdminPayoutDialog extends StatefulWidget {
  const _AdminPayoutDialog({
    required this.store,
    required this.booking,
    required this.pickSlip,
    this.paymentController,
  });
  final AppStore store;
  final Booking booking;
  final SlipPickerFn pickSlip;
  final PaymentController? paymentController;

  @override
  State<_AdminPayoutDialog> createState() => _AdminPayoutDialogState();
}

class _AdminPayoutDialogState extends State<_AdminPayoutDialog> {
  final noteCtrl = TextEditingController();
  Uint8List? slipBytes;
  String slipName = '';
  bool busy = false;

  @override
  void dispose() {
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _chooseSlip() async {
    setState(() => busy = true);
    try {
      final picked = await widget.pickSlip(context);
      if (picked != null && mounted) {
        setState(() {
          slipBytes = picked.bytes;
          slipName = picked.name;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submitPayout() async {
    if (slipBytes == null) return;
    setState(() => busy = true);
    final succeeded = await perform(
      context,
      () => (widget.paymentController ?? PaymentController(widget.store))
          .payoutAsync(
        widget.booking.id,
        fileName: slipName,
        bytes: slipBytes,
        note: noteCtrl.text,
      ),
      'บันทึกจ่ายเงินเจ้าของแล้ว',
    );
    if (!mounted) return;
    if (succeeded) {
      Navigator.pop(context);
    } else {
      setState(() => busy = false);
    }
  }

  Widget _buildPayoutSlipPicker(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'สลิปยืนยันการโอนให้เจ้าของ (JPG / PNG ไม่เกิน 5 MB)',
        style: theme.textTheme.labelMedium,
      ),
      const SizedBox(height: 8),
      ImagePickerBox(
        busy: busy,
        bytes: slipBytes,
        fileName: slipName,
        emptyIcon: Icons.receipt_long_outlined,
        emptyIconSize: 28,
        previewHeight: 150,
        boxPadding: const EdgeInsets.all(12),
        emptyText: 'กรุณาแนบภาพสลิปการโอนก่อนยืนยัน',
        pickLabel: 'เลือกภาพสลิป',
        pickKey: const ValueKey('payout-pick-slip-btn'),
        clearKey: const ValueKey('payout-clear-slip-btn'),
        onPick: _chooseSlip,
        onClear: slipBytes == null
            ? null
            : () => setState(() {
                slipBytes = null;
                slipName = '';
              }),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final owner = widget.store.user(widget.booking.ownerId);
    final bankText = owner.bankInfo.trim().isEmpty
        ? 'ยังไม่ได้ระบุ'
        : owner.bankInfo.trim();

    return AlertDialog(
      title: const Text('ยืนยันบันทึกโอนเงินให้เจ้าของ'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('เจ้าของ: ${owner.name} (${owner.phoneLabel})'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'บัญชีรับเงิน: $bankText',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (owner.bankInfo.trim().isNotEmpty)
                    IconButton(
                      tooltip: 'คัดลอกบัญชีรับเงิน',
                      onPressed: () => copyToClipboard(
                        context,
                        owner.bankInfo.trim(),
                        'คัดลอกบัญชี ${owner.bankInfo.trim()} แล้ว',
                      ),
                      icon: const Icon(Icons.copy_outlined, size: 16),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'ยอดสุทธิที่ต้องโอน: ${bahtLabel(widget.booking.ownerNet)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '(จากค่าเช่า ${bahtLabel(widget.booking.rentAmount)} หักค่าบริการ 5% ${bahtLabel(widget.booking.platformFee)})',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              _buildPayoutSlipPicker(theme),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('payout-note-field'),
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'หมายเหตุ / เลขอ้างอิงการโอน (ไม่บังคับ)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          key: const ValueKey('payout-confirm-btn'),
          onPressed: busy || slipBytes == null ? null : _submitPayout,
          child: Text(busy ? 'กำลังบันทึก...' : 'บันทึกโอนเงินแล้ว'),
        ),
      ],
    );
  }
}

class BookingPage extends StatefulWidget {
  const BookingPage({
    super.key,
    required this.store,
    required this.bookingId,
    this.pickSlip,
    this.bookingController,
    this.paymentController,
    this.spaceController,
  });
  final AppStore store;
  final String bookingId;
  final SlipPickerFn? pickSlip;
  final BookingController? bookingController;
  final PaymentController? paymentController;
  final SpaceController? spaceController;

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
      if (mounted) unawaited(widget.store.poll());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, String>? get _authHeaders => widget.store.api.authHeaders;

  Widget _emptyScaffold(String message, {bool titled = true}) => Scaffold(
    appBar: AppBar(title: titled ? const Text('รายละเอียดการจอง') : null),
    body: PageBody(children: [empty(message)]),
  );

  Widget _deadlineBanner({
    required DateTime deadline,
    required String prefix,
    required String expiredText,
    required BadgeTone tone,
    required IconData icon,
    required bool showHours,
  }) {
    final diff = deadline.difference(store.clock());
    final remaining = diff.isNegative
        ? expiredText
        : showHours && diff.inHours > 0
        ? 'เหลือเวลาอีก ${diff.inHours} ชั่วโมง'
        : diff.inMinutes > 0
        ? 'เหลือเวลาอีก ${diff.inMinutes} นาที'
        : 'เหลือเวลาไม่ถึง 1 นาที';
    return NoticeBanner(
      icon: icon,
      iconSize: 16,
      tone: tone,
      bgAlpha: 0.1,
      radius: 6,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      message: '$prefix ${dateTimeLabel(deadline)} ($remaining)',
    );
  }

  void _openSlipZoomDialog(BuildContext context, PaymentSlip slip) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                maxScale: 5,
                child: SlipImage(slip, headers: _authHeaders),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlipCard(
    BuildContext context,
    int index,
    PaymentSlip slip, {
    String? titleOverride,
    String? badgeText,
    BadgeTone? badgeTone,
    String timestampPrefix = 'ส่ง',
  }) {
    final theme = Theme.of(context);
    final label =
        badgeText ?? (slip.rejectionReason.isEmpty ? 'ส่งแล้ว' : 'ไม่ผ่าน');
    final tone =
        badgeTone ??
        (slip.rejectionReason.isEmpty ? BadgeTone.info : BadgeTone.danger);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titleOverride ?? 'ครั้งที่ ${index + 1}: ${slip.name}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              StatusBadge(label, tone: tone),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$timestampPrefix ${dateLabel(slip.submittedAt)} ${timeLabel(slip.submittedAt.hour * 60 + slip.submittedAt.minute)}',
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
            behavior: HitTestBehavior.opaque,
            onTap: () => _openSlipZoomDialog(context, slip),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SlipImage(
                slip,
                height: 200,
                width: double.infinity,
                headers: _authHeaders,
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
      final b = widget.store.maybeBooking(widget.bookingId);
      final u = widget.store.currentUser;
      if (b == null || u == null || !u.active) {
        return _emptyScaffold('ไม่พบการจอง');
      }
      final allowed =
          u.role == UserRole.admin ||
          (u.role == UserRole.owner ? b.ownerId == u.id : b.renterId == u.id);
      if (!allowed) return _emptyScaffold('ไม่มีสิทธิ์ดูรายการนี้', titled: false);
      final renter = widget.store.maybeUser(b.renterId);
      final owner = widget.store.maybeUser(b.ownerId);
      if (renter == null || owner == null) {
        return _emptyScaffold('ไม่พบข้อมูลผู้เกี่ยวข้อง');
      }
      final theme = Theme.of(context);
      final booking = widget.bookingController ?? BookingController(widget.store),
          payment = widget.paymentController ?? PaymentController(widget.store);

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
                        onPressed: () => copyToClipboard(
                          context,
                          b.id,
                          'คัดลอกรหัสการจอง ${b.id} แล้ว',
                        ),
                        icon: const Icon(Icons.copy_outlined, size: 16),
                        label: const Text('คัดลอกรหัสจอง'),
                      ),
                      FilledButton.tonalIcon(
                        key: const ValueKey('copy-booking-evidence-btn'),
                        onPressed: () => copyToClipboard(
                          context,
                          'หลักฐานการจอง rentSPACE\n'
                              'รหัสการจอง: ${b.id}\n'
                              'สถานที่: ${b.spaceName}\n'
                              'ช่วงเวลา: ${bookingWhen(b)}\n'
                              'ผู้เข้าร่วม: ${b.attendees} ท่าน (${b.zone})\n'
                              '${b.renterNote.isNotEmpty ? 'หมายเหตุถึงเจ้าของ: ${b.renterNote}\n' : ''}'
                              'ผู้เช่า: ${renter.name} (${renter.phoneLabel})\n'
                              'เจ้าของพื้นที่: ${owner.name} (${owner.phoneLabel})\n'
                              'สถานะ: ${b.status.label}\n'
                              'ยอดชำระ: ${bahtLabel(b.rentAmount)}',
                          'คัดลอกหลักฐานการจองพร้อมส่งต่อแล้ว',
                        ),
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
                        b.paymentDeadline != null)
                      _deadlineBanner(
                        deadline: b.paymentDeadline!,
                        prefix: 'กรุณาชำระภายใน',
                        expiredText: 'หมดเวลาชำระแล้ว',
                        tone: BadgeTone.warning,
                        icon: Icons.timer_outlined,
                        showHours: false,
                      ),
                    if (b.status == BookingStatus.slipRejected &&
                        b.effectiveSlipResubmitDeadline != null)
                      _deadlineBanner(
                        deadline: b.effectiveSlipResubmitDeadline!,
                        prefix: 'ส่งสลิปใหม่ภายใน',
                        expiredText: 'หมดเวลาส่งสลิปแล้ว',
                        tone: BadgeTone.danger,
                        icon: Icons.error_outline,
                        showHours: true,
                      ),
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
                          onPressed: () => copyToClipboard(
                            context,
                            '000-0-00000-0',
                            'คัดลอกเลขบัญชี 000-0-00000-0 แล้ว',
                          ),
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
                            builder: (_) => SlipPage(
                              store: store,
                              booking: b,
                              pickSlip: widget.pickSlip,
                              paymentController: widget.paymentController,
                            ),
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
                        trailing: CopyIconButton(
                          text: owner.bankInfo,
                          message: 'คัดลอกเลขบัญชี ${owner.bankInfo} แล้ว',
                          size: 15,
                          padding: const EdgeInsets.only(left: 6),
                          duration: null,
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
                      b.payoutSlip != null
                          ? 'โอนเงินแล้ว ${dateLabel(b.paidOutAt!)} • มีสลิปแนบ'
                          : 'โอนเงินแล้ว ${dateLabel(b.paidOutAt!)}',
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
                    onPressed: () => performWithReason(
                      context,
                      'ยกเลิกคำขอจอง',
                      (r) => booking.cancelAsync(b.id, r),
                    ),
                    child: const Text('ยกเลิกคำขอ'),
                  ),
                if (u.role == UserRole.owner &&
                    b.status == BookingStatus.ownerReview) ...[
                  FilledButton(
                    onPressed: () => perform(
                      context,
                      () => booking.ownerReviewAsync(b.id, true, ''),
                    ),
                    child: const Text('อนุมัติคำขอ'),
                  ),
                  OutlinedButton(
                    onPressed: () => performWithReason(
                      context,
                      'เหตุผลปฏิเสธคำขอ',
                      (r) => booking.ownerReviewAsync(b.id, false, r),
                    ),
                    child: const Text('ปฏิเสธคำขอ'),
                  ),
                ],
                if (u.role == UserRole.owner &&
                    b.status == BookingStatus.confirmed)
                  FilledButton(
                    onPressed: !widget.store.clock().isBefore(b.endsAt)
                        ? () => perform(
                            context,
                            () => booking.completeAsync(b.id),
                            'ทำเครื่องหมายว่าใช้บริการแล้ว',
                          )
                        : null,
                    child: const Text('ทำเครื่องหมายว่าใช้บริการแล้ว'),
                  ),
                if (u.role == UserRole.admin &&
                    b.status == BookingStatus.slipReview) ...[
                  FilledButton(
                    onPressed: () => perform(
                      context,
                      () => payment.reviewAsync(b.id, true, ''),
                    ),
                    child: const Text('ตรวจแล้ว ยืนยันการจอง'),
                  ),
                  OutlinedButton(
                    onPressed: () => performWithReason(
                      context,
                      'เหตุผลที่สลิปไม่ผ่าน',
                      (r) => payment.reviewAsync(b.id, false, r),
                    ),
                    child: const Text('ปฏิเสธสลิป'),
                  ),
                ],
                if (u.role == UserRole.admin &&
                    b.status == BookingStatus.completed &&
                    b.paidOutAt == null)
                  FilledButton(
                    onPressed: () => showAdminPayoutDialog(
                      context,
                      store: widget.store,
                      booking: b,
                      paymentController: widget.paymentController,
                    ),
                    child: const Text('บันทึกจ่ายเจ้าของ (แนบสลิป)'),
                  ),
              ],
            ),
            if (u.role == UserRole.owner && b.status == BookingStatus.confirmed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  !widget.store.clock().isBefore(b.endsAt)
                      ? 'ถึงเวลาสิ้นสุดการจองแล้ว สามารถกดยืนยันจบงานได้'
                      : 'ทำรายการได้เมื่อถึงเวลาสิ้นสุดการจอง (${dateTimeLabel(b.endsAt)})',
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
            if (u.role != UserRole.renter &&
                (b.paidOutAt != null || b.payoutSlip != null)) ...[
              const SizedBox(height: 8),
              const SectionHeader(
                'สลิปโอนเงินให้เจ้าของ (Admin)',
                subtitle: 'หลักฐานการโอนยอดสุทธิจากผู้ดูแลระบบถึงเจ้าของพื้นที่',
              ),
              if (b.payoutSlip != null)
                _buildSlipCard(
                  context,
                  0,
                  b.payoutSlip!,
                  titleOverride: 'สลิปโอนเงินให้เจ้าของ: ${b.payoutSlip!.name}',
                  badgeText: 'โอนแล้ว',
                  badgeTone: BadgeTone.success,
                  timestampPrefix: 'โอนเมื่อ',
                )
              else
                SurfaceCard(
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'บันทึกโอนเงินแล้วเมื่อ ${dateLabel(b.paidOutAt!)} (ไม่มีสลิปแนบในรายการเดิม)',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
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
              _ReviewFormCard(
                store: store,
                bookingId: b.id,
                bookingController: widget.bookingController,
              ),
            if (u.role == UserRole.admin &&
                ![
                  BookingStatus.completed,
                  BookingStatus.canceled,
                  BookingStatus.ownerRejected,
                ].contains(b.status))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => performWithReason(
                    context,
                    'ยกเลิกการจอง',
                    (r) => booking.cancelAsync(b.id, r),
                  ),
                  child: const Text('Admin ยกเลิกการจอง'),
                ),
              ),
            if (u.role != UserRole.admin)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => performWithReason(
                    context,
                    'แจ้งปัญหา / ขอให้ Admin ช่วยเหลือ',
                    (r) => (widget.spaceController ?? SpaceController(store))
                        .reportAsync(b.id, r),
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
  const SlipPage({
    super.key,
    required this.store,
    required this.booking,
    this.pickSlip,
    this.paymentController,
  });
  final AppStore store;
  final Booking booking;
  final SlipPickerFn? pickSlip;
  final PaymentController? paymentController;
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
      final picker = widget.pickSlip ?? pickValidatedSlipImage;
      final picked = await picker(context);
      if (picked != null && mounted) {
        setState(() {
          bytes = picked.bytes;
          filename = picked.name;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('แนบสลิป')),
    body: PageBody(
      children: [
        heading(
          widget.booking.spaceName,
          'ยอดชำระ ${bahtLabel(widget.booking.rentAmount)}',
        ),
        SurfaceCard(
          title: 'อัปโหลดสลิป',
          subtitle: 'JPG / PNG ไม่เกิน 5 MB',
          child: ImagePickerBox(
            busy: busy,
            bytes: bytes,
            fileName: filename,
            previewHeight: 260,
            boxPadding: const EdgeInsets.all(20),
            emptyText:
                'เลือกภาพ JPG / PNG ไม่เกิน 5 MB\nที่แสดงยอด วันเวลา และเลขอ้างอิง',
            pickLabel: 'เลือกภาพสลิป',
            onPick: choose,
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
                        : () async {
                            setState(() => busy = true);
                            final ok = await perform(
                              context,
                              () => (widget.paymentController ??
                                      PaymentController(widget.store))
                                  .submitAsync(
                                widget.booking.id,
                                filename,
                                bytes!,
                                note.text,
                              ),
                              'ส่งสลิปแล้ว รอ Admin ตรวจสอบ',
                            );
                            if (ok && context.mounted) {
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

class _ReviewFormCard extends StatefulWidget {
  const _ReviewFormCard({
    required this.store,
    required this.bookingId,
    this.bookingController,
  });
  final AppStore store;
  final String bookingId;
  final BookingController? bookingController;
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
                () => (widget.bookingController ?? BookingController(widget.store))
                    .submitReviewAsync(widget.bookingId, rating, comment.text),
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
