import 'package:flutter/foundation.dart';

/// A global hotkey as parts, not text: no escaping rules needed, and the only
/// behaviour-bearing settings part, split out with its own tests.
@immutable
class HotkeyBinding {
  const HotkeyBinding({
    required this.modifiers,
    required this.key,
    this.enabled = true,
  });

  /// Modifier names: 'ctrl', 'alt', 'shift', 'win'.
  final List<String> modifiers;

  /// A single character, or a named key such as 'F5', 'Space', 'Home'.
  final String key;
  final bool enabled;

  static const HotkeyBinding defaultBinding =
      HotkeyBinding(modifiers: <String>['ctrl', 'alt'], key: 'N');

  /// Whether this combination can actually be registered. Windows rejects a
  /// hotkey with no modifier, and one with only Win, which the shell keeps for
  /// Start and the window shortcuts.
  bool get isRegistrable {
    if (!enabled || key.isEmpty) return false;
    if (modifiers.isEmpty) return false;
    if (modifiers.length == 1 && modifiers.first == 'win') return false;
    return true;
  }

  /// Display form, ordered so the same combination always reads the same way
  /// regardless of the order the modifiers happen to be stored in.
  String get display {
    if (!enabled) return 'Off';
    if (key.isEmpty) return 'Not set';
    const Map<String, int> order = <String, int>{'ctrl': 0, 'alt': 1, 'shift': 2, 'win': 3};
    final List<String> sorted = modifiers.toList()
      ..sort((String a, String b) => (order[a] ?? 9).compareTo(order[b] ?? 9));
    final List<String> parts = <String>[
      for (final String m in sorted)
        switch (m) {
          'ctrl' => 'Ctrl',
          'alt' => 'Alt',
          'shift' => 'Shift',
          _ => 'Win',
        },
      _prettyKey(key),
    ];
    return parts.join('+');
  }

  static String _prettyKey(String raw) {
    if (raw.length == 1) return raw.toUpperCase();
    const Map<String, String> named = <String, String>{
      'Space': 'Space',
      'Enter': 'Enter',
      'Escape': 'Esc',
      'Tab': 'Tab',
      'Backspace': 'Backspace',
      'Delete': 'Del',
      'Insert': 'Ins',
      'Home': 'Home',
      'End': 'End',
      'PageUp': 'PgUp',
      'PageDown': 'PgDn',
      'Left': 'Left',
      'Right': 'Right',
      'Up': 'Up',
      'Down': 'Down',
    };
    return named[raw] ?? raw;
  }

  HotkeyBinding copyWith({
    List<String>? modifiers,
    String? key,
    bool? enabled,
  }) =>
      HotkeyBinding(
        modifiers: modifiers ?? this.modifiers,
        key: key ?? this.key,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'modifiers': modifiers,
        'key': key,
        'enabled': enabled,
      };

  static HotkeyBinding fromJson(
    Map<String, dynamic> json, {
    HotkeyBinding? fallback,
  }) {
    final HotkeyBinding base = fallback ?? defaultBinding;
    final mods = json['modifiers'];
    final key = json['key'];
    final HotkeyBinding parsed = HotkeyBinding(
      modifiers:
          mods is List ? mods.whereType<String>().toList() : base.modifiers,
      key: key is String && key.isNotEmpty ? key : base.key,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
    );
    // A stored combination Windows would reject is worse than the default,
    // which at least registers.
    return parsed.isRegistrable ? parsed : base;
  }

  /// Modifiers compare in stored order, not sorted order. Equality here drives
  /// "did this setting change?", and re-sorting would make a cosmetic reorder
  /// look like a real change and trigger a needless hotkey re-registration.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HotkeyBinding &&
          other.key == key &&
          other.enabled == enabled &&
          _sameModifiers(other.modifiers);

  @override
  int get hashCode => Object.hash(key, enabled, Object.hashAll(modifiers));

  bool _sameModifiers(List<String> other) {
    if (other.length != modifiers.length) return false;
    for (int i = 0; i < modifiers.length; i++) {
      if (other[i] != modifiers[i]) return false;
    }
    return true;
  }
}