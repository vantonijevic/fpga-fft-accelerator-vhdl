library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fft_axis is
    generic(
        FFT_N           : POSITIVE := 1024;
        LOG2_N          : POSITIVE := 10;
        SIRINA_PODATAKA : POSITIVE := 16;
        PIPE_DUBINA     : POSITIVE := 5 
    );
    port(
        aclk    : in STD_LOGIC;
        aresetn : in STD_LOGIC;
        
        -- SLAVE
        s_axis_tdata      : in STD_LOGIC_VECTOR(2*SIRINA_PODATAKA-1 downto 0);
        s_axis_tvalid     : in STD_LOGIC;
        s_axis_tready     : out STD_LOGIC;
        s_axis_tlast      : in STD_LOGIC;
        
        -- MASTER
        m_axis_tdata      : out STD_LOGIC_VECTOR(2*SIRINA_PODATAKA-1 downto 0);
        m_axis_tvalid     : out STD_LOGIC;
        m_axis_tready     : in STD_LOGIC;
        m_axis_tlast      : out STD_LOGIC;
        
        -- STATUS
        stat_zauzeto : out STD_LOGIC; -- '1' dok traje obrada paketa
        stat_greska  : out STD_LOGIC  -- '1' ako TPOSLEDNJI stigne na pogresno mesto
    );
end fft_axis;

architecture rtl of fft_axis is
    type stanje_t is(
        S_MIR,    -- ceka prvi uzorak paketa
        S_POKRET, -- start impuls poslat, ceka se spremnost jezgra
        S_PRIJEM, -- prima FFT_N reci sa S_AXIS
        S_OBRADA, -- ceka kraj signal iz jezgra
        S_ADRESA, -- postavlja adresu rezultata
        S_SLANJE  --salje rec na M_AXIS
    );
    signal stanje : stanje_t := S_MIR;
    
    -- RESET U POLARITETU KOJI JEZGRO OCEKUJE
    signal rst : STD_LOGIC;
    
    -- INTERFEJS KA JEZGRU
    signal jz_start       : STD_LOGIC := '0';
    signal jz_obrada      : STD_LOGIC;
    signal jz_kraj        : STD_LOGIC;
    signal jz_in_valid    : STD_LOGIC := '0';
    signal jz_in_re       : SIGNED(SIRINA_PODATAKA-1 downto 0) := (others=>'0');
    signal jz_in_im       : SIGNED(SIRINA_PODATAKA-1 downto 0) := (others=>'0');
    signal jz_in_spreman  : STD_LOGIC;
    signal jz_rez_addr    : UNSIGNED(LOG2_N-1 downto 0) := (others=>'0');
    signal jz_rez_re      : SIGNED(SIRINA_PODATAKA-1 downto 0) := (others=>'0');
    signal jz_rez_im      : SIGNED(SIRINA_PODATAKA-1 downto 0) := (others=>'0');
    signal jz_rez_spreman : STD_LOGIC;
    
    -- BROJACI
    signal prijem_br : UNSIGNED(LOG2_N downto 0) := (others=>'0');
    signal slanje_br : UNSIGNED(LOG2_N downto 0) := (others=>'0');
    
    -- INTERNI HANDSHAKE SIGNALI
    signal tspreman_i : STD_LOGIC := '0';
    signal tvalid_i   : STD_LOGIC := '0';
    signal greska_i   : STD_LOGIC := '0';
    
begin
    rst <= not aresetn;
    
    U_FFT : entity work.fft_top
        generic map(
            FFT_N           => FFT_N,
            LOG2_N          => LOG2_N,
            SIRINA_PODATAKA => SIRINA_PODATAKA,
            PIPE_DUBINA     => PIPE_DUBINA
        )
        port map(
            CLK              => aCLK,
            RST              => rst,
            start            => jz_start,
            obrada           => jz_obrada,
            kraj             => jz_kraj,
            in_valid         => jz_in_valid,
            in_re            => jz_in_re,
            in_im            => jz_in_im,
            in_spreman       => jz_in_spreman,
            rezultat_addr    => jz_rez_addr,
            rezultat_re      => jz_rez_re,
            rezultat_im      => jz_rez_im,
            rezultat_spreman => jz_rez_spreman,
            dbg_stepen       => open,
            dbg_bank_sel     => open
        );
    
    automat : process(aCLK)
    begin
        if rising_edge(aCLK) then
            if rst = '1' then
                stanje      <= S_MIR;
                jz_start    <= '0';
                jz_in_valid <= '0';
                prijem_br   <= (others => '0');
                slanje_br   <= (others => '0');
                jz_rez_addr <= (others => '0');
                tspreman_i  <= '0';
                tvalid_i    <= '0';
                greska_i    <= '0';
                
            else
                jz_start    <= '0';
                jz_in_valid <= '0';
                
                case stanje is
                    when S_MIR =>
                        tspreman_i <= '0';
                        tvalid_i   <= '0';
                        prijem_br  <= (others => '0');
                        slanje_br  <= (others => '0');
                        greska_i   <= '0';
                        
                        if s_axis_tvalid = '1' then
                            jz_start <= '1'; -- implus od 1 takta
                            stanje   <= S_POKRET;
                        end if;
                        
                    when S_POKRET =>
                        if jz_in_spreman = '1' then
                            tspreman_i <= '1';
                            stanje     <= S_PRIJEM;
                        end if;
                    
                    
                    when S_PRIJEM =>
                        tspreman_i <= jz_in_spreman;
                        
                        if s_axis_tvalid = '1' and tspreman_i = '1' then
                            jz_in_re <= SIGNED(s_axis_tdata(2*SIRINA_PODATAKA-1 downto SIRINA_PODATAKA));
                            jz_in_im <= SIGNED(s_axis_tdata(SIRINA_PODATAKA-1 downto 0));
                            jz_in_valid <= '1';
                            prijem_br <= prijem_br + 1;
                            
                            if s_axis_tlast = '1' and prijem_br /= FFT_N - 1 then
                                greska_i <= '1'; -- PAKET JE KRACI OD FFT_N
                            end if;
                            
                            if s_axis_tlast = '0' and prijem_br = FFT_N - 1 then
                                greska_i <= '1'; -- PAKET JE DUZI OD FFT_N
                            end if;
                            
                            if prijem_br = FFT_N - 1 then
                                tspreman_i <= '0';
                                stanje     <= S_OBRADA;
                            end if;
                        end if;
                        
                    when S_OBRADA =>
                        tspreman_i <= '0';
                        
                        if jz_kraj = '1' then
                            jz_rez_addr <= (others => '0');
                            slanje_br   <= (others => '0');
                            stanje      <= S_ADRESA;
                        end if;
                    
                    when S_ADRESA =>
                        tvalid_i <= '1';
                        stanje   <= S_SLANJE;
                        
                    when S_SLANJE =>
                        if m_axis_tready = '1' then
                            if slanje_br = FFT_N-1 then
                                tvalid_i <= '0';
                                stanje   <= S_MIR;
                            else
                                slanje_br   <= slanje_br + 1;
                                jz_rez_addr <= jz_rez_addr + 1;
                                tvalid_i    <= '0';
                                stanje      <= S_ADRESA;
                            end if;
                        end if;
                    
                    when others =>
                        stanje <= S_MIR;
                end case;
            end if;
        end if;
    end process automat;
    
    s_axis_tready <= tspreman_i;
    
    m_axis_tvalid     <= tvalid_i;
    m_axis_tdata      <= STD_LOGIC_VECTOR(jz_rez_re) & STD_LOGIC_VECTOR(jz_rez_im);
    m_axis_tlast <= '1' when (tvalid_i = '1' and slanje_br = FFT_N-1) else '0';
    
    stat_zauzeto <= '0' when stanje = S_MIR else '1';
    stat_greska  <= greska_i;

end rtl;
