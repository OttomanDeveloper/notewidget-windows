#ifndef RUNNER_WIN_NOTES_TRAY_H_
#define RUNNER_WIN_NOTES_TRAY_H_

#include <windows.h>

#include <functional>
#include <string>

namespace winnotes {

// The command behind a tray menu item. Dart maps these onto what the user
// expects; native only has to know which item was clicked.
enum class TrayCommand {
  kToggleWidget,
  kShowWidget,
  kHideWidget,
  kOpenEditor,
  kOpenSettings,
  kQuit,
};

using TrayCommandHandler = std::function<void(TrayCommand)>;

// A Shell_NotifyIcon wrapper that owns a hidden message-only window.
//
// The hidden window exists because tray callbacks and the global hotkey both
// need somewhere to arrive. Attaching them to a visible surface would mean the
// tray stops working whenever that window is hidden, which for the widget is
// most of the time.
class TrayIcon {
 public:
  TrayIcon() = default;
  ~TrayIcon();

  TrayIcon(const TrayIcon&) = delete;
  TrayIcon& operator=(const TrayIcon&) = delete;

  bool Create(HINSTANCE instance, TrayCommandHandler on_command);
  void Destroy();

  // Reflects app state in the menu, so the entry never reads as a state
  // toggle whose meaning depends on a tick mark.
  void SetWidgetVisible(bool visible);

  // Swaps the icon to match a light or dark taskbar, and back again if the
  // user changes Windows theme while the app is running.
  void RefreshIconForTheme();

  // Balloon used for "the notes file could not be read", which is the one
  // message that must reach someone who has not opened the editor.
  void ShowNotice(const std::wstring& title, const std::wstring& body);

  // The global hotkey is registered against this same hidden window, because
  // WM_HOTKEY needs a wndproc and this is the only one that is never hidden,
  // destroyed or recreated.
  void SetHotkeyHandler(std::function<void()> handler);

  HWND message_window() const { return message_window_; }

 private:
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;
  void BuildMenu();
  void DestroyMenu();

  HWND message_window_ = nullptr;
  NOTIFYICONDATAW data_{};
  HMENU menu_ = nullptr;
  TrayCommandHandler on_command_;
  std::function<void()> on_hotkey_;
  bool icon_added_ = false;
  bool widget_visible_ = false;
};

}  // namespace winnotes

#endif  // RUNNER_WIN_NOTES_TRAY_H_