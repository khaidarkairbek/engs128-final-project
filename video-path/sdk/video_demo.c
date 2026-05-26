/************************************************************************/
/*                                                                      */
/* video_demo.c -- ENGS 128 Audio-Reactive Video Filter                 */
/*                Display bring-up with test pattern + brightness       */
/*                                                                      */
/************************************************************************/
/*  Based on Digilent ZYBO Video Demo (Sam Bobrowicz, 2015).            */
/*                                                                      */
/*  This version:                                                       */
/*   - Brings up the HDMI Out display path only (no HDMI In).           */
/*   - Renders a static color-bar test pattern into a framebuffer.      */
/*   - Lets you toggle between passthrough and brightness-filter modes  */
/*     to verify the audio_video_filter IP is responding to AXI-Lite    */
/*     writes.                                                          */
/************************************************************************/

#include "video_demo.h"
#include "display_ctrl/display_ctrl.h"
#include <stdio.h>
#include "xuartps.h"
#include "xil_io.h"
#include "xil_types.h"
#include "xil_cache.h"
#include "timer_ps/timer_ps.h"
#include "xparameters.h"

/* ------------------------------------------------------------ */
/*  XPAR redefines                                              */
/* ------------------------------------------------------------ */

#define DYNCLK_BASEADDR     XPAR_AXI_DYNCLK_0_S_AXI_LITE_BASEADDR
#define VDMA_ID             XPAR_AXIVDMA_0_DEVICE_ID
#define HDMI_OUT_VTC_ID     XPAR_V_TC_OUT_DEVICE_ID
#define SCU_TIMER_ID        XPAR_SCUTIMER_DEVICE_ID
#define UART_BASEADDR       XPAR_PS7_UART_1_BASEADDR

/*
 * Brightness filter IP. Update FILTER_BASE_ADDR to match Vivado's
 * Address Editor for your design (or use the auto-generated macro
 * from xparameters.h, commented out below).
 */
#define FILTER_BASE_ADDR        XPAR_AUDIO_VIDEO_FILTER_0_BASEADDR
#define FILTER_GAIN_REG_OFFSET  0x00
#define FILTER_GAIN_REG         (FILTER_BASE_ADDR + FILTER_GAIN_REG_OFFSET)

/* Q4.12 gain presets */
#define GAIN_BLACK              0x0000   /* 0.0x */
#define GAIN_HALF               0x0800   /* 0.5x */
#define GAIN_UNITY              0x1000   /* 1.0x */
#define GAIN_BRIGHT             0x1800   /* 1.5x */
#define GAIN_DOUBLE             0x2000   /* 2.0x */

#define BRIGHTNESS_MIN_Q412		0x0100
#define BRIGHTNESS_MAX_Q412 	0x4000

#define BRIGHTNESS_STEP_NUM		11
#define BRIGHTNESS_STEP_DEN		10



/* ------------------------------------------------------------ */
/*  Globals                                                     */
/* ------------------------------------------------------------ */

DisplayCtrl  dispCtrl;
XAxiVdma     vdma;
FilterMode   currentMode = MODE_PASSTHROUGH;

/* Framebuffer(s). One frame is enough for a static pattern. */
u8 frameBuf[DISPLAY_NUM_FRAMES][DEMO_MAX_FRAME] __attribute__((aligned(0x20)));
u8 *pFrames[DISPLAY_NUM_FRAMES];

/* ------------------------------------------------------------ */
/*  Filter control                                              */
/* ------------------------------------------------------------ */

void FilterSetGain(u32 gain_q4_12)
{
    Xil_Out32(FILTER_GAIN_REG, gain_q4_12);
}

static u32 current_gain = GAIN_UNITY;

void BrightnessUp(void)
{
	u32 next = (current_gain * BRIGHTNESS_STEP_NUM) / BRIGHTNESS_STEP_DEN;
	if (next > BRIGHTNESS_MAX_Q412) {
		next = BRIGHTNESS_MAX_Q412;
	}

	current_gain = next;
	FilterSetGain(current_gain);
	xil_printf("	brighter: gain = 0x%04X (%d.%03dx)\n\r",
				(unsigned int) current_gain,
				(unsigned int) (current_gain >> 12),
				(unsigned int) (((current_gain & 0xFFF) * 1000) >> 12));
}

void BrightnessDown(void)
{
	u32 next = (current_gain * BRIGHTNESS_STEP_DEN) / BRIGHTNESS_STEP_NUM;
	if (next < BRIGHTNESS_MIN_Q412) {
		next = BRIGHTNESS_MIN_Q412;
	}

	current_gain = next;
	FilterSetGain(current_gain);
	xil_printf("	dimmer: gain = 0x%04X (%d.%03dx)\n\r",
				(unsigned int) current_gain,
				(unsigned int) (current_gain >> 12),
				(unsigned int) (((current_gain & 0xFFF) * 1000) >> 12));
}

void BrightnessReset(void)
{
	current_gain = GAIN_UNITY;
	FilterSetGain(current_gain);
	xil_printf("	brightness reset: gain = 0x1000 (1.000x)\n\r");
}

void FilterSetMode(FilterMode mode)
{
    currentMode = mode;
    BrightnessReset();
    if (mode == MODE_PASSTHROUGH) {
        xil_printf("\n\rMode: PASSTHROUGH (gain = 1.0x)\n\r");
    } else {
        xil_printf("\n\rMode: BRIGHTNESS (placeholder pulse)\n\r");
    }
}

/* ------------------------------------------------------------ */
/*  Test pattern generators                                     */
/*                                                              */
/*  Frame layout: stride bytes per line, 3 bytes per pixel.     */
/*  Byte order follows the Digilent demo: [R, B, G] per pixel.  */
/*  (Yes, R-B-G, not R-G-B -- the dvi2rgb pipeline orders       */
/*  channels this way on the Zybo.)                             */
/* ------------------------------------------------------------ */

/*
 * Classic 7-bar color pattern: white, yellow, cyan, green,
 * magenta, red, blue. Vertical bars across the full height.
 */
void DrawColorBars(u8 *frame, u32 width, u32 height, u32 stride)
{
    static const u8 bars[7][3] = {
        /* R    B    G  */
        { 255, 255, 255 },   /* white   */
        { 255,   0, 255 },   /* yellow  */
        {   0, 255, 255 },   /* cyan    */
        {   0,   0, 255 },   /* green   */
        { 255, 255,   0 },   /* magenta */
        { 255,   0,   0 },   /* red     */
        {   0, 255,   0 }    /* blue    */
    };

    u32 barWidth = width / 7;
    u32 y, x;

    for (y = 0; y < height; y++) {
        u8 *line = frame + y * stride;
        for (x = 0; x < width; x++) {
            u32 bar = x / barWidth;
            if (bar > 6) bar = 6;  /* last partial bar = blue */
            line[x * 3 + 0] = bars[bar][0];   /* R */
            line[x * 3 + 1] = bars[bar][1];   /* B */
            line[x * 3 + 2] = bars[bar][2];   /* G */
        }
    }

    Xil_DCacheFlushRange((unsigned int) frame, DEMO_MAX_FRAME);
}

/*
 * Horizontal gradient: black on the left, white on the right.
 * Useful for checking brightness behavior across the full range
 * -- when the filter dims or brightens, you can see the whole
 * tonal response curve at once.
 */
void DrawGradient(u8 *frame, u32 width, u32 height, u32 stride)
{
    u32 y, x;
    for (y = 0; y < height; y++) {
        u8 *line = frame + y * stride;
        for (x = 0; x < width; x++) {
            u8 v = (u8)((x * 255) / (width - 1));
            line[x * 3 + 0] = v;   /* R */
            line[x * 3 + 1] = v;   /* B */
            line[x * 3 + 2] = v;   /* G */
        }
    }
    Xil_DCacheFlushRange((unsigned int) frame, DEMO_MAX_FRAME);
}

/*
 * Solid color fill -- handy for sanity-checking that pixels
 * are reaching the display at all.
 */
void DrawSolidColor(u8 *frame, u32 width, u32 height, u32 stride,
                    u8 r, u8 g, u8 b)
{
    u32 y, x;
    for (y = 0; y < height; y++) {
        u8 *line = frame + y * stride;
        for (x = 0; x < width; x++) {
            line[x * 3 + 0] = r;
            line[x * 3 + 1] = b;
            line[x * 3 + 2] = g;
        }
    }
    Xil_DCacheFlushRange((unsigned int) frame, DEMO_MAX_FRAME);
}

/* ------------------------------------------------------------ */
/*  Main                                                        */
/* ------------------------------------------------------------ */

int main(void)
{
    DemoInitialize();
    DemoRun();
    return 0;
}

/* ------------------------------------------------------------ */
/*  Initialization                                              */
/* ------------------------------------------------------------ */

void DemoInitialize(void)
{
    int Status;
    XAxiVdma_Config *vdmaConfig;
    int i;

    for (i = 0; i < DISPLAY_NUM_FRAMES; i++) {
        pFrames[i] = frameBuf[i];
    }

    TimerInitialize(SCU_TIMER_ID);

    /* VDMA */
    vdmaConfig = XAxiVdma_LookupConfig(VDMA_ID);
    if (!vdmaConfig) {
        xil_printf("No video DMA found for ID %d\r\n", VDMA_ID);
        return;
    }
    Status = XAxiVdma_CfgInitialize(&vdma, vdmaConfig, vdmaConfig->BaseAddress);
    if (Status != XST_SUCCESS) {
        xil_printf("VDMA Configuration Initialization failed %d\r\n", Status);
        return;
    }

    /* Display controller (HDMI Out only) */
    Status = DisplayInitialize(&dispCtrl, &vdma, HDMI_OUT_VTC_ID,
                               DYNCLK_BASEADDR, pFrames, DEMO_STRIDE);
    if (Status != XST_SUCCESS) {
        xil_printf("Display Ctrl initialization failed %d\r\n", Status);
        return;
    }

    Status = DisplayStart(&dispCtrl);
    if (Status != XST_SUCCESS) {
        xil_printf("Couldn't start display %d\r\n", Status);
        return;
    }

    /* Draw the initial test pattern into the active frame */
    DrawColorBars(pFrames[dispCtrl.curFrame],
                  dispCtrl.vMode.width,
                  dispCtrl.vMode.height,
                  DEMO_STRIDE);

    /* Start in passthrough mode */
    FilterSetMode(MODE_PASSTHROUGH);
}

/* ------------------------------------------------------------ */
/*  Main loop                                                   */
/* ------------------------------------------------------------ */

void DemoRun(void)
{
    char userInput = 0;

    /* Flush UART FIFO */
    while (XUartPs_IsReceiveData(UART_BASEADDR)) {
        XUartPs_ReadReg(UART_BASEADDR, XUARTPS_FIFO_OFFSET);
    }

    while (userInput != 'q')
    {
        DemoPrintMenu();

        while (!XUartPs_IsReceiveData(UART_BASEADDR)) {}
        userInput = XUartPs_ReadReg(UART_BASEADDR, XUARTPS_FIFO_OFFSET);
        xil_printf("%c", userInput);

        switch (userInput)
        {
            case '1':
                FilterSetMode(MODE_PASSTHROUGH);
                TimerDelay(500000);
                break;

            case '2':
                FilterSetMode(MODE_BRIGHTNESS);
                TimerDelay(500000);
                break;

            case 'b':
                if (currentMode == MODE_BRIGHTNESS) {
                    BrightnessUp();
                } else {
                    xil_printf("\n\r(Switch to brightness mode first with '2')\n\r");
                }
                TimerDelay(500000);
                break;
            case 'd':
            	if (currentMode == MODE_BRIGHTNESS) {
					BrightnessDown();
				} else {
					xil_printf("\n\r(Switch to brightness mode first with '2')\n\r");
				}
				TimerDelay(500000);
            	break;

            case 'c':
                DrawColorBars(pFrames[dispCtrl.curFrame],
                              dispCtrl.vMode.width,
                              dispCtrl.vMode.height,
                              DEMO_STRIDE);
                xil_printf("\n\rDrew color bars\n\r");
                TimerDelay(500000);
                break;

            case 'g':
                DrawGradient(pFrames[dispCtrl.curFrame],
                             dispCtrl.vMode.width,
                             dispCtrl.vMode.height,
                             DEMO_STRIDE);
                xil_printf("\n\rDrew gradient\n\r");
                TimerDelay(500000);
                break;

            case 'w':
                DrawSolidColor(pFrames[dispCtrl.curFrame],
                               dispCtrl.vMode.width,
                               dispCtrl.vMode.height,
                               DEMO_STRIDE, 255, 255, 255);
                xil_printf("\n\rDrew solid white\n\r");
                TimerDelay(500000);
                break;

            case 'k':
                DrawSolidColor(pFrames[dispCtrl.curFrame],
                               dispCtrl.vMode.width,
                               dispCtrl.vMode.height,
                               DEMO_STRIDE, 0, 0, 0);
                xil_printf("\n\rDrew solid black\n\r");
                TimerDelay(500000);
                break;

            case 'q':
                break;

            default:
                xil_printf("\n\rInvalid selection");
                TimerDelay(500000);
        }
    }
}

/* ------------------------------------------------------------ */
/*  UI                                                          */
/* ------------------------------------------------------------ */

void DemoPrintMenu(void)
{
    xil_printf("\x1B[H");
    xil_printf("\x1B[2J");
    xil_printf("**************************************************\n\r");
    xil_printf("*    ENGS 128 Audio-Reactive Video Filter        *\n\r");
    xil_printf("*           (display-only bring-up)              *\n\r");
    xil_printf("**************************************************\n\r");
    xil_printf("*Display Resolution: %28s*\n\r", dispCtrl.vMode.label);
    xil_printf("*Filter Mode:        %28s*\n\r",
               (currentMode == MODE_PASSTHROUGH) ? "PASSTHROUGH" : "BRIGHTNESS");
    xil_printf("**************************************************\n\r");
    xil_printf("\n\r");
    xil_printf("Filter:\n\r");
    xil_printf("  1 - Passthrough  (gain = 1.0x)\n\r");
    xil_printf("  2 - Brightness   \n\r");
    xil_printf("  b - Step brightness up\n\r");
    xil_printf("  d - Step brightness down\n\r");
    xil_printf("\n\r");
    xil_printf("Test pattern:\n\r");
    xil_printf("  c - Color bars\n\r");
    xil_printf("  g - Gradient (black -> white)\n\r");
    xil_printf("  w - Solid white\n\r");
    xil_printf("  k - Solid black\n\r");
    xil_printf("\n\r");
    xil_printf("  q - Quit\n\r");
    xil_printf("\n\rEnter a selection: ");
}

