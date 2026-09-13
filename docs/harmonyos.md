# 鸿蒙（HarmonyOS NEXT / OpenHarmony）适配进展

> **状态：HAP 已成功产出（108.69 MB），唯一未完成的是签名 —— 那一步需要你的华为开发者账号。**
> 实测证据与复现步骤见 `docs/harmonyos-build-log.md`。
> 最后更新：2026-09-12 夜

---

## 一句话结论

**鸿蒙端打不通的问题已经解决到"只差签名"。** 真正的卡点不是 SDK 版本（本机 API 24
被工具链正常接受），而是 **Flutter 的鸿蒙适配分支长期落后于官方 Flutter** ——
官方分支是 Flutter 3.7.12 / Dart 2.19，而砚的代码用了 Dart 3 的 records 与模式匹配。
最终选定 CPF-Flutter 的 **3.27.4-ohos** 分支，绕开了这个问题。

**你明天需要做的一件事**：在 DevEco Studio 里配置调试签名（见文末第五节），
之后重新跑一次构建脚本就能得到可装真机的 `entry-default-signed.hap`。

---

## 一、环境（已就绪）

| 组件 | 版本 / 位置 | 来源 |
|---|---|---|
| Flutter（鸿蒙分支） | **3.27.4-ohos** @ `C:\ohos-flutter-327` | [gitcode.com/CPF-Flutter/flutter_flutter](https://gitcode.com/CPF-Flutter/flutter_flutter) 分支 `br_3.27.4-ohos-1.0.4` |
| Dart | **3.6.2** | 随分支自动下载 |
| DevEco Studio | 6.1 | `C:\Program Files\Huawei\DevEco Studio` |
| HarmonyOS SDK | **API 24**（HarmonyOS 6.1.1.125） | DevEco 自带，`sdk\default\sdk-pkg.json` |
| ohpm | 6.1.2.285 | DevEco `tools\ohpm\bin` |
| hvigor | 随 DevEco | DevEco `tools\hvigor\bin` |
| hdc | 3.2.0d | DevEco `sdk\default\openharmony\toolchains` |
| Node | v18.20.1 | DevEco `tools\node` |
| JDK | JBR 21.0.8 | DevEco `jbr` |

环境脚本：`app/tool/ohos_env.ps1`（source 进当前会话，不改系统环境变量）。

**`flutter doctor` 关键行（实测输出）**：

```
[✓] HarmonyOS toolchain - develop for HarmonyOS devices
```

在 3.7.12 分支上它还额外报告了：

```
• OpenHarmony Sdk at ...\DevEco Studio\sdk, available api versions has [24:default]
• Ohpm version 6.1.2.285
• Node version v18.20.1
• Hvigorw binary at ...\tools\hvigor\bin\hvigorw
```

---

## 二、选型过程（为什么不是官方仓）

### 试过 A：官方仓 `gitee.com/openharmony-sig/flutter_flutter` 的 master

- 只有它分支列表里有完整鸿蒙支持；但 **基于 Flutter 3.7.12，自带 Dart 2.19.6**（提交日期 2025-02-21）
- 实测 `flutter doctor` 通过，工具链识别正常
- **致命问题**：Dart 2.19 不支持 records 与模式匹配，砚的代码里有 **44 处 records + 6 处模式匹配**
  （`lib/src/core/` 与 `lib/src/state/` 大量使用，例如 `SearchHit` 的命中位置、
  `MathExtractor` 的 `(String, int)` 返回、`TextStats` 的元组赋值）
- 全量降级到 Dart 2.19 成本高且易错，而且会让同一份代码库长期分裂

### 试过 B：同仓 `3.22.1-ohos-0.1.0` 分支

- 以为它能支持 Dart 3 —— **但它其实是纯上游 Flutter 3.22，完全没有鸿蒙支持**
  （`templates/app` 下没有 ohos 目录，`commands/` 里没有 `build_hap.dart`）
- 该分支的 `bin/internal/` 里根本没有 `engine.ohos.version`，只有 `engine.version`
- 排除

### 选定 C：`gitcode.com/CPF-Flutter/flutter_flutter` 的 `br_3.27.4-ohos-1.0.4`

- **Flutter 3.27.4 + Dart 3.6.2**，且**确实带完整鸿蒙支持**
  （122 个文件涉及 ohos，含 `build_hap.dart` / `ohos_builder.dart` / `ohos.tmpl` 模板）
- 官方 GitHub 的 `openharmony-sig` 组织**已不存在**（`Repository not found`），
  仓库迁到了 gitee 与 gitcode；gitcode 这个镜像的版本更新
- 唯一需要改的 Dart 3.9+ 语法只有 1 处 `abstract final class`（见下）

**这个判断值得记下来**：鸿蒙 Flutter 生态的关键限制不是 SDK 版本，而是
**适配分支的 Flutter 版本落后**。选分支时要先看它基于哪个 Flutter 版本，
再看那个版本带哪个 Dart —— 否则会撞上语言特性缺失。

---

## 三、为兼容 Dart 3.6 做的代码调整

### 1. `abstract final class` → 私有构造

`lib/src/core/typography.dart` 原用 `abstract final class AppFonts`，
这是 **Dart 3.9** 的语法，Dart 3.6 不认。改为：

```dart
class AppFonts {
  const AppFonts._();
  // ... 其余不变（全静态成员）
}
```

语义完全一致（不可实例化、不可继承），但兼容 Dart 3.0+。

### 2. `pubspec.yaml` 的 SDK 下界：`>=3.9.0` → `>=3.6.0`

桌面端是 Flutter 3.47 / Dart 3.13，鸿蒙端是 Dart 3.6.2。下界取两者中更低的一方。

### 3. 依赖约束改为"下界低 + 上界放开"

原来写的是 `markdown: ^7.3.1` 这类**宽松范围**，在 Dart 3.6 下会直接求解失败：

```
Because yan_note depends on flutter_lints >=6.0.0 which requires SDK version ^3.8.0,
version solving failed.
```

改成区间约束（如 `markdown: ">=7.2.0 <8.0.0"`），让 pub 求解器**按各端自己的 Dart 版本
自动挑最高的兼容版本**：桌面端取最新，鸿蒙端自动降到仍兼容 3.6 的最高版。

### 4. `flutter_test` / `integration_test` 在鸿蒙线上不能用

鸿蒙 fork **自报版本号是 `0.0.0-unknown`**，而这两个 SDK 包都要求 Flutter >= 3.18：

```
Because every version of flutter_test from sdk depends on leak_tracker_flutter_testing
>=2.0.3 which requires Flutter SDK version >=3.18.0-18.0.pre.54, version solving failed.
```

处理方式：`tool/build_ohos.ps1` 在构建 HAP 前**临时**把这两个依赖从 pubspec 摘掉，
构建后自动还原。桌面端要跑集成测试则用 `tool/with_integration_test.ps1` 临时加回来。

> 这是 fork 的限制，不是砚的问题。上游把版本号修好之后这两个脚本就可以删掉。

---

## 四、构建方式

```powershell
# 一键构建 HAP（自动处理依赖裁剪、环境变量、数学包补丁）
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yan\app\tool\build_ohos.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yan\app\tool\build_ohos.ps1 -Mode release
```

等价的原始命令：

```powershell
. C:\yan\app\tool\ohos_env.ps1
cd C:\yan\app
flutter build hap --debug --target-platform ohos-arm64
```

**实测产物（已产出）**：

```
ohos\entry\build\default\outputs\default\entry-default-unsigned.hap   108.69 MB
```

包内关键内容：`libflutter.so`(39 MB 鸿蒙引擎) + `kernel_blob.bin`(58 MB Dart 代码)
+ `isolate_snapshot_data` + `ets/modules.abc`(ArkTS) + KaTeX 公式字体 + 示例笔记。

配置签名后才会得到 `entry-default-signed.hap`。

安装到设备（需真机 + USB 调试）：

```powershell
hdc list targets
hdc -t <deviceId> install <hap 路径>
# 或
flutter run --debug -d <deviceId>
```

---

## 五、高频坑：DevEco 同步报 `Error Code: 00308018`

**症状**（在 DevEco 里同步工程，或直接敲 hvigor 命令时）：

```
> hvigor ERROR: Error Code: 00308018 Unknown Error
TypeError Cannot read properties of undefined (reading 'filter')
  at evaluateHvigorConfig (.../hvigor/src/base/internal/lifecycle/init.js)
```

**根因（已实测确认，不是配置问题）**

`ohos/node_modules/flutter-hvigor-plugin` 的 `findFlutterPlugins()` 里是：

```js
const ohosPlugins = JSON.parse(fileContent).plugins.ohos
const filteredPlugins = ohosPlugins.filter(plugin => plugin.native_build !== false)
```

而**官方 Flutter 的 `pub get` 会重写 `.flutter-plugins-dependencies`，并抹掉 `ohos` 键** ——
因为官方 Flutter 根本不认识 `ohos` 这个平台。实测对比：

| 谁跑的 pub get | 顶层键 |
|---|---|
| OHOS fork | `ios, android, macos, linux, windows, web, **ohos**` |
| 官方 Flutter 3.47 | `ios, android, macos, linux, windows, web` ← **ohos 没了** |

`ohos` 键一没，`.plugins.ohos` 就是 `undefined`，`.filter` 立刻抛错，hvigor 连带整个同步失败。

**所以触发条件很日常**：只要在鸿蒙构建之前用桌面版 Flutter 跑过一次 `pub get`
（比如为了跑 Windows 测试），hvigor 同步就会崩。

**修复（两层，均已落地）**

1. `tool/patch_hvigor_plugin.ps1` —— 把插件改成容错：缺 `ohos` 键时按"没有 ohos 插件"处理，
   而不是整个崩掉。
2. `tool/build_ohos.ps1` —— 构建前**必定**用 OHOS fork 跑一次 `pub get`，保证 `ohos` 键存在；
   构建后再复核一遍插件补丁（因为 hvigor 会跑 `ohpm install`，可能还原 `node_modules`）。

**你自己遇到时的速修**：

```powershell
# 方案 A：用 OHOS fork 重新生成该文件（治本）
. C:\yan\app\tool\ohos_env.ps1
cd C:\yan\app
flutter pub get

# 方案 B：给插件打容错补丁（治标，但能扛住以后官方 pub get 的覆盖）
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yan\app\tool\patch_hvigor_plugin.ps1
```

### 打完补丁仍然报同一个错？先重启守护进程

**这是最容易误判的一步。** hvigor 守护进程把插件代码**缓存在内存里**（Node 的 require 缓存），
文件被改动**不会**让已加载的模块失效。于是会出现"补丁明明在文件里，DevEco 构建却仍报
`00308018 / reading 'filter'`"。

实测时间线：

| 时间 | 事件 |
|---|---|
| 12:47:35 | 守护进程 worker 启动，加载**未打补丁**的插件 |
| 12:53:08 | 补丁写入文件（worker 内存里仍是旧的） |
| 13:24 | DevEco 构建 → 复用旧 worker → 旧代码 → 崩 |

**判别方法**：同一命令

```powershell
hvigorw --sync -p product=default ... --daemon      # 崩
hvigorw --sync -p product=default ... --no-daemon   # 正常
```

加了 `--daemon` 崩、加 `--no-daemon` 正常 —— 就是守护进程缓存。

**处理**：杀掉 hvigor 的 node 进程（`patch_hvigor_plugin.ps1` 现在会自动做这件事），
下次构建会自动重启并重新读取插件。

---

## 六、还差的一步：签名（需要你做）

`ohos/build-profile.json5` 里 `signingConfigs` 是**空数组**（`flutter create` 生成时不含签名），
因此只能产出 unsigned HAP，**装不上真机**。构建日志里的原文提示：

```
请通过DevEco Studio打开ohos工程后配置调试签名
(File -> Project Structure -> Signing Configs 勾选Automatically generate signature)
```

**操作步骤**：

1. 打开 DevEco Studio → `File` → `Open` → 选择 `C:\yan\app\ohos`
2. `File` → `Project Structure` → `Signing Configs` → 勾选
   **`Automatically generate signature`**（会要求登录华为账号）
3. 等它生成证书与 profile
4. 回到命令行重跑 `tool\build_ohos.ps1` → 应得到 `entry-default-signed.hap`
5. 真机连上后：`hdc -t <deviceId> install <signed.hap 路径>`

---

## 七、已知卡点与风险

| 卡点 | 说明 | 状态 |
|---|---|---|
| 模拟器 | 鸿蒙模拟器**仅支持 Mac(arm64)**，Windows 上没有 | 只能真机验证 |
| 签名 | `build-profile.json5` 的 `signingConfigs` 为**空数组** —— 未配置签名时 HAP 可以构建但**装不上真机** | 待你提供签名（DevEco 里自动生成） |
| SDK 版本 | 模板写死 `5.0.0(12)`、`targetSdkVersion` 为空串，与本机 API 24 不匹配 | **已修**，见第六节；`tool/sync_ohos_sdk_version.ps1` 自动对齐 |
| 无真机 | 本机没有鸿蒙设备，**无法验证运行**，只能验证"构建通过" | 需要在你的真机上验证 |
| Dart 版本差 | 鸿蒙 Dart 3.6 vs 桌面 Dart 3.13，代码需长期保持"3.6 兼容" | 需要 CI 或约定来守 |

---

## 八、SDK 版本报错的修法

**症状**：

```
compileSdkVersion、compatibleSdkVersion 或 targetSdkVersion（若显式配置）的值不正确，
请按照指南中的说明修改该值。
```

**根因**：`flutter create` 的鸿蒙模板把 `compatibleSdkVersion` 写死成 `5.0.0(12)`，
且 `targetSdkVersion` 是**空字符串**（schema 不接受空串）。若本机只装了别的版本
（例如 HarmonyOS 6.1.1 / API 24），两者就对不上。

证据：修之前 HAP 里记录的 `minAPIVersion` 是 `50000012`（= 5.0.0(12)），
而 `targetAPIVersion` 是 `60101024` —— 声明的最低版本 12 在本机根本不存在。

**修法**（已自动化，`tool/sync_ohos_sdk_version.ps1`）：

1. 从 `<DevEco>/sdk/default/sdk-pkg.json` 读 `platformVersion` 与 `apiVersion`
2. 拼成 `主.次.修订(API)`，例如 `6.1.1(24)`
3. 写进 `build-profile.json5` 的 `compatibleSdkVersion` 与 `targetSdkVersion`

`build_ohos.ps1` 每次构建前会调用它，所以换机器不用手动改。

**格式由 hvigor 的 schema 校验**：

```
^((?:[5-9]|[1-9]\d+)\.\d+\.\d+\(\d+\)|4\.(?:[1-9]\d*\.\d+\(\d+\)|0\.(?:[1-9]\d*\(\d+\)|0\((?:1[1-9]|[2-9]\d+)\))))$
```

**`compileSdkVersion` 不用配**：hvigor 里是
`compileSdkVersion: t.compileSdkVersion ?? SUPPORT_COMPILE_VERSION`，缺省即用
SDK 自带的默认值。

修完的验证：HAP 里的 `minAPIVersion` 变为 `60101024`，与 `targetAPIVersion` 一致。

---

## 九、诚实结论：做到哪一步了

**已经完成并实测通过的**：

- ✅ 环境打通：鸿蒙工具链被 `flutter doctor` 识别为 `[✓] HarmonyOS toolchain`
- ✅ 选定并拉取可用的 Flutter 鸿蒙分支（**3.27.5-ohos-1.0.4** / Dart 3.6.2）
- ✅ 修掉浅克隆导致的 `0.0.0-unknown`（补 tag，`.git` 1.95 GB）
- ✅ 生成 `ohos` 平台工程（35 个文件，含 `EntryAbility.ets` / `module.json5` / `hvigorfile.ts`）
- ✅ 代码调整到 Dart 3.6 兼容（1 处语法 + pubspec SDK 下界 + 依赖区间约束）
- ✅ 依赖在鸿蒙线上求解通过（`pub get`，依赖树自动降到兼容 3.6 的版本）
- ✅ 解决 `flutter_math_fork` 与 Flutter 3.27 / `TargetPlatform.ohos` 的双重不兼容
- ✅ **HAP 构建成功产出**：`entry-default-unsigned.hap`，**108.69 MB**，46 个条目，
      内含鸿蒙引擎 `libflutter.so`、Dart 代码 `kernel_blob.bin`、KaTeX 公式字体、示例笔记
- ✅ 脚本落地：`ohos_env.ps1` / `build_ohos.ps1` / `patch_math_for_ohos.ps1` / `with_integration_test.ps1`

**没有完成、也无法在我这里完成的**：

- ❌ **签名** —— `signingConfigs` 为空，需你在 DevEco Studio 勾选自动生成签名（需华为账号）
- ❌ **真机运行验证** —— 本机没有鸿蒙设备；鸿蒙模拟器**仅支持 Mac(arm64)**，Windows 上不可用
- ❌ **上架准备** —— 需华为开发者认证（宪章 §3 已提到要提前查流程与费用）

**给宪章排期的建议**：把鸿蒙端从 W7–8 的"适配"重新定义为两段——
① **构建打通**（本次已完成）；② **签名 + 真机验证 + 上架**（需要你在有设备与账号时做）。
另外把"鸿蒙 Flutter 分支版本"列为**长期跟踪项**：上游一旦跟进到更新的 Dart 版本，
就该升级 fork，否则桌面端会被迫一直停留在 Dart 3.6 兼容模式。

---

## 十、给上游的反馈建议

本次踩到的问题都值得提给上游，对后来的鸿蒙 Flutter 使用者有直接价值：

1. **`flutter_math_fork` 与 `TargetPlatform.ohos` 不兼容** ——
   鸿蒙分支给 `TargetPlatform` 新增了 `ohos`，任何对 `switch (platform)` 做穷尽匹配的第三方包
   都会编译失败。建议鸿蒙分支给出兼容迁移指引，或在 `flutter_math_fork` 侧补 `ohos` 分支。
2. **`flutter_math_fork 0.7.4` 依赖 Flutter 3.47 才有的
   `RenderObjectWithLayoutCallbackMixin`** —— 与 3.22/3.27 系列均不兼容。
   建议包方在文档里标注最低 Flutter 版本。
3. **官方仓（gitee `openharmony-sig`）的 master 仍停留在 Flutter 3.7.12 / Dart 2.19** ——
   与 2026 年的 Dart 3 生态差距过大。建议 README 明确标注"Dart 2.19，不支持 records /
   模式匹配"，避免使用者按默认分支拉下来才发现要降级语言特性。
4. **`flutter-hvigor-plugin` 应按缺失的 `ohos` 键容错** —— 官方 Flutter 的 `pub get` 会抹掉
   该键（它不认识 ohos 平台），而插件直接 `.plugins.ohos.filter(...)`，导致
   `Error Code: 00308018`。建议插件方改成 `?? []`，或在 README 里写明
   "跑过官方 pub get 之后要用 fork 重新生成 `.flutter-plugins-dependencies`"。

---

## 十一、参考

- [Flutter 鸿蒙版环境配置（Windows）](https://cloud.tencent.com.cn/developer/article/2514736)
- [适配 HarmonyOS Next API16 的鸿蒙版 Flutter 3.22.0 发布](https://cloud.tencent.cn/developer/article/2518615)
- [基于 Flutter 3.27.4 鸿蒙版 0.1.0（Beta）发布](https://cloud.tencent.cn/developer/article/2546682)
- [Flutter-OH 升级指导](https://openharmonycrossplatform.csdn.net/69bc95e00a2f6a37c598bb01.html)
- 官方仓（Flutter 3.7.12 / Dart 2.19）：<https://gitee.com/openharmony-sig/flutter_flutter>
- 本次选用的仓（Flutter 3.27.4）：<https://gitcode.com/CPF-Flutter/flutter_flutter>
- 实测构建记录：`docs/harmonyos-build-log.md`
