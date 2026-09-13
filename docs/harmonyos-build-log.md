# 鸿蒙 HAP 构建记录（实测证据）

> 本文件是 `docs/harmonyos.md` 的证据附录：记录**实际执行过的命令与真实输出**。
> 时间：2026-09-12 夜

---

## 结果摘要

**HAP 构建成功产出，唯一未完成的是签名 —— 那一步需要你的华为开发者账号。**

产物：

```
C:\yan\app\ohos\entry\build\default\outputs\default\entry-default-unsigned.hap
108.69 MB   (2026-09-12 23:30:42)
```

它是一个**合法且完整**的包（HAP 本质是 zip），46 个条目，关键内容齐全：

| 内容 | 大小 | 说明 |
|---|---|---|
| `libs/arm64-v8a/libflutter.so` | 39.0 MB | 鸿蒙版 Flutter 引擎 |
| `resources/rawfile/flutter_assets/kernel_blob.bin` | 58.1 MB | **Dart 代码**（debug 走 kernel，release 才是 libapp.so） |
| `resources/rawfile/flutter_assets/isolate_snapshot_data` | 10.3 MB | Dart isolate 快照 |
| `ets/modules.abc` | 868.6 KB | ArkTS 侧（EntryAbility 等） |
| `module.json` / `resources.index` / `pack.info` | — | 模块与资源描述 |
| `flutter_assets/packages/flutter_math_fork/.../KaTeX_*.ttf` | 20 个文件 | **公式渲染字体已随包** |
| `flutter_assets/assets/sample/*.md` | 5 个文件 | 内置示例库 |

> `libapp.so` 不在包内是**正常的**：debug 构建用 `kernel_blob.bin`，AOT 产物 `libapp.so`
> 只在 `--release` 下生成。

---

## 环境

| 项 | 值 |
|---|---|
| Flutter（鸿蒙分支） | `3.27.5-ohos-1.0.4` @ `C:\ohos-flutter-327` |
| Dart | 3.6.2 |
| 分支 | `br_3.27.4-ohos-1.0.4` @ `269265738b`（2026-07-28） |
| 仓库 | `https://gitcode.com/CPF-Flutter/flutter_flutter.git` |
| 引擎 revision | `e672b006cb34c921db85b8e2f482ed3144a4574b` |
| 鸿蒙引擎 revision | `5588629ae9bd133b0096eaa66ff359d9c6a907a6` |
| DevEco Studio | 6.1 |
| HarmonyOS SDK | API 24（HarmonyOS 6.1.1.125） |
| JAVA_HOME | DevEco 自带 JBR 21.0.8 |

`flutter doctor` 关键行（真实输出）：

```
[✓] HarmonyOS toolchain - develop for HarmonyOS devices
    • OpenHarmony Sdk at C:\Program Files\Huawei\DevEco Studio\sdk, available api versions has [24:default]
    • Ohpm version 6.1.2.285
    • Node version v18.20.1
    • Hvigorw binary at C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw
```

---

## 构建命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yan\app\tool\build_ohos.ps1
```

该脚本依次做：

1. 配置 OHOS 环境变量（`DEVECO_SDK_HOME` / `JAVA_HOME` / PATH / pub 与引擎镜像）
2. **临时**从 `pubspec.yaml` 摘掉 `flutter_test` 与 `integration_test`（原因见下）
3. `flutter pub get`
4. `flutter build hap --debug --target-platform ohos-arm64`
5. 还原 `pubspec.yaml`
6. 搜索并打印 HAP 产物

---

## 途中解决的 5 个真实问题

### 0. DevEco 同步报 `Error Code: 00308018`（最常见的一个）

**症状**：

```
> hvigor ERROR: Error Code: 00308018 Unknown Error
TypeError Cannot read properties of undefined (reading 'filter')
  at evaluateHvigorConfig (.../hvigor/src/base/internal/lifecycle/init.js:1:5193)
```

**根因**：`flutter-hvigor-plugin` 的 `findFlutterPlugins()` 做
`JSON.parse(fileContent).plugins.ohos` 之后直接 `.filter(...)`，
而**官方 Flutter 的 `pub get` 会重写 `.flutter-plugins-dependencies` 并抹掉 `ohos` 键**
（它不认识 ohos 平台）。实测：

```
OHOS fork 写的       -> ios, android, macos, linux, windows, web, ohos
官方 Flutter 3.47 写的 -> ios, android, macos, linux, windows, web        (ohos 消失)
```

于是 `.plugins.ohos` 是 `undefined` → `.filter` 抛错 → hvigor 同步整体失败。

**修复**：

- `tool/patch_hvigor_plugin.ps1`：把插件改为容错（缺键当"无 ohos 插件"）
- `tool/build_ohos.ps1`：构建前必定用 OHOS fork 跑 `pub get`；构建后复核插件补丁
  （hvigor 会跑 `ohpm install`，可能还原 `node_modules`）

**验证**：故意用官方 Flutter 制造"缺 ohos 键"状态后，原命令
`hvigorw --sync -p product=default ...` 由 `BUILD FAILED` 变为 `exit=0`、无报错。

### 1. 浅克隆导致版本号算不出来 → 所有依赖求解失败

**症状**：

```
The current Flutter SDK version is 0.0.0-unknown.
Because yan_note depends on flutter_math_fork >=0.3.0+1 which requires Flutter SDK version >=2.0.0,
version solving failed.
```

**根因**：`git clone --depth 1` 没有 tag，`git describe --tags` 报
`fatal: No names found, cannot describe anything.`，于是
`GitTagVersion.determine()` 返回 `0.0.0-unknown`（见 `packages/flutter_tools/lib/src/version.dart`）。

**修复**：

```powershell
cd C:\ohos-flutter-327
git fetch --tags --force --unshallow origin   # 拉完 .git 约 1.95 GB，72 个 tag
Remove-Item bin\cache\flutter.version.json    # 清掉缓存的错误版本
flutter --version                             # 重建缓存
```

修复后：

```
Flutter 3.27.5-ohos-1.0.4 • channel [user-branch] • https://gitcode.com/CPF-Flutter/flutter_flutter.git
Framework • revision 269265738b (7 weeks ago) • 2026-07-28 16:37:44 +0800
Engine • revision e672b006cb
Tools • Dart 3.6.2 • DevTools 2.40.0
```

### 2. `flutter_test` / `integration_test` 在鸿蒙线上无法解析

**症状**：

```
Because every version of flutter_test from sdk depends on leak_tracker_flutter_testing
>=2.0.3 which requires Flutter SDK version >=3.18.0-18.0.pre.54, version solving failed.
```

**根因**：fork 自报版本号被上游测试包判定不满足 `>=3.18`。
**修复**：构建前临时摘掉这两个 dev 依赖（`build_ohos.ps1` 自动做并还原）。
这是 fork 的限制，不是砚的问题。

### 3. `flutter_math_fork 0.7.4` 与 Flutter 3.27 不兼容

**症状（两类编译错误）**：

```
layout_builder_baseline.dart:26: Error: Type 'RenderObjectWithLayoutCallbackMixin' not found.
selectable.dart:276: Error: The type 'TargetPlatform' is not exhaustively matched by the
  switch cases since it doesn't match 'TargetPlatform.ohos'.
```

**根因**：

1. `RenderObjectWithLayoutCallbackMixin` / `runLayoutCallback()` 是 **Flutter 3.47** 才有的 API
   （3.47 的 `packages/flutter/lib/src/rendering/object.dart` 里有，3.27.4 里没有）。
   即该包是按比 3.27 更新的 Flutter 写的。
2. 鸿蒙分支给 `TargetPlatform` 枚举**新增了 `ohos`**（官方 Flutter 的枚举只有
   android/fuchsia/iOS/linux/macOS/windows），于是第三方包里所有穷尽 `switch (platform)`
   都编译失败 —— 该包共 4 处。

**修复**：`tool/patch_math_for_ohos.ps1` 就地修补 pub 缓存里的包：

- 去掉 3.27 不存在的 mixin，加一个提供空 `runLayoutCallback()` 的兼容垫片；
- 在 4 处 `case TargetPlatform.windows:` 前插入同分支的 `case TargetPlatform.ohos:`。

脚本幂等（重复运行只报"已是最新"）。

### 4. HAP 构建失败的最后一步：签名

**症状（构建成功产出 HAP 之后）**：

```
请通过DevEco Studio打开ohos工程后配置调试签名
(File -> Project Structure -> Signing Configs 勾选Automatically generate signature)
```

**根因**：`ohos/build-profile.json5` 里 `signingConfigs` 是**空数组**（`flutter create` 生成时
不含签名）。没有签名只能产出 `entry-default-unsigned.hap`，**装不到真机**。

**这一步需要你来做**（需要华为开发者账号）：

1. `DevEco Studio` → `File` → `Open` → 选择 `C:\yan\app\ohos`
2. `File` → `Project Structure` → `Signing Configs` → 勾选
   **`Automatically generate signature`**（需要登录华为账号）
3. 等待自动生成证书与 profile
4. 回到命令行重新跑 `tool\build_ohos.ps1`，这次应产出 `entry-default-signed.hap`

---

## 复现步骤（从零）

```powershell
# 1. 拉取鸿蒙版 Flutter（3.27.4-ohos）
git clone --depth 1 --branch br_3.27.4-ohos-1.0.4 `
    https://gitcode.com/CPF-Flutter/flutter_flutter.git C:\ohos-flutter-327

# 2. 必须补 tag，否则版本号是 0.0.0-unknown
cd C:\ohos-flutter-327
git fetch --tags --force --unshallow origin

# 3. 生成 ohos 平台工程（已提交到本仓库，通常不需要重跑）
cd C:\yan\app
. C:\yan\app\tool\ohos_env.ps1
flutter create --platforms ohos --project-name yan_note --org dev.yan --no-pub .

# 4. 给 flutter_math_fork 打兼容补丁（pub get 之后）
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yan\app\tool\patch_math_for_ohos.ps1

# 5. 给 hvigor 插件打容错补丁（防止官方 pub get 抹掉 ohos 键后同步崩溃）
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yan\app\tool\patch_hvigor_plugin.ps1

# 6. 构建 HAP
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yan\app\tool\build_ohos.ps1
```

**日常最容易踩的一条**：鸿蒙构建之前不要用桌面版 Flutter 跑 `pub get`。
真跑了也没关系 —— 重新执行第 6 步（脚本里已经包含"用 fork 重新 pub get"这一步）。

---

## 还需要做的事

| 事项 | 谁来做 | 说明 |
|---|---|---|
| 配置调试签名 | **你**（需华为账号） | 见上文第 4 节；完成后即可产出 signed HAP |
| 真机安装验证 | **你**（需鸿蒙设备） | `hdc -t <id> install <hap>`；Windows 上无鸿蒙模拟器 |
| 上架准备 | **你** | 需华为开发者认证（宪章 §3 已提到要提前查流程与费用） |
| 升级 fork 后重跑补丁 | 维护时 | 换 PUB_CACHE / `pub cache clean` 后需重跑补丁脚本 |
| 给上游反馈 | 建议 | 见 `docs/harmonyos.md` 的"给上游的反馈建议" |
