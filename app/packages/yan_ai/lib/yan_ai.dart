// yan_ai 原生库的加载入口。
//
// 这个插件的职责很单纯：**让 hvigor 把 llama.cpp + 桥接层编成 libyan_ai.so
// 并随应用打包**（靠 pubspec 里的 `ffiPlugin: true` 与 ohos/build-profile.json5
// 的 externalNativeOptions）。
//
// 真正的 FFI 绑定在应用侧（lib/src/core/ai_native.dart）：那里要把调用放进
// 独立 isolate、还要处理取消，属于应用逻辑，不该塞进插件。所以这里只提供
// "库在不在、怎么打开"这一件事。

import 'dart:ffi';
import 'dart:io';

/// 原生库的运行时文件名。
const String yanAiLibName = 'yan_ai';

/// 打开原生库。
///
/// 各平台的产物名不同：Windows 是 yan_ai.dll，OHOS/Linux 是 libyan_ai.so。
/// 加载失败返回 null —— 端侧补全是可选能力，缺了库不该让应用起不来。
DynamicLibrary? openYanAiLibrary() {
  try {
    if (Platform.isWindows) {
      return DynamicLibrary.open('$yanAiLibName.dll');
    }
    if (Platform.operatingSystem == 'ohos' || Platform.isLinux) {
      return DynamicLibrary.open('lib$yanAiLibName.so');
    }
  } on Object {
    return null;
  }
  return null;
}

/// 原生库是否可用。
bool get yanAiLibraryAvailable => openYanAiLibrary() != null;
