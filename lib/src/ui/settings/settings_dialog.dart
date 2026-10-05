import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../data/hotkey_binding.dart';
import '../../data/settings_repository.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../palette.dart';
import '../theme.dart';

/// Settings, in five flat groups with no nesting.
///
/// Appearance, Widget, Startup, Hotkey and Storage. Each is a `Card` rather than
/// an `ExpansionTile`, because a setting hidden behind a click is a setting
/// nobody changes.
class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({
    super.key,
    required this.defaultDataDirectory,
  });

  /// The runner channel, and the default folder.
  ///
  /// Both are allowed to cross as parameters because neither is *state*: they do
  /// not change, so nothing here rebuilds when they do. What would not be allowed
  /// is the settings controller the old version took - that is state, and it is now
  /// read with `ref.watch` in each group. `AGENTS.md` section 0.8.
  final String defaultDataDirectory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The dialog itself does not read the settings; each group watches what it
    // draws, so toggling the theme repaints the appearance group and not the
    // storage group's folder path.
    final theme = Theme.of(context);

    return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(context, theme),
                Divider(height: 1, color: theme.dividerColor),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      const _AppearanceGroup(),
                      const SizedBox(height: 20),
                      const _WidgetGroup(),
                      const SizedBox(height: 20),
                      const _StartupGroup(),
                      const SizedBox(height: 20),
                      const _HotkeyGroup(),
                      const SizedBox(height: 20),
                      _StorageGroup(defaultDirectory: defaultDataDirectory),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
  }

  Widget _header(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Text(
            'Settings',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close settings',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.trailing,
    this.description,
    this.onTap,
  });

  final String label;
  final Widget trailing;
  final String? description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label, style: theme.textTheme.bodyLarge),
                    if (description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Theme.of(context).dividerColor);
}

/// The colour swatches.
///
/// Nine circles and the name of the one you picked, rather than a dropdown:
/// the whole point of a colour list is that you can recognise the colour you
/// want without reading its name, and a dropdown throws that away.
///
/// Each swatch shows the palette's **light-mode** accent, because that is the
/// one with to stay legible against a pale dialog — the dark-mode variant is a
/// lighter shade of the same hue, so the swatch reads as the family rather than
/// as a colour you will not actually get.
class _PalettePicker extends StatelessWidget {
  const _PalettePicker({required this.selected, required this.onSelected});

  final WinNotesPalette selected;
  final ValueChanged<WinNotesPalette> onSelected;

  /// Exposed so widget tests aim at a swatch without reverse-engineering the
  /// wrap order — the same reason the composer's controls are keyed.
  static Key keyFor(String paletteId) => ValueKey('settings.palette.$paletteId');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 196,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              for (final palette in winNotesPalettes)
                _Swatch(
                  palette: palette,
                  isSelected: palette.id == selected.id,
                  onTap: () => onSelected(palette),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            selected.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.palette,
    required this.isSelected,
    required this.onTap,
  });

  final WinNotesPalette palette;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A tick rather than a ring: a ring in the same colour as the swatch reads
    // as a slightly bigger swatch, which is not obviously "this one".
    final onAccent = readableOn(palette.accent);

    return Semantics(
      button: true,
      selected: isSelected,
      label: palette.label,
      // On the Semantics rather than the InkWell nested inside it, so a test can
      // ask "which swatch claims to be selected" by key. A key on the innermost
      // widget would make the selected state unobservable, because the
      // Semantics that carries it sits above.
      key: _PalettePicker.keyFor(palette.id),
      child: Tooltip(
        message: palette.label,
        child: SizedBox(
          // Outside the Material, deliberately: a Material with a clip shape
          // expands to fill its constraints, which would make every swatch the
          // width of the picker and swallow taps meant for its neighbours.
          width: 30,
          height: 30,
          child: Material(
            color: Colors.transparent,
            shape: CircleBorder(
              side: BorderSide(
                color: isSelected ? palette.accent : scheme.outlineVariant,
                width: isSelected ? 2.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Center(
                child: AnimatedContainer(
                  // A plain duration rather than WinNotesMotion: that class is
                  // fed by the launch's animation flag, which this dialog is not
                  // plumbed to, and plumbing it for a 14px circle is not worth
                  // the seam.
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  width: isSelected ? 16 : 14,
                  height: isSelected ? 16 : 14,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    shape: BoxShape.circle,
                  ),
                  child: isSelected
                      ? Icon(Icons.check, size: 11, color: onAccent)
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppearanceGroup extends ConsumerWidget {
  const _AppearanceGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).value?.settings ?? SettingsRepository.defaults;
    final controller = ref.read(settingsProvider.notifier);
    final acrylicSupported =
        ref.watch(settingsProvider).value?.acrylicSupported ?? false;
    return _Group(
      title: 'Appearance',
      children: [
        _Row(
          label: 'Theme',
          description: 'Follows Windows unless you say otherwise.',
          trailing: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (value) =>
                controller.apply((s) => s.copyWith(themeMode: value.first)),
          ),
        ),
        const _Separator(),
        _Row(
          label: 'Colour',
          description: 'The accent, and the surfaces built around it.',
          trailing: _PalettePicker(
            selected: paletteById(settings.accentPalette),
            onSelected: (palette) => controller.apply(
              (s) => s.copyWith(accentPalette: palette.id),
            ),
          ),
        ),
        const _Separator(),
        _Row(
          label: 'Widget opacity',
          description: '${settings.widgetOpacity}%'
              '${settings.widgetOpacity < 100 ? '  Lower values let the desktop show through.' : ''}',
          trailing: SizedBox(
            width: 190,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: settings.widgetOpacity.toDouble(),
                    min: 30,
                    max: 100,
                    divisions: 14,
                    label: '${settings.widgetOpacity}%',
                    onChanged: (value) => controller.apply(
                      (s) => s.copyWith(widgetOpacity: value.round()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const _Separator(),
        _Row(
          label: 'Acrylic backdrop',
          description: acrylicSupported
              ? 'The widget picks up the wallpaper the way Windows surfaces do.'
              : 'This build of Windows cannot provide it, so the widget uses a '
                  'plain translucent surface instead.',
          trailing: Switch(
            value: settings.acrylicEnabled && acrylicSupported,
            onChanged: !acrylicSupported
                ? null
                : (value) => controller.apply(
                      (s) => s.copyWith(acrylicEnabled: value),
                    ),
          ),
        ),
      ],
    );
  }
}

/// Everything about how the widget sits on the desktop.
///
/// Grouped separately from Appearance because these are the three decisions
/// about where it goes and whether it gets in the way, rather than how it
/// looks. A lock and an always-on-top switch sitting together also make the
/// trade-off obvious: a widget you cannot move is worth more if it is also not
/// covering your work.
class _WidgetGroup extends ConsumerWidget {
  const _WidgetGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).value?.settings ?? SettingsRepository.defaults;
    final controller = ref.read(settingsProvider.notifier);
    return _Group(
      title: 'Widget',
      children: [
        _Row(
          label: 'Keep the widget above other windows',
          description: 'A note that cannot be seen is not a note.',
          trailing: Switch(
            value: settings.alwaysOnTop,
            onChanged: (value) =>
                controller.apply((s) => s.copyWith(alwaysOnTop: value)),
          ),
        ),
        const _Separator(),
        _Row(
          label: 'Lock the widget in place',
          description: settings.widgetPositionLocked
              ? 'Dragging the widget does nothing, so it cannot be knocked out '
                  'of position by accident. Turn this off to move it, then '
                  'lock it again once it is where you want it. Resizing from a '
                  'corner still works either way.'
              : 'The widget can be dragged anywhere, and stays where you drop '
                  'it. Turn this on to stop an accidental drag moving it.',
          trailing: Switch(
            value: settings.widgetPositionLocked,
            onChanged: (value) => controller.apply(
              (s) => s.copyWith(widgetPositionLocked: value),
            ),
          ),
        ),
      ],
    );
  }
}

class _StartupGroup extends ConsumerWidget {
  const _StartupGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).value?.settings ?? SettingsRepository.defaults;
    final controller = ref.read(settingsProvider.notifier);
    return _Group(
      title: 'Startup',
      children: [
        _Row(
          label: 'Bring the widget back after every restart',
          description: 'One entry under your own account, so no administrator '
              'rights are needed and it shows up in Task Manager.',
          trailing: Switch(
            value: settings.autoStart,
            onChanged: (enabled) => controller.setAutoStart(enabled: enabled),
          ),
        ),
        const _Separator(),
        _Row(
          label: 'Startup delay',
          description: settings.autoStartDelayMs == 0
              ? 'Show the widget the moment Windows gets there.'
              : 'Wait ${(settings.autoStartDelayMs / 1000).toStringAsFixed(1)} '
                  'seconds so the widget does not race the login animation. '
                  'Applies to startup only, never to a launch by hand.',
          trailing: SizedBox(
            width: 190,
            child: Slider(
              value: settings.autoStartDelayMs.toDouble(),
              min: 0,
              max: 15000,
              divisions: 30,
              label: '${(settings.autoStartDelayMs / 1000).toStringAsFixed(1)}s',
              onChanged: (value) => controller.apply(
                (s) => s.copyWith(autoStartDelayMs: value.round()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HotkeyGroup extends ConsumerWidget {
  const _HotkeyGroup();

  /// Opens the capture dialog and stores whatever combination was pressed.
  ///
  /// Reads through `ref` rather than taking the settings as a field, because the
  /// old version of this class held them and this method is the one thing in the
  /// dialog that runs outside `build`.
  Future<void> _capture(BuildContext context, WidgetRef ref) async {
    final settings =
        ref.read(settingsProvider).value?.settings ?? SettingsRepository.defaults;
    final binding = settings.editorHotkey;
    final captured = await showDialog<HotkeyBinding>(
      context: context,
      builder: (context) => _HotkeyCaptureDialog(initial: binding),
    );
    if (captured == null) return;
    await ref
        .read(settingsProvider.notifier)
        .apply((s) => s.copyWith(editorHotkey: captured));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).value?.settings ?? SettingsRepository.defaults;
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final problem = ref.watch(settingsProvider).value?.hotkeyProblem;

    return _Group(
      title: 'Hotkey',
      children: [
        _Row(
          label: 'Open the editor from anywhere',
          description: 'Works from any application, including full-screen ones.',
          onTap: () => _capture(context, ref),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!settings.editorHotkey.enabled)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Off',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: () => _capture(context, ref),
                child: Text(settings.editorHotkey.display),
              ),
              const SizedBox(width: 6),
              if (settings.editorHotkey != HotkeyBinding.defaultBinding)
                IconButton(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  tooltip: 'Back to ${HotkeyBinding.defaultBinding.display}',
                  onPressed: () => controller.apply(
                    (s) => s.copyWith(editorHotkey: HotkeyBinding.defaultBinding),
                  ),
                ),
            ],
          ),
        ),
        // A collision has to be visible. The spec is explicit that the app
        // notices rather than silently doing nothing.
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    problem,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const _Separator(),
        _Row(
          label: 'Turn the hotkey off',
          description: 'The tray menu still opens the editor.',
          trailing: Switch(
            value: settings.editorHotkey.enabled,
            onChanged: (value) => controller.apply(
              (s) => s.copyWith(
                editorHotkey: s.editorHotkey.copyWith(enabled: value),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Captures a key combination by waiting for the next keystroke.
///
/// Deliberately not a TextField: typing "ctrl+alt+n" into a field is ambiguous
/// about every character that is also a modifier.
class _HotkeyCaptureDialog extends StatefulWidget {
  const _HotkeyCaptureDialog({required this.initial});
  final HotkeyBinding initial;

  @override
  State<_HotkeyCaptureDialog> createState() => _HotkeyCaptureDialogState();
}

class _HotkeyCaptureDialogState extends State<_HotkeyCaptureDialog> {
  /// The combination captured so far, held while this dialog is open.
  ///
  /// A `ValueNotifier` and not a provider, and not a `setState`. The dividing line
  /// is lifetime: this exists for as long as the capture dialog does, is read by
  /// nothing outside it, and is thrown away when it closes. That is the
  /// `ValueNotifier` half of `AGENTS.md` §0.7 - the same rule that made
  /// `_CorruptNotesScreenState` use one for its busy flag.
  late final ValueNotifier<HotkeyBinding> _pending;

  @override
  void initState() {
    super.initState();
    _pending = ValueNotifier<HotkeyBinding>(widget.initial);
  }

  // Modifier keys, as a plain final Set rather than a const one:
  // LogicalKeyboardKey overrides == and hashCode, which Dart forbids in a
  // constant set.
  final Set<LogicalKeyboardKey> _allowed = {
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  KeyEventResult _handle(KeyEvent event) {
    final key = event.logicalKey;

    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      if (_allowed.contains(key)) {
        final name = switch (key) {
          LogicalKeyboardKey.control ||
          LogicalKeyboardKey.controlLeft ||
          LogicalKeyboardKey.controlRight =>
            'ctrl',
          LogicalKeyboardKey.alt ||
          LogicalKeyboardKey.altLeft ||
          LogicalKeyboardKey.altRight =>
            'alt',
          LogicalKeyboardKey.shift ||
          LogicalKeyboardKey.shiftLeft ||
          LogicalKeyboardKey.shiftRight =>
            'shift',
          _ => 'win',
        };
        // Which physical modifier is held does not matter; only which ones.
        final next = {..._pending.value.modifiers};
        if (next.contains(name)) {
          next.remove(name);
        } else {
          next.add(name);
        }
        _pending.value = _pending.value.copyWith(modifiers: next.toList());
        return KeyEventResult.handled;
      }

      final character = event.character;
      if (character != null && character.isNotEmpty) {
        _pending.value = _pending.value.copyWith(key: character);
        return KeyEventResult.handled;
      }
      final named = _nameFor(key);
      if (named != null) {
        _pending.value = _pending.value.copyWith(key: named);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.handled;
  }

  static String? _nameFor(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    if (label.isEmpty) return null;
    // Single printable characters arrive with no character but do have a label.
    if (label.length == 1) return label;
    if (key.keyId >= LogicalKeyboardKey.f1.keyId &&
        key.keyId <= LogicalKeyboardKey.f12.keyId) {
      return label.toUpperCase();
    }
    return switch (key) {
      LogicalKeyboardKey.space => 'Space',
      LogicalKeyboardKey.enter => 'Enter',
      LogicalKeyboardKey.escape => 'Escape',
      LogicalKeyboardKey.tab => 'Tab',
      LogicalKeyboardKey.backspace => 'Backspace',
      LogicalKeyboardKey.delete => 'Delete',
      LogicalKeyboardKey.insert => 'Insert',
      LogicalKeyboardKey.home => 'Home',
      LogicalKeyboardKey.end => 'End',
      LogicalKeyboardKey.pageUp => 'PageUp',
      LogicalKeyboardKey.pageDown => 'PageDown',
      LogicalKeyboardKey.arrowLeft => 'Left',
      LogicalKeyboardKey.arrowRight => 'Right',
      LogicalKeyboardKey.arrowUp => 'Up',
      LogicalKeyboardKey.arrowDown => 'Down',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The draft this dialog shows, read through a listener.
    //
    // `_pending` replaced a `setState` field, and the first version of this build
    // read it with nothing listening - so pressing a combination updated the field
    // and the dialog carried on showing the one it opened with, with "Use this" still
    // disabled. `no_set_state_test`'s "every ValueNotifier is listened to" check found
    // it, and nothing else would have: this dialog is driven by key events rather than
    // by a control a test can find and tap.
    return ListenableBuilder(
      listenable: _pending,
      builder: (context, _) {
        final registrable = _pending.value.isRegistrable;

        return AlertDialog(

      title: const Text('Set the shortcut'),
      content: Focus(
        autofocus: true,
        onKeyEvent: (node, event) => _handle(event),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Center(
                child: Text(
                  _pending.value.display,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: registrable
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              registrable
                  ? 'Press the combination you want. Modifiers toggle as you '
                      'press them.'
                  : 'Add at least one modifier other than the Windows key.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: registrable
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: registrable
              ? () => Navigator.of(context).pop(_pending.value)
              : null,
          child: const Text('Use this'),
        ),
      ],
        );
      },
    );
  }
}

class _StorageGroup extends ConsumerWidget {
  const _StorageGroup({required this.defaultDirectory});

  final String defaultDirectory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).value?.settings ?? SettingsRepository.defaults;
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final active = controller.resolveStorageDirectory(defaultDirectory);
    final isCustom = settings.storageDirectory.trim().isNotEmpty;

    return _Group(
      title: 'Storage',
      children: [
        _Row(
          label: 'Notes file',
          description: active,
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                icon: const Icon(Icons.folder_open, size: 18),
                tooltip: 'Show the folder',
                onPressed: () => ref.read(shellProvider).revealPath(active),
              ),
              IconButton(
                icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                tooltip: 'Choose another folder',
                onPressed: () async {
                  final picked = await ref.read(shellProvider).pickFolder(start: active);
                  if (picked == null) return;
                  await controller.apply(
                    (s) => s.copyWith(storageDirectory: picked),
                  );
                },
              ),
              if (isCustom)
                IconButton(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  tooltip: 'Back to the default folder',
                  onPressed: () => controller.apply(
                    (s) => s.copyWith(storageDirectory: ''),
                  ),
                ),
            ],
          ),
        ),
        const _Separator(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'One plain JSON file, written as a whole so a half-finished write '
            'cannot break it, and readable without this app. Back it up whenever '
            'you like; there is no account and nothing to sync.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
