#ifndef RUNNER_WIN_NOTES_WINDOW_H_
#define RUNNER_WIN_NOTES_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <memory>
#include <string>
#include <vector>

#include "win_notes_platform.h"

namespace winnotes {

// Notified when the window wants the host to do something that cannot be
// answered inside the window itself.
class WindowHostDelegate {
 public:
  virtual ~WindowHostDelegate() = default;

  virtual void OnWindowReady(SurfaceRole role) = 0;
  virtual void OnWindowHidden(SurfaceRole role) = 0;
  virtual void OnWindowGeometryChanged(SurfaceRole role, const RECT& bounds) = 0;
  virtual void OnWindowCloseRequested(SurfaceRole role) = 0;
  // Fired for the widget when the user drops it against a screen edge.
  virtual void OnWindowDocked(SurfaceRole role, const RECT& bounds) = 0;
  // The window gained or lost the foreground.
  //
  // Only ever fired for the editor. The widget is WS_EX_NOACTIVATE, so it can
  // become the foreground window exactly once - while it is borrowing the
  // keyboard to compose a note - and the host has no use for that; it is
  // notified of compose mode directly instead.
  virtual void OnWindowActivationChanged(SurfaceRole role, bool active) = 0;
  // A second launch pointed at this instance; bring it forward.
  //
  // [open_editor] carries the intent of the launch that found us, because it is
  // not always the same thing. After an autostart launch there is no editor
  // window at all, so a person clicking the Start menu icon is asking for one
  // and must not be answered with nothing happening.
  virtual void OnInstanceActivated(bool open_editor) = 0;
};

struct WindowCreateParams {
  SurfaceRole role = SurfaceRole::kShell;
  std::wstring title;
  RECT bounds{80, 80, 560, 560};
  bool visible_at_start = true;
  std::vector<std::string> dart_arguments;
};

// A top-level Win32 window hosting one Flutter view.
//
// Each instance owns a FlutterEngine, so the widget surface and the editor
// surface run in separate isolates. That is deliberate: the app already keeps
// its whole state in a JSON file, so a second isolate is a second reader rather
// than a shared-memory problem.
class Window {
 public:
  Window(const WindowCreateParams& params, WindowHostDelegate* delegate);
  ~Window();

  Window(const Window&) = delete;
  Window& operator=(const Window&) = delete;

  bool Create(const flutter::DartProject& project);
  void Destroy();

  // Styles must be chosen before CreateWindowExW, because that is the only
  // moment they can be set without the window briefly flashing wrong.
  static void StyleForRole(SurfaceRole role, DWORD* style, DWORD* ex_style);

  HWND handle() const { return window_; }
  SurfaceRole role() const { return params_.role; }
  flutter::FlutterEngine* engine() const;
  flutter::BinaryMessenger* messenger() const;

  // Visibility. Show uses SW_SHOWNOACTIVATE for the widget so revealing the
  // widget never pulls the caret out of whatever the user is typing into.
  void Show();
  void Hide();
  bool visible() const { return visible_; }

  void Focus();
  void Raise();

  // Widget-only composition controls.
  void SetAlwaysOnTop(bool on_top);
  void SetBackdrop(Backdrop backdrop);
  void SetWidgetOpacity(int alpha_0_100);
  void SetRoundedCorners(bool enabled);

  // Widget-only. While locked the body stops reporting HTCAPTION, so a drag
  // over the card does nothing at all instead of nudging the widget somewhere
  // new. Resize bands are untouched: locking is about position, and a corner
  // drag is a deliberate act rather than an accidental one.
  void SetPositionLocked(bool locked);
  bool position_locked() const { return position_locked_; }

  // Lets the widget take the keyboard, for as long as composing a note needs it.
  //
  // The widget is WS_EX_NOACTIVATE so that clicking it never pulls the caret out
  // of whatever is being typed into - which is also why it cannot contain a text
  // field at all. Rather than give that up for good, the flag is dropped only
  // while someone is actually writing a note, and put straight back afterwards,
  // along with the keyboard: the window that had focus before gets it back.
  //
  // That is the whole trick behind "add a note from the widget". A widget that
  // stole focus permanently would be unusable on a desktop, and one that could
  // never take it could not be typed into.
  void PostSetComposeMode(bool active);
  bool compose_mode() const { return compose_mode_; }

  // Starts a native move or resize loop against the current cursor.
  //
  // Flutter hands Dart only view-relative pointer positions, and a window that
  // follows the cursor shrinks its own reported delta: the widget lands at
  // roughly 40% of the drag that was asked for, however carefully it is
  // computed in Dart. The screen-space position only exists here, so the loop
  // that actually moves the window has to live here too. Dart decides *which*
  // gesture it is and says so; this tracks the cursor.
  void PostBeginMove(double anchor_x, double anchor_y);
  void PostBeginResize(int edge, double anchor_x, double anchor_y);
  void SeedLoopAnchor();

  RECT bounds() const;
  void SetBounds(const RECT& bounds);
  void SetTitle(const std::wstring& title);

  // Pushes a new geometry onto the platform thread. Used by Dart, which is not
  // on the UI thread.
  void PostSetBounds(const RECT& bounds);
  void PostShow();
  void PostHide();

  // Recomputes the widget's rounded region from the current DPI and size.
  void RefreshRoundedRegion();

  bool drag_in_progress() const { return dragging_; }

 private:
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;
  static Window* FromHandle(HWND window) noexcept;

  LRESULT HandleMessage(HWND window, UINT message, WPARAM wparam,
                        LPARAM lparam) noexcept;
  bool OnCreate();
  void OnDestroy();
  void SetChildContent(HWND content);
  LRESULT HitTest(POINT screen_pt) const;
  void ClampToReachableScreen();
  void NotifyGeometry();

  WindowCreateParams params_;
  WindowHostDelegate* delegate_ = nullptr;

  HWND window_ = nullptr;
  HWND child_content_ = nullptr;
  bool visible_ = false;
  // Set by Hide(), and read once by the deferred first-frame Show() in Create.
  // `visible_` cannot carry it: it also starts false, so it does not distinguish
  // "never decided" from "decided, and the answer was hidden".
  bool hidden_before_first_frame_ = false;
  bool dragging_ = false;
  bool rounded_corners_ = false;
  bool position_locked_ = false;  // Draggable until Dart says otherwise.
  int corner_radius_ = 12;
  int edge_dock_margin_ = 8;
  int opacity_percent_ = 100;

  POINT drag_start_screen_{};
  RECT drag_start_bounds_{};
  int resize_edge_ = 0;  // Which edge/corner is being dragged; 0 when idle.
  bool resizing_ = false;

  // Live move or resize loop, started from Dart and driven from here.
  bool move_loop_ = false;
  bool resize_loop_ = false;
  int loop_edge_ = 0;
  POINT loop_start_cursor_{};
  RECT loop_start_bounds_{};
  void EndLoop();

  // Gesture anchor handed over from Dart, view-relative and in logical pixels.
  bool pending_anchor_valid_ = false;
  double pending_anchor_x_ = 0.0;
  double pending_anchor_y_ = 0.0;

  // Compose mode, and the window whose keyboard we are holding.
  bool compose_mode_ = false;
  HWND compose_previous_focus_ = nullptr;
  void ApplyComposeMode(bool active);

  std::unique_ptr<flutter::FlutterViewController> controller_;
};

}  // namespace winnotes

#endif  // RUNNER_WIN_NOTES_WINDOW_H_