import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_kum_bloklari/oyun_kum_bloklari.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final rules = SandRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  test('kum akar ve durur; tane sayısı korunur', () {
    final g = SandGame(rules.build(planner.spec(1, mode: GameModeId.endless)).puzzle);
    expect(g.drop(0, 3), isTrue);
    final before = g.g.where((v) => v != 0).length;
    var guard = 0;
    while (g.stepSand() > 0 && guard++ < 500) {}
    expect(guard, lessThan(500));
    expect(g.g.where((v) => v != 0).length, before);
    // En alt sıraya ulaştı.
    expect(g.g.sublist((kSH - 1) * kSW).any((v) => v != 0), isTrue);
  });

  test('soldan sağa aynı renk köprü silinir', () {
    final g = SandGame(rules.build(planner.spec(1, mode: GameModeId.endless)).puzzle);
    for (var x = 0; x < kSW; x++) {
      g.g[(kSH - 1) * kSW + x] = 2;
    }
    g.g[(kSH - 2) * kSW + 5] = 1;
    expect(g.clearBridges(), kSW);
    expect(g.bridges, 1);
  });

  test('kampanya bölümleri bot tarafından bitirilir', () {
    for (final lv in [1, 12, 50, 99, 230, 777, 2500, 9999, 33333, 49999]) {
      final gl = rules.build(planner.spec(lv));
      expect(gl.validation.ok, isTrue, reason: 'bölüm $lv');
      expect(gl.attempts, lessThan(40), reason: 'bölüm $lv kolaylaştırıldı');
      final l = rules.finalize(gl);
      final m = simulateSandLevel(l);
      expect(m, greaterThan(0), reason: 'bölüm $lv');
    }
  });

  test('kayıt geri yüklenince aynı devam eder', () {
    final l = rules.build(planner.spec(55)).puzzle;
    final g = SandGame(l);
    for (var k = 0; k < 6; k++) {
      final m = g.bestMove();
      if (m == null) break;
      g.drop(m.$1, m.$2);
      g.settle();
    }
    final r = SandGame.restore(l, g.serialize());
    expect(r.serialize(), g.serialize());
  });
}
