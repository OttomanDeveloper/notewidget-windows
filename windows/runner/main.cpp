#include <flutter/dart_project.h>
#include <windows.h>

#include <string>
#include <vector>

#include "utils.h"
#include "win_notes_host.h"
#include "win_notes_platform.h"

namespace {

// Reads the launch flags out of the raw command line.
//
// The autostart entry writes "win_notes.exe" --widget. Without that flag every
// login would open the full editor, which is not what anyone wants at 9am, so
// this is the difference between the widget being a fixture and being a
// nuisance.
winnotes::LaunchMode ResolveLaunchMode() {
  int count = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &count);
  if (argv == nullptr) return winnotes::LaunchMode::kNormal;

  winnotes::LaunchMode mode = winnotes::LaunchMode::kNormal;
  for (int i = 1; i < count; ++i) {
    if (wcscmp(argv[i], L"--widget") == 0) {
      mode = winnotes::LaunchMode::kWidgetOnly;
      break;
    }
  }
  LocalFree(argv);
  return mode;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  // Attach to the console flutter run started, so log output still lands in the
  // terminal during development.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // COM is needed by the tray icon and the common file dialogs.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  winnotes::LaunchMode mode = ResolveLaunchMode();

  winnotes::Host host(mode);
  if (!host.Startup()) {
    // Either another instance already owns the mutex, in which case it has
    // been told to raise itself, or a surface failed to come up. Neither is
    // worth a dialog: the second launch has already done its job.
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  ::MSG msg;
  bool running = true;
  while (running) {
    // A zero Msg means no work is pending, so wait indefinitely instead of
    // spinning the CPU while the app sits idle on the desktop.
    const BOOL result = ::GetMessageW(&msg, nullptr, 0, 0);
    if (result == 0) {
      running = false;
    } else if (result == -1) {
      running = false;
    } else {
      ::TranslateMessage(&msg);
      ::DispatchMessageW(&msg);
    }
  }

  host.Shutdown();
  ::CoUninitialize();
  return EXIT_SUCCESS;
}