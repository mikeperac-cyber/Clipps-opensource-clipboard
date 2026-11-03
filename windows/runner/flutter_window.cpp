#include "flutter_window.h"

#include <climits>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kMenuOpen = 1;
constexpr UINT kMenuQuit = 2;
constexpr UINT_PTR kClipboardTimer = 1;
constexpr UINT kClipboardDelayMs = 50;
constexpr int kClipboardMaxAttempts = 10;
constexpr int kHotkeyId = 1;

enum class ClipboardPrivacy { kPublic, kPrivate, kBusy };

// Unlike utils.h's Utf8FromUtf16, converts the full length (no 32767 cap) and
// replaces lone surrogates with U+FFFD instead of failing.
std::optional<std::string> Utf8FromWide(const std::wstring& wide) {
  if (wide.empty()) {
    return std::string();
  }
  if (wide.size() > static_cast<size_t>(INT_MAX)) {
    return std::nullopt;
  }
  int wide_length = static_cast<int>(wide.size());
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(), wide_length,
                                 nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    return std::nullopt;
  }
  std::string utf8(static_cast<size_t>(size), '\0');
  if (WideCharToMultiByte(CP_UTF8, 0, wide.data(), wide_length, utf8.data(),
                          size, nullptr, nullptr) != size) {
    return std::nullopt;
  }
  return utf8;
}

void ShowAndForeground(HWND hwnd) {
  ShowWindow(hwnd, SW_SHOW);
  ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
}

// Password managers set these formats so clipboard history tools skip secrets.
// The verdict and the text are taken in one clipboard session so they describe
// the same contents.
ClipboardPrivacy ReadClipboard(HWND hwnd, std::wstring* text, bool* has_text) {
  static const UINT kExclude = RegisterClipboardFormatW(
      L"ExcludeClipboardContentFromMonitorProcessing");
  static const UINT kViewerIgnore =
      RegisterClipboardFormatW(L"Clipboard Viewer Ignore");
  static const UINT kCanInclude =
      RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
  // The writer often still holds the clipboard right after the update.
  if (!OpenClipboard(hwnd)) {
    return ClipboardPrivacy::kBusy;
  }
  ClipboardPrivacy result = ClipboardPrivacy::kPublic;
  if (IsClipboardFormatAvailable(kExclude) ||
      IsClipboardFormatAvailable(kViewerIgnore)) {
    result = ClipboardPrivacy::kPrivate;
  } else if (IsClipboardFormatAvailable(kCanInclude)) {
    HANDLE data = GetClipboardData(kCanInclude);
    if (data) {
      const DWORD* value = static_cast<const DWORD*>(GlobalLock(data));
      if (value) {
        if (GlobalSize(data) >= sizeof(DWORD) && *value == 0) {
          result = ClipboardPrivacy::kPrivate;
        }
        GlobalUnlock(data);
      }
    }
  }
  if (result == ClipboardPrivacy::kPublic) {
    HANDLE data = GetClipboardData(CF_UNICODETEXT);
    if (data) {
      const wchar_t* value = static_cast<const wchar_t*>(GlobalLock(data));
      if (value) {
        size_t max_chars = GlobalSize(data) / sizeof(wchar_t);
        size_t length = wcsnlen(value, max_chars);
        // Not NUL-terminated within the block: treat as no text.
        if (length < max_chars) {
          text->assign(value, length);
          *has_text = true;
        }
        GlobalUnlock(data);
      }
    }
  }
  CloseClipboard();
  return result;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden)
    : project_(project),
      start_hidden_(start_hidden),
      taskbar_created_message_(RegisterWindowMessageW(L"TaskbarCreated")) {}

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
  hotkey_registered_ = RegisterHotKey(GetHandle(), kHotkeyId,
                                      MOD_CONTROL | MOD_ALT | MOD_NOREPEAT,
                                      VK_OEM_PERIOD) != 0;

  tray_icon_.cbSize = sizeof(tray_icon_);
  tray_icon_.hWnd = GetHandle();
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayMessage;
  tray_icon_.hIcon = LoadIcon(GetModuleHandle(nullptr),
                              MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_.szTip, L"Clipps \u2014 clipboard history");
  Shell_NotifyIcon(NIM_ADD, &tray_icon_);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      this->Show();
    }
    if (!hotkey_registered_ && clipboard_channel_) {
      clipboard_channel_->InvokeMethod("hotkeyUnavailable", nullptr);
    }
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
    UnregisterHotKey(hwnd, kHotkeyId);
  }

  if (message == WM_HOTKEY && wparam == kHotkeyId) {
    if (IsWindowVisible(hwnd) && GetForegroundWindow() == hwnd) {
      ShowWindow(hwnd, SW_HIDE);
    } else {
      ShowAndForeground(hwnd);
      if (clipboard_channel_) {
        clipboard_channel_->InvokeMethod("focusSearch", nullptr);
      }
    }
    return 0;
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
      PostMessage(hwnd, WM_NULL, 0, 0);
      if (cmd == kMenuOpen) {
        ShowAndForeground(hwnd);
      } else if (cmd == kMenuQuit) {
        quitting_ = true;
        PostMessage(hwnd, WM_CLOSE, 0, 0);
      }
    }
    return 0;
  }

  if (message == taskbar_created_message_) {
    // Explorer restarted and dropped all tray icons.
    Shell_NotifyIcon(NIM_ADD, &tray_icon_);
    return 0;
  }

  if (message == WM_CLIPBOARDUPDATE) {
    // Wait for the writer to release the clipboard; also coalesces bursts.
    clipboard_attempts_ = 0;
    // Must be read now; the owner and foreground window change quickly.
    pending_source_ = GetClipboardSource();
    SetTimer(hwnd, kClipboardTimer, kClipboardDelayMs, nullptr);
    return 0;
  }

  if (message == WM_TIMER && wparam == kClipboardTimer) {
    std::wstring text;
    bool has_text = false;
    ClipboardPrivacy privacy = ReadClipboard(hwnd, &text, &has_text);
    if (privacy == ClipboardPrivacy::kBusy &&
        ++clipboard_attempts_ < kClipboardMaxAttempts) {
      return 0;
    }
    KillTimer(hwnd, kClipboardTimer);
    // Still busy after retries: skip it rather than risk storing a secret.
    if (privacy == ClipboardPrivacy::kPublic && clipboard_channel_) {
      auto field = [](const std::wstring& value) {
        std::optional<std::string> utf8 = Utf8FromWide(value);
        return value.empty() || !utf8 ? flutter::EncodableValue()
                                      : flutter::EncodableValue(*utf8);
      };
      std::optional<std::string> utf8_text =
          has_text ? Utf8FromWide(text) : std::nullopt;
      flutter::EncodableMap source{
          {flutter::EncodableValue("sourceApp"), field(pending_source_.app)},
          {flutter::EncodableValue("sourceTitle"),
           field(pending_source_.title)},
          {flutter::EncodableValue("text"),
           utf8_text ? flutter::EncodableValue(*utf8_text)
                     : flutter::EncodableValue()}};
      clipboard_channel_->InvokeMethod(
          "clipboardChanged",
          std::make_unique<flutter::EncodableValue>(std::move(source)));
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
