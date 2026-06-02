#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include "xparameters.h"

#define APP_FRAME_WIDTH_MAX         1920U
#define APP_FRAME_HEIGHT_MAX        1080U
#define APP_FRAME_BYTES_PER_PIXEL   3U
#define APP_FRAME_STRIDE            (APP_FRAME_WIDTH_MAX * APP_FRAME_BYTES_PER_PIXEL)
#define APP_FRAME_BYTES_MAX         (APP_FRAME_STRIDE * APP_FRAME_HEIGHT_MAX)

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
