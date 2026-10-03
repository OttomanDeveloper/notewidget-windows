import 'dart:async';

import 'package:flutter/services.dart';

/// One monitor, as the native runner sees it.
class MonitorInfo {
  const MonitorInfo({
    required this.id,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.scale,
  });

  final int id;
  final int left;
  final int top;
  final int width;
  final int height;
  final double scale;

  int get right => left + width;
  int get bottom => top + height;

  static MonitorInfo fromMap(Map<dynamic, dynamic> map) => MonitorInfo(
        id: (map['id'] as num).toInt(),
        left: (map['left'] as num).toInt(),
        top: (map['top'] as num).toInt(),
        width: (map['width'] as num).toInt(),
        height: (map['height'] as num).toInt(),
        scale: (map['scale'] as num).toDouble(),
      );
}

/// Rectangle in virtual-screen pixels.
class NativeBounds {
  const NativeBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;

  static NativeBounds fromMap(Map<dynamic, dynamic> map) => NativeBounds(
        left: (map['left'] as num).toInt(),
        top: (map['top'] as num).toInt(),
        width: (map['width'] as num).toInt(),
        height: (map['height'] as num).toInt(),
      );
}

/// Why a hotkey registration failed, in terms the Settings dialog can show.
enum HotkeyFailure {
  none,
  alreadyRegistered,
  invalid,
  failed;

  static HotkeyFailure fromName(String? name) => switch (name) {
        'ok' => HotkeyFailure.none,
        'alreadyRegistered' => HotkeyFailure.alreadyRegistered,
        'invalid' => HotkeyFailure.invalid,
        _ => HotkeyFailure.failed,
      };
}

class HotkeyRegistration {
  const HotkeyRegistration({required this.ok, required this.failure});
  final bool ok;
  final HotkeyFailure failure;
}

/// Everything the Dart side needs to know about how it was started.
class LaunchInfo {
  const LaunchInfo({
    required this.role,
    required this.launchMode,
    required this.isWidgetSurface,
    required this.dataDirectory,
    required this.executablePath,
    required this.isSystemDark,
    required this.animationsEnabled,
    required this.highContrast,
    required this.acrylicSupported,
    required this.buildNumber,
    required this.monitors,
    required this.autostartEnabled,
    required this.autostartCommand,
    required this.defaultWidgetBounds,
  });

  /// 'shell' for the widget surface, 'editor' for the editor surface.
  final String role;
  final String launchMode;
  final bool isWidgetSurface;
  final String dataDirectory;
  final String executablePath;
  final bool isSystemDark;

  /// False when Windows reports that animation is turned off, in which case
  /// nothing in the app slides or fades.
  final bool animationsEnabled;
  final bool highContrast;
  final bool acrylicSupported;
  final int buildNumber;
  final List<MonitorInfo> monitors;
  final bool autostartEnabled;
  final String autostartCommand;
  final NativeBounds defaultWidgetBounds;

  /// True when this launch came from the autostart entry, which is the only
  /// case the startup delay applies to.
  bool get isAutostartLaunch => launchMode == 'widget';
}

/// Typed wrapper over the runner's method channel.
///
/// Every call is defensive about the reply: the runner can be an older build
/// than the Dart code if someone half-updates, and a missing reply should
/// degrade to "no" rather than throwing through a widget build.
class ShellChannel {
  ShellChannel();

  /// Exposed so [ShellEvents] can install its handler on the same channel.
  static const MethodChannel methodChannel = MethodChannel('dev.winnotes/shell');

  /// Screen reader text for the app name, so the platform layer does not have
  /// to import the UI.
  static String appTitle = 'WinNotes';

  Future<LaunchInfo?> bootstrap() async {
    // Must be installed before any event can arrive, otherwise a hotkey press
    // during the first frame is dropped.
    ShellEvents.instance.install();
    try {
      final raw = await methodChannel.invokeMapMethod<String, dynamic>('bootstrap');
      if (raw == null) return null;
      return LaunchInfo(
        role: raw['role'] as String? ?? 'editor',
        launchMode: raw['launchMode'] as String? ?? 'normal',
        isWidgetSurface: raw['isWidgetSurface'] as bool? ?? false,
        dataDirectory: raw['dataDir'] as String? ?? '',
        executablePath: raw['exePath'] as String? ?? '',
        isSystemDark: raw['isSystemDark'] as bool? ?? false,
        animationsEnabled: raw['animationsEnabled'] as bool? ?? true,
        highContrast: raw['highContrast'] as bool? ?? false,
        acrylicSupported: raw['acrylicSupported'] as bool? ?? false,
        buildNumber: (raw['buildNumber'] as num?)?.toInt() ?? 0,
        monitors: (raw['monitors'] as List?)
                ?.whereType<Map>()
                .map(MonitorInfo.fromMap)
                .toList() ??
            const [],
        autostartEnabled: raw['autostartEnabled'] as bool? ?? false,
        autostartCommand: raw['autostartCommand'] as String? ?? '',
        defaultWidgetBounds: NativeBounds.fromMap(
          raw['defaultWidgetBounds'] as Map? ?? const {'left': 0, 'top': 0, 'width': 360, 'height': 420},
        ),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> showWindow(String role) => _fire('window.show', {'role': role});
  Future<void> hideWindow(String role) => _fire('window.hide', {'role': role});
  Future<void> focusWindow(String role) => _fire('window.focus', {'role': role});
  Future<void> setWindowTitle(String role, String title) =>
      _fire('window.setTitle', {'role': role, 'title': title});

  /// Pushes every widget appearance choice into the runner in one call, so the
  /// widget can never be half-configured mid-frame.
  Future<void> configureWidget({
    required bool alwaysOnTop,
    required int opacity,
    required bool acrylic,
    required bool rounded,
    required bool visible,

    /// Whether the widget refuses to be dragged. Sent on every configure rather
    /// than only when it changes, because this call is already the single place
    /// that decides how the widget looks and behaves.
    bool positionLocked = true,
  }) =>
      _fire('widget.configure', {
        'alwaysOnTop': alwaysOnTop,
        'opacity': opacity,
        'acrylic': acrylic,
        'rounded': rounded,
        'visible': visible,
        'positionLocked': positionLocked,
      });

  Future<void> setWidgetGeometry(NativeBounds bounds) => _fire('widget.setGeometry', {
        'left': bounds.left,
        'top': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      });

  Future<HotkeyRegistration> registerHotkey({
    required List<String> modifiers,
    required String key,
    required bool enabled,
  }) async {
    try {
      final raw = await methodChannel.invokeMapMethod<String, dynamic>('hotkey.register', {
        'modifiers': modifiers,
        'key': key,
        'enabled': enabled,
      });
      return HotkeyRegistration(
        ok: raw?['ok'] as bool? ?? false,
        failure: HotkeyFailure.fromName(raw?['reason'] as String?),
      );
    } on PlatformException {
      return const HotkeyRegistration(ok: false, failure: HotkeyFailure.failed);
    } on MissingPluginException {
      return const HotkeyRegistration(ok: false, failure: HotkeyFailure.failed);
    }
  }

  Future<bool> queryAutoStart() async {
    try {
      final raw = await methodChannel.invokeMapMethod<String, dynamic>('autostart.query');
      return raw?['enabled'] as bool? ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> setAutoStart(bool enabled) async {
    try {
      final raw = await methodChannel.invokeMapMethod<String, dynamic>('autostart.set', {
        'enabled': enabled,
      });
      return raw?['ok'] as bool? ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> showNotice(String title, String body) =>
      _fire('tray.notice', {'title': title, 'body': body});

  Future<void> showEditor() => _fire('shell.showEditor');
  Future<void> showWidget() => _fire('shell.showWidget');
  Future<void> openSettings() => _fire('shell.openSettings');
  Future<void> quit() => _fire('app.quit');

  Future<bool> confirmQuit() async {
    try {
      return await methodChannel.invokeMethod<bool>('dialog.confirmQuit') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openPath(String path) => _fire('path.open', {'path': path});
  Future<void> revealPath(String path) => _fire('path.reveal', {'path': path});

  Future<String?> pickFolder({String? start}) async {
    try {
      return await methodChannel.invokeMethod<String>('path.pickFolder', {'start': start ?? ''});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<String?> pickFile({String? start, String filter = 'WinNotes backups|*.txt|All files|*.*'}) async {
    try {
      return await methodChannel.invokeMethod<String>('path.pickFile', {'start': start ?? '', 'filter': filter});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<String?> saveFile({
    String? start,
    required String suggestedName,
    String filter = 'Text files|*.txt|All files|*.*',
  }) async {
    try {
      return await methodChannel.invokeMethod<String>('path.saveFile', {
        'start': start ?? '',
        'suggestedName': suggestedName,
        'filter': filter,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _fire(String method, [Map<String, dynamic>? args]) async {
    try {
      await methodChannel.invokeMethod<void>(method, args);
    } on PlatformException {
      // Window and tray calls are conveniences; failing one must never take a
      // surface down with it.
    } on MissingPluginException {
      // Running under `flutter test`, where there is no runner at all.
    }
  }

  /// Events pushed from the runner to this surface.
  Stream<ShellEvent> get events => ShellEvents.instance.stream;
}

/// Typed view over the runner's event stream.
///
/// The runner pushes these with `InvokeMethod` on the same channel the Dart
/// side calls out on, so they arrive through [setMethodCallHandler] rather than
/// an EventChannel. Using an EventChannel here would silently receive nothing.
class ShellEvents {
  ShellEvents._();

  static final ShellEvents instance = ShellEvents._();

  final StreamController<ShellEvent> _controller =
      StreamController<ShellEvent>.broadcast();

  Stream<ShellEvent> get stream => _controller.stream;

  bool _installed = false;

  void install() {
    if (_installed) return;
    _installed = true;
    ShellChannel.methodChannel.setMethodCallHandler((call) async {
      final event = ShellEvent.fromMethod(call.method, call.arguments);
      if (_controller.isClosed) return null;
      _controller.add(event);
      return null;
    });
  }

  void dispose() {
    _controller.close();
  }
}

/// An event the runner sent up to Dart.
class ShellEvent {
  const ShellEvent._(this.method, this.arguments);

  final String method;
  final Object? arguments;

  /// Distinguishes the events the UI reacts to, so listeners can pattern-match
  /// instead of comparing strings at every call site.
  ShellEventKind get kind => switch (method) {
        'event.hotkey' => ShellEventKind.hotkey,
        'event.openSettings' => ShellEventKind.openSettings,
        'event.visibility' => ShellEventKind.visibility,
        'event.geometry' => ShellEventKind.geometry,
        _ => ShellEventKind.unknown,
      };

  static ShellEvent fromMethod(String method, Object? arguments) =>
      ShellEvent._(method, arguments);
}

enum ShellEventKind { hotkey, openSettings, visibility, geometry, unknown }

/// Convenience accessors over [ShellEvent] arguments.
extension ShellEventData on ShellEvent {
  bool get isVisible => arguments is Map
      ? (arguments as Map)['visible'] as bool? ?? true
      : true;

  NativeBounds? get bounds {
    final args = arguments;
    if (args is! Map) return null;
    return NativeBounds.fromMap(args);
  }
}