import 'package:flutter/material.dart';

import 'guard.dart';

/// An installed app's launcher icon.
class AppIcon extends StatelessWidget {
  const AppIcon(this.pkg, {super.key, this.size = 40});

  final String pkg;
  final double size;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: guard.icon(pkg),
    builder: (context, snap) => snap.data == null
        ? Icon(Icons.android, size: size)
        : Image.memory(snap.data!, width: size, height: size, gaplessPlayback: true),
  );
}

/// A rule's apps, overlapping: the first three, then +n.
class AppStack extends StatelessWidget {
  const AppStack(this.apps, {super.key});

  final Set<String> apps;

  @override
  Widget build(BuildContext context) {
    final shown = apps.take(3).toList();
    final more = apps.length - shown.length;
    return SizedBox(
      width: 40 + 22.0 * (shown.length - 1).clamp(0, 2) + (more > 0 ? 30 : 0),
      height: 40,
      child: Stack(
        children: [
          for (final (i, pkg) in shown.indexed) Positioned(left: 22.0 * i, child: AppIcon(pkg)),
          if (more > 0)
            Positioned(right: 0, top: 10, child: Text('+$more', style: Theme.of(context).textTheme.labelMedium)),
        ],
      ),
    );
  }
}

/// The window as a strip, oldest on the left, now on the right: each block is time spent in the rule's apps.
/// Blocks slide out on the left as their time comes back.
class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.status, required this.window, this.height = 10});

  final Status status;
  final int window;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomPaint(
          size: Size.fromHeight(height),
          painter: _Strip(
            status: status,
            window: Duration(minutes: window),
            track: cs.surfaceContainerHighest,
            sand: status.paused ? cs.error : cs.primary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('il y a ${windowLabel(window)}', style: muted),
            const Spacer(),
            Text('maintenant', style: muted),
          ],
        ),
      ],
    );
  }
}

class _Strip extends CustomPainter {
  _Strip({required this.status, required this.window, required this.track, required this.sand});

  final Status status;
  final Duration window;
  final Color track, sand;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    final from = status.now.subtract(window);
    double x(DateTime t) => (t.difference(from).inMilliseconds / window.inMilliseconds).clamp(0, 1) * size.width;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, r));
    for (final (start, end) in status.sessions) {
      // At least 2 px, so a few seconds still show.
      final left = x(start), right = x(end);
      canvas.drawRect(Rect.fromLTRB(left, 0, right < left + 2 ? left + 2 : right, size.height), Paint()..color = sand);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Strip old) => old.status != status || old.sand != sand || old.track != track;
}

class RuleCard extends StatelessWidget {
  const RuleCard({super.key, required this.rule, required this.status, required this.onTap});

  final Rule rule;
  final Status? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = status;
    final line = !rule.on
        ? 'Désactivée'
        : s == null
        ? ''
        : s.paused
        ? 'En pause jusqu\'à ${hhmm(s.until!)}'
        : '${fmt(s.left)} restantes · ${fmt(s.used)} utilisées';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (rule.apps.isNotEmpty) ...[AppStack(rule.apps), const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rule.name, style: theme.textTheme.titleMedium),
                        Text(rule.summary, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Switch(
                    value: rule.on,
                    // Not while paused: switching it off would end the pause.
                    onChanged: s?.paused == true
                        ? null
                        : (v) {
                            rule.on = v;
                            guard.save();
                          },
                  ),
                ],
              ),
              if (s != null && rule.on) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Timeline(status: s, window: rule.window),
                ),
              ],
              if (line.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (s?.paused == true && rule.on) ...[
                      Icon(Icons.lock_clock, size: 18, color: cs.error),
                      const SizedBox(width: 6),
                    ],
                    Text(line, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
