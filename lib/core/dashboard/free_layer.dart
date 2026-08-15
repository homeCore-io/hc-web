/// Whether an element sits *in* the grid or *above* it.
///
/// Arc 1 of the designer's second pass, and the change that stops every page
/// being a mosaic. Until now two cards could never occupy the same cell —
/// `GridEngine` pushed one of them out of the way — so a page was a tiling of
/// rectangles by construction and no arrangement of tools could make it
/// anything else. A reading over a photograph, a control floating on a floor
/// plan, a headline across a hero: none of them were expressible.
///
/// **Core never forbade this.** It validates `x,y ≥ 0`, `w,h > 0`,
/// `x + w ≤ columns` and one placement per widget, and says nothing about
/// overlap. The rule was ours, in `grid_engine.dart`. So this arc is a client
/// change with no schema behind it.
///
/// **It rides in the widget's `config`**, like [CardStyle] and for the same
/// reason: `DashboardWidget` is id, type, title, subtitle, refresh policy and
/// config, and core stores the object verbatim. Absent means grounded, so every
/// page already saved is byte-identical and looks exactly as it did.
///
/// **Lifting is a property of the element, not of the layout.** A card lifted
/// above the grid is lifted at every breakpoint. Per-breakpoint lifting is
/// expressible later — it would move these keys into the placement — but a
/// design decision that changes when you rotate a tablet is not one anybody
/// asked for.
library;

/// What a person can ask of an element's place in the stack.
///
/// A named request rather than a new config: the inspector and the card menu
/// both say *what was asked for*, and one place — the page — knows the heights
/// in use and works out the number. Two surfaces each doing their own z
/// arithmetic is two surfaces that can disagree about what "forward" means.
enum StackMove {
  lift('Float above the grid'),
  ground('Put back in the grid'),
  front('Bring to front'),
  forward('Bring forward'),
  backward('Send backward'),
  back('Send to back');

  const StackMove(this.label);

  final String label;
}

/// Where the two keys live inside `config`.
const freeLayerKey = 'layer';
const freeLayerValue = 'free';
const zKey = 'z';

/// True when this element floats above the grid.
bool isFloating(Map<String, dynamic> config) =>
    config[freeLayerKey] == freeLayerValue;

/// How high it floats. Grounded elements are all at 0 and never compared.
///
/// Clamped on the way out rather than trusted: a hand-edited document with
/// `z: 1e9` would otherwise sort fine and then overflow an int somewhere less
/// forgiving.
int zOf(Map<String, dynamic> config) {
  final raw = config[zKey];
  if (raw is! num) return 0;
  return raw.toInt().clamp(-999, 999);
}

/// [config] with this element lifted above the grid.
Map<String, dynamic> lift(Map<String, dynamic> config, {int z = 1}) => {
      ...config,
      freeLayerKey: freeLayerValue,
      zKey: z.clamp(-999, 999),
    };

/// [config] with it put back in the grid.
///
/// Both keys go, so a card lifted and then grounded leaves the document exactly
/// as it found it — the same rule [CardStyle] follows, and what keeps a page's
/// JSON from accumulating a record of every idle click.
Map<String, dynamic> ground(Map<String, dynamic> config) {
  final next = {...config};
  next.remove(freeLayerKey);
  next.remove(zKey);
  return next;
}

/// [config] at a new height, staying lifted.
Map<String, dynamic> withZ(Map<String, dynamic> config, int z) =>
    lift(config, z: z);

/// Where [id] lands when it is sent one step in [direction] among [zs].
///
/// Not `z ± 1`: two elements can share a height — nothing stops it and nothing
/// should — and stepping by one would swap them into the same value again and
/// look like the control does nothing. This finds the next *distinct* height in
/// that direction and steps past it, which is what "bring forward" means when
/// you are looking at the screen rather than at the numbers.
int stepZ(int current, Iterable<int> zs, int direction) {
  final others = zs.toList()..sort();
  if (direction > 0) {
    for (final z in others) {
      if (z > current) return z + 1;
    }
    return current + 1;
  }
  for (final z in others.reversed) {
    if (z < current) return z - 1;
  }
  return current - 1;
}

/// The top and bottom of a stack, for *bring to front* and *send to back*.
int frontZ(Iterable<int> zs) =>
    zs.isEmpty ? 1 : zs.reduce((a, b) => a > b ? a : b) + 1;

int backZ(Iterable<int> zs) =>
    zs.isEmpty ? 1 : zs.reduce((a, b) => a < b ? a : b) - 1;
