// Dumps raw fp32 logits for a fixed token sequence.
//
// Compile the same source against two builds (a CPU oracle and a GPU fork) and
// compare the two dumps with compare_logits.py. Raw fp32 is the point: the
// perplexity tool's logits file stores fp16 log-probabilities, which is too
// coarse to resolve the difference this test looks for.

#include "llama.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

int main(int argc, char ** argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: %s MODEL OUT.bin PROMPT [N_TOKENS]\n", argv[0]);
        return 2;
    }

    const char *        model_path = argv[1];
    const char *        out_path   = argv[2];
    const std::string   prompt     = argv[3];
    const int           n_want     = argc > 4 ? atoi(argv[4]) : 16;

    llama_backend_init();

    struct llama_model_params mparams = llama_model_default_params();
    // inert in a build without a GPU backend; 0 gives the CPU-only control
    const char * ngl_env = getenv("PARITY_NGL");
    mparams.n_gpu_layers = ngl_env != NULL ? atoi(ngl_env) : 99;

    struct llama_model * model = llama_model_load_from_file(model_path, mparams);
    if (model == NULL) {
        fprintf(stderr, "logitprobe: failed to load %s\n", model_path);
        return 1;
    }

    const struct llama_vocab * vocab = llama_model_get_vocab(model);
    const int n_vocab = llama_vocab_n_tokens(vocab);

    std::vector<llama_token> toks(n_want + 32);
    int n = llama_tokenize(vocab, prompt.c_str(), (int) prompt.size(),
                           toks.data(), (int) toks.size(), false, false);
    if (n <= 0) {
        fprintf(stderr, "logitprobe: tokenize failed (%d)\n", n);
        return 1;
    }
    if (n > n_want) {
        n = n_want;
    }
    toks.resize(n);

    struct llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx     = 64;
    cparams.n_batch   = 64;
    cparams.n_ubatch  = 64;

    struct llama_context * ctx = llama_init_from_model(model, cparams);
    if (ctx == NULL) {
        fprintf(stderr, "logitprobe: failed to create context\n");
        return 1;
    }

    struct llama_batch batch = llama_batch_init(n, 0, 1);
    for (int i = 0; i < n; i++) {
        batch.token[i]     = toks[i];
        batch.pos[i]       = i;
        batch.n_seq_id[i]  = 1;
        batch.seq_id[i][0] = 0;
        batch.logits[i]    = 1;  // logits at every position, not just the last
    }
    batch.n_tokens = n;

    if (llama_decode(ctx, batch) != 0) {
        fprintf(stderr, "logitprobe: decode failed\n");
        return 1;
    }

    FILE * f = fopen(out_path, "wb");
    if (f == NULL) {
        fprintf(stderr, "logitprobe: cannot write %s\n", out_path);
        return 1;
    }

    fwrite("LOGP", 1, 4, f);
    fwrite(&n_vocab, sizeof(int), 1, f);
    fwrite(&n,       sizeof(int), 1, f);
    fwrite(toks.data(), sizeof(llama_token), n, f);
    for (int i = 0; i < n; i++) {
        float * logits = llama_get_logits_ith(ctx, i);
        if (logits == NULL) {
            fprintf(stderr, "logitprobe: no logits at position %d\n", i);
            return 1;
        }
        fwrite(logits, sizeof(float), n_vocab, f);
    }
    fclose(f);

    printf("tokens (%d):", n);
    for (int i = 0; i < n; i++) {
        printf(" %d", toks[i]);
    }
    printf("\nn_vocab: %d\nwrote: %s\n", n_vocab, out_path);

    llama_batch_free(batch);
    llama_free(ctx);
    llama_model_free(model);
    llama_backend_free();

    return 0;
}
