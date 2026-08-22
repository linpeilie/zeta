/// Zeta 的 Graphite 设计系统。
///
/// 这里只放**与业务无关**的 UI 原语：主题 token（颜色/排版/间距/圆角/动效/尺寸）、
/// `Ide*` 控件、Workbench 骨架、虚拟滚动与弹层原语。
///
/// 明确不做的事：
///
/// - 不认识 Agent、Provider、Repository、Riverpod 或任何业务模型；
/// - 不读文件、不起进程（无 `dart:io`）——需要本机资源时由宿主传入数据；
/// - 不 import generated l10n：控件自有文案通过 [ZetaUiTextCatalog] 注入。
library;

export 'src/app_theme.dart';
export 'src/ide_activity_rail.dart';
export 'src/ide_button.dart';
export 'src/ide_chip.dart';
export 'src/ide_choice_card.dart';
export 'src/ide_collapsible_card.dart';
export 'src/ide_colors.dart';
export 'src/ide_context_menu.dart';
export 'src/ide_dialog.dart';
export 'src/ide_effects.dart';
export 'src/ide_icon_box.dart';
export 'src/ide_metrics.dart';
export 'src/ide_motion.dart';
export 'src/ide_popover.dart';
export 'src/ide_resize_handle.dart';
export 'src/ide_select.dart';
export 'src/ide_skeleton.dart';
export 'src/ide_spacing.dart';
export 'src/ide_stable_overlay_handler.dart';
export 'src/ide_status_card.dart';
export 'src/ide_switch.dart';
export 'src/ide_tabs.dart';
export 'src/ide_text_styles.dart';
export 'src/ide_toast.dart';
export 'src/layout/ide_constraint_bucket_builder.dart';
export 'src/metrics/compact_metric_bar.dart';
export 'src/pane_widgets.dart';
export 'src/rows/ide_data_row.dart';
export 'src/rows/ide_key_value_row.dart';
export 'src/rows/ide_list_row.dart';
export 'src/rows/ide_row_divider.dart';
export 'src/rows/ide_row_group.dart';
export 'src/rows/ide_settings_row.dart';
export 'src/surfaces/ide_surface.dart';
export 'src/virtualization/ide_dynamic_sliver_list.dart';
export 'src/virtualization/ide_extent_index.dart';
export 'src/virtualization/ide_smooth_scroll_controller.dart';
export 'src/virtualization/ide_virtual_item.dart';
export 'src/virtualization/ide_virtual_list_controller.dart';
export 'src/virtualization/ide_virtual_scroll_coordinator.dart';
export 'src/virtualization/ide_virtual_scrollbar.dart';
export 'src/window_frame.dart';
export 'src/workbench/ide_page_body.dart';
export 'src/workbench/ide_page_header.dart';
export 'src/workbench/ide_retained_page_view.dart';
export 'src/workbench/ide_section.dart';
export 'src/workbench/ide_toolbar.dart';
export 'src/workbench/ide_workbench_scaffold.dart';
export 'src/zeta_ui_text_catalog.dart';
