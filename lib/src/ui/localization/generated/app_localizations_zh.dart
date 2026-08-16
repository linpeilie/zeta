// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Zeta';

  @override
  String localizationContractGreeting(String name) {
    return '你好 $name';
  }

  @override
  String get shadcnFormNotEmpty => '此项不能为空';

  @override
  String get shadcnInvalidValue => '值无效';

  @override
  String get shadcnInvalidEmail => '邮箱无效';

  @override
  String get shadcnInvalidURL => 'URL 无效';

  @override
  String shadcnFormLessThan(String value) {
    return '必须小于 $value';
  }

  @override
  String shadcnFormGreaterThan(String value) {
    return '必须大于 $value';
  }

  @override
  String shadcnFormLessThanOrEqualTo(String value) {
    return '必须小于或等于 $value';
  }

  @override
  String shadcnFormGreaterThanOrEqualTo(String value) {
    return '必须大于或等于 $value';
  }

  @override
  String get shadcnFormPhoneNumberInvalid => '电话号码无效';

  @override
  String get shadcnFormPhoneNumberEmpty => '请填写电话号码';

  @override
  String shadcnFormBetweenInclusively(String min, String max) {
    return '必须介于 $min 和 $max 之间（含边界）';
  }

  @override
  String shadcnFormBetweenExclusively(String min, String max) {
    return '必须介于 $min 和 $max 之间（不含边界）';
  }

  @override
  String shadcnFormLengthLessThan(String value) {
    return '至少 $value 个字符';
  }

  @override
  String shadcnFormLengthGreaterThan(String value) {
    return '最多 $value 个字符';
  }

  @override
  String get shadcnFormPasswordDigits => '至少包含一位数字';

  @override
  String get shadcnFormPasswordLowercase => '至少包含一个小写字母';

  @override
  String get shadcnFormPasswordUppercase => '至少包含一个大写字母';

  @override
  String get shadcnFormPasswordSpecial => '至少包含一个特殊字符';

  @override
  String get shadcnCommandSearch => '输入命令或搜索…';

  @override
  String get shadcnCommandEmpty => '未找到结果。';

  @override
  String get shadcnCommandMoveUp => '上移';

  @override
  String get shadcnCommandMoveDown => '下移';

  @override
  String get shadcnCommandActivate => '选择';

  @override
  String get shadcnDatePickerSelectYear => '选择年份';

  @override
  String get shadcnPlaceholderDatePicker => '选择日期';

  @override
  String get shadcnPlaceholderTimePicker => '选择时间';

  @override
  String get shadcnPlaceholderColorPicker => '选择颜色';

  @override
  String get shadcnPlaceholderDurationPicker => '选择时长';

  @override
  String get shadcnButtonCancel => '取消';

  @override
  String get shadcnButtonSave => '保存';

  @override
  String get shadcnButtonPrevious => '上一页';

  @override
  String get shadcnButtonNext => '下一页';

  @override
  String get shadcnTimeHour => '时';

  @override
  String get shadcnTimeMinute => '分';

  @override
  String get shadcnTimeSecond => '秒';

  @override
  String get shadcnTimeAM => 'AM';

  @override
  String get shadcnTimePM => 'PM';

  @override
  String get shadcnColorRed => '红';

  @override
  String get shadcnColorGreen => '绿';

  @override
  String get shadcnColorBlue => '蓝';

  @override
  String get shadcnColorAlpha => '透明';

  @override
  String get shadcnColorHue => '色相';

  @override
  String get shadcnColorSaturation => '饱和';

  @override
  String get shadcnColorValue => '明度';

  @override
  String get shadcnColorLightness => '亮度';

  @override
  String get shadcnMenuCut => '剪切';

  @override
  String get shadcnMenuCopy => '复制';

  @override
  String get shadcnMenuPaste => '粘贴';

  @override
  String get shadcnMenuSelectAll => '全选';

  @override
  String get shadcnMenuUndo => '撤销';

  @override
  String get shadcnMenuRedo => '重做';

  @override
  String get shadcnMenuDelete => '删除';

  @override
  String get shadcnMenuShare => '分享';

  @override
  String get shadcnMenuSearchWeb => '搜索网页';

  @override
  String get shadcnMenuLiveTextInput => '实况文本';

  @override
  String get shadcnRefreshTriggerPull => '下拉刷新';

  @override
  String get shadcnRefreshTriggerRelease => '松开刷新';

  @override
  String get shadcnRefreshTriggerRefreshing => '正在刷新…';

  @override
  String get shadcnRefreshTriggerComplete => '刷新完成';

  @override
  String get shadcnColorPickerTabRecent => '最近';

  @override
  String get shadcnColorPickerTabRGB => 'RGB';

  @override
  String get shadcnColorPickerTabHSV => 'HSV';

  @override
  String get shadcnColorPickerTabHSL => 'HSL';

  @override
  String get shadcnColorPickerTabHEX => 'HEX';

  @override
  String shadcnDataTableSelectedRows(String count, String total) {
    return '已选择 $count / $total 行。';
  }

  @override
  String get shadcnDataTableNext => '下一页';

  @override
  String get shadcnDataTablePrevious => '上一页';

  @override
  String get shadcnDataTableColumns => '列';

  @override
  String get shadcnTimeDaysAbbreviation => 'DD';

  @override
  String get shadcnTimeHoursAbbreviation => 'HH';

  @override
  String get shadcnTimeMinutesAbbreviation => 'MM';

  @override
  String get shadcnTimeSecondsAbbreviation => 'SS';

  @override
  String get shadcnDurationDay => '天';

  @override
  String get shadcnDurationHour => '小时';

  @override
  String get shadcnDurationMinute => '分钟';

  @override
  String get shadcnDurationSecond => '秒';

  @override
  String get shadcnAbbreviatedMonday => 'Mo';

  @override
  String get shadcnAbbreviatedTuesday => 'Tu';

  @override
  String get shadcnAbbreviatedWednesday => 'We';

  @override
  String get shadcnAbbreviatedThursday => 'Th';

  @override
  String get shadcnAbbreviatedFriday => 'Fr';

  @override
  String get shadcnAbbreviatedSaturday => 'Sa';

  @override
  String get shadcnAbbreviatedSunday => 'Su';

  @override
  String get shadcnMonthJanuary => 'January';

  @override
  String get shadcnMonthFebruary => 'February';

  @override
  String get shadcnMonthMarch => 'March';

  @override
  String get shadcnMonthApril => 'April';

  @override
  String get shadcnMonthMay => 'May';

  @override
  String get shadcnMonthJune => 'June';

  @override
  String get shadcnMonthJuly => 'July';

  @override
  String get shadcnMonthAugust => 'August';

  @override
  String get shadcnMonthSeptember => 'September';

  @override
  String get shadcnMonthOctober => 'October';

  @override
  String get shadcnMonthNovember => 'November';

  @override
  String get shadcnMonthDecember => 'December';

  @override
  String get shadcnAbbreviatedJanuary => 'Jan';

  @override
  String get shadcnAbbreviatedFebruary => 'Feb';

  @override
  String get shadcnAbbreviatedMarch => 'Mar';

  @override
  String get shadcnAbbreviatedApril => 'Apr';

  @override
  String get shadcnAbbreviatedMay => 'May';

  @override
  String get shadcnAbbreviatedJune => 'Jun';

  @override
  String get shadcnAbbreviatedJuly => 'Jul';

  @override
  String get shadcnAbbreviatedAugust => 'Aug';

  @override
  String get shadcnAbbreviatedSeptember => 'Sep';

  @override
  String get shadcnAbbreviatedOctober => 'Oct';

  @override
  String get shadcnAbbreviatedNovember => 'Nov';

  @override
  String get shadcnAbbreviatedDecember => 'Dec';
}
