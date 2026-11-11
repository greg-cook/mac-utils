#include "MBSDieSensors.h"

#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <stdlib.h>

// Private IOKit API; no public API reports Apple silicon temperatures. The public simple client
// lists the sensors but returns no readings from them.
typedef CFTypeRef IOHIDEventRef;
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client,
                                             CFDictionaryRef matching);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type,
                                                 int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

enum {
    kTemperatureEventType = 15,
    kTemperatureLevelField = kTemperatureEventType << 16,
    kVendorUsagePage = 0xff00,
    kTemperatureUsage = 5,
};

struct MBSDieSensors {
    IOHIDEventSystemClientRef client;
    CFMutableArrayRef services;
};

// Die sensors are named like "PMU tdie3"; the other temperature sensors cover the battery, SSD
// and power rails.
static bool IsDieSensor(IOHIDServiceClientRef service) {
    CFTypeRef name = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
    if (!name) return false;
    bool isDie = CFGetTypeID(name) == CFStringGetTypeID() &&
                 CFStringFind(name, CFSTR("tdie"), 0).location != kCFNotFound;
    CFRelease(name);
    return isDie;
}

MBSDieSensors *MBSDieSensorsCreate(void) {
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return NULL;
    int page = kVendorUsagePage, usage = kTemperatureUsage;
    CFNumberRef values[] = {CFNumberCreate(NULL, kCFNumberIntType, &page),
                            CFNumberCreate(NULL, kCFNumberIntType, &usage)};
    const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
    CFDictionaryRef matching = CFDictionaryCreate(NULL, keys, (const void **)values, 2,
                                                  &kCFTypeDictionaryKeyCallBacks,
                                                  &kCFTypeDictionaryValueCallBacks);
    IOHIDEventSystemClientSetMatching(client, matching);
    CFRelease(matching);
    CFRelease(values[0]);
    CFRelease(values[1]);
    CFArrayRef all = IOHIDEventSystemClientCopyServices(client);
    CFMutableArrayRef services = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if (all) {
        for (CFIndex i = 0; i < CFArrayGetCount(all); i++) {
            IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(all, i);
            if (IsDieSensor(service)) CFArrayAppendValue(services, service);
        }
        CFRelease(all);
    }
    if (CFArrayGetCount(services) == 0) {
        CFRelease(services);
        CFRelease(client);
        return NULL;
    }
    MBSDieSensors *sensors = malloc(sizeof *sensors);
    sensors->client = client;
    sensors->services = services;
    return sensors;
}

bool MBSDieSensorsReadMax(MBSDieSensors *sensors, double *celsius) {
    bool found = false;
    for (CFIndex i = 0; i < CFArrayGetCount(sensors->services); i++) {
        IOHIDServiceClientRef service =
            (IOHIDServiceClientRef)CFArrayGetValueAtIndex(sensors->services, i);
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kTemperatureEventType, 0, 0);
        if (!event) continue;
        double value = IOHIDEventGetFloatValue(event, kTemperatureLevelField);
        CFRelease(event);
        // Idle sensors can report nonsense such as negative values.
        if (value <= 0 || value > 150) continue;
        if (!found || value > *celsius) *celsius = value;
        found = true;
    }
    return found;
}
