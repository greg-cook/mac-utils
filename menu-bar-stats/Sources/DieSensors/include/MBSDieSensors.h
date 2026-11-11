#pragma once

#include <stdbool.h>

// Reads the Apple silicon die temperature sensors that the HID event system exposes.
typedef struct MBSDieSensors MBSDieSensors;

// Returns NULL when this Mac exposes no die sensors.
MBSDieSensors *_Nullable MBSDieSensorsCreate(void);

// The hottest die sensor, in degrees Celsius. Returns false when no sensor gave a reading.
bool MBSDieSensorsReadMax(MBSDieSensors *_Nonnull sensors, double *_Nonnull celsius);
