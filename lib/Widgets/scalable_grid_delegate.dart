import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// A square grid that morphs continuously between integer column counts.
class ScalableGridDelegate extends SliverGridDelegate {
  const ScalableGridDelegate({
    required this.columnCount,
    this.crossAxisSpacing = 0,
    this.mainAxisSpacing = 0,
  }) : assert(columnCount >= 1);

  /// May be fractional. Child geometry is interpolated between the two
  /// surrounding integer-column layouts.
  final double columnCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final lowerCount = columnCount.floor();
    final upperCount = columnCount.ceil();

    return _ScalableGridLayout(
      lower: _GridMetrics(
        crossAxisCount: lowerCount,
        crossAxisExtent: constraints.crossAxisExtent,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
      ),
      upper: _GridMetrics(
        crossAxisCount: upperCount,
        crossAxisExtent: constraints.crossAxisExtent,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
      ),
      transition: columnCount - lowerCount,
      crossAxisExtent: constraints.crossAxisExtent,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(covariant ScalableGridDelegate oldDelegate) {
    return oldDelegate.columnCount != columnCount ||
        oldDelegate.crossAxisSpacing != crossAxisSpacing ||
        oldDelegate.mainAxisSpacing != mainAxisSpacing;
  }
}

class _GridMetrics {
  _GridMetrics({
    required this.crossAxisCount,
    required double crossAxisExtent,
    required double crossAxisSpacing,
    required double mainAxisSpacing,
  }) {
    childExtent =
        (crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1)) /
        crossAxisCount;
    crossAxisStride = childExtent + crossAxisSpacing;
    mainAxisStride = childExtent + mainAxisSpacing;
  }

  final int crossAxisCount;
  late final double childExtent;
  late final double crossAxisStride;
  late final double mainAxisStride;

  double scrollOffsetFor(int index) =>
      (index ~/ crossAxisCount) * mainAxisStride;

  double crossAxisOffsetFor(int index) =>
      (index % crossAxisCount) * crossAxisStride;

  int minIndexFor(double scrollOffset) => mainAxisStride > 0
      ? crossAxisCount * (scrollOffset ~/ mainAxisStride)
      : 0;

  int maxIndexFor(double scrollOffset) => mainAxisStride > 0
      ? math.max(0, crossAxisCount * (scrollOffset / mainAxisStride).ceil() - 1)
      : 0;

  double maxScrollOffset(int childCount) {
    if (childCount == 0) return 0;
    final rowCount = (childCount + crossAxisCount - 1) ~/ crossAxisCount;
    return mainAxisStride * (rowCount - 1) + childExtent;
  }
}

class _ScalableGridLayout extends SliverGridLayout {
  const _ScalableGridLayout({
    required this.lower,
    required this.upper,
    required this.transition,
    required this.crossAxisExtent,
    required this.reverseCrossAxis,
  });

  final _GridMetrics lower;
  final _GridMetrics upper;
  final double transition;
  final double crossAxisExtent;
  final bool reverseCrossAxis;

  double _lerp(double start, double end) => start + (end - start) * transition;

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    return math.min(
      lower.minIndexFor(scrollOffset),
      upper.minIndexFor(scrollOffset),
    );
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    return math.max(
      lower.maxIndexFor(scrollOffset),
      upper.maxIndexFor(scrollOffset),
    );
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final childExtent = _lerp(lower.childExtent, upper.childExtent);
    var crossAxisOffset = _lerp(
      lower.crossAxisOffsetFor(index),
      upper.crossAxisOffsetFor(index),
    );
    if (reverseCrossAxis) {
      crossAxisOffset = crossAxisExtent - crossAxisOffset - childExtent;
    }
    return SliverGridGeometry(
      scrollOffset: _lerp(
        lower.scrollOffsetFor(index),
        upper.scrollOffsetFor(index),
      ),
      crossAxisOffset: crossAxisOffset,
      mainAxisExtent: childExtent,
      crossAxisExtent: childExtent,
    );
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    return _lerp(
      lower.maxScrollOffset(childCount),
      upper.maxScrollOffset(childCount),
    );
  }
}
