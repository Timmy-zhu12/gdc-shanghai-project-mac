# PC Accuracy Baseline Sync

This iPhone/macOS version has been synced with the latest PC accuracy-improved
baseline.

## Ported capabilities

- Gemma4 4B wording and offline edge workflow are preserved.
- B-mode feature extraction now emits the PC-style 14-dimensional vector:
  mean, variance, horizontal and vertical differences, gradient, edge density,
  entropy, DoG mean/high response, chamber area proxy, speckle residual,
  contrast gain, directional anisotropy, and symmetry proxy.
- The study aggregator now reports both absolute `contractility_proxy` and
  relative `contractility_fraction_proxy` for systole/diastole pairs.
- The rule fallback uses the CAMUS-derived low-EF B-mode calibration from the
  PC version, plus motion-based contractility checks, before emitting
  `左心室收缩功能减低`.
- A4C/A2C view detection accepts common `4ch` and `2ch` filename labels.
- Animated raster files are expanded with ImageIO and video/cine containers are
  sampled into representative frames with `AVAssetImageGenerator`, preserving the
  same multi-frame study aggregation used by DICOM cine loops.

## Compatibility note

The Apple build keeps the same input/output contract as the PC version:
multiple image/DICOM/animated-raster/video-cine frames in, one teaching
reference diagnosis report out. On macOS, local Gemma4 4B GGUF execution remains
available through the configured llama.cpp command. This is a medical teaching
aid only and must not be used as clinical diagnosis, treatment advice, or a
doctor's order.
