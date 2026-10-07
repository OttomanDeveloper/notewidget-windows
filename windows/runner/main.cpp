#include <flutter/dart_project.h>
#include <windows.h>

#include <cstdio>
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

// Appends an unhandled native fault to crash.log, so one file describes one run
// whether the failure was in Dart or in the runner.
//
// The console below only exists for a debugger, so a build launched at login has
// nowhere to print. There is no telemetry and no upload (PROJECT.md), so this file
// is the only way a native crash is ever seen.
//
// UTF-8, because the Dart side writes UTF-8 into the same file. A narrow `_snprintf`
// into a stack buffer, not a formatted wide string: the payload is digits and
// hex, so there is nothing here that needs encoding, and writing wchar_t would
// interleave NULs into a file that is read as bytes.
//
// Returns EXCEPTION_EXECUTE_HANDLER so the process still dies: this records the
// fault, it does not make continuing safe.
LONG WINAPI RecordUnhandledException(EXCEPTION_POINTERS* info) {
  if (info != nullptr && info->ExceptionRecord != nullptr) {
    const EXCEPTION_RECORD* record = info->ExceptionRecord;
    char buffer[384];
    ULONG_PTR fault = 0;
    if (record->NumberParameters > 1) fault = record->ExceptionInformation[1];
    const int written = _snprintf_s(
        buffer, _TRUNCATE,
        "{\n  \"source\": \"win32\",\n  \"code\": %lu,\n"
        "  \"address\": \"%p\",\n  \"faultAddress\": \"%p\"\n}\n",
        static_cast<unsigned long>(record->ExceptionCode),
        static_cast<void*>(record->ExceptionAddress),
        reinterpret_cast<void*>(fault));
    // The same directory the runner hands Dart, so both halves land in one file.
    // Empty when the folder could not be resolved; there is nowhere to write.
    const std::wstring directory = winnotes::AppDataDirectory();
    if (written > 0 && !directory.empty()) {
      const std::wstring path = directory + L"\\crash.log";
      HANDLE file = ::CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                                  nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (file != INVALID_HANDLE_VALUE) {
        DWORD bytes = 0;
        ::WriteFile(file, buffer, static_cast<DWORD>(written), &bytes, nullptr);
        ::CloseHandle(file);
      }
    }
  }
  return EXCEPTION_EXECUTE_HANDLER;
}

// Where `--diagnose <path>` was told to write, or an empty string.
//
// Parsed here rather than in Dart because the process command line never
// reaches it: the runner sets `dart_entrypoint_arguments` itself (`--surface`,
// `--launch`), so `main(List<String> args)` sees those two and not the argv the
// person actually typed. Passing it through `bootstrap` is the same route the
// existing flags take, and it adds no platform method.
std::wstring ResolveDiagnosePath() {
  int count = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &count);
  if (argv == nullptr) return std::wstring();
  std::wstring target;
  for (int i = 1; i + 1 < count; ++i) {
    if (wcscmp(argv[i], L"--diagnose") == 0) {
      target = argv[i + 1];
      break;
    }
  }
  LocalFree(argv);
  return target;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  // Attach to the console flutter run started, so log output still lands in the
  // terminal during development.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Installed before anything else can fault, and independent of the console
  // above on purpose - see the function note.
  ::SetUnhandledExceptionFilter(RecordUnhandledException);

  // COM is needed by the tray icon and the common file dialogs.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  winnotes::LaunchMode mode = ResolveLaunchMode();

  winnotes::Host host(mode, ResolveDiagnosePath());
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