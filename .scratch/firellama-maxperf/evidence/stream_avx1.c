#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>
#include <time.h>
#include <math.h>
#include <immintrin.h>

#define N_ELEMENTS (128 * 1024 * 1024)  // 128M elements
#define N_THREADS_MAX 24
#define N_RUNS 10
#define N_BENCHMARK_RUNS 3

// Thread arguments
typedef struct {
    int thread_id;
    int num_threads;
    double *a;
    double *b;
    double *c;
    double scalar;
    int kernel_type;  // 0=Copy, 1=Scale, 2=Add, 3=Triad, 4=ReadOnlySum
    double *result_sum;  // For read-only sum
} thread_args_t;

// Global arrays
static double *a = NULL;
static double *b = NULL;
static double *c = NULL;

// Timing
static double get_time() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

// Kernel implementations using AVX (256-bit, 4 doubles per vector)
static void kernel_copy(int start, int end, double *a, double *b) {
    int i = start;
    // Vectorized portion
    for (; i + 3 < end; i += 4) {
        __m256d vb = _mm256_loadu_pd(&b[i]);
        _mm256_storeu_pd(&a[i], vb);
    }
    // Scalar remainder
    for (; i < end; i++) {
        a[i] = b[i];
    }
}

static void kernel_scale(int start, int end, double *a, double *b, double scalar) {
    int i = start;
    __m256d vs = _mm256_set1_pd(scalar);
    for (; i + 3 < end; i += 4) {
        __m256d vb = _mm256_loadu_pd(&b[i]);
        __m256d va = _mm256_mul_pd(vs, vb);
        _mm256_storeu_pd(&a[i], va);
    }
    for (; i < end; i++) {
        a[i] = scalar * b[i];
    }
}

static void kernel_add(int start, int end, double *a, double *b, double *c) {
    int i = start;
    for (; i + 3 < end; i += 4) {
        __m256d vb = _mm256_loadu_pd(&b[i]);
        __m256d vc = _mm256_loadu_pd(&c[i]);
        __m256d va = _mm256_add_pd(vb, vc);
        _mm256_storeu_pd(&a[i], va);
    }
    for (; i < end; i++) {
        a[i] = b[i] + c[i];
    }
}

static void kernel_triad(int start, int end, double *a, double *b, double *c, double scalar) {
    int i = start;
    __m256d vs = _mm256_set1_pd(scalar);
    for (; i + 3 < end; i += 4) {
        __m256d vc = _mm256_loadu_pd(&c[i]);
        __m256d vb = _mm256_loadu_pd(&b[i]);
        __m256d va = _mm256_add_pd(vb, _mm256_mul_pd(vs, vc));  // a = b + s*c
        _mm256_storeu_pd(&a[i], va);
    }
    for (; i < end; i++) {
        a[i] = b[i] + scalar * c[i];
    }
}

static double kernel_readonly_sum(int start, int end, double *b) {
    double sum = 0.0;
    int i = start;
    __m256d vsum = _mm256_setzero_pd();
    for (; i + 3 < end; i += 4) {
        __m256d vb = _mm256_loadu_pd(&b[i]);
        vsum = _mm256_add_pd(vsum, vb);
    }
    // Horizontal sum of vsum
    double tmp[4];
    _mm256_storeu_pd(tmp, vsum);
    sum = tmp[0] + tmp[1] + tmp[2] + tmp[3];
    // Scalar remainder
    for (; i < end; i++) {
        sum += b[i];
    }
    return sum;
}

void *thread_func(void *arg) {
    thread_args_t *t = (thread_args_t *)arg;
    int n = N_ELEMENTS;
    int chunk = n / t->num_threads;
    int start = t->thread_id * chunk;
    int end = (t->thread_id == t->num_threads - 1) ? n : start + chunk;

    switch (t->kernel_type) {
        case 0: // Copy
            kernel_copy(start, end, t->a, t->b);
            break;
        case 1: // Scale
            kernel_scale(start, end, t->a, t->b, t->scalar);
            break;
        case 2: // Add
            kernel_add(start, end, t->a, t->b, t->c);
            break;
        case 3: // Triad
            kernel_triad(start, end, t->a, t->b, t->c, t->scalar);
            break;
        case 4: // ReadOnlySum
            *(t->result_sum) = kernel_readonly_sum(start, end, t->b);
            break;
    }
    return NULL;
}

double run_kernel(int kernel_type, int num_threads, double scalar, double *out_sum) {
    pthread_t threads[N_THREADS_MAX];
    thread_args_t args[N_THREADS_MAX];
    double start_time, end_time;
    double best_time = 1e30;
    double total_time = 0.0;
    int valid_runs = 0;

    for (int run = 0; run < N_RUNS; run++) {
        start_time = get_time();
        
        for (int t = 0; t < num_threads; t++) {
            args[t].thread_id = t;
            args[t].num_threads = num_threads;
            args[t].a = a;
            args[t].b = b;
            args[t].c = c;
            args[t].scalar = scalar;
            args[t].kernel_type = kernel_type;
            args[t].result_sum = out_sum;
            pthread_create(&threads[t], NULL, thread_func, &args[t]);
        }
        
        for (int t = 0; t < num_threads; t++) {
            pthread_join(threads[t], NULL);
        }
        
        end_time = get_time();
        double elapsed = end_time - start_time;
        
        if (run == 0) {
            // Discard first run (warmup)
            continue;
        }
        
        valid_runs++;
        total_time += elapsed;
        if (elapsed < best_time) best_time = elapsed;
    }
    
    // Return best time (we'll compute GB/s in main)
    return best_time;
}

double run_kernel_mean(int kernel_type, int num_threads, double scalar, double *out_sum) {
    pthread_t threads[N_THREADS_MAX];
    thread_args_t args[N_THREADS_MAX];
    double start_time, end_time;
    double total_time = 0.0;
    int valid_runs = 0;

    for (int run = 0; run < N_RUNS; run++) {
        start_time = get_time();
        
        for (int t = 0; t < num_threads; t++) {
            args[t].thread_id = t;
            args[t].num_threads = num_threads;
            args[t].a = a;
            args[t].b = b;
            args[t].c = c;
            args[t].scalar = scalar;
            args[t].kernel_type = kernel_type;
            args[t].result_sum = out_sum;
            pthread_create(&threads[t], NULL, thread_func, &args[t]);
        }
        
        for (int t = 0; t < num_threads; t++) {
            pthread_join(threads[t], NULL);
        }
        
        end_time = get_time();
        double elapsed = end_time - start_time;
        
        if (run == 0) {
            // Discard first run (warmup)
            continue;
        }
        
        valid_runs++;
        total_time += elapsed;
    }
    
    return total_time / valid_runs;
}

// Initialize arrays with first-touch policy
void init_arrays(int num_threads) {
    pthread_t threads[N_THREADS_MAX];
    thread_args_t args[N_THREADS_MAX];
    
    for (int t = 0; t < num_threads; t++) {
        args[t].thread_id = t;
        args[t].num_threads = num_threads;
        args[t].a = a;
        args[t].b = b;
        args[t].c = c;
        args[t].scalar = 0.0;
        args[t].kernel_type = 0;  // Use copy kernel for init (a = b)
        args[t].result_sum = NULL;
        pthread_create(&threads[t], NULL, thread_func, &args[t]);
    }
    
    for (int t = 0; t < num_threads; t++) {
        pthread_join(threads[t], NULL);
    }
    
    // Now initialize b and c with different values
    for (int t = 0; t < num_threads; t++) {
        int n = N_ELEMENTS;
        int chunk = n / num_threads;
        int start = t * chunk;
        int end = (t == num_threads - 1) ? n : start + chunk;
        for (int i = start; i < end; i++) {
            b[i] = 1.0;
            c[i] = 2.0;
        }
    }
}

int main() {
    printf("STREAM-style Memory Bandwidth Benchmark (AVX1)\n");
    printf("==============================================\n");
    printf("Elements per array: %d (%.2f GiB per array)\n", N_ELEMENTS, (double)N_ELEMENTS * 8 / (1024*1024*1024));
    printf("Total memory: %.2f GiB\n\n", 3.0 * (double)N_ELEMENTS * 8 / (1024*1024*1024));
    
    // Allocate aligned memory
    size_t bytes = N_ELEMENTS * sizeof(double);
    a = (double *)aligned_alloc(64, bytes);
    b = (double *)aligned_alloc(64, bytes);
    c = (double *)aligned_alloc(64, bytes);
    
    if (!a || !b || !c) {
        fprintf(stderr, "Failed to allocate memory\n");
        return 1;
    }
    
    // Check for heavy processes
    printf("Checking for heavy processes...\n");
    FILE *fp = popen("pgrep -fl 'llama-server|llama-quantize'", "r");
    if (fp) {
        char line[256];
        int found = 0;
        while (fgets(line, sizeof(line), fp)) {
            printf("  Found: %s", line);
            found = 1;
        }
        pclose(fp);
        if (found) {
            printf("Heavy processes running. Stopping.\n");
            return 1;
        }
    }
    printf("  No heavy processes found.\n\n");
    
    const char *kernel_names[4] = {"Copy", "Scale", "Add", "Triad"};
    int bytes_per_elem[4] = {16, 16, 24, 24};
    int thread_counts[4] = {1, 6, 12, 24};
    double scalar = 3.14159;
    
    // Storage for 3 benchmark runs
    double run_results[3][4][4];  // [run][kernel][thread_idx] = mean GB/s
    double run_best[3][4][4];     // [run][kernel][thread_idx] = best GB/s
    double readonly_sums[3];
    double readonly_means[3];
    double readonly_bests[3];
    
    double total_wall_start = get_time();
    
    for (int bench_run = 0; bench_run < N_BENCHMARK_RUNS; bench_run++) {
        printf("=== Benchmark Run %d ===\n", bench_run + 1);
        
        for (int tc_idx = 0; tc_idx < 4; tc_idx++) {
            int num_threads = thread_counts[tc_idx];
            
            // First-touch initialization with this thread count
            init_arrays(num_threads);
            
            for (int k = 0; k < 4; k++) {
                double best_time = run_kernel(k, num_threads, scalar, NULL);
                double mean_time = run_kernel_mean(k, num_threads, scalar, NULL);
                
                double bytes = (double)N_ELEMENTS * bytes_per_elem[k];
                double best_gbs = bytes / best_time / 1e9;
                double mean_gbs = bytes / mean_time / 1e9;
                
                run_best[bench_run][k][tc_idx] = best_gbs;
                run_results[bench_run][k][tc_idx] = mean_gbs;
                
                printf("  %s @ %2d threads: best = %.3f GB/s, mean = %.3f GB/s\n",
                       kernel_names[k], num_threads, best_gbs, mean_gbs);
            }
        }
        
        // Read-only sum at 12 threads
        init_arrays(12);
        double sum = 0.0;
        double best_time = run_kernel(4, 12, scalar, &sum);
        double mean_time = run_kernel_mean(4, 12, scalar, &sum);
        
        double bytes_ro = (double)N_ELEMENTS * 8;
        readonly_bests[bench_run] = bytes_ro / best_time / 1e9;
        readonly_means[bench_run] = bytes_ro / mean_time / 1e9;
        readonly_sums[bench_run] = sum;
        
        printf("  ReadOnlySum @ 12 threads: best = %.3f GB/s, mean = %.3f GB/s (sum=%.6f)\n",
               readonly_bests[bench_run], readonly_means[bench_run], sum);
        printf("\n");
    }
    
    double total_wall_end = get_time();
    double total_wall_time = total_wall_end - total_wall_start;
    
    // Print summary tables
    printf("==============================================\n");
    printf("SUMMARY TABLES\n");
    printf("==============================================\n\n");
    
    for (int bench_run = 0; bench_run < N_BENCHMARK_RUNS; bench_run++) {
        printf("--- Run %d ---\n", bench_run + 1);
        printf("%-12s", "Kernel");
        for (int tc_idx = 0; tc_idx < 4; tc_idx++) {
            printf("  %2dT Best  %2dT Mean", thread_counts[tc_idx], thread_counts[tc_idx]);
        }
        printf("\n");
        
        for (int k = 0; k < 4; k++) {
            printf("%-12s", kernel_names[k]);
            for (int tc_idx = 0; tc_idx < 4; tc_idx++) {
                printf("  %8.3f  %8.3f", run_best[bench_run][k][tc_idx], run_results[bench_run][k][tc_idx]);
            }
            printf("\n");
        }
        printf("  ReadOnlySum @ 12T: best = %.3f GB/s, mean = %.3f GB/s\n\n",
               readonly_bests[bench_run], readonly_means[bench_run]);
    }
    
    // Statistics across 3 runs at 12 threads
    printf("--- Statistics across 3 runs (12 threads) ---\n");
    printf("%-12s  %8s  %8s\n", "Kernel", "Mean GB/s", "StdDev");
    
    for (int k = 0; k < 4; k++) {
        double vals[3];
        for (int r = 0; r < 3; r++) {
            vals[r] = run_results[r][k][2];  // 12 threads is index 2
        }
        double mean = (vals[0] + vals[1] + vals[2]) / 3.0;
        double variance = 0.0;
        for (int r = 0; r < 3; r++) {
            double diff = vals[r] - mean;
            variance += diff * diff;
        }
        variance /= 2.0;  // sample stddev
        double stddev = sqrt(variance);
        printf("%-12s  %8.3f  %8.3f\n", kernel_names[k], mean, stddev);
    }
    
    // Read-only sum stats
    double ro_vals[3] = {readonly_means[0], readonly_means[1], readonly_means[2]};
    double ro_mean = (ro_vals[0] + ro_vals[1] + ro_vals[2]) / 3.0;
    double ro_var = 0.0;
    for (int r = 0; r < 3; r++) {
        double diff = ro_vals[r] - ro_mean;
        ro_var += diff * diff;
    }
    ro_var /= 2.0;
    double ro_stddev = sqrt(ro_var);
    printf("%-12s  %8.3f  %8.3f\n", "ReadOnlySum", ro_mean, ro_stddev);
    
    printf("\nTotal wall time: %.1f seconds\n", total_wall_time);
    
    // Cleanup
    free(a);
    free(b);
    free(c);
    
    return 0;
}