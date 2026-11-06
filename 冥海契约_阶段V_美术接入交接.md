# 冥海契约：阶段 V 美术接入交接

日期：2026-11-05  
写给：接手的人（GPT 或 Claude）。需求原文是《冥海契约_阶段V_种族名册与美术需求》第 4–6 节。

## 用哪一份素材
`output/` 下两份内容一样：`阶段V_美术资产_v1/`（工作文件夹，带 Codex 的 README、清单、每张图的 metadata）和 `阶段V_美术资产_v1_交付.zip`（同一批的打包）。
95 张 PNG 逐个比过 md5，完全一样。**用文件夹**，zip 不用解。

自检结果：86 张都在，规格都对。
- 恩赐图标 16 张，256²。
- 新生物立绘 39 张，宽 1024。
- 图鉴小图 20 张，256²。
- 格框 2 张，324²，中心透明。
- 立绘底 1 张，1920×810。
- 事件插图 8 张，1024×512。
- 全部 RGBA、四角透明；新生物全部头朝左，三个时期一个比一个完整；扁的（哭面鲽、圣骸鳐）是从上往下看；水母伞盖在左。

`output/` 加了 `.gdignore`：它在项目里面，Godot 原来把它当游戏资源导入了一遍（那些 `.import` 就是这么来的）。

## 已经做了的（2026-11-05，都还没提交）
1. 86 张都复制进了 `assets/`：
   - `assets/icons/boon_*.png`
   - `assets/creatures/icons/*.png`
   - `assets/ui/codex_*.png`
   - `assets/creatures/<新 id>*.png`
   - `assets/events/*.png`
   新的 `.import` 都打开了 mipmaps（缩小显示不发虚，和生物插图、HUD 一样）。
2. 16 张永久恩赐卡（`data/cards/*.tres` 里 `permanent = true` 的）的图标换成了 `boon_<id>.png`。截图看过开局三选一和奖励屏。
3. 图鉴的小图、格框、立绘底：代码本来就按路径找（`CodexScreen._thumb`、`TILE_FRAME`、`PORTRAIT_PLATE`），放进去就用上了，截图看过。
4. 另一件没提交的：往左看海面出条带的修复（`shaders/sea_scene.gdshader` 的 `trace_sea`、`tests/sky_capture.gd` 的 `only=look`、`docs/场景与UI.md`）。

## 还要做的
（做完一项在这里划掉或写上"做了"）

### A. 十三种新生物上线
1. 做了：十三个 .tres 从 `data/fish_draft/` 挪进了 `data/fish/`（`git mv`），配上了三张插图（`icon` 成长期、`icon_juvenile`、`icon_adult`）。
2. 做了：跑过 `python tools/bake_motion_masks.py`，三十九张新插图都有动效遮罩，会游的还有"脊"。
   有须、头灯要单独飘的种类，在 .tres 里加 `motion_head_limbs = true`（现在只有磷灯婆、千目窥渊鲶）；新的十三种都没加。
3. 做了：`tests/test_catch.gd` 的 `_test_drafts` 改成查正式的二十种（草案剩 0 种），"只在血月 / 异化的夜里出""无面鲂特殊词条多"那几条照旧。
   上线以后测试跟着改了四处（都是名册变了，不是游戏坏了）：
   - `test_catch` / `test_bait` 找水层时，血月鳗、无面鲂按那种夜算（`CodexScreen._config_for`）。原来按平常的夜算，找不到水层，下标 −1 报错。
   - `test_bait`：深水骨渣饵最常咬钩的是盐尸蟹或噬骸鳗，萤浆饵是磷魂母或磷灯婆。每层水三种材料多的都有了，"不对路的饵"改成按公式查。
   - `test_codex` 查从弱到强的排序本身（最强的现在是无目祭司鲛）。
   - `test_fishing`：能力 3 档对 5 级的范围放到 60–86%（5 级多了挣扎轻的冥河蜃螺，平均 83%）。
   改完七套都过了（2026-11-05）。二十种成年的动效截过一张（`tests/motion_capture.tscn`），都有遮罩、没有报错。
4. 做了：结算清单的格子按种类数收窄（`SettlementScreen._cell()`：七种时一格 92 宽，二十种 58 宽，整排不超过 1160），名字小一号，一格一格亮得快一点。
   截图看过：二十种 × 三个时期一排放得下，名字看得清。
5. 图鉴：格子一行五格，二十种正好四行，代码不用改。看一眼血月鳗、无面鲂：右边写"只在血月 / 异化的夜里"，出没那一页按那种夜算。
6. 整局模拟器（没重跑：数和草案时一模一样，草案时测的就是现在的结果；想确认就跑 `res://tests/sim_contract.tscn -- dump`）：
   - 草案阶段测过加不加差不多：偿清 99 / 86 / 93 / 100 / 84%，对照 95 / 88 / 92 / 100 / 85%。
   - 献心多了三个点，看要不要把 `Settlement.DEVOTED_RATIO`（1.7）再提一点。
7. 截图：`tests/codex_capture.tscn`、`tests/motion_capture.tscn -- only=<id>`、`tests/catch_capture.tscn`（要出画面跑）。
8. 文档：
   - 《渔获与船舱》里的种类表、"插图的动态"
   - 计划文档第 111、112 条改成已上线
   - 名册文档第 4 节

### B. 海上事件插图（做了）
`EventScreen.ART`：插图浮在标题上面（380×190），轻轻上下浮；祂的低语那张压在祂的话后面、淡一些。截图看过冥市船、残骸、低语。
事件 id（`SeaEvents.NAMES`）对文件（`assets/events/`）：

| 事件 | id | 文件 |
|---|---|---|
| 冥市船 | trade | ghost_market.png |
| 溺者之手 | hand | drowned_hand.png |
| 漂来的残骸 | wreck | drifting_wreck.png |
| 血月 | blood_moon | blood_moon.png |
| 祂的低语 | whisper | his_whisper.png |
| 亡魂 | ghost | lost_soul.png |
| 暴雨 | storm | storm.png |
| 冥市的赌徒 | gambler | market_gambler.png |

截图：`tests/ui_capture.tscn` 有事件屏的几张。

### C. 提交
等你说了再提交。
- 照旧不放：`mobile-video-upload.json`、`冥海契约_当前版本全程展示.mp4`。
- `output/`（Codex 的工作文件夹和 50 MB 的 zip）要不要进仓库，问一下你；不进的话加进 `.gitignore`。
