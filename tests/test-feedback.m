#import <Foundation/Foundation.h>
#import "MLFeedback.h"

// Pure request/receipt model checks only. This test never opens the feedback
// window, reads microphones, writes a draft, or contacts a service.
static NSUInteger Checks;
static NSUInteger Failures;
static NSString * const RequestID = @"6B08F9CE-8302-4EE7-B950-DF6A4FA58499";
static NSString * const PrivateMarker = @"fixture-private-marker-never-send";

static void Check(BOOL condition, NSString *message) {
    Checks++;
    if (!condition) {
        Failures++;
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    }
}

static NSData *JSONData(id value) {
    return [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];
}

static NSDictionary *Receipt(NSDictionary *changes) {
    NSMutableDictionary *value = [@{@"accepted":@YES, @"clientRequestId":RequestID.lowercaseString,
        @"receiptId":@"ML-20261011-123abc", @"storageStatus":@"received"} mutableCopy];
    [value addEntriesFromDictionary:changes];
    return value;
}

static NSDictionary *Validate(NSDictionary *value, NSInteger status, NSString *requestID) {
    return MLFeedbackValidateResponse(JSONData(value), status, requestID, NULL);
}

int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        NSDictionary *payload = MLFeedbackBuildPayload(@"  小声输入会漏字。\n", RequestID, nil, &error);
        Check(payload != nil && error == nil, @"ordinary voice-entered description is accepted");
        Check([payload[@"description"] isEqualToString:@"小声输入会漏字。"], @"outer whitespace is trimmed without changing problem text");
        Check([payload[@"clientRequestId"] isEqualToString:RequestID.lowercaseString], @"UUID is canonical and stable");
        Check([payload[@"schema"] isEqual:@1], @"request uses the supported schema");
        Check(payload[@"diagnostics"] == nil, @"diagnostics disabled means no diagnostics field");
        Check([payload isEqual:MLFeedbackBuildPayload(@"小声输入会漏字。", RequestID.lowercaseString, nil, NULL)],
            @"same report and UUID rebuild the same request for retry");
        for (NSString *invalid in @[@"", @" \n\t", [@"a" stringByPaddingToLength:4001 withString:@"a" startingAtIndex:0]]) {
            error = nil;
            Check(MLFeedbackBuildPayload(invalid, RequestID, nil, &error) == nil && error != nil,
                @"empty or over-limit description fails with a visible error");
        }
        Check(MLFeedbackBuildPayload([@"文" stringByPaddingToLength:4000 withString:@"文" startingAtIndex:0],
            RequestID, nil, NULL) != nil, @"maximum length Chinese description is accepted");
        for (NSString *invalidID in @[@"", @"not-a-uuid", @"../report", @"6B08F9CE-8302-1EE7-B950-DF6A4FA58499"]) {
            Check(MLFeedbackBuildPayload(@"问题描述", invalidID, nil, NULL) == nil,
                @"invalid idempotency identifier cannot be sent");
        }

        NSDictionary *diagnostics = @{@"appVersion":@"3.2.0", @"appBuild":@"12", @"lockEnabled":@YES,
            @"healthStatus":@"healthy", @"targetPresent":@YES, @"currentMatchesTarget":@YES,
            @"inputs":@[@{@"kind":@1, @"transport":@"Built-in", @"alive":@YES,
                @"isTarget":@YES, @"isCurrent":@YES, @"nominalSampleRate":@44100,
                @"inputChannels":@1, @"name":PrivateMarker, @"uid":PrivateMarker, @"deviceID":@987}],
            @"recentEvents":@[@{@"event":@"launch", @"secondsAgo":@12, @"rawLog":PrivateMarker}],
            @"serialNumber":PrivateMarker, @"clipboardText":PrivateMarker, @"path":PrivateMarker,
            @"apiKey":PrivateMarker, @"recording":PrivateMarker};
        NSDictionary *withDiagnostics = MLFeedbackBuildPayload(@"问题描述", RequestID, diagnostics, NULL);
        Check(withDiagnostics != nil, @"bounded useful diagnostics can accompany a report");
        NSString *encoded = [[NSString alloc] initWithData:JSONData(withDiagnostics != nil ? withDiagnostics : @{}) encoding:NSUTF8StringEncoding];
        Check(![encoded containsString:PrivateMarker], @"unknown top-level and nested diagnostic fields never leave the client");
        NSDictionary *clean = withDiagnostics[@"diagnostics"];
        Check([clean[@"appVersion"] isEqualToString:@"3.2.0"] && [clean[@"lockEnabled"] isEqual:@YES],
            @"white-list filtering retains useful version and lock state");
        NSDictionary *booleanNumbers = MLFeedbackBuildPayload(@"问题描述", RequestID,
            @{@"memoryBytes":@YES, @"inputs":@[@{@"kind":@YES, @"nominalSampleRate":@YES,
                @"inputChannels":@YES}], @"recentEvents":@[@{@"event":@"launch", @"secondsAgo":@YES}]}, NULL);
        NSDictionary *typedDiagnostics = booleanNumbers[@"diagnostics"];
        NSArray *typedInputs = typedDiagnostics[@"inputs"];
        NSDictionary *typedInput = typedInputs.count > 0 ? typedInputs.firstObject : @{};
        Check(typedDiagnostics[@"memoryBytes"] == nil, @"boolean cannot masquerade as memory byte count");
        Check(typedInput[@"kind"] == nil, @"boolean cannot masquerade as numeric device kind");
        Check(typedInput[@"nominalSampleRate"] == nil, @"boolean cannot masquerade as sample rate");
        Check(typedInput[@"inputChannels"] == nil, @"boolean cannot masquerade as channel count");
        Check([typedDiagnostics[@"recentEvents"] count] == 0, @"boolean cannot masquerade as relative event age");
        Check([clean[@"recentEvents"] count] == 1, @"valid fixed event with relative time survives filtering");
        Check(Validate(Receipt(@{@"clientRequestId":@"6b08f9ce-8302-1ee7-b950-df6a4fa58499"}), 200,
            @"6b08f9ce-8302-1ee7-b950-df6a4fa58499") == nil, @"non-v4 receipt request identity is rejected");

        NSDictionary *huge = MLFeedbackBuildPayload(@"问题描述", RequestID,
            @{@"osVersion":[@"v" stringByPaddingToLength:70000 withString:@"v" startingAtIndex:0]}, NULL);
        Check(huge == nil || JSONData(huge).length <= 65536, @"large input cannot create a request over 64 KiB");

        for (NSNumber *status in @[@200, @201, @202]) {
            Check(Validate(Receipt(@{}), status.integerValue, RequestID) != nil,
                @"valid server receipt is accepted only in the success status range");
        }
        Check(Validate(Receipt(@{@"storageStatus":@"feishu_synced"}), 200, RequestID) != nil,
            @"confirmed Feishu sync is accepted separately from durable local receipt");
        for (NSNumber *status in @[@0, @199, @203, @204, @301, @400, @429, @500]) {
            Check(Validate(Receipt(@{}), status.integerValue, RequestID) == nil,
                @"non-contract HTTP statuses cannot show successful submission");
        }
        for (id accepted in @[@NO, @2, @"true", NSNull.null]) {
            Check(Validate(Receipt(@{@"accepted":accepted}), 200, RequestID) == nil,
                @"only the JSON boolean true proves server acceptance");
        }
        Check(Validate(Receipt(@{@"clientRequestId":@"fbfe9fb7-cde0-476e-8fe2-81b0517d9060"}), 200, RequestID) == nil,
            @"receipt from another request is rejected");
        Check(Validate(Receipt(@{@"clientRequestId":@""}), 200, @"") == nil,
            @"empty expected request identifier fails closed");
        for (NSString *receiptID in @[@"", @"../private", @"a\nb", [@"a" stringByPaddingToLength:65 withString:@"a" startingAtIndex:0]]) {
            Check(Validate(Receipt(@{@"receiptId":receiptID}), 200, RequestID) == nil,
                @"unsafe or oversized receipt identifiers are rejected");
        }
        for (NSString *storage in @[@"pending", @"failed", @"unknown", @""]) {
            Check(Validate(Receipt(@{@"storageStatus":storage}), 200, RequestID) == nil,
                @"unknown storage state never implies durable receipt");
        }
        NSDictionary *filteredReceipt = Validate(Receipt(@{@"token":PrivateMarker,
            @"debugLog":PrivateMarker}), 200, RequestID);
        NSString *stored = [[NSString alloc] initWithData:JSONData(filteredReceipt != nil ? filteredReceipt : @{}) encoding:NSUTF8StringEncoding];
        Check(filteredReceipt != nil && ![stored containsString:PrivateMarker],
            @"unknown response fields are not persisted in the local receipt");
        Check(MLFeedbackValidateResponse([@"not json" dataUsingEncoding:NSUTF8StringEncoding], 200, RequestID, NULL) == nil,
            @"malformed response is not accepted");
        Check(MLFeedbackValidateResponse(JSONData(@[]), 200, RequestID, NULL) == nil,
            @"response root must be an object");
        NSData *tooLarge = [[@" " stringByPaddingToLength:16385 withString:@" " startingAtIndex:0]
            dataUsingEncoding:NSUTF8StringEncoding];
        Check(MLFeedbackValidateResponse(tooLarge, 200, RequestID, NULL) == nil,
            @"oversized response cannot be trusted");
        Check(MLFeedbackValidateResponse(NSData.data, 200, RequestID, NULL) == nil,
            @"empty response cannot be trusted");
        printf("Feedback model regression: %lu checks, %lu failures. No network, hardware, draft or UI actions.\n",
            (unsigned long)Checks, (unsigned long)Failures);
    }
    return Failures == 0 ? 0 : 1;
}
