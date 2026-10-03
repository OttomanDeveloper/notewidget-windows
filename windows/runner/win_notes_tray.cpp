#include "win_notes_tray.h"

#include <shellapi.h>
#include <windowsx.h>

#include "resource.h"
#include "win_notes_platform.h"

namespace winnotes {

namespace {

constexpr const wchar_t kTrayWindowClass[] = L"FLUTTER_WINNOTES_TRAY";
constexpr UINT kTrayCallback = WM_APP + 20;

enum MenuCommand : UINT {
  kCmdToggleWidget = 1001,
  kCmdShowWidget = 1002,
  kCmdHideWidget = 1003,
  kCmdOpenEditor = 1004,
  kCmdOpenSettings = 1005,
  kCmdQuit = 1099,
};

TrayCommand CommandFromId(UINT id) {
  switch (id) {
    case kCmdToggleWidget: return TrayCommand::kToggleWidget;
    case kCmdShowWidget: return TrayCommand::kShowWidget;
    case kCmdHideWidget: return TrayCommand::kHideWidget;
    case kCmdOpenEditor: return TrayCommand::kOpenEditor;
    case kCmdOpenSettings: return TrayCommand::kOpenSettings;
    case kCmdQuit: return TrayCommand::kQuit;
    default: return TrayCommand::kToggleWidget;
  }
}

}  // namespace

TrayIcon::~TrayIcon() {
  Destroy();
}

bool TrayIcon::Create(HINSTANCE instance, TrayCommandHandler on_command) {
  on_command_ = std::move(on_command);

  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = &TrayIcon::WndProc;
  wc.hInstance = instance;
  wc.lpszClassName = kTrayWindowClass;
  RegisterClassExW(&wc);

  message_window_ = CreateWindowExW(
      0, kTrayWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, instance,
      this);
  if (message_window_ == nullptr) return false;

  data_ = {};
  data_.cbSize = sizeof(data_);
  data_.hWnd = message_window_;
  data_.uID = 1;
  data_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  data_.uCallbackMessage = kTrayCallback;
  wcscpy_s(data_.szTip, L"WinNotes");
  data_.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(IDI_TRAY_ICON));
  data_.uVersion = NOTIFYICON_VERSION_4;

  icon_added_ = FALSE != Shell_NotifyIconW(NIM_ADD, &data_);
  if (icon_added_) {
    Shell_NotifyIconW(NIM_SETVERSION, &data_);
  }
  RefreshIconForTheme();
  return icon_added_;
}

void TrayIcon::Destroy() {
  if (icon_added_) {
    Shell_NotifyIconW(NIM_DELETE, &data_);
    icon_added_ = false;
  }
  DestroyMenu();
  if (message_window_ != nullptr) {
    HWND target = message_window_;
    message_window_ = nullptr;
    DestroyWindow(target);
  }
}

void TrayIcon::RefreshIconForTheme() {
  if (!icon_added_) return;

  // A colour icon disappears into a same-coloured taskbar. Windows tells us
  // which taskbar is in play through AppsUseLightTheme, so the tray gets a
  // light-theme or dark-theme drawing of the same mark.
  const bool dark_taskbar = !IsSystemDarkMode();
  const std::wstring icon_path = TrayIconPath(dark_taskbar);

  HICON icon = static_cast<HICON>(
      LoadImageW(GetModuleHandle(nullptr), icon_path.c_str(), IMAGE_ICON, 0, 0,
                 LR_LOADFROMFILE | LR_DEFAULTSIZE));
  if (icon == nullptr) {
    // Fall back to the resource icon so the tray is never empty.
    icon = LoadIconW(GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_TRAY_ICON));
  }
  if (icon == nullptr) return;

  data_.hIcon = icon;
  data_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  Shell_NotifyIconW(NIM_MODIFY, &data_);
}

void TrayIcon::BuildMenu() {
  DestroyMenu();
  menu_ = CreatePopupMenu();
  if (menu_ == nullptr) return;

  // Spelled out as the action it performs rather than as a state toggle with a
  // tick: "Show widget" next to a checked box is ambiguous about which one it
  // refers to, and the checkmark is the only hint the user would get.
  AppendMenuW(menu_, MF_STRING,
              widget_visible_ ? kCmdHideWidget : kCmdShowWidget,
              widget_visible_ ? L"Hide widget" : L"Show widget");
  AppendMenuW(menu_, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu_, MF_STRING, kCmdOpenEditor, L"Open editor\tCtrl+Alt+N");
  AppendMenuW(menu_, MF_STRING, kCmdOpenSettings, L"Settings\tCtrl+Alt+S");
  AppendMenuW(menu_, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu_, MF_STRING, kCmdQuit, L"Quit WinNotes");
}

void TrayIcon::SetWidgetVisible(bool visible) {
  if (widget_visible_ == visible && menu_ != nullptr) return;
  widget_visible_ = visible;
  BuildMenu();
}

void TrayIcon::SetHotkeyHandler(std::function<void()> handler) {
  on_hotkey_ = std::move(handler);
}

void TrayIcon::DestroyMenu() {
  if (menu_ != nullptr) {
    // Qualified: this member function shadows the Win32 DestroyMenu, so an
    // unqualified call here would recurse into itself with the wrong arity.
    ::DestroyMenu(menu_);
    menu_ = nullptr;
  }
}

void TrayIcon::ShowNotice(const std::wstring& title, const std::wstring& body) {
  if (!icon_added_) return;
  NOTIFYICONDATAW notice = data_;
  notice.uFlags = NIF_INFO;
  notice.dwInfoFlags = NIIF_WARNING | NIIF_RESPECT_QUIET_TIME;
  wcscpy_s(notice.szInfoTitle, title.c_str());
  wcscpy_s(notice.szInfo, body.c_str());
  Shell_NotifyIconW(NIM_MODIFY, &notice);
}

LRESULT CALLBACK TrayIcon::WndProc(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam) noexcept {
  auto* self = reinterpret_cast<TrayIcon*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));

  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  } else if (self != nullptr) {
    switch (message) {
      case kTrayCallback: {
        // NOTIFYICON_VERSION_4 packs the event in the low word and the
        // identifier in the high word.
        const UINT event = LOWORD(lparam);
        if (event == WM_LBUTTONUP || event == WM_LBUTTONDBLCLK) {
          // Clicking the icon goes to the editor: that is what a person
          // clicking the app's icon means to do.
          if (self->on_command_) self->on_command_(TrayCommand::kOpenEditor);
          return 0;
        }
        if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
          const POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
          SetForegroundWindow(window);
          self->BuildMenu();
          if (self->menu_ != nullptr) {
            // Setting the foreground window is what makes the menu dismiss
            // when the user clicks somewhere else; WM_NULL clears it again.
            TrackPopupMenu(self->menu_,
                           TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY, pt.x,
                           pt.y, 0, window, nullptr);
          }
          PostMessageW(window, WM_NULL, 0, 0);
          return 0;
        }
        break;
      }

      case WM_COMMAND: {
        if (self->on_command_) self->on_command_(CommandFromId(HIWORD(lparam)));
        return 0;
      }

      case WM_HOTKEY: {
        if (self->on_hotkey_) self->on_hotkey_();
        return 0;
      }

      case WM_THEMECHANGED:
      case WM_SETTINGCHANGE:
        // Someone switched Windows between light and dark while running.
        self->RefreshIconForTheme();
        return 0;

      case WM_DESTROY:
        self->DestroyMenu();
        return 0;

      default:
        break;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

}  // namespace winnotes