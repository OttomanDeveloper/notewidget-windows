#include "win_notes_window.h"

#include <dwmapi.h>
#include <shellscalingapi.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

namespace winnotes {

namespace {

// One registered class serves both roles. Every message is dispatched through
// the instance stored in GWLP_USERDATA, so the shared class costs nothing and
// keeps registration in a single place.
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_WINNOTES_WINDOW";

// DWMWA_USE_IMMERSIVE_DARK_MODE is missing from older SDK headers.
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr int kMinWidgetWidth = 200;
constexpr int kMinWidgetHeight = 140;

// Messages below WM_APP are reserved for the system, so WinNotes starts there.
constexpr UINT kWmGeometryChanged = WM_APP + 1;
constexpr UINT kWmShow = WM_APP + 2;
constexpr UINT kWmHide = WM_APP + 3;
constexpr UINT kWmSetBounds = WM_APP + 4;
constexpr UINT kWmToggleVisible = WM_APP + 5;
constexpr UINT kWmBeginMove = WM_APP + 6;
constexpr UINT kWmBeginResize = WM_APP + 7;
constexpr UINT kWmComposeMode = WM_APP + 8;

// Edges for kWmBeginResize. Plain integers rather than HT* values: HTLEFT and
// friends collide with the hit-test codes, and this is a different vocabulary
// for the same idea.
enum EdgeCode {
  kEdgeNone = 0,
  kEdgeLeft = 1,
  kEdgeRight = 2,
  kEdgeTop = 3,
  kEdgeBottom = 4,
  kEdgeTopLeft = 5,
  kEdgeTopRight = 6,
  kEdgeBottomLeft = 7,
  kEdgeBottomRight = 8,
};
// Must match gActivateInstanceMessage in win_notes_host.cpp, which posts it.
constexpr UINT kWmActivateInstance = WM_APP + 40;

// Scales a logical pixel count to the physical pixels of the window's monitor.
int ScaleForWindow(HWND window, int logical) {
  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  UINT dpi = 96;
  if (monitor != nullptr && SUCCEEDED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI,
                                                        &dpi, nullptr))) {
    // Fall through to the 96 default below.
  }
  if (dpi == 0) dpi = 96;
  return MulDiv(logical, static_cast<int>(dpi), 96);
}

bool IsWidgetRole(SurfaceRole role) {
  return role == SurfaceRole::kShell;
}

}  // namespace

Window::Window(const WindowCreateParams& params, WindowHostDelegate* delegate)
    : params_(params), delegate_(delegate) {}

Window::~Window() {
  Destroy();
}

flutter::FlutterEngine* Window::engine() const {
  return controller_ ? controller_->engine() : nullptr;
}

flutter::BinaryMessenger* Window::messenger() const {
  return controller_ ? controller_->engine()->messenger() : nullptr;
}

void Window::StyleForRole(SurfaceRole role, DWORD* style, DWORD* ex_style) {
  if (role == SurfaceRole::kShell) {
    // Frameless, layered so DWM can composite acrylic behind it, and
    // NOACTIVATE so clicking it never steals the caret mid-sentence.
    // WS_EX_TOOLWINDOW keeps it out of the taskbar and out of Alt+Tab, which is
    // what "no taskbar button" means in practice.
    *style = WS_POPUP;
    *ex_style = WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
  } else {
    // The editor is an ordinary window on purpose: it is the one surface the
    // user is deliberately looking at, so it gets a real title bar.
    *style = WS_OVERLAPPEDWINDOW;
    *ex_style = 0;
  }
}

bool Window::Create(const flutter::DartProject& project) {
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.style = CS_DBLCLKS;
  wc.lpfnWndProc = &Window::WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.hIcon = LoadIconW(wc.hInstance, MAKEINTRESOURCEW(IDI_APP_ICON));
  wc.hIconSm = LoadIconW(wc.hInstance, MAKEINTRESOURCEW(IDI_APP_ICON));
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = nullptr;  // Flutter paints every pixel.
  wc.lpszClassName = kWindowClassName;
  // A second window of the same class is not an error; ignore the failure.
  RegisterClassExW(&wc);

  DWORD style = 0, ex_style = 0;
  StyleForRole(params_.role, &style, &ex_style);

  const int width = params_.bounds.right - params_.bounds.left;
  const int height = params_.bounds.bottom - params_.bounds.top;

  window_ = CreateWindowExW(
      ex_style, kWindowClassName, params_.title.c_str(), style,
      params_.bounds.left, params_.bounds.top, width, height, nullptr,
      nullptr, wc.hInstance, this);

  if (window_ == nullptr) return false;

  // Tagged so the single-instance handshake can find the shell specifically
  // rather than whichever surface happens to exist. Both windows share one
  // window class, so the class name alone cannot tell them apart.
  SetPropW(window_, L"WinNotesRole",
           params_.role == SurfaceRole::kShell ? L"shell" : L"editor");
  return OnCreate();
}

bool Window::OnCreate() {
  if (controller_) return true;

  // Each surface gets its own DartProject so it can carry its own entrypoint
  // arguments. `main()` reads them and decides which app to run, so a single
  // Dart library backs both windows with no extra entrypoints to maintain.
  flutter::DartProject scoped(L"data");
  scoped.set_dart_entrypoint_arguments(params_.dart_arguments);

  RECT client{};
  GetClientRect(window_, &client);
  const int w = client.right - client.left;
  const int h = client.bottom - client.top;

  controller_ = std::make_unique<flutter::FlutterViewController>(
      w > 0 ? w : 320, h > 0 ? h : 320, scoped);
  if (!controller_->engine() || !controller_->view()) {
    controller_ = nullptr;
    return false;
  }

  RegisterPlugins(controller_->engine());
  SetChildContent(controller_->view()->GetNativeWindow());

  if (IsWidgetRole(params_.role)) {
    rounded_corners_ = true;
    corner_radius_ = 12;
    RefreshRoundedRegion();
    // Acrylic on top of whatever the desktop is showing. If the build cannot
    // do it, ApplyBackdrop downgrades and Dart paints the plain translucent
    // surface instead.
    ApplyBackdrop(window_, AcrylicSupported() ? Backdrop::kAcrylic
                                               : Backdrop::kPlain,
                  IsSystemDarkMode());
  } else {
    // Correct title bar button colours for the current Windows theme.
    const BOOL dark = IsSystemDarkMode() ? TRUE : FALSE;
    DwmSetWindowAttribute(window_, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark,
                          sizeof(dark));
  }

  controller_->engine()->SetNextFrameCallback([this]() {
    if (params_.visible_at_start) Show();
    if (delegate_ != nullptr) delegate_->OnWindowReady(params_.role);
  });
  controller_->ForceRedraw();
  return true;
}

void Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_);
  RECT frame{};
  GetClientRect(window_, &frame);
  MoveWindow(content, 0, 0, frame.right - frame.left, frame.bottom - frame.top,
             TRUE);
  // Deliberately no SetFocus here. The editor's focus arrives from
  // SetForegroundWindow, and for the widget taking focus is exactly what
  // WS_EX_NOACTIVATE exists to prevent.
}

void Window::OnDestroy() {
  child_content_ = nullptr;
  controller_ = nullptr;
}

void Window::Destroy() {
  if (window_ != nullptr) {
    HWND target = window_;
    window_ = nullptr;
    DestroyWindow(target);
  }
  OnDestroy();
}

// --- Visibility --------------------------------------------------------------

void Window::Show() {
  if (window_ == nullptr) return;
  if (IsWidgetRole(params_.role)) {
    // SW_SHOWNOACTIVATE: putting the widget on screen must not steal focus.
    ShowWindow(window_, SW_SHOWNOACTIVATE);
  } else {
    ShowWindow(window_, SW_SHOWNORMAL);
  }
  visible_ = true;
}

void Window::Hide() {
  if (window_ == nullptr) return;
  ShowWindow(window_, SW_HIDE);
  visible_ = false;
  if (delegate_ != nullptr) delegate_->OnWindowHidden(params_.role);
}

void Window::PostShow() {
  if (window_ != nullptr) PostMessageW(window_, kWmShow, 0, 0);
}

void Window::PostHide() {
  if (window_ != nullptr) PostMessageW(window_, kWmHide, 0, 0);
}

void Window::Focus() {
  if (window_ == nullptr) return;
  if (IsWidgetRole(params_.role)) {
    // The widget is WS_EX_NOACTIVATE; SetForegroundWindow would fail anyway.
    // Revealing it is enough.
    Show();
    return;
  }
  ShowWindow(window_, SW_RESTORE);
  SetForegroundWindow(window_);
}

void Window::Raise() {
  if (window_ == nullptr) return;
  SetWindowPos(window_, HWND_TOP, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void Window::SetTitle(const std::wstring& title) {
  if (window_ != nullptr) SetWindowTextW(window_, title.c_str());
}

// --- Composition -------------------------------------------------------------

void Window::SetAlwaysOnTop(bool on_top) {
  if (window_ == nullptr || !IsWidgetRole(params_.role)) return;
  SetWindowPos(window_, on_top ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void Window::SetBackdrop(Backdrop backdrop) {
  if (window_ == nullptr || !IsWidgetRole(params_.role)) return;
  ApplyBackdrop(window_, backdrop, IsSystemDarkMode());
  RefreshRoundedRegion();
}

void Window::SetWidgetOpacity(int alpha_0_100) {
  if (window_ == nullptr || !IsWidgetRole(params_.role)) return;
  opacity_percent_ = std::clamp(alpha_0_100, 10, 100);
  // Per-window alpha covers the content and the blur together, which is what
  // "the widget sits beside the work rather than on top of it" needs.
  const BYTE alpha = static_cast<BYTE>((opacity_percent_ * 255) / 100);
  SetLayeredWindowAttributes(window_, 0, alpha, LWA_ALPHA);
}

void Window::SetRoundedCorners(bool enabled) {
  rounded_corners_ = enabled;
  RefreshRoundedRegion();
}

void Window::SetPositionLocked(bool locked) {
  // Written from the platform thread and read by HitTest on the UI thread, the
  // same arrangement as rounded_corners_ and opacity_percent_ above. A byte is
  // read whole, and the worst a stale value can do is let one drag behave
  // according to the previous setting for a frame.
  position_locked_ = locked;
}

void Window::PostSetComposeMode(bool active) {
  if (window_ != nullptr) PostMessageW(window_, kWmComposeMode, active ? 1 : 0, 0);
}

// Drops or restores WS_EX_NOACTIVATE, and moves the keyboard with it.
//
// Two details are load-bearing. The previous foreground window is remembered on
// the way in, because an always-on-top widget that takes the caret and never
// gives it back is the single most irritating thing a desktop widget can do -
// and the person who just typed a note is usually in the middle of something
// else. And the style change is applied with SetWindowPos rather than left to
// SetWindowLongPtr alone, because an extended style is not live until the window
// is told to recalculate.
void Window::ApplyComposeMode(bool active) {
  if (window_ == nullptr || compose_mode_ == active) return;
  compose_mode_ = active;

  LONG_PTR ex = GetWindowLongPtrW(window_, GWL_EXSTYLE);
  if (active) {
    compose_previous_focus_ = GetForegroundWindow();
    if (compose_previous_focus_ == window_) compose_previous_focus_ = nullptr;
    ex &= ~static_cast<LONG_PTR>(WS_EX_NOACTIVATE);
    // WS_EX_LAYERED windows need the frame recalculated for the new activation
    // behaviour to take effect, or clicks keep being swallowed as non-client.
    SetWindowLongPtrW(window_, GWL_EXSTYLE, ex);
    SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER);
    SetForegroundWindow(window_);
    SetActiveWindow(window_);
    SetFocus(window_);
    return;
  }

  ex |= static_cast<LONG_PTR>(WS_EX_NOACTIVATE);
  SetWindowLongPtrW(window_, GWL_EXSTYLE, ex);
  SetWindowPos(window_, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);

  // Hand the keyboard back. Only if it is still ours: if the user has already
  // alt-tabbed somewhere deliberate, yanking them back would be worse than
  // leaving them where they chose to be.
  HWND previous = compose_previous_focus_;
  compose_previous_focus_ = nullptr;
  if (previous != nullptr && IsWindow(previous) &&
      GetForegroundWindow() == window_) {
    SetForegroundWindow(previous);
  }
}

// --- Move and resize loops ---------------------------------------------------

namespace {
// The same floor SetBounds already enforces, restated here because the loop
// clamps before it gets there: clamping late would let a drag reach zero and
// bounce back, which reads as the widget fighting the pointer.
constexpr int kMinWidgetW = kMinWidgetWidth;
constexpr int kMinWidgetH = kMinWidgetHeight;

// Not a screen limit, just a backstop so a single fast flick cannot leave a
// widget wider than any display could ever show.
constexpr int kMaxWidgetW = 4000;
constexpr int kMaxWidgetH = 4000;
}  // namespace

void Window::PostBeginMove(double anchor_x, double anchor_y) {
  pending_anchor_valid_ = true;
  pending_anchor_x_ = anchor_x;
  pending_anchor_y_ = anchor_y;
  if (window_ != nullptr) PostMessageW(window_, kWmBeginMove, 0, 0);
}

void Window::PostBeginResize(int edge, double anchor_x, double anchor_y) {
  pending_anchor_valid_ = true;
  pending_anchor_x_ = anchor_x;
  pending_anchor_y_ = anchor_y;
  if (window_ != nullptr) PostMessageW(window_, kWmBeginResize, (WPARAM)edge, 0);
}

// Where the pointer actually was when the gesture started.
//
// Dart supplies the anchor because the runner cannot recover it: the drag is
// only recognised once the pointer has already travelled past the threshold, so
// anchoring on the cursor here would silently discard everything moved in that
// first hop. That is about 10% of a short drag and more of a slow one. Dart's
// anchor is view-relative and in logical pixels, so it is converted against the
// window origin and this window's own DPI scale.
void Window::SeedLoopAnchor() {
  RECT r = bounds();
  const double scale = ScaleForWindow(window_, 96) / 96.0;
  loop_start_cursor_.x =
      r.left + static_cast<LONG>(std::lround(pending_anchor_x_ * scale));
  loop_start_cursor_.y =
      r.top + static_cast<LONG>(std::lround(pending_anchor_y_ * scale));
  loop_start_bounds_ = bounds();
  pending_anchor_valid_ = false;
}

void Window::EndLoop() {
  move_loop_ = false;
  resize_loop_ = false;
  loop_edge_ = 0;
  if (window_ != nullptr) ReleaseCapture();
  // A monitor may have appeared or vanished while the pointer was down.
  ClampToReachableScreen();
  RefreshRoundedRegion();
  NotifyGeometry();
}

void Window::RefreshRoundedRegion() {
  if (window_ == nullptr) return;
  if (rounded_corners_ && IsWidgetRole(params_.role)) {
    ApplyRoundedRegion(window_, ScaleForWindow(window_, corner_radius_));
  } else {
    SetWindowRgn(window_, nullptr, TRUE);
  }
}

// --- Geometry ----------------------------------------------------------------

RECT Window::bounds() const {
  RECT r{};
  if (window_ != nullptr) GetWindowRect(window_, &r);
  return r;
}

void Window::ClampToReachableScreen() {
  if (window_ == nullptr) return;
  const auto monitors = EnumerateMonitors();
  if (monitors.empty()) return;

  RECT current{};
  GetWindowRect(window_, &current);
  if (RectIsReachable(current, monitors)) return;

  // The widget was left somewhere that no longer exists, which is what happens
  // when the monitor holding it gets unplugged. Move it onto the nearest
  // remaining screen, docked to the edge it was nearest to, rather than
  // leaving it where it can never be clicked again.
  const MonitorInfo* target = MonitorForWindow(window_, monitors);
  if (target == nullptr) return;

  const int width = current.right - current.left;
  const int height = current.bottom - current.top;
  const int margin = ScaleForWindow(window_, edge_dock_margin_);

  int left = target->bounds.left + margin;
  int top = target->bounds.top + margin;

  // Keep the original side preference: if it was flush right, put it back on
  // the right of whatever screen it lands on.
  const int right_gap = target->bounds.right - current.right;
  const int left_gap = current.left - target->bounds.left;
  if (std::abs(right_gap) < std::abs(left_gap)) {
    left = target->bounds.right - width - margin;
  }
  const int bottom_gap = target->bounds.bottom - current.bottom;
  const int top_gap = current.top - target->bounds.top;
  if (std::abs(bottom_gap) < std::abs(top_gap)) {
    top = target->bounds.bottom - height - margin;
  }

  RECT restored{left, top, left + width, top + height};
  SetWindowPos(window_, nullptr, restored.left, restored.top, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void Window::SetBounds(const RECT& bounds) {
  if (window_ == nullptr) return;
  // LONG is long and ScaleForWindow returns int, so std::max needs both sides
  // spelled as the same type rather than silently narrowing.
  const int width = std::max(static_cast<int>(bounds.right - bounds.left),
                             ScaleForWindow(window_, kMinWidgetWidth));
  const int height = std::max(static_cast<int>(bounds.bottom - bounds.top),
                              ScaleForWindow(window_, kMinWidgetHeight));
  SetWindowPos(window_, nullptr, bounds.left, bounds.top, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE);
  RefreshRoundedRegion();
}

void Window::PostSetBounds(const RECT& bounds) {
  if (window_ == nullptr) return;
  // The RECT is copied into the message payload so Dart never has to know it
  // was talking to a message queue rather than a function call.
  auto* payload = new RECT(bounds);
  PostMessageW(window_, kWmSetBounds, 0, reinterpret_cast<LPARAM>(payload));
}

void Window::NotifyGeometry() {
  if (delegate_ != nullptr) {
    delegate_->OnWindowGeometryChanged(params_.role, bounds());
  }
}

// --- Hit testing and dragging ------------------------------------------------

LRESULT Window::HitTest(POINT screen_pt) const {
  // Everything on the widget is HTCLIENT, including the whole body, and this is
  // load-bearing rather than a simplification.
  //
  // The obvious way to make a frameless window draggable is to answer
  // HTCAPTION for its body and let Windows run the move loop. That cannot work
  // here, for two independent reasons:
  //
  //   * The Flutter view covers the client area, so the system hit-tests the
  //     child and never consults this. Reporting HTCAPTION was dead code: the
  //     widget could not be dragged, and asking this handler directly returned a
  //     value that never influenced a real click.
  //   * Even when it does reach the window, DefWindowProc only starts the move
  //     or size loop for a window with WS_CAPTION or WS_THICKFRAME. This is a
  //     borderless WS_POPUP with neither, so the loop never began.
  //
  // And reporting HTCAPTION over the body would be actively wrong anyway,
  // because the same pixels have to deliver taps: the widget's cards are
  // selectable and a double-click opens the editor. Windows hit-tests exactly
  // one target per pixel, so caption-or-taps is a choice and taps are the one
  // worth making.
  //
  // Dragging and resizing are therefore decided in Dart, from the pointer the
  // widget already receives, and applied through widget.setGeometry. That also
  // puts both gestures next to the position lock that already governs them.
  (void)screen_pt;
  return HTCLIENT;
}

// --- Window procedure --------------------------------------------------------

LRESULT CALLBACK Window::WndProc(HWND window, UINT message, WPARAM wparam,
                                 LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    auto* self = static_cast<Window*>(create->lpCreateParams);
    if (self != nullptr) self->window_ = window;
  } else if (Window* self = FromHandle(window)) {
    return self->HandleMessage(window, message, wparam, lparam);
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

Window* Window::FromHandle(HWND window) noexcept {
  return reinterpret_cast<Window*>(GetWindowLongPtrW(window, GWLP_USERDATA));
}

LRESULT Window::HandleMessage(HWND window, UINT message, WPARAM wparam,
                              LPARAM lparam) noexcept {
  // Give the Flutter engine first refusal on every message: this is what keeps
  // text input, IME and accessibility working in the editor.
  if (controller_) {
    std::optional<LRESULT> handled =
        controller_->HandleTopLevelWindowProc(window, message, wparam, lparam);
    if (handled.has_value()) return *handled;
  }

  const bool widget = IsWidgetRole(params_.role);

  switch (message) {
    case WM_ACTIVATE: {
      // Editor only. A topmost window is above *every* window, so once the
      // widget is topmost there is no Z-order position that is "above other
      // apps but below the editor" - the widget simply covers it. The host has
      // to be told when the editor is the window someone is working in, so it
      // can take the widget out of the topmost band while that lasts.
      if (!widget && delegate_ != nullptr) {
        delegate_->OnWindowActivationChanged(
            params_.role, LOWORD(wparam) != WA_INACTIVE);
      }
      break;
    }

    case WM_NCHITTEST: {
      if (!widget) break;
      return HitTest(POINT{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)});
    }

    case WM_MOUSEACTIVATE: {
      if (widget) {
        // Belt and braces with WS_EX_NOACTIVATE: never take focus from the app
        // the user is typing in.
        //
        // The exception is compose mode. This handler would otherwise keep
        // refusing activation at the exact moment the widget is meant to be a
        // text field, which is the same bug as not dropping WS_EX_NOACTIVATE at
        // all, one layer down and harder to see.
        if (compose_mode_) break;
        return MA_NOACTIVATE;
      }
      break;
    }

    case WM_NCLBUTTONDOWN: {
      // Nothing to do. The widget is HTCLIENT everywhere, so a body drag never
      // arrives here as a non-client message; only the system frame, which a
      // borderless popup does not have, would. Left in place so an unexpected
      // hit falls through to the default handler rather than being swallowed.
      break;
    }

    case kWmComposeMode: {
      ApplyComposeMode(wparam != 0);
      return 0;
    }

    case kWmBeginMove: {
      if (!widget || window_ == nullptr || position_locked_) break;
      if (pending_anchor_valid_) {
        SeedLoopAnchor();
      } else {
        GetCursorPos(&loop_start_cursor_);
        loop_start_bounds_ = bounds();
      }
      move_loop_ = true;
      resize_loop_ = false;
      loop_edge_ = 0;
      SetCapture(window_);
      return 0;
    }

    case kWmBeginResize: {
      if (!widget || window_ == nullptr) break;
      if (pending_anchor_valid_) {
        SeedLoopAnchor();
      } else {
        GetCursorPos(&loop_start_cursor_);
        loop_start_bounds_ = bounds();
      }
      move_loop_ = false;
      resize_loop_ = true;
      loop_edge_ = static_cast<int>(wparam);
      SetCapture(window_);
      return 0;
    }

    case WM_MOUSEMOVE: {
      if (!move_loop_ && !resize_loop_) break;
      // No "is the button still down" check here. The window holds the capture,
      // so WM_LBUTTONUP is addressed to this proc and cannot be stolen, and the
      // obvious way to ask anyway - GetAsyncKeyState(VK_LBUTTON) - does not
      // report injected mouse buttons, so it ends every synthetic drag on the
      // first move. That is a harness case, but the lesson generalises: a guard
      // that can end a real drag by mistake is worse than the leak it prevents.
      POINT now{};
      GetCursorPos(&now);
      const int dx = now.x - loop_start_cursor_.x;
      const int dy = now.y - loop_start_cursor_.y;
      RECT b = loop_start_bounds_;

      if (move_loop_) {
        b.left += dx;
        b.top += dy;
        b.right += dx;
        b.bottom += dy;
      } else {
        const bool left = loop_edge_ == kEdgeLeft || loop_edge_ == kEdgeTopLeft ||
                          loop_edge_ == kEdgeBottomLeft;
        const bool right = loop_edge_ == kEdgeRight || loop_edge_ == kEdgeTopRight ||
                           loop_edge_ == kEdgeBottomRight;
        const bool top = loop_edge_ == kEdgeTop || loop_edge_ == kEdgeTopLeft ||
                         loop_edge_ == kEdgeTopRight;
        const bool bottom = loop_edge_ == kEdgeBottom ||
                            loop_edge_ == kEdgeBottomLeft ||
                            loop_edge_ == kEdgeBottomRight;
        if (left) b.left += dx;
        if (right) b.right += dx;
        if (top) b.top += dy;
        if (bottom) b.bottom += dy;

        // Clamped, so a fast flick cannot drag the widget off the screen or
        // collapse it to a sliver nobody can find again.
        int w = b.right - b.left;
        int h = b.bottom - b.top;
        w = std::clamp(w, kMinWidgetW, kMaxWidgetW);
        h = std::clamp(h, kMinWidgetH, kMaxWidgetH);
        // Re-derive the origin so a drag past a limit pushes the far edge out
        // rather than sliding the near one through it.
        if (left) b.left = b.right - w;
        if (top) b.top = b.bottom - h;
        if (right) b.right = b.left + w;
        if (bottom) b.bottom = b.top + h;
      }

      SetWindowPos(window_, nullptr, b.left, b.top, b.right - b.left,
                   b.bottom - b.top, SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }

    case WM_LBUTTONUP:
    case WM_CAPTURECHANGED:
    case WM_CANCELMODE: {
      if (!move_loop_ && !resize_loop_) break;
      EndLoop();
      return 0;
    }

    case WM_ERASEBKGND:
      // Flutter covers the client area; letting Windows erase it first would
      // show as flicker during resize and window moves.
      return 1;

    case WM_SIZE: {
      if (child_content_ != nullptr) {
        RECT client{};
        GetClientRect(window, &client);
        MoveWindow(child_content_, 0, 0, client.right - client.left,
                   client.bottom - client.top, TRUE);
      }
      if (widget) RefreshRoundedRegion();
      NotifyGeometry();
      break;
    }

    case WM_MOVE: {
      NotifyGeometry();
      break;
    }

    case WM_DPICHANGED: {
      // Follow the suggested rectangle so the widget keeps its physical size
      // when it is dragged between monitors with different scaling.
      auto* suggested = reinterpret_cast<RECT*>(lparam);
      SetWindowPos(window, nullptr, suggested->left, suggested->top,
                   suggested->right - suggested->left,
                   suggested->bottom - suggested->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      RefreshRoundedRegion();
      NotifyGeometry();
      break;
    }

    case WM_CLOSE: {
      // Closing a window never ends the app. That is the entire point.
      Hide();
      if (delegate_ != nullptr) delegate_->OnWindowCloseRequested(params_.role);
      return 0;
    }

    case WM_DESTROY: {
      window_ = nullptr;
      OnDestroy();
      return 0;
    }

    case WM_DWMCOLORIZATIONCOLORCHANGED: {
      if (widget) {
        SetBackdrop(AcrylicSupported() ? Backdrop::kAcrylic : Backdrop::kPlain);
      }
      break;
    }

    case WM_DISPLAYCHANGE:
    case WM_DEVICECHANGE: {
      // A monitor was added, removed or rearranged. Re-clamp so the widget
      // never ends up off-screen after docking or undocking a laptop.
      ClampToReachableScreen();
      break;
    }

    case WM_SETTINGCHANGE: {
      if (widget) RefreshRoundedRegion();
      break;
    }

    // --- Host messages ---
    case kWmShow:
      Show();
      return 0;
    case kWmHide:
      Hide();
      return 0;
    case kWmToggleVisible:
      if (visible_) {
        Hide();
      } else {
        Show();
      }
      return 0;
    case kWmSetBounds: {
      std::unique_ptr<RECT> payload(reinterpret_cast<RECT*>(lparam));
      if (payload) SetBounds(*payload);
      return 0;
    }
    case kWmGeometryChanged: {
      NotifyGeometry();
      return 0;
    }

    case kWmActivateInstance: {
      // A second launch found us. Raise what the person was trying to reach
      // instead of stacking a duplicate widget on top of this one. WPARAM says
      // whether they were reaching for the editor or just for the widget.
      Show();
      if (delegate_ != nullptr) delegate_->OnInstanceActivated(wparam != 0);
      return 0;
    }

    default:
      break;
  }

  return DefWindowProcW(window, message, wparam, lparam);
}

}  // namespace winnotes