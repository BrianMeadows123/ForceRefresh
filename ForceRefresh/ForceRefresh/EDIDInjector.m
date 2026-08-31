#import "EDIDInjector.h"
#import <IOKit/IOKitLib.h>

// Private API -- reverse-engineered, not declared in any public Apple
// header. Declaring the symbols here lets us link against what
// IOKit.framework already exports on Apple Silicon.
typedef CFTypeRef IOAVServiceRef;
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceSetVirtualEDIDMode(IOAVServiceRef service, uint32_t mode, CFDataRef _Nullable edidData);

@implementation EDIDInjector

+ (NSInteger)apply:(nullable NSData *)edidData {
    io_iterator_t iterator;
    kern_return_t kr = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("DCPAVServiceProxy"),
        &iterator
    );
    if (kr != KERN_SUCCESS) {
        NSLog(@"[EDIDInjector] Could not find DCPAVServiceProxy (kr=%d)", kr);
        return 0;
    }

    NSInteger applied = 0;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        CFStringRef location = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, CFSTR("Location"),
            kCFAllocatorDefault, kIORegistryIterateRecursively
        );
        NSString *loc = (__bridge_transfer NSString *)location;

        if ([loc isEqualToString:@"Embedded"]) {
            IOObjectRelease(service);
            continue; // built-in display -- never touch this one
        }

        IOAVServiceRef avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service);
        if (!avService) {
            IOObjectRelease(service);
            continue;
        }

        IOReturn result;
        if (edidData) {
            result = IOAVServiceSetVirtualEDIDMode(avService, 1, (__bridge CFDataRef)edidData);
        } else {
            result = IOAVServiceSetVirtualEDIDMode(avService, 0, NULL);
        }

        if (result == kIOReturnSuccess) {
            applied++;
        } else {
            NSLog(@"[EDIDInjector] Failed on a display, IOReturn=0x%x", result);
        }

        CFRelease(avService);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return applied;
}

+ (NSInteger)applyEDID:(NSData *)edidData {
    return [self apply:edidData];
}

+ (void)reset {
    [self apply:nil];
}

@end
