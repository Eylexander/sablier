import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Kotlin side (MainActivity.kt): rules are stored there so the accessibility service (Guard.kt) can read them.
const channel = MethodChannel('sablier/guard');

/// The apps of a rule may be on screen [budget] minutes in any [window] minutes. The window slides: each minute
/// used comes back [window] minutes later, like sand.
class Rule {
  Rule({required this.id, required this.name, required this.apps, this.budget = 5, this.window = 60, this.on = true});

  final String id;
  String name;
  Set<String> apps;
  int budget, window;
  bool on;

  factory Rule.fromJson(Map<String, dynamic> j) => Rule(
    id: j['id'],
    name: j['name'],
    apps: {...(j['apps'] as List).cast<String>()},
    budget: j['budget'],
    window: j['window'],
    on: j['on'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'apps': [...apps],
    'budget': budget,
    'window': window,
    'on': on,
  };

  String get summary => '$budget min ${windowLabel(window, per: true)}';
}

/// A rule's state right now, from Android's usage stats.
class Status {
  Status(Map m)
    : now = DateTime.fromMillisecondsSinceEpoch(m['now']),
      used = Duration(milliseconds: m['used']),
      left = Duration(milliseconds: m['left']),
      until = m['until'] == 0 ? null : DateTime.fromMillisecondsSinceEpoch(m['until']),
      sessions = [
        for (var i = 0; i < (m['sessions'] as List).length; i += 2)
          (
            DateTime.fromMillisecondsSinceEpoch(m['sessions'][i]),
            DateTime.fromMillisecondsSinceEpoch(m['sessions'][i + 1]),
          ),
      ];

  final DateTime now;
  final Duration used, left;

  /// End of the pause, while the budget is spent.
  final DateTime? until;

  /// When the rule's apps were on screen within the window.
  final List<(DateTime, DateTime)> sessions;

  bool get paused => until != null;
}

/// Window choices, in minutes.
const windows = [30, 60, 180, 1440];

/// Budget choices, in minutes; only those shorter than the window are offered.
const budgets = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120];

String windowLabel(int minutes, {bool per = false}) => switch (minutes) {
  1440 => per ? 'par jour' : '24 h',
  60 => per ? 'par heure' : '1 h',
  < 60 => per ? 'par $minutes min' : '$minutes min',
  _ => per ? 'toutes les ${minutes ~/ 60} h' : '${minutes ~/ 60} h',
};

/// 45 s, 4 min 30, 1 h 05.
String fmt(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '$s s';
  if (s < 3600) return s % 60 == 0 ? '${s ~/ 60} min' : '${s ~/ 60} min ${(s % 60).toString().padLeft(2, '0')}';
  return '${s ~/ 3600} h ${(s % 3600 ~/ 60).toString().padLeft(2, '0')}';
}

String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Apps people usually want to ration, preselected in the first rule when installed.
const social = [
  'com.instagram.android',
  'com.myinsta.android',
  'com.zhiliaoapp.musically',
  'com.twitter.android',
  'com.snapchat.android',
  'com.reddit.frontpage',
  'com.facebook.katana',
];

class Guard extends ChangeNotifier {
  List<Rule> rules = [];
  Map<String, Status> status = {};
  bool usageAccess = false, serviceOn = false;

  /// Launchable apps as (package, label), by label.
  List<(String, String)> apps = [];
  final _icons = <String, Future<Uint8List?>>{};

  bool get ready => usageAccess && serviceOn;
  String label(String pkg) => apps.firstWhere((a) => a.$1 == pkg, orElse: () => (pkg, pkg)).$2;
  Future<Uint8List?> icon(String pkg) => _icons[pkg] ??= channel.invokeMethod<Uint8List>('icon', pkg);

  Future<void> load() async {
    apps = [for (final a in await channel.invokeListMethod<List>('apps') ?? []) (a[0] as String, a[1] as String)];
    final json = await channel.invokeMethod<String>('rules');
    if (json == null) {
      // First launch: one rule for the social apps that are installed.
      final installed = {for (final a in apps) a.$1};
      rules = [
        Rule(id: '1', name: 'Réseaux sociaux', apps: {...social.where(installed.contains)}),
      ];
      await save();
    } else {
      rules = [for (final r in jsonDecode(json) as List) Rule.fromJson(r)];
    }
    await refresh();
  }

  Future<void> save() async {
    await channel.invokeMethod('setRules', jsonEncode(rules));
    await refresh();
  }

  Future<void> refresh() async {
    final access = await channel.invokeMapMethod<String, bool>('access') ?? {};
    usageAccess = access['usage'] ?? false;
    serviceOn = access['guard'] ?? false;
    status = usageAccess
        ? {for (final m in await channel.invokeListMethod<Map>('status') ?? []) m['id']: Status(m)}
        : {};
    notifyListeners();
  }

  void put(Rule rule) {
    final i = rules.indexWhere((r) => r.id == rule.id);
    i < 0 ? rules.add(rule) : rules[i] = rule;
    save();
  }

  void remove(Rule rule) {
    rules.removeWhere((r) => r.id == rule.id);
    save();
  }

  String newId() => '${DateTime.now().millisecondsSinceEpoch}';
}

final guard = Guard();
