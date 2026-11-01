# 杠速 BarSpeed

摄像头测杠铃速度 + LVP 分析 + 纵跳测量的 iOS 应用。SwiftUI 原生，iOS 17+，全部数据留在本机。

## 目录

```
barspeed/
├─ project.yml                 # XcodeGen 工程描述
├─ BarSpeed/
│  ├─ App/BarSpeedApp.swift    # 入口
│  ├─ Core/                    # 数据模型、速度数学、本地存储
│  ├─ Capture/                 # 相机、杠铃跟踪、纵跳识别、语音
│  ├─ Billing/PurchaseManager  # StoreKit 2
│  ├─ UI/                      # 五个页面 + 主题
│  └─ PrivacyInfo.xcprivacy    # 隐私清单
```

## 构建

需要 macOS + Xcode 15 以上（真机运行，模拟器没有相机）。

```bash
brew install xcodegen
cd barspeed
xcodegen generate
open BarSpeed.xcodeproj
```

1. TARGETS → BarSpeed → Signing & Capabilities，选你的 Team，把 Bundle Identifier 改成你自己的（例如 `com.yourname.barspeed`）。
2. 在 `project.yml` 里同步 `PRODUCT_BUNDLE_IDENTIFIER`，否则下次 `xcodegen generate` 会覆盖回去。
3. 插上 iPhone，⌘R。

## 内购配置（必须做，否则付费入口是空的）

App Store Connect → 你的 App → 订阅 / App 内购买项目，建三个商品，ID 必须与代码一致：

| 商品 ID | 类型 | 建议价 |
|---|---|---|
| com.barspeed.pro.monthly | 自动续期订阅（1 个月） | ¥12 |
| com.barspeed.pro.yearly | 自动续期订阅（1 年） | ¥68 |
| com.barspeed.pro.lifetime | 非消耗型 | ¥148 |

订阅要建一个「订阅组」，把月卡和年卡放进去（同一组内互斥升降级）。商品建好后还要提交审核信息、上传截图，状态变成「准备提交」后沙盒才能拉取到。

测试：Xcode → Scheme → Run → Options → StoreKit Configuration，指一个本地 `.storekit` 文件，可在不连 App Store 的情况下点通购买流程。或者用沙盒账号在真机测。

## 免费与付费边界

- 免费：无限次测速、7 天记录、`深蹲` 一个动作的 LVP
- 会员：全部动作 LVP / 1RM 预测 / 推荐负重 / 速度损失告警增强 / 长期趋势 / CSV 导出 / 纵跳看板

要改边界，改 `Core/AppStore.swift` 里的 `freeExercise`、`freeHistoryDays`、`canViewLVP(_:)`。

## 标定与方向（真机上第一个要调的东西）

见 `Capture/BarTracker.swift` 顶部注释。默认：

- `axis = .x`、`sign = -1`：竖屏 + 后置摄像头时，图像缓冲区是 1920×1080 横向，世界坐标「向上」对应图像 -x。
- 如果速度符号反了（往上推显示负数），把 `TrainSession.sign` 改成 `+1`；如果速度恒为 0 或跟踪乱跳，把 `axis` 改成 `.y`。

标定时点两次杠铃片的上沿和下沿（或左右沿，沿运动方向那一对），直径用于换算米/像素。

## 已知待办

- 视频叠加导出（目前只存数据，不导出视频）
- 用 Core ML 训练专用杠铃检测器替换 ZNCC 模板（低光下更稳）
- 训练组间休息计时器
- 云端同步（需要后端，见 `docs/定价与收费方案.md`）
