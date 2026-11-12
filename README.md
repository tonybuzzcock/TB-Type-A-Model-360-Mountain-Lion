# TB Type A 360 (Mountain Lion VST)

A VST 2.4 plugin of the A-type noise reduction unit **Model 360** with its
**Cat. No. 22** module, modelled from the Cat. 22 circuit (drawing ABC 641/3,
in `Docs/`) and the 360/361 manuals, with one modification for the
**"Dolby A trick"**: each of the four band summing resistors is an **on/off
switch and a level pot** on the front panel.

64-bit Intel, Mac OS X **10.8.5** Mountain Lion and later; made for Pro Tools 11
through Blue Cat PatchWork. Built and tested on GitHub Actions. Personal,
non-commercial use. The modern Mac version is in `TB-Type-A-Model-360-2026-MAC`.

## Front panel

Laid out like the real 360's 1U face, with the silver control plate widened to
take the band mod:

| Control | What it does |
|---|---|
| **Dolby tone** | 850 Hz calibration tone at Dolby level (with its warble). Record only, as on the unit; the NR signal is shorted while it runs. |
| Meter | Output 1 level against Dolby level (average-responding, VU-like). |
| **NR (in - out)** | Lit = NR in. Out = the unit as a fixed-gain amplifier. |
| **rec / play** | Interlocked. **rec** = encode (the Dolby A trick), **play** = decode. |
| **BAND 1-4 level** | The band's summing resistor as a pot: 0 = off, 10 = the stock resistor (unmodified Cat. 22). Audio taper: half way = -12 dB. |
| **BAND 1-4 on** | Lit = the band is in. |

Band frequencies (from the filter components): BAND 1 below 80 Hz, BAND 2
80 Hz - 3 kHz, BAND 3 above 3 kHz, BAND 4 above 9 kHz. Band 2 is made on the
card by subtracting bands 1 and 3 from the full signal, so the bands overlap:
switching band 1 (or bands 3 and 4) off leaves a little of band 2's edge, just
as lifting those resistors would on a real card.

The bottom strip has the plugin-only controls: **Input** and **Output** trims
(+-20 dB), 8 **presets** (SAVE, then a slot), and the readout.

Levels: a **-18 dBFS** sine is **Dolby level** (+4 dBu at the unit's line input),
and Dolby level comes out at -18 dBFS. Use Input to set how hard you drive the
compressors: the trick depends on the level against Dolby level.

## The circuit as modelled

- Input transformer, input level, input amplifier with its 34.6 kHz Sallen-Key low-pass.
- Band filters from the drawing: band 1 Sallen-Key low-pass 80.8 Hz (Q 0.73);
  band 3 Sallen-Key high-pass 2.98 kHz (Q 0.70); band 4 9.58 kHz (Q 0.80);
  band 2 = wideband minus bands 1 and 3.
- Four feedback compressors (FET attenuators controlled from the band's own
  output through a full-wave rectifier and integrator), overshoot limiter diodes.
- Summing resistors R109 11K0, R209 11K3, R309 8K87, R409 9K53 (the band mod).
- Record: output = input + NR signal. Play: the NR signal is fed back
  (solved exactly each sample), so encode -> decode returns the input.
- Output 2 amp, line amplifier clipping at about +21 dBm into 600 ohms on the
  18 V rail, 1:2 output transformer.
- Runs at 4x oversampling.

### Estimates

Values the drawings don't fix, as named constants in `Source/DSP/TypeA360.cpp`:

- Compressor gain law and threshold: the real gains are "adjusted on test", so
  they are fitted to the published A-type encode curve: about +10 dB at low
  level (bands 1-3), +15 dB above 9 kHz, +6 dB at -30 dB, +3.5 dB at -20 dB,
  +1 dB at Dolby level.
- Compressor time constants: attack 1 ms / release 28 ms (bands 3, 4), twice
  that for bands 1, 2 (from the integrator RCs), plus a fast speed-up path.
- Limiter level.
- Transformers T2 (A3D426) and T3 (A3D435): only part numbers are known;
  modelled with gentle low- and high-frequency roll-offs and a little core
  saturation at low frequencies and high levels.
- Dolby Tone warble period (about 0.63 s, from the unijunction timing).

## Install

Actions -> latest run -> Artifacts -> `TB-Type-A-Model-360-mountain-lion-vst`;
unzip (twice) and copy `TB Type A 360.vst` to `/Library/Audio/Plug-Ins/VST/`,
then rescan in PatchWork.

## Tests

`make -C Tests run vst-run` (Linux or Mac), `make -C Tests asan`. The Mac job
also builds the bundle, checks it declares 10.8.5, loads it in a mini host,
opens the panel offscreen, drives its controls and publishes screenshots to the
`gui-preview` branch.
