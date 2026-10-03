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
  if (!IsWidgetRole(params_.role) || window_ == nullptr) {
    return HTCLIENT;
  }
  RECT r{};
  GetWindowRect(window_, &r);
  const int x = screen_pt.x - r.left;
  const int y = screen_pt.y - r.top;
  const int w = r.right - r.left;
  const int h = r.bottom - r.top;

  // A grab band along the edges for resizing. Everything inside it stays
  // clickable so notes remain selectable right up to the border.
  const int band = ScaleForWindow(window_, 8);

  const bool left = x < band;
  const bool right = x >= w - band;
  const bool top = y < band;
  const bool bottom = y >= h - band;

  if (top && left) return HTTOPLEFT;
  if (top && right) return HTTOPRIGHT;
  if (bottom && left) return HTBOTTOMLEFT;
  if (bottom && right) return HTBOTTOMRIGHT;
  if (left) return HTLEFT;
  if (right) return HTRIGHT;
  if (top) return HTTOP;
  if (bottom) return HTBOTTOM;

  // Drag the card by its body. HCAPTION lets Windows drive the drag loop,
  // including the snap-to-edge behaviour, without us reimplementing it.
  //
  // Locked, the body reports HTCLIENT instead so the pointer reaches Flutter and
  // a drag simply moves nothing. Resizing stays available either way.
  if (position_locked_) return HTCLIENT;
  return HTCAPTION;
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
    case WM_NCHITTEST: {
      if (!widget) break;
      return HitTest(POINT{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)});
    }

    case WM_MOUSEACTIVATE: {
      if (widget) {
        // Belt and braces with WS_EX_NOACTIVATE: never take focus from the app
        // the user is typing in.
        return MA_NOACTIVATE;
      }
      break;
    }

    case WM_NCLBUTTONDOWN: {
      if (!widget) break;
      const int hit = LOWORD(lparam);
      const bool resizing = hit == HTLEFT || hit == HTRIGHT || hit == HTTOP ||
                            hit == HTBOTTOM || hit == HTTOPLEFT ||
                            hit == HTTOPRIGHT || hit == HTBOTTOMLEFT ||
                            hit == HTBOTTOMRIGHT;
      const bool dragging = hit == HTCAPTION;
      if (!resizing && !dragging) break;

      // Let Windows drive the loop. It handles capture, cursor changes,
      // double-click maximise and the edge-snap behaviour that a hand-rolled
      // move loop always gets subtly wrong.
      resizing_ = resizing;
      dragging_ = dragging;
      drag_start_screen_ = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      drag_start_bounds_ = bounds();
      LRESULT result = DefWindowProcW(window, message, wparam, lparam);
      resizing_ = false;
      dragging_ = false;

      // A monitor may have appeared or vanished while the mouse was down.
      ClampToReachableScreen();
      RefreshRoundedRegion();
      NotifyGeometry();
      return result;
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