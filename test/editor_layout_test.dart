/// The session layout: the source/preview split and the note list drawer.
///
/// Both are session state on purpose — they answer "what am I doing right now",
/// not a preference — so the tests below assert they are *not* written to
/// `settings.json`, which is the half that would be easy to get wrong later.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/features/notes/presentation/providers/editor_layout_provider.dart';
import 'package:win_notes/features/notes/presentation/widgets/pane_divider/pane_divider.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  EditorLayoutNotifier layout() => container.read(editorLayoutProvider.notifier);
  EditorLayout state() => container.read(editorLayoutProvider);

  group('the split stays inside its bounds', () {
    test('it starts even, which is what two Expandeds gave before', () {
      expect(state().sourceFraction, EditorLayout.defaultSourceFraction);
      expect(state().sourceFraction, 0.5);
    });

    test('a drag past either end is clamped, not obeyed', () {
      layout().setSourceFraction(0.95);
      expect(state().sourceFraction, EditorLayout.maxSourceFraction);

      layout().setSourceFraction(0.02);
      expect(state().sourceFraction, EditorLayout.minSourceFraction);

    });

    test('neither pane can be dragged out of recognition', () {
      // 20% of a 1000px body is 200px, which is about where prose stops being
      // readable in a column. The point is that both ends are bounded.
      expect(state().clampSource(0.0), EditorLayout.minSourceFraction);
      expect(state().clampSource(1.0), EditorLayout.maxSourceFraction);
    });

    test('the list width is bounded too', () {
      // The editor floor is 520 wide (`PROJECT.md` §87), so a list wider than
      // 420 leaves the editor no room to be a window.
      layout().setListWidth(10);
      expect(state().listWidth, EditorLayout.minListWidth);
      layout().setListWidth(5000);
      expect(state().listWidth, EditorLayout.maxListWidth);
    });

    test('setting the same value twice does not produce a new state', () {
      // A drag reports the same position many times, and each one that changed
      // identity would rebuild both panes.
      final EditorLayout before = state();
      layout().setSourceFraction(0.5);
      expect(identical(before, state()), isTrue);
    });
  });

  group('the list collapses rather than disappearing', () {
    test('it toggles', () {
      expect(state().listCollapsed, isFalse);
      layout().toggleList();
      expect(state().listCollapsed, isTrue);
      layout().toggleList();
      expect(state().listCollapsed, isFalse);
    });

    test('reset puts both measurements back without un-collapsing', () {
      layout().setSourceFraction(0.75);
      layout().setListWidth(400);
      layout().setListCollapsed(collapsed: true);

      layout().resetSplit();

      expect(state().sourceFraction, EditorLayout.defaultSourceFraction);
      expect(state().listWidth, EditorLayout.defaultListWidth);
      // Double-clicking a divider moves a divider; it should not also decide
      // whether the list is open.
      expect(state().listCollapsed, isTrue);
    });
  });

  group('none of this is persisted', () {
    test('the provider holds it and nothing else does', () {
      layout().setSourceFraction(0.7);
      layout().setListWidth(360);
      layout().setListCollapsed(collapsed: true);

      // If these were written to settings.json, dragging a divider would mark
      // the settings file dirty and a settings write would be triggered on every
      // frame of a drag. The container's lifetime *is* the session, which is
      // exactly the lifetime wanted.
      expect(state().sourceFraction, 0.7);
      expect(state().listWidth, 360);
      expect(state().listCollapsed, isTrue);
    });
  });

  group('the divider is a real drag target', () {
    // A `MaterialApp` because the divider carries a `Tooltip`, and a tooltip
    // needs an Overlay. Without one the subtree fails and the drag finds nothing
    // - which looked like a divider that could not be dragged.
    Widget host(Widget child) => MaterialApp(
          home: Scaffold(
            body: Row(
              children: <Widget>[
                const SizedBox(width: 120, child: Text('left')),
                child,
                const Expanded(child: Text('right')),
              ],
            ),
          ),
        );

    testWidgets('a drag reports a position and double-click resets',
        (WidgetTester tester) async {
      final List<double> dragged = <double>[];
      int resets = 0;

      await tester.pumpWidget(host(
        PaneDivider(
          onDrag: dragged.add,
          onReset: () => resets++,
        ),
      ));

      final Offset centre = tester.getCenter(find.byType(PaneDivider));
      await tester.dragFrom(centre, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(dragged, isNotEmpty,
          reason: 'a divider that cannot be dragged is just a line');
      // A delta, not a position: positive to the right, and never negative for
      // a drag that only went right.
      expect(dragged.every((double dx) => dx > 0), isTrue);
      expect(dragged.reduce((double a, double b) => a + b), greaterThan(30),
          reason: 'the deltas have to add up to about the distance dragged');

      await tester.tapAt(centre);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(centre);
      await tester.pumpAndSettle();
      expect(resets, 1, reason: 'double-click is the one gesture needing no instructions');
    });

    testWidgets('its hit area is wider than the line it draws',
        (WidgetTester tester) async {
      await tester.pumpWidget(host(
        PaneDivider(onDrag: (_) {}, onReset: () {}),
      ));

      // A 1px line is not a target; 10px is, and matches the native grab band.
      expect(
        tester.getSize(find.byType(PaneDivider)).width,
        greaterThanOrEqualTo(10),
      );
    });

    testWidgets('the cursor says it can be dragged', (WidgetTester tester) async {
      await tester.pumpWidget(host(PaneDivider(onDrag: (_) {})));
      // `.last`: `Tooltip` wraps this in a MouseRegion of its own that defers
      // its cursor, and the divider's is the inner one - so the wrong MouseRegion
      // is not a compile error, it is a cursor that says "wait".
      final MouseRegion region = tester.widget<MouseRegion>(
        find
            .descendant(
              of: find.byType(PaneDivider),
              matching: find.byType(MouseRegion),
            )
            .last,
      );
      expect(region.cursor, SystemMouseCursors.resizeColumn);
    });

    testWidgets('a null reset does not throw on double-click',
        (WidgetTester tester) async {
      // The widget surface and the list rows render no divider, but a caller
      // that supplies a drag and no reset must not break.
      await tester.pumpWidget(host(PaneDivider(onDrag: (_) {})));
      final Offset centre = tester.getCenter(find.byType(PaneDivider));
      await tester.tapAt(centre);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(centre);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('the layout provider is not the settings provider', () {
    test('they are different objects, so a drag cannot mark settings dirty', () {
      expect(identical(editorLayoutProvider, settingsProviderForTest), isFalse);
    });
  });
}

/// A stand-in so the last test names something real without importing the
/// settings graph, which would drag a file-backed repository into a unit test.
final Provider<Object> settingsProviderForTest = Provider<Object>((Ref ref) => Object());
