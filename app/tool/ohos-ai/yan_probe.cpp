// OHOS 端侧推理探针：最小可执行。
//
// 目的只有一个：**证明 llama.cpp 能在鸿蒙上加载模型并真正跑出推理结果**。
// 所以刻意保持最小 —— 不要 UI、不要 Flutter、不要采样策略，只验证
// "运行时能起来 + 模型能加载 + 前向计算能出 token"。
//
// 用法（在设备上）：
//     ./yan_probe <模型.gguf> "<提示词>" [生成token数]

#include "llama.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

int main(int argc, char ** argv) {
    if (argc < 3) {
        fprintf(stderr, "用法: %s <model.gguf> <prompt> [n_predict]\n", argv[0]);
        return 2;
    }
    const char * model_path = argv[1];
    const std::string prompt = argv[2];
    const int n_predict = argc > 3 ? atoi(argv[3]) : 16;

    printf("[probe] llama.cpp backend init\n");
    fflush(stdout);
    llama_backend_init();

    auto mparams = llama_model_default_params();
    // 探针跑在模拟器/真机 CPU 上，显式关掉 GPU 卸载，避免依赖设备 GPU 后端
    mparams.n_gpu_layers = 0;

    printf("[probe] loading model: %s\n", model_path);
    fflush(stdout);
    llama_model * model = llama_model_load_from_file(model_path, mparams);
    if (model == nullptr) {
        fprintf(stderr, "[probe] FAIL: cannot load model\n");
        return 1;
    }

    const llama_vocab * vocab = llama_model_get_vocab(model);
    printf("[probe] model loaded, n_vocab=%d\n", llama_vocab_n_tokens(vocab));
    fflush(stdout);

    auto cparams = llama_context_default_params();
    cparams.n_ctx = 256;
    cparams.n_batch = 128;
    // CPU 线程数：模拟器上给保守值，真机可按核数调
    cparams.n_threads = 4;
    cparams.n_threads_batch = 4;

    llama_context * ctx = llama_init_from_model(model, cparams);
    if (ctx == nullptr) {
        fprintf(stderr, "[probe] FAIL: cannot create context\n");
        return 1;
    }

    // tokenize
    std::vector<llama_token> tokens(prompt.size() + 8);
    const int n_tok = llama_tokenize(vocab, prompt.c_str(), (int) prompt.size(),
                                     tokens.data(), (int) tokens.size(),
                                     /*add_special=*/true, /*parse_special=*/false);
    if (n_tok < 0) {
        fprintf(stderr, "[probe] FAIL: tokenize failed\n");
        return 1;
    }
    tokens.resize(n_tok);
    printf("[probe] prompt tokens=%d\n", n_tok);
    fflush(stdout);

    // 一次前向（prefill）
    llama_batch batch = llama_batch_get_one(tokens.data(), (int) tokens.size());
    if (llama_decode(ctx, batch) != 0) {
        fprintf(stderr, "[probe] FAIL: decode failed\n");
        return 1;
    }
    printf("[probe] prefill OK\n");
    fflush(stdout);

    // 贪心解码，只验证能不能持续出 token
    std::string out;
    for (int i = 0; i < n_predict; i++) {
        const llama_token tok = llama_sampler_sample(
            llama_sampler_chain_init(llama_sampler_chain_default_params()), ctx, -1);
        if (llama_vocab_is_eog(vocab, tok)) break;

        char buf[256];
        const int n = llama_token_to_piece(vocab, tok, buf, sizeof(buf), 0, false);
        if (n > 0) { out.append(buf, n); }

        llama_batch b = llama_batch_get_one((llama_token *) &tok, 1);
        if (llama_decode(ctx, b) != 0) {
            fprintf(stderr, "[probe] FAIL: decode at step %d\n", i);
            return 1;
        }
    }

    printf("[probe] generated: %s\n", out.c_str());
    printf("[probe] RESULT: OK\n");

    llama_free(ctx);
    llama_model_free(model);
    llama_backend_free();
    return 0;
}
