import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'guard.dart';
import 'pause.dart';
import 'rule.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await guard.load();
  runApp(const App());
}

final navigator = GlobalKey<NavigatorState>();
final messenger = GlobalKey<ScaffoldMessengerState>();

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
    builder: (light, dark) {
      // The wallpaper's primary as seed: the full Material 3 scheme in the system's colors.
      ColorScheme scheme(Brightness b, ColorScheme? system) =>
          ColorScheme.fromSeed(seedColor: system?.primary ?? sand, brightness: b);
      return MaterialApp(
        title: 'Sablier',
        navigatorKey: navigator,
        scaffoldMessengerKey: messenger,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(scheme(Brightness.light, light)),
        darkTheme: buildTheme(scheme(Brightness.dark, dark)),
        home: const Home(),
      );
    },
  );
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The pause screen: when Guard brings the app back for it, and when it launched the app.
    channel.setMethodCallHandler((call) async => call.method == 'paused' ? _pause(call.arguments as String) : null);
    channel.invokeMethod<String>('takePaused').then((id) => id == null ? null : _pause(id));
    // The sand moves while the app is on screen.
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) guard.refresh();
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the system settings (permissions) or from the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) guard.refresh();
  }

  void _pause(String id) {
    final rule = guard.rules.where((r) => r.id == id).firstOrNull;
    if (rule == null) return;
    guard.refresh();
    navigator.currentState!
      ..popUntil((r) => r.isFirst)
      ..push(MaterialPageRoute(builder: (_) => PausePage(rule: rule)));
  }

  void _edit(Rule rule, {bool isNew = false}) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RulePage(rule: rule, isNew: isNew),
    ),
  );

  void _locked(Status s) => messenger.currentState?.showSnackBar(
    SnackBar(content: Text('Règle verrouillée pendant la pause, jusqu\'à ${hhmm(s.until!)}.')),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sablier')),
    floatingActionButton: FloatingActionButton.extended(
      icon: const Icon(Icons.add),
      label: const Text('Règle'),
      onPressed: () => _edit(Rule(id: guard.newId(), name: '', apps: {}), isNew: true),
    ),
    body: ListenableBuilder(
      listenable: guard,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (!guard.ready) ...[const Setup(), const SizedBox(height: 12)],
          for (final rule in guard.rules) ...[
            RuleCard(
              rule: rule,
              status: guard.status[rule.id],
              // A paused rule can't be loosened until its pause is over: that would be too easy.
              onTap: () => guard.status[rule.id]?.paused == true ? _locked(guard.status[rule.id]!) : _edit(rule),
            ),
            const SizedBox(height: 12),
          ],
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Le temps passé revient comme le sable : avec une règle « par heure », une minute utilisée à 14 h 10 '
              'est de nouveau disponible à 15 h 10. Assez pour répondre à vos messages, pas pour défiler sans fin.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The two permissions the rules need, until both are granted.
class Setup extends StatelessWidget {
  const Setup({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget step(bool done, IconData icon, String title, String subtitle, String method) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: done ? Icon(Icons.check_circle, color: cs.primary) : const Icon(Icons.chevron_right),
      onTap: done ? null : () => channel.invokeMethod(method),
    );
    return Card(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text('Deux autorisations pour commencer', style: Theme.of(context).textTheme.titleMedium),
            ),
            step(
              guard.usageAccess,
              Icons.query_stats,
              "Accès aux données d'utilisation",
              'Pour compter le temps passé dans chaque application.',
              'openUsage',
            ),
            step(
              guard.serviceOn,
              Icons.accessibility_new,
              "Service d'accessibilité « Sablier »",
              "Pour voir quelle application s'ouvre et la mettre en pause. Il ne lit jamais l'écran.",
              'openGuard',
            ),
            if (!guard.serviceOn)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton.icon(
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Interrupteur grisé ? Autorisez les paramètres restreints (menu ⋮)'),
                  onPressed: () => channel.invokeMethod('openAppInfo'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
