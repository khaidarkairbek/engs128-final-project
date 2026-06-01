# Integration SDK

This standalone Vitis application merges the existing audio and video SDK
behavior without changing either original demo. Import the root
`design_1_wrapper.xsa`, create a standalone application, and add this directory's
sources and driver folders to the application build.

The checked-in XSA uses a 256-point FFT. `app_config.h` exposes
`APP_FFT_LENGTH` so a future 1024-point platform can be selected at build time,
but the setting must always match the Vivado design.

## Known RTL dependency

Reliable FFT-driven gains require a regenerated XSA after these fixes in
`audio-path/hw/fft_wrapper.vhd`:

1. In both FFT config processes, reset when `aresetn = '0'`.
2. Drive right BRAM enable and write-enable from `right_fft_out_tvalid`.
3. If moving to 1024 points, regenerate the FFT IP and wrapper widths
   consistently before exporting the XSA.

The current XSA is still useful for application structure, video bring-up, and
the UART manual-gain test.

## UART controls

- `a`: toggle audio-reactive updates
- `c`: calibrate the quiet baseline for about three seconds, then enter active mode
- `b`: show color bars
- `d`: show gradient
- `h`: request live HDMI input
- `g`: toggle a live RGB energy and gain trace at about 5 Hz
- `m`: disable reactive updates and cycle manual RGB gain presets
- `p`: switch between musical bands and equal thirds
- `s`: print FFT, band, gain, and video diagnostics
- `q`: disable reactive updates and restore unity gains
- `?`: print the menu

## Calibration and gain tuning

The response calculation is in `audio_reactive.c`: `AudioReactive_Update()`
averages each FFT band, `EnergyToTargetGain()` converts energy to a Q4.12 target,
and `SmoothGain()` applies attack and decay smoothing. Tune the calibration
window, deadband, minimum response span, and gain range in `app_config.h`.

Press `c` while the input is quiet. The application averages each band's FFT
energy for about three seconds and stores those values as its baseline. Active
mode maps a band close to baseline to `1.0x`; as its absolute deviation grows,
its gain approaches `0.0x`. A deadband prevents normal idle noise from causing
visible movement. Disabling reactive mode restores neutral `1.0x` gains.

If BSP-generated interrupt macros differ after platform regeneration, override
`APP_GPIO_VIDEO_IRQ_ID`, `APP_VTC_IN_IRQ_ID`, and `APP_IIC_IRQ_ID` in the build
settings or update `app_config.h`.
