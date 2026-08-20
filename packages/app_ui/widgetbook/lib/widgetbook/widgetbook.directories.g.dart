// dart format width=80
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering

// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AppGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:widgetbook/widgetbook.dart' as _widgetbook;
import 'package:widgetbook_catalog/widgetbook/use_cases/app_button.dart'
    as _widgetbook_catalog_widgetbook_use_cases_app_button;
import 'package:widgetbook_catalog/widgetbook/use_cases/ide_components.dart'
    as _widgetbook_catalog_widgetbook_use_cases_ide_components;

final directories = <_widgetbook.WidgetbookNode>[
  _widgetbook.WidgetbookFolder(
    name: 'components',
    children: [
      _widgetbook.WidgetbookComponent(
        name: 'IdeButton',
        useCases: [
          _widgetbook.WidgetbookUseCase(
            name: 'control gallery',
            builder: _widgetbook_catalog_widgetbook_use_cases_ide_components
                .controlGallery,
          ),
        ],
      ),
      _widgetbook.WidgetbookComponent(
        name: 'IdeStatusCard',
        useCases: [
          _widgetbook.WidgetbookUseCase(
            name: 'status tones',
            builder: _widgetbook_catalog_widgetbook_use_cases_ide_components
                .statusTones,
          ),
        ],
      ),
      _widgetbook.WidgetbookComponent(
        name: 'IdeTabs',
        useCases: [
          _widgetbook.WidgetbookUseCase(
            name: 'desktop tabs',
            builder: _widgetbook_catalog_widgetbook_use_cases_ide_components
                .desktopTabs,
          ),
        ],
      ),
      _widgetbook.WidgetbookComponent(
        name: 'WindowFrame',
        useCases: [
          _widgetbook.WidgetbookUseCase(
            name: 'Windows shell',
            builder: _widgetbook_catalog_widgetbook_use_cases_ide_components
                .windowsShell,
          ),
        ],
      ),
    ],
  ),
  _widgetbook.WidgetbookFolder(
    name: 'widgets',
    children: [
      _widgetbook.WidgetbookComponent(
        name: 'AppButton',
        useCases: [
          _widgetbook.WidgetbookUseCase(
            name: 'all sizes',
            builder:
                _widgetbook_catalog_widgetbook_use_cases_app_button.allSizes,
          ),
          _widgetbook.WidgetbookUseCase(
            name: 'disabled',
            builder:
                _widgetbook_catalog_widgetbook_use_cases_app_button.disabled,
          ),
          _widgetbook.WidgetbookUseCase(
            name: 'outline',
            builder:
                _widgetbook_catalog_widgetbook_use_cases_app_button.outline,
          ),
          _widgetbook.WidgetbookUseCase(
            name: 'primary',
            builder:
                _widgetbook_catalog_widgetbook_use_cases_app_button.primary,
          ),
          _widgetbook.WidgetbookUseCase(
            name: 'secondary',
            builder:
                _widgetbook_catalog_widgetbook_use_cases_app_button.secondary,
          ),
        ],
      ),
    ],
  ),
];
