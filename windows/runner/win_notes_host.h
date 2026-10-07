#ifndef RUNNER_WIN_NOTES_HOST_H_
#define RUNNER_WIN_NOTES_HOST_H_

#include <flutter/encodable_value.h>
#include <flutter/method_result.h>
#include <windows.h>

#include <memory>
#include <string>

#include "win_notes_platform.h"
#include "win_notes_tray.h"
#include "win_notes_window.h"

namespace winnotes {

// Owns the process: both surfaces, the tray, the global hotkey, the
// single-instance handshake, and the method channel the Dart side talks to.
class Host : public WindowHostDelegate {
 public:
  explicit Host(LaunchMode mode, std::wstring diagnose_path = std::wstring());
  ~Host() override;

  Host(const Host&) = delete;
  Host& operator=(const Host&) = delete;

  bool Startup();
  void Shutdown();

  // WindowHostDelegate:
  void OnWindowReady(SurfaceRole role) override;
  void OnWindowHidden(SurfaceRole role) override;
  void OnWindowGeometryChanged(SurfaceRole role, const RECT& bounds) override;
  void OnWindowCloseRequested(SurfaceRole role) override;
  void OnWindowDocked(SurfaceRole role, const RECT& bounds) override;
  void OnWindowActivationChanged(SurfaceRole role, bool active) override;
  void OnInstanceActivated(bool open_editor) override;

 private:
  // Returns the already-running window and false if another instance owns it.
  bool ClaimSingleInstance();
  bool CreateSurfaces();
  bool CreateShellWindow();

  // Creates the editor surface if it does not exist yet. Kept separate from
  // CreateSurfaces because a window can be asked for long after startup, by
  // the tray menu, the hotkey or a second launch.
  bool EnsureEditorWindow();
  void RegisterHotkeys(HWND target);
  void UnregisterHotkeys();
  void Quit();

  Window* WindowFor(SurfaceRole role) const;
  // Fire-and-forget message to the Dart side. `args` is moved in because the
  // channel API takes ownership of the payload.
  void SendTo(SurfaceRole role, const std::string& method,
              std::unique_ptr<flutter::EncodableValue> args = nullptr);
  void OnTrayCommand(TrayCommand command);

  // Puts the widget in the topmost band, or takes it back out, so that it never
  // sits above the editor while the editor is the window someone is working in.
  //
  // Both halves are needed. Dropping the widget out of the topmost band on its
  // own leaves it at the top of the *ordinary* band, which is still above the
  // editor - measured, not assumed. The editor therefore has to be brought
  // forward at the same time, or the widget ends up covering the editor *and*
  // burying it.
  void ApplyWidgetTopmost();

  void HandleMethodCall(SurfaceRole role, const std::string& method,
                        const flutter::EncodableMap* args,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  LaunchMode mode_;

  // Non-empty only for `win_notes.exe --diagnose <path>`. Handed to Dart in the
  // bootstrap payload rather than as a Dart argument, because the runner owns
  // the entrypoint arguments and the process command line never reaches them.
  std::wstring diagnose_path_;
  std::unique_ptr<Window> shell_;
  std::unique_ptr<Window> editor_;
  TrayIcon tray_;

  // Hotkey registration lives with the shell surface because the shell is the
  // one surface that exists from boot to quit. A hotkey owned by the editor
  // would stop working the moment the editor was closed.
  bool hotkey_registered_ = false;
  int hotkey_id_ = 0;
  UINT hotkey_modifiers_ = 0;
  UINT hotkey_vk_ = 0;

  HANDLE instance_mutex_ = nullptr;
  HWND previous_instance_window_ = nullptr;
  bool owns_mutex_ = false;

  // The user's always-on-top preference, remembered rather than applied on
  // arrival, because the widget has to be able to leave the topmost band and
  // come back to it without asking Dart again.
  bool always_on_top_ = true;
  // True only while the editor is the foreground window.
  bool editor_foreground_ = false;
};

}  // namespace winnotes

#endif  // RUNNER_WIN_NOTES_HOST_H_