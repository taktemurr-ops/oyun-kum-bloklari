/// Kum Blokları: bloklar kuma dönüşür; aynı renkle soldan sağa köprü kur.
/// Blok Oyunları merkez uygulamasının oyunu.
library;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';

import 'src/sand_rules.dart';
import 'src/sand_view.dart';

export 'src/sand_engine.dart';
export 'src/sand_rules.dart';

final kumBloklariConfig = GameConfig(
  gameId: kumBloklariId,
  title: const ['Kum Blokları', 'Sand Blocks', 'Sandblöcke', 'Bloques de Arena', 'Blocs de Sable'],
  tagline: const [
    'Kumu akıt, renk köprüsü kur!',
    'Pour the sand, build a color bridge!',
    'Lass Sand fließen, bau eine Farbbrücke!',
    '¡Vierte arena y crea un puente de color!',
    'Versez le sable, créez un pont de couleur !',
  ],
  seedColor: const Color(0xFFD4A373),
  icon: Icons.grain_rounded,
  rules: SandRules(),
  buildPlay: (ctx) => SandView(ctx: ctx),
  tutorial: const [
    TutorialStep(Icons.pan_tool_alt, [
      'Parçayı tahtanın üstüne sürükle ya da seçip bir sütuna dokun. Parça kuma dönüşüp akar.',
      'Drag a piece over the board, or select it and tap a column. It turns to sand and flows.',
      'Ziehe ein Teil aufs Brett oder tippe eine Spalte an. Es wird zu Sand.',
      'Arrastra una pieza o tócala y luego una columna. Se convierte en arena.',
      'Glissez une pièce ou touchez une colonne. Elle devient du sable.',
    ]),
    TutorialStep(Icons.horizontal_rule, [
      'Aynı renk kum sol duvardan sağ duvara kesintisiz uzanırsa silinir.',
      'Sand of one color reaching from the left wall to the right wall clears.',
      'Sand einer Farbe von Wand zu Wand verschwindet.',
      'La arena de un color que une ambas paredes desaparece.',
      'Le sable d\'une couleur reliant les deux murs disparaît.',
    ]),
  ],
);
