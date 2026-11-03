#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kMenuOpen = 1;
constexpr UINT kMenuQuit = 2;

void ShowAndForeground(HWND hwnd) {
  ShowWindow(hwnd, SW_SHOW);
  ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "clipps/clipboard",
          &flutter::StandardMethodCodec::GetInstance());
  AddClipboardFormatListener(GetHandle());

  tray_icon_.cbSize = sizeof(tray_icon_);
  tray_icon_.hWnd = GetHandle();
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayMessage;
  tray_icon_.hIcon = LoadIcon(GetModuleHandle(nullptr),
                              MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_.szTip, L"Clipps — clipboard history");
  Shell_NotifyIcon(NIM_ADD, &tray_icon_);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  Shell_NotifyIcon(NIM_DELETE, &tray_icon_);
  clipboard_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Win32Window clears its handle before OnDestroy(), so unregister here.
  if (message == WM_DESTROY) {
    RemoveClipboardFormatListener(hwnd);
  }

  if (message == WM_CLOSE && !quitting_) {
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }

  if (message == kTrayMessage) {
    if (LOWORD(lparam) == WM_LBUTTONUP) {
      ShowAndForeground(hwnd);
    } else if (LOWORD(lparam) == WM_RBUTTONUP) {
      HMENU menu = CreatePopupMenu();
      AppendMenuW(menu, MF_STRING, kMenuOpen, L"Open");
      AppendMenuW(menu, MF_STRING, kMenuQuit, L"Quit");
      POINT pt;
      GetCursorPos(&pt);
      // Without this the menu does not dismiss when clicking elsewhere.
      SetForegroundWindow(hwnd);
      UINT cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.x,
                                pt.y, 0, hwnd, nullptr);
      DestroyMenu(menu);
      if (cmd == kMenuOpen) {
        ShowAndForeground(hwnd);
      } else if (cmd == kMenuQuit) {
        quitting_ = true;
        PostMessage(hwnd, WM_CLOSE, 0, 0);
      }
    }
    return 0;
  }

  if (message == WM_CLIPBOARDUPDATE) {
    if (clipboard_channel_) {
      clipboard_channel_->InvokeMethod("clipboardChanged", nullptr);
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
