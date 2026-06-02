# Integration SDK

This standalone Vitis application initializes the audio codec and provides a
small UART-controlled HDMI video bring-up app. Import the root
`design_1_wrapper.xsa`, create a standalone application, and add this directory's
sources and driver folders to the application build.

## UART controls

- `t`: cycle to the next source
- `b`: show color bars
- `g`: show gradient
- `h`: request live HDMI passthrough
- `s`: print video diagnostics
- `?`: print the menu

If BSP-generated interrupt macros differ after platform regeneration, override
`APP_GPIO_VIDEO_IRQ_ID`, `APP_VTC_IN_IRQ_ID`, and `APP_IIC_IRQ_ID` in the build
settings or update `app_config.h`.
