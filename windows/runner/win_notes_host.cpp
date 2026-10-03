#include "win_notes_host.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <map>

#include "win_notes_platform.h"

namespace winnotes {

namespace {

constexpr char kChannelName[] = "dev.winnotes/shell";
constexpr wchar_t kSingleInstanceMutex[] = L"Local\\WinNotesSingleInstance";
constexpr wchar_t kRoleProperty[] = L"WinNotesRole";

// A second launch must raise the existing instance rather than stacking a
// second copy of the widget on top of the first. The hidden widget window
// carries this property so the search finds the shell specifically instead of
// whichever surface happens to exist.
UINT gActivateInstanceMessage = WM_APP + 40;

struct FindShellContext {
  const wchar_t* class_name;
  HWND found;
};

BOOL CALLBACK FindShellWindow(HWND window, LPARAM param) {
  auto* ctx = reinterpret_cast<FindShellContext*>(param);
  wchar_t class_name[256]{};
  if (!GetClassNameW(window, class_name, 256)) return TRUE;
  if (wcscmp(class_name, ctx->class_name) != 0) return TRUE;
  wchar_t* role = reinterpret_cast<wchar_t*>(GetPropW(window, kRoleProperty));
  if (role == nullptr || wcscmp(role, L"shell") != 0) return TRUE;
  ctx->found = window;
  return FALSE;
}

// --- Method argument helpers -------------------------------------------------
//
// Everything crossing the channel is read through these. A channel method that
// indexes a map without checking first is how a settings toggle ends up
// crashing the widget instead of doing nothing.

const flutter::EncodableValue* Find(const flutter::EncodableMap* map,
                                    const char* key) {
  if (map == nullptr) return nullptr;
  auto it = map->find(flutter::EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

bool GetBool(const flutter::EncodableMap* map, const char* key, bool fallback) {
  const auto* value = Find(map, key);
  if (value == nullptr || !std::holds_alternative<bool>(*value)) return fallback;
  return std::get<bool>(*value);
}

int64_t GetInt(const flutter::EncodableMap* map, const char* key, int64_t fallback) {
  const auto* value = Find(map, key);
  if (value == nullptr) return fallback;
  std::optional<int64_t> parsed = value->TryGetLongValue();
  return parsed.has_value() ? *parsed : fallback;
}

double GetDouble(const flutter::EncodableMap* map, const char* key, double fallback) {
  const auto* value = Find(map, key);
  if (value == nullptr) return fallback;
  if (std::holds_alternative<double>(*value)) return std::get<double>(*value);
  if (std::optional<int64_t> parsed = value->TryGetLongValue()) {
    return static_cast<double>(*parsed);
  }
  return fallback;
}

std::string GetString(const flutter::EncodableMap* map, const char* key,
                      const std::string& fallback = "") {
  const auto* value = Find(map, key);
  if (value == nullptr || !std::holds_alternative<std::string>(*value)) {
    return fallback;
  }
  return std::get<std::string>(*value);
}

SurfaceRole RoleFrom(const flutter::EncodableMap* map) {
  const std::string role = GetString(map, "role", "shell");
  return role == "editor" ? SurfaceRole::kEditor : SurfaceRole::kShell;
}

// Encodes a window rectangle for Dart.
flutter::EncodableValue EncodeRect(const RECT& r) {
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("left"), flutter::EncodableValue(static_cast<int64_t>(r.left))},
      {flutter::EncodableValue("top"), flutter::EncodableValue(static_cast<int64_t>(r.top))},
      {flutter::EncodableValue("width"), flutter::EncodableValue(static_cast<int64_t>(r.right - r.left))},
      {flutter::EncodableValue("height"), flutter::EncodableValue(static_cast<int64_t>(r.bottom - r.top))},
  });
}

RECT RectFrom(const flutter::EncodableMap* map) {
  RECT r{};
  r.left = static_cast<LONG>(GetInt(map, "left", 0));
  r.top = static_cast<LONG>(GetInt(map, "top", 0));
  r.right = r.left + static_cast<LONG>(GetInt(map, "width", 320));
  r.bottom = r.top + static_cast<LONG>(GetInt(map, "height", 320));
  return r;
}

// Maps a Dart modifier name onto a Win32 modifier bit.
UINT ModifierFromString(const std::string& name) {
  if (name == "ctrl" || name == "control") return MOD_CONTROL;
  if (name == "alt") return MOD_ALT;
  if (name == "shift") return MOD_SHIFT;
  if (name == "win" || name == "super" || name == "meta") return MOD_WIN;
  return 0;
}

UINT VirtualKeyFromString(const std::string& key) {
  if (key.empty()) return 0;

  // A single printable character maps by its upper-case code point, which is
  // how RegisterHotKey expects letters to be given.
  if (key.size() == 1) {
    const char c = key[0];
    if (c >= 'a' && c <= 'z') return static_cast<UINT>(c - 'a' + 'A');
    if (c >= 'A' && c <= 'Z') return static_cast<UINT>(c);
    if (c >= '0' && c <= '9') return static_cast<UINT>(c);
    if (c == '+') return VK_OEM_PLUS;
    if (c == '-') return VK_OEM_MINUS;
    if (c == '[') return VK_OEM_4;
    if (c == ']') return VK_OEM_6;
    if (c == ';') return VK_OEM_1;
    if (c == '\'') return VK_OEM_7;
    if (c == ',') return VK_OEM_COMMA;
    if (c == '.') return VK_OEM_PERIOD;
    if (c == '/') return VK_OEM_2;
    if (c == '\\') return VK_OEM_5;
    if (c == '`') return VK_OEM_3;
    return 0;
  }

  if (key.size() >= 2 && key[0] == 'F') {
    const int n = std::atoi(key.c_str() + 1);
    if (n >= 1 && n <= 24) return VK_F1 + (n - 1);
    return 0;
  }
  if (key == "Space") return VK_SPACE;
  if (key == "Enter" || key == "Return") return VK_RETURN;
  if (key == "Escape" || key == "Esc") return VK_ESCAPE;
  if (key == "Tab") return VK_TAB;
  if (key == "Backspace") return VK_BACK;
  if (key == "Delete" || key == "Del") return VK_DELETE;
  if (key == "Insert" || key == "Ins") return VK_INSERT;
  if (key == "Home") return VK_HOME;
  if (key == "End") return VK_END;
  if (key == "PageUp") return VK_PRIOR;
  if (key == "PageDown") return VK_NEXT;
  if (key == "Left") return VK_LEFT;
  if (key == "Right") return VK_RIGHT;
  if (key == "Up") return VK_UP;
  if (key == "Down") return VK_DOWN;
  return 0;
}

// Where the widget should sit the first time it appears: docked to the right
// edge of the primary monitor, which is where a permanent fixture is least
// likely to cover whatever is being worked on.
RECT DefaultWidgetBounds() {
  const auto monitors = EnumerateMonitors();
  if (monitors.empty()) return {100, 100, 460, 520};

  HMONITOR primary = MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
  const MonitorInfo* target = nullptr;
  for (const auto& m : monitors) {
    if (m.handle == primary) {
      target = &m;
      break;
    }
  }
  if (target == nullptr) target = &monitors.front();

  const int width = 360;
  const int height = 420;
  const int margin = 12;
  const int left = target->bounds.right - width - margin;
  const int top = target->bounds.top + margin;
  return {left, top, left + width, top + height};
}

}  // namespace

Host::Host(LaunchMode mode) : mode_(mode) {}

Host::~Host() {
  Shutdown();
}

bool Host::ClaimSingleInstance() {
  instance_mutex_ = CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (instance_mutex_ == nullptr) {
    // If the mutex cannot be created, carry on rather than refusing to start.
    return true;
  }
  owns_mutex_ = GetLastError() != ERROR_ALREADY_EXISTS;
  if (owns_mutex_) return true;

  FindShellContext ctx{L"FLUTTER_WINNOTES_WINDOW", nullptr};
  EnumWindows(&FindShellWindow, reinterpret_cast<LPARAM>(&ctx));
  if (ctx.found != nullptr) {
    // WPARAM carries this launch's intent. After an autostart launch the
    // running instance has no editor window, so a person clicking the Start
    // menu icon has to be able to ask for one.
    const UINT intent = (mode_ == LaunchMode::kNormal) ? 1u : 0u;
    PostMessageW(ctx.found, gActivateInstanceMessage, intent, 0);
  }
  return false;
}

Window* Host::WindowFor(SurfaceRole role) const {
  return role == SurfaceRole::kShell ? shell_.get() : editor_.get();
}

bool Host::CreateSurfaces() {
  if (!CreateShellWindow()) return false;

  // The editor only exists when it is asked for. Autostart must not create it,
  // or every login would pop the editor on top of the desktop.
  if (mode_ == LaunchMode::kNormal) {
    if (!EnsureEditorWindow()) return false;
  }
  return true;
}

bool Host::CreateShellWindow() {
  const flutter::DartProject project(L"data");

  WindowCreateParams shell_params;
  shell_params.role = SurfaceRole::kShell;
  shell_params.title = L"WinNotes Widget";
  shell_params.bounds = DefaultWidgetBounds();
  shell_params.visible_at_start = true;
  shell_params.dart_arguments = {"--surface=widget",
                                 std::string("--launch=") + LaunchModeName(mode_)};

  shell_ = std::make_unique<Window>(shell_params, this);
  if (!shell_->Create(project)) return false;

  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      shell_->messenger(), kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        // MethodCall::arguments() returns a pointer to a value owned by the
        // call, and is null for a call sent with no arguments at all.
        const flutter::EncodableMap* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        HandleMethodCall(SurfaceRole::kShell, call.method_name(), args,
                         std::move(result));
      });
  return true;
}

bool Host::EnsureEditorWindow() {
  if (editor_ != nullptr && editor_->handle() != nullptr) return true;
  if (editor_ != nullptr) editor_->Destroy();

  const flutter::DartProject project(L"data");

  WindowCreateParams editor_params;
  editor_params.role = SurfaceRole::kEditor;
  editor_params.title = L"WinNotes";
  editor_params.bounds = {160, 120, 1160, 780};
  editor_params.visible_at_start = true;
  // Always reported as a normal launch: an editor window only exists because
  // somebody asked for one, whatever mode the process itself started in.
  editor_params.dart_arguments = {"--surface=editor", "--launch=normal"};

  editor_ = std::make_unique<Window>(editor_params, this);
  if (!editor_->Create(project)) return false;

  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          editor_->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const flutter::EncodableMap* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        HandleMethodCall(SurfaceRole::kEditor, call.method_name(), args,
                         std::move(result));
      });
  return true;
}

bool Host::Startup() {
  if (!ClaimSingleInstance()) {
    // Another copy is already running and has been told to raise itself.
    return false;
  }

  if (!tray_.Create(GetModuleHandle(nullptr),
                   [this](TrayCommand command) { OnTrayCommand(command); })) {
    return false;
  }
  tray_.SetWidgetVisible(true);

  if (!CreateSurfaces()) return false;

  tray_.SetHotkeyHandler([this]() { SendTo(SurfaceRole::kShell, "event.hotkey", nullptr); });
  // Registered immediately so the hotkey works from the very first moment; Dart
  // sends the real combination during bootstrap and it is re-registered then.
  RegisterHotkeys(tray_.message_window());

  return true;
}

void Host::Shutdown() {
  UnregisterHotkeys();
  if (editor_) {
    editor_->Destroy();
    editor_ = nullptr;
  }
  if (shell_) {
    shell_->Destroy();
    shell_ = nullptr;
  }
  tray_.Destroy();
  if (instance_mutex_ != nullptr) {
    if (owns_mutex_) ReleaseMutex(instance_mutex_);
    CloseHandle(instance_mutex_);
    instance_mutex_ = nullptr;
    owns_mutex_ = false;
  }
}

void Host::Quit() {
  PostQuitMessage(0);
}

void Host::RegisterHotkeys(HWND target) {
  UnregisterHotkeys();
  if (target == nullptr) return;

  // Ctrl+Alt+N until Dart says otherwise. Registering up front means the
  // combination works during startup rather than after the first frame.
  hotkey_modifiers_ = MOD_CONTROL | MOD_ALT;
  hotkey_vk_ = 'N';
  hotkey_id_ = 0x7117;

  hotkey_registered_ =
      RegisterHotKey(target, hotkey_id_, hotkey_modifiers_, hotkey_vk_) != FALSE;
}

void Host::UnregisterHotkeys() {
  if (!hotkey_registered_) return;
  if (tray_.message_window() != nullptr) {
    UnregisterHotKey(tray_.message_window(), hotkey_id_);
  }
  hotkey_registered_ = false;
}

void Host::SendTo(SurfaceRole role, const std::string& method,
                  std::unique_ptr<flutter::EncodableValue> args) {
  Window* window = WindowFor(role);
  if (window == nullptr || window->messenger() == nullptr) return;
  flutter::MethodChannel<flutter::EncodableValue> channel(
      window->messenger(), kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel.InvokeMethod(method, std::move(args));
}

void Host::OnTrayCommand(TrayCommand command) {
  switch (command) {
    case TrayCommand::kToggleWidget: {
      const bool now_visible = !shell_->visible();
      if (now_visible) {
        shell_->Show();
      } else {
        shell_->Hide();
      }
      tray_.SetWidgetVisible(now_visible);
      SendTo(SurfaceRole::kShell, "event.visibility",
             std::make_unique<flutter::EncodableValue>(
                 flutter::EncodableValue(flutter::EncodableMap{
                     {flutter::EncodableValue("role"), flutter::EncodableValue("widget")},
                     {flutter::EncodableValue("visible"), flutter::EncodableValue(now_visible)},
                 })));
      break;
    }
    case TrayCommand::kShowWidget:
      shell_->Show();
      tray_.SetWidgetVisible(true);
      break;
    case TrayCommand::kHideWidget:
      shell_->Hide();
      tray_.SetWidgetVisible(false);
      break;
    case TrayCommand::kOpenEditor: {
      // Closing the editor hides it rather than destroying it, so reopening
      // restores the scroll position and open note instead of starting over.
      // It is created on demand because an autostart launch never made one.
      if (!EnsureEditorWindow()) break;
      editor_->Focus();
      break;
    }
    case TrayCommand::kOpenSettings: {
      if (!EnsureEditorWindow()) break;
      editor_->Focus();
      SendTo(SurfaceRole::kEditor, "event.openSettings", nullptr);
      break;
    }
    case TrayCommand::kQuit:
      if (!ConfirmQuit(tray_.message_window())) break;
      Quit();
      break;
  }
}

// --- WindowHostDelegate ------------------------------------------------------

void Host::OnWindowReady(SurfaceRole role) {
  if (role != SurfaceRole::kShell) return;
  tray_.SetWidgetVisible(shell_ && shell_->visible());
}

void Host::OnWindowHidden(SurfaceRole role) {
  if (role == SurfaceRole::kShell) {
    tray_.SetWidgetVisible(false);
    SendTo(SurfaceRole::kShell, "event.visibility",
           std::make_unique<flutter::EncodableValue>(
               flutter::EncodableValue(flutter::EncodableMap{
                   {flutter::EncodableValue("role"), flutter::EncodableValue("widget")},
                   {flutter::EncodableValue("visible"), flutter::EncodableValue(false)},
               })));
    // Closing the editor hands focus back to the widget rather than leaving a
    // gap on screen where something used to be.
  } else {
    if (shell_ != nullptr && shell_->visible()) shell_->Raise();
  }
}

void Host::OnWindowGeometryChanged(SurfaceRole role, const RECT& bounds) {
  if (role != SurfaceRole::kShell) return;
  SendTo(SurfaceRole::kShell, "event.geometry",
         std::make_unique<flutter::EncodableValue>(EncodeRect(bounds)));
}

void Host::OnWindowCloseRequested(SurfaceRole role) {
  if (role == SurfaceRole::kEditor && shell_ != nullptr && shell_->visible()) {
    shell_->Raise();
  }
}

void Host::OnWindowDocked(SurfaceRole, const RECT&) {
  // Windows owns the drag loop, so snapping is already applied by the time the
  // geometry event arrives; nothing extra to do here yet.
}

void Host::OnInstanceActivated(bool open_editor) {
  // Launching the app when it is already running raises the existing surfaces
  // rather than stacking a second copy on top of them.
  if (shell_ != nullptr) {
    shell_->Show();
    tray_.SetWidgetVisible(true);
  }
  if (!open_editor) return;

  // The running instance may have been started by autostart, in which case no
  // editor window was ever created. Creating it here is what makes clicking the
  // Start menu icon after a reboot do the obvious thing.
  if (editor_ == nullptr || editor_->handle() == nullptr) {
    if (!EnsureEditorWindow()) return;
  }
  editor_->Focus();
}

// --- Method channel ----------------------------------------------------------

void Host::HandleMethodCall(
    SurfaceRole role, const std::string& method, const flutter::EncodableMap* args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method == "bootstrap") {
    const auto monitors = EnumerateMonitors();
    std::vector<flutter::EncodableValue> monitor_list;
    for (const auto& m : monitors) {
      monitor_list.push_back(flutter::EncodableValue(flutter::EncodableMap{
          {flutter::EncodableValue("id"), flutter::EncodableValue(static_cast<int64_t>(m.id))},
          {flutter::EncodableValue("left"), flutter::EncodableValue(static_cast<int64_t>(m.bounds.left))},
          {flutter::EncodableValue("top"), flutter::EncodableValue(static_cast<int64_t>(m.bounds.top))},
          {flutter::EncodableValue("width"), flutter::EncodableValue(static_cast<int64_t>(m.bounds.right - m.bounds.left))},
          {flutter::EncodableValue("height"), flutter::EncodableValue(static_cast<int64_t>(m.bounds.bottom - m.bounds.top))},
          {flutter::EncodableValue("scale"), flutter::EncodableValue(m.scale)},
      }));
    }

    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("role"), flutter::EncodableValue(RoleName(role))},
        {flutter::EncodableValue("launchMode"), flutter::EncodableValue(LaunchModeName(mode_))},
        {flutter::EncodableValue("isWidgetSurface"), flutter::EncodableValue(role == SurfaceRole::kShell)},
        {flutter::EncodableValue("dataDir"), flutter::EncodableValue(WideToUtf8(AppDataDirectory()))},
        {flutter::EncodableValue("exePath"), flutter::EncodableValue(WideToUtf8(ExecutablePath()))},
        {flutter::EncodableValue("isSystemDark"), flutter::EncodableValue(IsSystemDarkMode())},
        {flutter::EncodableValue("animationsEnabled"), flutter::EncodableValue(IsSystemAnimationEnabled())},
        {flutter::EncodableValue("highContrast"), flutter::EncodableValue(IsHighContrastActive())},
        {flutter::EncodableValue("acrylicSupported"), flutter::EncodableValue(AcrylicSupported())},
        {flutter::EncodableValue("buildNumber"), flutter::EncodableValue(static_cast<int64_t>(WindowsBuildNumber()))},
        {flutter::EncodableValue("monitors"), flutter::EncodableValue(monitor_list)},
        {flutter::EncodableValue("autostartEnabled"), flutter::EncodableValue(AutostartEnabled())},
        {flutter::EncodableValue("autostartCommand"), flutter::EncodableValue(WideToUtf8(AutostartCommand()))},
        {flutter::EncodableValue("defaultWidgetBounds"), EncodeRect(DefaultWidgetBounds())},
    }));
    return;
  }

  if (method == "window.show") {
    WindowFor(RoleFrom(args))->PostShow();
    result->Success(flutter::EncodableValue());
    return;
  }
  if (method == "window.hide") {
    Window* target = WindowFor(RoleFrom(args));
    target->PostHide();
    if (RoleFrom(args) == SurfaceRole::kShell) tray_.SetWidgetVisible(false);
    result->Success(flutter::EncodableValue());
    return;
  }
  if (method == "window.focus") {
    WindowFor(RoleFrom(args))->Focus();
    result->Success(flutter::EncodableValue());
    return;
  }
  if (method == "window.setTitle") {
    WindowFor(RoleFrom(args))->SetTitle(Utf8ToWide(GetString(args, "title")));
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "widget.configure") {
    if (shell_ != nullptr) {
      shell_->SetAlwaysOnTop(GetBool(args, "alwaysOnTop", true));
      shell_->SetWidgetOpacity(static_cast<int>(GetInt(args, "opacity", 100)));
      shell_->SetRoundedCorners(GetBool(args, "rounded", true));
      // Absent means locked. A platform message that predates the setting, or
      // a malformed one, must not quietly unlock someone's pinned widget.
      shell_->SetPositionLocked(GetBool(args, "positionLocked", true));
      const bool acrylic = GetBool(args, "acrylic", true) && AcrylicSupported();
      shell_->SetBackdrop(acrylic ? Backdrop::kAcrylic : Backdrop::kPlain);
      const bool visible = GetBool(args, "visible", true);
      if (visible) {
        shell_->Show();
      } else {
        shell_->Hide();
      }
      tray_.SetWidgetVisible(visible);
    }
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "widget.setGeometry") {
    if (shell_ != nullptr) shell_->PostSetBounds(RectFrom(args));
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "hotkey.register") {
    const auto* mods = Find(args, "modifiers");
    std::vector<std::string> names;
    if (mods != nullptr && std::holds_alternative<flutter::EncodableList>(*mods)) {
      for (const auto& item : std::get<flutter::EncodableList>(*mods)) {
        if (std::holds_alternative<std::string>(item)) {
          names.push_back(std::get<std::string>(item));
        }
      }
    }
    UINT modifier_bits = 0;
    for (const auto& name : names) modifier_bits |= ModifierFromString(name);
    const UINT vk = VirtualKeyFromString(GetString(args, "key"));

    UnregisterHotkeys();
    if (!GetBool(args, "enabled", true) || vk == 0 || modifier_bits == 0) {
      result->Success(flutter::EncodableValue(flutter::EncodableMap{
          {flutter::EncodableValue("ok"), flutter::EncodableValue(false)},
          {flutter::EncodableValue("reason"), flutter::EncodableValue("invalid")},
      }));
      return;
    }

    hotkey_modifiers_ = modifier_bits;
    hotkey_vk_ = vk;
    hotkey_id_ = 0x7117;
    // The spec is explicit that a collision must be noticed rather than
    // silently doing nothing, so the failure reason is reported back.
    const BOOL ok = RegisterHotKey(tray_.message_window(), hotkey_id_,
                                   hotkey_modifiers_, hotkey_vk_);
    hotkey_registered_ = ok != FALSE;
    const char* reason = "ok";
    if (!hotkey_registered_) {
      const DWORD err = GetLastError();
      reason = (err == ERROR_HOTKEY_ALREADY_REGISTERED) ? "alreadyRegistered" : "failed";
    }
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("ok"), flutter::EncodableValue(hotkey_registered_)},
        {flutter::EncodableValue("reason"), flutter::EncodableValue(reason)},
    }));
    return;
  }

  if (method == "autostart.query") {
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("enabled"), flutter::EncodableValue(AutostartEnabled())},
        {flutter::EncodableValue("command"), flutter::EncodableValue(WideToUtf8(AutostartCommand()))},
    }));
    return;
  }
  if (method == "autostart.set") {
    const bool enabled = GetBool(args, "enabled", false);
    const bool ok = SetAutostartEnabled(enabled);
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("ok"), flutter::EncodableValue(ok)},
        {flutter::EncodableValue("command"), flutter::EncodableValue(WideToUtf8(AutostartCommand()))},
    }));
    return;
  }

  if (method == "tray.notice") {
    tray_.ShowNotice(Utf8ToWide(GetString(args, "title")),
                     Utf8ToWide(GetString(args, "body")));
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "shell.showEditor") {
    // The hotkey lives on the widget surface and must work even when the
    // process started with --widget and never created an editor at all.
    if (EnsureEditorWindow()) editor_->Focus();
    result->Success(flutter::EncodableValue());
    return;
  }
  if (method == "shell.showWidget") {
    if (shell_ != nullptr) {
      shell_->Show();
      tray_.SetWidgetVisible(true);
    }
    result->Success(flutter::EncodableValue());
    return;
  }
  if (method == "shell.openSettings") {
    if (EnsureEditorWindow()) {
      editor_->Focus();
      SendTo(SurfaceRole::kEditor, "event.openSettings", nullptr);
    }
    result->Success(flutter::EncodableValue());
    return;
  }

  if (method == "dialog.confirmQuit") {
    result->Success(flutter::EncodableValue(ConfirmQuit(nullptr)));
    return;
  }

  if (method == "path.open") {
    OpenInDefaultApp(Utf8ToWide(GetString(args, "path")));
    result->Success(flutter::EncodableValue());
    return;
  }
  if (method == "path.reveal") {
    RevealInExplorer(Utf8ToWide(GetString(args, "path")));
    result->Success(flutter::EncodableValue());
    return;
  }
  if (method == "path.pickFolder") {
    const std::wstring picked =
        PickFolder(nullptr, Utf8ToWide(GetString(args, "start")));
    result->Success(flutter::EncodableValue(
        picked.empty() ? flutter::EncodableValue()
                       : flutter::EncodableValue(WideToUtf8(picked))));
    return;
  }
  if (method == "path.pickFile") {
    const std::wstring picked = PickFile(
        nullptr, Utf8ToWide(GetString(args, "start")),
        Utf8ToWide(GetString(args, "filter")).c_str());
    result->Success(flutter::EncodableValue(
        picked.empty() ? flutter::EncodableValue()
                       : flutter::EncodableValue(WideToUtf8(picked))));
    return;
  }
  if (method == "path.saveFile") {
    const std::wstring filter = Utf8ToWide(GetString(args, "filter"));
    const std::wstring picked =
        SaveFile(nullptr, Utf8ToWide(GetString(args, "start")),
                 Utf8ToWide(GetString(args, "suggestedName")).c_str(),
                 filter.c_str());
    result->Success(flutter::EncodableValue(
        picked.empty() ? flutter::EncodableValue()
                       : flutter::EncodableValue(WideToUtf8(picked))));
    return;
  }

  if (method == "app.quit") {
    Quit();
    result->Success(flutter::EncodableValue());
    return;
  }

  result->NotImplemented();
}

}  // namespace winnotes