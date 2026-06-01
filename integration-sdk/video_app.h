#ifndef VIDEO_APP_H
#define VIDEO_APP_H

#include "xiic.h"
#include "xil_types.h"

int VideoApp_Init(void);
void VideoApp_EnableInterrupts(XIic *iic);
void VideoApp_Service(void);
void VideoApp_SetGain(u32 r, u32 g, u32 b);
void VideoApp_ShowColorBars(void);
void VideoApp_ShowGradient(void);
int VideoApp_SelectLiveHdmi(void);
void VideoApp_CycleManualGain(void);
void VideoApp_PrintDiagnostics(void);

#endif
