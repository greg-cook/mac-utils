#import "MBMMenuBarRestriction.h"

#import <dlfcn.h>
#import <objc/message.h>

// Resolved at runtime, so a macOS release that changes or removes the framework makes hiding
// unavailable rather than stopping the app from launching.
static NSString *const MBMFrameworkPath =
    @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";

static NSError *MBMError(NSString *reason) {
    return [NSError errorWithDomain:@"MBMMenuBarRestriction"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

@implementation MBMMenuBarRestriction {
    id _assertion;
}

+ (BOOL)isAvailable {
    if (!dlopen(MBMFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) {
        return NO;
    }
    Class configuration = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
    return [configuration instancesRespondToSelector:
                              @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)]
        && [assertion instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)]
        && [assertion instancesRespondToSelector:@selector(invalidate)];
}

+ (void)activateAllowingBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                               completion:(void (^)(MBMMenuBarRestriction *, NSError *))completion {
    void (^finish)(MBMMenuBarRestriction *, NSError *) = ^(MBMMenuBarRestriction *restriction,
                                                          NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(restriction, error); });
    };
    if (![self isAvailable]) {
        finish(nil, MBMError(@"The macOS menu bar restriction API is unavailable"));
        return;
    }

    // macOS's own items (clock, Wi-Fi, Control Center, ...) are numbered slots; IDs that are not in
    // use are ignored, so allowing the whole range keeps all of them. The framework indexes into
    // both lists, so they must be arrays.
    NSMutableArray<NSNumber *> *systemItems = [NSMutableArray array];
    for (int i = 0; i < 64; i++) {
        [systemItems addObject:@(i)];
    }

    @try {
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(@"MBAssessmentModeConfiguration") alloc],
            @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:), systemItems,
            [bundleIdentifiers copy]);
        id assertion = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        if (!configuration || !assertion) {
            finish(nil, MBMError(@"Could not create the menu bar restriction"));
            return;
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, @selector(activateWithConfiguration:completionHandler:), configuration,
            ^(NSError *error) {
                if (error) {
                    finish(nil, error);
                    return;
                }
                MBMMenuBarRestriction *restriction = [[MBMMenuBarRestriction alloc] init];
                restriction->_assertion = assertion;
                finish(restriction, nil);
            });
    } @catch (NSException *exception) {
        finish(nil, MBMError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

- (void)invalidate {
    @try {
        ((void (*)(id, SEL))objc_msgSend)(_assertion, @selector(invalidate));
    } @catch (NSException *exception) {
        NSLog(@"MenuBarManager: invalidating the menu bar restriction raised %@", exception);
    }
    _assertion = nil;
}

@end
