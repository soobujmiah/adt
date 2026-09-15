#!/usr/bin/env python3
"""Generate the ADT site's geographic layer: assets/geo/adt-geo.js

This is ADT's own generator. It does not read, fetch or import anything
from another project's repository — the visual language is shared, the
implementation and the data file are not.

Source data: Natural Earth 1:110m (public domain) physical land polygons
and Admin-0 country polygons, fetched as GeoJSON. The world is projected
here, offline, with a Miller cylindrical projection and cropped to the
inhabited latitudes, then simplified with Douglas-Peucker and rounded.

Why only these countries: the map is allowed to state documented
geography only. ADT's evidence names exactly one place — the validation
device in Dhaka, Bangladesh (see docs/REAL_DEVICE_BUILD_VALIDATION.md).
Everything else on this map is context that makes that place readable:
its neighbours and, at the widest zoom, the world land. No second
country is ever highlighted as if ADT had a relationship with it.

Regenerate:
    curl -sL -o /tmp/ne_land.json \
      https://raw.githubusercontent.com/martynafford/natural-earth-geojson/master/110m/physical/ne_110m_land.json
    curl -sL -o /tmp/ne_countries.json \
      https://raw.githubusercontent.com/martynafford/natural-earth-geojson/master/110m/cultural/ne_110m_admin_0_countries.json
    python3 tools/make-geo.py

The output is committed, so the site build never needs this script or
network access.
"""

import json
import math
import os

SRC_LAND = "/tmp/ne_land.json"
SRC_COUNTRIES = "/tmp/ne_countries.json"
OUT = "assets/geo/adt-geo.js"

W = 1000.0                     # viewBox width in map units (lon -180..180)
LAT_TOP, LAT_BOT = 84.0, -58.0  # crop: inhabited latitudes, no Antarctica

TOL_LAND = 1.6                 # Douglas-Peucker tolerance, px (global context)
TOL_COUNTRY = 1.0              # regional context countries
TOL_ORIGIN = 0.35              # Bangladesh — recognisable outline
MIN_EXTENT = 1.4               # drop islands smaller than this in px

# Regional context. BGD is the active country; the rest give it
# surrounding geography a visitor can read.
ORIGIN_ISO = "BGD"
CONTEXT_ISO = ["IND", "MMR", "NPL", "BTN", "LKA", "PAK", "CHN", "THA"]

# Dhaka — the location of the validation device. Not a decoration: this
# coordinate is the only geographic claim the site makes.
ORIGIN_LON, ORIGIN_LAT = 90.4, 23.8


def miller_y(lat_deg: float) -> float:
    phi = math.radians(lat_deg)
    return -1.25 * math.log(math.tan(math.pi / 4 + 0.4 * phi)) * (W / (2 * math.pi))


TOP, BOTTOM = miller_y(LAT_TOP), miller_y(LAT_BOT)


def project(lon: float, lat: float):
    return ((lon + 180) / 360) * W, miller_y(lat)


def perp_dist(p, a, b):
    (px, py), (ax, ay), (bx, by) = p, a, b
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def simplify(points, tol):
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        dmax, idx = 0.0, i
        for k in range(i + 1, j):
            d = perp_dist(points[k], points[i], points[j])
            if d > dmax:
                dmax, idx = d, k
        if dmax > tol:
            keep[idx] = True
            stack.extend(((i, idx), (idx, j)))
    return [p for p, k in zip(points, keep) if k]


def rings_to_points(geom):
    """Yield every ring of a Polygon / MultiPolygon as a list of (x, y)."""
    if geom["type"] == "Polygon":
        polys = [geom["coordinates"]]
    elif geom["type"] == "MultiPolygon":
        polys = geom["coordinates"]
    else:
        return
    for poly in polys:
        for ring in poly:
            yield ring


def path_for(geometry, tol):
    """SVG path data for one feature, dropping specks and rounding to 0.1."""
    out = []
    for ring in rings_to_points(geometry):
        pts = [project(lon, lat) for lon, lat in ring]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        if max(max(xs) - min(xs), max(ys) - min(ys)) < MIN_EXTENT:
            continue
        pts = simplify(pts, tol)
        if len(pts) < 3:
            continue
        out.append(
            "M" + " ".join(f"{x:.1f} {y:.1f}" for x, y in pts) + "Z"
        )
    return "".join(out)


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)

    land = json.load(open(SRC_LAND))
    world = "".join(path_for(f["geometry"], TOL_LAND) for f in land["features"])

    countries = json.load(open(SRC_COUNTRIES))
    picked = {}
    for f in countries["features"]:
        p = f["properties"]
        iso = p.get("ADM0_A3") or p.get("ISO_A3")
        if iso in [ORIGIN_ISO] + CONTEXT_ISO:
            picked[iso] = path_for(f["geometry"], TOL_ORIGIN if iso == ORIGIN_ISO else TOL_COUNTRY)

    missing = [i for i in [ORIGIN_ISO] + CONTEXT_ISO if i not in picked]
    assert not missing, f"missing country geometry: {missing}"

    ox, oy = project(ORIGIN_LON, ORIGIN_LAT)

    # The origin must actually fall inside Bangladesh's own geometry —
    # the same guard the site relies on when it marks Dhaka. Checked on
    # the real rings, before simplification.
    bgd = next(
        f["geometry"]
        for f in countries["features"]
        if (f["properties"].get("ADM0_A3") or f["properties"].get("ISO_A3")) == ORIGIN_ISO
    )
    inside = False
    for ring in rings_to_points(bgd):
        pts = [project(lon, lat) for lon, lat in ring]
        for i in range(len(pts)):
            x1, y1 = pts[i]
            x2, y2 = pts[(i + 1) % len(pts)]
            if (y1 > oy) != (y2 > oy) and ox < (x2 - x1) * (oy - y1) / (y2 - y1) + x1:
                inside = not inside
    assert inside, "projected origin (Dhaka) is not inside the Bangladesh outline"
    assert TOP < oy < BOTTOM, "origin projected outside the map crop"

    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(
            "/* GENERATED — do not edit by hand.\n"
            "   Source: Natural Earth 1:110m (public domain), projected offline\n"
            "   by tools/make-geo.py with a Miller cylindrical projection.\n"
            "   Regenerate with: python3 tools/make-geo.py\n"
            "   Only documented geography is present: the origin country, its\n"
            "   neighbours for context, and world land at the widest zoom. */\n"
            "window.ADT_GEO = {\n"
            f"  width: {W:g},\n"
            f"  top: {TOP:.1f},\n"
            f"  bottom: {BOTTOM:.1f},\n"
            f"  origin: {{ lon: {ORIGIN_LON}, lat: {ORIGIN_LAT}, x: {ox:.1f}, y: {oy:.1f} }},\n"
            "  countries: {\n"
            + "".join(f"    {iso}: {json.dumps(d)},\n" for iso, d in picked.items())
            + "  },\n"
            f"  world: {json.dumps(world)},\n"
            "};\n"
        )

    size = len(open(OUT, encoding="utf-8").read())
    print(f"wrote {OUT} ({size / 1024:.1f} KB)")
    print(f"  world path: {len(world)} chars")
    for iso, d in picked.items():
        print(f"  {iso}: {len(d)} chars")
    print(f"  origin projected: x={ox:.1f} y={oy:.1f}")


if __name__ == "__main__":
    main()
