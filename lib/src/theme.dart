import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Colours and text size for a `MarketChart`.
///
/// Use [MarketChartTheme.dark] or [MarketChartTheme.light] as a starting point
/// and change what you need with [copyWith].
@immutable
class MarketChartTheme {
  /// Creates a theme. Every colour is required; see [dark] and [light].
  const MarketChartTheme({
    required this.backgroundColor,
    required this.bullColor,
    required this.bearColor,
    required this.gridColor,
    required this.textColor,
    required this.crosshairColor,
    required this.labelBackgroundColor,
    required this.labelTextColor,
    required this.lineColor,
    this.volumeOpacity = 0.4,
    this.fontSize = 11,
    this.fontFamily,
    this.indicatorColors = defaultIndicatorColors,
  });

  /// The colours moving averages and Bollinger Bands use when they don't set
  /// their own: orange, blue, purple, cyan, pink and green.
  static const defaultIndicatorColors = [
    Color(0xFFFF9800),
    Color(0xFF2196F3),
    Color(0xFFAB47BC),
    Color(0xFF00BCD4),
    Color(0xFFEC407A),
    Color(0xFF7CB342),
  ];

  /// A dark theme.
  static const dark = MarketChartTheme(
    backgroundColor: Color(0xFF131722),
    bullColor: Color(0xFF26A69A),
    bearColor: Color(0xFFEF5350),
    gridColor: Color(0x1AFFFFFF),
    textColor: Color(0xFFB2B5BE),
    crosshairColor: Color(0xFF9598A1),
    labelBackgroundColor: Color(0xFF363A45),
    labelTextColor: Color(0xFFFFFFFF),
    lineColor: Color(0xFF2962FF),
  );

  /// A light theme.
  static const light = MarketChartTheme(
    backgroundColor: Color(0xFFFFFFFF),
    bullColor: Color(0xFF089981),
    bearColor: Color(0xFFF23645),
    gridColor: Color(0x14000000),
    textColor: Color(0xFF434651),
    crosshairColor: Color(0xFF9598A1),
    labelBackgroundColor: Color(0xFF131722),
    labelTextColor: Color(0xFFFFFFFF),
    lineColor: Color(0xFF2962FF),
  );

  /// Fill behind the whole chart.
  final Color backgroundColor;

  /// Colour for candles that closed up.
  final Color bullColor;

  /// Colour for candles that closed down.
  final Color bearColor;

  /// Grid lines.
  final Color gridColor;

  /// Axis labels and the price summary.
  final Color textColor;

  /// The crosshair lines.
  final Color crosshairColor;

  /// Background of the crosshair price and time labels.
  final Color labelBackgroundColor;

  /// Text on labels with a coloured background.
  final Color labelTextColor;

  /// Line and area charts.
  final Color lineColor;

  /// Opacity of the volume bars, from 0 to 1.
  final double volumeOpacity;

  /// Font size for all chart text.
  final double fontSize;

  /// Font for all chart text. When null, the chart uses the app's font (from
  /// the surrounding `DefaultTextStyle`).
  final String? fontFamily;

  /// Colours for moving averages and Bollinger Bands that don't set their
  /// own, used in the order the indicators are listed.
  final List<Color> indicatorColors;

  /// Text style for axis labels.
  TextStyle get textStyle => TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontFamily: fontFamily,
        height: 1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Returns a copy with the given fields replaced.
  MarketChartTheme copyWith({
    Color? backgroundColor,
    Color? bullColor,
    Color? bearColor,
    Color? gridColor,
    Color? textColor,
    Color? crosshairColor,
    Color? labelBackgroundColor,
    Color? labelTextColor,
    Color? lineColor,
    double? volumeOpacity,
    double? fontSize,
    String? fontFamily,
    List<Color>? indicatorColors,
  }) =>
      MarketChartTheme(
        backgroundColor: backgroundColor ?? this.backgroundColor,
        bullColor: bullColor ?? this.bullColor,
        bearColor: bearColor ?? this.bearColor,
        gridColor: gridColor ?? this.gridColor,
        textColor: textColor ?? this.textColor,
        crosshairColor: crosshairColor ?? this.crosshairColor,
        labelBackgroundColor: labelBackgroundColor ?? this.labelBackgroundColor,
        labelTextColor: labelTextColor ?? this.labelTextColor,
        lineColor: lineColor ?? this.lineColor,
        volumeOpacity: volumeOpacity ?? this.volumeOpacity,
        fontSize: fontSize ?? this.fontSize,
        fontFamily: fontFamily ?? this.fontFamily,
        indicatorColors: indicatorColors ?? this.indicatorColors,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarketChartTheme &&
          other.backgroundColor == backgroundColor &&
          other.bullColor == bullColor &&
          other.bearColor == bearColor &&
          other.gridColor == gridColor &&
          other.textColor == textColor &&
          other.crosshairColor == crosshairColor &&
          other.labelBackgroundColor == labelBackgroundColor &&
          other.labelTextColor == labelTextColor &&
          other.lineColor == lineColor &&
          other.volumeOpacity == volumeOpacity &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          listEquals(other.indicatorColors, indicatorColors);

  @override
  int get hashCode => Object.hash(
        backgroundColor,
        bullColor,
        bearColor,
        gridColor,
        textColor,
        crosshairColor,
        labelBackgroundColor,
        labelTextColor,
        lineColor,
        volumeOpacity,
        fontSize,
        fontFamily,
        Object.hashAll(indicatorColors),
      );
}
