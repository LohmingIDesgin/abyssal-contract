"""烘焙第一人称手臂的手绘风格贴图（UV 空间）。

用法：python tools/bake_arm_texture.py [输出路径] [分辨率]
默认输出 assets/textures/arm_albedo.png，2048×2048。

逐像素读取该点在静止姿态下的 3D 位置、法线、骨骼权重，然后绘制：
  - 前臂和手背：沿前臂轴螺旋缠绕的绷带，后一圈压住前一圈，接缝处有压痕阴影，
    撕裂毛边、线头、纤维纹理、污渍，偶尔有破口露出皮肤；绷带缠到指根，收口是毛边
  - 手指：裸露皮肤（斑驳色差）、关节褶皱线、指甲（对准模型上的指甲环）
两只手共用同一套 UV，所以一张贴图左右手通用。
生成的 PNG 可以直接在绘图软件里继续手绘修改。
"""
import json
import struct
import sys

import numpy as np
from PIL import Image, ImageFilter

GLB = "钓鱼动画.glb"
OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/textures/arm_albedo.png"
SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 2048

# —— 颜色（取自 docs/reference/style_hands_flat.png）——
BANDAGE = np.array([0x9a, 0x99, 0x96]) / 255.0
BANDAGE_DARK = np.array([0x74, 0x75, 0x78]) / 255.0  # 压痕阴影
SKIN = np.array([0x88, 0x7c, 0x77]) / 255.0
SKIN_DARK = np.array([0x6c, 0x5f, 0x5e]) / 255.0
NAIL = np.array([0xa6, 0x9c, 0x97]) / 255.0
INK = np.array([0x14, 0x12, 0x12]) / 255.0
DIRT = np.array([0x6a, 0x5e, 0x52]) / 255.0

# —— 绷带参数 ——
STRIP_WIDTH = 0.05       # 一条绷带的宽度（模型单位，前臂约 0.47）
TURN_SHIFT = 3           # 每绕一圈前进几条带宽：越大缠得越斜（几条绷带交错缠绕）
EDGE_INK = 0.055         # 绷带边墨线宽度（占一圈的比例）
OVERLAP_SHADOW = 0.16    # 压痕阴影宽度
TEAR = 0.11              # 撕边毛糙程度
GAP_CHANCE = 0.28        # 某一圈出现破口露皮肤的概率

FINGER_CHAINS = {        # 手指骨骼链（第一根是掌骨，缠绷带）
    "thumb": [2, 3, 4],
    "index": [5, 6, 7, 8, 9],
    "middle": [10, 11, 12, 13, 14],
    "ring": [15, 16, 17, 18, 19],
    "pinky": [20, 21, 22, 23, 24],
}
METACARPALS = [2, 5, 10, 15, 20]
CREASE_JOINTS = [3, 4, 6, 7, 8, 11, 12, 13, 16, 17, 18, 21, 22, 23]


# ---------- 读取 glb ----------

def load_glb(path):
    data = open(path, "rb").read()
    clen, _ = struct.unpack("<II", data[12:20])
    gltf = json.loads(data[20:20 + clen])
    bin_off = 20 + clen + 8
    ctypes = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

    def read(index):
        a = gltf["accessors"][index]
        v = gltf["bufferViews"][a["bufferView"]]
        dt, n = ctypes[a["componentType"]], ncomp[a["type"]]
        off = bin_off + v.get("byteOffset", 0) + a.get("byteOffset", 0)
        item = np.dtype(dt).itemsize * n
        stride = v.get("byteStride", 0) or item
        raw = np.frombuffer(data, np.uint8, stride * a["count"], off).reshape(a["count"], stride)[:, :item]
        return np.frombuffer(raw.tobytes(), dt).reshape(a["count"], n).astype(np.float64)

    return gltf, read


gltf, read = load_glb(GLB)
# 右手：网格 0 + 蒙皮 0
prim = gltf["meshes"][0]["primitives"][0]
pos = read(prim["attributes"]["POSITION"])
nrm = read(prim["attributes"]["NORMAL"])
uv = read(prim["attributes"]["TEXCOORD_0"])
joints = read(prim["attributes"]["JOINTS_0"]).astype(int)
weights = read(prim["attributes"]["WEIGHTS_0"])
tris = read(prim["indices"]).astype(int).reshape(-1, 3)
ibm = read(gltf["skins"][0]["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
bind = np.linalg.inv(ibm)                     # 骨骼在静止姿态下的变换
heads = bind[:, :3, 3]
bone_y = bind[:, :3, 1] / np.linalg.norm(bind[:, :3, 1], axis=1, keepdims=True)

# 每个顶点的"手指程度"（手指骨骼权重之和）
finger_bones = [b for chain in FINGER_CHAINS.values() for b in chain if b not in METACARPALS]
finger_w = np.zeros(len(pos))
for k in range(4):
    finger_w += np.where(np.isin(joints[:, k], finger_bones), weights[:, k], 0.0)


# ---------- 噪声 ----------

def hash3(p):
    return np.modf(np.sin(p[..., 0] * 127.1 + p[..., 1] * 311.7 + p[..., 2] * 74.7) * 43758.5453)[0] % 1.0


def value_noise(p):
    i = np.floor(p)
    f = p - i
    f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * hash3(i + np.array([dx, dy, dz]))
    return out


def fbm(p, octaves=3):
    total, amp = 0.0, 0.5
    for _ in range(octaves):
        total = total + amp * value_noise(p)
        p = p * 2.03
        amp *= 0.5
    return total


def hash1(x):
    return np.modf(np.sin(x * 12.9898 + 78.233) * 43758.5453)[0] % 1.0


# ---------- 光栅化：逐像素插值位置/法线/手指程度 ----------

CACHE = f"tools/.bake_cache_{SIZE}.npz"  # 光栅化结果缓存，只改绘制参数时不用重算
try:
    cached = np.load(CACHE)
    P, N, F, filled = cached["P"], cached["N"], cached["F"], cached["filled"]
    tris_to_raster = []
except FileNotFoundError:
    P = np.zeros((SIZE, SIZE, 3))
    N = np.zeros((SIZE, SIZE, 3))
    F = np.zeros((SIZE, SIZE))
    filled = np.zeros((SIZE, SIZE), bool)
    tris_to_raster = tris
uv_px = uv * SIZE
for t in tris_to_raster:
    a, b, c = uv_px[t]
    x0, y0 = np.floor(np.minimum(np.minimum(a, b), c)).astype(int)
    x1, y1 = np.ceil(np.maximum(np.maximum(a, b), c)).astype(int)
    x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, SIZE - 1), min(y1, SIZE - 1)
    if x1 < x0 or y1 < y0:
        continue
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(det) < 1e-12:
        continue
    l0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / det
    l1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / det
    l2 = 1 - l0 - l1
    inside = (l0 >= -0.01) & (l1 >= -0.01) & (l2 >= -0.01)
    if not inside.any():
        continue
    yy, xx = (ys[inside] - 0.5).astype(int), (xs[inside] - 0.5).astype(int)
    w = np.stack([l0[inside], l1[inside], l2[inside]], -1)
    P[yy, xx] = w @ pos[t]
    N[yy, xx] = w @ nrm[t]
    F[yy, xx] = w @ finger_w[t]
    filled[yy, xx] = True

if len(tris_to_raster):
    np.savez_compressed(CACHE, P=P, N=N, F=F, filled=filled)
N /= np.maximum(np.linalg.norm(N, axis=-1, keepdims=True), 1e-9)
m = filled
p = P[m]
n = N[m]
fing = F[m]
count = p.shape[0]
print("texels", count)

# ---------- 圆柱坐标：前臂一根轴，手掌另一根轴 ----------
# 手腕是弯的，前臂轴线延长出去会从手背穿出，手背上的条纹会散成放射状，所以手掌单独用"手腕 → 指根中心"的轴


def cylinder(o, d, pts):
    d = d / np.linalg.norm(d)
    r1 = np.cross(d, [0.0, 1.0, 0.0])
    r1 /= np.linalg.norm(r1)
    r2 = np.cross(d, r1)
    rel_ = pts - o
    al = rel_ @ d
    rad = rel_ - np.outer(al, d)
    th = np.arctan2(rad @ r2, rad @ r1)
    return al, th, np.linalg.norm(rad, axis=1), d


origin = heads[1]
wrist = heads[10]
knuckle_mid = (heads[6] + heads[11] + heads[16] + heads[21]) / 4
along_f, theta_f, rad_f, axis = cylinder(origin, wrist - origin, p)
along_h, theta_h, rad_h, hand_axis = cylinder(wrist, knuckle_mid - wrist, p)
wrist_along = (wrist - origin) @ axis
on_hand = along_f > wrist_along
along = np.where(on_hand, wrist_along + along_h, along_f)   # 手掌接着前臂往下数，条纹基本连续
theta = np.where(on_hand, theta_h, theta_f)
radius = np.where(on_hand, rad_h, rad_f)
turn = (theta + np.pi) / (2 * np.pi)                        # 0..1
arc = theta * radius                                        # 沿周长的弧长，噪声用它采样

# ---------- 绷带 ----------

phase = along / STRIP_WIDTH + turn * TURN_SHIFT
tear = (fbm(np.stack([phase * 0.5, arc * 90.0, np.zeros(count)], -1)) - 0.5) * 2 * TEAR
phase_t = phase + tear
strip = np.floor(phase_t)
s = phase_t - strip                                        # 0 = 本圈上沿（压在上一圈上），1 = 下沿

# 绷带缠到指根：沿轴超过指根（各掌骨远端）就是裸露皮肤，收口是毛边
knuckles = np.array([heads[6], heads[11], heads[16], heads[21]])
end_along = wrist_along + ((knuckles - wrist) @ hand_axis).min() - 0.012
end_ragged = end_along + (fbm(np.stack([arc * 110.0, np.full(count, 3.3), np.zeros(count)], -1)) - 0.5) * 0.03
wrapped = (fing < 0.5) & (along < end_ragged)

# 破口：部分圈上有不规则的撕裂破洞，露出下面的皮肤（噪声场超过阈值的地方，边缘天然参差）
hole_field = fbm(np.stack([phase * 1.3, arc * 45.0, strip * 0.37], -1), octaves=4)
hole_field = hole_field + np.minimum(s - 0.18, 0.9 - s) * 0.6     # 越靠近绷带边缘越不容易破
holey = hash1(strip * 9.3) < GAP_CHANCE
HOLE_T = 0.66
in_gap = holey & (hole_field > HOLE_T)
gap_border = holey & (hole_field > HOLE_T - 0.025) & ~in_gap
bandaged = wrapped & ~in_gap

# 每条绷带的明暗略有差别 + 沿缠绕方向的纤维纹理
tone = 1.0 + (hash1(strip * 5.7) - 0.5) * 0.08
fiber = fbm(np.stack([phase * 3.0, arc * 900.0, along * 4.0], -1))
tone = tone * (1.0 + (fiber - 0.5) * 0.12)
color = np.tile(BANDAGE, (count, 1)) * tone[:, None]
# 压痕阴影：下一圈压上来的地方（本圈下沿）
shadow = np.clip((s - (1.0 - OVERLAP_SHADOW)) / OVERLAP_SHADOW, 0, 1)
color = color * (1 - shadow[:, None] * 0.7) + BANDAGE_DARK * shadow[:, None] * 0.7
# 污渍
dirt = np.clip((fbm(p * 18.0) - 0.58) * 4.0, 0, 1) * 0.45
color = color * (1 - dirt[:, None]) + DIRT * dirt[:, None]

# ---------- 皮肤 ----------

mottle = fbm(p * 60.0)
skin = SKIN * (1.0 + (mottle - 0.5) * 0.14)[:, None]
skin_shadow = np.clip(fbm(p * 14.0 + 7.0) - 0.45, 0, 1)[:, None] * 0.8
skin = skin * (1 - skin_shadow) + SKIN_DARK * skin_shadow
# 破口里的皮肤更暗（在绷带下面）
gap_skin = skin * 0.82
result = np.where(bandaged[:, None], color, np.where((wrapped & in_gap)[:, None], gap_skin, skin))

# ---------- 墨线 ----------

ink = np.zeros(count)
# 绷带上沿墨线，宽度带抖动；线头：上沿附近零星的短竖线
edge_w = EDGE_INK * (0.6 + 0.8 * fbm(np.stack([arc * 190.0, strip, np.full(count, 5.0)], -1)))
ink = np.maximum(ink, ((s < edge_w) & bandaged).astype(float))
fray = (((arc * 560.0 + hash1(strip) * 10) % 1.0) < 0.06) & (s > edge_w) & (s < edge_w + 0.12) & (hash1(np.floor(arc * 560.0) + strip * 13) < 0.35)
ink = np.maximum(ink, (fray & bandaged).astype(float))
# 绷带褶皱：本圈中间偶尔一道细线
fold = (np.abs(s - (0.45 + hash1(strip * 2.3) * 0.2)) < 0.012) & (fbm(np.stack([arc * 38.0, strip, np.full(count, 9.0)], -1)) > 0.55)
ink = np.maximum(ink, (fold & bandaged).astype(float) * 0.85)
# 破口边缘、收口边缘
ink = np.maximum(ink, (gap_border & wrapped).astype(float))
end_line = (fing < 0.5) & (np.abs(along - end_ragged) < 0.004)
ink = np.maximum(ink, end_line.astype(float))

# 手指关节褶皱：关节平面附近的断续短线（两道）
for j in CREASE_JOINTS:
    d = (p - heads[j]) @ bone_y[j]
    near = np.linalg.norm((p - heads[j]) - np.outer(d, bone_y[j]), axis=1) < 0.03
    broken = fbm(p * 140.0 + j) > 0.42
    for off in (-0.0035, 0.0035):
        ink = np.maximum(ink, ((np.abs(d - off) < 0.0012) & near & broken & (fing > 0.5)).astype(float) * 0.9)

# ---------- 指甲：对准模型上的指甲环（UV 里最密的那一小圈顶点）----------

e1 = uv[tris[:, 1]] - uv[tris[:, 0]]
e2 = uv[tris[:, 2]] - uv[tris[:, 0]]
tri_area = np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]) * 0.5
vert_area = np.zeros(len(pos))
vert_cnt = np.zeros(len(pos))
for k in range(3):
    np.add.at(vert_area, tris[:, k], tri_area)
    np.add.at(vert_cnt, tris[:, k], 1)
vert_area /= np.maximum(vert_cnt, 1)
dominant = joints[np.arange(len(pos)), np.argmax(weights, axis=1)]
nails = []
for name, chain in FINGER_CHAINS.items():
    tip_bones = chain[-2:]
    cand = np.where(np.isin(dominant, tip_bones))[0]
    if len(cand) < 20:
        continue
    dense = cand[np.argsort(vert_area[cand])[:40]]
    center_uv = uv[dense].mean(0)
    radius_uv = np.percentile(np.linalg.norm(uv[dense] - center_uv, axis=1), 90) * 1.15
    nails.append((center_uv, radius_uv))
    print(f"nail {name}: uv {center_uv.round(3)} r {radius_uv:.4f}")

texel_uv = (np.argwhere(m)[:, ::-1] + 0.5) / SIZE
for center_uv, radius_uv in nails:
    r = np.linalg.norm(texel_uv - center_uv, axis=1) / radius_uv
    inside = r < 1.0
    result[inside] = NAIL * (1.0 + (mottle[inside, None] - 0.5) * 0.1)
    # 甲面一道细弧形高光、甲缘墨线
    rel_uv = (texel_uv - center_uv) / radius_uv
    lean = (rel_uv @ np.array([-0.7, -0.7])) / np.maximum(r, 1e-6)
    result[inside & (r > 0.5) & (r < 0.66) & (lean > 0.55)] *= 1.15
    ink = np.maximum(ink, ((r > 0.88) & (r < 1.03)).astype(float))

result = result * (1 - ink[:, None]) + INK * ink[:, None]

# ---------- 写出，并向外扩边避免 UV 接缝出现黑线 ----------

img = np.zeros((SIZE, SIZE, 3))
img[m] = np.clip(result, 0, 1)
out = Image.fromarray((img * 255).astype(np.uint8), "RGB")
mask = Image.fromarray((m * 255).astype(np.uint8), "L")
for _ in range(12):
    grown = out.filter(ImageFilter.MaxFilter(3))
    grown_mask = mask.filter(ImageFilter.MaxFilter(3))
    newly = np.array(grown_mask) > np.array(mask)
    arr = np.array(out)
    arr[newly] = np.array(grown)[newly]
    out = Image.fromarray(arr)
    mask = grown_mask
out.save(OUT)
print("saved", OUT)
