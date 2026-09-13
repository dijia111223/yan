// OHOS 端侧推理探针。
//
// 回答两个问题：鸿蒙上能不能跑 llama.cpp 推理，以及**跑多快、吃多少内存**。
// 后者才是决定"端侧补全"这条路走不走得通的关键 —— 0.5B 模型在手机 CPU 上
// 如果每 token 要一两秒，就不能做成逐键补全，只能做成异步的建议。
//
// 用法（在设备上）：
//     ./yan_probe <模型.gguf> "<提示词>" [生成token数] [--raw]

#include "llama.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <time.h>

static double now_ms() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

// 只看 VmHWM（峰值常驻内存），这是端侧应用最硬的约束
static long peak_rss_kb() {
    FILE * f = fopen("/proc/self/status", "r");
    if (f == nullptr) return -1;
    char line[256];
    long kb = -1;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "VmHWM:", 6) == 0) { sscanf(line + 6, "%ld", &kb); break; }
    }
    fclose(f);
    return kb;
}

static void print_escaped(const char * label, const std::string & s) {
    printf("%s", label);
    for (unsigned char c : s) {
        if (c == '\n')      printf("\\n");
        else if (c == '\r') printf("\\r");
        else if (c == '\t') printf("\\t");
        else if (c == 0)    printf("\\0");
        else if (c < 0x20)  printf("\\x%02x", c);
        else                putchar(c);
    }
    printf("\n");
}

int main(int argc, char ** argv) {
    if (argc < 3) {
        fprintf(stderr, "用法: %s <model.gguf> <prompt> [n_predict] [--raw]\n", argv[0]);
        return 2;
    }
    const char * model_path = argv[1];
    const std::string user_prompt = argv[2];
    const int n_predict = argc > 3 ? atoi(argv[3]) : 64;
    // --raw: 不用 chat 模板，直接续写（base 模型的裸行为）
    const bool raw_mode = argc > 4 && strcmp(argv[4], "--raw") == 0;

    // llama.cpp 的加载日志刷屏，探针只关心自己的输出
    llama_log_set([](ggml_log_level, const char *, void *) {}, nullptr);

    llama_backend_init();

    auto mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;   // 模拟器/真机 CPU 上跑，不依赖 GPU 后端

    const double t0 = now_ms();
    llama_model * model = llama_model_load_from_file(model_path, mparams);
    if (model == nullptr) {
        fprintf(stderr, "[probe] FAIL: cannot load model\n");
        return 1;
    }
    const double t_load = now_ms() - t0;

    const llama_vocab * vocab = llama_model_get_vocab(model);
    printf("[probe] model loaded in %.0f ms, n_vocab=%d\n", t_load, llama_vocab_n_tokens(vocab));

    // 有 chat 模板就用 —— Qwen3 是 instruct 模型，裸提示词它不知道该"接着写"。
    //
    // 注意：C API 的 llama_chat_apply_template 不是 jinja 解析器，只匹配一份内置模板
    // 列表并硬编码输出，**没法传 enable_thinking=false**。所以 Qwen3 的思考块只能在
    // 输出端剥掉（见下面 skip_thinking）。
    std::string prompt = user_prompt;
    const char * tmpl = llama_model_chat_template(model, nullptr);
    if (!raw_mode && tmpl != nullptr) {
        const llama_chat_message msg = { "user", user_prompt.c_str() };
        std::vector<char> buf(user_prompt.size() * 2 + 1024);
        int n = llama_chat_apply_template(tmpl, &msg, 1, /*add_ass=*/true, buf.data(), (int) buf.size());
        if (n > (int) buf.size()) {
            buf.resize(n);
            n = llama_chat_apply_template(tmpl, &msg, 1, true, buf.data(), n);
        }
        if (n > 0) prompt.assign(buf.data(), n);
        printf("[probe] chat template applied\n");
    }

    auto cparams = llama_context_default_params();
    cparams.n_ctx = 512;
    cparams.n_batch = 128;
    cparams.n_threads = 4;
    cparams.n_threads_batch = 4;

    llama_context * ctx = llama_init_from_model(model, cparams);
    if (ctx == nullptr) {
        fprintf(stderr, "[probe] FAIL: cannot create context\n");
        return 1;
    }

    std::vector<llama_token> tokens(prompt.size() + 8);
    // chat 模板里已经带了 <|im_start|> 这些特殊标记，分词时不能再 add_special，
    // 否则会喂进去双重 BOS，模型一上来就吐结束符。
    const bool add_special = raw_mode;
    int n_tok = llama_tokenize(vocab, prompt.c_str(), (int) prompt.size(),
                               tokens.data(), (int) tokens.size(), add_special, true);
    if (n_tok < 0) {
        tokens.resize(-n_tok);
        n_tok = llama_tokenize(vocab, prompt.c_str(), (int) prompt.size(),
                               tokens.data(), (int) tokens.size(), add_special, true);
    }
    if (n_tok < 0) {
        fprintf(stderr, "[probe] FAIL: tokenize failed\n");
        return 1;
    }
    tokens.resize(n_tok);
    printf("[probe] prompt tokens=%d\n", n_tok);

    const double t1 = now_ms();
    if (llama_decode(ctx, llama_batch_get_one(tokens.data(), n_tok)) != 0) {
        fprintf(stderr, "[probe] FAIL: prefill decode failed\n");
        return 1;
    }
    const double t_prefill = now_ms() - t1;
    printf("[probe] prefill %.0f ms (%.1f tok/s)\n", t_prefill, n_tok / (t_prefill / 1000.0));

    // 链里必须挂 sampler —— 空链的 cur_p.selected 是 -1，采样时直接断言失败
    llama_sampler * chain = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(chain, llama_sampler_init_greedy());

    // 补全必须有停止串：没有的话模型会一路生成到 n_predict，延迟不可控。
    // <|im_end|> 是 Qwen 的轮次结束符，双换行是"写完一段"的自然边界。
    const std::vector<std::string> stops = { "<|im_end|>", "\n\n" };

    // 状态机：思考块内部的换行不能当停止串，否则会在 <think> 第一个换行处就截断，
    // 内容一个字都留不下。必须先越过 </think>，之后才开始判停止串。
    const std::string think_close = "</think";
    size_t content_from = std::string::npos;   // raw 中内容起始下标（</think> 那行之后）

    std::string raw;
    int n_gen = 0;
    int n_think = 0;
    bool stopped = false;
    const double t2 = now_ms();
    for (int i = 0; i < n_predict; i++) {
        const llama_token tok = llama_sampler_sample(chain, ctx, -1);
        if (llama_vocab_is_eog(vocab, tok)) break;

        char buf[256];
        const int n = llama_token_to_piece(vocab, tok, buf, sizeof(buf), 0, /*special=*/true);
        if (n > 0) raw.append(buf, n);
        n_gen++;

        if (llama_decode(ctx, llama_batch_get_one((llama_token *) &tok, 1)) != 0) {
            fprintf(stderr, "[probe] FAIL: decode at step %d\n", i);
            return 1;
        }

        if (content_from == std::string::npos) {
            const size_t tc = raw.find(think_close);
            if (tc == std::string::npos) { n_think = n_gen; continue; }
            const size_t after = tc + think_close.size();
            // 等 ">" 到齐
            const size_t gt = raw.find('>', after);
            if (gt == std::string::npos) { n_think = n_gen; continue; }
            content_from = gt + 1;
            // 紧跟着的那个换行属于思考块的排版，不算正文
            if (content_from < raw.size() && raw[content_from] == '\n') content_from++;
            continue;
        }

        for (const std::string & s : stops) {
            const size_t pos = raw.find(s, content_from);
            if (pos != std::string::npos) { raw.resize(pos); stopped = true; break; }
        }
        if (stopped) break;
    }
    const double t_gen = now_ms() - t2;

    // 剥掉 Qwen3 的思考块：C API 传不进 enable_thinking=false，
    // 只能在输出端去掉，否则补全建议里会混进一段思考过程。
    std::string content = (content_from != std::string::npos && content_from <= raw.size())
                        ? raw.substr(content_from) : raw;

    printf("[probe] ---\n");
    print_escaped("[probe] raw: ", raw);
    print_escaped("[probe] content: ", content);
    printf("[probe] decode: %d tokens in %.0f ms = %.2f tok/s%s\n",
           n_gen, t_gen, n_gen / (t_gen / 1000.0), stopped ? " (stopped)" : " (hit n_predict)");
    if (n_think > 0) printf("[probe] thinking overhead: %d tokens (~%.0f ms)\n", n_think, n_think * t_gen / (n_gen > 0 ? n_gen : 1));
    printf("[probe] load=%.0f ms prefill=%.0f ms\n", t_load, t_prefill);
    const long hwm = peak_rss_kb();
    if (hwm > 0) printf("[probe] peak RSS = %.0f MB\n", hwm / 1024.0);
    printf("[probe] RESULT: OK\n");

    llama_sampler_free(chain);
    llama_free(ctx);
    llama_model_free(model);
    llama_backend_free();
    return 0;
}
