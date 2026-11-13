# MiniWorld

用 Godot 4 和 GDScript 制作的低多边形漂浮岛沙盒。可以新建或切换岛屿，用无人机搭建多层建筑，再切回第三人称在岛上探索。

## 运行

用 Godot 4.7 打开根目录的 `project.godot`。首次打开时等待 GLB 导入完成。主场景 `godot/main.tscn` 在编辑器里预览木屋岛和角色。按 **F5** 进入游戏后会加载当前存档的岛屿，可从右上角切换平坦岛、木屋岛和港口岛。

- **角色**：WASD 按镜头方向移动，A/D 侧移，S 后退，Shift + W 跑步，空格跳跃。鼠标转向，滚轮调整越肩镜头距离。按 Esc 释放鼠标操作菜单，点击场景恢复控制。触屏可拖动转向。
- **交互**：用准星对准附近的木门、板凳、长椅或咖啡椅，按 F 或点交互按钮。咖啡椅从正面使用，长椅会选择最近的可用坐点。角色直接到达坐点前方并播放坐下动作。再次交互站起时，镜头转到角色背后。
- **岛屿总览**：点「岛屿」进入总览，可环绕、缩放，并切换正交和透视。
- **建造**：点「建造」进入无人机视角。WASD 移动，E/Q 升降，拖动或按方向键转向。建造栏支持分类筛选和「最近」，点右上角「展开」可显示更多物件。从建造栏选择物件后对准位置，点右侧「放置」。没有待放置物件时，用准星对准已有物件即可选中，再点「旋转」「移动」或「删除」。移动后点「放置」确认，点「取消」放弃当前操作，点右下角「退出」离开建造模式。
- **多层建造**：对准楼板边缘、墙顶或楼梯出口接铺构件。墙体的厚度中心贴住格线，楼板以厚度中线为楼层高度。小物件用 5×5 子格定位，角色可沿楼梯斜坡上下楼。
- **新岛建造尺寸**：基础格边长约 0.927，整墙高 1.50，半墙高 0.75。按 1.68 米的角色换算，整墙约宽 1.854 米、高 3 米，宽高比为 1∶1.618。一面墙占一条格边，楼梯占两格进深。
- **木墙门窗**：选中木门、门洞或木窗后，瞄准已有木墙预览并放置。新岛还可安装宽木窗。选中带开口的墙后，点「拆门窗」恢复实墙。
- **分数墙高**：新尺寸岛屿的石矮墙是整墙的 1/3，三段可叠成一层。建造栏还提供 1/4、1/2 和 2/3 高的墙段。
- **拼接屋顶**：在「结构 → 屋顶」选同一比例的木坡片和木三角墙。比例表示跨一格时的垂直高差。对准楼板、墙顶或已有屋面，预览会按接缝自动匹配高度和坡向。按 R 或点「旋转」可以切换可用的摆放方向。
- **港口建造**：在「结构 → 码头」选码头平台或栈桥，从岸边或已有平台向水面接铺。切回角色后可以走过栈桥。
- **岛屿扩建**：在「设置 → 存档管理」选中当前岛屿，点「扩建岛屿」。岛屿从 14 × 10 米逐级扩建，最大 24 × 24 米。

## 存档

Godot 版会自动保存到 `user://islands.json`。在 macOS 上，默认路径是 `~/Library/Application Support/Godot/app_userdata/MiniWorld/islands.json`。

右上角岛屿菜单用于快速切换。「设置 → 存档管理」可以新建、重命名、导入、导出或删除岛屿存档。删除需要确认，至少保留一个存档。导出文件可再次导入。建造尺寸随岛屿保存，既有岛屿和旧版导入存档沿用原来的格宽与层高。

如需迁移网页版岛屿，在原 MiniWorld 页面所在地址的 Chrome 开发者工具控制台运行以下命令，将剪贴板内容保存为 `islands.json`。在 Godot 版「设置 → 存档管理」选择「导入…」。导入会新增岛屿，遇到相同 ID 时保留两份。

```js
copy(localStorage.getItem('miniworld.islands.v1'))
```

网页版的源码和运行入口可从 Git 提交 `3843576` 找回。

## 素材

以下低多边形 GLB 由 **Polyfork** 创作，以 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 使用。场景调整了模型的缩放、位置和方向。

- [Porch Log Cabin](https://polyfork.dev/asset/porch-log-cabin-d2f3ef)（屋顶改色）
- [Campground Pine Stand](https://polyfork.dev/asset/campground-pine-stand-0bf4f2)（树冠提亮）
- [Creek Footbridge](https://polyfork.dev/asset/creek-footbridge-d35cf7)
- [Lily Pads](https://polyfork.dev/asset/lily-pads-b0c5d0)
- [Lake Pebbles](https://polyfork.dev/asset/lake-pebbles-6c0359)
- [Flower Bed](https://polyfork.dev/asset/flower-bed-708e73)
- [Wooden Crate](https://polyfork.dev/asset/wooden-crate-e46521)
- [Farm Lantern](https://polyfork.dev/asset/farm-lantern-747dc8)

本地 Synty 模型和贴图放在 `local-assets/models/` 和 `local-assets/textures/`。主角场景位于 `local-assets/models/spy-player/`，使用 Spy Kit 特工和 Mixamo 的待机、行走、跳跃动作。建造模式从 `local-assets/models/spy-drone/` 加载 Spy Kit 无人机。缺少本地素材时，游戏使用内置角色、无人机和建材。

特工的座椅交互需要本地动画库 `local-assets/models/spy-player/seating.res`。它由 Mixamo 的坐下和起身动作转换到特工骨架。内置方块角色使用程序生成的坐姿和起身过渡。

特工的侧移、后退和跑步循环来自 Quaternius 的 [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) 和 [Universal Animation Library 2](https://quaternius.com/packs/universalanimationlibrary2.html)（CC0）。通过 [KinemIQ 动画库](https://kinemiq.app/studio/data/catalog.json)取得片段，转换为适配特工骨架的原地动画，保存在 `assets/animations/locomotion.res`。

`local-assets/` 由 Git 忽略。整包素材可放在 `local-assets/packs/`，并在该目录创建空的 `.gdignore`，让 Godot 跳过导入。
