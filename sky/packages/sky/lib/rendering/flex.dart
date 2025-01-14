// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:sky/rendering/box.dart';
import 'package:sky/rendering/object.dart';

export 'package:sky/rendering/object.dart' show EventDisposition;

class FlexBoxParentData extends BoxParentData with ContainerParentDataMixin<RenderBox> {
  int flex;

  void merge(FlexBoxParentData other) {
    if (other.flex != null)
      flex = other.flex;
    super.merge(other);
  }

  String toString() => '${super.toString()}; flex=$flex';
}

enum FlexDirection { horizontal, vertical }

enum FlexJustifyContent {
  start,
  end,
  center,
  spaceBetween,
  spaceAround,
}

enum FlexAlignItems {
  start,
  end,
  center,
  stretch,
  baseline,
}

typedef double _ChildSizingFunction(RenderBox child, BoxConstraints constraints);

class RenderFlex extends RenderBox with ContainerRenderObjectMixin<RenderBox, FlexBoxParentData>,
                                        RenderBoxContainerDefaultsMixin<RenderBox, FlexBoxParentData> {
  // lays out RenderBox children using flexible layout

  RenderFlex({
    List<RenderBox> children,
    FlexDirection direction: FlexDirection.horizontal,
    FlexJustifyContent justifyContent: FlexJustifyContent.start,
    FlexAlignItems alignItems: FlexAlignItems.center,
    TextBaseline textBaseline
  }) : _direction = direction,
       _justifyContent = justifyContent,
       _alignItems = alignItems,
       _textBaseline = textBaseline {
    addAll(children);
  }

  FlexDirection _direction;
  FlexDirection get direction => _direction;
  void set direction (FlexDirection value) {
    if (_direction != value) {
      _direction = value;
      markNeedsLayout();
    }
  }

  FlexJustifyContent _justifyContent;
  FlexJustifyContent get justifyContent => _justifyContent;
  void set justifyContent (FlexJustifyContent value) {
    if (_justifyContent != value) {
      _justifyContent = value;
      markNeedsLayout();
    }
  }

  FlexAlignItems _alignItems;
  FlexAlignItems get alignItems => _alignItems;
  void set alignItems (FlexAlignItems value) {
    if (_alignItems != value) {
      _alignItems = value;
      markNeedsLayout();
    }
  }

  // Set during layout if overflow occurred on the main axis
  TextBaseline _textBaseline;
  TextBaseline get textBaseline => _textBaseline;
  void set textBaseline (TextBaseline value) {
    if (_textBaseline != value) {
      _textBaseline = value;
      markNeedsLayout();
    }
  }

  double _overflow;

  void setupParentData(RenderBox child) {
    if (child.parentData is! FlexBoxParentData)
      child.parentData = new FlexBoxParentData();
  }

  double _getIntrinsicSize({ BoxConstraints constraints,
                             FlexDirection sizingDirection,
                             _ChildSizingFunction childSize }) {
    // http://www.w3.org/TR/2015/WD-css-flexbox-1-20150514/#intrinsic-sizes
    if (_direction == sizingDirection) {
      // INTRINSIC MAIN SIZE
      // Intrinsic main size is the smallest size the flex container can take
      // while maintaining the min/max-content contributions of its flex items.
      BoxConstraints childConstraints;
      switch(_direction) {
        case FlexDirection.horizontal:
          childConstraints = new BoxConstraints(maxHeight: constraints.maxHeight);
          break;
        case FlexDirection.vertical:
          childConstraints = new BoxConstraints(maxWidth: constraints.maxWidth);
          break;
      }

      double totalFlex = 0.0;
      double inflexibleSpace = 0.0;
      double maxFlexFractionSoFar = 0.0;
      RenderBox child = firstChild;
      while (child != null) {
        int flex = _getFlex(child);
        totalFlex += flex;
        if (flex > 0) {
          double flexFraction = childSize(child, childConstraints) / _getFlex(child);
          maxFlexFractionSoFar = math.max(maxFlexFractionSoFar, flexFraction);
        } else {
          inflexibleSpace += childSize(child, childConstraints);
        }
        assert(child.parentData is FlexBoxParentData);
        child = child.parentData.nextSibling;
      }
      double mainSize = maxFlexFractionSoFar * totalFlex + inflexibleSpace;

      // Ensure that we don't violate the given constraints with our result
      switch(_direction) {
        case FlexDirection.horizontal:
          return constraints.constrainWidth(mainSize);
        case FlexDirection.vertical:
          return constraints.constrainHeight(mainSize);
      }
    } else {
      // INTRINSIC CROSS SIZE
      // The spec wants us to perform layout into the given available main-axis
      // space and return the cross size. That's too expensive, so instead we
      // size inflexible children according to their max intrinsic size in the
      // main direction and use those constraints to determine their max
      // intrinsic size in the cross direction. We don't care if the caller
      // asked for max or min -- the answer is always computed using the
      // max size in the main direction.

      double availableMainSpace;
      BoxConstraints childConstraints;
      switch(_direction) {
        case FlexDirection.horizontal:
          childConstraints = new BoxConstraints(maxWidth: constraints.maxWidth);
          availableMainSpace = constraints.maxWidth;
          break;
        case FlexDirection.vertical:
          childConstraints = new BoxConstraints(maxHeight: constraints.maxHeight);
          availableMainSpace = constraints.maxHeight;
          break;
      }

      // Get inflexible space using the max in the main direction
      int totalFlex = 0;
      double inflexibleSpace = 0.0;
      double maxCrossSize = 0.0;
      RenderBox child = firstChild;
      while (child != null) {
        int flex = _getFlex(child);
        totalFlex += flex;
        double mainSize;
        double crossSize;
        if (flex == 0) {
          switch (_direction) {
              case FlexDirection.horizontal:
                mainSize = child.getMaxIntrinsicWidth(childConstraints);
                BoxConstraints widthConstraints =
                  new BoxConstraints(minWidth: mainSize, maxWidth: mainSize);
                crossSize = child.getMaxIntrinsicHeight(widthConstraints);
                break;
              case FlexDirection.vertical:
                mainSize = child.getMaxIntrinsicHeight(childConstraints);
                BoxConstraints heightConstraints =
                  new BoxConstraints(minWidth: mainSize, maxWidth: mainSize);
                crossSize = child.getMaxIntrinsicWidth(heightConstraints);
                break;
          }
          inflexibleSpace += mainSize;
          maxCrossSize = math.max(maxCrossSize, crossSize);
        }
        assert(child.parentData is FlexBoxParentData);
        child = child.parentData.nextSibling;
      }

      // Determine the spacePerFlex by allocating the remaining available space
      double spacePerFlex = (availableMainSpace - inflexibleSpace) / totalFlex;

      // Size remaining items, find the maximum cross size
      child = firstChild;
      while (child != null) {
        int flex = _getFlex(child);
        if (flex > 0) {
          double childMainSize = spacePerFlex * flex;
          double crossSize;
          switch (_direction) {
            case FlexDirection.horizontal:
              BoxConstraints childConstraints =
                new BoxConstraints(minWidth: childMainSize, maxWidth: childMainSize);
              crossSize = child.getMaxIntrinsicHeight(childConstraints);
              break;
            case FlexDirection.vertical:
              BoxConstraints childConstraints =
                new BoxConstraints(minHeight: childMainSize, maxHeight: childMainSize);
              crossSize = child.getMaxIntrinsicWidth(childConstraints);
              break;
          }
          maxCrossSize = math.max(maxCrossSize, crossSize);
        }
        assert(child.parentData is FlexBoxParentData);
        child = child.parentData.nextSibling;
      }

      // Ensure that we don't violate the given constraints with our result
      switch(_direction) {
        case FlexDirection.horizontal:
          return constraints.constrainHeight(maxCrossSize);
        case FlexDirection.vertical:
          return constraints.constrainWidth(maxCrossSize);
      }
    }
  }

  double getMinIntrinsicWidth(BoxConstraints constraints) {
    return _getIntrinsicSize(
      constraints: constraints,
      sizingDirection: FlexDirection.horizontal,
      childSize: (c, innerConstraints) => c.getMinIntrinsicWidth(innerConstraints)
    );
  }

  double getMaxIntrinsicWidth(BoxConstraints constraints) {
    return _getIntrinsicSize(
      constraints: constraints,
      sizingDirection: FlexDirection.horizontal,
      childSize: (c, innerConstraints) => c.getMaxIntrinsicWidth(innerConstraints)
    );
  }

  double getMinIntrinsicHeight(BoxConstraints constraints) {
    return _getIntrinsicSize(
      constraints: constraints,
      sizingDirection: FlexDirection.vertical,
      childSize: (c, innerConstraints) => c.getMinIntrinsicHeight(innerConstraints)
    );
  }

  double getMaxIntrinsicHeight(BoxConstraints constraints) {
    return _getIntrinsicSize(
      constraints: constraints,
      sizingDirection: FlexDirection.vertical,
      childSize: (c, innerConstraints) => c.getMaxIntrinsicHeight(innerConstraints));
  }

  double computeDistanceToActualBaseline(TextBaseline baseline) {
    if (_direction == FlexDirection.horizontal)
      return defaultComputeDistanceToHighestActualBaseline(baseline);
    return defaultComputeDistanceToFirstActualBaseline(baseline);
  }

  int _getFlex(RenderBox child) {
    assert(child.parentData is FlexBoxParentData);
    return child.parentData.flex != null ? child.parentData.flex : 0;
  }

  double _getCrossSize(RenderBox child) {
    return (_direction == FlexDirection.horizontal) ? child.size.height : child.size.width;
  }

  double _getMainSize(RenderBox child) {
    return (_direction == FlexDirection.horizontal) ? child.size.width : child.size.height;
  }

  void performLayout() {
    // Based on http://www.w3.org/TR/css-flexbox-1/ Section 9.7 Resolving Flexible Lengths
    // Steps 1-3. Determine used flex factor, size inflexible items, calculate free space
    int totalFlex = 0;
    int totalChildren = 0;
    assert(constraints != null);
    final double mainSize = (_direction == FlexDirection.horizontal) ? constraints.maxWidth : constraints.maxHeight;
    double crossSize = 0.0;  // This will be determined after laying out the children
    double freeSpace = mainSize;
    RenderBox child = firstChild;
    while (child != null) {
      assert(child.parentData is FlexBoxParentData);
      totalChildren++;
      int flex = _getFlex(child);
      if (flex > 0) {
        totalFlex += child.parentData.flex;
      } else {
        BoxConstraints innerConstraints;
        if (alignItems == FlexAlignItems.stretch) {
          switch (_direction) {
            case FlexDirection.horizontal:
              innerConstraints = new BoxConstraints(maxWidth: constraints.maxWidth,
                                                    minHeight: constraints.minHeight,
                                                    maxHeight: constraints.maxHeight);
              break;
            case FlexDirection.vertical:
              innerConstraints = new BoxConstraints(minWidth: constraints.minWidth,
                                                    maxWidth: constraints.maxWidth,
                                                    maxHeight: constraints.maxHeight);
              break;
          }
        } else {
          innerConstraints = constraints.loosen();
        }
        child.layout(innerConstraints, parentUsesSize: true);
        freeSpace -= _getMainSize(child);
        crossSize = math.max(crossSize, _getCrossSize(child));
      }
      child = child.parentData.nextSibling;
    }
    _overflow = math.max(0.0, -freeSpace);
    freeSpace = math.max(0.0, freeSpace);

    // Steps 4-5. Distribute remaining space to flexible children.
    double spacePerFlex = totalFlex > 0 ? (freeSpace / totalFlex) : 0.0;
    double usedSpace = 0.0;
    double maxBaselineDistance = 0.0;
    child = firstChild;
    while (child != null) {
      int flex = _getFlex(child);
      if (flex > 0) {
        double spaceForChild = spacePerFlex * flex;
        BoxConstraints innerConstraints;
        switch (_direction) {
          case FlexDirection.horizontal:
            innerConstraints = new BoxConstraints(maxHeight: constraints.maxHeight,
                                                  minWidth: spaceForChild,
                                                  maxWidth: spaceForChild);
            break;
          case FlexDirection.vertical:
            innerConstraints = new BoxConstraints(minHeight: spaceForChild,
                                                  maxHeight: spaceForChild,
                                                  maxWidth: constraints.maxWidth);
            break;
        }
        child.layout(innerConstraints, parentUsesSize: true);
        usedSpace += _getMainSize(child);
        crossSize = math.max(crossSize, _getCrossSize(child));
      }
      if (alignItems == FlexAlignItems.baseline) {
        assert(textBaseline != null);
        double distance = child.getDistanceToBaseline(textBaseline, onlyReal: true);
        if (distance != null)
          maxBaselineDistance = math.max(maxBaselineDistance, distance);
      }
      assert(child.parentData is FlexBoxParentData);
      child = child.parentData.nextSibling;
    }

    // Section 8.2: Main Axis Alignment using the justify-content property
    double remainingSpace = math.max(0.0, freeSpace - usedSpace);
    double leadingSpace;
    double betweenSpace;
    switch (_justifyContent) {
      case FlexJustifyContent.start:
        leadingSpace = 0.0;
        betweenSpace = 0.0;
        break;
      case FlexJustifyContent.end:
        leadingSpace = remainingSpace;
        betweenSpace = 0.0;
        break;
      case FlexJustifyContent.center:
        leadingSpace = remainingSpace / 2.0;
        betweenSpace = 0.0;
        break;
      case FlexJustifyContent.spaceBetween:
        leadingSpace = 0.0;
        betweenSpace = totalChildren > 1 ? remainingSpace / (totalChildren - 1) : 0.0;
        break;
      case FlexJustifyContent.spaceAround:
        betweenSpace = totalChildren > 0 ? remainingSpace / totalChildren : 0.0;
        leadingSpace = betweenSpace / 2.0;
        break;
    }

    switch (_direction) {
      case FlexDirection.horizontal:
        size = constraints.constrain(new Size(mainSize, crossSize));
        crossSize = size.height;
        break;
      case FlexDirection.vertical:
        size = constraints.constrain(new Size(crossSize, mainSize));
        crossSize = size.width;
        break;
    }

    // Position elements
    double childMainPosition = leadingSpace;
    child = firstChild;
    while (child != null) {
      assert(child.parentData is FlexBoxParentData);
      double childCrossPosition;
      switch (_alignItems) {
        case FlexAlignItems.stretch:
        case FlexAlignItems.start:
          childCrossPosition = 0.0;
          break;
        case FlexAlignItems.end:
          childCrossPosition = crossSize - _getCrossSize(child);
          break;
        case FlexAlignItems.center:
          childCrossPosition = crossSize / 2.0 - _getCrossSize(child) / 2.0;
          break;
        case FlexAlignItems.baseline:
          childCrossPosition = 0.0;
          if (_direction == FlexDirection.horizontal) {
            assert(textBaseline != null);
            double distance = child.getDistanceToBaseline(textBaseline, onlyReal: true);
            if (distance != null)
              childCrossPosition = maxBaselineDistance - distance;
          }
          break;
      }
      switch (_direction) {
        case FlexDirection.horizontal:
          child.parentData.position = new Point(childMainPosition, childCrossPosition);
          break;
        case FlexDirection.vertical:
          child.parentData.position = new Point(childCrossPosition, childMainPosition);
          break;
      }
      childMainPosition += _getMainSize(child) + betweenSpace;
      child = child.parentData.nextSibling;
    }
  }

  void hitTestChildren(HitTestResult result, { Point position }) {
    defaultHitTestChildren(result, position: position);
  }

  void paint(PaintingContext context, Offset offset) {
    if (_overflow > 0) {
      context.canvas.save();
      context.canvas.clipRect(offset & size);
      defaultPaint(context, offset);
      context.canvas.restore();
    } else {
      defaultPaint(context, offset);
    }
  }

  void debugPaintSize(PaintingContext context, Offset offset) {
    super.debugPaintSize(context, offset);
    if (_overflow <= 0)
      return;

    // Draw a red rectangle over the overflow area in debug mode
    // You should be using a Clip if you want to clip your children
    Paint paint = new Paint()..color = const Color(0x7FFF0000);
    Rect overflowRect;
    switch(direction) {
      case FlexDirection.horizontal:
        overflowRect = offset + new Offset(size.width, 0.0) &
                       new Size(_overflow, size.height);
        break;
      case FlexDirection.vertical:
        overflowRect = offset + new Offset(0.0, size.height) &
                       new Size(size.width, _overflow);
        break;
    }
    context.canvas.drawRect(overflowRect, paint);
  }
}
