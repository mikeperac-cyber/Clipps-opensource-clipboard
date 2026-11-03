#ifndef RUNNER_CLIPBOARD_SOURCE_H_
#define RUNNER_CLIPBOARD_SOURCE_H_

#include <string>

// Where the current clipboard content came from. Empty means unknown.
struct ClipboardSource {
  std::wstring app;
  std::wstring title;
};

// Looks up the clipboard owner's app name and, if it is also the foreground
// process, the foreground window title. Never fails; unknown fields are empty.
ClipboardSource GetClipboardSource();

#endif  // RUNNER_CLIPBOARD_SOURCE_H_
