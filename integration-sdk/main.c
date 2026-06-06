#include "app_config.h"
#include "audio/audio.h"
#include "iic/iic.h"
#include "video_app.h"
#include "xiic.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "xuartps.h"

static XIic sIic;

static void PrintMenu(void)
{
    xil_printf("\r\nENGS 128 HDMI video\r\n");
    xil_printf("  t next source | b color bars | g gradient | h live HDMI passthrough\r\n");
    xil_printf("  s status | ? menu\r\n");
}

static void HandleKey(char key)
{
    switch (key) {
    case 't':
        (void)VideoApp_CycleSource();
        break;
    case 'b':
        VideoApp_ShowColorBars();
        break;
    case 'g':
        VideoApp_ShowGradient();
        break;
    case 'h':
        (void)VideoApp_SelectLiveHdmi();
        break;
    case 's':
        VideoApp_PrintDiagnostics();
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
    PrintMenu();

    while (1) {
        if (XUartPs_IsReceiveData(APP_UART_BASE)) {
            HandleKey((char)XUartPs_ReadReg(APP_UART_BASE, XUARTPS_FIFO_OFFSET));
        }

        VideoApp_Service();
    }
}
