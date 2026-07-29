#include "system_font_catalog_channel.h"

// Windows headers must precede DirectWrite and Flutter codec headers.
#include <windows.h>

#include <dwrite.h>
#include <dwrite_1.h>
#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cwctype>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;

constexpr char kChannelName[] = "zeta/system_fonts";
constexpr char kListFontFamiliesMethod[] = "listFontFamilies";

struct LocalizedName {
  std::wstring locale;
  std::wstring value;
};

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int length =
      WideCharToMultiByte(CP_UTF8, 0, value.data(),
                          static_cast<int>(value.size()), nullptr, 0, nullptr,
                          nullptr);
  if (length <= 0) {
    return std::string();
  }
  std::string result(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), length,
                      nullptr, nullptr);
  return result;
}

std::wstring NormalizeLocale(std::wstring locale) {
  std::replace(locale.begin(), locale.end(), L'_', L'-');
  std::transform(locale.begin(), locale.end(), locale.begin(),
                 [](wchar_t character) { return std::towlower(character); });
  return locale;
}

std::wstring LocaleLanguage(const std::wstring& locale) {
  const size_t separator = locale.find(L'-');
  return separator == std::wstring::npos ? locale
                                        : locale.substr(0, separator);
}

std::vector<LocalizedName> ReadLocalizedNames(IDWriteLocalizedStrings* names) {
  std::vector<LocalizedName> result;
  if (names == nullptr) {
    return result;
  }
  const UINT32 count = names->GetCount();
  result.reserve(count);
  for (UINT32 index = 0; index < count; ++index) {
    UINT32 locale_length = 0;
    UINT32 value_length = 0;
    if (FAILED(names->GetLocaleNameLength(index, &locale_length)) ||
        FAILED(names->GetStringLength(index, &value_length))) {
      continue;
    }
    std::wstring locale(locale_length + 1, L'\0');
    std::wstring value(value_length + 1, L'\0');
    if (FAILED(names->GetLocaleName(index, locale.data(), locale_length + 1)) ||
        FAILED(names->GetString(index, value.data(), value_length + 1))) {
      continue;
    }
    locale.resize(locale_length);
    value.resize(value_length);
    if (!value.empty()) {
      result.push_back({NormalizeLocale(locale), value});
    }
  }
  return result;
}

std::wstring PickLocalizedName(const std::vector<LocalizedName>& names,
                               const std::wstring& requested_locale,
                               bool prefer_english) {
  if (names.empty()) {
    return std::wstring();
  }
  const std::wstring normalized_locale = NormalizeLocale(requested_locale);
  const std::wstring requested =
      prefer_english ? std::wstring(L"en-us") : normalized_locale;
  for (const auto& name : names) {
    if (name.locale == requested) {
      return name.value;
    }
  }
  const std::wstring language = LocaleLanguage(requested);
  for (const auto& name : names) {
    if (LocaleLanguage(name.locale) == language) {
      return name.value;
    }
  }
  for (const auto& name : names) {
    if (name.locale == L"en-us") {
      return name.value;
    }
  }
  return names.front().value;
}

std::wstring FileStem(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  const size_t start = slash == std::wstring::npos ? 0 : slash + 1;
  const size_t dot = path.find_last_of(L'.');
  const size_t end =
      dot == std::wstring::npos || dot < start ? path.size() : dot;
  return path.substr(start, end - start);
}

void AddFontFileAliases(IDWriteFontFamily* family,
                        std::set<std::string>* aliases) {
  const UINT32 font_count = family->GetFontCount();
  for (UINT32 font_index = 0; font_index < font_count; ++font_index) {
    ComPtr<IDWriteFont> font;
    if (FAILED(family->GetFont(font_index, &font))) {
      continue;
    }
    ComPtr<IDWriteFontFace> face;
    if (FAILED(font->CreateFontFace(&face))) {
      continue;
    }
    UINT32 file_count = 0;
    if (FAILED(face->GetFiles(&file_count, nullptr)) || file_count == 0) {
      continue;
    }
    std::vector<IDWriteFontFile*> raw_files(file_count, nullptr);
    if (FAILED(face->GetFiles(&file_count, raw_files.data()))) {
      continue;
    }
    for (IDWriteFontFile* raw_file : raw_files) {
      ComPtr<IDWriteFontFile> file;
      file.Attach(raw_file);
      const void* reference_key = nullptr;
      UINT32 reference_key_size = 0;
      ComPtr<IDWriteFontFileLoader> loader;
      if (FAILED(file->GetReferenceKey(&reference_key, &reference_key_size)) ||
          FAILED(file->GetLoader(&loader))) {
        continue;
      }
      ComPtr<IDWriteLocalFontFileLoader> local_loader;
      if (FAILED(loader.As(&local_loader))) {
        continue;
      }
      UINT32 path_length = 0;
      if (FAILED(local_loader->GetFilePathLengthFromKey(
              reference_key, reference_key_size, &path_length))) {
        continue;
      }
      std::wstring path(path_length + 1, L'\0');
      if (FAILED(local_loader->GetFilePathFromKey(
              reference_key, reference_key_size, path.data(),
              path_length + 1))) {
        continue;
      }
      path.resize(path_length);
      const std::string stem = WideToUtf8(FileStem(path));
      if (!stem.empty()) {
        aliases->insert(stem);
      }
    }
  }
}

bool IsMonospace(IDWriteFontFamily* family) {
  ComPtr<IDWriteFont> font;
  if (FAILED(family->GetFirstMatchingFont(
          DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
          DWRITE_FONT_STYLE_NORMAL, &font))) {
    return false;
  }
  ComPtr<IDWriteFont1> font1;
  return SUCCEEDED(font.As(&font1)) && font1->IsMonospacedFont();
}

std::string ReadRequestedLocale(
    const flutter::EncodableValue* arguments) {
  if (arguments == nullptr) {
    return "en-US";
  }
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return "en-US";
  }
  const auto iterator = map->find(flutter::EncodableValue("locale"));
  if (iterator == map->end()) {
    return "en-US";
  }
  const auto* locale = std::get_if<std::string>(&iterator->second);
  return locale == nullptr || locale->empty() ? "en-US" : *locale;
}

HRESULT ListFontFamilies(const std::string& locale,
                         flutter::EncodableList* result) {
  ComPtr<IDWriteFactory> factory;
  HRESULT status = DWriteCreateFactory(
      DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
      reinterpret_cast<IUnknown**>(factory.GetAddressOf()));
  if (FAILED(status)) {
    return status;
  }

  ComPtr<IDWriteFontCollection> collection;
  status = factory->GetSystemFontCollection(&collection, TRUE);
  if (FAILED(status)) {
    return status;
  }

  const std::wstring requested_locale = Utf8ToWide(locale);
  const UINT32 family_count = collection->GetFontFamilyCount();
  result->reserve(family_count);
  for (UINT32 family_index = 0; family_index < family_count; ++family_index) {
    ComPtr<IDWriteFontFamily> family;
    ComPtr<IDWriteLocalizedStrings> family_names;
    if (FAILED(collection->GetFontFamily(family_index, &family)) ||
        FAILED(family->GetFamilyNames(&family_names))) {
      continue;
    }

    const std::vector<LocalizedName> localized_names =
        ReadLocalizedNames(family_names.Get());
    const std::wstring canonical_name =
        PickLocalizedName(localized_names, L"en-us", true);
    const std::wstring display_name =
        PickLocalizedName(localized_names, requested_locale, false);
    if (canonical_name.empty()) {
      continue;
    }

    std::set<std::string> aliases;
    for (const auto& name : localized_names) {
      const std::string alias = WideToUtf8(name.value);
      if (!alias.empty()) {
        aliases.insert(alias);
      }
    }
    AddFontFileAliases(family.Get(), &aliases);

    const std::string canonical_utf8 = WideToUtf8(canonical_name);
    std::string stable_name = canonical_utf8;
    std::transform(stable_name.begin(), stable_name.end(), stable_name.begin(),
                   [](unsigned char character) {
                     return static_cast<char>(std::tolower(character));
                   });

    flutter::EncodableList encoded_aliases;
    encoded_aliases.reserve(aliases.size());
    for (const auto& alias : aliases) {
      encoded_aliases.emplace_back(alias);
    }

    flutter::EncodableMap encoded_family;
    encoded_family[flutter::EncodableValue("id")] =
        flutter::EncodableValue("windows:" + stable_name);
    encoded_family[flutter::EncodableValue("familyName")] =
        flutter::EncodableValue(canonical_utf8);
    encoded_family[flutter::EncodableValue("displayName")] =
        flutter::EncodableValue(WideToUtf8(display_name));
    encoded_family[flutter::EncodableValue("aliases")] =
        flutter::EncodableValue(encoded_aliases);
    encoded_family[flutter::EncodableValue("monospace")] =
        flutter::EncodableValue(IsMonospace(family.Get()));
    result->emplace_back(encoded_family);
  }
  return S_OK;
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateSystemFontCatalogChannel(flutter::BinaryMessenger* messenger) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != kListFontFamiliesMethod) {
          result->NotImplemented();
          return;
        }
        flutter::EncodableList families;
        const HRESULT status =
            ListFontFamilies(ReadRequestedLocale(call.arguments()), &families);
        if (FAILED(status)) {
          result->Error("font_catalog_failed",
                        "DirectWrite could not enumerate system fonts.",
                        flutter::EncodableValue(static_cast<int64_t>(status)));
          return;
        }
        result->Success(flutter::EncodableValue(families));
      });
  return channel;
}
