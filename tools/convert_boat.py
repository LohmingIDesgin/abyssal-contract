"""把 3D 木船的原件转成游戏里用的网格和贴图。

用法：python tools/convert_boat.py
读 art_src/木船2.glb（原件：两块网格、两张 512 的颜色贴图，没有法线和粗糙度），写出：
  assets/models/木船2.glb                    只有网格：两块（装饰件、船板），单位米（原件是厘米，套着 0.01 的缩放），
                                             去掉原件摆在场景里的位移；位置、法线、UV、索引，各带一个材质名
  assets/textures/boat3d_{trim,planks}_albedo.png      颜色，原样拷出来
  assets/textures/boat3d_{trim,planks}_normal.png      法线（OpenGL 约定，绿色朝上），1024
  assets/textures/boat3d_{trim,planks}_roughness.png   粗糙度（灰度，白 = 粗糙），1024
trim 是装饰件那张图集（横梁、铁件），planks 是船板那张（横着的木板，会在 UV 里平铺）。

法线和粗糙度是照着颜色"画"出来的：
  - 法线：把颜色的亮度当高度，板缝、木纹里深色的地方凹下去。先去掉大块的深浅（一整块木板偏暗不该变成一个大斜坡），
    再分两层叠：细木纹（一两个像素的明暗）、板缝和裂缝（比周围暗一截的细线）。铁件（偏灰、偏蓝、不饱和的地方）压平一些。
    贴图在 UV 里平铺，所以求导、模糊都按首尾相接算，接缝处不会断。
  - 粗糙度：木头整体很粗糙（0.8 上下），板缝和脏的地方更粗糙，磨得发亮的浅色木面稍微光一点；铁件光滑一些（0.4~0.55）。
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

SRC = "art_src/木船2.glb"
MODEL_OUT = "assets/models/木船2.glb"
TEX_DIR = "assets/textures"
DEBUG = sys.argv[1] if len(sys.argv) > 1 else ""  # 给一个文件夹就把中间结果（铁件遮罩、高度）也存进去
MAP_SIZE = 1024
PARTS = {0: ("trim", "木船2_装饰"), 1: ("planks", "木船2_船板")}  # 原件的第几块网格 → 贴图名、材质名

# —— 法线 ——
GRAIN_STRENGTH = 5.0     # 细木纹
SEAM_STRENGTH = 3.0      # 板缝、裂缝
METAL_FLATTEN = 0.35     # 铁件的起伏乘这个
# —— 粗糙度 ——
WOOD_ROUGH = 0.82
SEAM_ROUGH = 0.12        # 板缝、脏的地方再粗糙多少
WORN_SMOOTH = 0.12       # 磨亮的浅色木面光滑多少
METAL_ROUGH = (0.4, 0.58)  # 铁件：亮处 → 暗处


def load_glb(path):
    data = open(path, "rb").read()
    clen, _ = struct.unpack("<II", data[12:20])
    gltf = json.loads(data[20:20 + clen])
    bin_off = 20 + clen + 8
    return data, gltf, bin_off


def view_bytes(data, gltf, bin_off, view):
    v = gltf["bufferViews"][view]
    off = bin_off + v.get("byteOffset", 0)
    return data[off: off + v["byteLength"]]


def read(data, gltf, bin_off, index):
    a = gltf["accessors"][index]
    v = gltf["bufferViews"][a["bufferView"]]
    dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    off = bin_off + v.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = v.get("byteStride", 0) or np.dtype(dt).itemsize * n
    raw = np.frombuffer(data, np.uint8, stride * a["count"], off).reshape(a["count"], stride)[:, :np.dtype(dt).itemsize * n]
    return np.frombuffer(raw.tobytes(), dt).reshape(a["count"], n)


# ---------- 网格 ----------

def write_mesh(data, gltf, bin_off):
    node = gltf["nodes"][gltf["scenes"][0]["nodes"][0]]
    scale = np.array(node.get("scale", [1.0, 1.0, 1.0]), np.float32)
    prims = gltf["meshes"][node["mesh"]]["primitives"]
    out_bin = bytearray()
    views, accessors, primitives, materials = [], [], [], []

    def add(array, target, kind, with_bounds=False):
        while len(out_bin) % 4:
            out_bin.append(0)
        raw = np.ascontiguousarray(array).tobytes()
        views.append({"buffer": 0, "byteOffset": len(out_bin), "byteLength": len(raw), "target": target})
        out_bin.extend(raw)
        comp = {np.dtype(np.float32): 5126, np.dtype(np.uint32): 5125}[array.dtype]
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": int(array.shape[0]), "type": kind}
        if with_bounds:
            acc["min"] = array.min(0).tolist()
            acc["max"] = array.max(0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    for i, p in enumerate(prims):
        pos = read(data, gltf, bin_off, p["attributes"]["POSITION"]).astype(np.float32) * scale
        nrm = read(data, gltf, bin_off, p["attributes"]["NORMAL"]).astype(np.float32) * np.sign(scale)
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
        uv = read(data, gltf, bin_off, p["attributes"]["TEXCOORD_0"]).astype(np.float32)
        idx = read(data, gltf, bin_off, p["indices"]).astype(np.uint32).reshape(-1)
        attrs = {"POSITION": add(pos, 34962, "VEC3", True), "NORMAL": add(nrm, 34962, "VEC3"),
                 "TEXCOORD_0": add(uv, 34962, "VEC2")}
        primitives.append({"attributes": attrs, "indices": add(idx, 34963, "SCALAR"), "material": i, "mode": 4})
        materials.append({"name": PARTS[i][1], "doubleSided": True,
                          "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 1.0}})
    while len(out_bin) % 4:
        out_bin.append(0)
    out = {
        "asset": {"version": "2.0", "generator": "abyssal tools/convert_boat.py, from " + SRC},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [0]}],
        "nodes": [{"name": "木船2", "mesh": 0}],
        "meshes": [{"name": "木船2", "primitives": primitives}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(out_bin)}],
    }
    js = json.dumps(out, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    glb = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(out_bin))
    glb += struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(out_bin), b"BIN\x00") + bytes(out_bin)
    os.makedirs(os.path.dirname(MODEL_OUT), exist_ok=True)
    open(MODEL_OUT, "wb").write(glb)
    print("mesh", MODEL_OUT, len(glb), "bytes")


# ---------- 法线、粗糙度 ----------

def box_blur(a, r):
    """方框模糊，首尾相接（贴图平铺）"""
    for axis in (0, 1):
        pad = [(0, 0)] * a.ndim
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad, mode="wrap"), axis=axis, dtype=np.float64)
        hi = np.take(c, np.arange(2 * r + 1, c.shape[axis]), axis=axis)
        lo = np.take(c, np.arange(0, c.shape[axis] - 2 * r - 1), axis=axis)
        a = ((hi - lo) / (2 * r + 1)).astype(np.float32)
    return a


def blur(a, r):
    for _ in range(3):  # 三次方框 ≈ 高斯
        a = box_blur(a, r)
    return a


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def save_debug(name, img):
    if DEBUG:
        os.makedirs(DEBUG, exist_ok=True)
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(os.path.join(DEBUG, name + ".png"))


def make_maps(albedo_img, name):
    k = MAP_SIZE / 1024
    rgb = np.asarray(albedo_img.convert("RGB").resize((MAP_SIZE, MAP_SIZE), Image.BICUBIC), np.float32) / 255
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    # 铁件：不饱和、偏蓝灰
    hi, lo = rgb.max(-1), rgb.min(-1)
    saturation = (hi - lo) / np.maximum(hi, 1e-4)
    metal = smoothstep(0.2, 0.09, saturation) * smoothstep(-0.03, 0.02, rgb[..., 2] - rgb[..., 0])
    metal = blur(metal, int(2 * k))
    # 高度：细木纹（一两个像素的明暗）+ 板缝（比周围暗一截的细线，凹下去）
    grain = lum - blur(lum, int(2 * k))
    seam = np.clip((blur(lum, int(6 * k)) - lum) * 4.0, 0.0, 1.0)
    height = GRAIN_STRENGTH * grain - SEAM_STRENGTH * blur(seam, 1) * 0.25
    height *= 1.0 - (1.0 - METAL_FLATTEN) * metal
    save_debug(name + "_metal", metal)
    save_debug(name + "_height", height * 2 + 0.5)
    # 图像坐标（x 右、y 下）的导数；首尾相接
    gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5 * MAP_SIZE / 256
    gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5 * MAP_SIZE / 256
    # OpenGL 约定：切线空间 +Y 是图像里的"上"，所以 y 分量是 +∂h/∂y（图像 y 朝下）
    n = np.stack([-gx, gy, np.ones_like(gx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(f"{TEX_DIR}/boat3d_{name}_normal.png", optimize=True)
    # 粗糙度
    worn = smoothstep(0.55, 0.85, lum)
    wood = WOOD_ROUGH + SEAM_ROUGH * seam - WORN_SMOOTH * worn + (blur(np.random.default_rng(7).random(lum.shape).astype(np.float32), int(3 * k)) - 0.5) * 0.1
    iron = METAL_ROUGH[0] + (METAL_ROUGH[1] - METAL_ROUGH[0]) * (1.0 - lum)
    rough = np.clip(wood + (iron - wood) * metal, 0.0, 1.0)
    Image.fromarray((rough * 255 + 0.5).astype(np.uint8), mode="L").save(f"{TEX_DIR}/boat3d_{name}_roughness.png", optimize=True)
    print(name, "maps done; metal share", round(float(metal.mean()), 3), "roughness", round(float(rough.min()), 2), "~", round(float(rough.max()), 2))


data, gltf, bin_off = load_glb(SRC)
write_mesh(data, gltf, bin_off)
prims = gltf["meshes"][gltf["nodes"][gltf["scenes"][0]["nodes"][0]]["mesh"]]["primitives"]
for i, p in enumerate(prims):
    name = PARTS[i][0]
    tex = gltf["materials"][p["material"]]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    img = Image.open(io.BytesIO(view_bytes(data, gltf, bin_off, gltf["images"][gltf["textures"][tex]["source"]]["bufferView"])))
    img.convert("RGB").save(f"{TEX_DIR}/boat3d_{name}_albedo.png", optimize=True)
    make_maps(img, name)
