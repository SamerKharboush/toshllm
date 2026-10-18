// Reads one Metal function's threadgroup memory request and prints it beside the
// device's ceiling, so the request and the driver's wording are never conflated.
//
// kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64 is present in fa.metallib by
// every string check and is still refused by newComputePipelineStateWithFunction
// with the driver's own wording "exceed the local data storage limit". That string
// is the driver's, not Apple's; Metal words the same condition as "Threadgroup
// memory size (N) exceeds the maximum threadgroup memory allowed (M)". This probe
// prints the number it can measure and the fault lines verbatim, and never
// paraphrases one as the other.
//
// Metal reports a pipeline's static threadgroup bytes only through a pipeline state
// that was built. A refused pipeline has no state, so on that path the byte count is
// reported as unavailable and only the driver's own claim about the ceiling stands.
//
// fa.metal says sh_acc needs about 33 KB on 64 lanes and ships _lds32 twins for it.
// Point argv[3] at kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_lds32 to get a
// byte count from a sibling that builds; that is a different kernel's request, not
// this one's, and the two must not be reported as one number.
//
// build: clang -fobjc-arc -framework Foundation -framework Metal -o threadgroupprobe threadgroupprobe.m
// run:   export GGML_METAL_DEVICES=2 GGML_METAL_VRAM_RESERVE_MB=1024 GGML_METAL_SIMDGROUP_REDUCTION_DISABLE=1
//        ./threadgroupprobe 2
//
// args, each also settable by environment variable, argument wins:
//   argv[1] device index  LDS_PROBE_DEVICE     default 2
//   argv[2] metallib      LDS_PROBE_METALLIB   default <exe dir>/../../vendor/llama.cpp/build-static/bin/kernels/fa.metallib
//   argv[3] function      LDS_PROBE_FUNCTION   default kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64
//
// exit: 0 pipeline built, 3 pipeline refused (the measurement is still printed), 2 probe error
//
// output: one key=value per line, in the order printed. Multi-line error text is
// split into driver_error_line[i] rather than escaped, so every byte survives a diff.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static NSString * env_str(const char * name) {
    const char * v = getenv(name);
    return (v != NULL && v[0] != '\0') ? @(v) : nil;
}

static NSString * default_metallib(void) {
    NSString * exe = [[NSBundle mainBundle] executablePath];
    if (exe == nil) {
        return nil;
    }
    NSString * dir  = [[exe stringByDeletingLastPathComponent] stringByStandardizingPath];
    NSString * root = [[dir stringByAppendingPathComponent:@"../.."] stringByStandardizingPath];
    return [root stringByAppendingPathComponent:@"vendor/llama.cpp/build-static/bin/kernels/fa.metallib"];
}

static void print_lines(const char * key, NSString * text) {
    NSArray<NSString *> * lines = [text componentsSeparatedByString:@"\n"];
    for (NSUInteger i = 0; i < lines.count; i++) {
        printf("%s[%lu]=%s\n", key, (unsigned long) i, [lines[i] UTF8String]);
    }
}

int main(int argc, char ** argv) {
    @autoreleasepool {
        NSString * dev_str  = argc > 1 ? @(argv[1]) : env_str("LDS_PROBE_DEVICE");
        NSString * lib_path = argc > 2 ? @(argv[2]) : env_str("LDS_PROBE_METALLIB");
        NSString * fn_name  = argc > 3 ? @(argv[3]) : env_str("LDS_PROBE_FUNCTION");
        if (lib_path == nil) {
            lib_path = default_metallib();
        }
        if (fn_name == nil) {
            fn_name = @"kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64";
        }
        long dev_index = dev_str != nil ? strtol([dev_str UTF8String], NULL, 10) : 2;

        printf("probe=threadgroup-memory-request\n");

        NSArray<id<MTLDevice>> * devs = MTLCopyAllDevices();
        printf("device_count=%lu\n", (unsigned long) devs.count);
        for (NSUInteger i = 0; i < devs.count; i++) {
            printf("device[%lu]=%s\n", (unsigned long) i, [[devs[i] name] UTF8String]);
        }
        if (dev_index < 0 || (NSUInteger) dev_index >= devs.count) {
            fprintf(stderr, "probe error: device index %ld is out of range 0..%lu; "
                            "refusing to measure a device that was not asked for\n",
                    dev_index, (unsigned long) devs.count - 1);
            return 2;
        }
        id<MTLDevice> dev = devs[dev_index];
        const NSUInteger ceiling = dev.maxThreadgroupMemoryLength;

        printf("device_index=%ld\n", dev_index);
        printf("device_name=%s\n", [[dev name] UTF8String]);
        printf("device_max_threadgroup_memory_length_bytes=%lu\n", (unsigned long) ceiling);
        printf("metallib=%s\n", [lib_path UTF8String]);
        printf("function=%s\n", [fn_name UTF8String]);

        NSError * err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithURL:[NSURL fileURLWithPath:lib_path] error:&err];
        if (lib == nil) {
            printf("metallib_loaded=NO\n");
            printf("library_error_domain=%s\n", [[err domain] UTF8String]);
            printf("library_error_code=%ld\n", (long) [err code]);
            print_lines("library_error_line", [err description]);
            fprintf(stderr, "probe error: cannot load metallib %s\n", [lib_path UTF8String]);
            return 2;
        }
        printf("metallib_loaded=YES\n");

        id<MTLFunction> fn = [lib newFunctionWithName:fn_name];
        if (fn == nil) {
            printf("function_found=NO\n");
            fprintf(stderr, "probe error: %s has no function named %s\n",
                    [lib_path UTF8String], [fn_name UTF8String]);
            return 2;
        }
        printf("function_found=YES\n");

        MTLComputePipelineReflection * refl = nil;
        id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithFunction:fn
                                             options:MTLPipelineOptionBindingInfo
                                          reflection:&refl
                                               error:&err];

        // The request is everything the kernel declares it needs: the static
        // allocations the pipeline state reports, plus its threadgroup bindings.
        NSUInteger bindings = 0, dynamic = 0;
        if (refl != nil) {
            for (id<MTLBinding> b in refl.bindings) {
                if (b.type != MTLBindingTypeThreadgroupMemory) {
                    continue;
                }
                id<MTLThreadgroupBinding> tb = (id<MTLThreadgroupBinding>) b;
                printf("threadgroup_binding[%lu]=index=%lu name=%s bytes=%lu alignment_bytes=%lu\n",
                       (unsigned long) bindings, (unsigned long) b.index, [[b name] UTF8String],
                       (unsigned long) tb.threadgroupMemoryDataSize,
                       (unsigned long) tb.threadgroupMemoryAlignment);
                dynamic += tb.threadgroupMemoryDataSize;
                bindings++;
            }
        }

        if (ps != nil) {
            const NSUInteger req = ps.staticThreadgroupMemoryLength + dynamic;
            printf("pipeline_build=OK\n");
            printf("pipeline_static_threadgroup_memory_bytes=%lu\n", (unsigned long) ps.staticThreadgroupMemoryLength);
            printf("pipeline_threadgroup_bindings=%lu\n", (unsigned long) bindings);
            printf("pipeline_dynamic_threadgroup_memory_bytes=%lu\n", (unsigned long) dynamic);
            printf("pipeline_requested_threadgroup_memory_bytes=%lu\n", (unsigned long) req);
            printf("pipeline_requested_threadgroup_memory_source=MTLComputePipelineState.staticThreadgroupMemoryLength+MTLThreadgroupBinding.threadgroupMemoryDataSize\n");
            printf("request_exceeds_device_ceiling=%s\n", req > ceiling ? "YES" : "NO");
            printf("thread_execution_width=%lu\n", (unsigned long) ps.threadExecutionWidth);
            printf("max_total_threads_per_threadgroup=%lu\n", (unsigned long) ps.maxTotalThreadsPerThreadgroup);
        } else {
            printf("pipeline_build=REFUSED\n");
            printf("pipeline_static_threadgroup_memory_bytes=unavailable\n");
            printf("pipeline_threadgroup_bindings=unavailable\n");
            printf("pipeline_dynamic_threadgroup_memory_bytes=unavailable\n");
            printf("pipeline_requested_threadgroup_memory_bytes=unavailable\n");
            printf("pipeline_requested_threadgroup_memory_source=refused_pipeline_has_no_state\n");
            printf("request_exceeds_device_ceiling=UNKNOWN\n");
        }

        if (err != nil) {
            printf("driver_error_domain=%s\n", [[err domain] UTF8String]);
            printf("driver_error_code=%ld\n", (long) [err code]);
            print_lines("driver_error_line", [err description]);
            NSDictionary * info = [err userInfo];
            for (NSString * k in [[info allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
                printf("driver_error_user_info[%s]=%s\n", [k UTF8String],
                       [[[info objectForKey:k] description] UTF8String]);
            }
            // The driver's claim, kept apart from our own byte count.
            printf("driver_says_exceed_local_data_storage_limit=%s\n",
                   [[err description] containsString:@"exceed the local data storage limit"] ? "YES" : "NO");
        } else {
            printf("driver_error=NONE\n");
        }

        printf("done\n");
        return ps != nil ? 0 : 3;
    }
}
