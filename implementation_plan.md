# Migration to `docs/flutter_architecture_pattern.md` — implementation plan

Target: 100% of the rulebook. Applicable rules become guarded; genuinely N/A items
(network images, API pagination, Android bundles, `compute`) stay N/A with the
authority that excuses them (`PROJECT.md`: no network, Windows-only, local notes).

## Wave 1 — tree + imports + guard paths (mechanical, no logic changes)
- Moves per the table below (`git mv`). File contents unchanged except import
  paths, plus the three extractions noted.
- `main.dart`: import `ShellMissingApp` from core, delete private class.
- Extractions: `SelectionRepository` → notes/data/selection_repository.dart;
  `WidgetStateRepository` → widget/data/widget_state_repository.dart;
  `EmptyState`/`UndoToastBody(public)` → core/widgets/empty_state + undo_toast;
  `ShellMissingApp(public)` → core/widgets/shell_missing.
- `providers.dart` split (no logic change): shell+launch → core/platform;
  appPaths → core/utils; isWidgetSurface+brightness → core/theme;
  repo providers → `<feature>/presentation/providers/*_providers.dart`.
- Import rewrite via explicit old→new mapping script, then `flutter analyze`.
- Guards: new paths in `guards.dart` + all guard tests; cap stays 200 + every-line
  counting until Wave 2 (decision table keeps §2 declined).
- `AGENTS.md` §3 diagram/paths only. Verify: analyze + full `flutter test`.

## Wave 2 — providers + Riverpod (§5/§6, cap 300 code-only)
- Code-only counter replaces every-line counting; cap 200→300; `_decidedSections`
  row for §2-providers flipped.
- Split `notes_controller.dart` (~427 code-only): list/selection/search/mutations
  vs corrupt-file recovery (as `provider_pattern.md` §3.6 planned).
- `Note` immutable (`copyWith`); domain repository interfaces in each
  `domain/`; providers depend on them.
- `ref.select` for single fields; narrow `Consumer`s (screen shells become
  `Stateless`); `ref.listen` audit; `autoDispose`/`keepAlive` justifications;
  `.family` for by-id lookups; derived providers (`displayNotes`, `selectedNote`,
  `focusedNote`, counts, storage dir); `watch` (not `read`) inside providers.
- Fix `provider_pattern.md` §2 projection claim; update §3/§6/§7/§8 + `AGENTS.md`
  §0.8/§0.11/§4.7. Verify: analyze + test.

## Wave 3 — widgets (§3, caps 350/500 code-only)
- One public widget per file in its own folder; 23 private widgets → public
  (State stays paired in-file); 23 `_buildX` helpers → widget classes.
- Splits: settings_dialog (~775), markdown_text (~760), widget_surface (~558),
  editor_view (~416), note_editor_pane (~419). Flip decision rows.
- Update `provider_pattern.md` §5, `widget_pattern.md`, `AGENTS.md` §0.8/§4.
  Verify: analyze + test.

## Wave 4 — comments, lints, checks, docs (§2/§9/§10/§7 leftovers)
- Trim every comment to 2–3 lines (summarise, displace rationale to pattern docs).
- `analysis_options.yaml`: add §9 lints; `tool/check_architecture.ps1` with the §9
  one-liners (pwsh equivalents); wire into CI if present.
- Perf leftovers: `RepaintBoundary` around painter; markdown preview out of
  `build()` via derived provider; record N/A (itemExtent non-uniform lists,
  images, pagination, compute, deferred, Impeller) with authority.
- `AGENTS.md` §0/§3/§6, `PROJECT.md` only if a product statement conflicts
  (none expected: no network added, isolates + runner unchanged),
  `CHANGELOG.md` bullets (≤3 lines). Final verify: analyze + test + §9 script.

## Path mapping (old → new)
- `lib/main.dart` → `lib/main.dart`
- `src/core/app_paths.dart` → `lib/core/utils/app_paths.dart`
- `src/core/atomic_json_file.dart` → `lib/core/utils/atomic_json_file.dart`
- `src/platform/shell_channel.dart` → `lib/core/platform/shell_channel.dart`
- `src/ui/theme.dart` → `lib/core/theme/theme.dart`
- `src/ui/palette.dart` → `lib/core/theme/palette.dart`
- `src/ui/theme_scope.dart` → `lib/core/theme/theme_scope.dart`
- `src/ui/common/completion_toggle.dart` → `lib/core/widgets/completion_toggle/completion_toggle.dart`
- `src/ui/common/markdown_text.dart` → `lib/core/widgets/markdown_text/markdown_text.dart`
- `src/ui/common/widgets.dart` → `lib/core/widgets/empty_state/empty_state.dart` + `lib/core/widgets/undo_toast/undo_toast.dart`
- `src/data/note.dart` → `lib/features/notes/domain/note.dart`
- `src/data/notes_repository.dart` → `lib/features/notes/data/notes_repository.dart` (+ `selection_repository.dart`)
- `src/data/settings.dart` → `lib/features/settings/domain/settings.dart`
- `src/data/hotkey_binding.dart` → `lib/features/settings/domain/hotkey_binding.dart`
- `src/data/settings_repository.dart` → `lib/features/settings/data/settings_repository.dart` (minus `WidgetStateRepository`)
- `src/data/storage_location.dart` → `lib/features/settings/data/storage_location.dart`
- `src/data/storage_transfer.dart` → `lib/features/settings/data/storage_transfer.dart`
- `src/state/notes_controller.dart` → `lib/features/notes/presentation/providers/notes_controller.dart`
- `src/state/widget_controller.dart` → `lib/features/widget/presentation/providers/widget_controller.dart`
- `src/state/settings_controller.dart` → `lib/features/settings/presentation/providers/settings_controller.dart`
- `src/state/providers.dart` → split into core + `features/*/presentation/providers/`
- `src/ui/editor/editor_app.dart` → `lib/features/notes/presentation/screens/editor_app/editor_app.dart`
- `src/ui/editor/editor_view.dart` → `lib/features/notes/presentation/screens/editor_screen/editor_screen.dart`
- `src/ui/editor/note_list_pane.dart` → `lib/features/notes/presentation/widgets/note_list_pane/note_list_pane.dart`
- `src/ui/editor/note_editor_pane.dart` → `lib/features/notes/presentation/widgets/note_editor_pane/note_editor_pane.dart`
- `src/ui/widget/widget_app.dart` → `lib/features/widget/presentation/screens/widget_app/widget_app.dart`
- `src/ui/widget/widget_surface.dart` → `lib/features/widget/presentation/screens/widget_surface/widget_surface.dart`
- `src/ui/widget/widget_note_card.dart` → `lib/features/widget/presentation/widgets/widget_note_card/widget_note_card.dart`
- `src/ui/settings/settings_dialog.dart` → `lib/features/settings/presentation/screens/settings_dialog/settings_dialog.dart`
- New: `lib/features/widget/data/widget_state_repository.dart`
- New (Wave 2): `lib/features/*/domain/*_repository.dart` interfaces
