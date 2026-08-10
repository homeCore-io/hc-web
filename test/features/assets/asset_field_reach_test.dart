import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';

/// Which fields can actually take a file.
///
/// Six features stored an address with nowhere to put the file behind it, and
/// the note saying so was written next to each one separately. The failure this
/// guards is the same shape: adding the picker to three of them and leaving the
/// fourth with a bare text box, which nobody would notice until they tried.

void main() {
  setUpAll(registerBuiltinDashboardWidgets);

  test('a picture takes a file; a stream and a page do not', () {
    // The distinction that made a new config kind necessary rather than
    // reusing `url`: a camera points at a stream and an embed at a page, and
    // neither is something you could choose from disk.
    WidgetConfigKind kindOf(String widget, String field) =>
        WidgetRegistry.lookup(widget)!
            .configFields
            .firstWhere((f) => f.name == field)
            .kind;

    expect(kindOf('image', 'url'), WidgetConfigKind.image);
    expect(kindOf('camera_video', 'url'), WidgetConfigKind.url,
        reason: 'a camera stream is not a file you upload');
    expect(kindOf('web_embed', 'url'), WidgetConfigKind.url,
        reason: 'a web page is not a file you upload');
  });

  test('the image widget still requires its address', () {
    // The picker changed how the string gets filled in, not whether it must be.
    final f = WidgetRegistry.lookup('image')!
        .configFields
        .firstWhere((f) => f.name == 'url');
    expect(f.required, isTrue);
  });
}
