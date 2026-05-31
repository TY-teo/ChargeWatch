# 充电上限机制调研与修复方案

> 调研日期：2026-06-01 ｜ 方法：多 Agent 并行调研 + 对抗式校验（11 agents）｜ 机型：Apple Silicon，macOS 26.4（Darwin 25.4）
> 触发背景：插电后电量在 90% 附近高频充放（循环 < 1 分钟），从未掉到 limit-deadband(87%) 再充；且“退出 App”后后台仍在限充。

## 一、用户两个问题的直接回答

### 问题 1：苹果系统是不是“慢慢掉到下限（如 87%）再接回上限（90%）”这种带缓冲的滞回？

**部分 yes，但要分清两套机制，且具体数字与“87%”不符。**

- **官方“充电上限（Charge Limit）”：是滞回，缓冲带固定 5%（不是按 deadband 算的 87%）。** Apple 官方文档原文：插电状态下电量“下跌超过 5%”才恢复充电，再充到“距上限几个百分点以内”就停（confirmed）。即设 90% 时约掉到 85% 以下才回充；设 80% 时约掉到 75% 以下才回充。停充点也不必精确等于上限，而是“within a few percentage points of the limit”。
- **官方“优化电池充电（OBC）”：不是滞回，而是“延迟充满”。** 端侧 ML 预测长时间插电时把充电暂停在 80%（显示 Charging On Hold），临到惯常拔线前才补满。官方**从未公布** OBC 在 80% 处的下限/滞回数字（confirmed）。
- **共性：两种机制都会偶尔充满到 100%** 以维持电量计（SoC）估算准确（confirmed）。

**结论：苹果的“充电上限”确实是带缓冲的滞回，缓冲带 = 固定 5%（绝对百分点，不随上限步进变化），靠大幅放电 5% 才回充一次、周期很长。chargewatch 当前“deadband=3、掉到 limit-3 再充”方向对，但实现有 bug，表现成了高频抖动——恰恰是苹果设计要规避的行为。**

### 问题 2：iPhone/Mac 官方怎么做、Mac 应借鉴什么？

- **iPhone（iOS 18，仅 15/16）：** 上限可设 80/85/90/95%（5% 步进），机制同 Mac——充到接近上限停充，**下滑超过 5% 才恢复**，偶尔充满校准（confirmed）。无真正电气旁路。
- **Mac（macOS 26.4+ 且 Apple 芯片）：** 原生“充电上限”可在 80–100% 间选，5% 滞回；到达上限后**仅用适配器供电、电池静止保持**（电气行为属社区描述；Apple 官方只写“减少满电停留时间以延寿”这一目的）。
- **chargewatch 应借鉴的三点：**
  1. **用 ≥5% 缓冲带替代单点死守**，避免上限点高频微充放。
  2. **优先“只停充电、保持适配器供电”语义**，而不是物理断开适配器（这正是当前 bug 的根源）。
  3. **配套定期满充校准**，防 SoC 漂移。

## 二、macOS 官方机制

来源：Apple 支持文档 102338《About Optimized Battery Charging and Charge Limit on Mac》<https://support.apple.com/en-us/102338>

| 机制 | 触发 | 维持点 | 滞回/恢复 | 要求 |
|---|---|---|---|---|
| 优化电池充电（OBC） | 自动，端侧 ML | 暂停 80%，临拔线前补满 | 官方未公布数字（confirmed） | 全机型 |
| 充电上限（Charge Limit） | 手动 80–100% | 充到“距上限几个百分点内”停 | **下跌超过 5% 才恢复**（官方明文，confirmed） | **macOS 26.4+ 且 Apple 芯片**（confirmed） |

关键官方原文（confirmed）：
- 滞回：“If the battery charge level drops more than 5% while connected to power, charging resumes, again charging to within a few percentage points of the limit.”
- 校准：“…your Mac will occasionally charge to 100% to maintain accurate battery state-of-charge estimates.”（两机制各出现一次）
- OBC 决策：端侧 ML 学习作息，“fully charged by the time it expects you to need a full charge.”

归因边界（社区/第三方，非官方原文）：“暂缓充电时适配器仍连、由适配器供电、电池静止不放电”这套电气机制属第三方 SMC 逆向；Apple 官方只确认“减少满电停留时间以延寿”这一目的。

**重要：本机（Apple Silicon + macOS 26.4）已满足原生“充电上限”的硬件/系统要求，可在系统设置里直接用 80–100% 的原生上限——它正确实现了 5% 滞回、不断开适配器、不放电。**

## 三、iOS/iPhone 官方机制

来源：Apple 支持文档 108055 <https://support.apple.com/en-us/108055>

- OBC：“delay charging past 80 percent in certain situations”，端侧 ML，约 14 天学习；是“延迟充满”，不是上限点反复微充放（confirmed）。
- 充电上限（iOS 18，仅 15/16）：80/85/90/95%（confirmed）；“…drops more than 5 percent while connected to power, charging will resume…”——明确 5% 缓冲带（confirmed）；设 <100% 时偶尔充满校准（confirmed）。
- 无官方旁路/直供：满电后充电 IC 停充、外部供电、自然回落约 5% 再补，社区称“伪旁路”（推测，medium）。

对 Mac 的启示：iOS 官方范式 = **5% 缓冲带滞回 + 偶尔满充校准**，正是 chargewatch 应对齐的目标。

## 四、Apple Silicon 充电限制工程实现对比

> 以下 SMC 键名/阈值均来自开源项目源码逆向，**非 Apple 官方公开**，已逐一核实。

### 4.1 两类完全不同的操作

| 操作语义 | 物理效果 | ExternalConnected | 涉及键 |
|---|---|---|---|
| **停充电（charge-disable）** | 适配器仍连、墙电供电、电池静止 | **保持 Yes** | batt: `CH0B`/`CH0C`（旧固件）、`CHTE`（新固件）；Battery-Toolkit: `CHTE`/`CH0C` |
| **强制放电（关适配器）** | 真正切断适配器、电池放电 | **变 No** | batt: `CH0I`/`CH0J`/`CHIE`；Battery-Toolkit: `CHIE`/`CH0J` |

- **关键工程教训：日常维持上限只用 charge-disable，绝不强制放电。** batt 日常仅 DisableCharging/EnableCharging，DisableAdapter 只在校准放电时用（confirmed）。
- chargewatch 当前用的是 **CHIE=0x08（强制放电/关适配器）**——会让电池真实放电、ExternalConnected 变 No，是问题根源。

来源：batt `pkg/smc/charging.go`、`pkg/smc/adapter.go`、`pkg/daemon/loop.go`；Battery-Toolkit `SMCComm+Power.swift`。

### 4.2 如何识别“真实拔插”（直接关系本 bug）

- batt 用 **`AC-W`** 键检测物理适配器是否在位（int8 > 0 = 插着；VirtualSMC 文档：AC-W = “active AC port index”，confirmed）。
- **不要用 `ExternalConnected` 当“墙插是否插着”的真值**：一旦用关适配器（CHIE）限充，它会被自己的动作反映为 false——这就是 chargewatch 振荡的根因。应改读不受充电控制影响的物理在位信号（`AC-W`，或 IORegistry `AdapterDetails` 非空 / `Watts>0`）。

来源：batt `pkg/smc/acpower.go`。

### 4.3 滞回参数实测

| 项目 | 下限/缓冲带 | 轮询 |
|---|---|---|
| batt | 上限 − 2%（可调） | 10s |
| AlDente Sailing Mode | 5–10% | — |
| BatteryOptimizer | 上限 − 5（默认） | — |
| Battery-Toolkit | 仅低于下限才充，安全下限 ≥20% | — |
| **Apple 官方** | **固定 5%** | — |

### 4.4 纠正（refuted）

- **“强制放电用 ACEN”——证伪**：三个被引用项目源码均无 ACEN 键（batt 用 `CH0K`，actuallymentor 用 `CH0I`）；ACEN 仅见于搜索引擎生成式摘要，无源码/官方支撑。
- **CH0B/CH0C 是停充键，CH0I 是关适配器键，不可并列。**
- **CHWA 属实（confirmed）**：Apple 芯片用 CHWA 持久化上限，仅 80/100、需固件 ≥13.0；Intel 用 BCLM。

## 五、chargewatch 当前实现的根因（源码逐行核实，confirmed）

### 5.1 振荡反馈环

**根因：用“物理断开适配器（CHIE=0x08）”限充，却用 `ExternalConnected` 判断“是否接电”——控制输出污染了控制输入，形成负反馈环。**

文件 `Sources/ChargeWatchHelper/main.swift`，逐轮追踪（limit=90, deadband=3 → upper=90, lower=87）：

1. 第 N 轮：external=true、SoC=90≥upper 且 !inhibiting → `main.swift:121-122` 写 `CHIE_OFF`，inhibiting=true，适配器断开、电池放电。
2. 第 N+1 轮（10s 后）：适配器已断 → `main.swift:71` 读 `ExternalConnected=false` → `main.swift:113` 守卫 `!cfg.enabled || !bat.external || cfg.limit >= 100` 被 `!bat.external` 命中。
3. 进入 `main.swift:115` `if inhibiting || !cfg.enabled { allowCharging(); inhibiting = false }`：因 inhibiting==true，写回 `CHIE=0x00`、inhibiting 复位，适配器重新接通。
4. 此时 SoC 仍约 89~90%（只放电了一个 10s 周期，远未到 87%）。
5. external 又变 true、SoC≥90 → 回到第 1 步。

**为什么永远掉不到 lower(87)：** 真正“放电到 lower 再恢复”的分支是 `main.swift:123`，但要进到 `119-128` 的滞回逻辑必须先过 `main.swift:113` 守卫（要求 external==true）；可一旦 inhibiting 生效 external 立刻 false，控制权被 `113-117` 抢走，在仅掉 1% 时就 allowCharging 并清 inhibiting。滞回区间形同虚设，`125-127` 的“维持禁充”分支也永远进不去。

证据行号：`main.swift:71,90-91,113,115,119-129`。

### 5.2 “退出 App”不彻底

点菜单栏“退出”只关 GUI 进程，**不停守护进程、不写回 CHIE、不改 enabled**，后台仍按上限断充。

- 退出按钮 `MenuBarPanel.swift:188` → `StatusBarController.swift:36` `NSApp.terminate(nil)`。
- `ChargeWatchApp.swift:48-50` `applicationWillTerminate` 只调 `container.stop()`；`AppContainer.swift:44-47` 仅停采样。
- 三个“否”：① 不卸载 LaunchDaemon（`RunAtLoad`+`KeepAlive`，独立 system 域）；② 不写回 CHIE（GUI 不持有 SMC，helper 的 fail-safe 只对自身退出生效，`NSApp.terminate` 不给 helper 发信号）；③ 不改 enabled（`readConfig` 下一轮仍读到 true）。

## 六、推荐修复方案

### 6.1 振荡修复

根本矛盾：“用关适配器（CHIE）限充”与“用 ExternalConnected 判断接电”互相污染。

- **方案 1（最小改动，必做）：** 修改 `main.swift:113` 守卫，inhibiting 时不被自造的 `ExternalConnected=false` 误导——只有 enabled 变 false、limit≥100、或确认 SoC≤lower 时才写回 CHIE_ON，让 inhibiting 期间继续走 `119-128` 滞回，真正放电到 lower 再恢复。
- **方案 2（强烈建议，配合 1）：** 改读独立的物理适配器在位信号（SMC `AC-W`，或 IORegistry `AdapterDetails` 非空 / `Watts>0`）判断“用户是否真插着电”，不再用 `ExternalConnected` 当真值。需在本机 `--dump`（`DumpCommand.swift`）实测确认 CHIE=0x08 时哪个键仍稳定反映物理在位。
- **方案 3（治本，可选）：** 若本机存在 charge-disable 键（`CH0B`/`CH0C`/`CHTE`）可“停充但保持适配器供电”，改用它替代 CHIE=0x08，反馈环从物理上消失。注：`main.swift:3` 注释称本机 M5 实测这些键不可用/惰性，**需重新实测确认**。
- **deadband 调整：** 默认 3 偏小，建议 ≥5%，对齐 Apple 官方 5% 滞回，拉长充放周期、减少微循环。

### 6.2 “退出 App”彻底关闭

- **A（推荐）：** `ChargeWatchApp.swift:48` `applicationWillTerminate` 内，在 `container.stop()` 之外写 `smc-limit.json` 的 `enabled=false`（复用 `SMCChargeLimiter.disable()`，无需 root/密码），helper 下一轮恢复充电；如需立即恢复可同时给 helper 发 SIGTERM。用 `applicationShouldTerminate` 返回 `.terminateLater` 保证写盘落地。是否连带 launchctl 卸载守护进程做成可选项，**默认仅“停用上限+恢复充电”**，避免每次退出弹密码。
- **B（配合）：** UI 拆成“暂停充电上限”（disable，无密码、立即恢复、保留守护进程）与“退出 App”（关 GUI）两个明确入口。当前 `MenuBarPanel.swift:188` 只有一个“退出”，语义混淆。

### 6.3 借鉴苹果策略

1. 大滞回、低频充放（≥5% 缓冲带）。
2. 限充期间保持适配器供电、电池静止（优先 charge-disable）。
3. 定期满充校准防 SoC 漂移。
4. 避免微充放（Battery-Toolkit 明确“short charging bursts can further deteriorate batteries”）。

### 6.4 战略性替代：直接用 macOS 26.4 原生充电上限

本机已满足原生“充电上限”要求（Apple Silicon + macOS 26.4）。对 **80–100%** 区间，原生功能正确实现了 5% 滞回、不断开适配器、不放电、自动校准，**严格优于**当前 CHIE 方案。chargewatch 自研 SMC 方案的唯一独有价值是 **<80% 的上限**（原生做不到）。可考虑：80–100% 委托原生 / 仅 <80% 才走自研 CHIE 路径。

### 6.5 验证方法

- 看 `/var/log/chargewatch-helper.log`，确认能观测到完整一轮 `upper → 放电 → lower → 恢复`，SoC 真能掉到 limit-deadband 再充、周期显著拉长。
- 退出 App 后 `launchctl print` 确认守护进程状态、`DumpCommand` 回读 CHIE 确认充电已恢复。

## 七、关键主张可信度

| 主张 | 判定 | 来源 |
|---|---|---|
| 官方 Charge Limit 明确 5% 滞回、上限 80–100%、需 26.4+Apple 芯片 | confirmed | support.apple.com/en-us/102338 |
| OBC 在 80% 处官方未公布下限/滞回数字 | confirmed | 102338 / 108055 |
| 两特性都偶尔充满 100% 校准 SoC | confirmed | 102338 / 108055 |
| iOS 18 上限 80/85/90/95% 含 5% 缓冲 | confirmed | 108055 |
| charge-disable（CH0B/CH0C/CHTE）停充时 ExternalConnected 仍 Yes | confirmed | batt / Battery-Toolkit 源码 |
| batt 用 AC-W 检测物理适配器在位 | confirmed | batt `pkg/smc/acpower.go` |
| “强制放电用 ACEN”“停充用 CH0B/CH0I 并列”“工具靠 ioreg IsCharging 监测” | refuted | batt/actuallymentor 源码 |
| chargewatch 振荡 = CHIE 与 ExternalConnected 负反馈环 | confirmed | `main.swift:71,90-91,113,115,119-129` |
| “退出 App”不卸载守护进程/不写回 CHIE/不改 enabled | confirmed | `ChargeWatchApp.swift:48-50` 等 |
