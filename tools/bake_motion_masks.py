"""把生物插图烘成动效遮罩（2026-11-05）：assets/creatures/<名字>.png → assets/creatures/motion/<名字>.png。
给 shaders/creature_display.gdshader 用（CreatureArt.mask_for 按同名找）：插图哪里是身子、哪里是附肢（鳍、须、手指、头灯、触须、水草……），
附肢上每一点离身子多远、往哪边长、和别的附肢错开多少。着色器按种类的动效（FishData.motion_style）让附肢各自摆起来。

    python tools/bake_motion_masks.py              # 烘所有插图（跳过遮罩比插图、这一种的 .tres 都新的）
    python tools/bake_motion_masks.py --force      # 全部重烘
    python tools/bake_motion_masks.py grey_dace    # 只烘名字里带这一段的
    python tools/bake_motion_masks.py --debug 文件夹  # 另存一张看得懂的预览（灰 = 身子，彩色 = 附肢，颜色是相位）

只用插图的透明度，不用另外画：新加的生物放进 assets/creatures/ 以后跑一遍就有了。
怎么算的（工作分辨率宽 256）：
1. 形状 = 不透明的部分；每一点离背景多远（逐次腐蚀，棋盘距离），最厚处的半厚是 dmax。
2. 身子 = 形状做一次开运算（方形核，边长 CORE_K × dmax）以后最大的那一块：比它细的部分都被刮掉了。
3. 附肢 = 形状里不是身子的部分（鳍、须、手指……），按连通块分开，太小的碎点并回身子。
4. 附肢上每一点沿着形状离身子多远（测地距离）÷ REACH × 高 = 权重（根部 0，越往外越大，最多 1）。
   长的附肢尖上动得多、短的鳍动得少，和绕根部转一个角度是一样的。
5. 有的附肢不单独摆，只跟着身子动（2026-11-05，你说嘴像果冻一样弹、尾巴晃的时候有割裂感）：
   - 太短的（不到 MIN_LIMB × 高）：刺、牙、鳞片的尖，哪一种都不摆。
   - 会游的（鱼、鳗、灯笼、鲀、鲸，看这一种 .tres 里的 motion_style）：
     - 头那一截（HEAD_ZONE）里的：嘴、吻尖、下巴、牙、脸上的刺都不摆——一张平面插图做不了嘴的开合，单独摆起来就像果冻。
       只有 .tres 里 motion_head_limbs 打开的种类（千目窥渊鲶的须、磷灯婆的头灯），细长的（长 ÷ 粗过了 SLENDER）照样摆。
       光看形状分不出须和尖嘴（鲟鱼幼年的吻和须一样又细又长），所以由种类自己说。
     - 尾巴：碰到身子最后头的那一块（尾鳍）、根在 TAIL_ZONE 以后的，只跟着身子那道波摆。再单独抖一层，尾柄和尾鳍之间会错开。
   - 手、水母、蟹、扁的、螺：手指、触须、腿、边上的东西照样各摆各的。
6. 每一块附肢一个相位（按从左到右排，黄金分割错开），一个方向（根部的中心指向尖上的中心）。
   头上照样摆的那几根（须、头灯）另记一笔，着色器给它们慢慢地飘，不和鳍一样快快地抖。
7. 往形状外面再铺几个像素（权重一步步变小），附肢摆出去的时候外面也有值（着色器是反着取样的）。
输出 RGB：R = 权重，G = 相位（0–0.5 是鳍这些，0.5–1 是头上的须、头灯），B = 方向角 ÷ 2π。身子和远处的背景都是 0。
8. 会游的另烘一张"脊"（<名字>_body.png，2026-11-05：磷灯婆、千目鲇、白鲟的身子是弯的，原来那道波一律上下推，
   往上翘的尾巴就成了顺着自己伸缩，不像在摆）：身子（连同只跟着身子动的头、尾鳍）从头那头沿着身子量过去的距离 s
   （0 = 头，1 = 尾巴尖），和每一点横过身子的方向。着色器沿着 s 传那道波、顺着横的方向推，弯的身子、翘的尾巴都是左右摆。
   整张图都填上（离身子最近的那一点的值，再抹平），网格上透明的地方也跟着身子走。
   输出 RGB：R = s，G、B = 横的方向（0.5 + 0.5 × 分量）。
"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "creatures")
OUT = os.path.join(SRC, "motion")

WORK_W = 256        # 工作分辨率（宽），遮罩也存这么大
ALPHA_CUT = 0.3     # 透明度过了这个算形状
CORE_K = 0.8        # 开运算的核边长 = 这个 × 最厚处的半厚：比身子厚度的四成还细的算附肢
MIN_PART = 0.002    # 附肢的连通块小于形状面积的这么多，并回身子（描边上的碎点）
REACH = 0.3         # 离身子这么远（占图高）权重到 1
SPREAD = 0.05       # 往形状外面铺多远（占图宽）
SPREAD_DECAY = 0.9  # 往外每铺一个像素，权重乘这个
GOLDEN = 0.6180339887
# 哪些附肢不单独摆（见上面第 5 条）；会游的另烘脊（第 8 条）。和 CreatureArt.SWIMMERS 一样
SWIMMERS = {"fish", "eel", "lantern", "puffer", "whale"}
MIN_LIMB = 0.07     # 比这短（占图高）的附肢不摆
HEAD_ZONE = 0.3     # 形状从头那头数这么宽（占外框宽）算头
TAIL_ZONE = 0.7     # 根在这以后的算尾巴
TAIL_END = 0.95     # 碰到这么靠后的（占外框宽）算尾鳍
SLENDER = 5.0       # 头上的附肢长 ÷ 粗过了这个，算须、头灯（只对 motion_head_limbs 打开的种类）


def tres_for(image_name):
    """这张插图那一种的 .tres（data/fish/ 或 data/fish_draft/），没有返回 None"""
    base = re.sub(r"_(juvenile|adult)$", "", os.path.splitext(image_name)[0])
    for d in ("fish", "fish_draft"):
        p = os.path.join(ROOT, "data", d, base + ".tres")
        if os.path.exists(p):
            return p
    return None


def style_of(image_name):
    """这张插图是哪一种的：(怎么动, 头上的须、头灯摆不摆)，读 data/fish/ 或 data/fish_draft/ 里 .tres 的
    motion_style、motion_head_limbs；找不到算鱼、不摆"""
    base = re.sub(r"_(juvenile|adult)$", "", os.path.splitext(image_name)[0])
    for d in ("fish", "fish_draft"):
        p = os.path.join(ROOT, "data", d, base + ".tres")
        if os.path.exists(p):
            text = open(p, encoding="utf-8").read()
            m = re.search(r'^motion_style = "(\w+)"', text, re.M)
            return (m.group(1) if m else "fish"), re.search(r"^motion_head_limbs = true", text, re.M) is not None
    return "fish", False


def _filter(mask, flt):
    im = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8), "L")
    return np.array(im.filter(flt)) > 127


def erode(mask, k):
    return _filter(mask, ImageFilter.MinFilter(k)) if k > 1 else mask.copy()


def dilate(mask, k):
    return _filter(mask, ImageFilter.MaxFilter(k)) if k > 1 else mask.copy()


def shift(a, dy, dx, fill):
    """整张往 (dy, dx) 挪，空出来的填 fill（不回卷）"""
    out = np.full_like(a, fill)
    h, w = a.shape
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = a[ys, xs]
    return out


NEIGHBORS = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]


def label(mask):
    """八连通的连通块：返回 (标号图, 块数)，标号从 1 开始"""
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    for y0, x0 in zip(*np.nonzero(mask)):
        if lab[y0, x0]:
            continue
        n += 1
        lab[y0, x0] = n
        stack = [(y0, x0)]
        while stack:
            y, x = stack.pop()
            for dy, dx in NEIGHBORS:
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = n
                    stack.append((yy, xx))
    return lab, n


def depth(shape):
    """每一点离背景多远（逐次腐蚀，棋盘距离）"""
    d = np.zeros(shape.shape, np.int32)
    cur = shape.copy()
    while cur.any():
        d[cur] += 1
        cur = erode(cur, 3)
    return d


def geodesic(core, shape):
    """形状里每一点沿着形状离身子多远（八连通的步数）；和身子不连着的碎块，按直线离身子多远补上"""
    dist = np.full(shape.shape, np.inf)
    dist[core] = 0
    reached = core.copy()
    step = 0
    while True:
        step += 1
        grown = dilate(reached, 3) & shape & ~reached
        if not grown.any():
            break
        dist[grown] = step
        reached |= grown
    loose = shape & ~reached
    if loose.any():
        free = reached.copy()
        free_step = 0
        while (loose & ~free).any() and free_step < 4 * max(shape.shape):
            free_step += 1
            grown = dilate(free, 3) & ~free
            dist[grown & loose] = free_step
            free |= grown
    return dist


def bake(path, out_path, debug_dir=None):
    src = Image.open(path).convert("RGBA")
    work_h = max(8, round(src.height * WORK_W / src.width))
    # 先在原图上把透明度扩一点再缩：细的须、触须缩到工作分辨率以后还在
    grow = max(3, (src.width // WORK_W) | 1)
    alpha = np.array(src.getchannel("A").filter(ImageFilter.MaxFilter(grow)).resize((WORK_W, work_h), Image.BOX)) / 255.0
    shape = alpha > ALPHA_CUT
    h, w = shape.shape
    d = depth(shape)
    dmax = int(d.max())
    k = max(3, int(round(CORE_K * dmax)) | 1)
    opened = dilate(erode(shape, k), k) & shape
    lab, n = label(opened)
    if n == 0:
        core = shape.copy()
    else:
        sizes = np.bincount(lab.ravel())
        sizes[0] = 0
        core = lab == int(sizes.argmax())
    parts = shape & ~core
    plab, pn = label(parts)
    area = shape.sum()
    for i in range(1, pn + 1):
        if (plab == i).sum() < MIN_PART * area:
            core |= plab == i
            plab[plab == i] = 0
    dist = geodesic(core, shape)
    # 不单独摆的附肢并回身子（见上面第 5 条）
    style, head_limbs = style_of(os.path.basename(path))
    xs_all = np.nonzero(shape)[1]
    x0, bw = xs_all.min(), max(1, xs_all.max() - xs_all.min())
    ring = dilate(core, 3)
    rigid = 0
    head_parts = set()  ## 头上照样摆的须、头灯
    for i in range(1, pn + 1):
        m = plab == i
        if not m.any():
            continue
        dm = dist[m]
        finite = np.isfinite(dm)
        length = float(dm[finite].max()) if finite.any() else 0.0
        root = m & ring
        ys, xs = np.nonzero(root if root.any() else m)
        rx = (xs.mean() - x0) / bw
        reach_x = (np.nonzero(m)[1].max() - x0) / bw
        thick = 2.0 * float(np.median(d[m]))
        slender = length / max(1.0, thick)
        still = length < MIN_LIMB * h
        if style in SWIMMERS:
            head = rx < HEAD_ZONE and not (head_limbs and slender >= SLENDER)
            tail = rx > TAIL_ZONE or reach_x >= TAIL_END
            still = still or head or tail
            if not still and rx < HEAD_ZONE:
                head_parts.add(i)
        if still:
            plab[m] = 0
            rigid += 1
    reach = REACH * h
    weight = np.where(plab > 0, np.clip(np.nan_to_num(dist, posinf=reach) / reach, 0.0, 1.0), 0.0)
    phase = np.zeros((h, w))
    angle = np.zeros((h, w))
    ids = [i for i in range(1, pn + 1) if (plab == i).any()]
    cy_core, cx_core = [float(v.mean()) for v in np.nonzero(core)] if core.any() else (h / 2, w / 2)
    ids.sort(key=lambda i: np.nonzero(plab == i)[1].mean())
    for order, i in enumerate(ids):
        m = plab == i
        phase[m] = ((order * GOLDEN + 0.13) % 1.0) * 0.5 + (0.5 if i in head_parts else 0.0)
        dm = dist[m]
        ys, xs = np.nonzero(m)
        finite = np.isfinite(dm)
        if finite.any() and dm[finite].max() > dm[finite].min():
            lo, hi = dm[finite].min(), dm[finite].max()
            root = finite & (dm <= lo + 2)
            tip = finite & (dm >= lo + 0.75 * (hi - lo))
            vy = ys[tip].mean() - ys[root].mean()
            vx = xs[tip].mean() - xs[root].mean()
        else:
            vy = ys.mean() - cy_core
            vx = xs.mean() - cx_core
        angle[m] = (math.atan2(vy, vx) / (2 * math.pi)) % 1.0
    # 往形状外面铺：附肢摆出去的地方也要有值
    weight = np.array(Image.fromarray((weight * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(1))) / 255.0 * (plab > 0) \
        + weight * (plab == 0)
    assigned = shape.copy()
    for _ in range(max(1, int(round(SPREAD * w)))):
        best = np.zeros((h, w))
        best_p = np.zeros((h, w))
        best_a = np.zeros((h, w))
        for dy, dx in NEIGHBORS:
            cw = shift(weight, dy, dx, 0.0)
            take = cw > best
            best = np.where(take, cw, best)
            best_p = np.where(take, shift(phase, dy, dx, 0.0), best_p)
            best_a = np.where(take, shift(angle, dy, dx, 0.0), best_a)
        new = ~assigned & (best > 0.01)
        if not new.any():
            break
        weight[new] = best[new] * SPREAD_DECAY
        phase[new] = best_p[new]
        angle[new] = best_a[new]
        assigned |= new
    rgb = np.stack([weight, phase, angle], axis=-1)
    Image.fromarray(np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB").save(out_path, optimize=True)
    if debug_dir:
        _preview(src, shape, shape & (plab == 0), weight, phase, os.path.join(debug_dir, os.path.basename(out_path)))
    body_path = body_path_for(out_path)
    if style in SWIMMERS:
        s, nx, ny = body_field(shape & (plab == 0))
        body = np.stack([s, 0.5 + 0.5 * nx, 0.5 + 0.5 * ny], axis=-1)
        Image.fromarray(np.clip(body * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB").save(body_path, optimize=True)
        if debug_dir:
            _preview_body(src, shape & (plab == 0), s, nx, ny, os.path.join(debug_dir, os.path.basename(body_path)))
    elif os.path.exists(body_path):
        os.remove(body_path)
    return len(ids), rigid, dmax, k, style


def body_path_for(out_path):
    root, ext = os.path.splitext(out_path)
    return root + "_body" + ext


def box_blur(a, r):
    """方框模糊（半径 r 像素），边上按最近的值补"""
    if r <= 0:
        return a
    k = 2 * r + 1
    c = np.cumsum(np.cumsum(np.pad(a, r, mode="edge"), 0), 1)
    c = np.pad(c, ((1, 0), (1, 0)))
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def fill_nearest(values, known):
    """known 以外的像素，一圈一圈用旁边已知的平均值填满整张图"""
    v = np.where(known, values, 0.0)
    k = known.copy()
    for _ in range(sum(k.shape)):
        if k.all():
            break
        acc = np.zeros_like(v)
        cnt = np.zeros_like(v)
        kf = k.astype(float)
        for dy, dx in NEIGHBORS:
            ck = shift(kf, dy, dx, 0.0)
            acc += shift(v, dy, dx, 0.0) * ck
            cnt += ck
        new = ~k & (cnt > 0)
        v[new] = acc[new] / cnt[new]
        k |= new
    return v


def body_field(body):
    """身子的"脊"：从头那头（最左边的几列）沿着身子量过去的距离 s（0–1），和横过身子的方向 (nx, ny)。整张图都有值"""
    h, w = body.shape
    cols = np.nonzero(body)[1]
    xx = np.arange(w)[None, :].repeat(h, 0)
    seed = body & (xx <= cols.min() + max(2, int(round(0.03 * w))))
    dist = geodesic(seed, body)
    known = body & np.isfinite(dist)
    smax = max(1.0, float(dist[known].max()))
    s = fill_nearest(np.where(known, dist / smax, 0.0), known)
    s = box_blur(s, 3)
    gy, gx = np.gradient(s)
    gx = box_blur(gx, 5)
    gy = box_blur(gy, 5)
    norm = np.hypot(gx, gy)
    flat = norm < 1e-6
    tx = np.where(flat, 1.0, gx / np.maximum(norm, 1e-6))
    ty = np.where(flat, 0.0, gy / np.maximum(norm, 1e-6))
    return np.clip(s, 0.0, 1.0), -ty, tx


def _preview_body(src, body, s, nx, ny, path):
    """脊的预览：身子按 s 从青（头）到红（尾）上色，每隔一段画一道横的方向"""
    from PIL import ImageDraw
    h, w = body.shape
    base = np.array(src.convert("RGB").resize((w, h), Image.LANCZOS)) / 255.0 * 0.3
    col = np.stack([s, 0.35 + 0.0 * s, 1.0 - s], -1)
    out = np.where(body[..., None], base * 0.4 + col * 0.6, base)
    img = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).resize((w * 3, h * 3), Image.NEAREST)
    dr = ImageDraw.Draw(img)
    for y in range(4, h, 8):
        for x in range(4, w, 8):
            if body[y, x]:
                cx, cy = x * 3 + 1, y * 3 + 1
                dr.line([cx - nx[y, x] * 9, cy - ny[y, x] * 9, cx + nx[y, x] * 9, cy + ny[y, x] * 9], fill=(255, 255, 255))
    img.save(path)


def _preview(src, shape, core, weight, phase, path):
    """看得懂的预览：插图压暗，身子灰，附肢按相位上色、按权重提亮"""
    h, w = shape.shape
    base = np.array(src.convert("RGB").resize((w, h), Image.LANCZOS)) / 255.0 * 0.35
    hue = phase * 6.0
    col = np.stack([np.clip(np.abs(hue - 3) - 1, 0, 1), np.clip(2 - np.abs(hue - 2), 0, 1), np.clip(2 - np.abs(hue - 4), 0, 1)], -1)
    out = base.copy()
    out[core] = out[core] * 0.6 + 0.25
    wm = weight > 0.01
    out[wm] = out[wm] * 0.3 + col[wm] * (0.35 + 0.65 * weight[wm, None])
    big = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).resize((w * 3, h * 3), Image.NEAREST)
    big.save(path)


def main(argv):
    force = "--force" in argv
    debug_dir = None
    if "--debug" in argv:
        debug_dir = argv[argv.index("--debug") + 1]
        os.makedirs(debug_dir, exist_ok=True)
    names = [a for a in argv if not a.startswith("--") and a != debug_dir]
    os.makedirs(OUT, exist_ok=True)
    count = 0
    for fn in sorted(os.listdir(SRC)):
        if not fn.endswith(".png"):
            continue
        if names and not any(n in fn for n in names):
            continue
        src_path = os.path.join(SRC, fn)
        out_path = os.path.join(OUT, fn)
        # 插图或者这一种的 .tres（motion_style、motion_head_limbs）比遮罩新，就重烘
        tres = tres_for(fn)
        newest = max(os.path.getmtime(src_path), os.path.getmtime(tres) if tres else 0.0)
        if not force and os.path.exists(out_path) and os.path.getmtime(out_path) >= newest:
            continue
        parts, rigid, dmax, k, style = bake(src_path, out_path, debug_dir)
        count += 1
        print("%-36s %-8s 附肢 %2d 块各自摆、%2d 块只跟着身子（最厚半厚 %d，核 %d）" % (fn, style, parts, rigid, dmax, k))
    print("烘了 %d 张" % count)


if __name__ == "__main__":
    main(sys.argv[1:])
