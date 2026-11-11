#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Wraps macOS 27's private menu bar restriction (MenuBarClientCore), which shows only an
// allow-list of apps plus macOS's own items. The restriction ends on -invalidate or when this
// process exits. Completion handlers run on the main queue.
@interface MBMMenuBarRestriction : NSObject

+ (BOOL)isAvailable;
+ (void)activateAllowingBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                               completion:(void (NS_SWIFT_UI_ACTOR ^)(MBMMenuBarRestriction *_Nullable restriction,
                                                    NSError *_Nullable error))completion;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
