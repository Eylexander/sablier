import 'package:flutter_test/flutter_test.dart';
import 'package:sablier/guard.dart';

void main() {
  test('fmt', () {
    expect(fmt(const Duration(seconds: 45)), '45 s');
    expect(fmt(const Duration(minutes: 5)), '5 min');
    expect(fmt(const Duration(minutes: 4, seconds: 5)), '4 min 05');
    expect(fmt(const Duration(hours: 1, minutes: 5)), '1 h 05');
  });

  test('rule summary', () {
    Rule r(int window) => Rule(id: '1', name: 'x', apps: {}, budget: 5, window: window);
    expect(r(60).summary, '5 min par heure');
    expect(r(30).summary, '5 min par 30 min');
    expect(r(180).summary, '5 min toutes les 3 h');
    expect(r(1440).summary, '5 min par jour');
  });

  test('rule json round trip', () {
    final r = Rule(id: '7', name: 'Réseaux', apps: {'a', 'b'}, budget: 10, window: 180, on: false);
    expect(Rule.fromJson(r.toJson()).toJson(), r.toJson());
  });

  test('status from the channel', () {
    final s = Status({
      'now': 3600000,
      'used': 300000,
      'left': 0,
      'until': 3660000,
      'sessions': [0, 120000, 3000000, 3180000],
    });
    expect(s.paused, isTrue);
    expect(s.sessions.length, 2);
    expect(s.sessions[1].$2, DateTime.fromMillisecondsSinceEpoch(3180000));
    expect(Status({'now': 0, 'used': 0, 'left': 300000, 'until': 0, 'sessions': []}).paused, isFalse);
  });
}
