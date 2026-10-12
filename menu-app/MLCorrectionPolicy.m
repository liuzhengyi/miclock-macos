#import "MLCorrectionPolicy.h"

@interface MLCorrectionPolicy ()
@property(nonatomic, strong) NSMutableArray<NSNumber *> *corrections;
@property(nonatomic) NSTimeInterval pausedUntil;
@end

@implementation MLCorrectionPolicy
- (instancetype)init {
    self = [super init];
    if (self) _corrections = [NSMutableArray array];
    return self;
}

- (BOOL)mayCorrectAtTime:(NSTimeInterval)time retryAfter:(NSTimeInterval *)retryAfter {
    if (retryAfter != NULL) *retryAfter = 0;
    if (self.pausedUntil > time) {
        if (retryAfter != NULL) *retryAfter = self.pausedUntil - time;
        return NO;
    }
    NSIndexSet *expired = [self.corrections indexesOfObjectsPassingTest:
        ^BOOL(NSNumber *value, NSUInteger index, BOOL *stop) {
            (void)index;
            (void)stop;
            return value.doubleValue <= time - 30.0;
        }];
    [self.corrections removeObjectsAtIndexes:expired];
    if (self.corrections.count >= 5) {
        self.pausedUntil = time + 30.0;
        if (retryAfter != NULL) *retryAfter = 30.0;
        return NO;
    }
    self.pausedUntil = 0;
    return YES;
}

- (void)recordCorrectionAtTime:(NSTimeInterval)time {
    [self.corrections addObject:@(time)];
}

- (void)reset {
    [self.corrections removeAllObjects];
    self.pausedUntil = 0;
}
@end
