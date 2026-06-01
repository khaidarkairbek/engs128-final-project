#ifndef AUDIO_REACTIVE_H
#define AUDIO_REACTIVE_H

void AudioReactive_Init(void);
void AudioReactive_Update(void);
void AudioReactive_SetEnabled(int enabled);
void AudioReactive_ToggleEnabled(void);
void AudioReactive_ToggleBandPolicy(void);
void AudioReactive_ToggleGainTrace(void);
void AudioReactive_PrintDiagnostics(void);

#endif
