"""程序化手绘美术工具：噪声、有向距离场（SDF）、高度场光照、描边、投影、合成。

思路：每个道具用 SDF 拼出轮廓，再把"离边缘多远"换算成高度（圆管 / 斜面截面），
由高度求法线打光，按光照值做渐变映射（gradient map）得到手绘的明暗层次，
叠上凹陷阴影、边缘磨损、颗粒和纹理，最后加墨线描边和投影。
所有坐标都是像素，y 轴向下；光从左上方来。
"""
import math

import numpy as np
from PIL import Image

np.seterr(over="ignore", invalid="ignore")

LIGHT = np.array([-0.52, -0.62, 0.59])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
HALF = LIGHT + np.array([0.0, 0.0, 1.0])
HALF = HALF / np.linalg.norm(HALF)


def grid(w, h):
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    return xs + 0.5, ys + 0.5


# ---------- 噪声 ----------

def _hash(ix, iy, seed):
    h = (ix.astype(np.uint32) * np.uint32(0x27D4EB2D)) ^ (iy.astype(np.uint32) * np.uint32(0x165667B1))
    h = h ^ np.uint32((seed * 0x9E3779B1) & 0xFFFFFFFF)
    h ^= h >> np.uint32(15)
    h *= np.uint32(0x85EBCA6B)
    h ^= h >> np.uint32(13)
    h *= np.uint32(0xC2B2AE35)
    h ^= h >> np.uint32(16)
    return (h >> np.uint32(8)).astype(np.float64) / float(1 << 24)


def vnoise(x, y, seed=0):
    x0 = np.floor(x)
    y0 = np.floor(y)
    fx = x - x0
    fy = y - y0
    ix = x0.astype(np.int64)
    iy = y0.astype(np.int64)
    ux = fx * fx * (3.0 - 2.0 * fx)
    uy = fy * fy * (3.0 - 2.0 * fy)
    a = _hash(ix, iy, seed)
    b = _hash(ix + 1, iy, seed)
    c = _hash(ix, iy + 1, seed)
    d = _hash(ix + 1, iy + 1, seed)
    return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy


def fbm(x, y, octaves=4, seed=0, lacunarity=2.03, gain=0.5):
    total = 0.0
    amp = 0.5
    norm = 0.0
    for i in range(octaves):
        total = total + amp * vnoise(x, y, seed + i * 31)
        norm += amp
        x, y = (0.8 * x - 0.6 * y) * lacunarity + 17.3, (0.6 * x + 0.8 * y) * lacunarity - 9.1
        amp *= gain
    return total / norm


def ridged(x, y, octaves=4, seed=0):
    """山脊噪声：值在 0.5 附近的地方变成尖脊，用来画裂纹和纤维。"""
    return 1.0 - np.abs(fbm(x, y, octaves, seed) * 2.0 - 1.0)


def worley(x, y, seed=0):
    ix = np.floor(x).astype(np.int64)
    iy = np.floor(y).astype(np.int64)
    f1 = np.full(x.shape, 9.0)
    f2 = np.full(x.shape, 9.0)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx = ix + dx
            cy = iy + dy
            px = cx + _hash(cx, cy, seed)
            py = cy + _hash(cx, cy, seed + 101)
            d = np.hypot(x - px, y - py)
            f2 = np.where(d < f1, f1, np.minimum(f2, d))
            f1 = np.minimum(f1, d)
    return f1, f2


def directional(x, y, angle, along, across, seed=0, octaves=3):
    """沿某个方向拉长的噪声：纤维、拉丝、骨纹。"""
    c, s = math.cos(angle), math.sin(angle)
    u = x * c + y * s
    v = -x * s + y * c
    return fbm(u * along, v * across, octaves, seed)


# ---------- 模糊 ----------

def box_blur(a, r):
    r = int(r)
    if r < 1:
        return a
    out = a
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r + 1, r)
        p = np.pad(out, pad, mode="edge")
        c = np.cumsum(p, axis=axis)
        if axis == 0:
            out = (c[2 * r + 1:, :] - c[:-2 * r - 1, :]) / (2 * r + 1)
        else:
            out = (c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)
    return out


def blur(a, r):
    """三次方框模糊 ≈ 高斯模糊，r 约等于标准差。"""
    if r <= 0:
        return a
    k = max(1, int(round(r * 0.8)))
    return box_blur(box_blur(box_blur(a, k), k), k)


def shift(a, dx, dy):
    out = np.zeros_like(a)
    h, w = a.shape
    xs0, xs1 = max(0, dx), min(w, w + dx)
    ys0, ys1 = max(0, dy), min(h, h + dy)
    out[ys0:ys1, xs0:xs1] = a[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
    return out


# ---------- SDF 图元 ----------

def sd_circle(X, Y, cx, cy, r):
    return np.hypot(X - cx, Y - cy) - r


def sd_ellipse(X, Y, cx, cy, rx, ry, angle=0.0):
    c, s = math.cos(angle), math.sin(angle)
    dx = X - cx
    dy = Y - cy
    u = c * dx + s * dy
    v = -s * dx + c * dy
    k0 = np.hypot(u / rx, v / ry)
    k1 = np.hypot(u / (rx * rx), v / (ry * ry))
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_segment(X, Y, ax, ay, bx, by):
    pax = X - ax
    pay = Y - ay
    bax = bx - ax
    bay = by - ay
    h = np.clip((pax * bax + pay * bay) / max(bax * bax + bay * bay, 1e-9), 0.0, 1.0)
    return np.hypot(pax - bax * h, pay - bay * h), h


def sd_capsule(X, Y, a, b, r0, r1=None):
    """返回 (sdf, 该点处的半径)。"""
    r1 = r0 if r1 is None else r1
    d, h = sd_segment(X, Y, a[0], a[1], b[0], b[1])
    r = r0 + (r1 - r0) * h
    return d - r, r


def sd_rbox(X, Y, cx, cy, hw, hh, r=0.0, angle=0.0):
    c, s = math.cos(angle), math.sin(angle)
    dx = X - cx
    dy = Y - cy
    u = np.abs(c * dx + s * dy) - hw + r
    v = np.abs(-s * dx + c * dy) - hh + r
    return np.hypot(np.maximum(u, 0), np.maximum(v, 0)) + np.minimum(np.maximum(u, v), 0) - r


def sd_polygon(X, Y, pts):
    n = len(pts)
    d = (X - pts[0][0]) ** 2 + (Y - pts[0][1]) ** 2
    s = np.ones_like(X)
    j = n - 1
    for i in range(n):
        ex = pts[j][0] - pts[i][0]
        ey = pts[j][1] - pts[i][1]
        wx = X - pts[i][0]
        wy = Y - pts[i][1]
        t = np.clip((wx * ex + wy * ey) / max(ex * ex + ey * ey, 1e-9), 0, 1)
        bx = wx - ex * t
        by = wy - ey * t
        d = np.minimum(d, bx * bx + by * by)
        c1 = Y >= pts[i][1]
        c2 = Y < pts[j][1]
        c3 = ex * wy > ey * wx
        flip = (c1 & c2 & c3) | (~c1 & ~c2 & ~c3)
        s = np.where(flip, -s, s)
        j = i
    return s * np.sqrt(d)


def sd_polyline(X, Y, pts, radii, bbox_pad=None):
    """沿折线的变粗细笔画，返回 (sdf, 半径)。只在包围盒附近计算以节省时间。"""
    pts = np.asarray(pts, dtype=np.float64)
    radii = np.asarray(radii, dtype=np.float64)
    d_best = np.full(X.shape, 1e6)
    r_best = np.full(X.shape, radii.max())
    pad = (bbox_pad if bbox_pad is not None else radii.max() + 6)
    x0 = max(0, int(pts[:, 0].min() - pad))
    x1 = min(X.shape[1], int(pts[:, 0].max() + pad) + 1)
    y0 = max(0, int(pts[:, 1].min() - pad))
    y1 = min(X.shape[0], int(pts[:, 1].max() + pad) + 1)
    if x1 <= x0 or y1 <= y0:
        return d_best, r_best
    sx = X[y0:y1, x0:x1]
    sy = Y[y0:y1, x0:x1]
    db = np.full(sx.shape, 1e6)
    rb = np.full(sx.shape, radii.max())
    for i in range(len(pts) - 1):
        d, h = sd_segment(sx, sy, pts[i, 0], pts[i, 1], pts[i + 1, 0], pts[i + 1, 1])
        r = radii[i] + (radii[i + 1] - radii[i]) * h
        dd = d - r
        better = dd < db
        db = np.where(better, dd, db)
        rb = np.where(better, r, rb)
    d_best[y0:y1, x0:x1] = db
    r_best[y0:y1, x0:x1] = rb
    return d_best, r_best


def spiral(cx, cy, r_start, r_end, a_start, turns, steps=160, squash=1.0, rot=0.0):
    """对数螺线采样点：从半径 r_start、角度 a_start 开始绕 turns 圈收到 r_end。"""
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a = a_start + turns * math.tau * t
        r = r_start * (r_end / r_start) ** t
        x = math.cos(a) * r
        y = math.sin(a) * r * squash
        c, s = math.cos(rot), math.sin(rot)
        pts.append((cx + x * c - y * s, cy + x * s + y * c))
    return pts


def bezier(p0, p1, p2, p3, steps=40):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0]
        y = u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]
        pts.append((x, y))
    return pts


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


# ---------- 高度场 ----------

def tube_height(sdf, r):
    """圆管截面：边缘处陡、轴线处最高。r 可以是数组（变粗细的笔画）。"""
    inside = np.clip(-sdf, 0.0, None)
    t = np.clip(inside / np.maximum(r, 1e-6), 0.0, 1.0)
    return r * np.sqrt(np.clip(1.0 - (1.0 - t) ** 2, 0.0, 1.0))


def bevel_height(sdf, width, height):
    """斜面截面：离边缘 width 以内渐升，之后是平台。"""
    t = np.clip(-sdf / width, 0.0, 1.0)
    return height * np.sqrt(np.clip(1.0 - (1.0 - t) ** 2, 0.0, 1.0))


def ridge_height(sdf, center, width, height):
    """在离边缘 center 处隆起一条圆脊。"""
    t = np.clip(1.0 - np.abs(-sdf - center) / width, 0.0, 1.0)
    return height * np.sqrt(np.clip(1.0 - (1.0 - t) ** 2, 0.0, 1.0))


def normals(h, strength=1.0):
    gy, gx = np.gradient(h)
    nx = -gx * strength
    ny = -gy * strength
    nz = np.ones_like(h)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    return nx * inv, ny * inv, nz * inv


def lighting(nx, ny, nz, wrap=0.35):
    ndl = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
    diffuse = np.clip((ndl + wrap) / (1.0 + wrap), 0.0, 1.0)
    ndh = np.clip(nx * HALF[0] + ny * HALF[1] + nz * HALF[2], 0.0, 1.0)
    return diffuse, ndh


def cavity(h, r):
    """凹陷为正、凸起为负（高度的反锐化）。"""
    return blur(h, r) - h


def ramp(t, stops):
    t = np.clip(t, 0.0, 1.0)
    pos = [s[0] for s in stops]
    out = np.zeros(t.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(t, pos, [s[1][c] for s in stops])
    return out


def soft_bands(t, bands, softness=0.35):
    """把连续的光照值压成几档色阶，档与档之间留一点柔和过渡（手绘感）。"""
    x = t * bands
    i = np.floor(x)
    f = x - i
    f = np.clip((f - 0.5) / max(softness, 1e-3) + 0.5, 0.0, 1.0)
    return np.clip((i + f) / bands, 0.0, 1.0)


def coverage(sdf):
    return np.clip(0.5 - sdf, 0.0, 1.0)


# ---------- 合成 ----------

class Layer:
    """预乘 alpha 的 RGBA 图层。"""

    def __init__(self, w, h):
        self.rgb = np.zeros((h, w, 3))
        self.a = np.zeros((h, w))

    def over(self, rgb, a):
        a = np.clip(a, 0.0, 1.0)
        self.rgb = rgb * a[..., None] + self.rgb * (1.0 - a[..., None])
        self.a = a + self.a * (1.0 - a)
        return self

    def under(self, rgb, a):
        a = np.clip(a, 0.0, 1.0) * (1.0 - self.a)
        self.rgb = self.rgb + rgb * a[..., None]
        self.a = self.a + a
        return self

    def image(self):
        a = np.clip(self.a, 0.0, 1.0)
        rgb = np.where(a[..., None] > 1e-6, self.rgb / np.maximum(a[..., None], 1e-6), 0.0)
        data = np.dstack([np.clip(rgb, 0, 1), a])
        return Image.fromarray((data * 255 + 0.5).astype(np.uint8), "RGBA")


def outline(sdf, inner, outer):
    """跨在轮廓上的描边：sdf 在 [-inner, outer] 内为 1，两端 1 像素抗锯齿。"""
    return np.clip(np.minimum(sdf + inner, outer - sdf) + 0.5, 0.0, 1.0)


def drop_shadow(alpha, dx, dy, radius, opacity):
    return blur(shift(alpha, dx, dy), radius) * opacity


def save(layer_or_image, path):
    img = layer_or_image.image() if isinstance(layer_or_image, Layer) else layer_or_image
    img.save(path)
    return img


def rgb(hex_color):
    hex_color = hex_color.lstrip("#")
    return np.array([int(hex_color[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
