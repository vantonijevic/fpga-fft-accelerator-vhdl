/* ===========================================================================
 * fft_dma_test.c
 * ===========================================================================
 * Upravljacki program za ARM Cortex-A9 (PS) koji preko AXI DMA kontrolera
 * salje blok uzoraka FFT akceleratoru u programabilnoj logici (PL) i
 * prima izracunati spektar.
 *
 * Okruzenje: Xilinx Vitis, standalone (bez operativnog sistema)
 *
 * Blok dizajn koji ovaj program pretpostavlja:
 *   ZYNQ7 PS  --AXI HP--> AXI DMA --AXIS--> fft_axis --AXIS--> AXI DMA --> PS
 *
 * Napomena o kesu:
 *   Zynq ima L1/L2 kes koji AXI DMA ne vidi. Zato se baferi moraju
 *   rucno isprazniti pre slanja (Flush) i ponistiti pre citanja (Invalidate),
 *   inace DMA prenosi zastarele podatke.
 *
 * Uz ovaj fajl ide i fft_soft.c, koji sadrzi tri softverske implementacije
 * za poredjenje performansi.
 * =========================================================================== */

#include <stdio.h>
#include <math.h>
#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xtime_l.h"

#define FFT_N       1024
#define SKALA       32767.0
#define DMA_DEV_ID  XPAR_AXIDMA_0_DEVICE_ID

/* Broj ponavljanja hardverskog merenja radi usrednjavanja */
#define BROJ_MERENJA 100

/* Baferi poravnati na 64 bajta zbog rada sa kesom */
static int32_t ulaz[FFT_N]  __attribute__((aligned(64)));
static int32_t izlaz[FFT_N] __attribute__((aligned(64)));

static XAxiDma dma;

/* Definisano u fft_soft.c */
extern void izmeri_softver(const int32_t *ulaz_pakovan, double hw_us);
extern double ispisi_statistiku(const char *naziv, const double *t, int n);

static double hw_t[BROJ_MERENJA];   /* vreme svakog pojedinacnog merenja [us] */

/* ---------------------------------------------------------------------------
 * Pakovanje kompleksnog broja u 32-bitnu rec
 *   [31:16] realni deo, [15:0] imaginarni deo, oba u formatu Q1.15
 * ------------------------------------------------------------------------- */
static inline int32_t spakuj(int16_t re, int16_t im)
{
    return ((int32_t)((uint16_t)re) << 16) | (uint16_t)im;
}

static inline int16_t uzmi_re(int32_t rec) { return (int16_t)(rec >> 16); }
static inline int16_t uzmi_im(int32_t rec) { return (int16_t)(rec & 0xFFFF); }

/* ---------------------------------------------------------------------------
 * Generisanje test signala: sinus na zadatom frekvencijskom uzorku
 * ------------------------------------------------------------------------- */
static void generisi_signal(int bin, double amplituda)
{
    for (int n = 0; n < FFT_N; n++) {
        double v = amplituda * sin(2.0 * M_PI * bin * n / FFT_N);
        int16_t q = (int16_t)lround(v * SKALA);
        ulaz[n] = spakuj(q, 0);
    }
}

/* ---------------------------------------------------------------------------
 * Inicijalizacija DMA kontrolera u rezimu bez skupljanja deskriptora
 * (Simple mode) -- dovoljan za prenos jednog bloka
 * ------------------------------------------------------------------------- */
static int dma_init(void)
{
    XAxiDma_Config *cfg = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (!cfg) {
        xil_printf("GRESKA: DMA konfiguracija nije pronadjena\r\n");
        return XST_FAILURE;
    }

    if (XAxiDma_CfgInitialize(&dma, cfg) != XST_SUCCESS) {
        xil_printf("GRESKA: inicijalizacija DMA nije uspela\r\n");
        return XST_FAILURE;
    }

    if (XAxiDma_HasSg(&dma)) {
        xil_printf("GRESKA: DMA je u Scatter-Gather rezimu, ocekivan Simple\r\n");
        return XST_FAILURE;
    }

    /* Prekidi se ne koriste -- cekanje je aktivno (polling) */
    XAxiDma_IntrDisable(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrDisable(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);

    return XST_SUCCESS;
}

/* ---------------------------------------------------------------------------
 * Jedan prolaz: slanje bloka u PL i prijem rezultata
 * ------------------------------------------------------------------------- */
static int uradi_fft(void)
{
    int status;

    /* Kes mora biti ispraznjen da bi DMA video sveze podatke */
    Xil_DCacheFlushRange((UINTPTR)ulaz, FFT_N * sizeof(int32_t));
    Xil_DCacheInvalidateRange((UINTPTR)izlaz, FFT_N * sizeof(int32_t));

    /* Prijemni kanal se otvara PRE predajnog, da rezultat ne bi bio izgubljen */
    status = XAxiDma_SimpleTransfer(&dma, (UINTPTR)izlaz,
                                    FFT_N * sizeof(int32_t),
                                    XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("GRESKA: prijemni prenos nije pokrenut\r\n");
        return XST_FAILURE;
    }

    status = XAxiDma_SimpleTransfer(&dma, (UINTPTR)ulaz,
                                    FFT_N * sizeof(int32_t),
                                    XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS) {
        xil_printf("GRESKA: predajni prenos nije pokrenut\r\n");
        return XST_FAILURE;
    }

    /* Aktivno cekanje na oba kanala */
    while (XAxiDma_Busy(&dma, XAXIDMA_DMA_TO_DEVICE))  { }
    while (XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA))  { }

    Xil_DCacheInvalidateRange((UINTPTR)izlaz, FFT_N * sizeof(int32_t));

    return XST_SUCCESS;
}

/* ===========================================================================
 * GLAVNI PROGRAM
 * =========================================================================== */
int main(void)
{
    XTime  t1, t2;
    int    max_bin = 0;
    double max_mag = 0.0;
    double hw_us;

    xil_printf("\r\n");
    xil_printf("=========================================================\r\n");
    xil_printf(" FFT AKCELERATOR -- test preko AXI DMA\r\n");
    xil_printf("=========================================================\r\n");
    xil_printf(" Duzina transformacije : %d\r\n", FFT_N);
    xil_printf(" Format podataka       : Q1.15 (16-bit signed)\r\n");
    xil_printf(" Test signal           : sinus @ uzorak 5, amplituda 0,5\r\n");
    xil_printf("=========================================================\r\n");

    if (dma_init() != XST_SUCCESS) return XST_FAILURE;

    generisi_signal(5, 0.5);

    /* ── Hardversko merenje ────────────────────────────────────────────────
     * Prvi prolaz se odbacuje jer u njemu kes jos nije "zagrejan".
     * Zatim se meri BROJ_MERENJA uzastopnih prolaza i uzima srednja
     * vrednost, cime se smanjuje uticaj pojedinacnih odstupanja.
     * -------------------------------------------------------------------- */
    if (uradi_fft() != XST_SUCCESS) return XST_FAILURE;   /* zagrevanje */

    /* Svako merenje se belezi posebno, kako bi se odredili minimum,
     * maksimum, srednja vrednost i standardna devijacija. */
    for (int i = 0; i < BROJ_MERENJA; i++) {
        XTime_GetTime(&t1);
        if (uradi_fft() != XST_SUCCESS) return XST_FAILURE;
        XTime_GetTime(&t2);
        hw_t[i] = (double)(t2 - t1) * 1000000.0 / COUNTS_PER_SECOND;
    }
    hw_us = ispisi_statistiku("Hardver (FPGA)", hw_t, BROJ_MERENJA);

    /* Pronalazenje pika u spektru */
    for (int k = 0; k < FFT_N; k++) {
        double re = uzmi_re(izlaz[k]);
        double im = uzmi_im(izlaz[k]);
        double m  = sqrt(re*re + im*im);
        if (m > max_mag) { max_mag = m; max_bin = k; }
    }

    xil_printf("\r\nHardver (FPGA):\r\n");
    xil_printf("  vreme (srednja vrednost od %d merenja) : %d us\r\n",
               BROJ_MERENJA, (int)hw_us);
    xil_printf("  pik spektra : uzorak %d, |X| = %d\r\n",
               max_bin, (int)max_mag);

    /* Provera ispravnosti */
    if (max_bin == 5 || max_bin == FFT_N - 5) {
        xil_printf("  provera     : ISPRAVNO (pik na ocekivanom uzorku)\r\n");
    } else {
        xil_printf("  provera     : GRESKA -- pik ocekivan na uzorku 5\r\n");
    }

    /* ── Prvih osam uzoraka spektra ──────────────────────────────────────── */
    xil_printf("\r\nPrvih 8 uzoraka spektra:\r\n");
    for (int k = 0; k < 8; k++) {
        xil_printf("  X[%2d] = %6d + j*%6d\r\n",
                   k, uzmi_re(izlaz[k]), uzmi_im(izlaz[k]));
    }

    /* ── Softverske implementacije ─────────────────────────────────────────
     * Funkcija izmeri_softver sama ispisuje rezultate sve tri varijante
     * i sumarnu tabelu poredjenja.
     * -------------------------------------------------------------------- */
    izmeri_softver(ulaz, hw_us);

    xil_printf("\r\n=== Kraj ===\r\n");
    return XST_SUCCESS;
}
