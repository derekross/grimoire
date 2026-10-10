"""Draws Grimoire's textures with cairo.

Usage: python3 draw.py <output dir>
Writes PNGs, then converts them to the 32-bit TGAs WoW loads (needs ImageMagick).
All art is original and drawn here in code, so it can be tweaked and re-rendered.
"""
import cairo, math, sys, os, subprocess
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
TAU = math.pi * 2

def surface(size):
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    c = cairo.Context(s); c.scale(size / 256, size / 256)
    return s, c

def radial(c, cx, cy, r0, r1, stops):
    g = cairo.RadialGradient(cx, cy, r0, cx, cy, r1)
    for off, col in stops: g.add_color_stop_rgba(off, *col)
    return g

def linear(x0, y0, x1, y1, stops):
    g = cairo.LinearGradient(x0, y0, x1, y1)
    for off, col in stops: g.add_color_stop_rgba(off, *col)
    return g

def ring(c, cx, cy, ro, ri):
    c.new_path(); c.arc(cx, cy, ro, 0, TAU); c.arc_negative(cx, cy, ri, TAU, 0); c.close_path()

def metal_ring(c, cx, cy, ro, ri, tint=(1, 1, 1)):
    tr, tg, tb = tint
    # base dark iron with top-left light
    ring(c, cx, cy, ro, ri)
    c.set_source(linear(cx - ro, cy - ro, cx + ro, cy + ro, [
        (0, (0.62 * tr, 0.60 * tg, 0.66 * tb, 1)), (0.45, (0.22 * tr, 0.20 * tg, 0.25 * tb, 1)),
        (0.55, (0.16 * tr, 0.14 * tg, 0.18 * tb, 1)), (1, (0.40 * tr, 0.37 * tg, 0.44 * tb, 1))]))
    c.fill()
    # inner bevel: dark lip inside, light lip outside
    c.set_line_width(2.5)
    c.arc(cx, cy, ro - 1.5, 0, TAU)
    c.set_source(linear(cx - ro, cy - ro, cx + ro, cy + ro, [(0, (1, 1, 1, 0.55)), (0.5, (1, 1, 1, 0.05)), (1, (0, 0, 0, 0.6))]))
    c.stroke()
    c.arc(cx, cy, ri + 1.5, 0, TAU)
    c.set_source(linear(cx - ro, cy - ro, cx + ro, cy + ro, [(0, (0, 0, 0, 0.75)), (0.5, (0, 0, 0, 0.2)), (1, (1, 1, 1, 0.35))]))
    c.stroke()
    # outer shadow line
    c.set_line_width(2); c.arc(cx, cy, ro, 0, TAU); c.set_source_rgba(0, 0, 0, 0.9); c.stroke()
    c.arc(cx, cy, ri, 0, TAU); c.set_source_rgba(0, 0, 0, 0.9); c.stroke()

def rivets(c, cx, cy, r, n, size, start=0):
    for i in range(n):
        a = start + i * TAU / n
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        c.arc(x, y, size, 0, TAU)
        c.set_source(radial(c, x - size * 0.35, y - size * 0.35, 0, size * 1.2, [(0, (0.95, 0.9, 1, 1)), (0.5, (0.45, 0.42, 0.5, 1)), (1, (0.1, 0.08, 0.12, 1))]))
        c.fill()

FEL = (0.45, 1.0, 0.35)

# Tome color variants: leather (light, mid, dark), sigil glow, engraving in the well.
PALETTES = {
    "Void":   dict(leather=((0.36, 0.18, 0.42), (0.20, 0.08, 0.25), (0.08, 0.03, 0.10)), sigil=FEL, engrave=(0.55, 0.35, 0.75)),
    "Shadow": dict(leather=((0.22, 0.20, 0.25), (0.10, 0.09, 0.12), (0.03, 0.02, 0.04)), sigil=(0.72, 0.45, 1.0), engrave=(0.45, 0.35, 0.60)),
    "Fel":    dict(leather=((0.20, 0.36, 0.16), (0.08, 0.18, 0.07), (0.02, 0.06, 0.02)), sigil=(0.75, 1.0, 0.25), engrave=(0.35, 0.65, 0.30)),
    "Blood":  dict(leather=((0.46, 0.12, 0.12), (0.24, 0.04, 0.05), (0.09, 0.01, 0.02)), sigil=(1.0, 0.55, 0.15), engrave=(0.70, 0.30, 0.25)),
}
PAL = PALETTES["Void"]

def glow(c, cx, cy, r, col, a=0.8):
    c.arc(cx, cy, r, 0, TAU)
    c.set_source(radial(c, cx, cy, 0, r, [(0, (*col, a)), (0.4, (*col, a * 0.35)), (1, (*col, 0))]))
    c.fill()

def sigil(c, cx, cy, r, col, width=2.2):
    # circle + inner circle + pentagram + rune ticks, drawn twice: blurred glow then crisp
    for lw, alpha in ((width * 4, 0.18), (width * 2.2, 0.35), (width, 1.0)):
        c.set_line_width(lw); c.set_line_cap(cairo.LINE_CAP_ROUND); c.set_line_join(cairo.LINE_JOIN_ROUND)
        c.set_source_rgba(*col, alpha)
        c.arc(cx, cy, r, 0, TAU); c.stroke()
        c.arc(cx, cy, r * 0.80, 0, TAU); c.stroke()
        pts = [(cx + math.cos(-math.pi / 2 + i * TAU / 5) * r * 0.80, cy + math.sin(-math.pi / 2 + i * TAU / 5) * r * 0.80) for i in range(5)]
        order = [0, 2, 4, 1, 3, 0]
        c.move_to(*pts[order[0]])
        for k in order[1:]: c.line_to(*pts[k])
        c.stroke()
        for i in range(10):
            a = i * TAU / 10 + TAU / 20
            c.move_to(cx + math.cos(a) * r * 0.84, cy + math.sin(a) * r * 0.84)
            c.line_to(cx + math.cos(a) * r * 0.96, cy + math.sin(a) * r * 0.96)
            c.stroke()

def tome(c, cx, cy, w, h):
    x0, y0 = cx - w / 2, cy - h / 2
    # pages (right/bottom edge, behind cover)
    c.rectangle(x0 + 8, y0 + 6, w, h)
    c.set_source(linear(x0, 0, x0 + w, 0, [(0, (0.75, 0.68, 0.55, 1)), (1, (0.92, 0.86, 0.72, 1))])); c.fill()
    c.set_line_width(0.8); c.set_source_rgba(0.45, 0.38, 0.28, 0.7)
    for i in range(1, 6):
        c.move_to(x0 + w + 8 - i * 1.4, y0 + 8); c.line_to(x0 + w + 8 - i * 1.4, y0 + h + 4); c.stroke()
    # cover (leather) with rounded corners
    rr = 6
    def cover_path():
        c.new_path()
        c.arc(x0 + w - rr, y0 + rr, rr, -math.pi / 2, 0); c.arc(x0 + w - rr, y0 + h - rr, rr, 0, math.pi / 2)
        c.arc(x0 + rr, y0 + h - rr, rr, math.pi / 2, math.pi); c.arc(x0 + rr, y0 + rr, rr, math.pi, 3 * math.pi / 2)
        c.close_path()
    cover_path()
    light, mid, dark = PAL["leather"]
    c.set_source(radial(c, cx - w * 0.15, cy - h * 0.2, 4, w * 0.9, [(0, (*light, 1)), (0.6, (*mid, 1)), (1, (*dark, 1))]))
    c.fill_preserve()
    c.set_source_rgba(0, 0, 0, 0.9); c.set_line_width(2); c.stroke()
    # spine band
    c.rectangle(x0, y0, 12, h)
    c.set_source(linear(x0, 0, x0 + 12, 0, [(0, (*dark, 1)), (0.5, (*mid, 1)), (1, (*dark, 1))])); c.fill()
    for yy in (y0 + h * 0.18, y0 + h * 0.5, y0 + h * 0.82):
        c.rectangle(x0, yy - 2, 12, 4); c.set_source(linear(0, yy - 2, 0, yy + 2, [(0, (0.85, 0.7, 0.4, 1)), (1, (0.35, 0.25, 0.1, 1))])); c.fill()
    # tooled border
    c.set_line_width(1.2); c.set_source_rgba(0.85, 0.68, 0.38, 0.55)
    c.rectangle(x0 + 18, y0 + 7, w - 25, h - 14); c.stroke()
    # metal corners
    for (px, py, sx, sy) in ((x0 + w, y0, -1, 1), (x0 + w, y0 + h, -1, -1), (x0 + 12, y0, 1, 1), (x0 + 12, y0 + h, 1, -1)):
        c.new_path(); c.move_to(px, py); c.line_to(px + sx * 18, py); c.line_to(px, py + sy * 18); c.close_path()
        c.set_source(linear(px, py, px + sx * 18, py + sy * 18, [(0, (0.95, 0.82, 0.5, 1)), (1, (0.45, 0.32, 0.12, 1))])); c.fill_preserve()
        c.set_source_rgba(0, 0, 0, 0.7); c.set_line_width(1); c.stroke()
    # clasp on the right
    c.rectangle(x0 + w - 4, cy - 7, 12, 14)
    c.set_source(linear(0, cy - 7, 0, cy + 7, [(0, (0.95, 0.82, 0.5, 1)), (1, (0.4, 0.28, 0.1, 1))])); c.fill_preserve()
    c.set_source_rgba(0, 0, 0, 0.8); c.set_line_width(1); c.stroke()
    # glowing sigil on the cover
    scx = cx + 6
    glow(c, scx, cy, w * 0.42, PAL["sigil"], 0.55)
    sigil(c, scx, cy, w * 0.27, PAL["sigil"], 1.8)
    # eye-gem in the middle
    c.arc(scx, cy, 5, 0, TAU)
    sr, sg, sb = PAL["sigil"]
    c.set_source(radial(c, scx - 1.5, cy - 1.5, 0, 6, [(0, (0.95, 1, 0.9, 1)), (0.5, (sr, sg, sb, 1)), (1, (sr * 0.2, sg * 0.2, sb * 0.2, 1))])); c.fill()

def centerpiece(size, name, pips=20):
    # name is a full path from here on
    s, c = surface(size)
    cx = cy = 128
    # dark well behind
    c.arc(cx, cy, 104, 0, TAU)
    mid, dark = PAL["leather"][1], PAL["leather"][2]
    c.set_source(radial(c, cx, cy, 10, 104, [(0, (mid[0] * 0.7, mid[1] * 0.7, mid[2] * 0.7, 1)), (0.75, (*dark, 1)), (1, (dark[0] * 0.3, dark[1] * 0.3, dark[2] * 0.3, 1))])); c.fill()
    # faint sigil engraved in the well
    sigil(c, cx, cy, 96, PAL["engrave"], 0.9)
    # pip sockets in the rim (runtime lights them; drawn here unlit)
    metal_ring(c, cx, cy, 126, 103, tint=(1.0, 0.95, 1.1))
    c.set_line_width(4); c.set_line_cap(cairo.LINE_CAP_ROUND)
    c.arc(cx, cy, 121, math.pi * 1.08, math.pi * 1.42); c.set_source_rgba(1, 1, 1, 0.3); c.stroke()
    ring(c, cx, cy, 103, 92)
    c.set_source(radial(c, cx, cy, 92, 103, [(0, (0, 0, 0, 0)), (1, (0, 0, 0, 0.7))])); c.fill()
    for i in range(pips):
        a = -math.pi / 2 + i * TAU / pips
        x, y = cx + math.cos(a) * 115, cy + math.sin(a) * 115
        c.arc(x, y, 5.2, 0, TAU); c.set_source_rgba(0, 0, 0, 0.85); c.fill()
        c.arc(x, y, 3.6, 0, TAU)
        c.set_source(radial(c, x - 1, y - 1, 0, 4, [(0, (0.25, 0.22, 0.28, 1)), (1, (0.05, 0.04, 0.06, 1))])); c.fill()
    tome(c, cx - 5, cy, 104, 132)
    s.write_to_png(name)

def button_rim(size, name):
    s, c = surface(size)
    # soft drop shadow
    ring(c, 128, 132, 128, 110); c.set_source(radial(c, 128, 132, 110, 128, [(0, (0, 0, 0, 0.6)), (1, (0, 0, 0, 0))])); c.fill()
    metal_ring(c, 128, 128, 124, 98, tint=(1.0, 0.95, 1.1))
    # specular arc on the upper left
    c.set_line_width(5); c.set_line_cap(cairo.LINE_CAP_ROUND)
    c.arc(128, 128, 116, math.pi * 1.05, math.pi * 1.45)
    c.set_source_rgba(1, 1, 1, 0.35); c.stroke()
    # inner shadow over the icon edge
    ring(c, 128, 128, 98, 86)
    c.set_source(radial(c, 128, 128, 86, 98, [(0, (0, 0, 0, 0)), (1, (0, 0, 0, 0.6))])); c.fill()
    rivets(c, 128, 128, 111, 4, 4.2, start=-math.pi / 4)
    s.write_to_png(name)

def glow_ring(size, name):
    s, c = surface(size)
    for r, w, a in ((116, 26, 0.25), (116, 14, 0.5), (116, 6, 1.0)):
        c.set_line_width(w); c.arc(128, 128, r, 0, TAU); c.set_source_rgba(1, 1, 1, a); c.stroke()
    s.write_to_png(name)

def addon_icon(size, name):
    """The tome alone on a dark rounded tile, for the AddOns list."""
    s, c = surface(size)
    c.new_path(); r = 36
    c.arc(256 - r, r, r, -math.pi / 2, 0); c.arc(256 - r, 256 - r, r, 0, math.pi / 2)
    c.arc(r, 256 - r, r, math.pi / 2, math.pi); c.arc(r, r, r, math.pi, 3 * math.pi / 2); c.close_path()
    c.set_source(radial(c, 128, 128, 10, 180, [(0, (0.18, 0.08, 0.22, 1)), (1, (0.03, 0.01, 0.04, 1))])); c.fill()
    tome(c, 120, 128, 150, 196)
    s.write_to_png(name)

def pip(size, name):
    s, c = surface(size)
    sr, sg, sb = PAL["sigil"]
    glow(c, 128, 128, 128, PAL["sigil"], 0.9)
    c.arc(128, 128, 60, 0, TAU)
    c.set_source(radial(c, 108, 108, 0, 70, [(0, (0.97, 1, 0.92, 1)), (0.45, (sr, sg, sb, 1)), (1, (sr * 0.25, sg * 0.4, sb * 0.25, 1))])); c.fill()
    s.write_to_png(name)

def use(palette):
    def wrap(fn):
        def run(n):
            global PAL
            PAL = PALETTES[palette]
            fn(n)
        return run
    return wrap

TEXTURES = {
    "Rim": lambda n: button_rim(128, n),
    "RimGlow": lambda n: glow_ring(128, n),
    "Icon": use("Void")(lambda n: addon_icon(64, n)),
}
for palette in PALETTES:
    TEXTURES["Grimoire" + palette] = use(palette)(lambda n: centerpiece(256, n))
    TEXTURES["Pip" + palette] = use(palette)(lambda n: pip(32, n))
for name, draw in TEXTURES.items():
    png = os.path.join(OUT, name + ".png")
    draw(png)
    # Uncompressed 32-bit TGA with alpha, bottom-left origin, as WoW expects.
    subprocess.run(["magick", png, "-compress", "none", "-define", "tga:image-origin=BottomLeft",
                    os.path.join(OUT, name + ".tga")], check=True)
    os.remove(png)
print("ok")
