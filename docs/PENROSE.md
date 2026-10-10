# The Penrose backdrop

`scripts/penrose_bg.gd` draws a genuine P3 Penrose tiling (the rhombus
tiling) by Robinson-triangle deflation, regenerated for every run. Because
Penrose tilings are aperiodic, every window into one is unique — the random
pivot, rotation and depth alone guarantee a fresh backdrop each game.

## The deflation rule

Each rhombus is split into two mirrored Robinson triangles; deflation
subdivides triangles into φ-scaled children (φ = golden ratio). The exact
rule used, in this project's vertex convention:

```
acute  (a, b, c)   — 36° at a:
    p = a + (b − a) / φ
    → obtuse(p, c, a), acute(c, p, b)

obtuse (a, b, c)   — 108° at a, 36° at b and c:
    q = b + (a − b) / φ
    r = b + (c − b) / φ
    → obtuse(q, r, b), acute(r, q, a), obtuse(r, c, a)
```

In BOTH families the side b–c is the rhombus diagonal shared with the
mirror triangle, so stroking only a–b and a–c outlines true Penrose rhombi
(the diagonal stays invisible).

### Why this exact rule

Deflation rules circulating online frequently have wrong vertex orderings —
they conserve area (any partition does) but the *roles* drift, so children
subdivide along wrong edges and the tiling silently degenerates after a few
generations. This rule was found by brute-force search over all child
vertex orderings and verified numerically before being hardcoded:

- exact area conservation through 6 generations (error 0.00e+00),
- every triangle remains a Robinson shape (36-72-72 or 36-36-108),
- consistent per-color vertex convention at every depth,
- triangle counts match the canonical Penrose sequence
  10 → 20 → 50 → 130 → 340 → 890 → 2330,
- **mirror-orientation completeness**: 100% of interior triangles pair
  with a twin across their b–c base — every unpaired base lies exactly on
  the seed region's boundary polygon (checked to 1e-6 px through depth 8,
  both seeds).

The last check matters as much as the first four: of the 32 child
orderings that conserve shape and area, most flip mirror orientation
somewhere, and a rule that "looks right" can leave half the triangles
twinless — the outlines still render as rhombi, but the tiling can't be
decomposed into them (the v1.3 breakable field exposed exactly this; the
orderings above are the corrected, pairing-complete set, and the
thick-rhombus seed's two halves must use the SAME b,c order). The
verification scripts live in the session scratchpad; the checks are easy
to re-run — subdivide, sum areas, classify angles, count twins.

## Seeds

Two initial configurations, picked 50/50 per run:

- **Sun wheel** — 10 acute triangles fanned around the pivot
  (`depth 5–6`).
- **Thick-rhombus seed** — two mirrored obtuse triangles forming one giant
  thick rhombus that covers the view (its inradius is `s·sin 72° / 2`, so
  the side is sized from the cover radius; `depth 7–8` compensates for the
  larger start).

Any Robinson triangle legally seeds a Penrose tiling, so both are exact.
The pivot wanders ±220/±160 px around screen center, rotation is uniform
0..τ, and the whole tiling drifts at ±0.01 rad/s (transform only — tiles
are drawn once; the spin costs nothing).

## Render styles

One of three per run, all in the deep-sea turquoise family — acute halves
(thin rhombi) and obtuse halves (thick rhombi) get separate tones:

| style | look |
| --- | --- |
| `GLASS` | two mid-teal fills, soft teal edges — reads as frosted glass |
| `EDGES` | near-uniform dark fill, brighter edges — a glowing lattice |
| `DUAL`  | teal vs. indigo fills, faint pale edges — highest tile contrast |

The menu uses the same generator under a vertical wash (dark up top for
legibility, teal glow pooling at the bottom), plus `TileSnow`
(`startup.gd`): 13 lone rhombi — the two P3 prototiles, thin 36° and thick
72° — in the block damage-ladder colors, drifting down at 18–42 px/s with a
lazy sway and spin. Sparse on purpose: snow, not weather.

## The tiling as the playfield

In the **penrose** and **comp** game modes the arena backdrop IS the wall.
`PenroseBg.rhombi()` reunites the mirror triangles across their shared b–c
diagonals into full rhombi — matching is *spatial* (same family, diagonal
midpoints within 0.3 px on a 1 px hash grid), because exact-key equality
would let float noise between different subdivision paths split a pair.
Rhombi with ≥ 30% of their area inside the strip between the rails below
y = 540 become `PenroseTile` static bodies (convex polygon collision via
`set_point_cloud`, so vertex winding can't bite) — the wall tiles the
strip continuously, while corner slivers behind the rails/floor lines stay
scenery. The backdrop is frozen (`freeze()`) so the dim ghost a destroyed
tile reveals stays aligned with the surviving bodies forever. Unpaired
boundary triangles exist only at the rim of the covered disc, off-screen,
and are dropped.

With `Game.field_constant` (the default) the arena's deal comes from a
seeded RNG (`FIELD_SEED = ⌊2³²/φ⌋` — 51 tiles) instead of the session RNG:
identical field, style and all, every run — reproducible speedruns and
fair competitions. The menu backdrop always stays random.

## Performance

Depth 6 sun ≈ 2 330 triangles; depth 8 rhombus-seed ≈ 4 400. Everything is
drawn once into the canvas item (`_draw`), then only transformed — no
per-frame redraws. The world flash on hits is a separate additive
full-screen rect in `main.gd`, deliberately NOT a tiling redraw.
