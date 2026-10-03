import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/hotkey_binding.dart';
import '../../data/settings.dart';
import '../../platform/shell_channel.dart';
import '../../state/settings_controller.dart';

/// Settings, in five flat groups with no nesting.
///
/// Appearance, Widget, Startup, Hotkey and Storage. Each is a `Card` rather than
/// an `ExpansionTile`, because a setting hidden behind a click is a setting
/// nobody changes.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.controller,
    required this.shell,
    required this.defaultDataDirectory,
  });

  final SettingsController controller;
  final ShellChannel shell;
  final String defaultDataDirectory;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final settings = widget.controller.settings;
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
                      _AppearanceGroup(
                        settings: settings,
                        controller: widget.controller,
                        acrylicSupported: widget.controller.acrylicSupported,
                      ),
                      const SizedBox(height: 20),
                      _WidgetGroup(
                        settings: settings,
                        controller: widget.controller,
                      ),
                      const SizedBox(height: 20),
                      _StartupGroup(
                        settings: settings,
                        controller: widget.controller,
                      ),
                      const SizedBox(height: 20),
                      _HotkeyGroup(
                        settings: settings,
                        controller: widget.controller,
                      ),
                      const SizedBox(height: 20),
                      _StorageGroup(
                        settings: settings,
                        controller: widget.controller,
                        shell: widget.shell,
                        defaultDirectory: widget.defaultDataDirectory,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

class _AppearanceGroup extends StatelessWidget {
  const _AppearanceGroup({
    required this.settings,
    required this.controller,
    required this.acrylicSupported,
  });

  final WinNotesSettings settings;
  final SettingsController controller;
  final bool acrylicSupported;

  @override
  Widget build(BuildContext context) {
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
                controller.update((s) => s.copyWith(themeMode: value.first)),
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
                    onChanged: (value) => controller.update(
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
                : (value) => controller.update(
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
class _WidgetGroup extends StatelessWidget {
  const _WidgetGroup({required this.settings, required this.controller});

  final WinNotesSettings settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return _Group(
      title: 'Widget',
      children: [
        _Row(
          label: 'Keep the widget above other windows',
          description: 'A note that cannot be seen is not a note.',
          trailing: Switch(
            value: settings.alwaysOnTop,
            onChanged: (value) =>
                controller.update((s) => s.copyWith(alwaysOnTop: value)),
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
            onChanged: (value) => controller.update(
              (s) => s.copyWith(widgetPositionLocked: value),
            ),
          ),
        ),
      ],
    );
  }
}

class _StartupGroup extends StatelessWidget {
  const _StartupGroup({required this.settings, required this.controller});

  final WinNotesSettings settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return _Group(
      title: 'Startup',
      children: [
        _Row(
          label: 'Bring the widget back after every restart',
          description: 'One entry under your own account, so no administrator '
              'rights are needed and it shows up in Task Manager.',
          trailing: Switch(
            value: settings.autoStart,
            onChanged: controller.setAutoStart,
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
              onChanged: (value) => controller.update(
                (s) => s.copyWith(autoStartDelayMs: value.round()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HotkeyGroup extends StatelessWidget {
  const _HotkeyGroup({required this.settings, required this.controller});

  final WinNotesSettings settings;
  final SettingsController controller;

  Future<void> _capture(BuildContext context) async {
    final binding = settings.editorHotkey;
    final captured = await showDialog<HotkeyBinding>(
      context: context,
      builder: (context) => _HotkeyCaptureDialog(initial: binding),
    );
    if (captured == null) return;
    await controller.update((s) => s.copyWith(editorHotkey: captured));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = controller.hotkeyProblem;

    return _Group(
      title: 'Hotkey',
      children: [
        _Row(
          label: 'Open the editor from anywhere',
          description: 'Works from any application, including full-screen ones.',
          onTap: () => _capture(context),
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
                onPressed: () => _capture(context),
                child: Text(settings.editorHotkey.display),
              ),
              const SizedBox(width: 6),
              if (settings.editorHotkey != HotkeyBinding.defaultBinding)
                IconButton(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  tooltip: 'Back to ${HotkeyBinding.defaultBinding.display}',
                  onPressed: () => controller.update(
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
            onChanged: (value) => controller.update(
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
  late HotkeyBinding _pending = widget.initial;

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
        final next = {..._pending.modifiers};
        if (next.contains(name)) {
          next.remove(name);
        } else {
          next.add(name);
        }
        setState(() => _pending = _pending.copyWith(modifiers: next.toList()));
        return KeyEventResult.handled;
      }

      final character = event.character;
      if (character != null && character.isNotEmpty) {
        setState(() => _pending = _pending.copyWith(key: character));
        return KeyEventResult.handled;
      }
      final named = _nameFor(key);
      if (named != null) {
        setState(() => _pending = _pending.copyWith(key: named));
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
    final registrable = _pending.isRegistrable;

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
                  _pending.display,
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
              ? () => Navigator.of(context).pop(_pending)
              : null,
          child: const Text('Use this'),
        ),
      ],
    );
  }
}

class _StorageGroup extends StatelessWidget {
  const _StorageGroup({
    required this.settings,
    required this.controller,
    required this.shell,
    required this.defaultDirectory,
  });

  final WinNotesSettings settings;
  final SettingsController controller;
  final ShellChannel shell;
  final String defaultDirectory;

  @override
  Widget build(BuildContext context) {
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
                onPressed: () => shell.revealPath(active),
              ),
              IconButton(
                icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                tooltip: 'Choose another folder',
                onPressed: () async {
                  final picked = await shell.pickFolder(start: active);
                  if (picked == null) return;
                  await controller.update(
                    (s) => s.copyWith(storageDirectory: picked),
                  );
                },
              ),
              if (isCustom)
                IconButton(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  tooltip: 'Back to the default folder',
                  onPressed: () => controller.update(
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