#include "audio_reactive.h"

#include <stdint.h>
#include "app_config.h"
#include "video_app.h"
#include "xil_io.h"
#include "xil_printf.h"

typedef struct {
    uint32_t begin;
    uint32_t end;
} BinRange;

typedef enum {
    BAND_POLICY_MUSICAL = 0,
    BAND_POLICY_EQUAL_THIRDS = 1
} BandPolicy;

static BandPolicy sPolicy;
static int sEnabled;
static int sGainTraceEnabled;
static uint64_t sEnergy[3];
static uint32_t sGain[3];
static BinRange sRanges[3];
static uint32_t sTraceUpdateCount;
static const int32_t sLog2Adjust[3] = {
    APP_RED_LOG2_ADJUST,
    APP_GREEN_LOG2_ADJUST,
    APP_BLUE_LOG2_ADJUST
};

static uint32_t MinU32(uint32_t a, uint32_t b)
{
    return (a < b) ? a : b;
}

static uint32_t HzToBinCeiling(uint32_t hz)
{
    return (hz * APP_FFT_LENGTH + APP_SAMPLE_RATE_HZ - 1U) /
           APP_SAMPLE_RATE_HZ;
}

static void ConfigureRanges(void)
{
    const uint32_t end = APP_USEFUL_BIN_COUNT;

    if (sPolicy == BAND_POLICY_EQUAL_THIRDS) {
        const uint32_t count = end - 1U;
        sRanges[0].begin = 1U;
        sRanges[0].end = 1U + count / 3U;
        sRanges[1].begin = sRanges[0].end;
        sRanges[1].end = 1U + (2U * count) / 3U;
        sRanges[2].begin = sRanges[1].end;
        sRanges[2].end = end;
        return;
    }

    sRanges[0].begin = 1U;
    sRanges[0].end = MinU32(HzToBinCeiling(APP_MUSICAL_RED_END_HZ), end);
    sRanges[1].begin = sRanges[0].end;
    sRanges[1].end = MinU32(HzToBinCeiling(APP_MUSICAL_GREEN_END_HZ), end);
    sRanges[2].begin = sRanges[1].end;
    sRanges[2].end = end;
}

static uint64_t ReadStereoMagnitude(uint32_t bin)
{
    uint64_t left = Xil_In32(APP_BRAM_LEFT_BASE + bin * sizeof(uint32_t));
    uint64_t right = Xil_In32(APP_BRAM_RIGHT_BASE + bin * sizeof(uint32_t));

    return (left + right) / 2U;
}

static uint64_t AverageRange(BinRange range)
{
    uint64_t total = 0U;
    uint32_t bin;

    if (range.end <= range.begin) {
        return 0U;
    }

    for (bin = range.begin; bin < range.end; ++bin) {
        total += ReadStereoMagnitude(bin);
    }

    return total / (range.end - range.begin);
}

static uint32_t Log2U64(uint64_t value)
{
    uint32_t result = 0U;

    while (value > 1U) {
        value >>= 1U;
        ++result;
    }

    return result;
}

static uint32_t EnergyToTargetGain(uint64_t energy, int32_t log2Adjust)
{
    int32_t level = (int32_t)Log2U64(energy) + log2Adjust;
    int32_t span = APP_ACTIVITY_LOG2_CEILING - APP_ACTIVITY_LOG2_FLOOR;
    uint32_t boost;

    if (level <= APP_ACTIVITY_LOG2_FLOOR) {
        return APP_GAIN_MIN_Q412;
    }
    if (level >= APP_ACTIVITY_LOG2_CEILING) {
        return APP_GAIN_MAX_Q412;
    }

    boost = ((level - APP_ACTIVITY_LOG2_FLOOR) *
             (APP_GAIN_MAX_Q412 - APP_GAIN_MIN_Q412)) / span;
    return APP_GAIN_MIN_Q412 + boost;
}

static uint32_t SmoothGain(uint32_t current, uint32_t target)
{
    if (target > current) {
        return current + (target - current + 1U) / 2U;
    }
    return current - (current - target + 7U) / 8U;
}

void AudioReactive_Init(void)
{
    sPolicy = BAND_POLICY_MUSICAL;
    sEnabled = 1;
    sGainTraceEnabled = 0;
    sTraceUpdateCount = 0U;
    sEnergy[0] = sEnergy[1] = sEnergy[2] = 0U;
    sGain[0] = sGain[1] = sGain[2] = APP_GAIN_UNITY_Q412;
    ConfigureRanges();
    VideoApp_SetGain(sGain[0], sGain[1], sGain[2]);
}

void AudioReactive_Update(void)
{
    uint32_t i;

    if (!sEnabled) {
        return;
    }

    for (i = 0U; i < 3U; ++i) {
        sEnergy[i] = AverageRange(sRanges[i]);
        sGain[i] = SmoothGain(sGain[i],
                              EnergyToTargetGain(sEnergy[i], sLog2Adjust[i]));
    }

    VideoApp_SetGain(sGain[0], sGain[1], sGain[2]);
    if (sGainTraceEnabled &&
        ++sTraceUpdateCount >= APP_GAIN_TRACE_DIVIDER) {
        sTraceUpdateCount = 0U;
        xil_printf("gain trace: energy=%lu/%lu/%lu gain=%04x/%04x/%04x\r\n",
                   (unsigned long)sEnergy[0], (unsigned long)sEnergy[1],
                   (unsigned long)sEnergy[2], (unsigned int)sGain[0],
                   (unsigned int)sGain[1], (unsigned int)sGain[2]);
    }
}

void AudioReactive_SetEnabled(int enabled)
{
    sEnabled = enabled != 0;
    if (!sEnabled) {
        sGain[0] = sGain[1] = sGain[2] = APP_GAIN_UNITY_Q412;
        VideoApp_SetGain(sGain[0], sGain[1], sGain[2]);
    }
    xil_printf("Audio reactive: %s\r\n", sEnabled ? "on" : "off");
}

void AudioReactive_ToggleEnabled(void)
{
    AudioReactive_SetEnabled(!sEnabled);
}

void AudioReactive_ToggleBandPolicy(void)
{
    sPolicy = (sPolicy == BAND_POLICY_MUSICAL) ?
              BAND_POLICY_EQUAL_THIRDS : BAND_POLICY_MUSICAL;
    ConfigureRanges();
    xil_printf("Band policy: %s\r\n",
               (sPolicy == BAND_POLICY_MUSICAL) ? "musical" : "equal thirds");
}

void AudioReactive_ToggleGainTrace(void)
{
    sGainTraceEnabled = !sGainTraceEnabled;
    sTraceUpdateCount = 0U;
    xil_printf("Gain trace: %s\r\n", sGainTraceEnabled ? "on" : "off");
}

void AudioReactive_PrintDiagnostics(void)
{
    xil_printf("FFT: %d points, %d Hz sample rate, policy=%s, reactive=%s, trace=%s\r\n",
               (int)APP_FFT_LENGTH, (int)APP_SAMPLE_RATE_HZ,
               (sPolicy == BAND_POLICY_MUSICAL) ? "musical" : "equal thirds",
               sEnabled ? "on" : "off", sGainTraceEnabled ? "on" : "off");
    xil_printf("Response: log2 window=[%d,%d], adjust=%d/%d/%d, gain_range=0x%04x..0x%04x\r\n",
               APP_ACTIVITY_LOG2_FLOOR, APP_ACTIVITY_LOG2_CEILING,
               APP_RED_LOG2_ADJUST, APP_GREEN_LOG2_ADJUST,
               APP_BLUE_LOG2_ADJUST, (unsigned int)APP_GAIN_MIN_Q412,
               (unsigned int)APP_GAIN_MAX_Q412);
    xil_printf("R bins [%d,%d) energy=%lu gain=0x%04x\r\n",
               (int)sRanges[0].begin, (int)sRanges[0].end,
               (unsigned long)sEnergy[0], (unsigned int)sGain[0]);
    xil_printf("G bins [%d,%d) energy=%lu gain=0x%04x\r\n",
               (int)sRanges[1].begin, (int)sRanges[1].end,
               (unsigned long)sEnergy[1], (unsigned int)sGain[1]);
    xil_printf("B bins [%d,%d) energy=%lu gain=0x%04x\r\n",
               (int)sRanges[2].begin, (int)sRanges[2].end,
               (unsigned long)sEnergy[2], (unsigned int)sGain[2]);
}
