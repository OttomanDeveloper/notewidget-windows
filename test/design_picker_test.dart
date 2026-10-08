// The design chips: what is offered, what they report, and what "None" means.
//
// The picker is the only way to reach the feature, so a chip that draws but does
// not report is a control that looks like it works. Mirrors `skin_picker_test`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/features/settings/presentation/widgets/design_chip/design_chip.dart';
import 'package:win_notes/features/settings/presentation/widgets/design_picker/design_picker.dart';
import 'package:win_notes/features/widget/domain/widget_design.dart';

Future<List<WidgetDesign?>> pumpPicker(
  WidgetTester tester, {
  required WidgetDesign? selected,
}) async {
  final List<WidgetDesign?> reported = <WidgetDesign?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 260,
          child: DesignPicker(
            selected: selected,
            onSelected: reported.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return reported;
}

void main() {
  testWidgets('every design is offered, and None comes first',
      (WidgetTester tester) async {
    await pumpPicker(tester, selected: null);
    final List<String> labels = tester
        .widgetList<DesignChip>(find.byType(DesignChip))
        .map((DesignChip c) => c.label)
        .toList();
    expect(labels.first, 'None');
    expect(labels.length, widgetDesigns.length + 1);
    expect(labels.skip(1).toList(),
        widgetDesigns.map((WidgetDesign d) => d.label).toList(),
        reason: 'the order Settings shows them and the order the model lists'
            ' them have to agree');
  });

  testWidgets('tapping a chip reports that design', (WidgetTester tester) async {
    final List<WidgetDesign?> reported =
        await pumpPicker(tester, selected: null);

    for (final WidgetDesign design in widgetDesigns) {
      await tester.tap(find.text(design.label));
      await tester.pumpAndSettle();
    }
    expect(reported, widgetDesigns,
        reason: 'every design has to be reachable, or a person cannot choose it');
  });

  testWidgets('the first chip clears the design rather than picking the first one',
      (WidgetTester tester) async {
    final List<WidgetDesign?> reported =
        await pumpPicker(tester, selected: widgetDesigns.first);

    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(reported.single, isNull,
        reason: 'None means the built-in card, and the built-in card is not in'
            ' the list - so picking the first entry would offer it twice');
  });

  testWidgets('the chosen chip is the one marked selected',
      (WidgetTester tester) async {
    await pumpPicker(tester, selected: designById('ticket'));
    final List<DesignChip> chips =
        tester.widgetList<DesignChip>(find.byType(DesignChip)).toList();
    final Set<String> chosen = chips
        .where((DesignChip c) => c.chosen)
        .map((DesignChip c) => c.label)
        .toSet();
    expect(chosen, <String>{'Ticket'});
  });

  testWidgets('None is marked when nothing is chosen', (WidgetTester tester) async {
    await pumpPicker(tester, selected: null);
    final List<DesignChip> chips =
        tester.widgetList<DesignChip>(find.byType(DesignChip)).toList();
    expect(chips.where((DesignChip c) => c.chosen).map((DesignChip c) => c.label),
        <String>{'None'});
  });

  testWidgets('the chips fit the row they are given', (WidgetTester tester) async {
    // Six chips in a `SettingsRow`'s unconstrained trailing slot overflowed by
    // 27px and took nine unrelated tests with it, so the bound is the rule.
    await pumpPicker(tester, selected: null);
    expect(tester.takeException(), isNull);
  });
}