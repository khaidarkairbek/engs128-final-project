#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include "xparameters.h"

/*
 * The checked-in integration XSA uses a 256-point FFT. Change this only when
 * the platform is regenerated from a matching Vivado design.
 */
#ifndef APP_FFT_LENGTH
#define APP_FFT_LENGTH 256U
#endif

#define APP_SAMPLE_RATE_HZ          48000U
#define APP_USEFUL_BIN_COUNT        (APP_FFT_LENGTH / 2U)
#define APP_UPDATE_INTERVAL_US      33000U

#define APP_MUSICAL_RED_END_HZ      500U
#define APP_MUSICAL_GREEN_END_HZ    4000U

#define APP_GAIN_UNITY_Q412         0x1000U
#define APP_GAIN_MIN_Q412           0x0200U
#define APP_GAIN_MAX_Q412           0x4000U

/*
 * Calibration lasts about three seconds at the 30 Hz update rate. Active mode
 * ignores small deviations around the quiet baseline. Above the deadband, the
 * absolute difference is normalized by the baseline and mapped logarithmically.
 * A ratio of 1 means the deviation equals the baseline; a ratio of 64 reaches
 * the minimum gain. The minimum span keeps nearly silent inputs stable.
 */
#define APP_CALIBRATION_SAMPLE_COUNT       90U
#define APP_CALIBRATION_DEADBAND_PERCENT   10U
#define APP_CALIBRATION_MIN_SPAN           1024U
#define APP_RESPONSE_MAX_RATIO             64U

/* Audio updates run at about 30 Hz. Print traced gains at about 5 Hz. */
#define APP_GAIN_TRACE_DIVIDER      6U

#define APP_FRAME_WIDTH_MAX         1920U
#define APP_FRAME_HEIGHT_MAX        1080U
#define APP_FRAME_BYTES_PER_PIXEL   3U
#define APP_FRAME_STRIDE            (APP_FRAME_WIDTH_MAX * APP_FRAME_BYTES_PER_PIXEL)
#define APP_FRAME_BYTES_MAX         (APP_FRAME_STRIDE * APP_FRAME_HEIGHT_MAX)

#define APP_BRAM_LEFT_BASE          XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR
#define APP_BRAM_RIGHT_BASE         XPAR_AXI_BRAM_CTRL_1_S_AXI_BASEADDR
#define APP_FILTER_BASE             XPAR_AUDIO_VIDEO_FILTER_0_BASEADDR
#define APP_DYNCLK_BASE             XPAR_AXI_DYNCLK_0_S_AXI_LITE_BASEADDR
#define APP_VDMA_DEVICE_ID          XPAR_AXIVDMA_0_DEVICE_ID
#define APP_VTC_OUT_DEVICE_ID       XPAR_V_TC_OUT_DEVICE_ID
#define APP_VTC_IN_DEVICE_ID        XPAR_V_TC_IN_DEVICE_ID
#define APP_GPIO_VIDEO_DEVICE_ID    XPAR_AXI_GPIO_VIDEO_DEVICE_ID
#define APP_UART_BASE               XPAR_PS7_UART_1_BASEADDR

/*
 * Override these three IDs with compiler definitions if a regenerated BSP
 * uses different xparameters.h spellings.
 */
#ifndef APP_GPIO_VIDEO_IRQ_ID
#define APP_GPIO_VIDEO_IRQ_ID       XPAR_FABRIC_AXI_GPIO_VIDEO_IP2INTC_IRPT_INTR
#endif
#ifndef APP_VTC_IN_IRQ_ID
#define APP_VTC_IN_IRQ_ID           XPAR_FABRIC_V_TC_IN_IRQ_INTR
#endif
#ifndef APP_IIC_IRQ_ID
#define APP_IIC_IRQ_ID              XPAR_FABRIC_IIC_0_VEC_ID
#endif

#endif
