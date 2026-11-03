#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const bool hidden = wcsstr(command_line, L"--hidden") != nullptr;
  // Single instance: surface the existing window instead of starting another.
  ::CreateMutexW(nullptr, TRUE, L"Local\\clipps_single_instance");
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"clipps");
    if (existing && !hidden) {
      ::ShowWindow(existing, SW_SHOW);
      ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
    return EXIT_SUCCESS;
  }

#ifdef CLIPPS_RELEASE
  // Start at login; rewritten every launch so the path follows the exe.
  {
    wchar_t exe[MAX_PATH];
    DWORD len = ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
    if (len > 0 && len < MAX_PATH) {
      std::wstring value = L"\"" + std::wstring(exe) + L"\" --hidden";
      ::RegSetKeyValueW(
          HKEY_CURRENT_USER,
          L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
          L"Clipps", REG_SZ, value.c_str(),
          static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
    }
  }
#endif

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, hidden);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"clipps", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
