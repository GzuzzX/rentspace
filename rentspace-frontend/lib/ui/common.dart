import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/domain.dart';

bool _performing = false;

void showToast(BuildContext context, String message, {Duration? duration}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration ?? const Duration(milliseconds: 4000),
    ),
  );
}

void copyToClipboard(
  BuildContext context,
  String text,
  String message, {
  Duration? duration,
}) {
  unawaited(Clipboard.setData(ClipboardData(text: text)));
  showToast(context, message, duration: duration);
}

Future<bool> perform(
  BuildContext context,
  FutureOr<dynamic> Function() action, [
  String? success,
]) async {
  if (_performing) return false;
  _performing = true;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final loading = OverlayEntry(
    builder: (_) => const Stack(
      children: [
        ModalBarrier(dismissible: false, color: Color(0x33000000)),
        Center(child: CircularProgressIndicator()),
      ],
    ),
  );
  overlay?.insert(loading);
  try {
    await action();
    if (success != null && context.mounted) showToast(context, success);
    return true;
  } on DomainError catch (e) {
    if (context.mounted) showToast(context, e.message);
    return false;
  } catch (_) {
    if (context.mounted) {
      showToast(context, 'เกิดข้อผิดพลาดในการดำเนินการ กรุณาลองใหม่อีกครั้ง');
    }
    return false;
  } finally {
    if (overlay != null) loading.remove();
    loading.dispose();
    _performing = false;
  }
}

Future<bool> performWithReason(
  BuildContext context,
  String title,
  FutureOr<dynamic> Function(String reason) action, [
  String? success,
]) async {
  final reason = await askReason(context, title);
  if (reason == null || !context.mounted) return false;
  return perform(context, () => action(reason), success);
}

Future<String?> askReason(BuildContext context, String title) async {
  var value = '';
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 380,
          child: TextField(
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'เหตุผล / รายละเอียด'),
            onChanged: (v) => set(() => value = v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('กลับ'),
          ),
          FilledButton(
            onPressed: value.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, value.trim()),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    ),
  );
}

/// Muted tag colours matching OpenSEO's status chips.
enum BadgeTone { neutral, primary, success, warning, danger, info }

Color toneColor(BuildContext context, BadgeTone tone) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final scheme = theme.colorScheme;
  return switch (tone) {
    BadgeTone.neutral => scheme.onSurface.withValues(alpha: dark ? 0.78 : 0.62),
    BadgeTone.primary => scheme.primary,
    BadgeTone.success =>
      dark ? const Color(0xFF58C765) : const Color(0xFF1E7B2A),
    BadgeTone.warning =>
      dark ? const Color(0xFFF0B135) : const Color(0xFF8A5A00),
    BadgeTone.danger =>
      dark ? const Color(0xFFFF8482) : const Color(0xFFC02B2A),
    BadgeTone.info => dark ? const Color(0xFF54CBF2) : const Color(0xFF00708F),
  };
}

BadgeTone bookingTone(BookingStatus status) => switch (status) {
  BookingStatus.ownerReview ||
  BookingStatus.paymentDue ||
  BookingStatus.slipReview => BadgeTone.warning,
  BookingStatus.confirmed => BadgeTone.primary,
  BookingStatus.completed => BadgeTone.success,
  BookingStatus.slipRejected || BookingStatus.ownerRejected => BadgeTone.danger,
  BookingStatus.canceled => BadgeTone.neutral,
};

BadgeTone spaceTone(SpaceStatus status) => switch (status) {
  SpaceStatus.pending => BadgeTone.warning,
  SpaceStatus.approved => BadgeTone.success,
  SpaceStatus.rejected => BadgeTone.danger,
};

class StatusBadge extends StatelessWidget {
  const StatusBadge(
    this.label, {
    super.key,
    this.tone = BadgeTone.neutral,
    this.icon,
  });
  final String label;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IconBox extends StatelessWidget {
  const IconBox(
    this.icon, {
    super.key,
    this.tone = BadgeTone.neutral,
    this.size = 32,
  });
  final IconData icon;
  final BadgeTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

/// Two-state light/dark switch. The selected side follows [dark].
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key, required this.dark, required this.onChanged});
  final bool dark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget option(IconData icon, String tip, bool selected, bool mode) =>
        Tooltip(
          message: tip,
          child: Material(
            color: selected ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onChanged(mode),
              child: Container(
                width: 30,
                height: 26,
                decoration: selected
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: scheme.outline),
                      )
                    : null,
                child: Icon(
                  icon,
                  size: 16,
                  color: selected
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(Icons.light_mode_outlined, 'โหมดสว่าง', !dark, false),
          const SizedBox(width: 2),
          option(Icons.dark_mode_outlined, 'โหมดมืด', dark, true),
        ],
      ),
    );
  }
}

/// Card with the OpenSEO header row + divider pattern.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onTap,
  });
  final String? title;
  final String? subtitle;
  final Widget? action;
  final Widget? child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body = Padding(
      padding: padding,
      child: child ?? const SizedBox.shrink(),
    );
    if (onTap != null) body = InkWell(onTap: onTap, child: body);
    return Card(
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title!, style: theme.textTheme.titleSmall),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          body,
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone = BadgeTone.primary,
    this.hint,
    this.onTap,
  });
  final String label, value;
  final IconData? icon;
  final BadgeTone tone;
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    IconBox(icon!, tone: tone, size: 28),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(hint!, style: theme.textTheme.labelSmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Segmented tabs matching daisyUI's boxed tabs.
class TabStrip extends StatelessWidget {
  const TabStrip({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.margin = const EdgeInsets.only(bottom: 16),
    this.expand = false,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry margin;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tabItem(int i, {bool centered = false}) {
      final isSelected = i == selected;
      return DecoratedBox(
        decoration: isSelected
            ? BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outline),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              )
            : BoxDecoration(borderRadius: BorderRadius.circular(8)),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              alignment: centered ? Alignment.center : null,
              child: Text(
                labels[i],
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? scheme.onSurface
                      : scheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: expand
          ? Row(
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: tabItem(i, centered: true)),
                ],
              ],
            )
          : Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [for (var i = 0; i < labels.length; i++) tabItem(i)],
            ),
    );
  }
}

Widget empty(String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
  child: Builder(
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.inbox_outlined,
          size: 28,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
        ),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  ),
);

Widget heading(String title, [String? subtitle]) => Padding(
  padding: const EdgeInsets.only(bottom: 20),
  child: Builder(
    builder: (context) {
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall),
          ],
        ],
      );
    },
  ),
);

Widget formInput(
  TextEditingController controller,
  String label, {
  bool obscure = false,
  bool number = false,
  TextInputType? keyboardType,
  int lines = 1,
  String? hint,
  Widget? prefix,
  Widget? suffix,
  Iterable<String>? autofillHints,
  TextInputAction? textInputAction,
  ValueChanged<String>? onSubmitted,
  bool autocorrect = true,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: TextField(
    controller: controller,
    obscureText: obscure,
    maxLines: lines,
    autofillHints: autofillHints,
    textInputAction: textInputAction,
    onSubmitted: onSubmitted,
    autocorrect: autocorrect,
    enableSuggestions: autocorrect,
    keyboardType:
        keyboardType ?? (number ? TextInputType.number : TextInputType.text),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix,
      suffixIcon: suffix,
    ),
  ),
);

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal = constraints.maxWidth > 900 ? 28.0 : 18.0;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 40),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      );
    },
  );
}

Widget _buildMediaImage({
  required Uint8List? bytes,
  required String url,
  required double? height,
  required double? width,
  required BoxFit fit,
  required Widget? fallback,
  Map<String, String>? headers,
  bool showLoading = false,
}) {
  final err = fallback ?? const Text('ไม่สามารถเปิดภาพได้');
  if (bytes != null && bytes.isNotEmpty) {
    return Image.memory(
      bytes,
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (_, _, _) => err,
    );
  }
  if (url.isNotEmpty) {
    return Image.network(
      url,
      height: height,
      width: width,
      fit: fit,
      headers: headers,
      loadingBuilder: !showLoading
          ? null
          : (_, child, progress) => progress == null
              ? child
              : SizedBox(
                  height: height,
                  width: width,
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
      errorBuilder: (_, _, _) => err,
    );
  }
  return err;
}

class SlipImage extends StatelessWidget {
  const SlipImage(
    this.slip, {
    super.key,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.fallback,
    this.headers,
  });
  final PaymentSlip slip;
  final double? height, width;
  final BoxFit fit;
  final Widget? fallback;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) => _buildMediaImage(
    bytes: slip.bytes,
    url: slip.imageUrl,
    height: height,
    width: width,
    fit: fit,
    fallback: fallback,
    headers: headers,
  );
}

class SpaceImage extends StatelessWidget {
  const SpaceImage(
    this.space, {
    super.key,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.fallback,
    this.showLoading = false,
  });
  final Space space;
  final double? height, width;
  final BoxFit fit;
  final Widget? fallback;
  final bool showLoading;

  @override
  Widget build(BuildContext context) => _buildMediaImage(
    bytes: space.imageBytes,
    url: space.image,
    height: height,
    width: width,
    fit: fit,
    fallback: fallback,
    showLoading: showLoading,
  );
}

class CopyIconButton extends StatelessWidget {
  const CopyIconButton({
    super.key,
    required this.text,
    required this.message,
    this.size = 13,
    this.padding = const EdgeInsets.all(2),
    this.duration = const Duration(seconds: 2),
  });
  final String text, message;
  final double size;
  final EdgeInsetsGeometry padding;
  final Duration? duration;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(4),
    onTap: () => copyToClipboard(context, text, message, duration: duration),
    child: Padding(
      padding: padding,
      child: Icon(
        Icons.copy_outlined,
        size: size,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.message,
    this.tone,
    this.iconColor,
    this.borderAlpha,
    this.bgAlpha = 0.12,
    this.useErrorContainer = false,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(10),
    this.radius = 8,
    this.iconSize = 18,
    this.textStyle,
    this.trailing,
    this.chips = const [],
  });
  final IconData icon;
  final String message;
  final BadgeTone? tone;
  final Color? iconColor;
  final double? borderAlpha;
  final double bgAlpha, radius, iconSize;
  final bool useErrorContainer;
  final EdgeInsetsGeometry margin, padding;
  final TextStyle? textStyle;
  final Widget? trailing;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = tone != null
        ? toneColor(context, tone!)
        : (useErrorContainer ? scheme.error : scheme.onSurface);
    final bg = useErrorContainer
        ? scheme.errorContainer.withValues(alpha: bgAlpha)
        : (tone != null
              ? fg.withValues(alpha: bgAlpha)
              : scheme.surfaceContainerLow);
    final border = borderAlpha != null
        ? fg.withValues(alpha: borderAlpha!)
        : (tone == null && !useErrorContainer ? scheme.outline : null);
    final row = Row(
      children: [
        Icon(
          icon,
          size: iconSize,
          color:
              iconColor ??
              (tone == null && !useErrorContainer ? scheme.primary : fg),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style:
                textStyle ??
                TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
          ),
        ),
        ?trailing,
      ],
    );
    return Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: chips.isEmpty
          ? row
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row,
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: chips),
              ],
            ),
    );
  }
}

class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.tiles, this.desktopWidth = 230});
  final List<StatTile> tiles;
  final double desktopWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final tileWidth = constraints.maxWidth < 400
          ? (constraints.maxWidth - 12) / 2
          : desktopWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
        ],
      );
    },
  );
}

typedef PickedImageFile = ({String name, Uint8List bytes});

Future<PickedImageFile?> pickValidatedImageBytes(
  BuildContext context, {
  int maxBytes = 5 * 1024 * 1024,
  String sizeError = 'อ่านขนาดไฟล์ไม่ได้ หรือไฟล์เกิน 5 MB',
  void Function(String name, Uint8List bytes)? validate,
}) async {
  try {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
    );
    if (picked == null) return null;
    final length = await picked.length();
    if (length == null || length > maxBytes) throw DomainError(sizeError);
    final rawBytes = await picked.readAsBytes();
    if (validate != null) {
      validate(picked.name, rawBytes);
    } else if (rawBytes.isEmpty) {
      throw DomainError('ไฟล์รูปภาพว่างเปล่า');
    }
    final codec = await ui.instantiateImageCodec(rawBytes, targetWidth: 1600);
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
    return (name: picked.name, bytes: rawBytes);
  } catch (err) {
    if (context.mounted) {
      showToast(
        context,
        err is DomainError ? err.message : 'เปิดไฟล์ภาพไม่ได้ กรุณาลองใหม่',
      );
    }
    return null;
  }
}

class ImagePickerBox extends StatelessWidget {
  const ImagePickerBox({
    super.key,
    required this.busy,
    required this.onPick,
    required this.pickLabel,
    required this.emptyText,
    this.bytes,
    this.previewUrl,
    this.fileName = '',
    this.emptyIcon = Icons.image_outlined,
    this.emptyIconSize = 34,
    this.previewHeight = 220,
    this.boxPadding = const EdgeInsets.all(16),
    this.fullWidthPreview = false,
    this.urlErrorText = 'ไม่สามารถเปิดภาพได้',
    this.pickKey,
    this.clearKey,
    this.onClear,
    this.extraActions = const [],
  });
  final bool busy, fullWidthPreview;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final Uint8List? bytes;
  final String? previewUrl;
  final String pickLabel, emptyText, fileName, urlErrorText;
  final IconData emptyIcon;
  final double emptyIconSize, previewHeight;
  final EdgeInsetsGeometry boxPadding;
  final Key? pickKey, clearKey;
  final List<Widget> extraActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget previewError(String msg) => fullWidthPreview
        ? Container(
            height: 100,
            alignment: Alignment.center,
            child: Text(msg, style: theme.textTheme.bodySmall),
          )
        : Text(msg);
    final hasNetwork = previewUrl != null && previewUrl!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: boxPadding,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outline),
          ),
          child: Column(
            children: [
              if (bytes != null || hasNetwork)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildMediaImage(
                    bytes: bytes,
                    url: previewUrl ?? '',
                    height: previewHeight,
                    width: fullWidthPreview ? double.infinity : null,
                    fit: BoxFit.contain,
                    fallback: previewError(
                      bytes != null ? 'ไม่สามารถเปิดภาพได้' : urlErrorText,
                    ),
                  ),
                )
              else ...[
                Icon(
                  emptyIcon,
                  size: emptyIconSize,
                  color: scheme.onSurface.withValues(alpha: 0.35),
                ),
                const SizedBox(height: 8),
                Text(
                  emptyText,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (fileName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(fileName, style: theme.textTheme.labelSmall),
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
              key: pickKey,
              onPressed: busy ? null : onPick,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(busy ? 'กำลังอ่านภาพ...' : pickLabel),
            ),
            if (onClear != null)
              TextButton.icon(
                key: clearKey,
                onPressed: busy ? null : onClear,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('ลบภาพ'),
              ),
            ...extraActions,
          ],
        ),
      ],
    );
  }
}
