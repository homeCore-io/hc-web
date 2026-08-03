#!/usr/bin/env python3
"""Generate every app icon from one vector definition.

    python3 tool/make_icons.py            # rewrites web/favicon.* and web/icons/

The mark is "Roof + Core": a roofline over a solid dot, in the app's own signal
amber (`accent.active`, #FFB661 — the colour that means "this is on") on
`surface.base`. It is not a house drawing; it is the idea of one, which is all
that survives at 16 px.

WHY A SCRIPT AND NOT SIX CHECKED-IN PNGS. Icons drift: someone edits the 512
and the 192 quietly disagrees with it forever. Here the geometry lives in one
place, in units, and every size is derived. Change GAP or ROOF_W below and all
six outputs move together.

WHY THE GEOMETRY LOOKS FUSSY. The whole design rests on the gap between the
roof's lower edge and the top of the core. At 16 px one design unit is a
quarter of a pixel, so the obvious spacing — a unit or two — renders as no gap
at all and the two shapes fuse into an amber blob. The values here leave 6.25
units, which is 1.56 px of background at 16 px: enough to read as two shapes,
and about as tight as it can get. Treat that as a floor, not a target.

Rendering is done by hand at 8x and downsampled rather than by shelling out to
a rasteriser, so the output does not depend on which SVG library happens to be
installed on the machine.
"""

import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(HERE, os.pardir, "web")

# --- palette -----------------------------------------------------------------
# Both from lib/design/skins.dart. Keep them in step with the tokens: the point
# of the mark is that it carries the same meaning as the UI.
AMBER = (0xFF, 0xB6, 0x61, 0xFF)  # accent.active — "this is on"
BASE = (0x0B, 0x0E, 0x13, 0xFF)  # surface.base

# --- geometry, in a 64-unit square -------------------------------------------
S = 64.0
CORNER = 14.0  # tile radius; roughly a squircle at icon sizes

ROOF_W = 8.5  # stroke weight
ROOF_L = (11.5, 29.0)  # left eave
ROOF_APEX = (32.0, 11.5)
ROOF_R = (52.5, 29.0)  # right eave

CORE_C = (32.0, 47.5)
CORE_R = 8.0

# Roof stroke bottom edge -> core top edge. Printed by main() as a sanity check;
# if a change here drops it below ~1.5 px at 16 the mark has stopped working.
GAP = (CORE_C[1] - CORE_R) - (ROOF_L[1] + ROOF_W / 2)

SS = 8  # supersample factor


def _draw(size, *, tile, scale=1.0):
    """Render the mark at `size` px.

    `tile` rounds the corners (the browser/desktop icon). Maskable icons pass
    False and a `scale` < 1: the platform crops them to whatever shape it likes,
    so the background must bleed to the edge and the mark must sit inside the
    safe zone — the centre circle of 80% diameter.
    """
    n = size * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    u = n / S  # one design unit, in supersampled pixels

    if tile:
        d.rounded_rectangle([0, 0, n - 1, n - 1], radius=CORNER * u, fill=BASE)
    else:
        d.rectangle([0, 0, n, n], fill=BASE)

    def pt(p):
        # Scale about the centre so shrinking for the safe zone keeps the mark
        # centred rather than pulling it toward the origin.
        return ((32 + (p[0] - 32) * scale) * u, (32 + (p[1] - 32) * scale) * u)

    w = ROOF_W * scale * u
    a, b, c = pt(ROOF_L), pt(ROOF_APEX), pt(ROOF_R)

    # `joint="curve"` rounds the apex; the caps are drawn as discs because
    # Pillow has no round-cap option.
    d.line([a, b, c], fill=AMBER, width=int(round(w)), joint="curve")
    for e in (a, c):
        d.ellipse([e[0] - w / 2, e[1] - w / 2, e[0] + w / 2, e[1] + w / 2], fill=AMBER)

    cc, cr = pt(CORE_C), CORE_R * scale * u
    d.ellipse([cc[0] - cr, cc[1] - cr, cc[0] + cr, cc[1] + cr], fill=AMBER)

    return img.resize((size, size), Image.LANCZOS)


def svg():
    """The same mark as vector, for browsers that take an SVG favicon.

    Worth shipping: it is ~400 bytes and stays crisp on every display, where the
    PNG is resampled by the browser at whatever size the tab strip wants.
    """
    ax, ay = ROOF_APEX
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
        f'<rect width="64" height="64" rx="{CORNER:g}" fill="#0B0E13"/>'
        f'<path d="M{ROOF_L[0]:g} {ROOF_L[1]:g} L{ax:g} {ay:g} L{ROOF_R[0]:g} {ROOF_R[1]:g}" '
        f'fill="none" stroke="#FFB661" stroke-width="{ROOF_W:g}" '
        'stroke-linecap="round" stroke-linejoin="round"/>'
        f'<circle cx="{CORE_C[0]:g}" cy="{CORE_C[1]:g}" r="{CORE_R:g}" fill="#FFB661"/>'
        "</svg>\n"
    )


def main():
    icons = os.path.join(WEB, "icons")
    os.makedirs(icons, exist_ok=True)

    _draw(64, tile=True).save(os.path.join(WEB, "favicon.png"))
    with open(os.path.join(WEB, "favicon.svg"), "w") as f:
        f.write(svg())

    for n in (192, 512):
        _draw(n, tile=True).save(os.path.join(icons, f"Icon-{n}.png"))
        # 0.72 keeps the mark's corners inside the 80% safe circle with room to
        # spare, so no launcher mask can clip the roof.
        _draw(n, tile=False, scale=0.72).save(
            os.path.join(icons, f"Icon-maskable-{n}.png")
        )

    print(f"gap: {GAP:g} units = {GAP * 16 / S:.2f} px at 16px")
    print("wrote favicon.png, favicon.svg, icons/Icon-{192,512}.png, "
          "icons/Icon-maskable-{192,512}.png")


if __name__ == "__main__":
    main()
