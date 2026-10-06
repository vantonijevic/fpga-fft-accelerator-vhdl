-- =============================================================================
-- fft_axis_tb.vhd
-- =============================================================================
-- Testbench za AXI4-Stream omotac FFT akceleratora
--
-- Sta se proverava:
--   TEST 1: Reset i pocetno stanje interfejsa
--   TEST 2: Realan ulaz (sinus) - provera rukovanja i prekida ulaznog toka
--   TEST 3: Zastoj primaoca usred slanja (M_AXIS TREADY se spusta)
--   TEST 4: Prijem rezultata, pozicija TLAST, pik na ocekivanom uzorku
--   TEST 5: DRUGI UZASTOPNI PAKET - isti ulaz mora dati isti izlaz
--   TEST 6: KOMPLEKSAN ULAZ - kompleksna eksponencijala, samo jedan pik
--   TEST 7: DETEKCIJA GRESKE - paket kraci od FFT_N
--
-- Pokretanje (GHDL):
--   ghdl -a fft_axis.vhd fft_axis_tb.vhd
--   ghdl -e fft_axis_tb
--   ghdl -r fft_axis_tb
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity fft_axis_tb is
end fft_axis_tb;

architecture sim of fft_axis_tb is

    constant FFT_N           : positive := 64;
    constant LOG2_N          : positive := 6;
    constant SIRINA_PODATAKA : positive := 16;
    constant PIPE_DUBINA     : positive := 5;
    constant CLK_PERIOD      : time     := 10 ns;
    constant SKALA           : real     := 32767.0;

    -- Frekvencijski uzorci test signala
    constant BIN_REALAN   : integer := 5;   -- za realan sinus
    constant BIN_KOMPLEKS : integer := 7;   -- za kompleksnu eksponencijalu

    signal aclk    : std_logic := '0';
    signal aresetn : std_logic := '0';

    signal s_tdata  : std_logic_vector(2*SIRINA_PODATAKA-1 downto 0) := (others => '0');
    signal s_tvalid : std_logic := '0';
    signal s_tready : std_logic;
    signal s_tlast  : std_logic := '0';

    signal m_tdata  : std_logic_vector(2*SIRINA_PODATAKA-1 downto 0);
    signal m_tvalid : std_logic;
    signal m_tready : std_logic := '1';
    signal m_tlast  : std_logic;

    signal stat_zauzeto : std_logic;
    signal stat_greska  : std_logic;

    signal sim_kraj : boolean := false;

    -- ── Prihvaceni rezultati ──────────────────────────────────────────────────
    type rez_t is array(0 to FFT_N-1) of integer;
    signal prim_re  : rez_t   := (others => 0);
    signal prim_im  : rez_t   := (others => 0);
    signal prim_br  : integer := 0;
    signal tlast_na : integer := -1;

    -- Kopija rezultata prvog paketa, za poredjenje u TESTU 5
    signal prvi_re : rez_t := (others => 0);
    signal prvi_im : rez_t := (others => 0);

    -- Brise brojac prijemnika izmedju paketa
    signal reset_prijema : boolean := false;

    -- ── Generatori test signala ───────────────────────────────────────────────
    -- Realan sinus: x[n] = 0,5 * sin(2*pi*bin*n/N)
    function sinus_re(n : integer) return integer is
    begin
        return integer(round(0.5 * sin(2.0*MATH_PI*real(BIN_REALAN)*real(n)/real(FFT_N)) * SKALA));
    end function;

    -- Kompleksna eksponencijala: x[n] = 0,4 * e^(j*2*pi*bin*n/N)
    -- Spektar takvog signala ima SAMO JEDAN pik (nema konjugovane slike),
    -- pa svaka zamena realnog i imaginarnog dela odmah razbija rezultat.
    function eksp_re(n : integer) return integer is
    begin
        return integer(round(0.4 * cos(2.0*MATH_PI*real(BIN_KOMPLEKS)*real(n)/real(FFT_N)) * SKALA));
    end function;

    function eksp_im(n : integer) return integer is
    begin
        return integer(round(0.4 * sin(2.0*MATH_PI*real(BIN_KOMPLEKS)*real(n)/real(FFT_N)) * SKALA));
    end function;

begin

    -- ── DUT ───────────────────────────────────────────────────────────────────
    DUT : entity work.fft_axis
        generic map (
            FFT_N           => FFT_N,
            LOG2_N          => LOG2_N,
            SIRINA_PODATAKA => SIRINA_PODATAKA,
            PIPE_DUBINA     => PIPE_DUBINA
        )
        port map (
            aclk           => aclk,
            aresetn        => aresetn,
            s_axis_tdata   => s_tdata,
            s_axis_tvalid  => s_tvalid,
            s_axis_tready  => s_tready,
            s_axis_tlast   => s_tlast,
            m_axis_tdata   => m_tdata,
            m_axis_tvalid  => m_tvalid,
            m_axis_tready  => m_tready,
            m_axis_tlast   => m_tlast,
            stat_zauzeto => stat_zauzeto,
            stat_greska  => stat_greska
        );

    aclk <= not aclk after CLK_PERIOD/2;

    -- ── Watchdog ──────────────────────────────────────────────────────────────
    cuvar : process
    begin
        wait for 2 ms;
        if not sim_kraj then
            report "WATCHDOG: simulacija nije zavrsena na vreme" severity failure;
        end if;
        wait;
    end process;

    -- ── Prijemnik sa M_AXIS ───────────────────────────────────────────────────
    -- Pasivan proces: hvata svaku rec kada su TVALID i TREADY oba '1'.
    -- Brojac se resetuje signalom reset_prijema izmedju paketa.
    prijemnik : process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' or reset_prijema then
                prim_br  <= 0;
                tlast_na <= -1;
            elsif m_tvalid = '1' and m_tready = '1' then
                if prim_br < FFT_N then
                    prim_re(prim_br) <= to_integer(signed(
                        m_tdata(2*SIRINA_PODATAKA-1 downto SIRINA_PODATAKA)));
                    prim_im(prim_br) <= to_integer(signed(
                        m_tdata(SIRINA_PODATAKA-1 downto 0)));
                end if;
                if m_tlast = '1' then
                    tlast_na <= prim_br;
                end if;
                prim_br <= prim_br + 1;
            end if;
        end if;
    end process prijemnik;

    -- ── Glavni test proces ────────────────────────────────────────────────────
    stimulus : process
        variable max_mag  : real;
        variable max_bin  : integer;
        variable mag      : real;
        variable drugi_max: real;
        variable drugi_bin: integer;
        variable razlika  : integer;
        variable max_razl : integer;

        -- Salje jednu rec uz postovanje rukovanja
        procedure posalji(re_v, im_v : in integer; zadnji : in boolean) is
        begin
            s_tdata  <= std_logic_vector(to_signed(re_v, SIRINA_PODATAKA)) &
                        std_logic_vector(to_signed(im_v, SIRINA_PODATAKA));
            s_tvalid <= '1';
            if zadnji then s_tlast <= '1'; else s_tlast <= '0'; end if;
            loop
                wait until rising_edge(aclk);
                exit when s_tready = '1';
            end loop;
        end procedure;

        -- Trazi uzorak sa najvecom magnitudom i njegovu vrednost
        procedure nadji_pik(signal re_a, im_a : in rez_t;
                            variable bin : out integer;
                            variable amp : out real) is
            variable m, mx : real := 0.0;
            variable b     : integer := 0;
        begin
            mx := 0.0;
            for k in 0 to FFT_N-1 loop
                m := sqrt(real(re_a(k))**2 + real(im_a(k))**2);
                if m > mx then mx := m; b := k; end if;
            end loop;
            bin := b;
            amp := mx;
        end procedure;

        -- Ceka da stigne ceo paket rezultata
        procedure cekaj_paket is
        begin
            wait until prim_br = FFT_N for 500 us;
            wait for CLK_PERIOD*2;
            assert prim_br = FFT_N
                report "Primljeno " & integer'image(prim_br) &
                       " reci umesto " & integer'image(FFT_N) severity failure;
        end procedure;

        -- Priprema prijemnik za sledeci paket
        procedure novi_paket is
        begin
            reset_prijema <= true;
            wait until rising_edge(aclk);
            wait until rising_edge(aclk);
            reset_prijema <= false;
            wait until rising_edge(aclk);
        end procedure;

    begin

        -- ══════════════════════════════════════════════════════════════════════
        report "=== TEST 1: Reset ===";
        aresetn <= '0';
        wait for CLK_PERIOD*5;
        aresetn <= '1';
        wait for CLK_PERIOD*2;

        assert s_tready = '0'    report "T1: TREADY treba 0 u mirovanju" severity error;
        assert m_tvalid = '0'    report "T1: TVALID treba 0 u mirovanju" severity error;
        assert stat_zauzeto = '0' report "T1: zauzeto treba 0"           severity error;
        assert stat_greska = '0'  report "T1: greska treba 0"            severity error;
        report "TEST 1: PASS";

        -- ══════════════════════════════════════════════════════════════════════
        report "=== TEST 2: Prvi paket, realan sinus @ uzorak " &
               integer'image(BIN_REALAN) & " ===";

        for n in 0 to FFT_N-1 loop
            posalji(sinus_re(n), 0, n = FFT_N-1);
            -- Prekid ulaznog toka usred paketa
            if n = 20 then
                s_tvalid <= '0';
                s_tlast  <= '0';
                wait for CLK_PERIOD*4;
                report "  ubacen prekid ulaznog toka posle uzorka 20";
            end if;
        end loop;
        s_tvalid <= '0';
        s_tlast  <= '0';

        assert stat_greska = '0'
            report "T2: neocekivana greska u ispravnom paketu" severity error;
        report "TEST 2: PASS";

        -- ══════════════════════════════════════════════════════════════════════
        report "=== TEST 3: Zastoj primaoca usred slanja ===";
        wait until m_tvalid = '1';
        wait for CLK_PERIOD*3;
        m_tready <= '0';
        wait for CLK_PERIOD*10;
        assert m_tvalid = '1'
            report "T3: TVALID se spustio dok TREADY nije dosao" severity error;
        m_tready <= '1';
        report "TEST 3: PASS - TVALID zadrzan 10 taktova";

        -- ══════════════════════════════════════════════════════════════════════
        report "=== TEST 4: Rezultat prvog paketa ===";
        cekaj_paket;

        assert tlast_na = FFT_N-1
            report "T4: TLAST na poziciji " & integer'image(tlast_na) &
                   " umesto " & integer'image(FFT_N-1) severity error;

        nadji_pik(prim_re, prim_im, max_bin, max_mag);
        report "  pik: uzorak " & integer'image(max_bin) &
               "  |X| = " & integer'image(integer(max_mag));

        assert max_bin = BIN_REALAN or max_bin = FFT_N-BIN_REALAN
            report "T4: pik na uzorku " & integer'image(max_bin) &
                   " umesto " & integer'image(BIN_REALAN) severity error;

        -- Cuvamo rezultat radi poredjenja u TESTU 5
        for k in 0 to FFT_N-1 loop
            prvi_re(k) <= prim_re(k);
            prvi_im(k) <= prim_im(k);
        end loop;
        wait for CLK_PERIOD;
        report "TEST 4: PASS";

        -- ══════════════════════════════════════════════════════════════════════
        report "=== TEST 5: Drugi uzastopni paket (isti ulaz) ===";
        -- Ovaj test otkriva zaostalo stanje: brojace koji se ne resetuju,
        -- pogresan polozaj memorijske banke, zaglavljen signal greske.

        wait for CLK_PERIOD*5;
        assert stat_zauzeto = '0'
            report "T5: omotac se nije vratio u mirovanje" severity error;

        novi_paket;

        for n in 0 to FFT_N-1 loop
            posalji(sinus_re(n), 0, n = FFT_N-1);
        end loop;
        s_tvalid <= '0';
        s_tlast  <= '0';

        cekaj_paket;

        -- Poredjenje sa prvim paketom: mora biti identicno do na bit
        max_razl := 0;
        for k in 0 to FFT_N-1 loop
            razlika := abs(prim_re(k) - prvi_re(k));
            if razlika > max_razl then max_razl := razlika; end if;
            razlika := abs(prim_im(k) - prvi_im(k));
            if razlika > max_razl then max_razl := razlika; end if;
        end loop;

        report "  najveca razlika izmedju paketa: " &
               integer'image(max_razl) & " LSB";
        assert max_razl = 0
            report "T5: drugi paket daje razlicit rezultat (razlika " &
                   integer'image(max_razl) & " LSB) - zaostalo stanje!"
            severity error;

        assert tlast_na = FFT_N-1
            report "T5: TLAST pogresno pozicioniran u drugom paketu" severity error;
        report "TEST 5: PASS - dva uzastopna paketa daju identican rezultat";

        -- ══════════════════════════════════════════════════════════════════════
        report "=== TEST 6: Kompleksan ulaz, eksponencijala @ uzorak " &
               integer'image(BIN_KOMPLEKS) & " ===";
        -- Za x[n] = A*e^(j*2*pi*bin*n/N) spektar ima SAMO JEDAN pik.
        -- Ako bi realni i imaginarni deo negde bili zamenjeni ili izgubljeni,
        -- pojavila bi se i konjugovana slika na uzorku N-bin.

        wait for CLK_PERIOD*5;
        novi_paket;

        for n in 0 to FFT_N-1 loop
            posalji(eksp_re(n), eksp_im(n), n = FFT_N-1);
        end loop;
        s_tvalid <= '0';
        s_tlast  <= '0';

        cekaj_paket;

        nadji_pik(prim_re, prim_im, max_bin, max_mag);
        report "  pik: uzorak " & integer'image(max_bin) &
               "  |X| = " & integer'image(integer(max_mag));

        assert max_bin = BIN_KOMPLEKS
            report "T6: pik na uzorku " & integer'image(max_bin) &
                   " umesto " & integer'image(BIN_KOMPLEKS) severity error;

        -- Trazimo drugi najveci uzorak - ne sme biti konjugovane slike
        drugi_max := 0.0;
        drugi_bin := 0;
        for k in 0 to FFT_N-1 loop
            if k /= max_bin then
                mag := sqrt(real(prim_re(k))**2 + real(prim_im(k))**2);
                if mag > drugi_max then
                    drugi_max := mag;
                    drugi_bin := k;
                end if;
            end if;
        end loop;

        report "  drugi po velicini: uzorak " & integer'image(drugi_bin) &
               "  |X| = " & integer'image(integer(drugi_max));

        -- Konjugovana slika bi bila uporediva sa pikom; sum je bar 20x manji
        assert drugi_max < max_mag / 20.0
            report "T6: postoji druga jaka komponenta na uzorku " &
                   integer'image(drugi_bin) &
                   " - realni i imaginarni deo se verovatno mesaju!"
            severity error;
        report "TEST 6: PASS - samo jedan pik, bez konjugovane slike";

        -- ══════════════════════════════════════════════════════════════════════
        report "=== TEST 7: Detekcija greske - paket kraci od " &
               integer'image(FFT_N) & " ===";
        -- Saljemo TLAST ranije nego sto treba; omotac to mora prijaviti.

        wait for CLK_PERIOD*5;
        novi_paket;

        for n in 0 to FFT_N-2 loop
            -- TLAST vec na pretposlednjem uzorku
            posalji(sinus_re(n), 0, n = FFT_N-2);
        end loop;
        s_tvalid <= '0';
        s_tlast  <= '0';
        wait for CLK_PERIOD*3;

        assert stat_greska = '1'
            report "T7: greska nije detektovana za kratak paket" severity error;
        if stat_greska = '1' then
            report "TEST 7: PASS - kratak paket prijavljen";
        end if;

        -- Jezgro sada ceka jos jedan uzorak; posaljemo ga da se oslobodi
        posalji(sinus_re(FFT_N-1), 0, true);
        s_tvalid <= '0';
        s_tlast  <= '0';

        -- ══════════════════════════════════════════════════════════════════════
        wait for CLK_PERIOD*20;
        sim_kraj <= true;
        wait for CLK_PERIOD;
        report "=== SVI TESTOVI ZAVRSENI ===" severity note;
        wait;

    end process stimulus;

end sim;