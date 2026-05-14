#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>
#include <shellapi.h>
#include <gdiplus.h>
#include <objidl.h>
#include <shlwapi.h>

#pragma comment(lib, "shlwapi.lib")

#include <iostream>
#include <vector>
#include <memory>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

// Initialize GDI+ if not already done
static void InitGdiPlus() {
  static bool initialized = false;
  static ULONG_PTR gdiplusToken;
  if (!initialized) {
    Gdiplus::GdiplusStartupInput gdiplusStartupInput;
    Gdiplus::GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, NULL);
    initialized = true;
  }
}

// Helper function to get encoder CLSID
int GetEncoderClsid(const WCHAR* format, CLSID* pClsid) {
  UINT num = 0;
  UINT size = 0;
  Gdiplus::GetImageEncodersSize(&num, &size);
  if (size == 0) return -1;

  Gdiplus::ImageCodecInfo* pImageCodecInfo = (Gdiplus::ImageCodecInfo*)malloc(size);
  if (!pImageCodecInfo) return -1;

  Gdiplus::GetImageEncoders(num, size, pImageCodecInfo);

  for (UINT j = 0; j < num; ++j) {
    if (wcscmp(pImageCodecInfo[j].MimeType, format) == 0) {
      *pClsid = pImageCodecInfo[j].Clsid;
      free(pImageCodecInfo);
      return j;
    }
  }
  free(pImageCodecInfo);
  return -1;
}

static std::wstring GetFileNameFromPath(const std::wstring& path) {
  size_t pos = path.find_last_of(L"/\\");
  if (pos == std::wstring::npos) {
    return path;
  }
  return path.substr(pos + 1);
}

static std::vector<uint8_t> EncodeHIconAsPng(HICON icon) {
  std::vector<uint8_t> result;
  if (!icon) {
    return result;
  }

  InitGdiPlus();
  Gdiplus::Bitmap* bitmap = Gdiplus::Bitmap::FromHICON(icon);
  if (!bitmap || bitmap->GetLastStatus() != Gdiplus::Ok) {
    delete bitmap;
    return result;
  }

  IStream* pSaveStream = nullptr;
  if (CreateStreamOnHGlobal(NULL, TRUE, &pSaveStream) != S_OK) {
    delete bitmap;
    return result;
  }

  CLSID pngClsid;
  if (GetEncoderClsid(L"image/png", &pngClsid) != -1 &&
      bitmap->Save(pSaveStream, &pngClsid, NULL) == Gdiplus::Ok) {
    HGLOBAL hSaveMem = nullptr;
    if (GetHGlobalFromStream(pSaveStream, &hSaveMem) == S_OK && hSaveMem) {
      void* pSaveData = GlobalLock(hSaveMem);
      if (pSaveData) {
        SIZE_T saveSize = GlobalSize(hSaveMem);
        result.assign((uint8_t*)pSaveData, (uint8_t*)pSaveData + saveSize);
        GlobalUnlock(hSaveMem);
      }
    }
  }

  if (pSaveStream) {
    pSaveStream->Release();
  }
  delete bitmap;
  return result;
}

bool GetClipboardOwnerInfo(HWND hwnd, std::wstring& outAppName,
                           std::vector<uint8_t>& outIconPng) {
  HWND owner = GetClipboardOwner();
  if (!owner) {
    return false;
  }

  DWORD process_id = 0;
  GetWindowThreadProcessId(owner, &process_id);
  if (process_id == 0) {
    return false;
  }

  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (!process) {
    return false;
  }

  WCHAR path[MAX_PATH];
  DWORD path_length = static_cast<DWORD>(std::size(path));
  if (!QueryFullProcessImageNameW(process, 0, path, &path_length)) {
    CloseHandle(process);
    return false;
  }
  CloseHandle(process);

  std::wstring full_path(path, path_length);
  std::wstring file_name = GetFileNameFromPath(full_path);
  size_t dot = file_name.find_last_of(L'.');
  if (dot != std::wstring::npos) {
    file_name = file_name.substr(0, dot);
  }
  outAppName = file_name;

  SHFILEINFOW sfi = {};
  if (SHGetFileInfoW(full_path.c_str(), FILE_ATTRIBUTE_NORMAL, &sfi,
                     sizeof(sfi), SHGFI_ICON | SHGFI_SMALLICON) != 0) {
    if (sfi.hIcon) {
      outIconPng = EncodeHIconAsPng(sfi.hIcon);
      DestroyIcon(sfi.hIcon);
    }
  }

  return true;
}

bool SetImageToClipboard(HWND hwnd, const std::vector<uint8_t>& imageData) {
  if (imageData.empty()) {
    std::cout << "[SetImageToClipboard] ERROR: imageData is empty" << std::endl;
    return false;
  }

  std::cout << "[SetImageToClipboard] START: bytes=" << imageData.size() << std::endl;

  InitGdiPlus();

  // Load image from PNG bytes
  HGLOBAL hStreamMem = GlobalAlloc(GMEM_MOVEABLE, imageData.size());
  if (!hStreamMem) {
    std::cout << "[SetImageToClipboard] ERROR: GlobalAlloc failed" << std::endl;
    return false;
  }
  void* pStreamMem = GlobalLock(hStreamMem);
  if (!pStreamMem) {
    GlobalFree(hStreamMem);
    std::cout << "[SetImageToClipboard] ERROR: GlobalLock failed" << std::endl;
    return false;
  }
  memcpy(pStreamMem, imageData.data(), imageData.size());
  GlobalUnlock(hStreamMem);

  IStream* pStream = nullptr;
  if (CreateStreamOnHGlobal(hStreamMem, FALSE, &pStream) != S_OK) {
    GlobalFree(hStreamMem);
    std::cout << "[SetImageToClipboard] ERROR: CreateStreamOnHGlobal failed" << std::endl;
    return false;
  }

  Gdiplus::Bitmap* bitmap = Gdiplus::Bitmap::FromStream(pStream);
  pStream->Release();
  if (!bitmap || bitmap->GetLastStatus() != Gdiplus::Ok) {
    delete bitmap;
    std::cout << "[SetImageToClipboard] ERROR: Failed to create Bitmap from stream" << std::endl;
    return false;
  }

  std::cout << "[SetImageToClipboard] Bitmap created successfully" << std::endl;

  HBITMAP hBitmap = NULL;
  HGLOBAL hDib = NULL;
  Gdiplus::Color blackColor(255, 0, 0, 0);
  if (bitmap->GetHBITMAP(blackColor, &hBitmap) != Gdiplus::Ok || !hBitmap) {
    hBitmap = NULL;
  } else {
    std::cout << "[SetImageToClipboard] HBITMAP created" << std::endl;
  }

  if (hBitmap) {
    BITMAP bmp;
    if (GetObject(hBitmap, sizeof(bmp), &bmp) == sizeof(bmp)) {
      BITMAPINFOHEADER bi = {};
      bi.biSize = sizeof(BITMAPINFOHEADER);
      bi.biWidth = bmp.bmWidth;
      bi.biHeight = bmp.bmHeight;
      bi.biPlanes = 1;
      bi.biBitCount = bmp.bmBitsPixel;
      bi.biCompression = BI_RGB;

      HDC hdc = GetDC(NULL);
      if (hdc) {
        int scanLine = ((bmp.bmWidth * bi.biBitCount + 31) / 32) * 4;
        bi.biSizeImage = scanLine * bmp.bmHeight;
        SIZE_T dibSize = sizeof(BITMAPINFOHEADER) + scanLine * bmp.bmHeight;
        hDib = GlobalAlloc(GMEM_MOVEABLE, dibSize);
        if (hDib) {
          BITMAPINFO* pDibInfo = (BITMAPINFO*)GlobalLock(hDib);
          if (pDibInfo) {
            pDibInfo->bmiHeader = bi;
            BYTE* dibBits = reinterpret_cast<BYTE*>(pDibInfo) + sizeof(BITMAPINFOHEADER);
            if (!GetDIBits(hdc, hBitmap, 0, bmp.bmHeight,
                           dibBits, pDibInfo, DIB_RGB_COLORS)) {
              GlobalUnlock(hDib);
              GlobalFree(hDib);
              hDib = NULL;
            } else {
              GlobalUnlock(hDib);
              std::cout << "[SetImageToClipboard] DIB created" << std::endl;
            }
          } else {
            GlobalFree(hDib);
            hDib = NULL;
          }
        }
        ReleaseDC(NULL, hdc);
      }
    } else {
      DeleteObject(hBitmap);
      hBitmap = NULL;
    }
  }

  std::vector<uint8_t> pngBytes;
  CLSID pngClsid;
  if (GetEncoderClsid(L"image/png", &pngClsid) != -1) {
    IStream* pSaveStream = nullptr;
    if (CreateStreamOnHGlobal(NULL, TRUE, &pSaveStream) == S_OK) {
      if (bitmap->Save(pSaveStream, &pngClsid, NULL) == Gdiplus::Ok) {
        HGLOBAL hSaveMem = nullptr;
        if (GetHGlobalFromStream(pSaveStream, &hSaveMem) == S_OK && hSaveMem) {
          void* pSaveData = GlobalLock(hSaveMem);
          if (pSaveData) {
            SIZE_T saveSize = GlobalSize(hSaveMem);
            pngBytes.assign((uint8_t*)pSaveData, (uint8_t*)pSaveData + saveSize);
            GlobalUnlock(hSaveMem);
            std::cout << "[SetImageToClipboard] PNG encoded, size=" << saveSize << std::endl;
          }
        }
      }
      pSaveStream->Release();
    }
  }

  delete bitmap;

  UINT cfPng = RegisterClipboardFormat(L"PNG");
  if (cfPng == 0) {
    if (hBitmap) {
      DeleteObject(hBitmap);
    }
    if (hDib) {
      GlobalFree(hDib);
    }
    std::cout << "[SetImageToClipboard] ERROR: RegisterClipboardFormat failed" << std::endl;
    return false;
  }

  HGLOBAL hPng = nullptr;
  HGLOBAL hDrop = nullptr;
  if (!pngBytes.empty()) {
    hPng = GlobalAlloc(GMEM_MOVEABLE, pngBytes.size());
    if (!hPng) {
      DeleteObject(hBitmap);
      GlobalFree(hDib);
      std::cout << "[SetImageToClipboard] ERROR: GlobalAlloc for PNG failed" << std::endl;
      return false;
    }
    void* pPng = GlobalLock(hPng);
    if (!pPng) {
      GlobalFree(hPng);
      DeleteObject(hBitmap);
      GlobalFree(hDib);
      std::cout << "[SetImageToClipboard] ERROR: GlobalLock for PNG failed" << std::endl;
      return false;
    }
    memcpy(pPng, pngBytes.data(), pngBytes.size());
    GlobalUnlock(hPng);

    WCHAR tempPath[MAX_PATH] = {};
    WCHAR tempFile[MAX_PATH] = {};
    if (GetTempPathW(MAX_PATH, tempPath) > 0 &&
        GetTempFileNameW(tempPath, L"img", 0, tempFile) != 0) {
      if (PathRenameExtensionW(tempFile, L".png")) {
        HANDLE hFile = CreateFileW(
            tempFile, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
            FILE_ATTRIBUTE_NORMAL, NULL);
        if (hFile != INVALID_HANDLE_VALUE) {
          DWORD bytesWritten = 0;
          if (WriteFile(hFile, pngBytes.data(),
                        static_cast<DWORD>(pngBytes.size()), &bytesWritten,
                        NULL) && bytesWritten == pngBytes.size()) {
            struct DropFilesStruct {
              DWORD pFiles;
              POINT pt;
              BOOL fNC;
              BOOL fWide;
            };
            SIZE_T pathBytes = (wcslen(tempFile) + 2) * sizeof(WCHAR);
            SIZE_T dropSize = sizeof(DropFilesStruct) + pathBytes;
            hDrop = GlobalAlloc(GMEM_MOVEABLE, dropSize);
            if (hDrop) {
              DropFilesStruct* pDrop = (DropFilesStruct*)GlobalLock(hDrop);
              if (pDrop) {
                ZeroMemory(pDrop, dropSize);
                pDrop->pFiles = sizeof(DropFilesStruct);
                pDrop->fWide = TRUE;
                memcpy((BYTE*)pDrop + sizeof(DropFilesStruct), tempFile, pathBytes);
                GlobalUnlock(hDrop);
              } else {
                GlobalFree(hDrop);
                hDrop = nullptr;
              }
            }
          }
          CloseHandle(hFile);
        }
      }
    }
  }

  if (!OpenClipboard(NULL)) {
    GlobalFree(hPng);
    GlobalFree(hDib);
    if (hDrop) {
      GlobalFree(hDrop);
    }
    DeleteObject(hBitmap);
    std::cout << "[SetImageToClipboard] ERROR: OpenClipboard failed" << std::endl;
    return false;
  }

  EmptyClipboard();
  std::cout << "[SetImageToClipboard] Clipboard emptied" << std::endl;

  bool success = false;

  if (hBitmap) {
    if (SetClipboardData(CF_BITMAP, hBitmap)) {
      success = true;
      std::cout << "[SetImageToClipboard] CF_BITMAP set" << std::endl;
    } else {
      DeleteObject(hBitmap);
      hBitmap = NULL;
      std::cout << "[SetImageToClipboard] CF_BITMAP failed" << std::endl;
    }
  }

  if (hDib) {
    if (SetClipboardData(CF_DIB, hDib)) {
      success = true;
      std::cout << "[SetImageToClipboard] CF_DIB set" << std::endl;
    } else {
      GlobalFree(hDib);
      hDib = NULL;
      std::cout << "[SetImageToClipboard] CF_DIB failed" << std::endl;
    }
  }

  if (hPng) {
    if (SetClipboardData(cfPng, hPng)) {
      success = true;
      std::cout << "[SetImageToClipboard] PNG format set" << std::endl;
    } else {
      GlobalFree(hPng);
      std::cout << "[SetImageToClipboard] PNG format failed" << std::endl;
    }
  }

  if (hDrop) {
    if (SetClipboardData(CF_HDROP, hDrop)) {
      success = true;
      std::cout << "[SetImageToClipboard] CF_HDROP set" << std::endl;
    } else {
      GlobalFree(hDrop);
      std::cout << "[SetImageToClipboard] CF_HDROP failed" << std::endl;
    }
  }

  CloseClipboard();
  std::cout << "[SetImageToClipboard] END: success=" << (success ? "true" : "false") << std::endl;

  if (!success) {
    if (hBitmap) {
      DeleteObject(hBitmap);
    }
    if (hDib) {
      GlobalFree(hDib);
    }
  }

  return success;
}


std::vector<uint8_t> GetImageFromClipboard(HWND hwnd) {
  std::vector<uint8_t> result;

  // Open clipboard
  if (!OpenClipboard(NULL)) {
    return result;
  }

  // 1. Try to get a dragged file (CF_HDROP), such as an image copied from Explorer
  HDROP hDrop = (HDROP)GetClipboardData(CF_HDROP);
  if (hDrop) {
    UINT fileCount = DragQueryFileW(hDrop, 0xFFFFFFFF, NULL, 0);
    if (fileCount > 0) {
      wchar_t filePath[MAX_PATH];
      if (DragQueryFileW(hDrop, 0, filePath, MAX_PATH)) {
        const wchar_t* ext = PathFindExtensionW(filePath);
        if (_wcsicmp(ext, L".png") == 0 || _wcsicmp(ext, L".jpg") == 0 ||
            _wcsicmp(ext, L".jpeg") == 0 || _wcsicmp(ext, L".bmp") == 0 ||
            _wcsicmp(ext, L".gif") == 0) {
          HANDLE hFile = CreateFileW(filePath, GENERIC_READ, FILE_SHARE_READ,
                                     NULL, OPEN_EXISTING,
                                     FILE_ATTRIBUTE_NORMAL, NULL);
          if (hFile != INVALID_HANDLE_VALUE) {
            DWORD fileSize = GetFileSize(hFile, NULL);
            if (fileSize > 0 && fileSize < 50 * 1024 * 1024) {
              result.resize(fileSize);
              DWORD bytesRead = 0;
              ReadFile(hFile, result.data(), fileSize, &bytesRead, NULL);
            }
            CloseHandle(hFile);
            if (!result.empty()) {
              CloseClipboard();
              return result;
            }
          }
        }
      }
    }
  }

  // 2. Try to get PNG format first
  UINT cfPng = RegisterClipboardFormat(L"PNG");
  HANDLE hPngData = GetClipboardData(cfPng);
  if (hPngData) {
    void* pData = GlobalLock(hPngData);
    if (pData) {
      SIZE_T size = GlobalSize(hPngData);
      result.assign((uint8_t*)pData, (uint8_t*)pData + size);
      GlobalUnlock(hPngData);
    }
    CloseClipboard();
    return result;
  }

  // If no PNG, try to get bitmap and convert to PNG
  InitGdiPlus();

  HBITMAP hBitmap = (HBITMAP)GetClipboardData(CF_BITMAP);
  if (!hBitmap) {
    // Try DIB
    HANDLE hDib = GetClipboardData(CF_DIB);
    if (hDib) {
      void* pDib = GlobalLock(hDib);
      if (pDib) {
        BITMAPINFO* pInfo = (BITMAPINFO*)pDib;
        void* pBits = (uint8_t*)pDib + pInfo->bmiHeader.biSize;
        if (pInfo->bmiHeader.biBitCount <= 8) {
          int colors = pInfo->bmiHeader.biClrUsed;
          if (colors == 0) colors = 1 << pInfo->bmiHeader.biBitCount;
          pBits = (uint8_t*)pBits + (colors * sizeof(RGBQUAD));
        }
        Gdiplus::Bitmap bitmap(pInfo, pBits);
        if (bitmap.GetLastStatus() == Gdiplus::Ok) {
          IStream* pStream = NULL;
          if (CreateStreamOnHGlobal(NULL, TRUE, &pStream) == S_OK) {
            CLSID pngClsid;
            if (GetEncoderClsid(L"image/png", &pngClsid) != -1) {
              if (bitmap.Save(pStream, &pngClsid, NULL) == Gdiplus::Ok) {
                HGLOBAL hMem = NULL;
                GetHGlobalFromStream(pStream, &hMem);
                if (hMem) {
                  void* pMem = GlobalLock(hMem);
                  SIZE_T size = GlobalSize(hMem);
                  result.assign((uint8_t*)pMem, (uint8_t*)pMem + size);
                  GlobalUnlock(hMem);
                }
              }
            }
            pStream->Release();
          }
        }
        GlobalUnlock(hDib);
      }
    }
  } else {
    Gdiplus::Bitmap bitmap(hBitmap, NULL);
    if (bitmap.GetLastStatus() == Gdiplus::Ok) {
      IStream* pStream = NULL;
      if (CreateStreamOnHGlobal(NULL, TRUE, &pStream) == S_OK) {
        CLSID pngClsid;
        if (GetEncoderClsid(L"image/png", &pngClsid) != -1) {
          if (bitmap.Save(pStream, &pngClsid, NULL) == Gdiplus::Ok) {
            HGLOBAL hMem = NULL;
            GetHGlobalFromStream(pStream, &hMem);
            if (hMem) {
              void* pMem = GlobalLock(hMem);
              SIZE_T size = GlobalSize(hMem);
              result.assign((uint8_t*)pMem, (uint8_t*)pMem + size);
              GlobalUnlock(hMem);
            }
          }
        }
        pStream->Release();
      }
    }
  }

  CloseClipboard();
  return result;
}
