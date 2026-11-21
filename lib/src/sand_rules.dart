import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';

import 'sand_engine.dart';

const kumBloklariId = 'oyun-kum-bloklari';

class SandRules extends GameRules<SandLevel> {
  @override
  String get gameId => kumBloklariId;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [
        GameModeId.campaign,
        GameModeId.endless,
        GameModeId.zen,
        GameModeId.daily,
        GameModeId.weekly,
        GameModeId.challenge,
      ];

  @override
  List<GameStat> get gameStats => const [
        GameStat('bridges', 'Renk köprüsü', 'Color bridges', scale: 5),
        GameStat('grains', 'Silinen kum', 'Sand cleared', scale: 2000),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('bridges', 'bridges', [2, 5, 12]),
      ];

  @override
  SandLevel generate(LevelSpec spec) => generateSandLevel(spec);

  @override
  Validation validate(SandLevel level, LevelSpec spec) {
    if (level.target == 0) return const Validation.ok();
    final m = simulateSandLevel(level);
    if (m < 0) return const Validation.fail('bot could not finish');
    return Validation.ok(m);
  }

  SandLevel finalize(GeneratedLevel<SandLevel> g) {
    final l = g.puzzle;
    if (l.target == 0 || l.difficulty < 5) return l;
    return l.withLimit((g.validation.metric * (2.2 - l.difficulty * 0.08)).ceil() + 6);
  }

  static int stars(SandGame g) {
    if (!g.won) return 0;
    if (g.lost) return 0;
    if (g.level.moveLimit == 0) return g.moves <= 12 * g.level.target ? 3 : 2;
    final left = g.level.moveLimit - g.moves;
    return left >= g.level.moveLimit ~/ 3 ? 3 : (left >= 3 ? 2 : 1);
  }
}
