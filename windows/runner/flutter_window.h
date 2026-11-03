#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <shellapi.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
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

  // Set by the tray "Quit" item so WM_CLOSE destroys instead of hiding.
  bool quitting_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
