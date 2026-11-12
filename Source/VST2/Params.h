// Params.h
// Parameter table shared by the VST wrapper, the editor and the preset store.
//
// Front-panel controls first, left to right as on the panel (Dolby Tone, NR
// in-out, Rec / Play, then BAND 1-4: on/off switch and level pot each), then
// the plugin-only controls in the editor's bottom strip.

#ifndef TBTYPEA_PARAMS_H
#define TBTYPEA_PARAMS_H

namespace tbtypea
{

enum Param
{
    // Front panel
    kTone = 0, kNr, kMode,
    kB1On, kB1Level, kB2On, kB2Level, kB3On, kB3Level, kB4On, kB4Level,
    // Plugin only (bottom strip of the editor)
    kInput, kOutput,
    kNumParams
};

enum Kind { kToneSw, kNrSw, kModeSw, kBandSw, kBandLevel, kDb20 };

const char* const kParamNames[kNumParams] = {
    "Tone", "NR", "Mode",
    "B1 On", "B1 Level", "B2 On", "B2 Level", "B3 On", "B3 Level", "B4 On", "B4 Level",
    "Input", "Output"
};

const int kParamKind[kNumParams] = {
    kToneSw, kNrSw, kModeSw,
    kBandSw, kBandLevel, kBandSw, kBandLevel, kBandSw, kBandLevel, kBandSw, kBandLevel,
    kDb20, kDb20
};

const float kDefaults[kNumParams] = {
    0.0f,       // Dolby Tone off
    1.0f,       // NR in
    1.0f,       // REC (encode: the Dolby A trick)
    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f,   // every band on, at the stock resistor
    0.5f, 0.5f  // Input, Output 0 dB
};

const double kTrimRangeDb = 20.0;

// Band b (0..3): its switch and level parameters
inline int bandOnParam (int b)    { return kB1On + 2 * b; }
inline int bandLevelParam (int b) { return kB1Level + 2 * b; }

inline bool isOn (float v) { return v >= 0.5f; }

} // namespace tbtypea

#endif
