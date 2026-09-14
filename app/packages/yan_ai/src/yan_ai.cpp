// 端侧补全的原生桥接层。
//
// 与探针的区别：探针是一次性验证程序，这里是给应用长期调用的库。
// 因此模型与会话必须能复用 —— 每次补全都重新加载 378 MB 模型是不可接受的。
//
// 线程模型：所有调用都阻塞直到完成，由 Dart 侧放到独立 isolate 里跑；
// yan_ai_cancel 可以从其它线程调用以打断生成。

#include "yan_ai.h"

#include "llama.h"

#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <time.h>

namespace {

double now_ms() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

// 生成结束的原因。命中哪个停止条件对上层调参很重要，所以要区分开。
enum class StopReason { Eog, StopString, Repeat, MaxTokens, Cancelled, Error };

const char * stop_reason_name(StopReason r) {
    switch (r) {
        case StopReason::Eog:        return "eog";
        case StopReason::StopString: return "stop";
        case StopReason::Repeat:     return "repeat";
        case StopReason::MaxTokens:  return "max";
        case StopReason::Cancelled:  return "cancelled";
        default:                     return "error";
    }
}

struct Session {
    llama_model *   model = nullptr;
    llama_context * ctx   = nullptr;
    const llama_vocab * vocab = nullptr;
    llama_sampler * chain = nullptr;
    int n_ctx = 0;
};

std::mutex g_mutex;              // 保护会话生命周期（load/unload）
Session *  g_session = nullptr;
volatile bool g_cancel = false;
double g_last_repeat_ratio = 0.0;   // 供诊断：为什么触发/未触发复读检测

// 需要带上具体路径的错误信息在这里拼。
// YanAiError::message 是 const char *（约定指向静态存储），所以这个缓冲必须是
// 静态生命周期 —— 指回栈上的局部数组会立刻变成悬垂指针。
char g_err_buf[256] = { 0 };

}  // namespace

extern "C" {

int yan_ai_load(const char * model_path, const YanAiConfig * cfg, YanAiError * err) {
    if (err) { err->code = 0; err->message = ""; }
    if (model_path == nullptr) {
        if (err) { err->code = 1; err->message = "模型路径为空"; }
        return 1;
    }

    std::lock_guard<std::mutex> lock(g_mutex);

    YanAiConfig local = { 512, 128, 4, 0 };
    if (cfg != nullptr) local = *cfg;

    llama_log_set([](ggml_log_level, const char *, void *) {}, nullptr);
    llama_backend_init();

    auto mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;

    llama_model * model = llama_model_load_from_file(model_path, mparams);
    if (model == nullptr) {
        if (err) {
            err->code = 2;
            snprintf(g_err_buf, sizeof(g_err_buf), "模型加载失败：%s", model_path);
            err->message = g_err_buf;
        }
        return 2;
    }

    auto cparams = llama_context_default_params();
    cparams.n_ctx           = local.n_ctx > 0 ? local.n_ctx : 512;
    cparams.n_batch         = local.n_batch > 0 ? local.n_batch : 128;
    cparams.n_threads       = local.n_threads > 0 ? local.n_threads : 4;
    cparams.n_threads_batch = cparams.n_threads;

    llama_context * ctx = llama_init_from_model(model, cparams);
    if (ctx == nullptr) {
        llama_model_free(model);
        if (err) { err->code = 3; err->message = "上下文创建失败"; }
        return 3;
    }

    auto * s = new Session();
    s->model = model;
    s->ctx   = ctx;
    s->vocab = llama_model_get_vocab(model);
    s->n_ctx = cparams.n_ctx;
    s->chain = llama_sampler_chain_init(llama_sampler_chain_default_params());
    // 采样链必须至少有一个 sampler：空链的 cur_p.selected 是 -1，采样时直接断言崩溃
    llama_sampler_chain_add(s->chain, llama_sampler_init_greedy());

    g_session = s;
    g_cancel  = false;
    return 0;
}

void yan_ai_unload(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_session == nullptr) return;
    llama_sampler_free(g_session->chain);
    llama_free(g_session->ctx);
    llama_model_free(g_session->model);
    delete g_session;
    g_session = nullptr;
    llama_backend_free();
}

int yan_ai_is_loaded(void) { return g_session != nullptr ? 1 : 0; }

void yan_ai_cancel(void) { g_cancel = true; }

// 检测小模型的复读。
//
// 两种复读形态都要覆盖，实测都遇到过：
//   1. 连续重复同一小段 —— `Markdown+CSS、Markdown+CSS、…`
//   2. **递增式**复读 —— `Markdown+CSS、Markdown+XML、Markdown+HTML、Markdown+CSS+XML、…`
//      每次都拼一个新组合，末尾并不重复，所以只做"末尾比对"是抓不到的（踩过）。
//
// 递增式靠**片段复用率**抓：把输出切成小片，统计有多少片在之前出现过。
// 自然语言里 4 字片段重复率很低，复读时会迅速升高。
static bool detect_repeat(const std::string & s, double * ratio_out = nullptr) {
    const size_t n = s.size();
    if (n < 24) { if (ratio_out) *ratio_out = 0.0; return false; }

    // 形态 1：末尾连续重复同一小段
    for (size_t unit = 4; unit <= n / 3; unit++) {
        bool same = true;
        for (size_t r = 1; r < 3 && same; r++) {
            for (size_t i = 0; i < unit; i++) {
                if (s[n - 1 - i] != s[n - 1 - i - unit * r]) { same = false; break; }
            }
        }
        if (same) { if (ratio_out) *ratio_out = 1.0; return true; }
    }

    // 形态 2：片段复用率过高
    const size_t grain = 4;
    if (n < grain * 6) { if (ratio_out) *ratio_out = 0.0; return false; }
    size_t total = 0, dup = 0;
    for (size_t i = 0; i + grain <= n; i += grain) {
        const std::string cur = s.substr(i, grain);
        total++;
        if (s.find(cur) < i) dup++;
    }
    const double ratio = total > 0 ? (double) dup / (double) total : 0.0;
    if (ratio_out) *ratio_out = ratio;
    return total >= 6 && ratio >= 0.75;
}

int yan_ai_complete(const char * prefix, const YanAiParams * p,
                    char * out_buf, int out_cap,
                    YanAiTokenFn on_token, void * user, YanAiError * err) {
    if (err) { err->code = 0; err->message = ""; }
    if (out_buf != nullptr && out_cap > 0) out_buf[0] = '\0';
    if (g_session == nullptr) {
        if (err) { err->code = 10; err->message = "模型未加载"; }
        return 10;
    }
    if (prefix == nullptr) prefix = "";

    // 默认 24：这个量级是"一条建议"，不是"一段文章"。
    // 实测 0.6B 在自由续写时会进入递增式复读（每次拼一个新组合），
    // 而**这种复读的片段复用率并不高**（实测只有 0.30–0.46），
    // 靠复读度量抓不住。所以真正的防线是**有界预算 + 停止串**，
    // 复读检测只作为兜底。详见 docs/on-device-ai-probe.md。
    YanAiParams local = { 24, 6, 0, 0 };
    if (p != nullptr) local = *p;
    if (local.max_tokens <= 0) local.max_tokens = 24;

    Session * s = g_session;
    g_cancel = false;
    g_last_repeat_ratio = 0.0;

    // 每次补全都清空 KV 缓存：补全的上下文是"光标前的文字"，
    // 与上次请求的公共前缀不一定重合，缓存复用要处理前缀回滚，
    // 复杂度换不来收益 —— 实测 prefill 约 38 tok/s，短前缀代价可接受。
    llama_memory_clear(llama_get_memory(s->ctx), true);

    const std::string text(prefix);
    std::vector<llama_token> tokens(text.size() + 8);
    // 裸续写：补全的输入是"文档里已有的半句话"，不是给助手的指令，
    // 套 chat 模板反而会引入 Qwen3 的思考块（实测吃掉 3-6 秒）。
    int n_tok = llama_tokenize(s->vocab, text.c_str(), (int) text.size(),
                               tokens.data(), (int) tokens.size(), true, false);
    if (n_tok < 0) {
        tokens.resize(-n_tok);
        n_tok = llama_tokenize(s->vocab, text.c_str(), (int) text.size(),
                               tokens.data(), (int) tokens.size(), true, false);
    }
    if (n_tok <= 0) {
        if (err) { err->code = 11; err->message = "分词失败"; }
        return 11;
    }
    tokens.resize(n_tok);

    // 前缀超长时只保留尾部：补全只关心光标附近
    const int budget = s->n_ctx - local.max_tokens - 8;
    if (budget > 0 && n_tok > budget) {
        tokens.erase(tokens.begin(), tokens.begin() + (n_tok - budget));
        n_tok = budget;
    }

    if (llama_decode(s->ctx, llama_batch_get_one(tokens.data(), n_tok)) != 0) {
        if (err) { err->code = 12; err->message = "prefill 失败"; }
        return 12;
    }

    // 停止串按光标所在行的形态选。判据用行的开头字符，比整段前缀更贴合意图。
    //
    // - **结构化行**（表格 / 列表 / 引用 / 标题）：下一个换行就是边界，一条建议补一行。
    //   试过对表格改以 `|` 为界 —— 模型在 ` Linux | 已发布 |` 的第一个竖线就命中，
    //   只得到 ` Linux`，真实内容被截掉，所以表格也用换行。
    // - **普通段落**：靠换行收尾会让建议长到没法用，应在句子边界收。
    //
    // 注意实测的一点：0.6B 写表格行时**经常不输出行尾的 `|`**，
    // 于是建议是个残缺的表格行。提示工程没能稳定修好它，
    // 所以改在上层做建议校验（见 Dart 侧的 suggestionLooksValid）。
    const size_t last_nl = text.rfind('\n');
    const std::string cur_line = (last_nl == std::string::npos) ? text : text.substr(last_nl + 1);
    const bool structured = !cur_line.empty() &&
                            (cur_line[0] == '|' || cur_line[0] == '-' || cur_line[0] == '*' ||
                             cur_line[0] == '+' || cur_line[0] == '>' || cur_line[0] == '#' ||
                             (cur_line.size() > 1 && cur_line[0] >= '0' && cur_line[0] <= '9' && cur_line[1] == '.'));

    std::vector<std::string> stops;
    if (structured) {
        stops = { "\n" };
    } else {
        stops = { "\n", "。", "！", "？", "；", "…" };
    }

    // 已确认属于最终结果、可以交付给调用方的文本。
    std::string out;
    // 刚生成、尚未确认的片段。停止串可能跨在它与前文之间，所以先押一步。
    std::string pending;
    bool cancelled_by_callback = false;
    StopReason reason = StopReason::MaxTokens;
    int n_gen = 0;

    for (int i = 0; i < local.max_tokens; i++) {
        if (g_cancel) { reason = StopReason::Cancelled; break; }

        const llama_token tok = llama_sampler_sample(s->chain, s->ctx, -1);
        if (llama_vocab_is_eog(s->vocab, tok)) { reason = StopReason::Eog; break; }

        char buf[256];
        const int n = llama_token_to_piece(s->vocab, tok, buf, sizeof(buf), 0, false);
        if (n > 0) {
            pending.append(buf, n);
            n_gen++;
        }

        if (llama_decode(s->ctx, llama_batch_get_one((llama_token *) &tok, 1)) != 0) {
            reason = StopReason::Error;
            break;
        }

        // 停止串：没有它生成会一路跑到上限，延迟不可控。
        //
        // 判据是"把 pending 并进来之后会不会出现停止串"：
        // 若会，说明 pending 正是边界那一段，不并入、直接收工。
        // 反过来（先并入再查）多发一个 token 才停，`\n` 这种单字符停止串会多带一个换行。
        const std::string merged = out + pending;
        bool hit = false;
        for (const std::string & st : stops) {
            if (merged.find(st) != std::string::npos) { hit = true; break; }
        }
        if (hit && !out.empty()) { reason = StopReason::StopString; break; }

        // 这一步没有命中停止串，前面的 pending 才算数。
        //
        // 为什么押这一步：回调与 out 缓冲必须给出**完全一样**的文本。
        // 先前是"立刻回调、之后才按停止串截断 out"，结果两者长度不同 ——
        // 停止串会落在已经吐出去的那部分里，调用方看到的比真值多。
        if (!pending.empty()) {
            out += pending;
            if (on_token != nullptr) {
                if (on_token(pending.data(), (int) pending.size(), user) != 0) {
                    cancelled_by_callback = true;
                    reason = StopReason::Cancelled;
                    break;
                }
            }
            pending.clear();
        }

        // 复读检测每 4 个 token 跑一次：它要遍历整段输出，每步都跑是浪费；
        // 而漏检 3 个 token 对补全没有影响。
        if (i % 4 == 3) {
            double ratio = 0.0;
            if (detect_repeat(out, &ratio)) { reason = StopReason::Repeat; break; }
            g_last_repeat_ratio = ratio;
        }
    }

    // 回调主动取消时，那段尚未交付的内容要算进结果里 —— 回调已经看到它了
    if (cancelled_by_callback && !pending.empty()) {
        out += pending;
        pending.clear();
    }

    // 把结果交给调用方。缓冲区由调用方提供，保证 NUL 结尾；
    // 截断时保留边界（宁可少给几个字，也不能写出界）。
    if (out_buf != nullptr && out_cap > 0) {
        const int n = (int) out.size() < out_cap - 1 ? (int) out.size() : out_cap - 1;
        if (n > 0) memcpy(out_buf, out.data(), (size_t) n);
        out_buf[n > 0 ? n : 0] = '\0';
    }

    if (err) err->message = stop_reason_name(reason);
    return (int) reason;
}

double yan_ai_last_repeat_ratio(void) { return g_last_repeat_ratio; }

}  // extern "C"
