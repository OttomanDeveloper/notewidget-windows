#ifndef RUNNER_WIN_NOTES_PLATFORM_H_
#define RUNNER_WIN_NOTES_PLATFORM_H_

#include <windows.h>

#include <string>
#include <vector>

namespace winnotes {

// Which Flutter surface a window hosts.
//
// The two surfaces are separate Flutter engines, each with its own isolate,
// so every native callback is scoped to a role. A callback that does not know
// which surface asked for it is a bug waiting to happen.
enum class SurfaceRole { kShell, kEditor };

// Human name, used as a stable key in the method channel.
const char* RoleName(SurfaceRole role);

// How the app was started, resolved once in main() and handed to Dart.
enum class LaunchMode {
  kNormal,     // Start menu / double click: open the editor.
  kWidgetOnly  // Autostart: go straight to the widget, no editor window.
};

const char* LaunchModeName(LaunchMode mode);

// --- Paths -------------------------------------------------------------------

// Full path of the running executable.
std::wstring ExecutablePath();

// Directory containing the executable.
std::wstring ExecutableDirectory();

// %APPDATA%\WinNotes, created if missing. This is where notes.json,
// settings.json, widget_state.json and selection.json live.
std::wstring AppDataDirectory();

// Tray icon for the current taskbar theme. Lives next to the exe so the icon
// is available before any Dart isolate has finished booting.
std::wstring TrayIconPath(bool dark_taskbar);

// --- System state ------------------------------------------------------------

bool IsSystemDarkMode();
bool IsSystemAnimationEnabled();
bool IsHighContrastActive();

// RtlGetVersion, which is the only way to get a real build number on modern
// Windows. GetVersionEx lies and reports 6.2 without a manifest opt-in.
long WindowsBuildNumber();

// --- Window backdrop ---------------------------------------------------------

enum class Backdrop { kNone, kPlain, kAcrylic };

// Applies a Windows 11 system backdrop to a frameless layered window.
// Returns the backdrop actually applied, which may be less than requested.
Backdrop ApplyBackdrop(HWND hwnd, Backdrop requested, bool dark);

bool AcrylicSupported();

// Clips the window to a rounded rectangle in window coordinates. This is what
// makes the corners genuinely see-through rather than a painted approximation,
// and it stays crisp at any DPI because Windows does the rounding.
bool ApplyRoundedRegion(HWND hwnd, int radius_px);

// --- Monitors ----------------------------------------------------------------

struct MonitorInfo {
  HMONITOR handle = nullptr;
  RECT bounds{};      // Virtual-screen coordinates.
  int id = 0;         // Stable across rearrangements on the same session.
  double scale = 1.0; // DPI / 96.
};

std::vector<MonitorInfo> EnumerateMonitors();

// Nearest monitor to a virtual-screen point. Never returns null: falls back
// to the primary monitor, because returning null would strand the widget
// off-screen where it can never be clicked again.
const MonitorInfo* MonitorForPoint(POINT pt, const std::vector<MonitorInfo>& all);

// Monitor currently displaying a window.
const MonitorInfo* MonitorForWindow(HWND hwnd, const std::vector<MonitorInfo>& all);

// True when a rectangle overlaps any monitor's work area by more than a sliver.
bool RectIsReachable(const RECT& r, const std::vector<MonitorInfo>& all);

// --- Dialogs -----------------------------------------------------------------

// Quit confirmation. Yes/No with No as the default so a stray Enter cannot
// end the app. Runs on the calling (UI) thread, which is the platform thread.
bool ConfirmQuit(HWND owner);

std::wstring PickFolder(HWND owner, const std::wstring& start_dir);
std::wstring PickFile(HWND owner, const std::wstring& start_dir, const wchar_t* filter);
std::wstring SaveFile(HWND owner, const std::wstring& start_dir, const wchar_t* suggested, const wchar_t* filter);

void RevealInExplorer(const std::wstring& path);
void OpenInDefaultApp(const std::wstring& path);

// --- Autostart ---------------------------------------------------------------

// Value written under HKCU\...\Run. Must point at the installed copy, not at
// the project build directory, or deleting the source tree silently disables
// the one feature this app exists to provide.
std::wstring AutostartCommand();
bool AutostartEnabled();
bool SetAutostartEnabled(bool enabled);

// --- String helpers ----------------------------------------------------------

std::wstring Utf8ToWide(const std::string& s);
std::string WideToUtf8(const std::wstring& s);

}  // namespace winnotes

#endif  // RUNNER_WIN_NOTES_PLATFORM_H_