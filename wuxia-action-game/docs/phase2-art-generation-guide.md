# Phase 2 AI 美术生成参考指南

本文档用于 Phase 2「美术管线验证」阶段，目标是把 GPT Image-2、HappyHouse、批处理脚本与 Godot 导入连接成可复用流程。所有资产必须先满足 `docs/superpowers/specs/2026-04-29-wuxia-action-game-design.md` 的硬性验收标准，再讨论审美偏好。

## 1. 生成原则

第一性原则：游戏资产不是单张好看的图，而是能在 60fps 战斗中稳定读取、分层、绑定、动画和复用的生产资料。


| 原则    | 量化要求                                           | 不合格表现            |
| ----- | ---------------------------------------------- | ---------------- |
| 可读性优先 | 灰度化 + 4px 高斯模糊后仍能区分玩家、杂兵、精英敌人                  | 只靠颜色区分阵营，剪影接近    |
| 管线一致  | 每张图先按 Prompt 约束生成，再映射到 32 色板，ΔE 均值 < 8         | 单图很好看，但放进场景后色温漂移 |
| 动画可拆  | 角色四肢、武器、衣摆边界清楚，便于骨骼绑定                          | 大片水墨糊成一团，关节不可见   |
| 战斗可判读 | 攻击命中帧必须有明确爆发形状，VFX 整体 α ≤ 80%                  | 特效遮挡角色动作和敌我距离    |
| 性能可控  | 单张纹理 ≤ 2048×2048，场景纹理 ≤ 16MB，战斗 Draw call ≤ 50 | 大图堆叠、透明层过多       |


## 2. 目录与文件命名

### 2.1 目录约定


| 类型          | 目标目录                           |
| ----------- | ------------------------------ |
| Style Bible | `assets/style_bible/`          |
| 主角          | `assets/characters/player/`    |
| 敌人 A：山匪杂兵   | `assets/characters/enemy_a/`   |
| 敌人 B：铁掌精英   | `assets/characters/enemy_b/`   |
| 翠竹林场景       | `assets/scenes/bamboo_forest/` |
| 战斗特效        | `assets/vfx/`                  |
| 生产源文件       | `assets/_source/phase2/`       |


如果目录不存在，创建时保持小写蛇形命名。Godot 导入用 PNG；Prompt、参考图、HappyHouse 工程文件放在 `_source`，避免运行时资源混杂。

### 2.2 文件命名格式

统一格式：

```text
p2_<asset_type>_<asset_id>_<view_or_anim>_<variant_or_frame>_<size>.<ext>
```

字段含义：


| 字段                 | 示例                                                               | 说明         |
| ------------------ | ---------------------------------------------------------------- | ---------- |
| `asset_type`       | `char`, `scene`, `vfx`, `style`                                  | 资产大类       |
| `asset_id`         | `player`, `enemy_a_bandit`, `enemy_b_iron_palm`, `bamboo_forest` | 资产身份       |
| `view_or_anim`     | `front`, `side`, `back`, `idle`, `atk01`, `hit_spark`            | 视图、动作或特效名  |
| `variant_or_frame` | `v01`, `f001`                                                    | 概念变体或序列帧编号 |
| `size`             | `512`, `1024x576`, `2048x1024`                                   | 单帧或图层尺寸    |


示例：

```text
assets/characters/player/p2_char_player_front_v01_512.png
assets/characters/player/p2_char_player_atk01_pose03_v01_512.png
assets/characters/enemy_a/p2_char_enemy_a_bandit_sheet_v01_1024.png
assets/scenes/bamboo_forest/p2_scene_bamboo_forest_midground_v01_2048x1024.png
assets/vfx/p2_vfx_hit_spark_f001_256.png
assets/vfx/p2_vfx_skill_burst_f012_512.png
```

## 3. 32 色调色板参考

用途：生成 Prompt 中声明色板，后处理脚本按此表进行色彩压缩。数值不是审美建议，而是跨资产一致性的锚点；最终以 ΔE 均值 < 8 为合格线。


| ID   | 名称    | HEX       | 用途         |
| ---- | ----- | --------- | ---------- |
| DG01 | 深墨绿 1 | `#07130E` | 最深阴影、竹林深处  |
| DG02 | 深墨绿 2 | `#0D2418` | 前景暗竹、衣物暗部  |
| DG03 | 深竹绿   | `#14351F` | 远景密林暗面     |
| DG04 | 冷松绿   | `#1D4728` | 中景竹干阴影     |
| DG05 | 暗苔绿   | `#275A34` | 草丛暗部       |
| DG06 | 墨叶绿   | `#315F3E` | 角色绿色布料暗部   |
| MG01 | 竹叶绿   | `#3E7046` | 主竹叶基色      |
| MG02 | 青竹绿   | `#4F8353` | 中景竹干       |
| MG03 | 苔石绿   | `#5F965F` | 地面苔藓       |
| MG04 | 晨雾绿   | `#72A56D` | 远景亮叶       |
| MG05 | 玉竹绿   | `#86B879` | 受光竹叶       |
| MG06 | 浅藤绿   | `#9AC58A` | 叶缘高光       |
| LG01 | 淡竹青   | `#B7D6A0` | 背景雾光       |
| LG02 | 米绿    | `#CADFB3` | 天光透射       |
| LG03 | 纸本绿   | `#DCE9C8` | 宣纸底色偏绿     |
| LG04 | 月白绿   | `#EEF4DF` | 最高亮、雾层     |
| WB01 | 树皮棕   | `#4A3224` | 竹节暗纹、木结构   |
| WB02 | 温土棕   | `#63452E` | 地面、木桥      |
| WB03 | 枯叶棕   | `#7A5A38` | 落叶、草鞋      |
| WB04 | 皮革棕   | `#936E45` | 腰带、护腕      |
| WB05 | 旧麻布   | `#B08A5A` | 杂兵衣物       |
| WB06 | 暖纸色   | `#D1B982` | 宣纸暖光       |
| GB01 | 墨蓝灰   | `#18222A` | 冷阴影、夜色边缘   |
| GB02 | 石青灰   | `#263844` | 石头暗部       |
| GB03 | 雾蓝灰   | `#3B5360` | 远山、空气透视    |
| GB04 | 青钢灰   | `#5E7680` | 武器冷光       |
| GB05 | 浅雾灰   | `#8FA4A8` | 远景雾层       |
| GB06 | 宣纸灰   | `#C3C9BE` | 中性过渡       |
| AC01 | 朱砂红   | `#B93A2E` | 受击点、少量血色   |
| AC02 | 暗金    | `#C49A3A` | 精英敌人掌印、金属边 |
| AC03 | 青白气劲  | `#A8E6D2` | 内力、技能高光    |
| AC04 | 墨黑    | `#030504` | 轮廓线、最深墨点   |


使用限制：

- 单张角色图最多使用 18-24 色；VFX 最多使用 10-14 色；场景层最多使用 24-32 色。
- `AC01`、`AC02`、`AC03` 是强调色，总面积建议 < 8%；否则会抢掉战斗判读焦点。
- 轮廓线使用 `AC04` 或 `DG01`，不要使用纯黑 `#000000`，避免和水墨风格脱节。

## 4. GPT Image-2 通用 Prompt 模板

### 4.1 基础结构

每次生成都使用「目标 + 风格约束 + 结构约束 + 色板约束 + 输出约束 + 排除项」。

```text
Create [ASSET_TARGET] for a 2D side-scrolling wuxia action game.

Visual style:
Chinese ink-wash painting mixed with readable hand-painted game sprites, rice-paper texture, controlled brush edges, elegant but combat-readable silhouettes, subtle ink bleeding only outside key joints, no photorealism.

Palette:
Use a strict 32-color palette inspired by dark bamboo greens, mid bamboo greens, light mist greens, warm browns, grey-blues, and three accent colors: cinnabar red, muted gold, pale cyan qi. Avoid saturated neon colors. Use off-black ink instead of pure black.

Production constraints:
[STRUCTURE_CONSTRAINTS]

Output:
[OUTPUT_FORMAT], clean transparent background where applicable, no text, no watermark, no UI, no frame border.

Negative prompt:
photorealistic, anime glossy skin, 3D render look, cyberpunk, western medieval armor, modern clothing, excessive blood, unreadable silhouette, noisy over-detailing, extra limbs, distorted hands, fused weapon, cropped feet, heavy bloom, pure black outlines, saturated neon palette, text, logo, watermark.
```

### 4.2 Style Bible 锚点 Prompt

目标：先生成 20 张候选，人工选 3-5 张作为 Style Bible 锚点。锚点不追求一次产出可用资产，而是锁定线条、色温、墨色边界和战斗可读性。

```text
Create a Style Bible reference image for a 2D side-scrolling wuxia action game set in a misty bamboo forest.

Scene and mood:
early morning bamboo grove, layered mist, wet stone path, fallen bamboo leaves, distant mountain silhouettes, quiet Jianghu atmosphere before combat, readable horizontal gameplay space.

Style:
Chinese ink-wash painting, visible rice-paper grain, dry-brush bamboo texture, soft ink diffusion in background only, crisp brush contour for gameplay objects, hand-painted 2D game concept art, restrained cinematic lighting.

Palette:
strict 32-color palette: deep ink greens, bamboo mid greens, pale mist greens, warm bark browns, grey-blue distant shadows, tiny cinnabar red accent, muted gold accent, pale cyan qi accent. Low saturation, no neon, no pure black.

Composition:
16:9 horizontal composition, side-scrolling camera, foreground leaves framing the bottom and sides, midground walkable path clearly visible, background bamboo silhouettes separated by atmospheric perspective, leave 35% central horizontal space visually readable for combat.

Output:
single concept image, 1920x1080, no characters, no UI, no text, no watermark.

Negative prompt:
photorealistic, 3D render, modern buildings, Japanese torii, sci-fi, high fantasy castle, colorful flowers dominating image, overexposed fog, low contrast gameplay path, text, watermark.
```

Style Bible 最少交付：


| 交付物      | 数量       | 验收               |
| -------- | -------- | ---------------- |
| 场景锚点图    | 3-5 张    | 色温一致，战斗区域可读      |
| 角色风格锚点   | 2-3 张    | 剪影可区分，关节清楚       |
| VFX 风格锚点 | 2-3 张    | 水墨扩散形状统一，α 不遮挡动作 |
| 色板映射结果   | 每类至少 1 张 | ΔE 均值 < 8        |


## 5. 翠竹林场景概念与分层

### 5.1 场景总概念 Prompt

```text
Create a production concept for Bamboo Forest, the first combat stage in a 2D side-scrolling wuxia action game.

Environment:
a dense bamboo forest after light rain, mossy stone path, broken bamboo fence, scattered leaves, thin mist, distant grey-blue mountains, old Jianghu travel road. The scene should support fast melee combat and dodge movement.

Style:
Chinese ink-wash with hand-painted game readability, dry-brush bamboo trunks, soft background ink wash, crisp playable silhouettes, rice-paper grain, restrained contrast.

Palette:
use the 32-color palette: dark bamboo greens for shadows, mid greens for bamboo trunks and leaves, light mist greens for atmospheric depth, warm browns for soil/wood/leaves, grey-blues for distant mountain and wet stone, minimal cinnabar/gold/cyan accents.

Composition:
side-scrolling 16:9 frame, walkable path in the lower middle, clear combat lane, no large object blocking character silhouettes, foreground/midground/background separable into parallax layers.

Output:
1920x1080 concept image, no characters, no UI, no text, no watermark.
```

### 5.2 三层视差结构


| 层级              | 建议倍率      | 内容               | 可读性要求             | 目标尺寸          |
| --------------- | --------- | ---------------- | ----------------- | ------------- |
| 远景 `background` | 0.35-0.45 | 雾、远山、竹林大轮廓、天光    | 低对比，不抢角色轮廓        | ≥ `2304x1296` |
| 中景 `midground`  | 0.70-0.85 | 可行走地面、主要竹干、石路、断篱 | 战斗判读核心，碰撞参考来自此层   | ≥ `2304x1296` |
| 前景 `foreground` | 1.10-1.25 | 近处竹叶、暗草、局部枝干     | 只压画面边缘，不遮挡角色胸口到武器 | ≥ `2304x1296` |


视差层生成时，必须分别出透明 PNG。中景可为不透明底图；远景和前景建议透明或半透明边缘，便于 Godot 组装。

### 5.3 远景层 Prompt

```text
Create the BACKGROUND parallax layer for Bamboo Forest in a 2D side-scrolling wuxia action game.

Layer content:
distant bamboo silhouettes, grey-blue mountain shapes, pale morning mist, soft ink-wash sky glow, no playable ground details.

Style and palette:
Chinese ink-wash, soft diffusion, low contrast, 32-color palette limited to light mist greens, grey-blues, and dark desaturated greens.

Production constraints:
horizontal tile-friendly image, no hard vertical seam, no characters, no UI, no text. Keep detail low so combat sprites remain readable.

Output:
transparent PNG if possible, 2304x1296 or larger, safe for parallax speed 0.35-0.45.
```

### 5.4 中景层 Prompt

```text
Create the MIDGROUND gameplay layer for Bamboo Forest in a 2D side-scrolling wuxia action game.

Layer content:
walkable mossy stone path, main bamboo trunks, broken bamboo fence, scattered leaves, small rocks, readable ground contact shadows. This layer defines the combat lane and collision reference.

Style and palette:
Chinese ink-wash hand-painted game art, crisp brush edges on walkable objects, 32-color palette using mid bamboo greens, warm browns, grey-blue wet stones, controlled dark green shadows.

Production constraints:
side-scrolling horizontal layout, central combat lane clear for characters, avoid tall foreground blockers, tile-friendly left and right edges, no characters, no UI, no text.

Output:
PNG, 2304x1296 or larger, no watermark.
```

### 5.5 前景层 Prompt

```text
Create the FOREGROUND parallax layer for Bamboo Forest in a 2D side-scrolling wuxia action game.

Layer content:
near bamboo leaves, dark grass silhouettes, partial bamboo stalks at extreme left and right edges, a few falling leaves. Leave the center combat lane mostly open.

Style and palette:
Chinese ink-wash, stronger dry-brush edges than background, dark bamboo greens and warm browns, small pale mist highlights, no saturated colors.

Production constraints:
transparent PNG, edge framing only, do not cover the center 60% of the image, no characters, no UI, no text, no watermark.

Output:
transparent PNG, 2304x1296 or larger, safe for parallax speed 1.10-1.25.
```

## 6. 主角：三视图与 5 个战斗姿态

### 6.1 角色方向

主角需要在 2D 横版战斗中快速读取，轮廓关键词是「轻装侠客、长剑、短衣摆、可见关节」。不要做成长袍大袖，原因是袖摆会遮挡手肘和武器轨迹，增加骨骼绑定和命中判读成本。

主角建议配置：


| 项目    | 标准                   |
| ----- | -------------------- |
| 单帧分辨率 | ≥ `512x512`          |
| 背景    | 透明 PNG               |
| 骨骼数   | 20-30 根              |
| 动画帧率  | 30fps                |
| 关键帧   | 约 26 张，包含待机、行走、普攻、受伤 |
| 武器    | 单手长剑，独立层优先           |


### 6.2 主角三视图 Prompt

```text
Create a three-view character sheet for the PLAYER character in a 2D side-scrolling wuxia action game.

Character:
young wandering swordsman, agile build, readable athletic silhouette, simple dark green and warm brown travel outfit, short layered robe panels, cloth belt, wrist wraps, light boots, single straight sword. Calm but ready for combat.

Views:
front view, side view facing right, back view. All three views must share identical proportions, costume details, sword length, hair shape, and color placement.

Style:
Chinese ink-wash hand-painted game sprite concept, crisp joints for rigging, controlled brush texture, rice-paper grain feel without dirty noise, clean readable silhouette.

Palette:
strict 32-color palette: dark bamboo greens for cloth shadow, mid greens for outer cloth, warm browns for belt/boots, grey-blue sword, tiny pale cyan qi accent only on sword guard or tassel.

Production constraints:
neutral A-pose or relaxed rigging pose, arms slightly away from body, legs separated, weapon visible and not fused with body, no long sleeves hiding elbows, no oversized hair hiding neck, no dramatic perspective.

Output:
transparent PNG, 1024x1024 sheet containing three aligned full-body views, no text, no labels, no watermark.

Negative prompt:
front-back mismatch, different costumes between views, chibi proportions, photorealistic, glossy anime, huge shoulder armor, robe covering feet, hidden hands, fused sword, cropped head or feet.
```

### 6.3 主角 5 个战斗姿态


| 姿态      | 文件建议                                    | 用途          | 姿态要求            |
| ------- | --------------------------------------- | ----------- | --------------- |
| 待机      | `p2_char_player_idle_pose_v01_512.png`  | idle 循环关键姿态 | 重心低，剑尖斜下，呼吸空间明确 |
| 普攻 1 起手 | `p2_char_player_atk01_pose_v01_512.png` | 第一段横斩       | 肩、肘、剑身方向清楚      |
| 普攻 2 起手 | `p2_char_player_atk02_pose_v01_512.png` | 第二段反手斩      | 剪影和 atk01 区分明显  |
| 普攻 3 起手 | `p2_char_player_atk03_pose_v01_512.png` | 第三段突刺       | 剑尖方向水平，命中距离可读   |
| 普攻 4 起手 | `p2_char_player_atk04_pose_v01_512.png` | 第四段重击       | 更大蓄力弧线，但不遮挡身体   |


### 6.4 主角姿态 Prompt

```text
Create five combat pose keyframes for the PLAYER character from the approved three-view sheet.

Character consistency:
same wandering swordsman design, same costume, same sword, same proportions, same palette placement as the reference sheet.

Required poses:
1. idle ready stance, low center of gravity, sword angled downward.
2. attack 01 windup, compact horizontal slash preparation.
3. attack 02 windup, reverse slash preparation, clearly different silhouette from attack 01.
4. attack 03 windup, forward thrust preparation, sword aligned toward the right.
5. attack 04 windup, heavier finishing strike preparation with a larger arc.

Style:
Chinese ink-wash hand-painted 2D game sprite, crisp limb separation, readable joints for 2D bone rigging, controlled brush edges, no excessive cloth blur.

Palette:
strict 32-color palette, same colors as the three-view sheet, pale cyan qi accent only as a tiny sword edge highlight.

Production constraints:
side view facing right, full body visible, feet on the same ground baseline, transparent background, no motion smear that hides joints, no text, no labels.

Output:
one transparent PNG sheet, 2048x1024, five equally spaced full-body poses, no watermark.
```

## 7. 敌人 A：山匪杂兵 Character Sheet

### 7.1 角色定位

敌人 A 是高频出现的基础敌人。第一性原则是低复杂度、高辨识度、低骨骼成本。它不应该比主角更华丽，否则会污染战斗焦点。


| 项目    | 标准                   |
| ----- | -------------------- |
| 单帧分辨率 | ≥ `256x256`          |
| 背景    | 透明 PNG               |
| 骨骼数   | 10-18 根              |
| 动画帧率  | 30fps                |
| 体型    | 略矮或略宽，和主角剪影不同        |
| 武器    | 短刀、木棍或朴刀，推荐短刀以降低动画遮挡 |
| 色彩    | 暖棕 + 暗绿，避免使用青白气劲     |


### 7.2 敌人 A Prompt

```text
Create a character sheet for ENEMY A, a common bandit mob, for a 2D side-scrolling wuxia action game.

Character:
low-level mountain bandit, rough cloth outfit, short jacket, patched trousers, rope belt, cloth headband, simple short saber, slightly hunched aggressive posture, rugged but not heroic.

Sheet content:
front view, side view facing left, back view, idle pose, walk key pose, attack windup, hurt pose, death/fall pose. Keep all poses consistent in costume, body shape, weapon size, and palette.

Style:
Chinese ink-wash hand-painted game sprite, readable silhouette, simplified details for repeated mob use, crisp joints for 10-18 bone rigging, no luxury armor.

Palette:
strict 32-color palette: warm browns for cloth and belt, dark greens for shadows, grey-blue for blade, tiny cinnabar red only on headband or small patch. Do not use pale cyan qi.

Production constraints:
transparent background, full body visible, feet aligned to baseline for each pose, weapon not fused with body, hands visible, no long sleeves covering elbows.

Output:
transparent PNG character sheet, 1024x1024, no text, no labels, no watermark.

Negative prompt:
heroic protagonist look, ornate armor, elite martial aura, glowing qi effects, photorealism, anime gloss, hidden feet, unreadable weapon, extra fingers, text, watermark.
```

### 7.3 敌人 A 动画最小集


| 动画     | 最低帧数 | 说明                 |
| ------ | ---- | ------------------ |
| idle   | 4    | 呼吸或小幅晃动，不要大幅摆手     |
| walk   | 8    | 4 方向 × 2 关键姿态，避免滑步 |
| attack | 3    | 起手、命中、收招；命中帧有小爆发   |
| hurt   | 2    | 身体后仰，剪影区别于 idle    |
| death  | 4    | 可用骨骼动画插值完成         |


## 8. 敌人 B：铁掌精英 Character Sheet

### 8.1 角色定位

敌人 B 是精英型铁掌武者，功能是给玩家提供「更强、更硬、攻击范围更危险」的视觉预期。它必须明显区别于山匪，但不能像 Boss 一样过度复杂。


| 项目    | 标准                       |
| ----- | ------------------------ |
| 单帧分辨率 | ≥ `256x256`，推荐 `384x384` |
| 背景    | 透明 PNG                   |
| 骨骼数   | 14-18 根                  |
| 动画帧率  | 30fps                    |
| 体型    | 更宽肩、更低重心、双掌开阔            |
| 武器    | 徒手铁掌，掌部可有暗金/朱砂强调         |
| 色彩    | 暗绿 + 灰蓝 + 暗金，强调手掌        |


### 8.2 敌人 B Prompt

```text
Create a character sheet for ENEMY B, an elite Iron Palm fighter, for a 2D side-scrolling wuxia action game.

Character:
elite martial artist from the Iron Palm sect, broad shoulders, grounded stance, sleeveless or short-sleeved martial outfit, forearm wraps, iron palm training marks, stern expression, no weapon, dangerous open-hand striking silhouette.

Sheet content:
front view, side view facing left, back view, idle stance, forward step key pose, palm strike windup, palm strike impact pose, hurt pose, stagger pose. Keep proportions and costume identical across all poses.

Style:
Chinese ink-wash hand-painted game sprite, stronger angular silhouette than the bandit mob, crisp shoulder/elbow/wrist separation for 14-18 bone rigging, readable hands, restrained elite detail.

Palette:
strict 32-color palette: dark bamboo greens and grey-blues for outfit, warm browns for wraps, muted gold on palm guards or trim, tiny cinnabar red on palm strike mark. Pale cyan qi is allowed only as a faint rim on impact pose.

Production constraints:
transparent background, full body visible, feet aligned to baseline, hands large enough to read but anatomically plausible, no armor bulk blocking elbow movement, no excessive aura covering body.

Output:
transparent PNG character sheet, 1024x1024, no text, no labels, no watermark.

Negative prompt:
boss-sized monster, metal plate armor, weapon, magical fire, superhero pose, photorealistic skin, glossy anime, hidden hands, extra fingers, unreadable palms, text, watermark.
```

### 8.3 敌人 B 动画最小集


| 动画          | 最低帧数 | 说明                  |
| ----------- | ---- | ------------------- |
| idle        | 4    | 稳定马步，肩部轻微起伏         |
| walk/step   | 8    | 步幅短而重，重心低           |
| palm_attack | 3-5  | 起手、蓄力、命中、收掌；命中帧手掌最大 |
| hurt        | 2    | 上身偏转但不失去精英稳定感       |
| stagger     | 3    | 破防或被强击时使用           |
| death       | 4    | 体型较重，落地动作慢于杂兵       |


## 9. 水墨 VFX 序列帧

### 9.1 通用 VFX 要求


| 项目    | 标准                                          |
| ----- | ------------------------------------------- |
| 单帧分辨率 | ≥ `128x128`，推荐命中特效 `256x256`，技能爆发 `512x512` |
| 帧数    | 6-12 帧；本文命中火花固定 8 帧，技能爆发固定 12 帧             |
| 背景    | 透明 PNG                                      |
| 透明度   | 整体 α ≤ 80%                                  |
| 粒子数   | 同屏 ≤ 200，移动端 ≤ 100                          |
| 动画帧率  | 30fps                                       |
| 可读性   | 第 1-3 帧体现爆发，第 4 帧后快速衰减                      |


### 9.2 8 帧命中火花 Prompt

```text
Create an 8-frame sprite sheet for a wuxia ink-wash HIT SPARK effect.

Effect:
short melee hit impact, ink splash mixed with pale cyan qi streaks and tiny cinnabar impact dots, dry-brush radial burst, fast decay, readable on top of dark green bamboo forest background.

Frame progression:
frame 1 small contact point,
frame 2 sharp radial burst,
frame 3 largest ink splash and qi streaks,
frame 4 broken brush fragments,
frame 5 fading ink droplets,
frame 6 shrinking mist,
frame 7 faint residual brush marks,
frame 8 almost transparent dissipating particles.

Style:
Chinese ink-wash VFX, hand-painted sprite sheet, controlled transparency, no fire, no lightning, no photorealism.

Palette:
use 32-color palette only: off-black ink, pale cyan qi accent, tiny cinnabar red impact dots, light mist green fade. Overall alpha must not visually exceed 80%.

Production constraints:
transparent background, centered effect, consistent anchor point across frames, no text, no frame borders, no watermark.

Output:
horizontal 8-frame transparent PNG sprite sheet, each frame 256x256, total 2048x256.
```

文件拆分后命名：

```text
assets/vfx/p2_vfx_hit_spark_f001_256.png
assets/vfx/p2_vfx_hit_spark_f002_256.png
...
assets/vfx/p2_vfx_hit_spark_f008_256.png
```

### 9.3 12 帧技能爆发 Prompt

```text
Create a 12-frame sprite sheet for a wuxia ink-wash SKILL BURST effect.

Effect:
a circular internal-energy burst for a sword skill, ink ring expands outward, pale cyan qi arcs spiral through the ink, bamboo-leaf-shaped brush fragments, strong but transparent center so the character remains readable.

Frame progression:
frame 1 compressed qi dot,
frame 2 ink ring begins,
frame 3 radial brush burst,
frame 4 first large expansion,
frame 5 largest bright cyan qi arc,
frame 6 widest ink circle,
frame 7 ring breaks into brush fragments,
frame 8 fragments drift outward,
frame 9 energy fades,
frame 10 only pale mist remains,
frame 11 residual ink specks,
frame 12 almost transparent end frame.

Style:
Chinese ink-wash hand-painted VFX sprite, dry-brush edges, rice-paper diffusion, game-readable alpha, no heavy bloom.

Palette:
32-color palette only: off-black ink, dark green shadow tint, pale cyan qi accent, light mist green fade, no neon blue, no pure white core.

Production constraints:
transparent background, centered anchor, consistent scale progression, leave center partly transparent in frames 4-7, no text, no border, no watermark.

Output:
horizontal 12-frame transparent PNG sprite sheet, each frame 512x512, total 6144x512.
```

文件拆分后命名：

```text
assets/vfx/p2_vfx_skill_burst_f001_512.png
assets/vfx/p2_vfx_skill_burst_f002_512.png
...
assets/vfx/p2_vfx_skill_burst_f012_512.png
```

## 10. HappyHouse 工作流参考

HappyHouse 在 Phase 2 中只做两类事：把 GPT Image-2 的概念图变成多角度/分层生产参考，以及输出便于 Godot 处理的干净 PNG。不要把 HappyHouse 当作最终验收工具；最终验收以 Godot、脚本和逐帧截图为准。

### 10.1 角色工作流

1. 输入 GPT Image-2 三视图或角色 sheet。
2. 锁定主视角：玩家默认面向右；敌人默认面向左。
3. 生成补充角度：正面、背面、侧面、3/4 角仅作为绑定参考，实际 Phase 2 使用侧面为主。
4. 拆分部件：头、躯干、上臂、前臂、手、上腿、小腿、脚、武器、衣摆。
5. 清理背景：导出透明 PNG，检查 alpha 是否为 1-bit 边界或可被脚本二值化。
6. 输出关键姿态：idle、walk、attack、hurt、death/stagger。
7. 导入 Godot Skeleton2D：主角 20-30 根骨骼，敌人 10-18 根骨骼。
8. 在 Godot 中用 30fps AnimationPlayer 检查插值，有撕裂就回到拆分层修正。

### 10.2 场景工作流

1. 输入翠竹林总概念图。
2. 分解为 `background`、`midground`、`foreground` 三层。
3. 为每层生成可横向拼接版本，左右边缘 4px 内不能有明显接缝。
4. 中景层额外导出碰撞参考图，标记地面、台阶、不可通行物。
5. 如需 3D 低模元素，单物件 ≤ 500 tris，场景总 ≤ 8000 tris。
6. Godot 组装 ParallaxBackground，倍率按 0.35-0.45、0.70-0.85、1.10-1.25 起步。
7. 截图对比 Style Bible，色温偏差必须 < 500K。

### 10.3 VFX 工作流

1. 输入整张 sprite sheet。
2. 按固定尺寸切帧：命中火花 `256x256` × 8，技能爆发 `512x512` × 12。
3. 检查锚点：每帧视觉中心偏差建议 < 4px。
4. 压缩色板：保留 10-14 个主要颜色，避免渐变噪声。
5. 导入 Godot SpriteFrames 或 AnimatedSprite2D，播放帧率 30fps。
6. 在深色竹林和浅色雾层背景上各测试 1 次，确认 α ≤ 80% 且不遮挡角色动作。

## 11. 质量标准与验收清单

### 11.1 角色资产


| 指标    | 硬性标准                              | 测量方式                   |
| ----- | --------------------------------- | ---------------------- |
| 分辨率   | 主角 ≥ `512x512`/帧；敌人 ≥ `256x256`/帧 | ImageMagick `identify` |
| 格式    | 透明 PNG，1-bit alpha 通道             | `pngcheck`             |
| 色板偏差  | 与 Style Bible 32 色板的 ΔE 均值 < 8    | CIELAB 脚本比对            |
| 骨骼数量  | 主角 20-30 根；敌人 10-18 根             | Godot Skeleton2D 节点计数  |
| 动画帧率  | 全部动画统一 30fps                      | Godot AnimationPlayer  |
| 待机动画  | ≥ 4 帧循环，无可见跳帧                     | 肉眼 + 逐帧截图              |
| 行走动画  | ≥ 8 帧，步幅与移动速度匹配                   | 位移/帧计算                 |
| 攻击动画  | 每段 ≥ 3 帧，起手/命中/收招明确               | 逐帧截图                   |
| 受伤动画  | ≥ 2 帧，和待机/攻击明显区分                  | A/B 对比                 |
| 剪影辨识度 | 灰度化模糊后仍能区分敌我                      | 脚本 + 肉眼确认              |


### 11.2 场景资产


| 指标      | 硬性标准                             | 测量方式                     |
| ------- | -------------------------------- | ------------------------ |
| 分层数     | ≥ 3 层，层间视差倍率差 ≥ 0.3              | Godot ParallaxBackground |
| 每层分辨率   | 不小于视口分辨率 × 1.2                   | ImageMagick `identify`   |
| 纹理尺寸    | 单张 ≤ `2048x2048`，总纹理内存 ≤ 16MB/场景 | Godot 资源面板               |
| 3D 模型面数 | 单物件 ≤ 500 tris，场景总 ≤ 8000 tris   | Godot 网格统计               |
| 无缝拼接    | 相邻图块边缘 4px 内无明显接缝                | 200% 截图检查                |
| 色温一致性   | 图层间色温偏差 < 500K                   | 5 点采样脚本                  |
| 碰撞体匹配   | 1080p 视口下视觉偏差 < 4px              | 碰撞可视化截图                  |


### 11.3 特效资产


| 指标   | 硬性标准                             | 测量方式                         |
| ---- | -------------------------------- | ---------------------------- |
| 帧数   | 每个特效 6-12 帧；本文命中火花 8 帧，技能爆发 12 帧 | 文件计数                         |
| 分辨率  | ≥ `128x128`/帧                    | ImageMagick `identify`       |
| 粒子数量 | 同屏 ≤ 200；移动端 ≤ 100               | CPUParticles2D amount        |
| 透明度  | 整体 α ≤ 80%                       | 截图采样                         |
| 播放帧率 | 30fps                            | SpriteFrames/AnimationPlayer |


### 11.4 Phase 2 最终验收


| 项目          | 通过条件                                        |
| ----------- | ------------------------------------------- |
| Style Bible | 3-5 张锚点图、Prompt 模板、32 色板齐全                  |
| 翠竹林         | 3 层 PNG 在 Godot 中正确视差堆叠                     |
| 主角          | 三视图 + 5 姿态 + 骨骼绑定，无明显撕裂                     |
| 敌人 A        | 行走、攻击、受伤、死亡动画完整                             |
| 敌人 B        | 可与敌人 A 同屏出现，剪影与战斗预期不同                       |
| VFX         | 8 帧命中火花 + 12 帧技能爆发可正常播放                     |
| 性能          | 浏览器战斗 60fps 桌面 / 30fps 移动，战斗 Draw call ≤ 50 |
| 资源体积        | 美术侧纹理总内存 < 64MB，关卡 `.pck` 4G 限速加载 < 3s      |


## 12. 常见问题与纠偏


| 问题        | 原因                   | 纠偏方式                                                                            |
| --------- | -------------------- | ------------------------------------------------------------------------------- |
| 图很好看但进游戏脏 | AI 细节和渐变太多，色板压缩后噪声明显 | Prompt 中增加 `simplified hand-painted game sprite, controlled brush edges`，减少高频纹理 |
| 主角攻击看不清   | 衣袖、墨迹、特效遮挡剑身         | 缩短袖摆，武器独立层，VFX 中心透明                                                             |
| 敌人和主角像同阵营 | 体型、重心、色块比例太接近        | 敌人 A 更矮宽、暖棕更多；敌人 B 更宽肩、掌部暗金                                                     |
| 视差层显得贴纸化  | 三层色温和透视不一致           | 远景降对比，中景保清晰，前景只压边缘                                                              |
| 骨骼动画撕裂    | 关节被水墨糊住或部件没拆干净       | HappyHouse 回退拆层，手肘/膝盖/武器交界必须清楚                                                  |
| 特效遮挡战斗    | α 过高、亮色面积过大          | 整体 α 降到 80% 以下，帧 4 后快速衰减                                                        |


## 13. 推荐执行顺序

1. 生成 20 张 Style Bible 场景候选，选 3-5 张锚点。
2. 固定 32 色板，做 1 次色板映射试验，确认 ΔE < 8。
3. 生成翠竹林总概念，再拆 `background`、`midground`、`foreground` 三层。
4. 生成主角三视图和 5 姿态，先验证骨骼绑定。
5. 生成敌人 A，再生成敌人 B，确保剪影差异。
6. 生成 8 帧命中火花和 12 帧技能爆发。
7. 全部资产导入 Godot，按 30fps 动画和 60fps 浏览器战斗进行验收。

