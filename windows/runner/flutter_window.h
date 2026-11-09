#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <shellapi.h>

#include <memory>

#include "clipboard_source.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // With |start_hidden| the window stays in the tray until the user opens it.
  FlutterWindow(const flutter::DartProject& project, bool start_hidden);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Tells Dart when the OS clipboard changes (WM_CLIPBOARDUPDATE).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      clipboard_channel_;

  // Tray icon; hWnd is kept here because GetHandle() is null in OnDestroy().
  NOTIFYICONDATAW tray_icon_ = {};

  // Broadcast when Explorer restarts; the tray icon must be re-added.
  UINT taskbar_created_message_;

  // Launched with --hidden (start at login): skip showing the first frame.
  bool start_hidden_;

  // False when RegisterHotKey failed (another app owns the shortcut).
  bool hotkey_registered_ = false;

  // Mirrors the Dart pause switch; shown in the tray tooltip and menu.
  bool capture_paused_ = false;

  // Set by the tray "Quit" item so WM_CLOSE destroys instead of hiding.
  bool quitting_ = false;

  // Privacy-check retries for the current clipboard change.
  int clipboard_attempts_ = 0;

  // Source of the latest clipboard update, sent once the privacy check passes.
  ClipboardSource pending_source_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
