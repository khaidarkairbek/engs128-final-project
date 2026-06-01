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
static int sCalibrating;
static int sCalibrated;
static uint64_t sEnergy[3];
static uint64_t sCalibrationTotal[3];
static uint64_t sBaseline[3];
static uint32_t sGain[3];
static BinRange sRanges[3];
static uint32_t sTraceUpdateCount;
static uint32_t sCalibrationSampleCount;

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

static uint64_t AbsDiffU64(uint64_t a, uint64_t b)
{
    return (a > b) ? (a - b) : (b - a);
}

static uint32_t Log2Q8(uint64_t valueQ8)
{
    uint32_t whole = 0U;
    uint64_t base = 256U;

    while (valueQ8 >= (base << 1U)) {
        base <<= 1U;
        ++whole;
    }

    /*
     * Linear interpolation within each power-of-two interval is sufficient
     * for a visual control signal and avoids floating-point math on the ARM.
     */
    return (whole << 8U) + (uint32_t)(((valueQ8 - base) << 8U) / base);
}

static uint32_t EnergyToTargetGain(uint64_t energy, uint64_t baseline)
{
    uint64_t difference = AbsDiffU64(energy, baseline);
    uint64_t deadband = (baseline * APP_CALIBRATION_DEADBAND_PERCENT) / 100U;
    uint64_t span = (baseline > APP_CALIBRATION_MIN_SPAN) ?
                    baseline : APP_CALIBRATION_MIN_SPAN;
    uint64_t ratioQ8;
    uint32_t responseLevelQ8;
    uint32_t maxResponseLevelQ8 = Log2Q8(APP_RESPONSE_MAX_RATIO << 8U);

    if (difference <= deadband) {
        return APP_GAIN_UNITY_Q412;
    }
    difference -= deadband;
    ratioQ8 = (difference << 8U) / span;
    if (ratioQ8 >= (APP_RESPONSE_MAX_RATIO << 8U)) {
        return APP_GAIN_MIN_Q412;
    }

    /*
     * Add one so sub-baseline differences remain near unity and the response
     * grows gradually as the deviation crosses powers of two.
     */
    responseLevelQ8 = Log2Q8(ratioQ8 + 256U);
    return APP_GAIN_UNITY_Q412 -
           (responseLevelQ8 * (APP_GAIN_UNITY_Q412 - APP_GAIN_MIN_Q412)) /
           maxResponseLevelQ8;
}

static uint32_t SmoothGain(uint32_t current, uint32_t target)
{
    if (target < current) {
        return current - (current - target + 1U) / 2U;
    }
    return current + (target - current + 7U) / 8U;
}

static void SetUnityGain(void)
{
    sGain[0] = sGain[1] = sGain[2] = APP_GAIN_UNITY_Q412;
    VideoApp_SetGain(sGain[0], sGain[1], sGain[2]);
}

void AudioReactive_Init(void)
{
    sPolicy = BAND_POLICY_MUSICAL;
    sEnabled = 1;
    sGainTraceEnabled = 0;
    sCalibrating = 0;
    sCalibrated = 0;
    sTraceUpdateCount = 0U;
    sEnergy[0] = sEnergy[1] = sEnergy[2] = 0U;
    sBaseline[0] = sBaseline[1] = sBaseline[2] = 0U;
    ConfigureRanges();
    SetUnityGain();
    xil_printf("Reactive mode waiting for calibration; press 'c' in silence\r\n");
}

void AudioReactive_Update(void)
{
    uint32_t i;

    for (i = 0U; i < 3U; ++i) {
        sEnergy[i] = AverageRange(sRanges[i]);
    }

    if (sEnabled && sCalibrating) {
        for (i = 0U; i < 3U; ++i) {
            sCalibrationTotal[i] += sEnergy[i];
        }
        ++sCalibrationSampleCount;
        if (sCalibrationSampleCount >= APP_CALIBRATION_SAMPLE_COUNT) {
            for (i = 0U; i < 3U; ++i) {
                sBaseline[i] = sCalibrationTotal[i] /
                               APP_CALIBRATION_SAMPLE_COUNT;
            }
            sCalibrating = 0;
            sCalibrated = 1;
            xil_printf("Calibration complete: baseline=%lu/%lu/%lu\r\n",
                       (unsigned long)sBaseline[0],
                       (unsigned long)sBaseline[1],
                       (unsigned long)sBaseline[2]);
        }
    } else if (sEnabled && sCalibrated) {
        for (i = 0U; i < 3U; ++i) {
            sGain[i] = SmoothGain(sGain[i],
                                  EnergyToTargetGain(sEnergy[i], sBaseline[i]));
        }
        VideoApp_SetGain(sGain[0], sGain[1], sGain[2]);
    }

    if (sGainTraceEnabled &&
        ++sTraceUpdateCount >= APP_GAIN_TRACE_DIVIDER) {
        sTraceUpdateCount = 0U;
        xil_printf("gain trace: energy=%lu/%lu/%lu base=%lu/%lu/%lu gain=%04x/%04x/%04x\r\n",
                   (unsigned long)sEnergy[0], (unsigned long)sEnergy[1],
                   (unsigned long)sEnergy[2], (unsigned long)sBaseline[0],
                   (unsigned long)sBaseline[1], (unsigned long)sBaseline[2],
                   (unsigned int)sGain[0], (unsigned int)sGain[1],
                   (unsigned int)sGain[2]);
    }
}

void AudioReactive_SetEnabled(int enabled)
{
    sEnabled = enabled != 0;
    if (!sEnabled) {
        SetUnityGain();
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
    sCalibrating = 0;
    sCalibrated = 0;
    SetUnityGain();
    xil_printf("Band policy: %s\r\n",
               (sPolicy == BAND_POLICY_MUSICAL) ? "musical" : "equal thirds");
    xil_printf("Band ranges changed; press 'c' in silence to recalibrate\r\n");
}

void AudioReactive_ToggleGainTrace(void)
{
    sGainTraceEnabled = !sGainTraceEnabled;
    sTraceUpdateCount = 0U;
    xil_printf("Gain trace: %s\r\n", sGainTraceEnabled ? "on" : "off");
}

void AudioReactive_StartCalibration(void)
{
    uint32_t i;

    sEnabled = 1;
    sCalibrating = 1;
    sCalibrated = 0;
    sCalibrationSampleCount = 0U;
    for (i = 0U; i < 3U; ++i) {
        sCalibrationTotal[i] = 0U;
        sBaseline[i] = 0U;
    }
    SetUnityGain();
    xil_printf("Calibration started: keep audio quiet for about %d seconds\r\n",
               (int)((APP_CALIBRATION_SAMPLE_COUNT * APP_UPDATE_INTERVAL_US +
                      999999U) / 1000000U));
}

void AudioReactive_PrintDiagnostics(void)
{
    xil_printf("FFT: %d points, %d Hz sample rate, policy=%s, reactive=%s, trace=%s, calibration=%s\r\n",
               (int)APP_FFT_LENGTH, (int)APP_SAMPLE_RATE_HZ,
               (sPolicy == BAND_POLICY_MUSICAL) ? "musical" : "equal thirds",
               sEnabled ? "on" : "off", sGainTraceEnabled ? "on" : "off",
               sCalibrating ? "running" : (sCalibrated ? "ready" : "required"));
    xil_printf("Calibration: samples=%d/%d deadband=%d%% min_span=%lu max_ratio=%d\r\n",
               (int)sCalibrationSampleCount, (int)APP_CALIBRATION_SAMPLE_COUNT,
               (int)APP_CALIBRATION_DEADBAND_PERCENT,
               (unsigned long)APP_CALIBRATION_MIN_SPAN,
               (int)APP_RESPONSE_MAX_RATIO);
    xil_printf("R bins [%d,%d) energy=%lu base=%lu gain=0x%04x\r\n",
               (int)sRanges[0].begin, (int)sRanges[0].end,
               (unsigned long)sEnergy[0], (unsigned long)sBaseline[0],
               (unsigned int)sGain[0]);
    xil_printf("G bins [%d,%d) energy=%lu base=%lu gain=0x%04x\r\n",
               (int)sRanges[1].begin, (int)sRanges[1].end,
               (unsigned long)sEnergy[1], (unsigned long)sBaseline[1],
               (unsigned int)sGain[1]);
    xil_printf("B bins [%d,%d) energy=%lu base=%lu gain=0x%04x\r\n",
               (int)sRanges[2].begin, (int)sRanges[2].end,
               (unsigned long)sEnergy[2], (unsigned long)sBaseline[2],
               (unsigned int)sGain[2]);
}
