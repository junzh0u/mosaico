"""Mosaico icon generator with neighbor-contrast constraint.

Full-bleed Voronoi mosaic whose cells blend from the smooth gradient
(zero contrast top-left third) to bold flat tiles (bottom-right).
Adjacent cells are guaranteed to differ: each cell rerolls its color
until its BLENDED (visible) color is far enough from every
already-colored neighbor.

Regenerate with: just icon
"""


import numpy as np
from matplotlib.colors import hsv_to_rgb
from scipy.spatial import cKDTree
from PIL import Image

SEED = 5
OUT = "Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

S = 1024
rng = np.random.default_rng(SEED)

y, x = np.mgrid[0:S, 0:S].astype(np.float64) / S
t = (x + y) / 2  # 0 at top-left, 1 at bottom-right

def grad_hsv(tc):
    """Smooth gradient color: sunny lime (95°) -> fresh mint (160°)."""
    return np.array([(95 + 65 * tc) / 360, 0.72, 0.92 - 0.06 * tc])

h = (95 + 65 * t) / 360
s = np.full_like(t, 0.72)
v = 0.92 - 0.06 * t

GRID = 6
cell = S / GRID
seeds = np.array([
    [(gx + rng.uniform(0.15, 0.85)) * cell, (gy + rng.uniform(0.15, 0.85)) * cell]
    for gy in range(GRID) for gx in range(GRID)
])
labels = cKDTree(seeds).query(
    np.column_stack([np.tile(np.arange(S), S), np.repeat(np.arange(S), S)]))[1]
labels = labels.reshape(S, S)

# Adjacency graph from label transitions between neighboring pixels
adj = {i: set() for i in range(len(seeds))}
for a, b in [(labels[:, :-1], labels[:, 1:]), (labels[:-1, :], labels[1:, :])]:
    edge = a != b
    for i, j in zip(a[edge].ravel(), b[edge].ravel()):
        adj[i].add(j)
        adj[j].add(i)

def ramp(tc):
    """Smoothstep: 0 below tc=0.42, 1 above 0.86."""
    k = np.clip((tc - 0.42) / (0.86 - 0.42), 0, 1)
    return k * k * (3 - 2 * k)

def color_dist(a, b):
    """Perceptual-ish HSV distance, brightness-weighted."""
    dh = min(abs(a[0] - b[0]), 1 - abs(a[0] - b[0]))
    return 2.0 * abs(a[2] - b[2]) + 1.5 * dh + 0.5 * abs(a[1] - b[1])

MIN_DIST = 0.18
visible = {}  # cell index -> blended HSV actually rendered

for i, (sx, sy) in enumerate(seeds):
    tc = t[int(sy), int(sx)]
    k = ramp(tc)
    g = grad_hsv(tc)
    if k == 0:
        visible[i] = g  # untouched smooth gradient
        continue
    neighbors = [visible[j] for j in adj[i] if j in visible]
    best, best_score = None, -1.0
    for _ in range(40):
        hc = (g[0] + rng.uniform(-0.06, 0.06)) % 1.0
        sc = np.clip(0.72 * rng.uniform(0.62, 1.40), 0.35, 1.0)
        mult = rng.uniform(1.06, 1.30) if rng.random() < 0.5 else rng.uniform(0.48, 0.68)
        vc = np.clip(g[2] * mult, 0.40, 1.0)
        cand = (1 - k) * g + k * np.array([hc, sc, vc])
        score = min((color_dist(cand, n) for n in neighbors), default=np.inf)
        # scale requirement by k: faint cells can't differ much by design
        if score >= MIN_DIST * k:
            best = cand
            break
        if score > best_score:
            best, best_score = cand, score
    visible[i] = best
    mask = labels == i
    h[mask], s[mask], v[mask] = best

img = hsv_to_rgb(np.dstack([h, s, v])) * 255
Image.fromarray(img.astype(np.uint8)).save(OUT)
print("wrote", OUT)
