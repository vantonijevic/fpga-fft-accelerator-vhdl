library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fft_kontroler is
    generic(
        FFT_N           : POSITIVE := 1024;
        LOG2_N          : POSITIVE := 10;
        SIRINA_PODATAKA : POSITIVE := 16;
        PIPE_DUBINA     : POSITIVE := 5 --DUBINA PIPELINE-A (1 BRAM + 4 butterfly stepena)
    );

    port(
        CLK : in STD_LOGIC;
        RST : in STD_LOGIC;

        start  : in STD_LOGIC;
        obrada : out STD_LOGIC; -- '1' dok traje FFT
        kraj   : out STD_LOGIC;

        -- ULAZNI PODACI
        in_valid   : in STD_LOGIC;
        in_re      : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        in_im      : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        in_spreman : out STD_LOGIC;

        -- PING PONG BUFFER INTERFEJS
        pp_bank_toggle : out STD_LOGIC;
        pp_upis_en     : out STD_LOGIC;
        pp_upis_addr   : out UNSIGNED(LOG2_N-1 downto 0);
        pp_upis_re     : out SIGNED(SIRINA_PODATAKA-1 downto 0);
        pp_upis_im     : out SIGNED(SIRINA_PODATAKA-1 downto 0);

        -- PISANJE (butterfly izlaz -> SINK BRAM)
        pp_wr_en     : out STD_LOGIC;
        pp_wr_addr_a : out UNSIGNED(LOG2_N-1 downto 0);
        pp_wr_addr_b : out UNSIGNED(LOG2_N-1 downto 0);

        -- CITANJE (SOURCE BRAM -> butterfly ulaz)
        pp_rd_addr_a : out UNSIGNED(LOG2_N-1 downto 0);
        pp_rd_addr_b : out UNSIGNED(LOG2_N-1 downto 0);

        -- TWIDDLE ROM INTERFEJS
        tw_en : out STD_LOGIC;
        tw_addr : out UNSIGNED(LOG2_N-2 downto 0);

        -- BUTTERFLY INTERFEJS
        bf_en : out STD_LOGIC;

        -- STATUS
        spreman_rez     : out STD_LOGIC; -- REZULTATI DOSTUPNI ZA CITANJE
        trenutni_stepen : out UNSIGNED(3 downto 0) --TRENUTNI FFT STEPEN
    );
end entity fft_kontroler;


architecture rtl of fft_kontroler is
    type stanje_t is (S_CEKA, S_UPIS, S_RACUN, S_KRAJ);
    signal stanje : stanje_t := S_CEKA;
    
    signal upis_br   : UNSIGNED(LOG2_N-1 downto 0) := (others => '0');
    signal stepen_br : UNSIGNED(3 downto 0) := (others => '0');
    signal bf_br     : UNSIGNED(LOG2_N-1 downto 0) := (others => '0');
    signal pipe_br   : UNSIGNED(3 downto 0) := (others => '0');

    signal addr_a_s  : UNSIGNED(LOG2_N-1 downto 0);
    signal addr_b_s  : UNSIGNED(LOG2_N-1 downto 0);
    signal tw_addr_s : UNSIGNED(LOG2_N-2 downto 0);

    type addr_pipe_t is array(0 to PIPE_DUBINA-1) of UNSIGNED(LOG2_N-1 downto 0);
    signal wa_pipe : addr_pipe_t := (others => (others => '0'));
    signal wb_pipe : addr_pipe_t := (others => (others => '0'));
    signal we_pipe : STD_LOGIC_VECTOR(PIPE_DUBINA-1 downto 0) := (others => '0');

    signal bf_validan : STD_LOGIC; -- '1' u taktu kada su adrese (BRAM + ROM) validne
    signal bf_aktivan : STD_LOGIC := '0'; -- zakasnjen 1 takt = trenutak kada su podaci na izlazu BRAM/ROM

    function bit_reversal(x : UNSIGNED) return UNSIGNED is
        alias xa   : UNSIGNED(x'length-1 downto 0) is x;
        variable r : UNSIGNED(x'length-1 downto 0);
    begin
        for i in r'range loop
            r(i) := xa(x'length-1-i);
        end loop;
        return r;
    end function;

begin

    assert FFT_N = 2**LOG2_N
        report "FFT_N mora biti 2**LOG2_N" severity failure;
    assert LOG2_N >= 2 and LOG2_N <= 16
        report "LOG2_N mora biti u opsegu 2..16 (stepen_br je 4-bitni)" severity failure;
    assert PIPE_DUBINA <= 15
        report "PIPE_DUBINA mora biti <= 15 (pipe_br je 4-bitni)" severity failure;
 
    --------------------------------------------------------
    -- KOMBINACIONA LOGIKA: GENERISANJE ADRESA ZA BUTTERFLY
    --------------------------------------------------------
    addr_gen : process(bf_br, stepen_br)
        variable s      : integer range 0 to 15;
        variable aa, ab : UNSIGNED(LOG2_N-1 downto 0);
        variable tw     : UNSIGNED(LOG2_N-2 downto 0);
    begin
        s  := to_integer(stepen_br);
        if s> LOG2_N-1 then
            s := LOG2_N-1;
        end if;

        aa := (others => '0');
        ab := (others => '0');
        tw := (others => '0');

        for i in 0 to LOG2_N-1 loop
            if i < s then
                aa(i) := bf_br(i);
                ab(i) := bf_br(i);
            elsif i = s then
                aa(i) := '0';
                ab(i) := '1';
            end if;
        end loop;
        
        for i in 1 to LOG2_N-1 loop
            if i > s then
                aa(i) := bf_br(i-1);
                ab(i) := bf_br(i-1);
            end if;
        end loop;

        -- TWIDDLE ADRESA
        for i in 0 to LOG2_N-2 loop
            if i < s then
                tw(LOG2_N-1-s+i) := bf_br(i);
            end if;
        end loop;

        addr_a_s  <= aa;
        addr_b_s  <= ab;
        tw_addr_s <= tw;
    end process addr_gen; 
            
    ------------------------------
    -- SEKVENCIJALNA LOGIKA - FSM
    ------------------------------
    fsm : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST = '1'then

                stanje      <= S_CEKA;
                upis_br     <= (others => '0');
                stepen_br   <= (others => '0');
                bf_br       <= (others => '0');
                pipe_br     <= (others => '0');
                bf_aktivan  <= '0';
                we_pipe     <= (others => '0');
                wa_pipe     <= (others => (others => '0'));
                wb_pipe     <= (others => (others => '0'));

            else
                
                bf_aktivan <= bf_validan;
                we_pipe(0) <= bf_validan;
                wa_pipe(0) <= addr_a_s;
                wb_pipe(0) <= addr_b_s;
                for i in 1 to PIPE_DUBINA-1 loop
                    we_pipe(i) <= we_pipe(i-1);
                    wa_pipe(i) <= wa_pipe(i-1);
                    wb_pipe(i) <= wb_pipe(i-1);
                end loop;
                
                case stanje is
                    
                    when S_CEKA => 
                        upis_br   <= (others => '0');
                        stepen_br <= (others => '0');
                        bf_br     <= (others => '0');
                        pipe_br   <= (others => '0');

                        if start = '1' then
                            stanje <= S_UPIS;
                        end if;
                    
                    when S_UPIS => 
                        if in_valid = '1' then
                            upis_br <= upis_br + 1;
                            if upis_br = FFT_N-1 then
                                stanje  <= S_RACUN;
                            end if;
                        end if;
                    
                    when S_RACUN =>
                        if bf_br < FFT_N/2 then
                            bf_br      <= bf_br + 1;
                        
                        else
                            if pipe_br < PIPE_DUBINA-1 then
                                pipe_br <= pipe_br + 1;
                            
                            else
                                pipe_br <= (others => '0');
                                bf_br   <= (others => '0');

                                if stepen_br = LOG2_N-1 then
                                    stanje <= S_KRAJ;
                                
                                else
                                    stepen_br <= stepen_br + 1;
                                end if;
                            end if;
                        end if;
                    
                    when S_KRAJ =>
                        if start = '1' then
                            stanje    <= S_UPIS;
                            upis_br   <= (others => '0');
                            stepen_br <= (others => '0');
                            bf_br     <= (others => '0');
                            pipe_br   <= (others => '0');
                        end if;
                    
                    when others =>
                        stanje <= S_CEKA;

                end case;
            end if;
        end if; 
    end process fsm;

    -----------------------
    -- KOMBINACIONI IZLAZI
    -----------------------

    -- STATUSNI SIGNALI
    obrada          <= '1' when (stanje = S_UPIS or stanje = S_RACUN) else '0';
    kraj            <= '1' when stanje = S_KRAJ else '0';
    spreman_rez     <= '1' when stanje = S_KRAJ else '0';
    trenutni_stepen <= stepen_br;

    -- S_UPIS IZLAZI
    in_spreman <= '1' when stanje = S_UPIS else '0';
    pp_upis_en <= in_valid when stanje = S_UPIS else '0';
    pp_upis_re <= in_re;
    pp_upis_im <= in_im;

    -- BIT REVERSAL ADRESA ZA UCITAVANJE
    pp_upis_addr <= bit_reversal(upis_br) when stanje = S_UPIS else (others => '0');
    
    -- S_RACUN IZLAZI: CITANJE
    pp_rd_addr_a <= addr_a_s;
    pp_rd_addr_b <= addr_b_s;

    -- S_RACUN IZLAZI: TWIDDLE ROM
    tw_en   <= bf_validan;
    tw_addr <= tw_addr_s;

    -- S_RACUN IZLAZI: BUTTERFLY
    bf_en <= bf_aktivan;
    bf_validan <= '1' when (stanje = S_RACUN and bf_br < FFT_N/2) else '0';

    -- S_RACUN IZLAZI: PISANJE
    pp_wr_en     <= we_pipe(PIPE_DUBINA-1);
    pp_wr_addr_a <= wa_pipe(PIPE_DUBINA-1);
    pp_wr_addr_b <= wb_pipe(PIPE_DUBINA-1);

    -- BANK TOGGLE (NA KRAJU SVAKOG FFT STEPENA)
    pp_bank_toggle <= '1' when (stanje = S_RACUN and bf_br >= FFT_N/2 and pipe_br = PIPE_DUBINA-1 and stepen_br < LOG2_N-1) else '0';

end architecture;