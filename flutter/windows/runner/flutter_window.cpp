#include "flutter_window.h"

#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <texture_rgba_renderer/texture_rgba_renderer_plugin_c_api.h>
#include <flutter_gpu_texture_renderer/flutter_gpu_texture_renderer_plugin_c_api.h>

#include "flutter/generated_plugin_registrant.h"

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <shlobj.h>
#include <windows.h>

#include <optional>
#include <memory>
#include <string>
#include <vector>

#include "win32_desktop.h"

namespace {

class DropSource : public IDropSource {
 public:
  HRESULT __stdcall QueryInterface(REFIID iid, void** object) override {
    if (iid == IID_IUnknown || iid == IID_IDropSource) {
      *object = static_cast<IDropSource*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  ULONG __stdcall AddRef() override { return ++ref_count_; }

  ULONG __stdcall Release() override {
    const auto count = --ref_count_;
    if (count == 0) {
      delete this;
    }
    return count;
  }

  HRESULT __stdcall QueryContinueDrag(BOOL escape_pressed,
                                      DWORD key_state) override {
    if (escape_pressed) {
      return DRAGDROP_S_CANCEL;
    }
    if ((key_state & MK_LBUTTON) == 0) {
      return DRAGDROP_S_DROP;
    }
    return S_OK;
  }

  HRESULT __stdcall GiveFeedback(DWORD) override {
    return DRAGDROP_S_USEDEFAULTCURSORS;
  }

 private:
  ULONG ref_count_ = 1;
};

class FileDataObject : public IDataObject {
 public:
  explicit FileDataObject(std::vector<std::wstring> paths)
      : paths_(std::move(paths)) {}

  HRESULT __stdcall QueryInterface(REFIID iid, void** object) override {
    if (iid == IID_IUnknown || iid == IID_IDataObject) {
      *object = static_cast<IDataObject*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  ULONG __stdcall AddRef() override { return ++ref_count_; }

  ULONG __stdcall Release() override {
    const auto count = --ref_count_;
    if (count == 0) {
      delete this;
    }
    return count;
  }

  HRESULT __stdcall GetData(FORMATETC* format, STGMEDIUM* medium) override {
    if (!IsSupported(format)) {
      return DV_E_FORMATETC;
    }

    size_t chars = 1;
    for (const auto& path : paths_) {
      chars += path.size() + 1;
    }
    const SIZE_T bytes = sizeof(DROPFILES) + chars * sizeof(wchar_t);
    HGLOBAL global = GlobalAlloc(GHND | GMEM_SHARE, bytes);
    if (!global) {
      return STG_E_MEDIUMFULL;
    }

    auto* drop_files = static_cast<DROPFILES*>(GlobalLock(global));
    if (!drop_files) {
      GlobalFree(global);
      return STG_E_MEDIUMFULL;
    }
    drop_files->pFiles = sizeof(DROPFILES);
    drop_files->fWide = TRUE;
    auto* cursor = reinterpret_cast<wchar_t*>(
        reinterpret_cast<BYTE*>(drop_files) + sizeof(DROPFILES));
    for (const auto& path : paths_) {
      memcpy(cursor, path.c_str(), path.size() * sizeof(wchar_t));
      cursor += path.size() + 1;
    }
    *cursor = L'\0';
    GlobalUnlock(global);

    medium->tymed = TYMED_HGLOBAL;
    medium->hGlobal = global;
    medium->pUnkForRelease = nullptr;
    return S_OK;
  }

  HRESULT __stdcall GetDataHere(FORMATETC*, STGMEDIUM*) override {
    return DATA_E_FORMATETC;
  }

  HRESULT __stdcall QueryGetData(FORMATETC* format) override {
    return IsSupported(format) ? S_OK : DV_E_FORMATETC;
  }

  HRESULT __stdcall GetCanonicalFormatEtc(FORMATETC*, FORMATETC* target)
      override {
    target->ptd = nullptr;
    return E_NOTIMPL;
  }

  HRESULT __stdcall SetData(FORMATETC*, STGMEDIUM*, BOOL) override {
    return E_NOTIMPL;
  }

  HRESULT __stdcall EnumFormatEtc(DWORD direction, IEnumFORMATETC** enum_out)
      override {
    if (direction != DATADIR_GET) {
      return E_NOTIMPL;
    }
    FORMATETC format = {CF_HDROP, nullptr, DVASPECT_CONTENT, -1,
                        TYMED_HGLOBAL};
    return SHCreateStdEnumFmtEtc(1, &format, enum_out);
  }

  HRESULT __stdcall DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }

  HRESULT __stdcall DUnadvise(DWORD) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }

  HRESULT __stdcall EnumDAdvise(IEnumSTATDATA**) override {
    return OLE_E_ADVISENOTSUPPORTED;
  }

 private:
  bool IsSupported(FORMATETC* format) {
    return format &&
           format->cfFormat == CF_HDROP &&
           (format->tymed & TYMED_HGLOBAL) &&
           format->dwAspect == DVASPECT_CONTENT;
  }

  ULONG ref_count_ = 1;
  std::vector<std::wstring> paths_;
};

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring result(size - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), size);
  return result;
}

bool DragFiles(const std::vector<std::wstring>& paths) {
  if (paths.empty()) {
    return false;
  }
  auto* data_object = new FileDataObject(paths);
  auto* drop_source = new DropSource();
  DWORD effect = DROPEFFECT_NONE;
  const HRESULT hr = DoDragDrop(
      data_object, drop_source, DROPEFFECT_COPY | DROPEFFECT_MOVE, &effect);
  data_object->Release();
  drop_source->Release();
  return hr == DRAGDROP_S_DROP && effect != DROPEFFECT_NONE;
}

std::vector<std::wstring> PathsFromArguments(
    const flutter::EncodableValue* arguments) {
  std::vector<std::wstring> paths;
  if (!arguments || !std::holds_alternative<flutter::EncodableList>(*arguments)) {
    return paths;
  }
  const auto args = std::get<flutter::EncodableList>(*arguments);
  for (const auto& item : args) {
    if (!std::holds_alternative<std::string>(item)) {
      continue;
    }
    const auto path = Utf8ToWide(std::get<std::string>(item));
    if (!path.empty() && GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES) {
      paths.push_back(path);
    }
  }
  return paths;
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

  flutter::MethodChannel<> channel(
    flutter_controller_->engine()->messenger(),
    "org.rustdesk.rustdesk/host",
    &flutter::StandardMethodCodec::GetInstance());

  channel.SetMethodCallHandler(
    [](const flutter::MethodCall<>& call, std::unique_ptr<flutter::MethodResult<>> result) {
      if (call.method_name() == "bumpMouse") {
        auto arguments = call.arguments();

        int dx = 0, dy = 0;

        if (std::holds_alternative<flutter::EncodableMap>(*arguments)) {
          auto argsMap = std::get<flutter::EncodableMap>(*arguments);

          auto dxIt = argsMap.find(flutter::EncodableValue("dx"));
          auto dyIt = argsMap.find(flutter::EncodableValue("dy"));

          if ((dxIt != argsMap.end()) && std::holds_alternative<int>(dxIt->second)) {
            dx = std::get<int>(dxIt->second);
          }
          if ((dyIt != argsMap.end()) && std::holds_alternative<int>(dyIt->second)) {
            dy = std::get<int>(dyIt->second);
          }
        } else if (std::holds_alternative<flutter::EncodableList>(*arguments)) {
          auto argsList = std::get<flutter::EncodableList>(*arguments);

          if ((argsList.size() >= 1) && std::holds_alternative<int>(argsList[0])) {
            dx = std::get<int>(argsList[0]);
          }
          if ((argsList.size() >= 2) && std::holds_alternative<int>(argsList[1])) {
            dy = std::get<int>(argsList[1]);
          }
        }

        bool succeeded = Win32Desktop::BumpMouse(dx, dy);

        result->Success(succeeded);
      } else if (call.method_name() == "dragFiles") {
        const auto paths = PathsFromArguments(call.arguments());
        result->Success(DragFiles(paths));
      } else {
        result->NotImplemented();
      }
    });

  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    TextureRgbaRendererPluginCApiRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("TextureRgbaRendererPlugin"));
    FlutterGpuTextureRendererPluginCApiRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("FlutterGpuTextureRendererPluginCApi"));
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
