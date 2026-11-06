"""烘焙哥特风 HUD 与场景道具贴图（参照 docs/reference/ui_style.webp）。

用法：python tools/bake_ui_art.py [组名 ...] [--preview 目录]
    组名：bones parchment flasks seals icons iron fight lantern ledger（不写则全部）
输出：assets/ui/*.png（显示尺寸 × S 倍分辨率，Godot 里缩小显示）
生成的 PNG 可以直接在绘图软件里继续手绘修改；改过的图不要再运行脚本覆盖。
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
from art_kit import *  # noqa: E402,F401,F403

OUT = "assets/ui"
S = 3  # 烘焙倍率
FONT_SC = r"C:/Windows/Fonts/NotoSerifSC-VF.ttf"
FONT_LATIN = r"C:/Windows/Fonts/georgiab.ttf"

INK = rgb("170f0a")
BONE_RAMP = [
    (0.00, rgb("140d08")),
    (0.16, rgb("3a2b1d")),
    (0.36, rgb("6e5b42")),
    (0.56, rgb("a1906d")),
    (0.76, rgb("cbbd99")),
    (0.92, rgb("e2d8bc")),
    (1.00, rgb("efe7d1")),
]


# ======================================================================
# 骨头
# ======================================================================

def shade_bone(X, Y, sdf, h, axis_angle, seed, holes=None, grime=1.0):
    nx, ny, nz = normals(h, 1.0)
    diff, ndh = lighting(nx, ny, nz, wrap=0.2)
    cav = cavity(h, 3.5 * S)
    grain = directional(X, Y, axis_angle, 0.03, 0.55, seed)
    blotch = fbm(X * 0.02, Y * 0.02, 4, seed + 7)
    # 明暗交界线用噪声打乱，再压成几档色阶：像一笔一笔涂出来的
    wobble = (fbm(X * 0.07, Y * 0.07, 3, seed + 13) - 0.5) * 0.22
    t = soft_bands(np.clip(diff * 0.95 + 0.05 + wobble, 0, 1), 5, 0.45)
    t = t + (grain - 0.5) * 0.12 + (blotch - 0.5) * 0.14 * grime
    t = t - np.clip(cav * 0.07, 0.0, 0.5)
    t = t + np.clip(-cav * 0.05, 0.0, 0.12)
    # 离轮廓近的地方压暗一圈（背光侧更多）：体积感更强
    gx, gy = np.gradient(sdf)
    gl = np.sqrt(gx * gx + gy * gy) + 1e-9
    away = np.clip(-(gx / gl * LIGHT[0] + gy / gl * LIGHT[1]) / np.hypot(LIGHT[0], LIGHT[1]), 0, 1)
    rim = np.clip(1.0 + sdf / (2.2 * S), 0, 1)
    t = t - rim * (0.1 + 0.25 * away)
    col = ramp(t, BONE_RAMP)
    # 陈年黄渍、污垢和毛孔
    stain = np.clip((fbm(X * 0.016, Y * 0.016, 3, seed + 11) - 0.5) * 2.6, 0, 1) * grime
    col = col * (1 - stain[..., None] * 0.32) + rgb("6e4f2a") * (stain[..., None] * 0.32)
    dirt = np.clip((fbm(X * 0.05, Y * 0.05, 4, seed + 17) - 0.58) * 4, 0, 1) * np.clip(cav * 0.3 + 0.3, 0, 1) * grime
    col = col * (1 - dirt[..., None] * 0.5) + rgb("2e2216") * (dirt[..., None] * 0.5)
    f1, _ = worley(X * 0.18, Y * 0.18, seed + 3)
    pores = np.clip(1.0 - f1 / 0.17, 0, 1) * (vnoise(X * 0.04, Y * 0.04, seed + 9) > 0.45)
    col = col * (1 - pores[..., None] * 0.3)
    col = col + (ndh ** 30 * 0.16)[..., None] * rgb("fff2d6")
    # 细裂纹
    crack = ridged(X * 0.02, Y * 0.02, 3, seed + 21)
    crack = np.clip((crack - 0.935) * 26, 0, 1) * (fbm(X * 0.009, Y * 0.009, 2, seed + 22) > 0.55)
    col = col * (1 - crack[..., None] * 0.7) + INK * (crack[..., None] * 0.7)
    if holes is not None:
        depth = np.clip(holes, 0, 1)
        hole_col = ramp(np.clip(0.22 - depth * 0.3 + (diff - 0.5) * 0.1, 0, 1), BONE_RAMP)
        col = col * (1 - depth[..., None]) + hole_col * depth[..., None]
    return col


def finish(sdf, col, ink=(0.45 * S, 0.55 * S), heavy=0.6 * S, shadow=(int(1.2 * S), int(2 * S), 2.2 * S, 0.55),
           ink_color=INK):
    """墨线描边（背光一侧加粗 heavy）+ 投影。"""
    h, w = sdf.shape
    gx, gy = np.gradient(sdf)
    gl = np.sqrt(gx * gx + gy * gy) + 1e-9
    away = np.clip(-(gx / gl * LIGHT[0] + gy / gl * LIGHT[1]) / np.hypot(LIGHT[0], LIGHT[1]), 0, 1)
    outer = ink[1] + heavy * away ** 1.5
    layer = Layer(w, h)
    total = coverage(sdf - outer)
    if shadow:
        layer.over(np.zeros((h, w, 3)), drop_shadow(total, *shadow))
    layer.over(col, coverage(sdf))
    line = np.clip(np.minimum(sdf + ink[0], outer - sdf) + 0.5, 0.0, 1.0)
    layer.over(np.broadcast_to(ink_color, (h, w, 3)), line)
    return layer


def long_bone_shape(X, Y, a, b, r_shaft, r_end, seed=0, flare=0.55):
    ax, ay = a
    bx, by = b
    length = math.hypot(bx - ax, by - ay)
    ux, uy = (bx - ax) / length, (by - ay) / length
    px, py = -uy, ux
    angle = math.atan2(uy, ux)
    a2 = (ax + ux * r_end * 1.1, ay + uy * r_end * 1.1)
    b2 = (bx - ux * r_end * 1.1, by - uy * r_end * 1.1)
    d, t = sd_segment(X, Y, a2[0], a2[1], b2[0], b2[1])
    # 骨干中段细、两端渐粗，带一点不对称的弯
    bend = np.sin(t * math.pi) * r_shaft * 0.35
    r = r_shaft * (1 + flare * np.abs(2 * t - 1) ** 3.5)
    shaft = d - r + bend * 0.0
    sdfs = [shaft]
    heights = [tube_height(shaft, r)]
    for ex, ey, sgn, big in ((ax, ay, 1, 0.9), (bx, by, -1, 1.0)):
        for side, scale, along in ((-1, 0.84, 0.92), (1, 0.72, 1.02)):
            rr = r_end * scale * big
            cx = ex + ux * sgn * rr * along + px * side * r_end * 0.48
            cy = ey + uy * sgn * rr * along + py * side * r_end * 0.48
            s = sd_circle(X, Y, cx, cy, rr)
            sdfs.append(s)
            heights.append(tube_height(s, rr) * 0.92)
    sdf = sdfs[0]
    for s in sdfs[1:]:
        sdf = smin(sdf, s, r_shaft * 1.3)
    hgt = np.maximum.reduce(heights)
    hgt = np.maximum(hgt, tube_height(sdf, r_shaft * 0.75))
    # 两个髁之间的凹口
    for ex, ey, sgn in ((ax, ay, 1), (bx, by, -1)):
        g = sd_ellipse(X, Y, ex - ux * sgn * r_end * 0.05, ey - uy * sgn * r_end * 0.05,
                       r_end * 0.42, r_end * 0.2, angle)
        sdf = smax(sdf, -g, 1.4 * S)
    hgt = blur(hgt, 0.8 * S / 3)
    return sdf, hgt, angle


def bake_long_bone(path, length, r_shaft, r_end, vertical, seed):
    """竖骨/横骨：三段式贴图（两端髁 + 可拉伸的骨干）。"""
    pad = int(r_end * 1.2 + 4 * S)
    if vertical:
        w, h = int(r_end * 2.4 + 8 * S), int(length + 2 * pad)
        a, b = (w / 2, pad), (w / 2, h - pad)
    else:
        w, h = int(length + 2 * pad), int(r_end * 2.4 + 8 * S)
        a, b = (pad, h / 2), (w - pad, h / 2)
    X, Y = grid(w, h)
    sdf, hgt, angle = long_bone_shape(X, Y, a, b, r_shaft, r_end, seed)
    col = shade_bone(X, Y, sdf, hgt, angle, seed)
    return save(finish(sdf, col), path)


def bake_skull(path, seed=5):
    """正面略俯视的头骨：深眼窝、倒心形鼻孔、颧骨、残缺的牙。"""
    w, h = 44 * S, 50 * S
    X, Y = grid(w, h)
    s = S
    cx = w / 2
    cran = sd_ellipse(X, Y, cx, 18.5 * s, 18 * s, 16.8 * s)
    # 太阳穴往里收一点，脸部比头盖骨窄
    temple_l = sd_ellipse(X, Y, cx - 21.5 * s, 26 * s, 5.5 * s, 7 * s)
    temple_r = sd_ellipse(X, Y, cx + 21.5 * s, 26 * s, 5.5 * s, 7 * s)
    cheek_l = sd_ellipse(X, Y, cx - 10.8 * s, 27.5 * s, 5.0 * s, 3.6 * s, 0.4)
    cheek_r = sd_ellipse(X, Y, cx + 10.8 * s, 27.5 * s, 5.0 * s, 3.6 * s, -0.4)
    maxilla = sd_rbox(X, Y, cx, 31.8 * s, 8.6 * s, 4.6 * s, 3.0 * s)
    jaw = sd_rbox(X, Y, cx, 39.6 * s, 7.6 * s, 4.4 * s, 3.4 * s)
    chin = sd_ellipse(X, Y, cx, 43.2 * s, 4.6 * s, 2.2 * s)
    sdf = smin(cran, cheek_l, 3.2 * s)
    sdf = smin(sdf, cheek_r, 3.2 * s)
    sdf = smin(sdf, maxilla, 3.6 * s)
    sdf = smax(sdf, -temple_l, 2.5 * s)
    sdf = smax(sdf, -temple_r, 2.5 * s)
    jaw_sdf = smin(jaw, chin, 1.5 * s)
    sdf = np.minimum(sdf, jaw_sdf)
    hgt = np.maximum.reduce([
        tube_height(cran, 16.8 * s) * 0.9,
        tube_height(cheek_l, 3.6 * s) + 6.5 * s,
        tube_height(cheek_r, 3.6 * s) + 6.5 * s,
        bevel_height(maxilla, 3.2 * s, 9.5 * s),
        bevel_height(jaw_sdf, 3.2 * s, 7.0 * s),
    ])
    hgt = np.maximum(hgt, bevel_height(sdf, 2.4 * s, 3.5 * s))
    # 眉弓：眼窝上缘隆起
    brow = np.exp(-((Y - 17.2 * s) / (1.4 * s)) ** 2) * (np.abs(X - cx) < 14 * s) * (np.abs(X - cx) > 1.6 * s)
    hgt = hgt + brow * 1.6 * s
    # 上下牙之间的缝 + 牙齿竖缝（缺一颗）
    mouth = np.exp(-((Y - 35.4 * s) / (0.55 * s)) ** 2) * (np.abs(X - cx) < 7.4 * s)
    hgt = hgt - mouth * 3.5 * s
    gaps = np.zeros_like(X)
    for i in range(-3, 4):
        x = cx + i * 2.35 * s + (0.3 * s if i % 2 else 0)
        gaps = np.maximum(gaps, np.exp(-((X - x) / (0.35 * s)) ** 2) * ((Y > 32.4 * s) & (Y < 38.6 * s)))
    hgt = hgt - gaps * 1.8 * s
    missing = sd_rbox(X, Y, cx + 3.6 * s, 33.9 * s, 1.0 * s, 1.5 * s, 0.4 * s)
    # 眼窝：圆角略方、外眼角下垂；鼻孔：倒心形
    eye_l = sd_rbox(X, Y, cx - 6.9 * s, 22.4 * s, 4.6 * s, 4.1 * s, 2.6 * s, 0.22)
    eye_r = sd_rbox(X, Y, cx + 6.9 * s, 22.4 * s, 4.6 * s, 4.1 * s, 2.6 * s, -0.22)
    nose_l = sd_ellipse(X, Y, cx - 1.1 * s, 27.6 * s, 1.3 * s, 2.3 * s, 0.35)
    nose_r = sd_ellipse(X, Y, cx + 1.1 * s, 27.6 * s, 1.3 * s, 2.3 * s, -0.35)
    tri = sd_polygon(X, Y, [(cx - 2.2 * s, 27.5 * s), (cx + 2.2 * s, 27.5 * s), (cx, 31.0 * s)])
    nose = smin(np.minimum(nose_l, nose_r), tri, 0.8 * s)
    holes = np.minimum.reduce([eye_l, eye_r, nose, missing])
    # 深度：越往里越深
    depth = np.clip(-holes / (2.6 * s), 0, 1)
    hgt = hgt - depth * 10 * s
    hgt = blur(hgt, 0.5 * s)
    # 头顶裂缝
    crack_pts = [(cx + 2.5 * s, 2.0 * s), (cx + 4.6 * s, 5.8 * s), (cx + 3.2 * s, 8.4 * s), (cx + 6.4 * s, 11.6 * s),
                 (cx + 5.0 * s, 14.2 * s)]
    crack, _ = sd_polyline(X, Y, crack_pts, [0.5 * s, 0.45 * s, 0.4 * s, 0.3 * s, 0.15 * s])
    col = shade_bone(X, Y, sdf, hgt, math.pi / 2, seed, holes=depth)
    c = coverage(crack) * (sdf < -0.5 * s)
    col = col * (1 - c[..., None] * 0.85) + INK * (c[..., None] * 0.85)
    return save(finish(sdf, col), path)


def bake_vertebra(path, seed, tilt=0.0, width=1.0):
    """正面看的一节椎骨：腰鼓形椎体（上下缘外翻）、两侧粗短的横突。"""
    w, h = 30 * S, 16 * S
    X, Y = grid(w, h)
    s = S
    cx, cy = w / 2, h / 2 - 0.6 * s
    c, sn = math.cos(tilt), math.sin(tilt)

    def rot(x, y):
        return cx + x * c - y * sn, cy + x * sn + y * c

    body = sd_rbox(X, Y, cx, cy, 5.8 * s * width, 4.3 * s, 2.6 * s, tilt)
    waist_l = sd_ellipse(X, Y, *rot(-7.6 * s * width, 0), 2.6 * s, 1.6 * s, tilt)
    waist_r = sd_ellipse(X, Y, *rot(7.6 * s * width, 0), 2.6 * s, 1.6 * s, tilt)
    body = smax(body, -np.minimum(waist_l, waist_r), 1.0 * s)
    parts = [body]
    heights = [bevel_height(body, 2.8 * s, 5.0 * s)]
    for side in (-1, 1):
        a = rot(side * 4.0 * s * width, -0.6 * s)
        b = rot(side * 8.6 * s * width, 1.2 * s)
        proc, r = sd_capsule(X, Y, a, b, 2.1 * s, 1.5 * s)
        knob = sd_circle(X, Y, *rot(side * 9.2 * s * width, 1.5 * s), 1.9 * s)
        proc = smin(proc, knob, 0.8 * s)
        parts.append(proc)
        heights.append(np.maximum(tube_height(proc, r) * 0.85, tube_height(knob, 1.6 * s) * 0.85))
    sdf = parts[0]
    for part in parts[1:]:
        sdf = smin(sdf, part, 1.3 * s)
    hgt = np.maximum.reduce(heights)
    hgt = np.maximum(hgt, bevel_height(sdf, 0.9 * s, 1.4 * s))
    # 椎体上下缘（终板）外翻成两道棱
    u = (X - cx) * c + (Y - cy) * sn
    v = -(X - cx) * sn + (Y - cy) * c
    for edge in (-3.0 * s, 3.0 * s):
        hgt = hgt + np.exp(-((v - edge) / (0.55 * s)) ** 2) * (np.abs(u) < 5.0 * s * width) * 0.8 * s
    hgt = blur(hgt, 0.45 * s)
    col = shade_bone(X, Y, sdf, hgt, tilt, seed)
    return save(finish(sdf, col, heavy=0.5 * S, shadow=(int(0.8 * S), int(1.4 * S), 1.4 * S, 0.5)), path)


def bake_charm(path, seed=41):
    """挂在横骨上的小坠子：一根绳 + 一颗骨珠 + 一枚獠牙。"""
    w, h = 14 * S, 32 * S
    X, Y = grid(w, h)
    s = S * 1.0
    cx = w / 2
    cord, _ = sd_polyline(X, Y, [(cx, 0), (cx + 0.4 * s, 6 * s), (cx, 11 * s)], [0.45 * s] * 3)
    bead = sd_circle(X, Y, cx, 12.6 * s, 2.2 * s)
    fang_pts = bezier((cx - 0.3 * s, 14.2 * s), (cx + 2.6 * s, 18 * s), (cx + 2.4 * s, 24 * s), (cx - 1.8 * s, 29.5 * s), 30)
    radii = [2.1 * s * (1 - i / 30) ** 0.8 + 0.25 * s for i in range(31)]
    fang, fr = sd_polyline(X, Y, fang_pts, radii)
    sdf = np.minimum(bead, fang)
    hgt = np.maximum(tube_height(bead, 2.2 * s), tube_height(fang, fr))
    col = shade_bone(X, Y, sdf, hgt, 1.3, seed)
    layer = finish(sdf, col, shadow=(int(0.8 * S), int(1.2 * S), 1.2 * S, 0.45))
    cord_cov = coverage(cord) * (bead > 0)
    layer.under(np.broadcast_to(rgb("2a2018"), layer.rgb.shape), cord_cov)
    return save(layer, path)


def bake_bones():
    out = {}
    out["bone_long_v"] = bake_long_bone(f"{OUT}/bone_long_v.png", 200 * S, 3.1 * S, 6.4 * S, True, 11)
    out["bone_long_h"] = bake_long_bone(f"{OUT}/bone_long_h.png", 220 * S, 3.2 * S, 6.6 * S, False, 12)
    out["bone_arm"] = bake_long_bone(f"{OUT}/bone_arm.png", 92 * S, 2.3 * S, 4.6 * S, False, 13)
    out["skull"] = bake_skull(f"{OUT}/skull.png")
    for i, (tilt, width) in enumerate(((0.0, 1.0), (0.07, 0.94), (-0.06, 1.05))):
        out[f"vertebra_{i}"] = bake_vertebra(f"{OUT}/vertebra_{i}.png", 30 + i, tilt, width)
    out["charm"] = bake_charm(f"{OUT}/charm.png")
    return out



# ======================================================================
# 羊皮卷格子
# ======================================================================

PARCH_RAMP = [
    (0.00, rgb("2b1a0d")),
    (0.18, rgb("5a3d22")),
    (0.38, rgb("8d6c45")),
    (0.58, rgb("b8996b")),
    (0.78, rgb("d4bd91")),
    (1.00, rgb("e6d6b2")),
]


def bake_parchment(path, seed, size=64, canvas=80, bites=4, folds=1, edge=9.0, stops=None, dirt=1.0):
    """一块旧羊皮卷：撕边、焦边、纤维、斑点、水渍、折痕，边缘压暗，带投影。
    size、canvas 是显示尺寸，一个数是正方形，也可以给 (宽, 高)；edge 是边缘压暗那一圈有多宽；
    stops 是色阶（默认黄褐的羊皮卷）；dirt 是脏的程度（斑块、霉点、水渍、折痕），1 = 原来的样子。"""
    stops = PARCH_RAMP if stops is None else stops
    sw, sh = (size, size) if np.isscalar(size) else size
    cw, ch = (canvas, canvas) if np.isscalar(canvas) else canvas
    W, H = cw * S, ch * S
    X, Y = grid(W, H)
    cx, cy = W / 2, H / 2
    hx, hy = sw * S / 2, sh * S / 2
    rng = np.random.default_rng(seed)
    base = sd_rbox(X, Y, cx, cy, hx, hy, 2.0 * S)
    warp = (fbm(X * 0.011, Y * 0.011, 3, seed) - 0.5) * 4.0 * S
    fray = (fbm(X * 0.08, Y * 0.08, 3, seed + 1) - 0.5) * 1.4 * S
    sdf = base + warp + fray
    # 沿边咬掉几个缺口
    for _ in range(bites):
        side = rng.integers(4)
        t = rng.uniform(-0.8, 0.8)
        px, py = [(cx + t * hx, cy - hy), (cx + hx, cy + t * hy), (cx + t * hx, cy + hy), (cx - hx, cy + t * hy)][side]
        r = rng.uniform(1.2, 2.6) * S
        bite = sd_circle(X, Y, px, py, r) + (fbm(X * 0.1, Y * 0.1, 2, seed + 50) - 0.5) * 1.5 * S
        sdf = smax(sdf, -bite, 0.8 * S)
    inside = np.clip(-sdf, 0, None)

    angle = rng.uniform(-0.3, 0.3)
    tone = fbm(X * 0.009, Y * 0.009, 4, seed + 3)
    mott = fbm(X * 0.035, Y * 0.035, 4, seed + 4)
    fiber = directional(X, Y, angle, 0.012, 0.42, seed + 5, 4)
    fiber2 = directional(X, Y, angle + 1.4, 0.02, 0.6, seed + 15, 3)
    grain = vnoise(X * 0.7, Y * 0.7, seed + 6)
    t = (0.66 + (tone - 0.5) * 0.55 * (0.4 + 0.6 * dirt) + (mott - 0.5) * 0.32 * dirt
         + (fiber - 0.5) * 0.05 + (fiber2 - 0.5) * 0.03 + (grain - 0.5) * 0.05)
    # 边缘逐渐变暗变黄，最外一圈是焦黑的毛边
    rim = np.clip(inside / (edge * S), 0, 1)
    t = t - (1 - rim) ** 1.6 * 0.42
    burn = np.clip(1 - inside / (1.6 * S) + (fbm(X * 0.12, Y * 0.12, 2, seed + 7) - 0.5) * 0.9, 0, 1)
    t = t - burn * 0.35
    # 霉斑（小褐点）
    f1, _ = worley(X * 0.06, Y * 0.06, seed + 8)
    pick = vnoise(np.floor(X * 0.06) * 7.1, np.floor(Y * 0.06) * 3.7, seed + 9)
    spots = np.clip(1 - f1 / (0.1 + 0.12 * pick), 0, 1) ** 1.5 * (pick > 0.8)
    f1b, _ = worley(X * 0.15 + 3.3, Y * 0.15 - 1.7, seed + 10)
    specks = np.clip(1 - f1b / 0.1, 0, 1) * (fbm(X * 0.02, Y * 0.02, 2, seed + 11) > 0.62)
    t = t - (spots * 0.2 + specks * 0.08) * dirt
    # 水渍：一圈深色的潮痕
    blob = fbm(X * 0.014 + 3.0, Y * 0.014, 3, seed + 12)
    tide = np.exp(-((blob - 0.62) / 0.035) ** 2) * np.clip((blob - 0.55) * 8, 0, 1)
    t = t - (tide * 0.06 + np.clip((blob - 0.62) * 5, 0, 1) * 0.07) * dirt
    # 折痕：斜线，两侧一亮一暗
    for k in range(folds):
        fa = rng.uniform(0, math.pi)
        fx, fy = math.cos(fa), math.sin(fa)
        off = rng.uniform(-0.25, 0.25) * min(hx, hy)
        fd = (X - cx) * fy - (Y - cy) * fx - off + (fbm(X * 0.02, Y * 0.02, 2, seed + 13 + k * 31) - 0.5) * 3 * S
        t = t - (np.exp(-(fd / (0.9 * S)) ** 2) * 0.05 - np.exp(-((fd - 1.8 * S) / (1.6 * S)) ** 2) * 0.03) * dirt
    col = ramp(t, stops)
    # 纸面起伏的光影
    bump = fbm(X * 0.045, Y * 0.045, 4, seed + 14) * 2.5 * S + fiber * 0.6 * S
    nx, ny, nz = normals(bump, 1.0)
    diff, _ = lighting(nx, ny, nz, 0.6)
    col = col * (0.86 + 0.2 * diff)[..., None]
    # 霉斑带一点偏冷的灰绿
    col = col * (1 - spots[..., None] * 0.15 * dirt) + rgb("4a4a32") * (spots[..., None] * 0.15 * dirt)
    layer = Layer(W, H)
    alpha = coverage(sdf)
    layer.over(np.zeros((H, W, 3)), drop_shadow(alpha, int(1.6 * S), int(2.4 * S), 2.6 * S, 0.7))
    layer.over(col, alpha)
    return save(layer, path)


def bake_parchments():
    out = {}
    for i in range(4):
        out[f"parchment_{i}"] = bake_parchment(f"{OUT}/parchment_{i}.png", 100 + i * 7)
    return out



# ======================================================================
# 通用材质着色
# ======================================================================

def shade_material(X, Y, sdf, h, stops, seed, grain_angle=0.0, grain=0.1, blotch=0.12, spec=0.15,
                   spec_power=30, bands=5, rim_dark=0.3, cav_dark=0.07, wobble=0.2):
    nx, ny, nz = normals(h, 1.0)
    diff, ndh = lighting(nx, ny, nz, wrap=0.2)
    cav = cavity(h, 3.0 * S)
    wob = (fbm(X * 0.07, Y * 0.07, 3, seed + 13) - 0.5) * wobble
    t = soft_bands(np.clip(diff * 0.95 + 0.05 + wob, 0, 1), bands, 0.45)
    t = t + (directional(X, Y, grain_angle, 0.03, 0.5, seed) - 0.5) * grain
    t = t + (fbm(X * 0.02, Y * 0.02, 4, seed + 7) - 0.5) * blotch
    t = t - np.clip(cav * cav_dark, 0.0, 0.5) + np.clip(-cav * 0.05, 0.0, 0.12)
    gx, gy = np.gradient(sdf)
    gl = np.sqrt(gx * gx + gy * gy) + 1e-9
    away = np.clip(-(gx / gl * LIGHT[0] + gy / gl * LIGHT[1]) / np.hypot(LIGHT[0], LIGHT[1]), 0, 1)
    t = t - np.clip(1.0 + sdf / (2.0 * S), 0, 1) * (0.08 + rim_dark * away)
    col = ramp(t, stops)
    col = col + (ndh ** spec_power * spec)[..., None]
    return col


WOOD = [(0.0, rgb("150d07")), (0.25, rgb("3b2414")), (0.5, rgb("6a4527")), (0.75, rgb("94693e")), (1.0, rgb("b88d5a"))]
LEAD = [(0.0, rgb("0d0e12")), (0.3, rgb("2a2c33")), (0.55, rgb("4c4f58")), (0.8, rgb("7b7f88")), (1.0, rgb("aeb2b8"))]
FISH = [(0.0, rgb("0f0c16")), (0.25, rgb("2c2540")), (0.5, rgb("4f4568")), (0.75, rgb("7b7194")), (1.0, rgb("a9a3be"))]
SAND = [(0.0, rgb("3b2410")), (0.4, rgb("8a5a2a")), (0.75, rgb("c08a4a")), (1.0, rgb("e0b47a"))]


# ======================================================================
# 药瓶（饵料）：玻璃 + 木塞；液体单独一张灰度图，在 Godot 里按饵料主属性着色
# ======================================================================

def flask_geometry(X, Y, kind):
    s = S
    cx = X.shape[1] / 2
    if kind == "round":       # 骨罐：圆底烧瓶
        body = sd_circle(X, Y, cx, 33 * s, 13.5 * s)
        neck = sd_rbox(X, Y, cx, 18 * s, 4.0 * s, 6 * s, 1.0 * s)
        lip = sd_rbox(X, Y, cx, 12.2 * s, 5.6 * s, 1.5 * s, 1.2 * s)
        cork = sd_rbox(X, Y, cx, 8.4 * s, 3.6 * s, 3.0 * s, 1.2 * s)
        fill_y = 27.5 * s
        body_r = 13.5 * s
    elif kind == "jar":       # 陶罐：矮胖的广口罐
        body = sd_rbox(X, Y, cx, 32 * s, 14 * s, 12.5 * s, 7.5 * s)
        neck = sd_rbox(X, Y, cx, 18.5 * s, 8.5 * s, 3 * s, 1.5 * s)
        lip = sd_rbox(X, Y, cx, 15.3 * s, 10.2 * s, 1.6 * s, 1.3 * s)
        cork = sd_rbox(X, Y, cx, 11.6 * s, 8.4 * s, 2.6 * s, 1.6 * s)
        fill_y = 25.5 * s
        body_r = 13 * s
    else:                     # 铜壶：细长颈的瓶子
        body = sd_ellipse(X, Y, cx, 35 * s, 11.5 * s, 12.5 * s)
        neck = sd_rbox(X, Y, cx, 17 * s, 3.0 * s, 8.5 * s, 1.0 * s)
        lip = sd_rbox(X, Y, cx, 8.6 * s, 4.4 * s, 1.4 * s, 1.1 * s)
        cork = sd_rbox(X, Y, cx, 5.2 * s, 2.8 * s, 2.6 * s, 1.0 * s)
        fill_y = 28.5 * s
        body_r = 12 * s
    glass = smin(smin(body, neck, 2.4 * s), lip, 0.8 * s)
    return glass, body, cork, fill_y, body_r


def bake_flask(name, kind, seed):
    w, h = 48 * S, 52 * S
    X, Y = grid(w, h)
    s = S
    cx = w / 2
    glass, body, cork, fill_y, body_r = flask_geometry(X, Y, kind)
    # 液体：瓶身内缩一圈、液面以下；液面是一道略亮的椭圆
    inner = body + 1.6 * s
    meniscus = fill_y + ((X - cx) / body_r) ** 2 * 1.2 * s
    liquid_a = coverage(np.maximum(inner, meniscus - Y))
    # 液体的明暗（灰度）：左上亮、右下暗，底部更暗，气泡更亮
    gx = (X - cx) / body_r
    gy = (Y - (fill_y + body_r * 0.5)) / body_r
    v = 0.62 - gx * 0.18 - gy * 0.22
    v = v + (fbm(X * 0.04, Y * 0.04, 3, seed) - 0.5) * 0.18
    surface = np.exp(-((Y - meniscus - 0.8 * s) / (0.9 * s)) ** 2)
    v = v + surface * 0.35
    rng = np.random.default_rng(seed)
    for _ in range(9):
        bx = cx + rng.uniform(-0.6, 0.6) * body_r
        by = fill_y + rng.uniform(0.15, 1.2) * body_r
        br = rng.uniform(0.5, 1.4) * s
        ring = np.exp(-((np.hypot(X - bx, Y - by) - br) / (0.35 * s)) ** 2)
        v = v + ring * 0.35
    v = np.clip(v, 0.05, 1.0)
    liquid = Layer(w, h)
    liquid.over(np.repeat(v[..., None], 3, axis=2), liquid_a)
    save(liquid, f"{OUT}/flask_{kind}_liquid.png")

    # 玻璃：中间很透、边缘较实（菲涅尔），左上一道高光，右侧反光
    edge = np.clip(1 + glass / (3.2 * s), 0, 1)
    glass_a = coverage(glass) * (0.16 + 0.55 * edge ** 1.6)
    glass_col = ramp(0.55 + edge * 0.25, [(0, rgb("2f4a48")), (1, rgb("9fbfb8"))])
    layer = Layer(w, h)
    shadow_a = coverage(np.minimum(glass, cork) - 0.6 * s)
    layer.over(np.zeros((h, w, 3)), drop_shadow(shadow_a, int(1.2 * s), int(1.8 * s), 1.8 * s, 0.5))
    layer.over(glass_col, glass_a)
    hl_pts = bezier((cx - body_r * 0.72, fill_y + body_r * 0.55), (cx - body_r * 0.9, fill_y - body_r * 0.1),
                    (cx - body_r * 0.6, fill_y - body_r * 0.55), (cx - body_r * 0.15, fill_y - body_r * 0.75), 30)
    hl, hr = sd_polyline(X, Y, hl_pts, [0.3 * s + 1.1 * s * math.sin(math.pi * i / 30) for i in range(31)])
    layer.over(np.ones((h, w, 3)), coverage(hl) * 0.8 * (body < 0))
    dot = sd_circle(X, Y, cx + body_r * 0.42, fill_y - body_r * 0.35, 1.1 * s)
    layer.over(np.ones((h, w, 3)), coverage(dot) * 0.7)
    rim_light = np.exp(-((body + 1.6 * s) / (0.7 * s)) ** 2) * np.clip((X - cx) / body_r, 0, 1) * (body < 0)
    layer.over(np.broadcast_to(rgb("cfe6e0"), (h, w, 3)), rim_light * 0.45)
    # 木塞
    cork_h = bevel_height(cork, 1.6 * s, 2.5 * s)
    cork_col = shade_material(X, Y, cork, cork_h, WOOD, seed + 3, grain_angle=0.0, grain=0.22, spec=0.05)
    layer.over(cork_col, coverage(cork))
    # 墨线：玻璃和木塞各自描边
    for shape in (glass, cork):
        gxs, gys = np.gradient(shape)
        gl = np.sqrt(gxs * gxs + gys * gys) + 1e-9
        away = np.clip(-(gxs / gl * LIGHT[0] + gys / gl * LIGHT[1]) / np.hypot(LIGHT[0], LIGHT[1]), 0, 1)
        outer = 0.5 * s + 0.6 * s * away ** 1.5
        line = np.clip(np.minimum(shape + 0.45 * s, outer - shape) + 0.5, 0.0, 1.0)
        layer.over(np.broadcast_to(INK, (h, w, 3)), line)
    return save(layer, f"{OUT}/flask_{kind}.png")


def bake_flasks():
    out = {}
    for i, kind in enumerate(("round", "jar", "bottle")):
        out[f"flask_{kind}"] = bake_flask(f"flask_{kind}", kind, 200 + i)
        out[f"flask_{kind}_liquid"] = Image.open(f"{OUT}/flask_{kind}_liquid.png")
    return out


# ======================================================================
# 印章：朱红方印，属性字镂空（白文）
# ======================================================================

SEAL_CHARS = {"rot": "腐", "blood": "血", "eye": "瞳", "grudge": "怨", "cold": "寒", "filth": "秽", "glow": "磷"}


def bake_seal(aspect, char, seed):
    w = 18 * S
    X, Y = grid(w, w)
    s = S
    rng = np.random.default_rng(seed)
    ang = rng.uniform(-0.12, 0.12)
    box = sd_rbox(X, Y, w / 2, w / 2, 7.6 * s, 7.6 * s, 1.2 * s, ang)
    box = box + (fbm(X * 0.12, Y * 0.12, 3, seed) - 0.5) * 1.2 * s
    # 字：用思源宋体最粗的字重渲染成遮罩
    font = ImageFont.truetype(FONT_SC, int(12.5 * s))
    font.set_variation_by_name("Black")
    mask = Image.new("L", (w, w), 0)
    d = ImageDraw.Draw(mask)
    bb = d.textbbox((0, 0), char, font=font)
    d.text(((w - (bb[2] - bb[0])) / 2 - bb[0], (w - (bb[3] - bb[1])) / 2 - bb[1]), char, fill=255, font=font)
    mask = mask.rotate(math.degrees(-ang), resample=Image.BICUBIC, center=(w / 2, w / 2))
    glyph = np.asarray(mask, dtype=np.float64) / 255.0
    # 印泥不均匀：零星的漏白和颗粒
    patchy = np.clip((fbm(X * 0.09, Y * 0.09, 4, seed + 1) - 0.32) * 4, 0, 1)
    speck = vnoise(X * 0.8, Y * 0.8, seed + 2) > 0.86
    ink_a = coverage(box) * (1 - glyph) * patchy * (1 - speck * 0.7)
    col = ramp(0.5 + (fbm(X * 0.05, Y * 0.05, 3, seed + 3) - 0.5) * 0.6,
               [(0, rgb("5e0d08")), (0.5, rgb("962018")), (1, rgb("b8352a"))])
    layer = Layer(w, w)
    layer.over(col, ink_a * 0.92)
    return save(layer, f"{OUT}/seal_{aspect}.png")


def bake_seals():
    return {f"seal_{k}": bake_seal(k, v, 300 + i) for i, (k, v) in enumerate(SEAL_CHARS.items())}


# ======================================================================
# 第一行格子的图标：测深锤（水层）、沙漏（时刻）、鱼（渔获）
# ======================================================================

def ink_finish(sdf, col, shadow=True):
    return finish(sdf, col, shadow=(int(1.0 * S), int(1.6 * S), 1.6 * S, 0.45) if shadow else None)


def bake_icon_depth(seed=400):
    w, h = 48 * S, 52 * S
    X, Y = grid(w, h)
    s = S
    cx = w / 2
    # 绳子 + 三个布条结（测深绳上的刻度）
    rope_pts = [(cx, 2 * s), (cx + 0.6 * s, 12 * s), (cx - 0.4 * s, 22 * s), (cx, 30 * s)]
    rope, rr = sd_polyline(X, Y, bezier(*rope_pts, steps=30), [0.75 * s] * 31)
    knots = []
    for k, ky in enumerate((9 * s, 16 * s, 23 * s)):
        knots.append(sd_ellipse(X, Y, cx + 0.2 * s, ky, 2.0 * s, 1.1 * s, 0.25 * (k - 1)))
    knot = np.minimum.reduce(knots)
    # 铅锤：上细下粗的长水滴
    lead = smin(sd_ellipse(X, Y, cx, 41 * s, 6.8 * s, 8.2 * s), sd_capsule(X, Y, (cx, 30 * s), (cx, 38 * s), 2.2 * s, 5.2 * s)[0], 2.5 * s)
    ring = sd_circle(X, Y, cx, 30.5 * s, 2.0 * s)
    ring = np.maximum(ring, -sd_circle(X, Y, cx, 30.5 * s, 1.0 * s))
    lead_h = np.maximum(tube_height(lead, 7 * s), tube_height(ring, 0.6 * s) * 1.5)
    lead_sdf = np.minimum(lead, ring)
    col = shade_material(X, Y, lead_sdf, lead_h, LEAD, seed, spec=0.35, spec_power=18, blotch=0.2)
    layer = ink_finish(lead_sdf, col)
    rope_h = tube_height(rope, rr) + 0.0
    rope_col = shade_material(X, Y, rope, rope_h, WOOD, seed + 1, grain_angle=1.2, grain=0.35, spec=0.03)
    rope_layer = ink_finish(rope, rope_col, shadow=False)
    layer.under(rope_layer.rgb, rope_layer.a)
    knot_h = tube_height(knot, 1.1 * s)
    knot_col = shade_material(X, Y, knot, knot_h, [(0, rgb("2a0c08")), (0.5, rgb("6e1f16")), (1, rgb("a8473a"))], seed + 2,
                              grain=0.25, spec=0.03)
    knot_layer = ink_finish(knot, knot_col, shadow=False)
    layer.over(knot_layer.rgb / np.maximum(knot_layer.a[..., None], 1e-6), knot_layer.a)
    return save(layer, f"{OUT}/icon_depth.png")


def bake_icon_time(seed=410):
    w, h = 48 * S, 52 * S
    X, Y = grid(w, h)
    s = S
    cx = w / 2
    top = sd_rbox(X, Y, cx, 6.5 * s, 13 * s, 2.0 * s, 1.0 * s)
    bottom = sd_rbox(X, Y, cx, 45.5 * s, 13 * s, 2.0 * s, 1.0 * s)
    posts = np.minimum(sd_rbox(X, Y, cx - 10.5 * s, 26 * s, 1.2 * s, 18 * s, 0.6 * s),
                       sd_rbox(X, Y, cx + 10.5 * s, 26 * s, 1.2 * s, 18 * s, 0.6 * s))
    frame = np.minimum.reduce([top, bottom, posts])
    frame_h = np.maximum(bevel_height(np.minimum(top, bottom), 1.2 * s, 2.2 * s), tube_height(posts, 1.2 * s))
    # 两个玻璃泡：圆角倒三角，中间细腰
    bulb_t = sd_ellipse(X, Y, cx, 16.5 * s, 7.6 * s, 8.4 * s)
    bulb_b = sd_ellipse(X, Y, cx, 35.5 * s, 7.6 * s, 8.4 * s)
    waist = sd_rbox(X, Y, cx, 26 * s, 1.1 * s, 3 * s, 0.5 * s)
    glass = smin(smin(bulb_t, bulb_b, 1.5 * s), waist, 1.6 * s)
    # 沙：上面剩一点、细细一线流下、下面堆成小山
    sand_top = np.maximum(bulb_t + 1.2 * s, (19.5 * s + ((X - cx) / (6 * s)) ** 2 * 2.5 * s) - Y)
    pile = (35.0 * s + np.abs(X - cx) * 0.55) - Y
    sand_bot = np.maximum(bulb_b + 1.2 * s, pile)
    stream = sd_rbox(X, Y, cx, 31 * s, 0.35 * s, 7 * s, 0.3 * s)
    sand = np.minimum.reduce([sand_top, sand_bot, stream])
    sand_col = shade_material(X, Y, sand, bevel_height(sand, 2 * s, 2 * s), SAND, seed + 1, grain=0.15, spec=0.02)
    layer = Layer(w, h)
    layer.over(np.zeros((h, w, 3)), drop_shadow(coverage(np.minimum(frame, glass)), int(1.0 * s), int(1.6 * s), 1.6 * s, 0.45))
    edge = np.clip(1 + glass / (2.5 * s), 0, 1)
    layer.over(ramp(edge, [(0, rgb("3d5552")), (1, rgb("a9c6bf"))]), coverage(glass) * (0.18 + 0.5 * edge ** 1.6))
    layer.over(sand_col, coverage(sand))
    hl = sd_ellipse(X, Y, cx - 3.8 * s, 14 * s, 1.0 * s, 3.4 * s, 0.25)
    layer.over(np.ones((h, w, 3)), coverage(hl) * 0.7)
    hl2 = sd_ellipse(X, Y, cx - 3.8 * s, 33 * s, 1.0 * s, 3.4 * s, 0.25)
    layer.over(np.ones((h, w, 3)), coverage(hl2) * 0.6)
    line = np.clip(np.minimum(glass + 0.45 * s, 0.9 * s - glass) + 0.5, 0.0, 1.0)
    layer.over(np.broadcast_to(INK, (h, w, 3)), line)
    frame_col = shade_material(X, Y, frame, frame_h, WOOD, seed, grain_angle=0.0, grain=0.25, spec=0.06)
    fl = ink_finish(frame, frame_col, shadow=False)
    layer.over(fl.rgb / np.maximum(fl.a[..., None], 1e-6), fl.a)
    return save(layer, f"{OUT}/icon_time.png")


def bake_icon_fish(seed=420):
    w, h = 52 * S, 44 * S
    X, Y = grid(w, h)
    s = S
    body = sd_ellipse(X, Y, 23 * s, 22 * s, 15.5 * s, 10.5 * s, -0.08)
    tail = sd_polygon(X, Y, [(36 * s, 22 * s), (47.5 * s, 12.5 * s), (44.5 * s, 22 * s), (48 * s, 32.5 * s)])
    sdf = smin(body, tail, 2.5 * s)
    # 背鳍：一排尖刺
    for i in range(5):
        bx = 14 * s + i * 4.3 * s
        by = 13.2 * s - math.sin((i + 0.5) / 5 * math.pi) * 1.4 * s
        spike = sd_polygon(X, Y, [(bx - 2.0 * s, by + 2.5 * s), (bx + 0.9 * s, by - 5.5 * s - (i % 2) * 1.2 * s), (bx + 2.2 * s, by + 2.5 * s)])
        sdf = smin(sdf, spike, 0.6 * s)
    belly_fin = sd_polygon(X, Y, [(18 * s, 30 * s), (21 * s, 37 * s), (26 * s, 31 * s)])
    sdf = smin(sdf, belly_fin, 0.6 * s)
    hgt = np.maximum(tube_height(body, 10.5 * s) * 0.8, bevel_height(sdf, 1.4 * s, 2.0 * s))
    # 鳞：Worley 网格压出浅凹
    f1, f2 = worley(X * 0.28, Y * 0.28 * 1.3, seed)
    scales = np.clip(1 - (f2 - f1) / 0.12, 0, 1) * (body < -1.5 * s) * (X > 14 * s)
    hgt = hgt - scales * 0.5 * s
    # 嘴：一道带牙的缝
    mouth = sd_capsule(X, Y, (8 * s, 25 * s), (14.5 * s, 23.5 * s), 0.6 * s)[0]
    hgt = hgt - coverage(mouth) * 2.5 * s
    col = shade_material(X, Y, sdf, hgt, FISH, seed, grain_angle=0.0, grain=0.08, spec=0.3, spec_power=16, blotch=0.18)
    # 腹部偏灰白、背部偏深紫
    belly = np.clip((Y - 22 * s) / (10 * s), 0, 1)
    col = col * (1 - belly[..., None] * 0.25) + rgb("8d8a90") * (belly[..., None] * 0.25)
    col = col * (1 - scales[..., None] * 0.18)
    eye = sd_circle(X, Y, 11.5 * s, 19.2 * s, 2.6 * s)
    pupil = sd_circle(X, Y, 11.9 * s, 19.4 * s, 1.1 * s)
    col = np.where((eye < 0)[..., None], rgb("c9b24a") * (0.75 + 0.35 * np.clip(-eye / (2.6 * s), 0, 1))[..., None], col)
    col = np.where((pupil < 0)[..., None], rgb("120d08"), col)
    teeth = (np.abs(Y - 24.2 * s) < 0.9 * s) & (np.sin(X / s * 2.2) > 0.4) & (X > 8.2 * s) & (X < 14 * s)
    col = np.where(teeth[..., None], rgb("e6dcc4"), col)
    layer = ink_finish(sdf, col)
    ring = np.clip(np.minimum(eye + 0.35 * s, 0.4 * s - eye) + 0.5, 0, 1)
    layer.over(np.broadcast_to(INK, layer.rgb.shape), ring)
    layer.over(np.broadcast_to(INK, layer.rgb.shape), coverage(mouth) * (sdf < 0))
    return save(layer, f"{OUT}/icon_fish.png")


def bake_icons():
    return {"icon_depth": bake_icon_depth(), "icon_time": bake_icon_time(), "icon_fish": bake_icon_fish()}



# ======================================================================
# 黑铁：张力计、罗盘、分隔线
# ======================================================================

IRON = [
    (0.00, rgb("040306")),
    (0.18, rgb("0e0c12")),
    (0.38, rgb("1c1922")),
    (0.58, rgb("2e2a37")),
    (0.78, rgb("474152")),
    (0.92, rgb("6a6479")),
    (1.00, rgb("948ea3")),
]
STEEL = [
    (0.00, rgb("08080a")),
    (0.2, rgb("1b1b21")),
    (0.42, rgb("36363f")),
    (0.64, rgb("595962")),
    (0.84, rgb("87878f")),
    (1.00, rgb("b8b8be")),
]


def shade_iron(X, Y, sdf, h, seed, stops=IRON, rust=1.0):
    """锻铁：锤痕起伏、细划痕、凸边磨亮、凹处积锈。"""
    f1, f2 = worley(X * 0.05, Y * 0.05, seed)
    hammered = h + (f1 - 0.35) * 0.4 * S
    nx, ny, nz = normals(hammered, 1.0)
    diff, ndh = lighting(nx, ny, nz, wrap=0.15)
    cav = cavity(h, 2.5 * S)
    wob = (fbm(X * 0.06, Y * 0.06, 3, seed + 13) - 0.5) * 0.18
    t = soft_bands(np.clip(diff * 0.9 + 0.04 + wob, 0, 1), 6, 0.5)
    t = t + (fbm(X * 0.02, Y * 0.02, 4, seed + 7) - 0.5) * 0.12
    t = t - np.clip(cav * 0.09, 0, 0.45)
    wear = np.clip(-cav * 0.08, 0, 0.3)
    t = t + wear
    gx, gy = np.gradient(sdf)
    gl = np.sqrt(gx * gx + gy * gy) + 1e-9
    away = np.clip(-(gx / gl * LIGHT[0] + gy / gl * LIGHT[1]) / np.hypot(LIGHT[0], LIGHT[1]), 0, 1)
    t = t - np.clip(1.0 + sdf / (1.6 * S), 0, 1) * 0.25 * away
    col = ramp(t, stops)
    # 细划痕
    scratch = directional(X, Y, 0.35, 0.004, 0.9, seed + 5, 2)
    scratch = np.clip((scratch - 0.72) * 6, 0, 1) * (fbm(X * 0.03, Y * 0.03, 2, seed + 6) > 0.55)
    col = col + scratch[..., None] * 0.07
    # 锈：铁锈红褐，长在凹处和边角
    rust_m = np.clip((fbm(X * 0.03, Y * 0.03, 4, seed + 9) - 0.52) * 3.5, 0, 1) * np.clip(cav * 0.25 + 0.2, 0, 1) * rust
    col = col * (1 - rust_m[..., None] * 0.55) + rgb("4a2416") * (rust_m[..., None] * 0.55)
    # 冷色高光（反射的是雾夜的天光）
    col = col + (ndh ** 40 * 0.18)[..., None] * rgb("cfe0e4") + (ndh ** 8 * 0.04)[..., None] * rgb("9fb3b8")
    return col


def scroll_stroke(X, Y, pts, r0, r1):
    n = len(pts)
    radii = [r0 + (r1 - r0) * (i / (n - 1)) ** 0.8 for i in range(n)]
    d, r = sd_polyline(X, Y, pts, radii)
    return d, tube_height(d, r)


def curl(cx, cy, r_start, r_end, a_start, turns, lead=None, steps=120):
    """卷草纹：可选的引线（从连接点过渡到螺线起点）+ 向内收的螺线。"""
    pts = spiral(cx, cy, r_start, r_end, a_start, turns, steps)
    if lead is not None:
        p0 = lead
        p3 = pts[0]
        tangent = (pts[1][0] - pts[0][0], pts[1][1] - pts[0][1])
        tl = math.hypot(*tangent) or 1
        k = math.hypot(p3[0] - p0[0], p3[1] - p0[1]) * 0.45
        p2 = (p3[0] - tangent[0] / tl * k, p3[1] - tangent[1] / tl * k)
        p1 = (p0[0] + (p2[0] - p0[0]) * 0.3, p0[1] + (p2[1] - p0[1]) * 0.3)
        pts = bezier(p0, p1, p2, p3, 24)[:-1] + pts
    return pts


class Iron:
    """把若干铁件的 (sdf, height) 叠起来。"""

    def __init__(self, X, Y):
        self.X, self.Y = X, Y
        self.sdf = np.full(X.shape, 1e6)
        self.h = np.zeros(X.shape)

    def add(self, sdf, h, k=0.0):
        self.sdf = smin(self.sdf, sdf, k) if k else np.minimum(self.sdf, sdf)
        self.h = np.maximum(self.h, h)

    def plate(self, sdf, height=2.4 * S, ridge=True, inner=None):
        """带双道凸棱的铁板（外缘一道、内框一道），中间是浅槽。"""
        h = bevel_height(sdf, 1.2 * S, height * 0.55)
        if ridge:
            h = h + ridge_height(sdf, 1.5 * S, 1.3 * S, height * 0.6)
        if inner is not None:
            h = h + ridge_height(-inner, 1.4 * S, 1.2 * S, height * 0.7) * (sdf < 0)
        self.add(sdf, h)

    def spear(self, pts, axis_a, axis_b, height=3.0 * S):
        sdf = sd_polygon(self.X, self.Y, pts)
        d, _ = sd_segment(self.X, self.Y, *axis_a, *axis_b)
        h = bevel_height(sdf, 2.2 * S, height * 0.7) + np.clip(1 - d / (2.2 * S), 0, 1) * height * 0.35 * (sdf < 0)
        self.add(sdf, h)

    def stroke(self, pts, r0, r1):
        d, h = scroll_stroke(self.X, self.Y, pts, r0, r1)
        self.add(d, h * 0.9)

    def rivet(self, x, y, r):
        d = sd_circle(self.X, self.Y, x, y, r)
        self.add(d, tube_height(d, r) + 1.2 * S)

    def ring(self, x, y, r_out, r_in, height=2.2 * S):
        d = np.maximum(sd_circle(self.X, self.Y, x, y, r_out), -sd_circle(self.X, self.Y, x, y, r_in))
        self.add(d, tube_height(d, (r_out - r_in) / 2) + height * 0.3)
        return d


def bake_gauge():
    w, h = 420 * S, 106 * S
    X, Y = grid(w, h)
    s = S
    iron = Iron(X, Y)
    # 主管：外框 + 玻璃窗
    outer = sd_rbox(X, Y, 210 * s, 44 * s, 158 * s, 18 * s, 2.5 * s)
    window = sd_rbox(X, Y, 210 * s, 44 * s, 148 * s, 10 * s, 1.5 * s)
    iron.plate(np.maximum(outer, -window), 3.0 * s, inner=window)
    # 左端：矛尖（带中脊和一道箍）+ 上下两道粗卷草 + 尖端圆球
    iron.spear([(60 * s, 31 * s), (42 * s, 34 * s), (20 * s, 44 * s), (42 * s, 54 * s), (60 * s, 57 * s)],
               (23 * s, 44 * s), (58 * s, 44 * s), 3.4 * s)
    collar = sd_rbox(X, Y, 50 * s, 44 * s, 2.2 * s, 9.5 * s, 1.0 * s)
    iron.add(collar, bevel_height(collar, 1.4 * s, 3.6 * s))
    iron.stroke(curl(33 * s, 20 * s, 11 * s, 2.6 * s, 0.35, -1.25, lead=(58 * s, 28 * s)), 3.3 * s, 1.1 * s)
    iron.stroke(curl(33 * s, 68 * s, 11 * s, 2.6 * s, -0.35, 1.25, lead=(58 * s, 60 * s)), 3.3 * s, 1.1 * s)
    tip = sd_circle(X, Y, 17 * s, 44 * s, 3.6 * s)
    iron.add(tip, tube_height(tip, 3.6 * s) + 0.8 * s)
    # 右端：斜尖 + 向上卷起的高卷草
    iron.spear([(360 * s, 28 * s), (374 * s, 28 * s), (390 * s, 44 * s), (374 * s, 60 * s), (360 * s, 60 * s)],
               (364 * s, 44 * s), (388 * s, 44 * s), 3.4 * s)
    collar = sd_rbox(X, Y, 370 * s, 44 * s, 2.2 * s, 9.5 * s, 1.0 * s)
    iron.add(collar, bevel_height(collar, 1.4 * s, 3.6 * s))
    iron.stroke(curl(397 * s, 15 * s, 12 * s, 2.8 * s, 2.25, 1.3, lead=(372 * s, 29 * s)), 3.5 * s, 1.1 * s)
    # 铆钉
    for x in (57, 363):
        iron.rivet(x * s, 33 * s, 1.7 * s)
        iron.rivet(x * s, 55 * s, 1.7 * s)
    # 铭牌：紧贴主管下方偏右，左端小矛尖 + 一道往上卷、搭在主管上的卷草；右端斜尖；嵌一个宝石座
    plate = sd_rbox(X, Y, 262 * s, 78 * s, 118 * s, 13 * s, 2.0 * s)
    panel = sd_rbox(X, Y, 258 * s, 78 * s, 108 * s, 8.5 * s, 1.2 * s)
    iron.plate(plate, 2.6 * s, inner=panel)
    iron.spear([(148 * s, 67 * s), (137 * s, 69 * s), (122 * s, 78 * s), (137 * s, 87 * s), (148 * s, 89 * s)],
               (125 * s, 78 * s), (147 * s, 78 * s), 2.8 * s)
    iron.stroke(curl(128 * s, 95 * s, 8 * s, 2.0 * s, -0.5, 1.2, lead=(146 * s, 88 * s)), 2.6 * s, 0.9 * s)
    iron.stroke(curl(118 * s, 62 * s, 6 * s, 1.6 * s, 0.9, -1.1, lead=(144 * s, 66 * s)), 2.2 * s, 0.8 * s)
    iron.spear([(376 * s, 67 * s), (386 * s, 67 * s), (397 * s, 78 * s), (386 * s, 89 * s), (376 * s, 89 * s)],
               (378 * s, 78 * s), (395 * s, 78 * s), 2.8 * s)
    iron.ring(366 * s, 78 * s, 7.6 * s, 4.6 * s)
    hgt = blur(iron.h, 0.5 * s)
    sdf = iron.sdf
    col = shade_iron(X, Y, sdf, hgt, 500)
    # 铭牌凹槽和宝石座内部：深色
    recess = coverage(panel) * 0.9
    col = col * (1 - recess[..., None]) + ramp(0.12 + (fbm(X * 0.05, Y * 0.05, 3, 77) - 0.5) * 0.1, IRON) * recess[..., None]
    socket = coverage(sd_circle(X, Y, 366 * s, 78 * s, 4.6 * s))
    col = col * (1 - socket[..., None]) + rgb("050406") * socket[..., None]
    layer = finish(sdf, col, ink=(0.4 * s, 0.5 * s), heavy=0.5 * s, shadow=(int(1.2 * s), int(2.2 * s), 2.4 * s, 0.6),
                   ink_color=rgb("030304"))
    # 玻璃管的反光：上缘一道亮线、下缘压暗（画在透明窗上，Godot 在下面画液柱）
    inside_w = coverage(window)
    top_hl = np.exp(-((Y - 37.5 * s) / (0.9 * s)) ** 2) * inside_w * np.clip((X - 70 * s) / (40 * s), 0, 1)
    layer.over(np.broadcast_to(rgb("e8f6f4"), (h, w, 3)), top_hl * 0.22)
    bottom_dark = np.clip((Y - 46 * s) / (8 * s), 0, 1) * inside_w
    layer.over(np.zeros((h, w, 3)), bottom_dark * 0.35)
    edge_shadow = np.clip(1 + window / (2.5 * s), 0, 1) * inside_w
    layer.over(np.zeros((h, w, 3)), edge_shadow * 0.45)
    return save(layer, f"{OUT}/gauge_frame.png")


def bake_compass():
    w, h = 140 * S, 158 * S
    X, Y = grid(w, h)
    s = S
    cx, cy = 70 * s, 88 * s
    r = np.hypot(X - cx, Y - cy)
    ang = np.arctan2(Y - cy, X - cx)
    iron = Iron(X, Y)
    # 表圈：粗外环 + 细内唇；顶上挂环
    bezel = np.maximum(r - 63 * s, 50.5 * s - r)
    bh = tube_height(np.maximum(r - 63 * s, 55 * s - r), 4.0 * s) + ridge_height(-(r - 52.8 * s) * 1.0 - 0.0, 0, 1.6 * s, 1.6 * s)
    iron.add(bezel, bh + 1.0 * s)
    knob = sd_rbox(X, Y, cx, 20 * s, 4.2 * s, 4.5 * s, 1.8 * s)
    iron.add(knob, bevel_height(knob, 1.8 * s, 3.2 * s))
    iron.ring(cx, 11 * s, 8.5 * s, 4.8 * s)
    # 外圈细密的滚花
    knurl = (np.sin(ang * 90) > 0.2) * (r > 61 * s) * (r < 63 * s)
    hgt = blur(iron.h, 0.5 * s) - knurl * 0.6 * s
    col = shade_iron(X, Y, iron.sdf, hgt, 510, STEEL, rust=0.6)
    layer = finish(iron.sdf, col, ink=(0.4 * s, 0.5 * s), heavy=0.5 * s, shadow=(int(1.4 * s), int(2.4 * s), 2.6 * s, 0.6),
                   ink_color=rgb("040405"))
    # 表盘：暗石板色，径向拉丝 + 外深内浅
    dial = coverage(r - 50.5 * s)
    brushed = directional(X - cx, Y - cy, 0.0, 0.002, 0.002, 520, 2)
    radial = fbm(ang * 30, r * 0.02, 3, 521)
    dv = 0.32 - np.clip((r - 30 * s) / (20 * s), 0, 1) * 0.1 + (radial - 0.5) * 0.08 + (brushed - 0.5) * 0.04
    dial_col = ramp(dv, [(0, rgb("07070b")), (0.3, rgb("1b1a24")), (0.6, rgb("343246")), (1, rgb("5a5872"))])
    layer.over(dial_col, dial)
    ink = Layer(w, h)
    bone = rgb("d9d2c0")
    # 刻度环：72 格，每 15° 一长格
    for i in range(72):
        a = i / 72 * math.tau - math.pi / 2
        long_tick = i % 6 == 0
        r0 = (40.5 if long_tick else 43.0) * s
        d, _ = sd_segment(X, Y, cx + math.cos(a) * r0, cy + math.sin(a) * r0,
                          cx + math.cos(a) * 47.5 * s, cy + math.sin(a) * 47.5 * s)
        ink.over(np.broadcast_to(bone, (h, w, 3)), coverage(d - (0.55 if long_tick else 0.35) * s) * 0.9)
    ring_line = np.abs(r - 39.3 * s) - 0.35 * s
    ink.over(np.broadcast_to(bone, (h, w, 3)), coverage(ring_line) * 0.6)
    # 罗经花：4 长 4 短，每个尖一半亮一半暗
    def point(a, length, width, light):
        tipx, tipy = cx + math.cos(a) * length, cy + math.sin(a) * length
        sx, sy = cx + math.cos(a + math.pi / 2) * width, cy + math.sin(a + math.pi / 2) * width
        tri = sd_polygon(X, Y, [(cx, cy), (sx, sy), (tipx, tipy)])
        ink.over(np.broadcast_to(light, (h, w, 3)), coverage(tri))
        tri2 = sd_polygon(X, Y, [(cx, cy), (tipx, tipy), (cx - (sx - cx), cy - (sy - cy))])
        ink.over(np.broadcast_to(light * 0.45, (h, w, 3)), coverage(tri2))
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4 - math.pi / 2
        point(a, 22 * s, 4.2 * s, rgb("5c5a6a"))
    for i in range(4):
        a = i * math.pi / 2 - math.pi / 2
        point(a, 33 * s, 5.2 * s, rgb("8a8798"))
    layer.over(ink.rgb / np.maximum(ink.a[..., None], 1e-6), ink.a)
    # 字母
    font = ImageFont.truetype(FONT_LATIN, int(12 * s))
    img = layer.image()
    d = ImageDraw.Draw(img)
    for letter, a in (("N", -math.pi / 2), ("E", 0), ("S", math.pi / 2), ("W", math.pi)):
        x = cx + math.cos(a) * 30.5 * s
        y = cy + math.sin(a) * 30.5 * s
        bb = d.textbbox((0, 0), letter, font=font)
        tx = x - (bb[2] - bb[0]) / 2 - bb[0]
        ty = y - (bb[3] - bb[1]) / 2 - bb[1]
        d.text((tx + s * 0.6, ty + s * 0.6), letter, fill=(0, 0, 0, 200), font=font)
        d.text((tx, ty), letter, fill=(222, 214, 196, 255), font=font)
    img.save(f"{OUT}/compass_body.png")
    # 玻璃罩：左上一道月牙反光（画在指针上面）
    glass = Layer(w, h)
    crescent = np.maximum(r - 47 * s, -(np.hypot(X - cx - 7 * s, Y - cy - 9 * s) - 46 * s))
    glass.over(np.ones((h, w, 3)), coverage(crescent) * 0.13 * np.clip((cy - Y) / (40 * s) + 0.4, 0, 1))
    spot = sd_ellipse(X, Y, cx - 24 * s, cy - 26 * s, 5 * s, 2.4 * s, -0.8)
    glass.over(np.ones((h, w, 3)), coverage(spot) * 0.22)
    save(glass, f"{OUT}/compass_glass.png")
    # 指针：北半铜红、南半钢灰，左右两面一亮一暗；轴心在贴图正中
    nw, nh = 18 * S, 82 * S
    NX, NY = grid(nw, nh)
    ncx, ncy = nw / 2, nh / 2
    needle = Layer(nw, nh)
    tip_n, tip_s, half_w = 36 * s, 30 * s, 4.2 * s
    halves = [
        ([(ncx, ncy), (ncx - half_w, ncy), (ncx, ncy - tip_n)], rgb("b5452c")),
        ([(ncx, ncy), (ncx, ncy - tip_n), (ncx + half_w, ncy)], rgb("6e2216")),
        ([(ncx, ncy), (ncx, ncy + tip_s), (ncx - half_w, ncy)], rgb("9a9aa4")),
        ([(ncx, ncy), (ncx + half_w, ncy), (ncx, ncy + tip_s)], rgb("4c4c56")),
    ]
    full = sd_polygon(NX, NY, [(ncx, ncy - tip_n), (ncx + half_w, ncy), (ncx, ncy + tip_s), (ncx - half_w, ncy)])
    needle.over(np.zeros((nh, nw, 3)), drop_shadow(coverage(full), int(1.0 * s), int(1.6 * s), 1.4 * s, 0.6))
    for pts, c in halves:
        needle.over(np.broadcast_to(c, (nh, nw, 3)), coverage(sd_polygon(NX, NY, pts)))
    needle.over(np.broadcast_to(rgb("08080a"), (nh, nw, 3)), np.clip(np.minimum(full + 0.35 * s, 0.45 * s - full) + 0.5, 0, 1))
    hub = sd_circle(NX, NY, ncx, ncy, 3.4 * s)
    hub_col = shade_iron(NX, NY, hub, tube_height(hub, 3.4 * s), 530, STEEL, rust=0)
    hl = finish(hub, hub_col, ink=(0.3 * s, 0.4 * s), heavy=0.3 * s, shadow=None, ink_color=rgb("08080a"))
    needle.over(hl.rgb / np.maximum(hl.a[..., None], 1e-6), hl.a)
    save(needle, f"{OUT}/compass_needle.png")
    return img


def bake_divider():
    """标题下的装饰线：中间菱形 + 两侧渐细的铁条，末端小卷草。"""
    w, h = 360 * S, 26 * S
    X, Y = grid(w, h)
    s = S
    cx, cy = w / 2, 12 * s
    iron = Iron(X, Y)
    for side in (-1, 1):
        bar, br = sd_capsule(X, Y, (cx + side * 9 * s, cy), (cx + side * 150 * s, cy), 1.7 * s, 0.5 * s)
        iron.add(bar, tube_height(bar, br))
        iron.stroke(curl(cx + side * 160 * s, cy - 4.5 * s, 4.5 * s, 1.2 * s, math.pi / 2 if side > 0 else math.pi / 2,
                         -side * 1.1, lead=(cx + side * 150 * s, cy)), 1.1 * s, 0.5 * s)
        dot = sd_circle(X, Y, cx + side * 15 * s, cy, 1.7 * s)
        iron.add(dot, tube_height(dot, 1.7 * s) + 0.5 * s)
    gem = sd_polygon(X, Y, [(cx, cy - 7 * s), (cx + 7 * s, cy), (cx, cy + 7 * s), (cx - 7 * s, cy)])
    iron.add(gem, bevel_height(gem, 3.2 * s, 3.2 * s))
    hgt = blur(iron.h, 0.4 * s)
    col = shade_iron(X, Y, iron.sdf, hgt, 540)
    return save(finish(iron.sdf, col, ink=(0.35 * s, 0.45 * s), heavy=0.4 * s, shadow=(int(1.0 * s), int(1.6 * s), 1.6 * s, 0.6),
                       ink_color=rgb("030304")), f"{OUT}/divider.png")


def bake_iron():
    return {"gauge_frame": bake_gauge(), "compass_body": bake_compass(),
            "compass_needle": Image.open(f"{OUT}/compass_needle.png"), "divider": bake_divider()}


def bake_stamina():
    """张力计下面的体力管：比张力管细的一根铁管，两端小矛尖；右边一根小铁梁，灵魂线从梁上垂下来（线由 Godot 画）。
    左边空着写"体力"。玻璃窗里是透明的，Godot 在下面画液柱。"""
    w, h = 420 * S, 36 * S
    X, Y = grid(w, h)
    s = S
    cy = 18
    iron = Iron(X, Y)
    outer = sd_rbox(X, Y, 196 * s, cy * s, 130 * s, 8 * s, 2.0 * s)
    window = sd_rbox(X, Y, 196 * s, cy * s, 122 * s, 4.2 * s, 1.2 * s)
    iron.plate(np.maximum(outer, -window), 2.6 * s, inner=window)
    # 两端：小矛尖 + 一道箍
    iron.spear([(68 * s, (cy - 7) * s), (62 * s, (cy - 6) * s), (52 * s, cy * s), (62 * s, (cy + 6) * s), (68 * s, (cy + 7) * s)],
               (54 * s, cy * s), (67 * s, cy * s), 2.6 * s)
    iron.spear([(324 * s, (cy - 7) * s), (330 * s, (cy - 6) * s), (340 * s, cy * s), (330 * s, (cy + 6) * s), (324 * s, (cy + 7) * s)],
               (325 * s, cy * s), (338 * s, cy * s), 2.6 * s)
    for x in (67, 325):
        collar = sd_rbox(X, Y, x * s, cy * s, 1.8 * s, 7.6 * s, 0.8 * s)
        iron.add(collar, bevel_height(collar, 1.2 * s, 3.0 * s))
    # 挂灵魂线的小铁梁：两端铆钉，右端往下卷一个小卷草
    beam = sd_rbox(X, Y, 381 * s, 6 * s, 27 * s, 2.3 * s, 1.0 * s)
    iron.add(beam, bevel_height(beam, 1.2 * s, 2.6 * s))
    for x in (357, 405):
        iron.rivet(x * s, 6 * s, 1.5 * s)
    iron.stroke(curl(412 * s, 11 * s, 4.2 * s, 1.1 * s, -1.6, 1.1, lead=(406 * s, 6 * s)), 1.6 * s, 0.6 * s)
    hgt = blur(iron.h, 0.5 * s)
    col = shade_iron(X, Y, iron.sdf, hgt, 560)
    layer = finish(iron.sdf, col, ink=(0.4 * s, 0.5 * s), heavy=0.5 * s, shadow=(int(1.0 * s), int(1.8 * s), 2.0 * s, 0.6),
                   ink_color=rgb("030304"))
    # 玻璃管的反光（同张力管）
    inside_w = coverage(window)
    top_hl = np.exp(-((Y - (cy - 2.6) * s) / (0.7 * s)) ** 2) * inside_w * np.clip((X - 80 * s) / (30 * s), 0, 1)
    layer.over(np.broadcast_to(rgb("e8f6f4"), (h, w, 3)), top_hl * 0.2)
    bottom_dark = np.clip((Y - (cy + 0.5) * s) / (4 * s), 0, 1) * inside_w
    layer.over(np.zeros((h, w, 3)), bottom_dark * 0.35)
    edge_shadow = np.clip(1 + window / (2.0 * s), 0, 1) * inside_w
    layer.over(np.zeros((h, w, 3)), edge_shadow * 0.45)
    return save(layer, f"{OUT}/stamina_frame.png")


def bake_fight():
    return {"stamina_frame": bake_stamina()}



# ======================================================================
# 场景道具：船头鲸油灯、灯架；船身轮廓的距离场
# ======================================================================

def bake_lantern():
    """铁皮鲸油灯：挂环、带烟囱的顶盖、三根护条的玻璃罩、底座；玻璃里亮着火。"""
    w, h = 40 * S, 80 * S
    X, Y = grid(w, h)
    s = S
    cx = w / 2
    iron = Iron(X, Y)
    iron.ring(cx, 5 * s, 4.0 * s, 2.3 * s)
    chimney = sd_rbox(X, Y, cx, 10.5 * s, 2.4 * s, 2.2 * s, 0.6 * s)
    iron.add(chimney, bevel_height(chimney, 1.0 * s, 2.0 * s))
    cap = sd_polygon(X, Y, [(cx - 4 * s, 12 * s), (cx + 4 * s, 12 * s), (cx + 10 * s, 18 * s), (cx - 10 * s, 18 * s)])
    iron.add(cap, bevel_height(cap, 2.0 * s, 3.2 * s))
    for y, hw in ((18.6 * s, 10.4 * s), (48.6 * s, 10.0 * s)):
        band = sd_rbox(X, Y, cx, y, hw, 1.3 * s, 0.6 * s)
        iron.add(band, bevel_height(band, 0.9 * s, 2.6 * s))
    for x, r in ((cx - 8.9 * s, 1.1 * s), (cx + 8.9 * s, 1.1 * s), (cx, 0.75 * s)):
        bar = sd_rbox(X, Y, x, 33.6 * s, r, 14.6 * s, r * 0.8)
        iron.add(bar, tube_height(bar, r) + 1.5 * s)
    guard = sd_rbox(X, Y, cx, 33.6 * s, 9.2 * s, 0.6 * s, 0.3 * s)
    iron.add(guard, tube_height(guard, 0.6 * s) + 1.2 * s)
    base = sd_polygon(X, Y, [(cx - 10 * s, 49.5 * s), (cx + 10 * s, 49.5 * s), (cx + 6.5 * s, 54.5 * s), (cx - 6.5 * s, 54.5 * s)])
    iron.add(base, bevel_height(base, 1.6 * s, 3.0 * s))
    knob = sd_circle(X, Y, cx, 56 * s, 2.0 * s)
    iron.add(knob, tube_height(knob, 2.0 * s))
    hgt = blur(iron.h, 0.4 * s)
    iron_col = shade_iron(X, Y, iron.sdf, hgt, 600, rust=1.3)
    # 玻璃罩：火焰周围最亮，往外变橙、顶上熏黑
    glass = sd_rbox(X, Y, cx, 33.6 * s, 8.4 * s, 14.2 * s, 2.6 * s)
    fx, fy = cx, 37.5 * s
    dist = np.hypot((X - fx) / (1.0 * s), (Y - fy) / (1.25 * s))
    glow = np.exp(-dist / 7.5)
    gcol = ramp(glow, [(0, rgb("7a2e0c")), (0.35, rgb("c86a22")), (0.7, rgb("f2b25a")), (1, rgb("fff0c8"))])
    soot = np.clip((24 * s - Y) / (6 * s), 0, 1)
    gcol = gcol * (1 - soot[..., None] * 0.55)
    # 火焰：上尖下圆的水滴
    flame = smin(sd_ellipse(X, Y, fx, fy + 1.2 * s, 2.0 * s, 2.6 * s),
                 sd_polygon(X, Y, [(fx - 1.6 * s, fy), (fx + 1.6 * s, fy), (fx + 0.2 * s, fy - 6.5 * s)]), 1.0 * s)
    core = sd_ellipse(X, Y, fx, fy + 1.4 * s, 0.9 * s, 1.5 * s)
    layer = Layer(w, h)
    layer.over(gcol, coverage(glass))
    layer.over(np.broadcast_to(rgb("ffd27a"), (h, w, 3)), coverage(flame))
    layer.over(np.broadcast_to(rgb("fffbe8"), (h, w, 3)), coverage(core))
    # 玻璃上的反光
    hl = sd_ellipse(X, Y, cx - 5.5 * s, 28 * s, 0.8 * s, 6 * s)
    layer.over(np.ones((h, w, 3)), coverage(hl) * 0.35)
    il = finish(iron.sdf, iron_col, ink=(0.35 * s, 0.5 * s), heavy=0.5 * s, shadow=None, ink_color=rgb("050404"))
    layer.over(il.rgb / np.maximum(il.a[..., None], 1e-6), il.a)
    gl_line = np.clip(np.minimum(glass + 0.3 * s, 0.4 * s - glass) + 0.5, 0, 1)
    layer.over(np.broadcast_to(rgb("2a1206"), (h, w, 3)), gl_line * 0.8)
    save(layer, f"{OUT}/lantern.png")

    # 灯架：套在船头立柱上的铁箍 + 向左伸出的铁臂，末端弯成钩
    bw, bh = 52 * S, 26 * S
    BX, BY = grid(bw, bh)
    arm = Iron(BX, BY)
    collar = sd_rbox(BX, BY, 44 * s, 8 * s, 6.5 * s, 4.2 * s, 1.0 * s)
    arm.add(collar, bevel_height(collar, 1.4 * s, 3.2 * s))
    for y in (5.2 * s, 10.8 * s):
        arm.rivet(40.5 * s, y, 0.9 * s)
        arm.rivet(47.5 * s, y, 0.9 * s)
    bar_pts = bezier((40 * s, 8 * s), (28 * s, 6.5 * s), (14 * s, 5.5 * s), (7 * s, 8 * s), 30)
    hook_pts = spiral(7.5 * s, 12.5 * s, 4.5 * s, 2.0 * s, -math.pi / 2 - 0.15, -0.72, 30)
    arm.stroke(bar_pts + hook_pts[1:], 1.9 * s, 1.0 * s)
    hgt = blur(arm.h, 0.4 * s)
    col = shade_iron(BX, BY, arm.sdf, hgt, 610, rust=1.3)
    save(finish(arm.sdf, col, ink=(0.35 * s, 0.5 * s), heavy=0.5 * s, shadow=None, ink_color=rgb("050404")),
         f"{OUT}/lantern_bracket.png")
    return {"lantern": layer.image(), "lantern_bracket": Image.open(f"{OUT}/lantern_bracket.png")}


# ======================================================================
# 预览
# ======================================================================

def preview(images, path, bg=(14, 30, 36), scale=1.0 / S, zoom_name=None):
    """把烘焙结果按显示尺寸排在深青色背景上，另附一张放大图看细节。"""
    items = [(k, v.resize((max(1, int(v.width * scale)), max(1, int(v.height * scale))), Image.LANCZOS))
             for k, v in images.items()]
    width = max(600, sum(im.width + 16 for _, im in items) + 16)
    rows = []
    row, x = [], 16
    for k, im in items:
        if x + im.width > 1200 and row:
            rows.append(row)
            row, x = [], 16
        row.append((k, im))
        x += im.width + 16
    rows.append(row)
    height = sum(max(im.height for _, im in r) + 16 for r in rows) + 16
    sheet = Image.new("RGBA", (min(width, 1232), height), bg + (255,))
    y = 16
    for r in rows:
        x = 16
        for _, im in r:
            sheet.alpha_composite(im, (x, y))
            x += im.width + 16
        y += max(im.height for _, im in r) + 16
    sheet.save(path)
    if zoom_name and zoom_name in images:
        big = images[zoom_name]
        bgimg = Image.new("RGBA", big.size, bg + (255,))
        bgimg.alpha_composite(big)
        bgimg.save(path.replace(".png", f"_{zoom_name}.png"))


# ======================================================================
# 灵魂等级图标、三类材料图标
# ======================================================================

SOUL = [(0.0, rgb("0b2230")), (0.3, rgb("1d5a6e")), (0.6, rgb("3fb3c6")), (0.85, rgb("9be8f0")), (1.0, rgb("e8fdff"))]


def bake_icon_soul(seed=430):
    """灵魂等级：一团幽蓝的灵魂火，火舌往上卷。"""
    w, h = 48 * S, 52 * S
    X, Y = grid(w, h)
    s = S
    cx = w / 2
    # 越往上火舌摆得越厉害
    sway = np.clip((44 * s - Y) / (36 * s), 0, 1)
    Xw = X + (fbm(X * 0.03, Y * 0.03, 3, seed) - 0.5) * 6 * s * sway
    body = sd_circle(Xw, Y, cx, 36 * s, 11 * s)
    tip = sd_polygon(Xw, Y, [(cx - 10.5 * s, 34 * s), (cx + 1.5 * s, 3 * s), (cx + 10.5 * s, 34 * s)])
    flame = smin(body, tip, 6 * s)
    left = sd_polygon(Xw, Y, [(cx - 11.5 * s, 39 * s), (cx - 14 * s, 17 * s), (cx - 3 * s, 33 * s)])
    right = sd_polygon(Xw, Y, [(cx + 4 * s, 31 * s), (cx + 13 * s, 13 * s), (cx + 11.5 * s, 37 * s)])
    flame = smin(flame, smin(left, right, 1 * s), 3 * s)
    core = smin(sd_circle(Xw, Y, cx, 38 * s, 5.5 * s),
                sd_polygon(Xw, Y, [(cx - 5 * s, 37 * s), (cx + 0.5 * s, 19 * s), (cx + 5 * s, 37 * s)]), 3 * s)
    inside = np.clip(-flame / (7 * s), 0, 1)
    flicker = fbm(X * 0.08, Y * 0.045, 3, seed + 3)
    t = 0.22 + inside * 0.42 + np.clip(-core / (3 * s), 0, 1) * 0.38 + (flicker - 0.5) * 0.18
    col = ramp(soft_bands(np.clip(t, 0, 1), 6, 0.5), SOUL)
    layer = Layer(w, h)
    layer.over(np.broadcast_to(rgb("3fb3c6"), (h, w, 3)), blur(coverage(flame), 4 * s) * 0.6)
    fl = finish(flame, col, ink=(0.35 * s, 0.45 * s), heavy=0.4 * s, shadow=None, ink_color=rgb("06141b"))
    layer.over(fl.rgb / np.maximum(fl.a[..., None], 1e-6), fl.a)
    return save(layer, f"{OUT}/icon_soul.png")


FLESH = [(0.0, rgb("1c0504")), (0.3, rgb("4f0f0b")), (0.55, rgb("8a1f17")), (0.8, rgb("b84236")), (1.0, rgb("e0806e"))]
SHELL = [(0.0, rgb("1d1710")), (0.3, rgb("4a3d2b")), (0.55, rgb("8a7756")), (0.8, rgb("bfae88")), (1.0, rgb("e4dcc2"))]
GLOW = [(0.0, rgb("06221f")), (0.35, rgb("0f5a4e")), (0.65, rgb("2fb59a")), (0.85, rgb("8ff0d6")), (1.0, rgb("eafff8"))]


def bake_mat_flesh(seed=440):
    """血肉质：一块生肉，夹着白色的筋膜，湿漉漉的反光。"""
    w = h = 40 * S
    X, Y = grid(w, h)
    s = S
    c = w / 2
    blob = smin(sd_ellipse(X, Y, c - 1 * s, c + 2 * s, 14 * s, 10.5 * s, -0.35),
                sd_ellipse(X, Y, c + 6 * s, c - 4 * s, 8 * s, 6.5 * s, 0.4), 4 * s)
    blob = blob + (fbm(X * 0.06, Y * 0.06, 3, seed) - 0.5) * 3 * s
    hgt = tube_height(blob, 9 * s) + (fbm(X * 0.05, Y * 0.05, 4, seed + 1) - 0.5) * 2 * s
    col = shade_material(X, Y, blob, hgt, FLESH, seed, grain_angle=0.6, grain=0.25, spec=0.55, spec_power=22, blotch=0.15)
    marb = ridged(X * 0.035, Y * 0.035, 3, seed + 2)
    fat = np.clip((marb - 0.86) * 9, 0, 1) * (blob < -1.5 * s)
    col = col * (1 - fat[..., None] * 0.75) + rgb("e8d2c4") * (fat[..., None] * 0.75)
    return save(ink_finish(blob, col), f"{OUT}/mat_flesh.png")


def bake_mat_shell(seed=450):
    """矿壳质：一片扇形的贝壳碎片，放射状的棱、一圈圈生长纹，边上结着灰绿的矿壳。"""
    w = h = 40 * S
    X, Y = grid(w, h)
    s = S
    hx, hy = w / 2, h - 9 * s
    a0 = -math.pi / 2 + 0.12
    pts = [(hx, hy)]
    for k in range(15):
        a = a0 - 0.9 + 1.8 * k / 14
        rr = 19 * s * (1 + 0.05 * math.sin(k * 2.7))
        pts.append((hx + math.cos(a) * rr, hy + math.sin(a) * rr))
    fan = sd_polygon(X, Y, pts)
    bite = sd_circle(X, Y, hx + 14 * s, hy - 15 * s, 5 * s) + (fbm(X * 0.1, Y * 0.1, 2, seed) - 0.5) * 2.5 * s
    fan = smax(fan, -bite, 1 * s)
    fan = fan + (fbm(X * 0.09, Y * 0.09, 2, seed + 1) - 0.5) * 1.0 * s
    dx, dy = X - hx, Y - hy
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    ribs = np.cos((ang - a0) * 15) * 0.5 + 0.5
    hgt = bevel_height(fan, 3 * s, 3 * s) + ribs * 1.3 * s * np.clip(-fan / (3 * s), 0, 1)
    col = shade_material(X, Y, fan, hgt, SHELL, seed, grain=0.08, spec=0.2, spec_power=20, blotch=0.2)
    growth = np.clip(np.cos(r / s * 1.25) * 0.5 + 0.5, 0, 1) ** 8 * 0.18
    col = col * (1 - growth[..., None])
    f1, _ = worley(X * 0.25, Y * 0.25, seed + 3)
    crust = np.clip(1 - f1 / 0.35, 0, 1) * (fbm(X * 0.05, Y * 0.05, 2, seed + 4) > 0.56) * (fan < 0)
    col = col * (1 - crust[..., None] * 0.6) + rgb("5d6656") * (crust[..., None] * 0.6)
    return save(ink_finish(fan, col), f"{OUT}/mat_shell.png")


def bake_mat_glow(seed=460):
    """幽光质：一枚半透明的腺体，膜上爬着暗红的血管，里面亮着青绿的光。"""
    w = h = 40 * S
    X, Y = grid(w, h)
    s = S
    c = w / 2
    sac = sd_ellipse(X, Y, c - 1 * s, c + 2 * s, 11 * s, 13 * s, 0.25) + (fbm(X * 0.05, Y * 0.05, 2, seed) - 0.5) * 1.5 * s
    duct = sd_capsule(X, Y, (c + 3 * s, c - 9 * s), (c + 8 * s, c - 16 * s), 2.4 * s, 1.7 * s)[0]
    shape = smin(sac, duct, 2 * s)
    inside = np.clip(-sac / (11 * s), 0, 1)
    core = np.exp(-(((X - c + 0.5 * s) / (6 * s)) ** 2 + ((Y - c - 3 * s) / (7 * s)) ** 2))
    t = 0.18 + inside * 0.25 + core * 0.62 + (fbm(X * 0.07, Y * 0.07, 3, seed + 1) - 0.5) * 0.12
    col = ramp(t, GLOW)
    veins = ridged(X * 0.045, Y * 0.045, 3, seed + 2)
    vein = np.clip((veins - 0.9) * 12, 0, 1) * (sac < -1 * s)
    col = col * (1 - vein[..., None] * 0.55) + rgb("5e1a20") * (vein[..., None] * 0.55)
    duct_col = shade_material(X, Y, duct, tube_height(duct, 2.4 * s), FLESH, seed + 5, grain=0.2, spec=0.3)
    col = np.where((sac < 0)[..., None], col, duct_col * 0.85 + rgb("4a3a40") * 0.15)
    layer = Layer(w, h)
    layer.over(np.broadcast_to(rgb("4fe0bf"), (h, w, 3)), blur(coverage(sac), 4 * s) * 0.5)
    fl = finish(shape, col, shadow=None)
    layer.over(fl.rgb / np.maximum(fl.a[..., None], 1e-6), fl.a)
    hl = sd_ellipse(X, Y, c - 5 * s, c - 4 * s, 2.0 * s, 3.4 * s, 0.5)
    layer.over(np.ones((h, w, 3)), coverage(hl) * 0.5)
    return save(layer, f"{OUT}/mat_glow.png")


def bake_ledger():
    # 三类材料图标（mat_flesh / mat_shell / mat_glow）已换成 GPT 画的（材料与添加剂图标_v0.6），这里不再烘焙，免得覆盖；
    # bake_mat_* 留着备用
    return {"icon_soul": bake_icon_soul()}


GROUPS = {
    "bones": bake_bones,
    "parchment": bake_parchments,
    "flasks": bake_flasks,
    "seals": bake_seals,
    "icons": bake_icons,
    "iron": bake_iron,
    "fight": bake_fight,
    "lantern": bake_lantern,
    "ledger": bake_ledger,
}


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    preview_dir = None
    if "--preview" in argv:
        i = argv.index("--preview")
        preview_dir = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    names = argv or list(GROUPS)
    for name in names:
        images = GROUPS[name]()
        print(f"{name}: " + ", ".join(f"{k} {v.size}" for k, v in images.items()))
        if preview_dir:
            preview(images, os.path.join(preview_dir, f"preview_{name}.png"), zoom_name=next(iter(images)))


if __name__ == "__main__":
    main(sys.argv[1:])
