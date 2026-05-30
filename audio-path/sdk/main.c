/************************************************************************/
/*																		*/
/*	main.c	--	Zybo Tone Generator (AXI DDS)		 				*/
/*																		*/
/************************************************************************/
/*	Author: Kendall Farnham												*/
/*  ENGS 128 - Lab 1 SDK	with AXI DDS							*/
/************************************************************************/
/*  Modified from Digilent audio DMA demo (demo.c)								*/
/*  Original Author: Sam Lowe	(9/6/2016)								*/
/*	Copyright 2015, Digilent Inc.										*/
/************************************************************************/

#include <stdio.h>
#include "xil_printf.h"
#include "intc/intc.h"
#include "iic/iic.h"
#include "audio/audio.h"
#include "xuartps.h"		// contains UART driver for reading from terminal


// BSP/platform include files
#include "xparameters.h"
#include "xil_exception.h"
#include "xdebug.h"
#include "xiic.h"
#include "xtime_l.h"
#include "xscugic.h"
#include "sleep.h"
#include "xil_cache.h"

// Get hardware device IDs and memory addresses from xparameters.h
#define UART_DEVICE_ID XPAR_PS7_UART_1_DEVICE_ID
#define UART_BASEADDR XPAR_PS7_UART_1_BASEADDR



#define BRAM_LEFT_BASE    XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR
#define BRAM_RIGHT_BASE   XPAR_AXI_BRAM_CTRL_1_S_AXI_BASEADDR

#define FFT_LENGTH        1024
#define FFT_USEFUL_BINS   (FFT_LENGTH / 2)   /* 512 — drop the mirror half */

#define SAMPLE_RATE_HZ    48000
#define BIN_HZ            ((float)SAMPLE_RATE_HZ / FFT_LENGTH)


/* How often to print a snapshot of the spectrum. ~5 Hz feels readable
 * on a terminal — much faster and you can't read the rows. */
#define SNAPSHOT_DELAY_US 200000

#define BAR_WIDTH         50
#define DISPLAY_BINS      32     /* show only first 32 bins (~0 to 1.5 kHz) */

/* Band ranges (in bins). Tweak to taste. */
#define BASS_START        1      /* skip DC bin 0 */
#define BASS_END          5      /*   ~47 - 235 Hz  */
#define LOW_MID_START     6
#define LOW_MID_END       20     /*  ~280 - 940 Hz  */
#define MID_START         21
#define MID_END           85     /*  ~985 - 3990 Hz */
#define HIGH_START        86
#define HIGH_END          255    /*   ~4 - 12 kHz   */


/* ------------------------------------------------------------ */
/*  BRAM access                                                 */
/* ------------------------------------------------------------ */

static inline void ReadBin(uint32_t bram_base, uint32_t bin,
                            uint32_t *mag_out)
{
    uint32_t addr = bram_base + bin * 4;
    *mag_out = (uint32_t)Xil_In32(addr);
}


static inline uint32_t BinEnergy(uint32_t bram_base, uint32_t bin)
{
    uint32_t m;
    ReadBin(bram_base, bin, &m);
    return m;
}

/* ------------------------------------------------------------ */
/*  Output helpers                                              */
/* ------------------------------------------------------------ */

/*
 * Print the first DISPLAY_BINS bins as a horizontal bar chart for one
 * channel. Length of each bar is log2(energy) scaled down so the visual
 * dynamic range is manageable.
 */
static void PrintSpectrum(const char *label, uint32_t bram_base)
{
    xil_printf("%s:\r\n", label);

    for (uint32_t b = 0; b < DISPLAY_BINS; b++) {
        uint64_t e = BinEnergy(bram_base, b);

        /* Print bin index, approx frequency, and the bar */
        uint32_t freq_hz = (uint32_t)(b * BIN_HZ);
        xil_printf("  bin %3d (%5d Hz) %d\r\n", (int)b, (int)freq_hz, (int)e);
    }
}


// Set Global variables
XUartPs UartPs;
XUartPs_Config *Config;

// Device instances
static XIic sIic;
static XScuGic sIntc;

 // Interrupt vector table
 const ivt_t ivt[] = {
 	//IIC
 	{XPAR_FABRIC_AXI_IIC_0_IIC2INTC_IRPT_INTR, (Xil_ExceptionHandler)XIic_InterruptHandler, &sIic}
 };

 /*
  * 	Function to convert input string to 32-bit integer
  * 	Use to convert serial terminal characters to AXI data
  */
 s32 string_to_int32(const char *str) {
     int result = 0;
     s32 result_32b;
     while (*str) {
         if (*str >= '0' && *str <= '9') {
             result = result * 10 + (*str - '0');
         }
         str++;
     }
     result_32b = (s32)result;
     return result_32b;
 }


 /*
  * 	Initialize the UART
  */
 int configureUart()
 {

     // Initialize the UART
     Config = XUartPs_LookupConfig(UART_DEVICE_ID);
     if (Config == NULL) {
         return XST_FAILURE;
     }
     XUartPs_CfgInitialize(&UartPs, Config, Config->BaseAddress);
     XUartPs_SetBaudRate(&UartPs, 115200); // Set the baud rate as needed

     xil_printf("UART Configured for User Input\n\r");

     return 0;
 }


int main()
{
	int Status;

	//Initialize the interrupt controller
	Status = fnInitInterruptController(&sIntc);
	if(Status != XST_SUCCESS) {
		xil_printf("Error initializing interrupts");
		return XST_FAILURE;
	}


	// Initialize IIC controller
	Status = fnInitIic(&sIic);
	if(Status != XST_SUCCESS) {
		xil_printf("Error initializing I2C controller");
		return XST_FAILURE;
	}


	// Initialize Audio Codec I2S
	Status = fnInitAudio();
	if(Status != XST_SUCCESS) {
		xil_printf("Audio initializing ERROR");
		return XST_FAILURE;
	}

	{
		XTime  tStart, tEnd;

		XTime_GetTime(&tStart);
		do {
			XTime_GetTime(&tEnd);
		}
		while((tEnd-tStart)/(COUNTS_PER_SECOND/10) < 20);
	}
	//Initialize Audio I2S
	Status = fnInitAudio();
	if(Status != XST_SUCCESS) {
		xil_printf("Audio initializing ERROR");
		return XST_FAILURE;
	}

	fnSetLineInput();
	//fnSetHpOutput();	// NOTE: do not set HP output

	// Enable all interrupts in our interrupt vector table
	// Make sure all driver instances using interrupts are initialized first
	fnEnableInterrupts(&sIntc, &ivt[0], sizeof(ivt)/sizeof(ivt[0]));


    print("Audio codec initialized.\n\r");

	// Initialize the UART serial terminal
    configureUart();

    print("Successfully ran configuration sequence.");

    uint32_t frame = 0;

    while (1)
    {
    	/* Clear terminal and home cursor so the display updates in place.
		 * Remove these two lines if you want a scrolling log instead. */
		xil_printf("\x1B[H");
		xil_printf("\x1B[2J");

		xil_printf("Frame %d\r\n", (int)frame++);
		xil_printf("------------------------------------------------\r\n");

		/* Spectrum visualization for left channel (most representative
		 * if you have a mono source; otherwise the right channel is
		 * similar). To see both, uncomment the right channel call. */
		PrintSpectrum("Left channel spectrum", BRAM_LEFT_BASE);
		/* PrintSpectrum("Right channel spectrum", BRAM_RIGHT_BASE); */

		/* For a known-tone debug, uncomment this. With a 1 kHz tone
		 * playing, you should see large R or I (or both) at bin 21. */
		/* PrintRawBin("Left ", BRAM_LEFT_BASE, 21); */
		/* PrintRawBin("Right", BRAM_RIGHT_BASE, 21); */

		usleep(SNAPSHOT_DELAY_US);
    }

    xil_printf("End of test\n\n\r");

    return 0;

    return 0;
}
