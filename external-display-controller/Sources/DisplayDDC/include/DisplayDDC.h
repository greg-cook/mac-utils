#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Talks DDC/CI to an external display over the I2C channel that Apple's private IOAVService interface
// exposes on Apple silicon. The interface has no public header, so its three functions are looked up with
// dlsym and every call here fails cleanly if a macOS update removes them.
typedef struct DDCService DDCService;

// True if all three private functions were found.
bool DDCInterfaceAvailable(void);

// Returns the external display services as a malloc'd array of `*count` pointers, or NULL if there are none.
// Free it with DDCFreeServices.
DDCService *_Nonnull *_Nullable DDCCopyExternalServices(size_t *_Nonnull count);
void DDCFreeServices(DDCService *_Nonnull *_Nullable services, size_t count);

// One I2C write or read. Each returns false on any error.
bool DDCWrite(DDCService *_Nonnull service, uint32_t chip, uint32_t offset, const uint8_t *_Nonnull bytes, size_t length);
bool DDCRead(DDCService *_Nonnull service, uint32_t chip, uint32_t offset, uint8_t *_Nonnull out, size_t length);

// The IORegistry entry the service came from, for reading its properties. Valid until DDCFreeServices.
uint32_t DDCServiceRegistryEntry(const DDCService *_Nonnull service);
