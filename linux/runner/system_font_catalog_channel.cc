#include "system_font_catalog_channel.h"

#include <fontconfig/fontconfig.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr char kChannelName[] = "zeta/system_fonts";
constexpr char kListFontFamiliesMethod[] = "listFontFamilies";

struct LocalizedName {
  std::string locale;
  std::string value;
};

struct FontFamilyRecord {
  std::string canonical_name;
  std::string display_name;
  std::set<std::string> aliases;
  bool is_monospace = false;
};

std::string lower_ascii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char character) {
                   return static_cast<char>(std::tolower(character));
                 });
  return value;
}

std::string normalize_locale(std::string locale) {
  std::replace(locale.begin(), locale.end(), '_', '-');
  return lower_ascii(std::move(locale));
}

std::string locale_language(const std::string& locale) {
  const size_t separator = locale.find('-');
  return separator == std::string::npos ? locale
                                       : locale.substr(0, separator);
}

std::string pick_localized_name(const std::vector<LocalizedName>& names,
                                const std::string& requested_locale,
                                bool prefer_english) {
  if (names.empty()) {
    return std::string();
  }
  const std::string requested =
      prefer_english ? "en-us" : normalize_locale(requested_locale);
  for (const auto& name : names) {
    if (name.locale == requested) {
      return name.value;
    }
  }
  const std::string language = locale_language(requested);
  for (const auto& name : names) {
    if (locale_language(name.locale) == language) {
      return name.value;
    }
  }
  for (const auto& name : names) {
    if (name.locale == "en-us" || name.locale == "en") {
      return name.value;
    }
  }
  return names.front().value;
}

std::vector<LocalizedName> read_family_names(FcPattern* pattern) {
  std::vector<LocalizedName> names;
  for (int index = 0;; ++index) {
    FcChar8* family = nullptr;
    if (FcPatternGetString(pattern, FC_FAMILY, index, &family) !=
        FcResultMatch) {
      break;
    }
    FcChar8* language = nullptr;
    const FcResult language_result =
        FcPatternGetString(pattern, FC_FAMILYLANG, index, &language);
    names.push_back(
        {language_result == FcResultMatch
             ? normalize_locale(reinterpret_cast<const char*>(language))
             : std::string(),
         reinterpret_cast<const char*>(family)});
  }
  return names;
}

std::string file_stem(const std::string& path) {
  const size_t slash = path.find_last_of('/');
  const size_t start = slash == std::string::npos ? 0 : slash + 1;
  const size_t dot = path.find_last_of('.');
  const size_t end =
      dot == std::string::npos || dot < start ? path.size() : dot;
  return path.substr(start, end - start);
}

std::string read_requested_locale(FlMethodCall* method_call) {
  FlValue* arguments = fl_method_call_get_args(method_call);
  if (arguments == nullptr ||
      fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP) {
    return "en-US";
  }
  FlValue* locale = fl_value_lookup_string(arguments, "locale");
  if (locale == nullptr || fl_value_get_type(locale) != FL_VALUE_TYPE_STRING) {
    return "en-US";
  }
  return fl_value_get_string(locale);
}

bool list_font_families(const std::string& locale,
                        std::vector<FontFamilyRecord>* result) {
  if (!FcInit()) {
    return false;
  }

  FcPattern* pattern = FcPatternCreate();
  FcObjectSet* objects =
      FcObjectSetBuild(FC_FAMILY, FC_FAMILYLANG, FC_FILE, FC_SPACING, nullptr);
  if (pattern == nullptr || objects == nullptr) {
    if (objects != nullptr) {
      FcObjectSetDestroy(objects);
    }
    if (pattern != nullptr) {
      FcPatternDestroy(pattern);
    }
    return false;
  }

  FcFontSet* fonts = FcFontList(nullptr, pattern, objects);
  FcObjectSetDestroy(objects);
  FcPatternDestroy(pattern);
  if (fonts == nullptr) {
    return false;
  }

  std::map<std::string, FontFamilyRecord> families;
  for (int font_index = 0; font_index < fonts->nfont; ++font_index) {
    FcPattern* font = fonts->fonts[font_index];
    const std::vector<LocalizedName> names = read_family_names(font);
    const std::string canonical_name =
        pick_localized_name(names, "en-us", true);
    if (canonical_name.empty()) {
      continue;
    }
    const std::string identity = lower_ascii(canonical_name);
    FontFamilyRecord& family = families[identity];
    if (family.canonical_name.empty()) {
      family.canonical_name = canonical_name;
    }
    if (family.display_name.empty()) {
      family.display_name = pick_localized_name(names, locale, false);
    }
    for (const auto& name : names) {
      if (!name.value.empty()) {
        family.aliases.insert(name.value);
      }
    }

    FcChar8* file = nullptr;
    if (FcPatternGetString(font, FC_FILE, 0, &file) == FcResultMatch) {
      const std::string alias =
          file_stem(reinterpret_cast<const char*>(file));
      if (!alias.empty()) {
        family.aliases.insert(alias);
      }
    }

    int spacing = FC_PROPORTIONAL;
    if (FcPatternGetInteger(font, FC_SPACING, 0, &spacing) == FcResultMatch) {
      family.is_monospace =
          family.is_monospace || spacing == FC_MONO || spacing == FC_DUAL ||
          spacing == FC_CHARCELL;
    }
  }
  FcFontSetDestroy(fonts);

  result->reserve(families.size());
  for (auto& entry : families) {
    FontFamilyRecord family = std::move(entry.second);
    family.aliases.insert(family.canonical_name);
    family.aliases.insert(family.display_name);
    result->push_back(std::move(family));
  }
  std::sort(result->begin(), result->end(),
            [](const FontFamilyRecord& left, const FontFamilyRecord& right) {
              return lower_ascii(left.display_name) <
                     lower_ascii(right.display_name);
            });
  return true;
}

FlValue* encode_font_families(
    const std::vector<FontFamilyRecord>& families) {
  FlValue* encoded_families = fl_value_new_list();
  for (const auto& family : families) {
    FlValue* aliases = fl_value_new_list();
    for (const auto& alias : family.aliases) {
      fl_value_append_take(aliases, fl_value_new_string(alias.c_str()));
    }

    FlValue* encoded_family = fl_value_new_map();
    const std::string identity = "linux:" + lower_ascii(family.canonical_name);
    fl_value_set_string_take(encoded_family, "id",
                             fl_value_new_string(identity.c_str()));
    fl_value_set_string_take(
        encoded_family, "familyName",
        fl_value_new_string(family.canonical_name.c_str()));
    fl_value_set_string_take(
        encoded_family, "displayName",
        fl_value_new_string(family.display_name.c_str()));
    fl_value_set_string_take(encoded_family, "aliases", aliases);
    fl_value_set_string_take(encoded_family, "monospace",
                             fl_value_new_bool(family.is_monospace));
    fl_value_append_take(encoded_families, encoded_family);
  }
  return encoded_families;
}

void method_call_cb(FlMethodChannel*,
                    FlMethodCall* method_call,
                    gpointer) {
  if (strcmp(fl_method_call_get_name(method_call),
             kListFontFamiliesMethod) != 0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }

  std::vector<FontFamilyRecord> families;
  if (!list_font_families(read_requested_locale(method_call), &families)) {
    fl_method_call_respond_error(
        method_call, "font_catalog_failed",
        "Fontconfig could not enumerate system fonts.", nullptr, nullptr);
    return;
  }

  g_autoptr(FlValue) response = encode_font_families(families);
  fl_method_call_respond_success(method_call, response, nullptr);
}

}  // namespace

FlMethodChannel* create_system_font_catalog_channel(
    FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr,
                                            nullptr);
  return channel;
}
