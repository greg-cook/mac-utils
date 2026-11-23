#include "DisplayDDC.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>

// A DCPAVServiceProxy and its ancestors carry no EDID, vendor, product or serial property, so nothing
// here says which screen a service belongs to. The caller pairs services with screens.

typedef CFTypeRef (*CreateFn)(CFAllocatorRef, io_service_t);
typedef IOReturn (*I2CFn)(CFTypeRef, uint32_t, uint32_t, void *, uint32_t);

struct DDCService {
    CFTypeRef avService;
    io_service_t entry;
};

static CreateFn createService;
static I2CFn readI2C;
static I2CFn writeI2C;
static pthread_once_t resolveOnce = PTHREAD_ONCE_INIT;

static void resolve(void) {
    createService = (CreateFn)dlsym(RTLD_DEFAULT, "IOAVServiceCreateWithService");
    readI2C = (I2CFn)dlsym(RTLD_DEFAULT, "IOAVServiceReadI2C");
    writeI2C = (I2CFn)dlsym(RTLD_DEFAULT, "IOAVServiceWriteI2C");
}

bool DDCInterfaceAvailable(void) {
    pthread_once(&resolveOnce, resolve);
    return createService != NULL && readI2C != NULL && writeI2C != NULL;
}

static bool isExternal(io_service_t entry) {
    CFTypeRef location = IORegistryEntryCreateCFProperty(entry, CFSTR("Location"), kCFAllocatorDefault, 0);
    if (location == NULL) return false;
    bool external = CFGetTypeID(location) == CFStringGetTypeID()
        && CFStringCompare(location, CFSTR("External"), 0) == kCFCompareEqualTo;
    CFRelease(location);
    return external;
}

DDCService *_Nonnull *_Nullable DDCCopyExternalServices(size_t *_Nonnull count) {
    *count = 0;
    if (!DDCInterfaceAvailable()) return NULL;

    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) != KERN_SUCCESS) {
        return NULL;
    }

    DDCService **services = NULL;
    size_t found = 0;
    io_service_t entry;
    while ((entry = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        CFTypeRef av = isExternal(entry) ? createService(kCFAllocatorDefault, entry) : NULL;
        DDCService *service = av != NULL ? malloc(sizeof(DDCService)) : NULL;
        DDCService **grown = service != NULL ? realloc(services, (found + 1) * sizeof(DDCService *)) : NULL;
        if (grown == NULL) {
            free(service);
            if (av != NULL) CFRelease(av);
            IOObjectRelease(entry);
            continue;
        }
        service->avService = av;
        service->entry = entry;
        services = grown;
        services[found++] = service;
    }
    IOObjectRelease(iterator);
    *count = found;
    return services;
}

void DDCFreeServices(DDCService *_Nonnull *_Nullable services, size_t count) {
    if (services == NULL) return;
    for (size_t i = 0; i < count; i++) {
        CFRelease(services[i]->avService);
        IOObjectRelease(services[i]->entry);
        free(services[i]);
    }
    free(services);
}

bool DDCWrite(DDCService *_Nonnull service, uint32_t chip, uint32_t offset, const uint8_t *_Nonnull bytes, size_t length) {
    if (!DDCInterfaceAvailable()) return false;
    return writeI2C(service->avService, chip, offset, (void *)bytes, (uint32_t)length) == kIOReturnSuccess;
}

bool DDCRead(DDCService *_Nonnull service, uint32_t chip, uint32_t offset, uint8_t *_Nonnull out, size_t length) {
    if (!DDCInterfaceAvailable()) return false;
    return readI2C(service->avService, chip, offset, out, (uint32_t)length) == kIOReturnSuccess;
}

uint32_t DDCServiceRegistryEntry(const DDCService *_Nonnull service) {
    return service->entry;
}
