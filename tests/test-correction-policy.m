#import <Foundation/Foundation.h>
#import "MLCorrectionPolicy.h"
#import <math.h>

static void Assert(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        MLCorrectionPolicy *policy = [[MLCorrectionPolicy alloc] init];
        NSTimeInterval delay = -1;
        for (NSUInteger index = 0; index < 5; index++) {
            Assert([policy mayCorrectAtTime:index retryAfter:&delay], @"first five corrections permitted");
            Assert(delay == 0, @"no retry before threshold");
            [policy recordCorrectionAtTime:index];
        }
        Assert(![policy mayCorrectAtTime:5 retryAfter:&delay], @"sixth correction backs off");
        Assert(fabs(delay - 30) < 0.001, @"caller gets exact retry delay");
        Assert(![policy mayCorrectAtTime:34 retryAfter:&delay], @"later events do not prolong backoff");
        Assert(fabs(delay - 1) < 0.001, @"retry uses remaining time");
        Assert([policy mayCorrectAtTime:35 retryAfter:&delay], @"retry allowed when cooldown expires");
        Assert(delay == 0, @"no second cooldown when old corrections expire");
        for (NSUInteger index = 0; index < 5; index++) [policy recordCorrectionAtTime:36 + index];
        Assert(![policy mayCorrectAtTime:41 retryAfter:&delay], @"second independent conflict backs off");
        [policy reset];
        Assert([policy mayCorrectAtTime:42 retryAfter:&delay], @"explicit pause/resume or target change clears cooldown");
        printf("Correction policy tests passed.\n");
    }
    return 0;
}
