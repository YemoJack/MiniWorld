# MiniWorld

一个低多边形漂浮岛建造沙盒。拖动可以绕岛旋转和调整俯仰，滚轮或双指缩放。点击右上角「透视」可在正交和透视视角之间切换。

默认进入平坦空岛。点击右上角岛名，可以新建空岛、切换到木屋岛，或回到其他已建岛屿。每座岛单独保存，原版摆放记录归入木屋岛。

进入「建造」后，从底部按分类浏览带缩略图的物件。点格子直接放置，可连续摆放同款。木地板可承托物件，墙壁、门洞和窗墙沿网格边缘放置。

点击已有物件可选中，青色描边和占地高亮会标出当前物件，即使物件摆在木地板上，高亮也能稳定显示。选中后可移动、旋转或删除，也可直接把物件拖到新格。拖动空地可以转动镜头。按 R 旋转，按 Esc 或点「取消」退出当前操作。点击「完成」时，已确认的编辑会保存到当前浏览器。

## 本地运行

需要 Node.js 20.19+（20.x）或 22.12+。

```sh
npm ci
npm run dev
```

`npm run build` 生成 `dist/`。

本地开发会读取 `local-assets/models/` 里的 Synty 长椅、种植箱和咖啡台。模型与共享贴图保存在 `local-assets/`，该目录由 Git 忽略，并且位于生产构建的静态资源目录之外。

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
