"""试玩日志的测量报告（设计对照文档 5.2、5.3：真人试玩）。

读游戏写的 user://playlogs/*.jsonl（Windows 上是 %APPDATA%\\Godot\\app_userdata\\冥海契约\\playlogs\\），
按契约、按夜把一竿一竿的事件汇总，和整局模拟器（tests/sim_contract.tscn）的"每一夜的账"对着看：
- 每夜：竿数、咬钩、钓上、每场搏斗多少秒、留 / 生吞 / 处理 / 放生（放生 2026-11-04 删了，老日志里才有）、制饵几次、黄昏要多少、船舱里有多少、献上多少、够没够；
  黄昏时的饱腹、夜里饿到下一档几回（G3 起的日志才有）；唤祂时手里还剩几份饵（新回合机制 H1 起才有）
- 节奏：一夜没有钟了（H1），一夜真实过了多少秒、平均每竿多少秒（含看渔获、制饵、契约书的时间），和模拟器估的对照
- 每份契约：怎么结束的（偿清 / 落水 / 被吞噬 / 没打完）、供奉丢了几枚烙印、剪了几次线（2026-11-04 起剪线也扣烙印）、结算的评价（G4 起的日志才有）
- 奖励卡（H2 起的日志才有）：每份契约每一夜供奉后给了几张候选、挑了哪张；献上的是要的几倍（到 150% 就是超额）；
  引深引上来的、进化长了的各几次。和模拟器的"奖励卡"一段对着看
- 自动垂钓（2026-11-04 起的日志才有）：自动收线几场、钓上几成、平均的机会，停下来交给你的、自动停了的各是为什么。
  自动收线的不算进"搏斗"那张表（那张和模拟器的手打对着看）

用法：
  python tools/playlog_report.py                   读默认文件夹里全部的日志
  python tools/playlog_report.py a.jsonl b.jsonl   只读这几个
  python tools/playlog_report.py --latest 3        只读最新的 3 个
  python tools/playlog_report.py --out 报告.md      另外写成一个 Markdown 文件
不到 --min-night 秒（默认 0，都算）的夜不算：要排掉自动跑出来的短夜时用。
"""
import argparse
import glob
import json
import os
import sys
from statistics import mean, median





def promise_names(kind="promises"):
    """许汝之物（或者奖励卡：kind="cards"）的 id → 中文名（读 data/<kind>/*.tres）"""
    names = {}
    folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", kind)
    for path in glob.glob(os.path.join(folder, "*.tres")):
        fields = {}
        with open(path, encoding="utf-8") as f:
            for line in f:
                if " = " in line:
                    key, value = line.split(" = ", 1)
                    fields[key.strip()] = value.strip().strip('"')
        if "id" in fields:
            names[fields["id"]] = fields.get("display_name", fields["id"])
    return names


PROMISES = promise_names()
CARDS = promise_names("cards")
FIGHT_RESULTS = ["caught", "slipped", "cut", "gamble_won", "fell", "overtime", "lured"]
FIGHT_NAMES = {"caught": "钓上", "slipped": "脱钩", "cut": "剪线", "gamble_won": "硬撑钓上", "fell": "落水", "overtime": "超时",
               "lured": "引深引上来"}
DECISIONS = ["keep", "eat", "dismantle", "release"]
DECISION_NAMES = {"keep": "留", "eat": "吞", "dismantle": "处理", "release": "放"}
OUTCOMES = {"repaid": "偿清", "fall": "落水", "offering": "被吞噬", "unfinished": "没打完"}


def default_dir():
    appdata = os.environ.get("APPDATA") or os.path.expanduser("~/.local/share")
    return os.path.join(appdata, "Godot", "app_userdata", "冥海契约", "playlogs")


def load(path):
    events = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return events


def new_night(number, t):
    return {"night": number, "start": t, "dusk": None, "casts": [], "bites": 0, "salvage": 0, "misses": {},
            "hooks": 0, "fights": {}, "fight_seconds": [], "catches": 0, "decisions": {}, "crafts": 0, "items": 0,
            "exhausted": 0, "demand": None, "hold": None, "offered": None, "met": None, "wish_met": None,
            "brand_lost": False, "level": None, "hunger": None, "hungry": 0, "summon_baits": None, "supply": 0,
            "choices": None, "card": None, "evolved": 0, "auto_fights": {}, "auto_chances": [], "takeovers": {},
            "auto_stops": {}, "events": []}


def apply(night, e):
    k = e["kind"]
    if k == "cast":
        night["casts"].append(e["t"])
    elif k == "bite":
        night["bites"] += 1
    elif k == "salvage":
        night["salvage"] += 1
    elif k == "miss":
        why = e.get("why", "?")
        night["misses"][why] = night["misses"].get(why, 0) + 1
    elif k == "hook":
        night["hooks"] += 1
    elif k == "fight" and e.get("auto"):  # 自动收线（2026-11-04 起）：单算
        r = e.get("result", "?")
        night["auto_fights"][r] = night["auto_fights"].get(r, 0) + 1
        if "chance" in e:
            night["auto_chances"].append(float(e["chance"]))
    elif k == "fight":
        r = e.get("result", "?")
        night["fights"][r] = night["fights"].get(r, 0) + 1
        if "seconds" in e:
            night["fight_seconds"].append(float(e["seconds"]))
    elif k == "catch":
        night["catches"] += 1
    elif k == "decide":
        a = e.get("action", "?")
        night["decisions"][a] = night["decisions"].get(a, 0) + 1
    elif k == "craft":
        night["crafts"] += 1
    elif k == "item":
        night["items"] += 1
    elif k == "exhausted":
        night["exhausted"] += 1
    elif k == "level_up":
        night["level"] = e.get("soul_level")
    elif k == "hungry":
        night["hungry"] += 1
    elif k == "summon":
        night["summon_baits"] = e.get("baits")
    elif k == "supply":
        night["supply"] += e.get("baits", 0)
    elif k == "dusk":
        night["dusk"] = e["t"]
        night["demand"] = e.get("demand")
        night["hold"] = e.get("hold_tribute", e.get("hold_food"))  # G2 起是祭值；更早的日志是饱食度
        night["hunger"] = e.get("hunger")  # G3 起才有
    elif k == "offering":
        night["offered"] = e.get("tribute", e.get("food"))
        night["met"] = e.get("met")
        night["wish_met"] = e.get("wish_met")
        night["brand_lost"] = bool(e.get("brand_lost"))
        if e.get("demand"):
            night["demand"] = e.get("demand")
    elif k == "reward":
        night["choices"] = len(e.get("choices", []))
        night["card"] = e.get("picked") or None
    elif k == "event":  # 海上事件（阶段 IV）：哪一件、选了第几个（−1 不接）
        night["events"].append((e.get("id", "?"), int(e.get("choice", -1)), e.get("got", "")))
    elif k == "evolve":
        night["evolved"] += 1
    elif k == "auto" and not e.get("on"):
        why = e.get("why", "?")
        bucket = night["takeovers"] if e.get("takeover") else night["auto_stops"]
        bucket[why] = bucket.get(why, 0) + 1


## 一个日志文件里可能有好几份契约：每次签约开一份，死了或者偿清了就结束
def split_contracts(path, events):
    contracts = []
    cur = None
    last = None  # 刚结束的那一份：结算清单（settlement）在 death / repaid 之后才写
    for e in events:
        k = e.get("kind")
        if k == "settlement" and last is not None:
            last["rating"] = e.get("rating", "")
            last["promise"] = e.get("promise", "")
            continue
        if k == "sign":
            cur = {"file": os.path.basename(path), "number": e.get("number"), "name": e.get("name", ""),
                   "outcome": "unfinished", "nights": [new_night(1, e["t"])], "rating": "", "promise": e.get("promise", "")}
            contracts.append(cur)
            continue
        if cur is None:
            continue
        if k == "night":
            cur["nights"].append(new_night(e.get("night", len(cur["nights"]) + 1), e["t"]))
            continue
        apply(cur["nights"][-1], e)
        if k == "death":
            cur["outcome"] = "fall" if e.get("cause") == "fall" else "offering"
            last, cur = cur, None
        elif k == "repaid":
            cur["outcome"] = "repaid"
            last, cur = cur, None
    return contracts


def elapsed(night):
    return night["dusk"] - night["start"] if night["dusk"] is not None else None


def fmt(x, digits=1):
    if x is None:
        return "—"
    return f"{x:.{digits}f}" if isinstance(x, float) else str(x)


def report(contracts, min_night):
    lines = []
    out = lines.append
    out("# 试玩测量报告\n")
    out(f"不到 {min_night:.0f} 秒的夜不算。\n")
    out("## 每份契约\n")
    out("| 日志 | 编号 | 名字 | 许汝之物 | 结局 | 打到第几夜 | 供奉丢的烙印 | 剪线（也扣烙印） | 评价 |")
    out("|---|---|---|---|---|---|---|---|---|")
    real = []
    for c in contracts:
        nights = [n for n in c["nights"] if elapsed(n) is not None and elapsed(n) >= min_night]
        real.extend(nights)
        if not nights:
            continue
        lost = sum(1 for n in c["nights"] if n["brand_lost"])
        cuts = sum(n["fights"].get("cut", 0) for n in c["nights"])
        promise = PROMISES.get(c.get("promise") or "", c.get("promise") or "—")
        out(f"| {c['file']} | {c['number']} | {c['name']} | {promise} | {OUTCOMES[c['outcome']]} | "
            f"{c['nights'][-1]['night']} | {lost} | {cuts} | {c.get('rating') or '—'} |")
    if not real:
        out("\n没有能算的夜：玩一份完整的契约（至少打完一夜）再跑。")
        return "\n".join(lines)

    out("\n## 每一夜\n")
    out("一夜没有钟（新回合机制）：真实秒数 = 从天黑到黄昏真过了多久（含看渔获、制饵、契约书）；每竿秒数 = 真实秒数 ÷ 竿数，")
    out("和模拟器估的对照（tests/sim_contract.tscn 的「一夜几分钟」）。唤祂剩饵 = 唤祂时饵料篓里还剩几份。\n")
    out("| 夜 | 几夜 | 竿数 | 咬钩 | 钓上 | 每场搏斗秒 | 留/吞/处理/放 | 制饵 | 需求 | 船舱 | 献上 | 够了 | 黄昏饱腹 | 饿了几回 | 唤祂剩饵 | 真实秒数 | 每竿秒数 |")
    out("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    by_night = {}
    for n in real:
        by_night.setdefault(n["night"], []).append(n)
    for number in sorted(by_night):
        rows = by_night[number]
        casts = mean(len(n["casts"]) for n in rows)
        fights = [s for n in rows for s in n["fight_seconds"]]
        dec = "/".join(fmt(mean(n["decisions"].get(a, 0) for n in rows)) for a in DECISIONS)
        demands = [n["demand"] for n in rows if n["demand"] is not None]
        holds = [n["hold"] for n in rows if n["hold"] is not None]
        offered = [n["offered"] for n in rows if n["offered"] is not None]
        mets = [n["met"] for n in rows if n["met"] is not None]
        hungers = [n["hunger"] for n in rows if n["hunger"] is not None]
        left = [n["summon_baits"] for n in rows if n["summon_baits"] is not None]
        real_s = mean(elapsed(n) for n in rows)
        out(f"| {number} | {len(rows)} | {fmt(casts)} | {fmt(mean(n['bites'] for n in rows))} | "
            f"{fmt(mean(n['catches'] for n in rows))} | {fmt(mean(fights)) if fights else '—'} | {dec} | "
            f"{fmt(mean(n['crafts'] for n in rows))} | {fmt(mean(demands)) if demands else '—'} | "
            f"{fmt(mean(holds)) if holds else '—'} | {fmt(mean(offered)) if offered else '—'} | "
            f"{fmt(100.0 * sum(mets) / len(mets), 0) + '%' if mets else '—'} | "
            f"{fmt(float(mean(hungers)), 0) if hungers else '—'} | {fmt(mean(n['hungry'] for n in rows))} | "
            f"{fmt(float(mean(left))) if left else '—'} | {fmt(real_s, 0)} | {fmt(real_s / casts) if casts else '—'} |")

    out("\n## 搏斗\n")
    fights = [s for n in real for s in n["fight_seconds"]]
    totals = {}
    for n in real:
        for r, c in n["fights"].items():
            totals[r] = totals.get(r, 0) + c
    if fights:
        out(f"一共 {len(fights)} 场，平均 {mean(fights):.1f} 秒，中位 {median(fights):.1f} 秒。"
            "模拟器里普通的手同级一场约 12–15 秒。\n")
    out("| " + " | ".join(FIGHT_NAMES[r] for r in FIGHT_RESULTS) + " |")
    out("|" + "---|" * len(FIGHT_RESULTS))
    out("| " + " | ".join(str(totals.get(r, 0)) for r in FIGHT_RESULTS) + " |")
    misses = {}
    for n in real:
        for why, c in n["misses"].items():
            misses[why] = misses.get(why, 0) + c
    names = {"too_early": "收竿太早", "late": "没来得及 / 没提", "nothing": "空等", "dusk": "到点收线"}
    out("\n没钓上的：" + "，".join(f"{names.get(k, k)} {v}" for k, v in sorted(misses.items())) if misses else "")

    # 自动垂钓（2026-11-04 起）：自动收线的结局、机会，停下来的原因
    auto = {}
    chances = []
    takeovers = {}
    stops = {}
    for n in real:
        for r, c in n["auto_fights"].items():
            auto[r] = auto.get(r, 0) + c
        chances.extend(n["auto_chances"])
        for why, c in n["takeovers"].items():
            takeovers[why] = takeovers.get(why, 0) + c
        for why, c in n["auto_stops"].items():
            stops[why] = stops.get(why, 0) + c
    if auto or takeovers or stops:
        out("\n## 自动垂钓\n")
        total = sum(auto.values())
        if total:
            caught = auto.get("caught", 0)
            out(f"自动收线 {total} 场，钓上 {caught} 场（{100.0 * caught / total:.0f}%）"
                + (f"，平均的机会 {100.0 * mean(chances):.0f}%" if chances else "") + "。")
        if takeovers:
            out("\n停下来交给你的：" + "，".join(f"{k} {v}" for k, v in sorted(takeovers.items(), key=lambda kv: -kv[1])))
        if stops:
            out("\n自动停了的：" + "，".join(f"{k} {v}" for k, v in sorted(stops.items(), key=lambda kv: -kv[1])))

    # 海上事件（阶段 IV 起）：碰上几件、每一种接了几次、得到了什么
    events = [ev for n in real for ev in n["events"]]
    if events:
        out("\n## 海上事件\n")
        names = {"trade": "冥市船", "hand": "溺者之手", "wreck": "漂来的残骸", "blood_moon": "血月", "whisper": "祂的低语"}
        seen = {}
        taken = {}
        for ev_id, choice, got in events:
            seen[ev_id] = seen.get(ev_id, 0) + 1
            if choice >= 0:
                taken[ev_id] = taken.get(ev_id, 0) + 1
        out("一共 %d 件（%d 夜）。" % (len(events), len(real)) + "，".join(
            "%s %d 次（接了 %d）" % (names.get(k, k), v, taken.get(k, 0)) for k, v in sorted(seen.items(), key=lambda kv: -kv[1])))

    # 奖励卡（H2 起）：每份契约每一夜给了几张候选、挑了哪张，献上的是要的几倍
    rewarded = [c for c in contracts if any(n["choices"] is not None for n in c["nights"])]
    if rewarded:
        out("\n## 奖励卡\n")
        out("每一格：献上 ÷ 要的（到 1.5 就是超额）· 几张候选 · 挑了哪张。模拟器里达标就收·普通七成多的夜是两张、一成多三张。\n")
        width = max(len(c["nights"]) for c in rewarded)
        out("| 编号 | " + " | ".join(f"第 {i + 1} 夜" for i in range(width)) + " | 引深 / 进化 |")
        out("|---|" + "---|" * width + "---|")
        picks = {}
        counts = {}
        for c in rewarded:
            cells = []
            for n in c["nights"]:
                ratio = n["offered"] / n["demand"] if n["offered"] is not None and n["demand"] else None
                cell = fmt(ratio, 2) if ratio is not None else "—"
                if n["choices"] is not None:
                    counts[n["choices"]] = counts.get(n["choices"], 0) + 1
                    cell += f" · {n['choices']} 张"
                    if n["card"]:
                        cell += f" · {CARDS.get(n['card'], n['card'])}"
                        picks[n["card"]] = picks.get(n["card"], 0) + 1
                cells.append(cell)
            cells += [""] * (width - len(cells))
            lured = sum(n["fights"].get("lured", 0) for n in c["nights"])
            evolved = sum(n["evolved"] for n in c["nights"])
            out(f"| {c['number']} | " + " | ".join(cells) + f" | {lured} / {evolved} |")
        total = sum(counts.values())
        out("\n候选：" + "，".join(f"{k} 张 {v} 夜（{100.0 * v / total:.0f}%）" for k, v in sorted(counts.items())) +
            "；挑过：" + ("，".join(f"{CARDS.get(k, k)} {v}" for k, v in sorted(picks.items(), key=lambda kv: -kv[1])) or "没有"))
    return "\n".join(lines)


def main(argv):
    parser = argparse.ArgumentParser(description="试玩日志的测量报告")
    parser.add_argument("files", nargs="*", help="日志文件；不写就读默认文件夹")
    parser.add_argument("--latest", type=int, default=0, help="只读最新的几个")
    parser.add_argument("--min-night", type=float, default=0.0, help="不到这么多秒的夜不算（默认 0，都算）")
    parser.add_argument("--out", help="另外写成 Markdown 文件")
    args = parser.parse_args(argv)
    files = args.files or sorted(glob.glob(os.path.join(default_dir(), "*.jsonl")))
    if args.latest:
        files = sorted(files, key=os.path.getmtime)[-args.latest:]
    contracts = []
    for path in files:
        contracts.extend(split_contracts(path, load(path)))
    text = report(contracts, args.min_night)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    print(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
