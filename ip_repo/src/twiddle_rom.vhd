library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity twiddle_rom is

    generic(
        FFT_N           : positive := 1024;
        SIRINA_PODATAKA : positive := 16
    );

    port(
        CLK, EN    : in STD_LOGIC;
        ADDR       : in UNSIGNED(integer(log2(real(FFT_N/2)))-1 downto 0);
        w_re, w_im : out SIGNED(SIRINA_PODATAKA-1 downto 0);
        valid      : out STD_LOGIC
    );

end entity twiddle_rom;

architecture rtl of twiddle_rom is

    type rom_t is array(0 to FFT_N/2 - 1) of signed(SIRINA_PODATAKA-1 downto 0);
    
    constant SKALA : real := real(2**(SIRINA_PODATAKA-1) - 1);
    
    function init_re return rom_t is
        variable t : rom_t;
        variable a : real;
    begin
        for k in 0 to FFT_N/2 - 1 loop
            a    := 2.0 * MATH_PI * real(k) / real(FFT_N);
            t(k) := to_signed(integer(round(cos(a) * SKALA)), SIRINA_PODATAKA);
        end loop;
        return t;
    end function;
    
    function init_im return rom_t is
        variable t : rom_t;
        variable a : real;
    begin
        for k in 0 to FFT_N/2 - 1 loop
            a    := 2.0 * MATH_PI * real(k) / real(FFT_N);
            t(k) := to_signed(integer(round(-sin(a) * SKALA)), SIRINA_PODATAKA);
        end loop;
        return t;
    end function;

    signal rom_re : rom_t     := init_re;
    signal rom_im : rom_t     := init_im;
    signal en_reg : STD_LOGIC := '0';
    
    attribute rom_style           : string;
    attribute rom_style of rom_re : signal is "block";
    attribute rom_style of rom_im : signal is "block";

begin
    --Latency: 1 clock
    read_BRAM : process(CLK)
    begin
        if rising_edge(CLK) then
            if en = '1' then
                w_re <= rom_re(to_integer(addr));
                W_im <= rom_im(to_integer(addr));
            end if;
            en_reg <= en;
        end if;
    end process read_BRAM;

    valid <= en_reg;
end architecture;