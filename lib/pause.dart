import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'guard.dart';
import 'widgets.dart';

/// Something to do instead, shown on the pause screen; tapping it shows another. Some come with a button: its label
/// and what the channel's `open` starts (MainActivity.kt).
const ideas = <(String, String?, String?)>[
  ("Buvez un grand verre d'eau.", null, null),
  ('Levez-vous et étirez-vous une minute.', null, null),
  ('Ouvrez la fenêtre et respirez à fond, cinq fois.', null, null),
  ('Faites dix squats ou dix pompes.', null, null),
  ('Allez marcher, même cinq minutes.', 'Minuteur 5 min', 'timer:300'),
  ("Lisez quelques pages d'un livre.", null, null),
  ("Appelez quelqu'un plutôt que de lui écrire.", 'Appeler', 'dial'),
  ('Rangez une chose qui traîne autour de vous.', null, null),
  ('Notez ce qui vous trotte dans la tête.', null, null),
  ('Regardez au loin par la fenêtre pour reposer vos yeux.', null, null),
  ('Mettez un album et écoutez-le en entier.', 'Musique', 'music'),
  ('Avancez sur la tâche que vous repoussez, cinq minutes seulement.', 'Minuteur 5 min', 'timer:300'),
  ('Préparez-vous un thé ou un café, sans écran.', 'Minuteur 4 min', 'timer:240'),
  ('Fermez les yeux et ne faites rien pendant deux minutes.', 'Minuteur 2 min', 'timer:120'),
];

/// Shown over an app whose time is spent (opened by Guard.kt). Leaving it, by the button or back, goes to the home
/// screen, not back to the app.
class PausePage extends StatefulWidget {
  const PausePage({super.key, required this.rule});

  final Rule rule;

  @override
  State<PausePage> createState() => _PausePageState();
}

class _PausePageState extends State<PausePage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _flip = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  late final Timer _clock;
  var _idea = Random().nextInt(ideas.length);

  /// Seconds still to wait for more time, while asked.
  int? _wait;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _wait = _wait == null ? null : _wait! - 1);
      if (_wait == 0) _extend();
    });
  }

  // The wait has to be watched: leaving the screen, or turning it off, starts it over.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) setState(() => _wait = null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.cancel();
    _flip.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context).pop();
    channel.invokeMethod('home');
  }

  Future<void> _extend() async {
    _wait = null;
    if (await channel.invokeMethod<bool>('extend', widget.rule.id) != true || !mounted) return;
    await guard.refresh();
    if (!mounted) return;
    Navigator.of(context).pop();
    channel.invokeMethod('back');
  }

  Future<void> _open(String what) async {
    if (await channel.invokeMethod<bool>('open', what) != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune appli pour ça.')));
    }
  }

  /// More time: a wait to sit through on this screen, longer each time, a few times a day.
  Widget _more(ThemeData theme, Status s) {
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (s.extras >= extrasPerDay) return Text("Plus de rallonge aujourd'hui.", style: muted);
    final wait = extraWait(s.extras);
    if (_wait == null) {
      return TextButton.icon(
        icon: const Icon(Icons.more_time),
        label: Text('$extraMinutes min de plus (attendre ${fmt(wait)})'),
        onPressed: () => setState(() => _wait = wait.inSeconds),
      );
    }
    return Column(
      children: [
        LinearProgressIndicator(value: 1 - _wait! / wait.inSeconds),
        const SizedBox(height: 8),
        Text('Encore $_wait s, sans quitter cet écran.', style: muted),
        TextButton(onPressed: () => setState(() => _wait = null), child: const Text('Annuler')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rule = widget.rule;
    final s = guard.status[rule.id];
    final left = s?.until?.difference(DateTime.now());
    final back = left == null || left.isNegative;
    final idea = ideas[_idea];
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
                  if (rule.extra) ...[const SizedBox(height: 16), _more(theme, s)],
                ],
                const Spacer(),
                Card.filled(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.lightbulb_outline),
                        title: Text(idea.$1),
                        trailing: const Icon(Icons.refresh),
                        onTap: () => setState(() => _idea = (_idea + 1) % ideas.length),
                      ),
                      if (idea.$2 != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            child: TextButton(onPressed: () => _open(idea.$3!), child: Text(idea.$2!)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
