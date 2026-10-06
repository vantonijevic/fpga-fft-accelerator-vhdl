library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity fft_top is
    generic(
        FFT_N           : POSITIVE := 1024;
        LOG2_N          : POSITIVE := 10;
        SIRINA_PODATAKA : POSITIVE := 16;
        PIPE_DUBINA     : POSITIVE := 5
    );

    port(
        CLK : in STD_LOGIC;
        RST : in STD_LOGIC;

        start  : in STD_LOGIC;
        obrada : out STD_LOGIC;
        kraj   : out STD_LOGIC;

        in_valid   : in STD_LOGIC;
        in_re      : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        in_im      : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        in_spreman : out STD_LOGIC;

        rezultat_addr    : in UNSIGNED(LOG2_N-1 downto 0);
        rezultat_re      : out SIGNED(SIRINA_PODATAKA-1 downto 0);
        rezultat_im      : out SIGNED(SIRINA_PODATAKA-1 downto 0);
        rezultat_spreman : out STD_LOGIC;

        --ZA DEBUG
        dbg_stepen   : out UNSIGNED(3 downto 0);
        dbg_bank_sel : out STD_LOGIC
    );
end entity fft_top;

architecture rtl of fft_top is

    -- KONTROLNI SIGNALI
    signal ctrl_bank_toggle : STD_LOGIC;
    signal ctrl_upis_en     : STD_LOGIC;
    signal ctrl_upis_addr   : UNSIGNED(LOG2_N-1 downto 0);
    signal ctrl_upis_re     : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal ctrl_upis_im     : SIGNED(SIRINA_PODATAKA-1 downto 0);

    signal ctrl_wr_en     : STD_LOGIC;
    signal ctrl_wr_addr_a : UNSIGNED(LOG2_N-1 downto 0);
    signal ctrl_wr_addr_b : UNSIGNED(LOG2_N-1 downto 0);

    signal ctrl_rd_addr_a : UNSIGNED(LOG2_N-1 downto 0);
    signal ctrl_rd_addr_b : UNSIGNED(LOG2_N-1 downto 0);

    signal ctrl_tw_en   : STD_LOGIC;
    signal ctrl_tw_addr : UNSIGNED(LOG2_N-2 downto 0);
    signal ctrl_bf_en   : STD_LOGIC;

    signal ctrl_obrada           : STD_LOGIC;
    signal ctrl_kraj             : STD_LOGIC;
    signal ctrl_rezultat_spreman : STD_LOGIC;
    signal ctrl_stepen           : UNSIGNED(3 downto 0);

    -- TWIDDLE ROM IZLAZI
    signal tw_re    : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal tw_im    : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal tw_valid : STD_LOGIC;

    -- BUTTERFLY SIGNALI
    signal bf_in_a_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal bf_in_a_im : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal bf_in_b_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal bf_in_b_im : SIGNED(SIRINA_PODATAKA-1 downto 0);

    signal bf_out_a_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal bf_out_a_im : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal bf_out_b_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal bf_out_b_im : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal bf_valid    : STD_LOGIC;

    -- PING-PONG STANJE
    signal bank_sel : STD_LOGIC := '0';

    -- BRAM_0 SIGNALI
    signal b0_a_addr : UNSIGNED(LOG2_N-1 downto 0);
    signal b0_a_wr_en : STD_LOGIC;
    signal b0_a_wr_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b0_a_wr_im : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b0_a_rd_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b0_a_rd_im : SIGNED(SIRINA_PODATAKA-1 downto 0);

    signal b0_b_addr : UNSIGNED(LOG2_N-1 downto 0);
    signal b0_b_wr_en : STD_LOGIC;
    signal b0_b_wr_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b0_b_wr_im : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b0_b_rd_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b0_b_rd_im : SIGNED(SIRINA_PODATAKA-1 downto 0);

    -- BRAM_1 SIGNALI
    signal b1_a_addr : UNSIGNED(LOG2_N-1 downto 0);
    signal b1_a_wr_en : STD_LOGIC;
    signal b1_a_wr_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b1_a_wr_im : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b1_a_rd_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b1_a_rd_im : SIGNED(SIRINA_PODATAKA-1 downto 0);

    signal b1_b_addr : UNSIGNED(LOG2_N-1 downto 0);
    signal b1_b_wr_en : STD_LOGIC;
    signal b1_b_wr_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b1_b_wr_im : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b1_b_rd_re : SIGNED(SIRINA_PODATAKA-1 downto 0);
    signal b1_b_rd_im : SIGNED(SIRINA_PODATAKA-1 downto 0);
    
begin

    ----------------
    --FFT KONTROLER
    ----------------
    U_CTRL : entity work.fft_kontroler
        generic map(
            FFT_N           => FFT_N,
            LOG2_N          => LOG2_N,
            SIRINA_PODATAKA => SIRINA_PODATAKA,
            PIPE_DUBINA     => PIPE_DUBINA
        )
        port map(
            CLK             => CLK,
            RST             => RST,
            start           => start,  
            obrada          => ctrl_obrada,
            kraj            => ctrl_kraj,   
            in_valid        => in_valid,  
            in_re           => in_re,
            in_im           => in_im,      
            in_spreman      => in_spreman,
            pp_bank_toggle  => ctrl_bank_toggle,
            pp_upis_en      => ctrl_upis_en,    
            pp_upis_addr    => ctrl_upis_addr,  
            pp_upis_re      => ctrl_upis_re,    
            pp_upis_im      => ctrl_upis_im,    
            pp_wr_en        => ctrl_wr_en,    
            pp_wr_addr_a    => ctrl_wr_addr_a,
            pp_wr_addr_b    => ctrl_wr_addr_b,
            pp_rd_addr_a    => ctrl_rd_addr_a,
            pp_rd_addr_b    => ctrl_rd_addr_b,
            tw_en           => ctrl_tw_en,
            tw_addr         => ctrl_tw_addr,
            bf_en           => ctrl_bf_en,
            spreman_rez     => ctrl_rezultat_spreman,    
            trenutni_stepen => ctrl_stepen
        );

        ---------------
        -- TWIDDLE ROM
        ---------------
        U_TWIDDLE : entity work.twiddle_rom
            generic map(
                FFT_N           => FFT_N,
                SIRINA_PODATAKA => SIRINA_PODATAKA
            )
            port map(
                CLK   => CLK,
                EN    => ctrl_tw_en,
                ADDR  => ctrl_tw_addr,
                w_re  => tw_re,
                w_im  => tw_im,
                valid => tw_valid
            );
    
        -------------
        -- BUTTERFLY
        -------------
        -- ULAZI DOLAZE IZ SOURCE BRAM-a (SA 1 CIKLUSOM KASNJENA)
        -- TWIDDLE ISTO KASNI 1 CIKLUS
        -- BUTTERFLY ENABLE MORA KASNITI 1 CIKLUS ZA bf_en ZBOG BRAM KASNJENJA
        U_BUTTERFLY : entity work.butterfly
            generic map(
                SIRINA_PODATAKA => SIRINA_PODATAKA
            )
            port map(
                a_re     => bf_in_a_re,
                a_im     => bf_in_a_im,
                b_re     => bf_in_b_re,
                b_im     => bf_in_b_im,
                w_re     => tw_re,
                w_im     => tw_im,
                out_a_re => bf_out_a_re,
                out_a_im => bf_out_a_im,
                out_b_re => bf_out_b_re,
                out_b_im => bf_out_b_im,
                valid    => bf_valid,
                CLK      => CLK,
                RST      => RST,
                EN       => tw_valid   
            );
        
        ----------------
        --DATA BRAM-OVI
        ----------------
        U_BRAM0 : entity work.data_bram_tdp
            generic map(
                FFT_N           => FFT_N,
                SIRINA_PODATAKA => SIRINA_PODATAKA
            )
            port map(
                CLK     => CLK,
                a_addr  => b0_a_addr,
                a_wr_en => b0_a_wr_en,
                a_wr_re => b0_a_wr_re,
                a_wr_im => b0_a_wr_im,
                a_rd_re => b0_a_rd_re,
                a_rd_im => b0_a_rd_im,
                b_addr  => b0_b_addr,
                b_wr_en => b0_b_wr_en,
                b_wr_re => b0_b_wr_re,
                b_wr_im => b0_b_wr_im,
                b_rd_re => b0_b_rd_re,
                b_rd_im => b0_b_rd_im
            );

        U_BRAM1 : entity work.data_bram_tdp
            generic map(
                FFT_N           => FFT_N,
                SIRINA_PODATAKA => SIRINA_PODATAKA
            )
            port map(
                CLK     => CLK,
                a_addr  => b1_a_addr,
                a_wr_en => b1_a_wr_en,
                a_wr_re => b1_a_wr_re,
                a_wr_im => b1_a_wr_im,
                a_rd_re => b1_a_rd_re,
                a_rd_im => b1_a_rd_im,
                b_addr  => b1_b_addr,
                b_wr_en => b1_b_wr_en,
                b_wr_re => b1_b_wr_re,
                b_wr_im => b1_b_wr_im,
                b_rd_re => b1_b_rd_re,
                b_rd_im => b1_b_rd_im
            );
        
        ----------------------------
        -- PING-PONG KONTROLA BANKE
        ----------------------------
        bank_ctrl : process(CLK) 
        begin
            if rising_edge(CLK) then
                if RST = '1' then
                    bank_sel <= '0';
                elsif start = '1' then  
                    bank_sel <= '0';
                elsif ctrl_bank_toggle = '1' then
                    bank_sel <= not bank_sel;
                end if;
            end if;
        end process bank_ctrl;

        ---------------------------------
        -- MULTIPLEKSIRANJE BRAM PORTOVA
        ---------------------------------
        -- 1) UPIS (ctrl_upis_en=1) - ULAZNI PODACI -> BRAM_0 PORT A
        -- 2) RACUNANJE (bank_sel)  - SOURCE BRAM CITA, SINK BRAM PISE
        -- 3) REZULTAT (kraj)       - REZULTAT SE CITA IZ POSLEDNJE SINK BANKE
        bram_mux : process(bank_sel, ctrl_upis_en, ctrl_upis_addr, ctrl_upis_re, ctrl_upis_im,
                           ctrl_rd_addr_a, ctrl_rd_addr_b, ctrl_wr_en, ctrl_wr_addr_a, ctrl_wr_addr_b,
                           bf_out_a_re, bf_out_a_im, bf_out_b_re, bf_out_b_im, rezultat_addr, ctrl_rezultat_spreman,
                           b0_a_rd_re, b0_a_rd_im, b0_b_rd_re, b0_b_rd_im,
                           b1_a_rd_re, b1_a_rd_im, b1_b_rd_re, b1_b_rd_im)
        begin
            b0_a_addr   <= (others => '0');
            b0_a_wr_en  <= '0';
            b0_a_wr_re  <= (others => '0');
            b0_a_wr_im  <= (others => '0');
            b0_b_addr   <= (others => '0');
            b0_b_wr_en  <= '0';
            b0_b_wr_re  <= (others => '0');
            b0_b_wr_im  <= (others => '0');

            b1_a_addr   <= (others => '0');
            b1_a_wr_en  <= '0';
            b1_a_wr_re  <= (others => '0');
            b1_a_wr_im  <= (others => '0');
            b1_b_addr   <= (others => '0');
            b1_b_wr_en  <= '0';
            b1_b_wr_re  <= (others => '0');
            b1_b_wr_im  <= (others => '0');

            bf_in_a_re  <= (others => '0');
            bf_in_a_im  <= (others => '0');
            bf_in_b_re  <= (others => '0');
            bf_in_b_im  <= (others => '0');

            rezultat_re <= (others => '0');
            rezultat_im <= (others => '0');

            if ctrl_upis_en = '1' then
                -- UCITAVANJE ULAZNIH PODATAKA
                -- ULAZNI PODACI UVEK IDU U BRAM_0 PREKO PORTA A
                b0_a_addr  <= ctrl_upis_addr;
                b0_a_wr_en <= '1';
                b0_a_wr_re <= ctrl_upis_re;
                b0_a_wr_im <= ctrl_upis_im;

            elsif ctrl_rezultat_spreman = '1' then
                -- OCITAVANJE REZULTATA (REZULTAT JE U BANCI SUPROTNOJ OD bank_sel, ZADNJI UPIS JE ISAO U SINK BANKU)
                if bank_sel = '0' then
                    -- SOURCE = BRAM_0 - POSLEDNJI UPIS ISAO U BRAM_1
                    b1_a_addr   <= rezultat_addr;
                    rezultat_re <= b1_a_rd_re;
                    rezultat_im <= b1_a_rd_im;

                else
                    -- SOURCE = BRAM_1 - POSLEDNJI UPIS ISAO U BRAM_0
                    b0_a_addr   <= rezultat_addr;
                    rezultat_re <= b0_a_rd_re;
                    rezultat_im <= b0_a_rd_im;
                end if;
            else
                -- FFT RACUNANJE
                if bank_sel = '0' then
                    -- SOURCE = BRAM_0 (CITANJE)
                    b0_a_addr  <= ctrl_rd_addr_a;
                    b0_b_addr  <= ctrl_rd_addr_b;
                    bf_in_a_re <= b0_a_rd_re;
                    bf_in_a_im <= b0_a_rd_im;
                    bf_in_b_re <= b0_b_rd_re;
                    bf_in_b_im <= b0_b_rd_im;

                    -- SINK = BRAM_1 (PISANJE)
                    b1_a_addr  <= ctrl_wr_addr_a;
                    b1_a_wr_en <= ctrl_wr_en;
                    b1_a_wr_re <= bf_out_a_re;
                    b1_a_wr_im <= bf_out_a_im;

                    b1_b_addr  <= ctrl_wr_addr_b;
                    b1_b_wr_en <= ctrl_wr_en;
                    b1_b_wr_re <= bf_out_b_re;
                    b1_b_wr_im <= bf_out_b_im;

                else
                    -- SOURCE = BRAM_1 (CITANJE)
                    b1_a_addr  <= ctrl_rd_addr_a;
                    b1_b_addr  <= ctrl_rd_addr_b;
                    bf_in_a_re <= b1_a_rd_re;
                    bf_in_a_im <= b1_a_rd_im;
                    bf_in_b_re <= b1_b_rd_re;
                    bf_in_b_im <= b1_b_rd_im;

                    -- SINK = BRAM_0 (PISANJE)
                    b0_a_addr  <= ctrl_wr_addr_a;
                    b0_a_wr_en <= ctrl_wr_en;
                    b0_a_wr_re <= bf_out_a_re;
                    b0_a_wr_im <= bf_out_a_im;

                    b0_b_addr  <= ctrl_wr_addr_b;
                    b0_b_wr_en <= ctrl_wr_en;
                    b0_b_wr_re <= bf_out_b_re;
                    b0_b_wr_im <= bf_out_b_im;
                end if;
            end if;
        end process bram_mux; 

        -------------------
        -- IZLAZNI SIGNALI
        -------------------
        obrada           <= ctrl_obrada;
        kraj             <= ctrl_kraj;
        rezultat_spreman <= ctrl_rezultat_spreman;
        dbg_stepen       <= ctrl_stepen;
        dbg_bank_sel     <= bank_sel;

end architecture;