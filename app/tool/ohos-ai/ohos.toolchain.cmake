# OHOS（OpenHarmony / HarmonyOS NEXT）交叉编译工具链。
#
# llama.cpp 仓库里没有 ohos.toolchain.cmake，但 OHOS NDK 自带完整 clang，
# 直接用 --target=+--sysroot 就能出 OHOS ELF（已单独验证过）。
#
# 用法：
#   cmake -G Ninja -DCMAKE_TOOLCHAIN_FILE=<此文件> -DOHOS_ARCH=x86_64 ..
#
# OHOS_ARCH 支持 x86_64（模拟器）与 aarch64（真机）。

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR ${OHOS_ARCH})

if(NOT OHOS_ARCH)
    set(OHOS_ARCH "x86_64")
endif()
if(NOT OHOS_SDK_NATIVE)
    message(FATAL_ERROR "必须指定 -DOHOS_SDK_NATIVE=<ohos sdk>/native")
endif()

set(OHOS_TRIPLE "${OHOS_ARCH}-linux-ohos")

set(CMAKE_C_COMPILER   "${OHOS_SDK_NATIVE}/llvm/bin/clang.exe")
set(CMAKE_CXX_COMPILER "${OHOS_SDK_NATIVE}/llvm/bin/clang++.exe")
set(CMAKE_AR           "${OHOS_SDK_NATIVE}/llvm/bin/llvm-ar.exe")
set(CMAKE_RANLIB       "${OHOS_SDK_NATIVE}/llvm/bin/llvm-ranlib.exe")
set(CMAKE_STRIP        "${OHOS_SDK_NATIVE}/llvm/bin/llvm-strip.exe")

set(OHOS_COMMON_FLAGS "--target=${OHOS_TRIPLE};--sysroot=${OHOS_SDK_NATIVE}/sysroot")
set(CMAKE_C_FLAGS_INIT   "${OHOS_COMMON_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${OHOS_COMMON_FLAGS}")

# 关键：OHOS 产物在 Windows 宿主上跑不起来（"not a valid Win32 application"），
# CMake 默认的运行式编译器探测会让它去执行产物从而崩掉。
# 改成只编静态库、不链接不运行，探测即可通过。
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# 让 try_compile 之类的探测也走交叉编译，不要试图在 Windows 上运行产物
set(CMAKE_CROSSCOMPILING_EMULATOR "")
set(CMAKE_FIND_ROOT_PATH "${OHOS_SDK_NATIVE}/sysroot")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
