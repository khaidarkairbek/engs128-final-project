#include "app_config.h"
#include "audio/audio.h"
#include "audio_reactive.h"
#include "iic/iic.h"
#include "video_app.h"
#include "xiic.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "xtime_l.h"
#include "xuartps.h"

static XIic sIic;

static void PrintMenu(void)
{
    xil_printf("\r\nENGS 128 audio-reactive video\r\n");
    xil_printf("  a reactive toggle | c color bars | d gradient | h live HDMI\r\n");
    xil_printf("  m manual gain test | p band policy | s status | q unity gain\r\n");
}

static void HandleKey(char key)
{
    switch (key) {
    case 'a':
        AudioReactive_ToggleEnabled();
        break;
    case 'c':
        VideoApp_ShowColorBars();
        break;
    case 'd':
        VideoApp_ShowGradient();
        break;
    case 'h':
        (void)VideoApp_SelectLiveHdmi();
        break;
    case 'm':
        AudioReactive_SetEnabled(0);
        VideoApp_CycleManualGain();
        break;
    case 'p':
        AudioReactive_ToggleBandPolicy();
        break;
    case 's':
        AudioReactive_PrintDiagnostics();
        VideoApp_PrintDiagnostics();
        break;
    case 'q':
        AudioReactive_SetEnabled(0);
        xil_printf("Unity gain selected\r\n");
        break;
    case '?':
        PrintMenu();
        break;
    default:
        break;
    }
}

int main(void)
{
    XTime lastUpdate;
    int status;

    status = VideoApp_Init();
    if (status != XST_SUCCESS) {
        xil_printf("Video initialization failed: %d\r\n", status);
        return status;
    }

    status = fnInitIic(&sIic);
    if (status != XST_SUCCESS) {
        xil_printf("IIC initialization failed: %d\r\n", status);
        return status;
    }

    status = fnInitAudio();
    if (status != XST_SUCCESS) {
        xil_printf("Audio initialization failed: %d\r\n", status);
        return status;
    }
    fnSetLineInput();

    VideoApp_EnableInterrupts(&sIic);
    AudioReactive_Init();
    PrintMenu();
    XTime_GetTime(&lastUpdate);

    while (1) {
        XTime now;

        if (XUartPs_IsReceiveData(APP_UART_BASE)) {
            HandleKey((char)XUartPs_ReadReg(APP_UART_BASE, XUARTPS_FIFO_OFFSET));
        }

        VideoApp_Service();
        XTime_GetTime(&now);
        if ((now - lastUpdate) >=
            (COUNTS_PER_SECOND / 1000000U) * APP_UPDATE_INTERVAL_US) {
            AudioReactive_Update();
            lastUpdate = now;
        }
    }
}
