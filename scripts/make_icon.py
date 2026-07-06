"""Generate the Mosaico app icon: a vivid diagonal gradient that
dissolves into bold polygon (Voronoi) mosaic cells, echoing the app's
Crystallize style.

Colors are built in HSV and hue-interpolated so every pixel stays
saturated — no muddy blends."""
import numpy as np
from matplotlib.colors import hsv_to_rgb
from scipy.spatial import cKDTree
from PIL import Image

S = 1024
rng = np.random.default_rng(11)

y, x = np.mgrid[0:S, 0:S].astype(np.float64) / S
t = (x + y) / 2  # 0 at top-left, 1 at bottom-right

# Cheerful gradient: sunny lime (95°) -> fresh mint (160°), gently dimmed
h = (95 + 65 * t) / 360
s = np.full_like(t, 0.72)
v = 0.92 - 0.06 * t

# Voronoi seeds: jittered grid so cells are irregular but evenly sized
GRID = 6
cell = S / GRID
seeds = np.array([
    [(gx + rng.uniform(0.15, 0.85)) * cell, (gy + rng.uniform(0.15, 0.85)) * cell]
    for gy in range(GRID) for gx in range(GRID)
])
labels = cKDTree(seeds).query(
    np.column_stack([np.tile(np.arange(S), S), np.repeat(np.arange(S), S)]))[1]
labels = labels.reshape(S, S)

# Cells whose seed lies past the diagonal become flat polygon tiles with
# STRONG color jitter; the cell shapes make the boundary organically jagged
for i, (sx, sy) in enumerate(seeds):
    if (sx + sy) / (2 * S) <= 0.52:  # keep upper-left smooth
        continue
    mask = labels == i
    tc = t[int(sy), int(sx)]
    h[mask] = ((95 + 65 * tc) / 360 + rng.uniform(-0.06, 0.06)) % 1.0
    s[mask] = np.clip(0.72 * rng.uniform(0.70, 1.35), 0.40, 1.0)
    # wide brightness spread for cell contrast, floor keeps it cheerful
    v[mask] = np.clip((0.92 - 0.06 * tc) * rng.uniform(0.55, 1.20), 0.42, 1.0)

img = hsv_to_rgb(np.dstack([h, s, v])) * 255
Image.fromarray(img.astype(np.uint8)).save("Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
print("wrote Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
