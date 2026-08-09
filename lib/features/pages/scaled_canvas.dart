import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Draws its child at [scale] **and takes the scaled size as its own**.
///
/// `Transform.scale` does only the first half: it paints at a scale but lays
/// out at the child's unscaled size. Inside a scroll view that is a quiet lie —
/// the scroll extent describes a canvas that is no longer that size, so a
/// zoomed-in layout simply cannot be scrolled to its right-hand edge, and a
/// zoomed-out one leaves a band of dead space where the rest of it used to be.
/// Neither shows an error. You just cannot reach part of your own page.
///
/// So this reports what is actually drawn. The child is laid out with the
/// incoming constraints divided by the scale — a 1600px desktop canvas stays a
/// 1600px canvas, and only the drawing of it changes size — and hit tests go
/// back through the same transform, which is what keeps a card draggable at
/// 50% and at 200%.
class ScaledCanvas extends SingleChildRenderObjectWidget {
  const ScaledCanvas({
    super.key,
    required this.scale,
    required Widget super.child,
  });

  final double scale;

  @override
  RenderScaledCanvas createRenderObject(BuildContext context) =>
      RenderScaledCanvas(scale);

  @override
  void updateRenderObject(
          BuildContext context, RenderScaledCanvas renderObject) =>
      renderObject.scale = scale;
}

class RenderScaledCanvas extends RenderProxyBox {
  RenderScaledCanvas(this._scale);

  double _scale;
  double get scale => _scale;
  set scale(double value) {
    if (value == _scale) return;
    _scale = value;
    markNeedsLayout();
  }

  Matrix4 _transform = Matrix4.identity();

  static BoxConstraints _undoScale(BoxConstraints c, double scale) =>
      BoxConstraints(
        minWidth: c.minWidth / scale,
        maxWidth: c.maxWidth == double.infinity
            ? double.infinity
            : c.maxWidth / scale,
        minHeight: c.minHeight / scale,
        maxHeight: c.maxHeight == double.infinity
            ? double.infinity
            : c.maxHeight / scale,
      );

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_undoScale(constraints, _scale), parentUsesSize: true);
    _transform = Matrix4.identity()..scaleByDouble(_scale, _scale, 1, 1);
    size = constraints.constrain(child.size * _scale);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scale == 1.0) {
      context.paintChild(child, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (inner, o) => inner.paintChild(child, o),
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (inner, p) => child.hitTest(inner, position: p),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_transform);
}
