#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kSingleInstanceMutex[] = L"Local\\MiniGameCenter.SingleInstance";
constexpr wchar_t kWindowTitle[] = L"minigameapp";

bool ForwardToExistingWindow(const std::wstring& deep_link) {
  HWND window = nullptr;
  for (int attempt = 0; attempt < 20 && !window; ++attempt) {
    window = FindWindow(nullptr, kWindowTitle);
    if (!window) {
      Sleep(100);
    }
  }
  if (!window) {
    return false;
  }
  COPYDATASTRUCT data{};
  data.dwData = 1;
  data.cbData = static_cast<DWORD>((deep_link.size() + 1) * sizeof(wchar_t));
  data.lpData = const_cast<wchar_t*>(deep_link.c_str());
  DWORD_PTR result = 0;
  SendMessageTimeout(window, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data),
                     SMTO_ABORTIFHUNG, 3000, &result);
  ShowWindow(window, SW_RESTORE);
  SetForegroundWindow(window);
  return true;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                       _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  HANDLE instance_mutex = CreateMutex(nullptr, TRUE, kSingleInstanceMutex);
  if (!instance_mutex) {
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    ForwardToExistingWindow(command_line ? command_line : L"");
    CloseHandle(instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"minigameapp", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ReleaseMutex(instance_mutex);
  CloseHandle(instance_mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
