library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity data_bram_tdp is
    generic (
        FFT_N           : POSITIVE := 1024;
        SIRINA_PODATAKA : POSITIVE := 16
    );
    port (
        CLK : in STD_LOGIC;

        a_addr  : in UNSIGNED(integer(log2(real(FFT_N)))-1 downto 0);
        a_wr_en : in STD_LOGIC;
        a_wr_re : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        a_wr_im : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        a_rd_re : out SIGNED(SIRINA_PODATAKA-1 downto 0);
        a_rd_im : out SIGNED(SIRINA_PODATAKA-1 downto 0);

        b_addr  : in UNSIGNED(integer(log2(real(FFT_N)))-1 downto 0);
        b_wr_en : in STD_LOGIC;
        b_wr_re : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        b_wr_im : in SIGNED(SIRINA_PODATAKA-1 downto 0);
        b_rd_re : out SIGNED(SIRINA_PODATAKA-1 downto 0);
        b_rd_im : out SIGNED(SIRINA_PODATAKA-1 downto 0)
    );
end entity data_bram_tdp;

architecture rtl of data_bram_tdp is
    constant SIRINA_RECI : POSITIVE := SIRINA_PODATAKA * 2;

    type bram_t is array(0 to FFT_N-1) of STD_LOGIC_VECTOR(SIRINA_RECI-1 downto 0);
    shared variable mem : bram_t;

    attribute ram_style : string;
    attribute ram_style of mem : variable is "block";

    signal a_rec : STD_LOGIC_VECTOR(SIRINA_RECI-1 downto 0) := (others => '0');
    signal b_rec : STD_LOGIC_VECTOR(SIRINA_RECI-1 downto 0) := (others => '0');

begin

    port_a : process(CLK)
    begin
        if rising_edge(CLK) then
            a_rec <= mem(to_integer(a_addr));
            if a_wr_en = '1' then
                mem(to_integer(a_addr)) := STD_LOGIC_VECTOR(a_wr_re) & STD_LOGIC_VECTOR(a_wr_im);
            end if;
        end if;
    end process port_a;

    port_b : process(CLK)
    begin
        if rising_edge(CLK) then
            b_rec <= mem(to_integer(b_addr));
            if b_wr_en = '1' then
                mem(to_integer(b_addr)) := STD_LOGIC_VECTOR(b_wr_re) & STD_LOGIC_VECTOR(b_wr_im);
            end if;
        end if;
    end process port_b;

    a_rd_re <= SIGNED(a_rec(SIRINA_RECI-1 downto SIRINA_PODATAKA));
    a_rd_im <= SIGNED(a_rec(SIRINA_PODATAKA-1 downto 0));
    b_rd_re <= SIGNED(b_rec(SIRINA_RECI-1 downto SIRINA_PODATAKA));
    b_rd_im <= SIGNED(b_rec(SIRINA_PODATAKA-1 downto 0));

end architecture;