// 端侧补全的 C 接口。Dart 侧通过 dart:ffi 调用。
#ifndef YAN_AI_H
#define YAN_AI_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct YanAiConfig {
    int n_ctx;        // 上下文窗口，0 表示用默认 512
    int n_batch;      // 0 表示用默认 128
    int n_threads;    // 0 表示用默认 4
    int reserved;     // 对齐用，必须为 0
} YanAiConfig;

typedef struct YanAiParams {
    int max_tokens;   // 最多生成多少 token
    int min_tokens;   // 至少生成多少 token 才允许被停止串截断
    int reserved1;
    int reserved2;
} YanAiParams;

// 错误信息。message 指向**静态存储**（不是调用方缓冲区），
// 所以不要 free，也不要在下一次调用之后继续使用。
//
// 为什么用 const char * 而不是内联的 char[64]：内联数组在 dart:ffi 里要当
// Array<Uint8> 处理，取值要么硬编码结构体偏移、要么绕开 `.address` 的限制，
// 两边都容易写错。指针形式在 Dart 侧就是一行 toDartString()。
typedef struct YanAiError {
    int         code;
    const char * message;
} YanAiError;

// 流出 token 时回调。可以为 NULL（不需要逐 token 通知）。
// 返回非 0 表示请求取消。
typedef int (*YanAiTokenFn)(const char * piece, int len, void * user);

// 返回 0 成功。模型只加载一次，之后可反复调用 yan_ai_complete。
int  yan_ai_load(const char * model_path, const YanAiConfig * cfg, YanAiError * err);
void yan_ai_unload(void);
int  yan_ai_is_loaded(void);

// 从其它线程调用以打断正在进行的生成。
void yan_ai_cancel(void);

// 阻塞直到完成。返回值是停止原因（见 yan_ai.cpp 的 StopReason），负数为错误。
//
// 生成的文本写进 [out]（长度上限 [out_cap]，保证 NUL 结尾）。
// 为什么要显式缓冲而不是只靠回调：Dart 侧不能把闭包跨 isolate 传给原生，
// 而原生回调又只在调用线程上跑，所以"只要结果、不要回调"是必须支持的用法。
int yan_ai_complete(const char * prefix, const YanAiParams * p,
                    char * out, int out_cap,
                    YanAiTokenFn on_token, void * user, YanAiError * err);

// 诊断用：上一次补全结束时的片段复用率（复读检测的度量）。
double yan_ai_last_repeat_ratio(void);

#ifdef __cplusplus
}
#endif

#endif  // YAN_AI_H
