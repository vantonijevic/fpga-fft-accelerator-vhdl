/* ===========================================================================
 * fft_soft.c
 * ===========================================================================
 * Softverske implementacije FFT algoritma za ARM Cortex-A9, namenjene
 * poredjenju performansi sa hardverskim akceleratorom.
 *
 * Sadrzi tri varijante:
 *   1. dft_direktna()   -- O(N^2), referentna, namerno spora
 *   2. fft_float()      -- O(N log N) u pokretnom zarezu (double)
 *   3. fft_q15()        -- O(N log N) u fiksnom zarezu Q1.15,
 *                          identican algoritam kao u hardveru
 *
 * Trecom varijantom se dobija najpostenije poredjenje: isti algoritam,
 * isti brojni format, ista strategija skaliranja -- razlikuje se samo
 * platforma na kojoj se izvrsava.
 * =========================================================================== */

#include <math.h>
#include <string.h>
#include <stdint.h>
#include "xtime_l.h"
#include "xil_printf.h"

#define FFT_N   1024
#define LOG2_N  10
#define SKALA   32767.0

/* ---------------------------------------------------------------------------
 * Obrtanje redosleda bita -- ista permutacija koju hardver vrsi
 * tokom ucitavanja podataka
 * ------------------------------------------------------------------------- */
static inline unsigned obrni_bite(unsigned x, int bita)
{
    unsigned r = 0;
    for (int i = 0; i < bita; i++) {
        r = (r << 1) | (x & 1);
        x >>= 1;
    }
    return r;
}

/* ===========================================================================
 * 1. DIREKTNA DFT -- O(N^2)
 * ===========================================================================
 * Racuna se po definiciji, bez ikakve optimizacije. Sluzi kao gornja
 * granica slozenosti i kao provera tacnosti ostalih implementacija.
 * ------------------------------------------------------------------------- */
void dft_direktna(const double *ul_re, const double *ul_im,
                  double *iz_re, double *iz_im)
{
    for (int k = 0; k < FFT_N; k++) {
        double sre = 0.0, sim = 0.0;
        for (int n = 0; n < FFT_N; n++) {
            double ugao = -2.0 * M_PI * k * n / FFT_N;
            double c = cos(ugao), s = sin(ugao);
            sre += ul_re[n] * c - ul_im[n] * s;
            sim += ul_re[n] * s + ul_im[n] * c;
        }
        iz_re[k] = sre / FFT_N;
        iz_im[k] = sim / FFT_N;
    }
}

/* ===========================================================================
 * 2. FFT U POKRETNOM ZAREZU -- O(N log N)
 * ===========================================================================
 * Cooley-Tukey, decimacija u vremenu. Koeficijenti se racunaju unapred
 * i cuvaju u tabeli, kao sto hardver cuva twiddle ROM.
 * ------------------------------------------------------------------------- */
static double tw_re[FFT_N/2];
static double tw_im[FFT_N/2];
static int    tw_spremni = 0;

static void pripremi_tabelu(void)
{
    if (tw_spremni) return;
    for (int k = 0; k < FFT_N/2; k++) {
        double a = 2.0 * M_PI * k / FFT_N;
        tw_re[k] =  cos(a);
        tw_im[k] = -sin(a);
    }
    tw_spremni = 1;
}

void fft_float(double *re, double *im)
{
    pripremi_tabelu();

    /* Permutacija sa obrnutim redosledom bita */
    for (unsigned i = 0; i < FFT_N; i++) {
        unsigned j = obrni_bite(i, LOG2_N);
        if (j > i) {
            double t;
            t = re[i]; re[i] = re[j]; re[j] = t;
            t = im[i]; im[i] = im[j]; im[j] = t;
        }
    }

    /* log2(N) stupnjeva */
    for (int s = 0; s < LOG2_N; s++) {
        int raspon = 1 << s;          /* razmak izmedju parova     */
        int korak  = FFT_N >> (s+1);  /* korak kroz tabelu faktora */

        for (int grupa = 0; grupa < FFT_N; grupa += (raspon << 1)) {
            for (int j = 0; j < raspon; j++) {
                int a = grupa + j;
                int b = a + raspon;
                int k = j * korak;

                double wr = tw_re[k], wi = tw_im[k];
                double br = re[b],    bi = im[b];

                /* W * B */
                double pr = br*wr - bi*wi;
                double pi = br*wi + bi*wr;

                /* Deljenje sa 2 u svakom stupnju -- kao u hardveru */
                re[b] = (re[a] - pr) * 0.5;
                im[b] = (im[a] - pi) * 0.5;
                re[a] = (re[a] + pr) * 0.5;
                im[a] = (im[a] + pi) * 0.5;
            }
        }
    }
}

/* ===========================================================================
 * 3. FFT U FIKSNOM ZAREZU Q1.15 -- O(N log N)
 * ===========================================================================
 * Najpostenije poredjenje sa hardverom: isti algoritam, isti brojni
 * format, isto skaliranje po stupnju. Razlikuje se samo platforma.
 * ------------------------------------------------------------------------- */
static int16_t twq_re[FFT_N/2];
static int16_t twq_im[FFT_N/2];
static int     twq_spremni = 0;

static void pripremi_tabelu_q15(void)
{
    if (twq_spremni) return;
    for (int k = 0; k < FFT_N/2; k++) {
        double a = 2.0 * M_PI * k / FFT_N;
        twq_re[k] = (int16_t)lround( cos(a) * SKALA);
        twq_im[k] = (int16_t)lround(-sin(a) * SKALA);
    }
    twq_spremni = 1;
}

void fft_q15(int16_t *re, int16_t *im)
{
    pripremi_tabelu_q15();

    for (unsigned i = 0; i < FFT_N; i++) {
        unsigned j = obrni_bite(i, LOG2_N);
        if (j > i) {
            int16_t t;
            t = re[i]; re[i] = re[j]; re[j] = t;
            t = im[i]; im[i] = im[j]; im[j] = t;
        }
    }

    for (int s = 0; s < LOG2_N; s++) {
        int raspon = 1 << s;
        int korak  = FFT_N >> (s+1);

        for (int grupa = 0; grupa < FFT_N; grupa += (raspon << 1)) {
            for (int j = 0; j < raspon; j++) {
                int a = grupa + j;
                int b = a + raspon;
                int k = j * korak;

                int32_t wr = twq_re[k], wi = twq_im[k];
                int32_t br = re[b],     bi = im[b];

                /* Kompleksno mnozenje: rezultat Q2.30, vracen u Q1.15 */
                int32_t pr = (br*wr - bi*wi) >> 15;
                int32_t pi = (br*wi + bi*wr) >> 15;

                int32_t ar = re[a], ai = im[a];

                /* Deljenje sa 2 -- identicno hardverskom skaliranju */
                re[b] = (int16_t)((ar - pr) >> 1);
                im[b] = (int16_t)((ai - pi) >> 1);
                re[a] = (int16_t)((ar + pr) >> 1);
                im[a] = (int16_t)((ai + pi) >> 1);
            }
        }
    }
}

/* ===========================================================================
 * MERENJE
 * ===========================================================================
 * Globalni tajmer Cortex-A9 radi na polovini frekvencije procesora.
 * COUNTS_PER_SECOND je definisan u xtime_l.h i vec uzima to u obzir.
 * ------------------------------------------------------------------------- */
static double proteklo_us(XTime t1, XTime t2)
{
    return (double)(t2 - t1) * 1000000.0 / COUNTS_PER_SECOND;
}

/* Radni baferi */
static double  f_re[FFT_N], f_im[FFT_N];
static int16_t q_re[FFT_N], q_im[FFT_N];
static double  d_re[FFT_N], d_im[FFT_N];
static double  d_izre[FFT_N], d_izim[FFT_N];

/* ---------------------------------------------------------------------------
 * Merenje sve tri softverske varijante.
 * Ulaz: isti signal koji se salje hardveru (Q1.15 upakovan u 32 bita).
 * ------------------------------------------------------------------------- */

/* ---------------------------------------------------------------------------
 * Statistika niza merenja: minimum, maksimum, srednja vrednost i
 * standardna devijacija. Vraca srednju vrednost.
 * ------------------------------------------------------------------------- */
#define BROJ_SW   100     /* broj ponavljanja softverskih FFT merenja */
#define BROJ_DFT  5       /* direktna DFT traje ~0,6 s, pa manje ponavljanja */
static double sw_t[BROJ_SW];

double ispisi_statistiku(const char *naziv, const double *t, int n)
{
    double mn = t[0], mx = t[0], sr = 0.0, sd = 0.0;
    for (int i = 0; i < n; i++) {
        if (t[i] < mn) mn = t[i];
        if (t[i] > mx) mx = t[i];
        sr += t[i];
    }
    sr /= n;
    for (int i = 0; i < n; i++) sd += (t[i] - sr) * (t[i] - sr);
    sd = sqrt(sd / (n > 1 ? n - 1 : 1));
    /* xil_printf ne podrzava %f, pa se ispisuje u stotim delovima us */
    xil_printf("\r\n%s (%d merenja):\r\n", naziv, n);
    xil_printf("  min = %d.%02d us, max = %d.%02d us\r\n",
               (int)mn, (int)(mn*100)%100, (int)mx, (int)(mx*100)%100);
    xil_printf("  srednja = %d.%02d us, std = %d.%02d us\r\n",
               (int)sr, (int)(sr*100)%100, (int)sd, (int)(sd*100)%100);
    return sr;
}

static void raspakuj(const int32_t *ulaz_pakovan);

void izmeri_softver(const int32_t *ulaz_pakovan, double hw_us)
{
    XTime t1, t2;
    double t_dft, t_float, t_q15;
    int pik;
    double maks;

    /* Raspakivanje ulaza u sve tri reprezentacije */
    for (int n = 0; n < FFT_N; n++) {
        int16_t r = (int16_t)(ulaz_pakovan[n] >> 16);
        int16_t i = (int16_t)(ulaz_pakovan[n] & 0xFFFF);

        q_re[n] = r;        q_im[n] = i;
        f_re[n] = r/SKALA;  f_im[n] = i/SKALA;
        d_re[n] = r/SKALA;  d_im[n] = i/SKALA;
    }

    /* --- Varijanta 3: fiksni zarez Q1.15 --- */
    for (int r = 0; r < BROJ_SW; r++) {
        raspakuj(ulaz_pakovan);                 /* svez ulaz, van merenja */
        XTime_GetTime(&t1);
        fft_q15(q_re, q_im);
        XTime_GetTime(&t2);
        sw_t[r] = proteklo_us(t1, t2);
    }
    t_q15 = ispisi_statistiku("Softver, FFT Q1.15", sw_t, BROJ_SW);

    maks = 0.0; pik = 0;
    for (int k = 0; k < FFT_N; k++) {
        double m = sqrt((double)q_re[k]*q_re[k] + (double)q_im[k]*q_im[k]);
        if (m > maks) { maks = m; pik = k; }
    }
    xil_printf("\r\nSoftver -- FFT, fiksni zarez Q1.15:\r\n");
    xil_printf("  vreme       : %d us\r\n", (int)t_q15);
    xil_printf("  pik spektra : uzorak %d, |X| = %d\r\n", pik, (int)maks);

    /* --- Varijanta 2: pokretni zarez --- */
    for (int r = 0; r < BROJ_SW; r++) {
        raspakuj(ulaz_pakovan);
        XTime_GetTime(&t1);
        fft_float(f_re, f_im);
        XTime_GetTime(&t2);
        sw_t[r] = proteklo_us(t1, t2);
    }
    t_float = ispisi_statistiku("Softver, FFT pokretni zarez", sw_t, BROJ_SW);

    maks = 0.0; pik = 0;
    for (int k = 0; k < FFT_N; k++) {
        double m = sqrt(f_re[k]*f_re[k] + f_im[k]*f_im[k]);
        if (m > maks) { maks = m; pik = k; }
    }
    xil_printf("\r\nSoftver -- FFT, pokretni zarez:\r\n");
    xil_printf("  vreme       : %d us\r\n", (int)t_float);
    xil_printf("  pik spektra : uzorak %d, |X| = %d\r\n",
               pik, (int)(maks * SKALA));

    /* --- Varijanta 1: direktna DFT --- */
    for (int r = 0; r < BROJ_DFT; r++) {
        XTime_GetTime(&t1);
        dft_direktna(d_re, d_im, d_izre, d_izim);
        XTime_GetTime(&t2);
        sw_t[r] = proteklo_us(t1, t2);
    }
    t_dft = ispisi_statistiku("Softver, direktna DFT", sw_t, BROJ_DFT);

    xil_printf("\r\nSoftver -- direktna DFT:\r\n");
    xil_printf("  vreme       : %d us\r\n", (int)t_dft);

    /* --- Sumarni pregled --- */
    xil_printf("\r\n");
    xil_printf("=========================================================\r\n");
    xil_printf(" POREDJENJE PERFORMANSI  (N = %d)\r\n", FFT_N);
    xil_printf("=========================================================\r\n");
    xil_printf(" Implementacija            Vreme [us]   Ubrzanje\r\n");
    xil_printf("---------------------------------------------------------\r\n");
    xil_printf(" Hardver (FPGA)            %8d         1x\r\n", (int)hw_us);
    xil_printf(" Softver, FFT Q1.15        %8d    %6d x\r\n",
               (int)t_q15,   (int)(t_q15   / hw_us));
    xil_printf(" Softver, FFT float        %8d    %6d x\r\n",
               (int)t_float, (int)(t_float / hw_us));
    xil_printf(" Softver, direktna DFT     %8d    %6d x\r\n",
               (int)t_dft,   (int)(t_dft   / hw_us));
    xil_printf("=========================================================\r\n");
    xil_printf("\r\nNapomena: poredjenje sa FFT Q1.15 je metodoloski\r\n");
    xil_printf("najpostenije -- isti algoritam i isti brojni format,\r\n");
    xil_printf("razlikuje se samo platforma izvrsavanja.\r\n");
}

/* Raspakivanje ulaza u sve tri reprezentacije */
static void raspakuj(const int32_t *ulaz_pakovan)
{
    for (int n = 0; n < FFT_N; n++) {
        int16_t r = (int16_t)(ulaz_pakovan[n] >> 16);
        int16_t i = (int16_t)(ulaz_pakovan[n] & 0xFFFF);
        q_re[n] = r;        q_im[n] = i;
        f_re[n] = r/SKALA;  f_im[n] = i/SKALA;
        d_re[n] = r/SKALA;  d_im[n] = i/SKALA;
    }
}
