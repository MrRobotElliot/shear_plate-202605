#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <optional>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Set up method channel for clipboard image support
  clipboard_channel_ = std::make_unique<flutter::MethodChannel<>>(
      flutter_controller_->engine()->messenger(), "clipboard_image",
      &flutter::StandardMethodCodec::GetInstance());
  clipboard_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<>& call,
         std::unique_ptr<flutter::MethodResult<>> result) {
        if (call.method_name() == "setImage") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            auto data_it = arguments->find(flutter::EncodableValue("data"));
            if (data_it != arguments->end()) {
              const auto* data_list = std::get_if<std::vector<uint8_t>>(&data_it->second);
              if (data_list) {
                std::cout << "[CPP setImage] Called with " << data_list->size() << " bytes" << std::endl;
                bool clipboard_success = SetImageToClipboard(NULL, *data_list);
                std::cout << "[CPP setImage] SetImageToClipboard returned: " << (clipboard_success ? "true" : "false") << std::endl;
                result->Success();
                return;
              } else {
                std::cerr << "[CPP setImage] ERROR: data is not a vector<uint8_t>" << std::endl;
              }
            } else {
              std::cerr << "[CPP setImage] ERROR: data field not found in map" << std::endl;
            }
          } else {
            std::cerr << "[CPP setImage] ERROR: arguments is not an EncodableMap" << std::endl;
          }
          result->Error("INVALID_ARGUMENT", "Image data is invalid");
        } else if (call.method_name() == "getImage") {
          auto imageData = GetImageFromClipboard(NULL);
          if (!imageData.empty()) {
            result->Success(flutter::EncodableValue(imageData));
          } else {
            result->Success(flutter::EncodableValue(nullptr));
          }
        } else {
          result->NotImplemented();
        }
      });

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
