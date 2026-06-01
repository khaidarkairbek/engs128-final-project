#include "video_app.h"

#include "app_config.h"
#include "display_ctrl/display_ctrl.h"
#include "intc/intc.h"
#include "video_capture/video_capture.h"
#include "xaxivdma.h"
#include "xgpio.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"

typedef enum {
    SOURCE_COLOR_BARS = 0,
    SOURCE_GRADIENT = 1,
    SOURCE_LIVE_HDMI = 2
} VideoSource;

static INTC sIntc;
static XAxiVdma sVdma;
static DisplayCtrl sDisplay;
static VideoCapture sCapture;
static VideoSource sSource;
static volatile int sCaptureEvent;
static u32 sGain[3];
static unsigned int sManualPreset;

static u8 sFrameBuf[DISPLAY_NUM_FRAMES][APP_FRAME_BYTES_MAX]
    __attribute__((aligned(0x20)));
static u8 *sFrames[DISPLAY_NUM_FRAMES];

static const VideoMode *FindMode(u32 width, u32 height)
{
    if (width == 640U && height == 480U) return &VMODE_640x480;
    if (width == 800U && height == 600U) return &VMODE_800x600;
    if (width == 1280U && height == 720U) return &VMODE_1280x720;
    if (width == 1280U && height == 1024U) return &VMODE_1280x1024;
    if (width == 1600U && height == 900U) return &VMODE_1600x900;
    if (width == 1920U && height == 1080U) return &VMODE_1920x1080;
    return NULL;
}

static int ConfigureDisplay(const VideoMode *mode, u32 frame)
{
    int status;

    status = DisplaySetMode(&sDisplay, mode);
    if (status != XST_SUCCESS) return status;
    status = DisplayChangeFrame(&sDisplay, frame);
    if (status != XST_SUCCESS) return status;
    return DisplayStart(&sDisplay);
}

static void FillColorBars(u8 *frame, u32 width, u32 height)
{
    static const u8 bars[7][3] = {
        {255, 255, 255}, {255, 0, 255}, {0, 255, 255}, {0, 0, 255},
        {255, 255, 0}, {255, 0, 0}, {0, 255, 0}
    };
    u32 x;
    u32 y;
    u32 barWidth = width / 7U;

    for (y = 0U; y < height; ++y) {
        u8 *line = frame + y * APP_FRAME_STRIDE;
        for (x = 0U; x < width; ++x) {
            u32 bar = x / barWidth;
            if (bar > 6U) bar = 6U;
            line[x * 3U] = bars[bar][0];
            line[x * 3U + 1U] = bars[bar][1];
            line[x * 3U + 2U] = bars[bar][2];
        }
    }
    Xil_DCacheFlushRange((UINTPTR)frame, APP_FRAME_BYTES_MAX);
}

static void FillGradient(u8 *frame, u32 width, u32 height)
{
    u32 x;
    u32 y;

    for (y = 0U; y < height; ++y) {
        u8 *line = frame + y * APP_FRAME_STRIDE;
        for (x = 0U; x < width; ++x) {
            u8 value = (u8)((x * 255U) / (width - 1U));
            line[x * 3U] = value;
            line[x * 3U + 1U] = value;
            line[x * 3U + 2U] = value;
        }
    }
    Xil_DCacheFlushRange((UINTPTR)frame, APP_FRAME_BYTES_MAX);
}

static void CaptureCallback(void *callbackRef, void *video)
{
    (void)callbackRef;
    (void)video;
    sCaptureEvent = 1;
}

static int ActivateLiveIfReady(void)
{
    const VideoMode *mode;
    int status;

    if (sCapture.state == VIDEO_DISCONNECTED) {
        return XST_NO_DATA;
    }

    mode = FindMode(sCapture.timing.HActiveVideo, sCapture.timing.VActiveVideo);
    if (mode == NULL) {
        xil_printf("Unsupported HDMI mode: %dx%d; returning to color bars\r\n",
                   (int)sCapture.timing.HActiveVideo,
                   (int)sCapture.timing.VActiveVideo);
        VideoApp_ShowColorBars();
        return XST_FAILURE;
    }

    if (sCapture.state == VIDEO_PAUSED) {
        status = VideoStart(&sCapture);
        if (status != XST_SUCCESS) {
            xil_printf("Could not start HDMI capture: %d\r\n", status);
            return status;
        }
    }

    Xil_DCacheInvalidateRange((UINTPTR)sFrames[sCapture.curFrame],
                              APP_FRAME_BYTES_MAX);
    status = ConfigureDisplay(mode, sCapture.curFrame);
    if (status == XST_SUCCESS) {
        xil_printf("Live HDMI: %s\r\n", mode->label);
    }
    return status;
}

int VideoApp_Init(void)
{
    XAxiVdma_Config *vdmaConfig;
    int status;
    int i;

    for (i = 0; i < DISPLAY_NUM_FRAMES; ++i) {
        sFrames[i] = sFrameBuf[i];
    }

    status = fnInitInterruptController(&sIntc);
    if (status != XST_SUCCESS) return status;

    vdmaConfig = XAxiVdma_LookupConfig(APP_VDMA_DEVICE_ID);
    if (vdmaConfig == NULL) return XST_FAILURE;
    status = XAxiVdma_CfgInitialize(&sVdma, vdmaConfig,
                                    vdmaConfig->BaseAddress);
    if (status != XST_SUCCESS) return status;

    status = DisplayInitialize(&sDisplay, &sVdma, APP_VTC_OUT_DEVICE_ID,
                               APP_DYNCLK_BASE, sFrames, APP_FRAME_STRIDE);
    if (status != XST_SUCCESS) return status;

    status = VideoInitialize(&sCapture, &sIntc, &sVdma,
                             APP_GPIO_VIDEO_DEVICE_ID,
                             APP_VTC_IN_DEVICE_ID, APP_VTC_IN_IRQ_ID,
                             sFrames, APP_FRAME_STRIDE, 0U);
    if (status != XST_SUCCESS) return status;

    VideoSetCallback(&sCapture, CaptureCallback, NULL);
    sGain[0] = sGain[1] = sGain[2] = APP_GAIN_UNITY_Q412;
    sManualPreset = 0U;
    VideoApp_SetGain(sGain[0], sGain[1], sGain[2]);
    VideoApp_ShowColorBars();
    return XST_SUCCESS;
}

void VideoApp_EnableInterrupts(XIic *iic)
{
    const ivt_t vectors[] = {
        videoGpioIvt(APP_GPIO_VIDEO_IRQ_ID, &sCapture),
        videoVtcIvt(APP_VTC_IN_IRQ_ID, &sCapture.vtc),
        {APP_IIC_IRQ_ID, (XInterruptHandler)XIic_InterruptHandler,
         iic, 0xA0, 0x3}
    };

    fnEnableInterrupts(&sIntc, vectors, sizeof(vectors) / sizeof(vectors[0]));
}

void VideoApp_Service(void)
{
    if (!sCaptureEvent) return;
    sCaptureEvent = 0;

    if (sSource != SOURCE_LIVE_HDMI) return;
    if (sCapture.state == VIDEO_DISCONNECTED) {
        xil_printf("HDMI disconnected; returning to color bars\r\n");
        VideoApp_ShowColorBars();
        return;
    }
    (void)ActivateLiveIfReady();
}

void VideoApp_SetGain(u32 r, u32 g, u32 b)
{
    sGain[0] = r;
    sGain[1] = g;
    sGain[2] = b;
    Xil_Out32(APP_FILTER_BASE, r);
    Xil_Out32(APP_FILTER_BASE + 4U, g);
    Xil_Out32(APP_FILTER_BASE + 8U, b);
}

void VideoApp_ShowColorBars(void)
{
    sSource = SOURCE_COLOR_BARS;
    FillColorBars(sFrames[0], VMODE_640x480.width, VMODE_640x480.height);
    if (ConfigureDisplay(&VMODE_640x480, 0U) != XST_SUCCESS) {
        xil_printf("Could not display color bars\r\n");
    } else {
        xil_printf("Source: color bars\r\n");
    }
}

void VideoApp_ShowGradient(void)
{
    sSource = SOURCE_GRADIENT;
    FillGradient(sFrames[0], VMODE_640x480.width, VMODE_640x480.height);
    if (ConfigureDisplay(&VMODE_640x480, 0U) != XST_SUCCESS) {
        xil_printf("Could not display gradient\r\n");
    } else {
        xil_printf("Source: gradient\r\n");
    }
}

int VideoApp_SelectLiveHdmi(void)
{
    sSource = SOURCE_LIVE_HDMI;

    /*
     * Handle sources that were already locked before GPIO interrupts became
     * active. GpioIsr configures the input VTC detector and returns quickly.
     */
    if (sCapture.state == VIDEO_DISCONNECTED &&
        XGpio_DiscreteRead(&sCapture.gpio, LOCKED_CHANNEL) != 0U) {
        GpioIsr(&sCapture);
    }

    if (sCapture.state == VIDEO_DISCONNECTED) {
        xil_printf("Live HDMI requested; waiting for input lock\r\n");
        return XST_NO_DATA;
    }

    return ActivateLiveIfReady();
}

void VideoApp_CycleManualGain(void)
{
    static const u32 presets[][3] = {
        {APP_GAIN_UNITY_Q412, APP_GAIN_UNITY_Q412, APP_GAIN_UNITY_Q412},
        {APP_GAIN_MAX_Q412, APP_GAIN_UNITY_Q412, APP_GAIN_UNITY_Q412},
        {APP_GAIN_UNITY_Q412, APP_GAIN_MAX_Q412, APP_GAIN_UNITY_Q412},
        {APP_GAIN_UNITY_Q412, APP_GAIN_UNITY_Q412, APP_GAIN_MAX_Q412}
    };

    sManualPreset = (sManualPreset + 1U) %
                    (sizeof(presets) / sizeof(presets[0]));
    VideoApp_SetGain(presets[sManualPreset][0], presets[sManualPreset][1],
                     presets[sManualPreset][2]);
    xil_printf("Manual gain preset %d: R=0x%04x G=0x%04x B=0x%04x\r\n",
               (int)sManualPreset, (unsigned int)sGain[0],
               (unsigned int)sGain[1], (unsigned int)sGain[2]);
}

void VideoApp_PrintDiagnostics(void)
{
    static const char *const sourceNames[] = {"color bars", "gradient", "live HDMI"};
    xil_printf("Video: source=%s capture_state=%d display=%s gains=%04x/%04x/%04x\r\n",
               sourceNames[sSource], (int)sCapture.state, sDisplay.vMode.label,
               (unsigned int)sGain[0], (unsigned int)sGain[1],
               (unsigned int)sGain[2]);
}
