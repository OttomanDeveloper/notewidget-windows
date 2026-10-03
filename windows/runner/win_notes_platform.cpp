#include "win_notes_platform.h"

#include <dwmapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <shellscalingapi.h>
#include <versionhelpers.h>

#include <cmath>
#include <vector>

#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "shcore.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "advapi32.lib")

namespace winnotes {

namespace {

constexpr wchar_t kAppFolder[] = L"WinNotes";
constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"WinNotes";
constexpr wchar_t kThemeKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr wchar_t kThemeValue[] = L"AppsUseLightTheme";

constexpr wchar_t kTrayLight[] = L"winnotes_tray_light.ico";
constexpr wchar_t kTrayDark[] = L"winnotes_tray_dark.ico";

// --- Undocumented composition attribute --------------------------------------
//
// SetWindowCompositionAttribute has been the only way to put acrylic behind an
// arbitrary top-level window since Windows 10, and it is what makes the widget
// pick up the wallpaper instead of being a flat grey rectangle. It is resolved
// dynamically so a future Windows build that drops it degrades to the plain
// translucent surface rather than refusing to load.
enum AccentState {
  kAccentDisabled = 0,
  kAccentEnableBlurBehind = 3,
  kAccentEnableAcrylicBlurBehind = 4,
};

struct AccentPolicy {
  DWORD AccentState;
  DWORD AccentFlags;
  DWORD GradientColor;   // 0xAABBGGRR
  DWORD AnimationId;
};

struct WindowCompositionAttributeData {
  DWORD Attribute;
  void* Data;
  SIZE_T SizeOfData;
};

using SetWindowCompositionAttributeFn = BOOL(WINAPI*)(HWND,
                                                       WindowCompositionAttributeData*);

SetWindowCompositionAttributeFn ResolveSetWindowCompositionAttribute() {
  static SetWindowCompositionAttributeFn fn = [] {
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    return user32 ? reinterpret_cast<SetWindowCompositionAttributeFn>(
                        GetProcAddress(user32, "SetWindowCompositionAttribute"))
                  : nullptr;
  }();
  return fn;
}

// DWMWA attributes that are not in older SDK headers.
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif

constexpr DWORD kDwmSystemBackdropType = 2;  // DWMSBT_MAINWINDOW

// Maps a colour to the 0xAABBGGRR form the accent policy expects.
// Alpha is applied here so the widget's opacity setting reaches the blur too,
// not just the content on top of it.
DWORD GradientColorFromBgra(BYTE b, BYTE g, BYTE r, BYTE a) {
  return (static_cast<DWORD>(a) << 24) | (static_cast<DWORD>(r) << 16) |
         (static_cast<DWORD>(g) << 8) | static_cast<DWORD>(b);
}

}  // namespace

const char* RoleName(SurfaceRole role) {
  return role == SurfaceRole::kShell ? "shell" : "editor";
}

const char* LaunchModeName(LaunchMode mode) {
  return mode == LaunchMode::kWidgetOnly ? "widget" : "normal";
}

// --- Paths -------------------------------------------------------------------

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  const int needed =
      MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(static_cast<size_t>(needed), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), out.data(), needed);
  return out;
}

std::string WideToUtf8(const std::wstring& s) {
  if (s.empty()) return "";
  const int needed =
      WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0, nullptr, nullptr);
  std::string out(static_cast<size_t>(needed), '\0');
  WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), out.data(), needed, nullptr, nullptr);
  return out;
}

std::wstring ExecutablePath() {
  std::vector<wchar_t> buf(MAX_PATH);
  for (;;) {
    DWORD n = GetModuleFileNameW(nullptr, buf.data(), static_cast<DWORD>(buf.size()));
    if (n == 0) return L"";
    if (n < buf.size()) return std::wstring(buf.data(), n);
    buf.resize(buf.size() * 2);
  }
}

std::wstring ExecutableDirectory() {
  std::wstring path = ExecutablePath();
  const size_t slash = path.find_last_of(L'\\');
  return slash == std::wstring::npos ? std::wstring() : path.substr(0, slash);
}

std::wstring AppDataDirectory() {
  PWSTR roaming = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &roaming))) {
    return std::wstring();
  }
  std::wstring base(roaming);
  CoTaskMemFree(roaming);

  std::wstring dir = base + L"\\" + kAppFolder;
  SHCreateDirectoryExW(nullptr, dir.c_str(), nullptr);
  return dir;
}

std::wstring TrayIconPath(bool dark_taskbar) {
  return ExecutableDirectory() + L"\\" + (dark_taskbar ? kTrayDark : kTrayLight);
}

// --- System state ------------------------------------------------------------

bool IsSystemDarkMode() {
  DWORD light_mode = 1;
  DWORD size = sizeof(light_mode);
  const LSTATUS r = RegGetValueW(HKEY_CURRENT_USER, kThemeKey, kThemeValue,
                                 RRF_RT_REG_DWORD, nullptr, &light_mode, &size);
  return r == ERROR_SUCCESS && light_mode == 0;
}

bool IsSystemAnimationEnabled() {
  BOOL enabled = TRUE;
  if (!SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &enabled, 0)) {
    return TRUE;
  }
  return enabled != FALSE;
}

bool IsHighContrastActive() {
  HIGHCONTRASTW hc{};
  hc.cbSize = sizeof(hc);
  if (!SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(hc), &hc, 0)) return false;
  return (hc.dwFlags & HCF_HIGHCONTRASTON) != 0;
}

long WindowsBuildNumber() {
  // GetVersionEx is shimmed for compatibility and reports 6.2 on Windows 11.
  // RtlGetVersion is ntdll's real implementation.
  using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
  static const RtlGetVersionFn fn = [] {
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    return ntdll ? reinterpret_cast<RtlGetVersionFn>(GetProcAddress(ntdll, "RtlGetVersion"))
                 : nullptr;
  }();
  if (!fn) return 0;
  RTL_OSVERSIONINFOW info{};
  info.dwOSVersionInfoSize = sizeof(info);
  if (fn(&info) != 0) return 0;
  return info.dwBuildNumber;
}

// --- Backdrop ----------------------------------------------------------------

bool AcrylicSupported() {
  return ResolveSetWindowCompositionAttribute() != nullptr &&
         WindowsBuildNumber() >= 22000;
}

bool ApplyRoundedRegion(HWND hwnd, int radius_px) {
  if (hwnd == nullptr || radius_px <= 0) return false;
  RECT client{};
  if (!GetClientRect(hwnd, &client)) return false;
  const int w = client.right - client.left;
  const int h = client.bottom - client.top;
  if (w <= 0 || h <= 0) return false;

  // Windows owns the corner rounding, so the curve stays smooth at any DPI and
  // the pixels outside it are truly not composited, rather than being painted
  // to look approximately transparent.
  HRGN region = CreateRoundRectRgn(0, 0, w + 1, h + 1, radius_px * 2, radius_px * 2);
  if (region == nullptr) return false;
  const BOOL ok = SetWindowRgn(hwnd, region, TRUE);
  if (!ok) DeleteObject(region);  // Ownership transferred on success.
  return ok != FALSE;
}

Backdrop ApplyBackdrop(HWND hwnd, Backdrop requested, bool dark) {
  if (hwnd == nullptr) return Backdrop::kNone;

  BOOL dark_mode = dark ? TRUE : FALSE;
  DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark_mode,
                        sizeof(dark_mode));

  // Corner shape is a system preference; honour it rather than forcing
  // rounded corners on someone who asked Windows for square ones.
  const int preference = 2;  // DWMWCP_ROUND
  DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &preference,
                        sizeof(preference));

  SetWindowCompositionAttributeFn set_composition =
      ResolveSetWindowCompositionAttribute();
  if (set_composition == nullptr) return Backdrop::kPlain;

  AccentPolicy policy{};
  WindowCompositionAttributeData data{};

  if (requested == Backdrop::kAcrylic && WindowsBuildNumber() >= 22000) {
    const int type = kDwmSystemBackdropType;
    DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &type, sizeof(type));
  }

  if (requested == Backdrop::kAcrylic) {
    policy.AccentState = kAccentEnableAcrylicBlurBehind;
    policy.AccentFlags = 0;
    // Dark theme leans indigo, light theme leans near-white. Both keep enough
    // alpha that the card text stays legible over a busy wallpaper.
    policy.GradientColor =
        dark ? GradientColorFromBgra(0x1B, 0x16, 0x38, 0xC0)
             : GradientColorFromBgra(0xF4, 0xF2, 0xEE, 0xC0);
    policy.AnimationId = 0;
  } else {
    policy.AccentState = kAccentDisabled;
    policy.AccentFlags = 0;
    policy.GradientColor = 0;
    policy.AnimationId = 0;
  }

  data.Attribute = 19;  // WCA_ACCENT_POLICY
  data.Data = &policy;
  data.SizeOfData = sizeof(policy);

  if (!set_composition(hwnd, &data)) {
    // Spec is explicit that a missing acrylic must degrade to a plain
    // translucent surface rather than fail to draw.
    return Backdrop::kPlain;
  }
  return requested;
}

// --- Monitors ----------------------------------------------------------------

namespace {

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM param) {
  auto* out = reinterpret_cast<std::vector<MonitorInfo>*>(param);
  if (out == nullptr) return TRUE;

  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) return TRUE;

  MonitorInfo mi;
  mi.handle = monitor;
  mi.bounds = info.rcMonitor;
  // Parse the device name (\\.\DISPLAY1) so the id follows the monitor itself
  // rather than its index, which changes when monitors are added or removed.
  const wchar_t* display = wcsstr(info.szDevice, L"DISPLAY");
  mi.id = display != nullptr ? static_cast<int>(wcstol(display + 7, nullptr, 10)) : 0;

  UINT dpi_x = 96, dpi_y = 96;
  if (FAILED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
    dpi_x = dpi_y = 96;
  }
  mi.scale = static_cast<double>(dpi_x) / 96.0;
  out->push_back(mi);
  return TRUE;
}

bool RectsOverlapAtLeast(const RECT& a, const RECT& b, LONG min_overlap) {
  const LONG dx = std::min(a.right, b.right) - std::max(a.left, b.left);
  const LONG dy = std::min(a.bottom, b.bottom) - std::max(a.top, b.top);
  return dx >= min_overlap && dy >= min_overlap;
}

}  // namespace

std::vector<MonitorInfo> EnumerateMonitors() {
  std::vector<MonitorInfo> monitors;
  EnumDisplayMonitors(nullptr, nullptr, &CollectMonitor,
                      reinterpret_cast<LPARAM>(&monitors));
  if (monitors.empty()) {
    // EnumDisplayMonitors failing entirely is not something the widget can do
    // anything useful about, but it must not hand callers an empty list.
    MonitorInfo fallback;
    fallback.handle = nullptr;
    fallback.scale = 1.0;
    if (SystemParametersInfoW(SPI_GETWORKAREA, 0, &fallback.bounds, 0)) {
      fallback.bounds = {0, 0, 1920, 1080};
      monitors.push_back(fallback);
    }
  }
  return monitors;
}

const MonitorInfo* MonitorForPoint(POINT pt, const std::vector<MonitorInfo>& all) {
  for (const auto& m : all) {
    if (pt.x >= m.bounds.left && pt.x < m.bounds.right && pt.y >= m.bounds.top &&
        pt.y < m.bounds.bottom) {
      return &m;
    }
  }
  // Not on any monitor: clamp into the nearest one by centre distance so the
  // widget comes back on screen rather than somewhere unclickable.
  const MonitorInfo* best = nullptr;
  double best_d = 0;
  for (const auto& m : all) {
    const double cx = (m.bounds.left + m.bounds.right) / 2.0;
    const double cy = (m.bounds.top + m.bounds.bottom) / 2.0;
    const double dx = cx - pt.x, dy = cy - pt.y;
    const double d = dx * dx + dy * dy;
    if (best == nullptr || d < best_d) { best = &m; best_d = d; }
  }
  return best != nullptr ? best : nullptr;
}

const MonitorInfo* MonitorForWindow(HWND hwnd, const std::vector<MonitorInfo>& all) {
  if (all.empty()) return nullptr;
  RECT r{};
  if (!GetWindowRect(hwnd, &r)) return &all.front();
  POINT centre{(r.left + r.right) / 2, (r.top + r.bottom) / 2};
  return MonitorForPoint(centre, all);
}

bool RectIsReachable(const RECT& r, const std::vector<MonitorInfo>& all) {
  // Require a real overlap, not a single pixel: a window technically on-screen
  // but with 99% of it off the edge is exactly the unreachable case the spec
  // calls out after a monitor gets unplugged.
  constexpr LONG kMinVisible = 64;
  for (const auto& m : all) {
    if (RectsOverlapAtLeast(r, m.bounds, kMinVisible)) return true;
  }
  return false;
}

// --- Dialogs -----------------------------------------------------------------

bool ConfirmQuit(HWND owner) {
  const int result = MessageBoxW(
      owner, L"WinNotes will stop running.\n\nYour notes are already saved on "
              L"this PC.",
      L"Quit WinNotes", MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2 |
                            MB_SETFOREGROUND | MB_TOPMOST);
  return result == IDYES;
}

namespace {

enum class DialogMode { kOpen, kSave };

// Wraps IFileOpenDialog / IFileSaveDialog behind one call.
//
// The two interfaces are separate COM objects rather than one with a flag, so
// the mode check below is unavoidable. Everything else - folder default,
// filter, result extraction - is shared.
std::wstring RunFileDialog(HWND owner, const std::wstring& start_dir,
                           DialogMode mode, DWORD flags, const wchar_t* file_name,
                           const wchar_t* filter) {
  std::wstring result;

  if (mode == DialogMode::kSave) {
    IFileSaveDialog* save = nullptr;
    if (FAILED(CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&save)))) {
      return result;
    }
    if (file_name != nullptr && *file_name != L'\0') save->SetFileName(file_name);

    if (SUCCEEDED(save->Show(owner))) {
      IShellItem* item = nullptr;
      if (SUCCEEDED(save->GetResult(&item)) && item != nullptr) {
        PWSTR path = nullptr;
        if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
          result = path;
          CoTaskMemFree(path);
        }
        item->Release();
      }
    }
    save->Release();
    return result;
  }

  IFileOpenDialog* open = nullptr;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&open)))) {
    return result;
  }

  // Prefer the caller's folder; fall back to Desktop so the dialog never
  // opens on an empty or unexpected location.
  const std::wstring initial =
      start_dir.empty() ? ExecutableDirectory() : start_dir;
  IShellItem* folder = nullptr;
  if (!initial.empty() &&
      SUCCEEDED(SHCreateItemFromParsingName(initial.c_str(), nullptr,
                                           IID_PPV_ARGS(&folder))) &&
      folder != nullptr) {
    open->SetFolder(folder);
    folder->Release();
  }

  if (filter != nullptr && *filter != L'\0') {
    COMDLG_FILTERSPEC specs[1]{};
    specs[0].pszName = L"WinNotes";  // Ignored when pszName is null; kept explicit.
    specs[0].pszSpec = filter;
    open->SetFileTypes(1, specs);
  }

  DWORD opts = 0;
  open->GetOptions(&opts);
  open->SetOptions(opts | flags | FOS_NOCHANGEDIR);

  if (SUCCEEDED(open->Show(owner))) {
    IShellItem* item = nullptr;
    if (SUCCEEDED(open->GetResult(&item)) && item != nullptr) {
      PWSTR path = nullptr;
      if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
        result = path;
        CoTaskMemFree(path);
      }
      item->Release();
    }
  }
  open->Release();
  return result;
}

}  // namespace

std::wstring PickFolder(HWND owner, const std::wstring& start_dir) {
  return RunFileDialog(owner, start_dir, DialogMode::kOpen,
                       FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST,
                       nullptr, nullptr);
}

std::wstring PickFile(HWND owner, const std::wstring& start_dir, const wchar_t* filter) {
  return RunFileDialog(owner, start_dir, DialogMode::kOpen,
                       FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST,
                       nullptr, filter);
}

std::wstring SaveFile(HWND owner, const std::wstring& start_dir, const wchar_t* suggested, const wchar_t* filter) {
  return RunFileDialog(owner, start_dir, DialogMode::kSave,
                       FOS_FORCEFILESYSTEM | FOS_OVERWRITEPROMPT, suggested, filter);
}

void RevealInExplorer(const std::wstring& path) {
  if (path.empty()) return;
  const std::wstring param = L"/select,\"" + path + L"\"";
  ShellExecuteW(nullptr, L"open", L"explorer.exe", const_cast<LPWSTR>(param.c_str()),
                nullptr, SW_SHOWNORMAL);
}

void OpenInDefaultApp(const std::wstring& path) {
  if (path.empty()) return;
  ShellExecuteW(nullptr, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

// --- Autostart ---------------------------------------------------------------

std::wstring AutostartCommand() {
  // The installed copy, with the widget flag so a login never pops the editor.
  std::wstring exe = ExecutablePath();
  if (exe.empty()) return L"";
  return L"\"" + exe + L"\" --widget";
}

bool AutostartEnabled() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) {
    return false;
  }
  wchar_t buffer[2048]{};
  DWORD size = sizeof(buffer);
  DWORD type = 0;
  const LSTATUS r = RegQueryValueExW(key, kRunValue, nullptr, &type,
                                     reinterpret_cast<LPBYTE>(buffer), &size);
  RegCloseKey(key);
  return r == ERROR_SUCCESS && type == REG_SZ && size > 1;
}

bool SetAutostartEnabled(bool enabled) {
  HKEY key = nullptr;
  DWORD disposition = 0;
  LSTATUS r = RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr,
                              REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr,
                              &key, &disposition);
  if (r != ERROR_SUCCESS) return false;

  r = ERROR_SUCCESS;
  if (enabled) {
    const std::wstring command = AutostartCommand();
    if (command.empty()) {
      RegCloseKey(key);
      return false;
    }
    // Written as REG_SZ, not REG_EXPAND_SZ: nothing here contains %VAR%, and
    // Task Manager's Startup tab only lists plain string values.
    r = RegSetValueExW(key, kRunValue, 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(command.c_str()),
                       static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    r = RegDeleteValueW(key, kRunValue);
    if (r == ERROR_FILE_NOT_FOUND) r = ERROR_SUCCESS;
  }
  RegCloseKey(key);
  return r == ERROR_SUCCESS;
}

}  // namespace winnotes