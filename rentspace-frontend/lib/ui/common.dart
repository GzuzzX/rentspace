import 'package:flutter/material.dart';

import '../models/domain.dart';

bool perform(BuildContext context, VoidCallback action, [String? success]) {
  try {
    action();
    if (success != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } on DomainError catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
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
          _ThemeOption(
            icon: Icons.light_mode_outlined,
            tooltip: 'โหมดสว่าง',
            selected: !dark,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 2),
          _ThemeOption(
            icon: Icons.dark_mode_outlined,
            tooltip: 'โหมดมืด',
            selected: dark,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.5);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? scheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            width: 30,
            height: 26,
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: scheme.outline),
                  )
                : null,
            child: Icon(icon, size: 16, color: color),
          ),
        ),
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
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outline),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < labels.length; i++)
            _TabItem(
              label: labels[i],
              selected: i == selected,
              onTap: () => onChanged(i),
            ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? scheme.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: scheme.outline),
                )
              : null,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? scheme.onSurface
                  : scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
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

Widget heading(String title, [String? subtitle]) =>
    _Heading(title: title, subtitle: subtitle);

class _Heading extends StatelessWidget {
  const _Heading({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

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
