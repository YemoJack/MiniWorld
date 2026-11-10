# MiniWorld

一个低多边形漂浮岛建造沙盒。本地角色素材加载后，默认进入第三人称。WASD 行走，空格跳跃，拖动或用方向键调整镜头。点击「角色」切换岛屿总览，可拖动旋转、滚轮或双指缩放，并在正交和透视视角之间切换。

木地板、石纹地板和玻璃地板都可以站立。楼梯保留台阶外观，角色沿斜面行走，镜头平滑跟随高度变化。角色下落时如果脚陷入楼板，会在板面有足够空间时恢复站立。

首次打开时进入平坦空岛，之后恢复上次使用的岛屿。点击右上角岛名，可以新建空岛、切换到木屋岛，或回到其他已建岛屿。每座岛单独保存，原版摆放记录归入木屋岛。

进入「建造」后，镜头跟随无人机。WASD 移动，E 上升、Q 下降，拖动鼠标或按方向键转向。用屏幕中央的准星对准目标，点击场景或按回车选择、放置。触屏可以按住方向和升降按钮飞行，拖动场景转向，轻点确认。

建造高度由准星命中的表面决定。选中地板后瞄准半墙或整墙的上沿，地板会贴在墙顶并对齐大格。瞄准已铺地板的边缘可以向外接铺，瞄准板面可以继续搭墙或放家具。提灯、木箱和花盆等物件使用 5×5 子格，按模型尺寸检查碰撞和楼板支撑。瞄准楼梯顶端可沿出口接下一段，也可以旋转 180° 在原格上方折返。

选中物件后可移动、旋转或删除。移动时用准星对准新位置再确认。按 R 旋转，按 Esc 或点「取消」退出当前操作。确认的改动会自动保存到当前浏览器，点击「完成」返回浏览视角。

## 本地运行

需要 Node.js 20.19+（20.x）或 22.12+。

```sh
npm ci
npm run dev
```

开发地址固定为 [http://localhost:5173](http://localhost:5173)。如果端口已被占用，请使用已经打开的 MiniWorld，或关闭占用该端口的服务后重试。浏览器按网址保存岛屿，`localhost` 和 `127.0.0.1` 也各有独立存档。

`npm run build` 生成 `dist/`。

本地开发会从 `local-assets/models/` 加载已登记的 Synty 模型，包括角色、凉亭、木围栏、桌椅和景观摆设。模型与共享贴图保存在 `local-assets/`，该目录由 Git 忽略，并且位于生产构建的静态资源目录之外。

可以把 Mixamo 动作重定向到当前角色骨骼，再将 `Idle`、`Walk`、`Jump` 三段动画和角色一起导出到 `local-assets/models/player.glb`。走路和跳跃动作使用原地版本，由游戏控制位移。模型缺少任一片段时，会使用内置的骨骼动画。

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
