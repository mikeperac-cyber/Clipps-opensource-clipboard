#include "clipboard_source.h"

#include <windows.h>

#include <vector>

namespace {
// Friendly name from the exe's version resource, else its file name.
std::wstring AppNameFromPath(const std::wstring& path) {
  std::wstring name = path.substr(path.find_last_of(L'\\') + 1);
  DWORD ignored = 0;
  DWORD size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
  if (size == 0) {
    return name;
  }
  std::vector<BYTE> data(size);
  if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
    return name;
  }
  struct Translation {
    WORD language;
    WORD codepage;
  }* translation = nullptr;
  UINT length = 0;
  if (!VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                      reinterpret_cast<void**>(&translation), &length) ||
      length < sizeof(Translation)) {
    return name;
  }
  wchar_t query[64];
  swprintf_s(query, L"\\StringFileInfo\\%04x%04x\\FileDescription",
             translation->language, translation->codepage);
  const wchar_t* description = nullptr;
  if (VerQueryValueW(data.data(), query,
                     reinterpret_cast<void**>(const_cast<wchar_t**>(
                         &description)),
                     &length) &&
      description && description[0] != L'\0') {
    return description;
  }
  return name;
}

std::wstring ImagePath(DWORD pid) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) {
    return L"";
  }
  wchar_t buffer[MAX_PATH * 2];
  DWORD size = static_cast<DWORD>(sizeof(buffer) / sizeof(buffer[0]));
  std::wstring path;
  if (QueryFullProcessImageNameW(process, 0, buffer, &size)) {
    path.assign(buffer, size);
  }
  CloseHandle(process);
  return path;
}
}  // namespace

ClipboardSource GetClipboardSource() {
  ClipboardSource source;
  HWND owner = GetClipboardOwner();
  if (!owner) {
    return source;
  }
  DWORD owner_pid = 0;
  GetWindowThreadProcessId(owner, &owner_pid);
  if (owner_pid == 0) {
    return source;
  }
  std::wstring path = ImagePath(owner_pid);
  if (!path.empty()) {
    source.app = AppNameFromPath(path);
  }

  // A title from another process would describe something that did not copy.
  HWND foreground = GetForegroundWindow();
  DWORD foreground_pid = 0;
  if (foreground) {
    GetWindowThreadProcessId(foreground, &foreground_pid);
  }
  if (foreground_pid == owner_pid) {
    wchar_t title[512];
    int length = GetWindowTextW(foreground, title,
                                static_cast<int>(sizeof(title) / sizeof(title[0])));
    if (length > 0) {
      source.title.assign(title, length);
    }
  }
  return source;
}
