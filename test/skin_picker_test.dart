// The Skin **picker**, as a widget.
//
// `skin_test` covers the model and the setting. Neither proves the row in
// Settings exists, draws, or can be tapped - and the same is true of the palette
// picker, whose test is model-only, which is how a control can be written,
// compile, analyse clean, and never have been rendered by anything.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/theme/skin.dart';
import 'package:win_notes/core/theme/theme.dart';
import 'package:win_notes/features/settings/presentation/widgets/none_swatch/none_swatch.dart';
import 'package:win_notes/features/settings/presentation/widgets/skin_picker/skin_picker.dart';
import 'package:win_notes/features/settings/presentation/widgets/skin_swatch/skin_swatch.dart';

const Color accent = Color(0xFF4B3FC0);

Future<void> pumpPicker(
  WidgetTester tester, {
  WinNotesSkin? selected,
  required ValueChanged<WinNotesSkin?> onSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWinNotesTheme(brightness: Brightness.light, highContrast: false),
      home: Scaffold(
        body: SkinPicker(selected: selected, onSelected: onSelected, accent: accent),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every corner radius in the tree, which is how the chips' shape is checked
/// without asserting on the skin model back.
Set<double> drawnRadii(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .map((Container c) => c.decoration)
    .whereType<BoxDecoration>()
    .map((BoxDecoration d) => d.borderRadius)
    .whereType<BorderRadius>()
    .map((BorderRadius r) => r.topLeft.x)
    .toSet();

void main() {
  testWidgets('every skin is offered, and None comes first', (WidgetTester tester) async {
    await pumpPicker(tester, selected: null, onSelected: (_) {});

    expect(find.byType(SkinSwatch), findsNWidgets(winNotesSkins.length));
    expect(find.byType(NoneSwatch), findsOneWidget);
  });

  testWidgets('tapping a chip reports that skin', (WidgetTester tester) async {
    WinNotesSkin? reported;
    await pumpPicker(tester,
        selected: null, onSelected: (WinNotesSkin? s) => reported = s);

    for (final WinNotesSkin skin in winNotesSkins) {
      reported = null;
      await tester.tap(find.bySemanticsLabel('${skin.label} skin'));
      await tester.pumpAndSettle();
      expect(reported, same(skin), reason: '${skin.id} did not report itself');
    }
  });

  testWidgets('the first chip clears the skin rather than picking the first one',
      (WidgetTester tester) async {
    // The distinction the whole feature rests on: "no skin" is not "skin one".
    WinNotesSkin? reported = skinById('solid');
    await pumpPicker(tester,
        selected: skinById('solid'), onSelected: (WinNotesSkin? s) => reported = s);

    await tester.tap(find.bySemanticsLabel('No skin'));
    await tester.pumpAndSettle();

    expect(reported, isNull);
    expect(reported, isNot(winNotesSkins.first));
  });

  testWidgets('the chosen chip is the one marked selected', (WidgetTester tester) async {
    await pumpPicker(tester, selected: skinById('soft'), onSelected: (_) {});

    final Iterable<Widget> selected = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((Semantics s) => s.properties.selected == true);
    expect(selected, hasLength(1));
    expect(find.bySemanticsLabel('Soft skin'), findsOneWidget);
  });

  testWidgets('the label under the row names the choice', (WidgetTester tester) async {
    await pumpPicker(tester, selected: skinById('sharp'), onSelected: (_) {});
    expect(find.text('Sharp'), findsOneWidget);

    await pumpPicker(tester, selected: null, onSelected: (_) {});
    expect(find.text('Default'), findsOneWidget,
        reason: 'no skin reads as Default, not as the first skin');
  });

  testWidgets('the chips draw shape, and different skins draw different shapes',
      (WidgetTester tester) async {
    // The mistake this feature corrected: a chip that previewed colour made Skin
    // a second Colour control. Sharp and Soft differ in nothing but shape, so a
    // set of drawn radii that cannot tell them apart means colour crept back in.
    for (final WinNotesSkin skin in winNotesSkins) {
      await pumpPicker(tester, selected: null, onSelected: (_) {});
      final Set<double> radii = drawnRadii(tester);
      expect(radii, contains(skin.cornerRadius),
          reason: '${skin.id} declared ${skin.cornerRadius} but drew $radii');
    }

    final Set<double> sharp = await _chipRadii(tester, 'Sharp');
    final Set<double> soft = await _chipRadii(tester, 'Soft');
    expect(sharp, contains(0.0), reason: 'Sharp declared a square corner');
    expect(soft, contains(18.0), reason: 'Soft declared an 18px corner');
    expect(sharp, isNot(soft),
        reason: 'Sharp and Soft differ only in shape; identical chips mean the '
            'preview is not showing shape');
  });

  testWidgets('a chip draws a separator when its skin asks for one',
      (WidgetTester tester) async {
    // Outline uses hairlines, Solid uses gaps, so one row of the chip shows a
    // Divider and the other shows nothing.
    await pumpPicker(tester, selected: skinById('outline'), onSelected: (_) {});
    final Finder outlineChip = find.bySemanticsLabel('Outline skin');
    expect(find.descendant(of: outlineChip, matching: find.byType(Divider)),
        findsOneWidget);

    await pumpPicker(tester, selected: skinById('solid'), onSelected: (_) {});
    final Finder solidChip = find.bySemanticsLabel('Solid skin');
    expect(find.descendant(of: solidChip, matching: find.byType(Divider)),
        findsNothing);
  });
}

/// The radii drawn **inside one chip**, not across the picker - every chip is on
/// screen at once, so a whole-picker measurement is the union of all four skins
/// and cannot tell any two of them apart.
Future<Set<double>> _chipRadii(WidgetTester tester, String label) async {
  final Finder chip = find.bySemanticsLabel('$label skin');
  return tester
      .widgetList<Container>(find.descendant(of: chip, matching: find.byType(Container)))
      .map((Container c) => c.decoration)
      .whereType<BoxDecoration>()
      .map((BoxDecoration d) => d.borderRadius)
      .whereType<BorderRadius>()
      .map((BorderRadius r) => r.topLeft.x)
      .toSet();
}