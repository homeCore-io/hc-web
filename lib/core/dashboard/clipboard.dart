/// Taking elements off one page and putting them on another.
///
/// The designer could already duplicate a card, and that is a different thing:
/// duplicating is *within* a page, and the most common way anyone builds a
/// second page is out of parts of the first. Without this, moving a tuned gauge
/// or an SVG binding or a code element to another page means adding it from the
/// library again and redoing every setting — real work, retyped, with the
/// original sitting one tab away.
///
/// **The system clipboard, not an in-memory one.** An app-local clipboard would
/// have been less code and would have worked between pages, which is most of
/// the value. It would not work between two windows, and it would not let you
/// keep a card in a scratch file, mail one to somebody, or read what you are
/// about to paste. The payload is JSON for the same reason: a format a person
/// can open is a format they can fix.
///
/// Everything here is pure. The widgets that read the clipboard live in
/// `page_screen`; what is encoded, what a legal payload is, and how a paste
/// lands are decided here, where they can be tested without pumping anything.
library;

import 'dart:convert';

import '../models/dashboard.dart';
import 'grid_engine.dart';
import 'groups.dart';

/// Marks a payload as ours, and says which shape it is in.
///
/// A person can put anything on a clipboard. Checking for this key is what
/// separates "not our data" — paste quietly does nothing — from "our data,
/// damaged", which is worth being loud about. Without it, every stray string
/// would parse as an empty page and paste would look broken rather than
/// inapplicable.
const clipboardKind = 'homecore.dashboard.cards';

/// Bumped only when an older build could not read a newer payload correctly.
/// Absent or unknown reads as incompatible rather than as version 1: guessing
/// would paste a card with settings silently dropped.
const clipboardVersion = 1;

/// One element on the clipboard: what it is, and where it sat relative to the
/// others that were copied with it.
///
/// The geometry is **relative to the top-left of the whole copied cluster**, so
/// a paste can put the cluster anywhere and keep its internal arrangement. Two
/// cards copied side by side stay side by side, on a page with different
/// columns, at a different scroll position, in a different window.
typedef ClipboardCard = ({
  DashboardWidgetModel widget,
  int dx,
  int dy,
  int w,
  int h,
  DashboardRect? rect,
  String? group,
});

/// What came off the clipboard.
typedef ClipboardCards = ({List<ClipboardCard> cards, bool composed});

/// Encodes [ids] out of a page. Returns null when there is nothing to copy.
///
/// [composed] says whether the layout these came from was a composition, which
/// decides whether the rectangles mean anything on the way back in — see
/// [pasteInto].
String? encodeCards({
  required Iterable<String> ids,
  required Map<String, DashboardWidgetModel> widgets,
  required List<GridItem> items,
  Map<String, String?> paths = const {},
  bool composed = false,
}) {
  final picked = [
    for (final i in items)
      if (ids.contains(i.id)) i,
  ];
  if (picked.isEmpty) return null;

  // The cluster's own origin. Relative geometry is what makes a paste
  // position-independent; absolute cells would land the second copy wherever
  // the first happened to be, which is only right by accident.
  var left = picked.first.x, top = picked.first.y;
  for (final i in picked) {
    if (i.x < left) left = i.x;
    if (i.y < top) top = i.y;
  }
  var rectLeft = 0.0, rectTop = 0.0, seenRect = false;
  for (final i in picked) {
    final r = i.rect;
    if (r == null) continue;
    if (!seenRect || r.x < rectLeft) rectLeft = r.x;
    if (!seenRect || r.y < rectTop) rectTop = r.y;
    seenRect = true;
  }

  return jsonEncode({
    'kind': clipboardKind,
    'version': clipboardVersion,
    'composed': composed,
    'cards': [
      for (final i in picked)
        if (widgets[i.id] case final w?)
          {
            'widget': w.toJson(),
            'dx': i.x - left,
            'dy': i.y - top,
            'w': i.w,
            'h': i.h,
            if (i.rect case final r?)
              'rect': DashboardRect(
                x: r.x - rectLeft,
                y: r.y - rectTop,
                w: r.w,
                h: r.h,
              ).toJson(),
            if (paths[i.id] case final g?) 'group': g,
          },
    ],
  });
}

/// Reads a payload. Null for anything that is not ours or cannot be trusted.
///
/// Deliberately strict. A half-understood card pastes as a card with settings
/// missing, and a card that quietly lost its config is worse than a paste that
/// declined to happen — the first looks like your work, the second looks like
/// a refusal you can act on.
ClipboardCards? decodeCards(String? text) {
  if (text == null || text.isEmpty) return null;
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (_) {
    return null;
  }
  if (raw is! Map) return null;
  if (raw['kind'] != clipboardKind) return null;
  if (raw['version'] != clipboardVersion) return null;
  final list = raw['cards'];
  if (list is! List) return null;

  final cards = <ClipboardCard>[];
  for (final entry in list) {
    if (entry is! Map) continue;
    final widget = entry['widget'];
    if (widget is! Map) continue;
    final DashboardWidgetModel model;
    try {
      model = DashboardWidgetModel.fromJson(Map<String, dynamic>.from(widget));
    } catch (_) {
      continue;
    }
    cards.add((
      widget: model,
      dx: _int(entry['dx']),
      dy: _int(entry['dy']),
      w: _int(entry['w'], fallback: 1).clamp(1, 64),
      h: _int(entry['h'], fallback: 1).clamp(1, 64),
      rect: DashboardRect.fromJson(entry['rect']),
      group: normalisePath(entry['group']),
    ));
  }
  if (cards.isEmpty) return null;
  return (cards: cards, composed: raw['composed'] == true);
}

int _int(Object? v, {int fallback = 0}) =>
    v is num && v.isFinite ? v.toInt() : fallback;

/// What a paste produces: fresh elements, ready to be added.
typedef Pasted = ({
  Map<String, DashboardWidgetModel> widgets,
  List<GridItem> items,
});

/// Lands [cards] on a page at [atX], [atY], with new identities.
///
/// **Ids are always regenerated.** A widget id is unique within a page, so
/// pasting a card back onto the page it came from would otherwise collide with
/// itself — and core rejects the whole dashboard, not the one card. [stamp]
/// makes the new ids, so a test can be deterministic and the app can use the
/// clock.
///
/// [columns] clamps the arrangement into the target's grid. A three-column card
/// pasted onto a four-column phone becomes as wide as fits, which is the same
/// rule deriving a layout follows.
///
/// [composedTarget] decides the rectangles. Copying a composition into a plain
/// grid drops them — a rectangle stated on a 1600-wide canvas means nothing on
/// a page that has none — and the cells come through instead, which is exactly
/// the fallback the whole two-representation design exists for.
///
/// [taken] are the group paths already on the target page; a copied group whose
/// name is in use is renamed rather than merged, because two groups that happen
/// to share a name are not the same group.
Pasted pasteInto({
  required ClipboardCards cards,
  required int columns,
  required int atX,
  required int atY,
  required String Function(int index) stamp,
  bool composedTarget = false,
  Set<String> taken = const {},
}) {
  final widgets = <String, DashboardWidgetModel>{};
  final items = <GridItem>[];

  // One rename per distinct copied path, decided up front, so two members of
  // the same group land in the *same* renamed group rather than in two.
  final renamed = <String, String>{};
  final claimed = {...taken};
  for (final card in cards.cards) {
    final path = card.group;
    if (path == null || renamed.containsKey(path)) continue;
    final next = claimed.contains(path) ? uniqueName(path, claimed) : path;
    renamed[path] = next;
    claimed.add(next);
  }

  for (var i = 0; i < cards.cards.length; i++) {
    final card = cards.cards[i];
    final id = stamp(i);
    final w = card.w.clamp(1, columns);
    final x = (atX + card.dx).clamp(0, (columns - w).clamp(0, columns));
    final group = card.group == null ? null : renamed[card.group!];

    widgets[id] = card.widget.copyWith(
      id: id,
      config: group == null
          ? withGroup(card.widget.config, null)
          : withGroup(card.widget.config, group),
    );
    items.add(GridItem(
      id: id,
      x: x,
      y: atY + card.dy,
      w: w,
      h: card.h,
      // Only when both ends are compositions. Carrying a rectangle onto a page
      // with no canvas would place it in units that page does not have.
      rect: cards.composed && composedTarget && card.rect != null
          ? DashboardRect(
              x: card.rect!.x,
              y: card.rect!.y,
              w: card.rect!.w,
              h: card.rect!.h,
            )
          : null,
    ));
  }
  return (widgets: widgets, items: items);
}
