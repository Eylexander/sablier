import 'dart:async';

import 'package:flutter/material.dart';

import 'guard.dart';
import 'widgets.dart';

/// Shown over an app whose time is spent (opened by Guard.kt). Leaving it, by the button or back, goes to the home
/// screen, not back to the app.
class PausePage extends StatefulWidget {
  const PausePage({super.key, required this.rule});

  final Rule rule;

  @override
  State<PausePage> createState() => _PausePageState();
}

class _PausePageState extends State<PausePage> with SingleTickerProviderStateMixin {
  late final _flip = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock.cancel();
    _flip.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context).pop();
    channel.invokeMethod('home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rule = widget.rule;
    final s = guard.status[rule.id];
    final left = s?.until?.difference(DateTime.now());
    final back = left == null || left.isNegative;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => didPop ? null : _close(),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                  // The hourglass turns over every few seconds.
                  child: RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.5).animate(
                      CurvedAnimation(
                        parent: _flip,
                        curve: const Interval(0.8, 1, curve: Curves.easeInOutCubic),
                      ),
                    ),
                    child: Icon(Icons.hourglass_empty, size: 72, color: cs.onPrimaryContainer),
                  ),
                ),
                const SizedBox(height: 32),
                Text(back ? 'Le sable est revenu' : 'Pause', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 12),
                Text(
                  '${rule.name} : vos ${rule.summary} sont écoulées.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                if (!back) ...[
                  Text('De retour dans', style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                  Text(fmt(left + const Duration(seconds: 1)), style: theme.textTheme.displaySmall),
                  Text('à ${hhmm(s!.until!)}', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  Timeline(status: s, window: rule.window),
                ],
                const Spacer(),
                Text(
                  'Vos messages vous attendront.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(onPressed: _close, child: const Text('Fermer')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
