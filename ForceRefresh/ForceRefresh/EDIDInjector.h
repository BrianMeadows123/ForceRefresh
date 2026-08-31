#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin wrapper around the private IOAVService API used to inject a
/// virtual EDID at runtime on Apple Silicon Macs. This is the only
/// mechanism that works there -- the legacy
/// /Library/Displays/.../Overrides plist method is silently ignored
/// because display negotiation happens on the DCP (Display CoProcessor),
/// not the path those overrides hook into.
///
/// This uses undocumented, private Apple APIs. It is not guaranteed to
/// keep working across macOS updates.
@interface EDIDInjector : NSObject

/// Applies `edidData` to every connected external display (built-in
/// displays are always skipped). Returns the number of displays it
/// was successfully applied to.
+ (NSInteger)applyEDID:(NSData *)edidData;

/// Resets every connected external display back to its native EDID.
+ (void)reset;

@end

NS_ASSUME_NONNULL_END
