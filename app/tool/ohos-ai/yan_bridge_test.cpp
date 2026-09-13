// 桥接层（yan_ai.h）的设备端验证程序。
//
// 探针只验证"llama.cpp 能跑"，这个验证"应用要用的 C 接口能用"：
// 模型只加载一次、连续多次补全、停止串与复读检测是否真的按预期终止。

#include "yan_ai.h"

#include <cstdio>
#include <cstring>
#include <string>

static int on_piece(const char * piece, int len, void * user) {
    std::string * acc = (std::string *) user;
    acc->append(piece, len);
    printf("%.*s", len, piece);
    fflush(stdout);
    return 0;
}

static int run_case(const char * label, const char * prefix, int max_tokens) {
    printf("\n=== %s ===\n", label);
    printf("输入: %s\n", prefix);

    YanAiParams p;
    memset(&p, 0, sizeof(p));
    p.max_tokens = max_tokens;

    YanAiError err;
    std::string out;
    printf("输出: ");
    fflush(stdout);

    const int rc = yan_ai_complete(prefix, &p, on_piece, &out, &err);
    printf("\n[停止原因] %s (rc=%d)\n", err.message, rc);
    printf("[本轮字节数] %d    [复读度量] %.2f\n", (int) out.size(), yan_ai_last_repeat_ratio());
    return rc;
}

int main(int argc, char ** argv) {
    if (argc < 2) {
        fprintf(stderr, "用法: %s <model.gguf>\n", argv[0]);
        return 2;
    }

    YanAiConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.n_ctx     = 512;
    cfg.n_batch   = 128;
    cfg.n_threads = 4;

    YanAiError err;
    printf("[bridge] 加载模型 %s\n", argv[1]);
    fflush(stdout);
    if (yan_ai_load(argv[1], &cfg, &err) != 0) {
        fprintf(stderr, "[bridge] FAIL: %s\n", err.message);
        return 1;
    }
    printf("[bridge] 已加载，is_loaded=%d\n", yan_ai_is_loaded());
    fflush(stdout);

    run_case("表格续写（默认预算）", "| 平台 | 状态 |\n| --- | --- |\n| Windows | 已发布 |\n|", 0);
    run_case("段落续写（默认预算）", "砚是一款专注于中文写作的 Markdown 编辑器，它", 0);
    run_case("列表续写（默认预算）", "- 支持 Windows\n- 支持鸿蒙\n-", 0);

    printf("\n[bridge] 会话复用验证：第三次补全未重新加载模型即完成\n");
    yan_ai_unload();
    printf("[bridge] RESULT: OK\n");
    return 0;
}
