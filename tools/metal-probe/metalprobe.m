// Prints what the installed GPUs actually support, instead of assuming.
//
// The D700 is a pre-Metal3 AMD GPU. llama.cpp's Metal backend assumes device
// features that these cards may not have, and the fork's own logs already say
// "tensor API disabled for pre-M5 and pre-A19 devices". This asks the driver.
//
// build: clang -fobjc-arc -framework Foundation -framework Metal -o metalprobe metalprobe.m

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static const char * yesno(BOOL b) {
    return b ? "YES" : "NO";
}

static void print_families(id<MTLDevice> d) {
    struct { const char * name; MTLGPUFamily f; } fams[] = {
        { "Apple7",  MTLGPUFamilyApple7  },
        { "Apple8",  MTLGPUFamilyApple8  },
        { "Apple9",  MTLGPUFamilyApple9  },
        { "Mac1",    MTLGPUFamilyMac1    },
        { "Mac2",    MTLGPUFamilyMac2    },
        { "Common1", MTLGPUFamilyCommon1 },
        { "Common2", MTLGPUFamilyCommon2 },
        { "Common3", MTLGPUFamilyCommon3 },
        { "Metal3",  MTLGPUFamilyMetal3  },
    };
    for (size_t i = 0; i < sizeof(fams)/sizeof(fams[0]); i++) {
        printf("    %-8s %s\n", fams[i].name, yesno([d supportsFamily:fams[i].f]));
    }
}

int main(void) {
    @autoreleasepool {
        NSArray<id<MTLDevice>> * devs = MTLCopyAllDevices();
        printf("device count: %lu\n", (unsigned long) devs.count);

        for (NSUInteger i = 0; i < devs.count; i++) {
            id<MTLDevice> d = devs[i];
            printf("\n=== device %lu ===\n", (unsigned long) i);
            printf("    name                         %s\n", [[d name] UTF8String]);
            printf("    hasUnifiedMemory             %s\n", yesno(d.hasUnifiedMemory));
            printf("    recommendedMaxWorkingSetSize %llu MiB\n",
                   [d recommendedMaxWorkingSetSize] / (1024ULL * 1024ULL));
            printf("    maxBufferLength              %llu MiB\n",
                   [d maxBufferLength] / (1024ULL * 1024ULL));
            printf("    supportsFamily:\n");
            print_families(d);

            // threadExecutionWidth is a device property but it is only reachable
            // through a pipeline state, so compile a trivial kernel for it.
            NSString * src = @"#include <metal_stdlib>\n"
                             "using namespace metal;\n"
                             "kernel void probe(device float * o [[buffer(0)]], uint g [[thread_position_in_grid]]) { o[g] = 1.0f; }\n";
            NSError * err = nil;
            id<MTLLibrary> lib = [d newLibraryWithSource:src options:nil error:&err];
            if (lib == nil) {
                printf("    trivial kernel compile        FAILED: %s\n",
                       err ? [[err localizedDescription] UTF8String] : "unknown");
                continue;
            }
            id<MTLFunction> fn = [lib newFunctionWithName:@"probe"];
            id<MTLComputePipelineState> ps = [d newComputePipelineStateWithFunction:fn error:&err];
            if (ps == nil) {
                printf("    trivial kernel pipeline       FAILED: %s\n",
                       err ? [[err localizedDescription] UTF8String] : "unknown");
                continue;
            }
            printf("    threadExecutionWidth         %lu\n", (unsigned long) [ps threadExecutionWidth]);
            printf("    maxTotalThreadsPerThreadgroup %lu\n", (unsigned long) [ps maxTotalThreadsPerThreadgroup]);
        }
        printf("\ndone\n");
    }
    return 0;
}
