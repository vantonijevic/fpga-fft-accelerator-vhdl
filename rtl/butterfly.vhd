library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity  butterfly is
    generic(
        SIRINA_PODATAKA : POSITIVE := 16;
        SIRINA_TWIDDLE  : POSITIVE := 16
    );
    port(
        a_re : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        a_im : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        b_re : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        b_im : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        w_re : in SIGNED(SIRINA_TWIDDLE-1 downto 0);
        w_im : in SIGNED(SIRINA_TWIDDLE-1 downto 0);

        out_a_re : out SIGNED(SIRINA_PODATAKA-1 downto 0);
        out_a_im : out SIGNED(SIRINA_PODATAKA-1 downto 0);
        out_b_re : out SIGNED(SIRINA_PODATAKA-1 downto 0);
        out_b_im : out SIGNED(SIRINA_PODATAKA-1 downto 0);
        valid    : out STD_LOGIC;
        
        CLK  : in STD_LOGIC;
        RST  : in STD_LOGIC;
        EN   : in STD_LOGIC
    );
end entity butterfly;

architecture rtl of butterfly is
    
    subtype proizvod_t is signed (SIRINA_PODATAKA + SIRINA_TWIDDLE -1 downto 0); 

    --Kombinacioni proizvod koji se racuna konkurentno
    signal pr_wr_br_comb : proizvod_t;
    signal pr_wi_br_comb : proizvod_t;
    signal pr_wr_bi_comb : proizvod_t;
    signal pr_wi_bi_comb : proizvod_t;

    --pomocni registi nultog nivoa
    signal s0_a_re : signed(SIRINA_PODATAKA-1 downto 0);
    signal s0_a_im : signed(SIRINA_PODATAKA-1 downto 0);
    signal s0_b_re : signed(SIRINA_PODATAKA-1 downto 0);
    signal s0_b_im : signed(SIRINA_PODATAKA-1 downto 0);
    signal s0_w_re : signed(SIRINA_TWIDDLE-1 downto 0);
    signal s0_w_im : signed(SIRINA_TWIDDLE-1 downto 0);

    --rezultati mnozenja
    signal s1_wr_br : proizvod_t;
    signal s1_wi_br : proizvod_t;
    signal s1_wr_bi : proizvod_t;
    signal s1_wi_bi : proizvod_t;

    --Kasnjenje signala A kroz pipeline 
    signal s1_a_re : signed(SIRINA_PODATAKA-1 downto 0);
    signal s1_a_im : signed(SIRINA_PODATAKA-1 downto 0);
    signal s2_a_re : signed(SIRINA_PODATAKA-1 downto 0);
    signal s2_a_im : signed(SIRINA_PODATAKA-1 downto 0);

    --akumulacija
    signal s2_wb_re : signed(SIRINA_PODATAKA downto 0);
    signal s2_wb_im : signed(SIRINA_PODATAKA downto 0);

    --pipeline za valid signal
    signal valid_pipe : STD_LOGIC_VECTOR(3 downto 0);

begin
        
    pr_wr_br_comb <= resize(s0_w_re * s0_b_re, proizvod_t'length);
    pr_wi_br_comb <= resize(s0_w_im * s0_b_re, proizvod_t'length);
    pr_wr_bi_comb <= resize(s0_w_re * s0_b_im, proizvod_t'length);
    pr_wi_bi_comb <= resize(s0_w_im * s0_b_im, proizvod_t'length);

    process(CLK)

        constant PROD_HI : integer := SIRINA_PODATAKA + SIRINA_TWIDDLE - 2;
        constant PROD_LO : integer := SIRINA_PODATAKA - 1;


        variable sum_a_re : signed(SIRINA_PODATAKA downto 0);
        variable sum_a_im : signed(SIRINA_PODATAKA downto 0);
        variable sum_b_re : signed(SIRINA_PODATAKA downto 0);
        variable sum_b_im : signed(SIRINA_PODATAKA downto 0);

    begin
        if rising_edge(CLK) then
            if RST = '1' then

                s0_a_re    <= (others => '0');
                s0_a_im    <= (others => '0');
                s0_b_re    <= (others => '0');
                s0_b_im    <= (others => '0');
                s0_w_re    <= (others => '0');
                s0_w_im    <= (others => '0');

                s1_wr_br   <= (others => '0');
                s1_wi_br   <= (others => '0');
                s1_wr_bi   <= (others => '0');
                s1_wi_bi   <= (others => '0');
                s1_a_re    <= (others => '0');
                s1_a_im    <= (others => '0');

                s2_wb_re   <= (others => '0');
                s2_wb_im   <= (others => '0');
                s2_a_re    <= (others => '0');
                s2_a_im    <= (others => '0');

                out_a_re   <= (others => '0');
                out_a_im   <= (others => '0');
                out_b_re   <= (others => '0');
                out_b_im   <= (others => '0');

                valid_pipe <= (others => '0');

            else
    
                s1_wr_br <= pr_wr_br_comb;
                s1_wi_br <= pr_wi_br_comb;
                s1_wr_bi <= pr_wr_bi_comb;
                s1_wi_bi <= pr_wi_bi_comb;

                if EN = '1' then
                    s0_a_re <= a_re;
                    s0_a_im <= a_im;
                    s0_b_re <= b_re;
                    s0_b_im <= b_im;
                    s0_w_re <= w_re;
                    s0_w_im <= w_im;

                end if;
    
                s1_a_re <= s0_a_re;
                s1_a_im <= s0_a_im;

                -- accumulation (use generic PROD_HI/PROD_LO as you already have)
                s2_wb_re <= resize(s1_wr_br(PROD_HI downto PROD_LO), SIRINA_PODATAKA + 1) 
                          - resize(s1_wi_bi(PROD_HI downto PROD_LO), SIRINA_PODATAKA + 1);
                s2_wb_im <= resize(s1_wr_bi(PROD_HI downto PROD_LO), SIRINA_PODATAKA + 1)
                          + resize(s1_wi_br(PROD_HI downto PROD_LO), SIRINA_PODATAKA + 1);

                s2_a_re <= s1_a_re;
                s2_a_im <= s1_a_im;

                -- add/sub and output
                sum_a_re := resize(s2_a_re, SIRINA_PODATAKA + 1) + s2_wb_re;
                sum_a_im := resize(s2_a_im, SIRINA_PODATAKA + 1) + s2_wb_im;
                sum_b_re := resize(s2_a_re, SIRINA_PODATAKA + 1) - s2_wb_re;
                sum_b_im := resize(s2_a_im, SIRINA_PODATAKA + 1) - s2_wb_im;

                out_a_re <= sum_a_re(SIRINA_PODATAKA downto 1);
                out_a_im <= sum_a_im(SIRINA_PODATAKA downto 1);
                out_b_re <= sum_b_re(SIRINA_PODATAKA downto 1);
                out_b_im <= sum_b_im(SIRINA_PODATAKA downto 1);

                valid_pipe <= valid_pipe(2 downto 0) & EN;

            end if;
        end if;
    end process;        

    valid <= valid_pipe(3);

end architecture;