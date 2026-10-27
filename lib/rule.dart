import 'package:flutter/material.dart';

import 'guard.dart';
import 'widgets.dart';

/// Edits a copy of a rule: name, time allowed per window, and its apps.
class RulePage extends StatefulWidget {
  const RulePage({super.key, required this.rule, this.isNew = false});

  final Rule rule;
  final bool isNew;

  @override
  State<RulePage> createState() => _RulePageState();
}

class _RulePageState extends State<RulePage> {
  late final r = Rule.fromJson(widget.rule.toJson());
  // Ordered once, chosen apps first, so the list doesn't jump while ticking boxes.
  late final List<(String, String)> _order = [
    ...guard.apps.where((a) => r.apps.contains(a.$1)),
    ...guard.apps.where((a) => !r.apps.contains(a.$1)),
  ];
  String _query = '';

  List<int> get _budgets => budgets.where((b) => b < r.window).toList();

  void _save() {
    if (r.name.trim().isEmpty) r.name = r.apps.length == 1 ? guard.label(r.apps.first) : 'Règle';
    guard.put(r);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer « ${r.name} » ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    guard.remove(r);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.toLowerCase();
    final shown = q.isEmpty ? _order : _order.where((a) => a.$2.toLowerCase().contains(q) || a.$1.contains(q));
    final options = _budgets;
    Widget title(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Nouvelle règle' : 'Modifier la règle'),
        actions: [if (!widget.isNew) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TextFormField(
              initialValue: r.name,
              decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (v) => r.name = v,
            ),
          ),
          title('Temps autorisé'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(r.summary, style: theme.textTheme.headlineSmall),
          ),
          Slider(
            value: options.indexOf(r.budget).toDouble(),
            max: options.length - 1.0,
            divisions: options.length - 1,
            label: '${r.budget} min',
            onChanged: (v) => setState(() => r.budget = options[v.round()]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<int>(
              segments: [for (final w in windows) ButtonSegment(value: w, label: Text(windowLabel(w)))],
              selected: {r.window},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                r.window = s.first;
                if (!_budgets.contains(r.budget)) r.budget = _budgets.lastWhere((b) => b < r.budget, orElse: () => 1);
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'Chaque minute utilisée revient ${windowLabel(r.window)} plus tard. Une minute avant la fin, '
              'un message prévient ; ensuite, ces applications sont en pause.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          SwitchListTile(
            title: const Text('Rallonges'),
            subtitle: Text(
              "Depuis l'écran de pause : $extraMinutes min de plus après une attente (20 s, puis 40 s, 80 s), "
              '$extrasPerDay fois par jour au plus. Ces minutes ne retardent pas la pause suivante.',
            ),
            value: r.extra,
            onChanged: (v) => setState(() => r.extra = v),
          ),
          title('Applications (${r.apps.length}) · temps partagé'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          for (final (pkg, label) in shown)
            CheckboxListTile(
              secondary: AppIcon(pkg),
              title: Text(label),
              value: r.apps.contains(pkg),
              onChanged: (v) => setState(() => v! ? r.apps.add(pkg) : r.apps.remove(pkg)),
            ),
          const SizedBox(height: 16),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            onPressed: r.apps.isEmpty ? null : _save,
            child: Text(r.apps.isEmpty ? 'Choisissez au moins une application' : 'Enregistrer'),
          ),
        ),
      ),
    );
  }
}
