-- =============================================================================
-- twiddle_pkg.vhd
-- =============================================================================
-- Auto-generisano Python skriptom generate_twiddle.py
-- FFT velicina: 64
-- Format: Q1.15 (16-bit signed two's complement)
-- Twiddle faktor: W_N^k = cos(2*pi*k/N) - j*sin(2*pi*k/N)
-- Broj faktora: 32 (= N/2)
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package twiddle_pkg is

    -- Tip za niz twiddle faktora
    type twiddle_array_t is array(0 to 31) of signed(15 downto 0);

    -- Konstanta: realni deo twiddle faktora (cos)
    -- W_re[k] = round(cos(2*pi*k/64) * 32767)
    constant TWIDDLE_RE : twiddle_array_t := (
        to_signed(32767, 16) ,
        to_signed(32609, 16) ,
        to_signed(32137, 16) ,
        to_signed(31356, 16) ,
        to_signed(30273, 16) ,
        to_signed(28898, 16) ,
        to_signed(27245, 16) ,
        to_signed(25329, 16) ,
        to_signed(23170, 16) ,
        to_signed(20787, 16) ,
        to_signed(18204, 16) ,
        to_signed(15446, 16) ,
        to_signed(12539, 16) ,
        to_signed(9512, 16)  ,
        to_signed(6393, 16)  ,
        to_signed(3212, 16)  ,
        to_signed(0, 16),   
        to_signed(-3212, 16) ,
        to_signed(-6393, 16) ,
        to_signed(-9512, 16) ,
        to_signed(-12539, 16),
        to_signed(-15446, 16),
        to_signed(-18204, 16),
        to_signed(-20787, 16),
        to_signed(-23170, 16),
        to_signed(-25329, 16),
        to_signed(-27245, 16),
        to_signed(-28898, 16),
        to_signed(-30273, 16),
        to_signed(-31356, 16),
        to_signed(-32137, 16),
        to_signed(-32609, 16)
    );

    -- Konstanta: imaginarni deo twiddle faktora (-sin)
    -- W_im[k] = round(-sin(2*pi*k/64) * 32767)
    constant TWIDDLE_IM : twiddle_array_t := (
        to_signed(0, 16) ,
        to_signed(-3212, 16) ,
        to_signed(-6393, 16) ,
        to_signed(-9512, 16) ,
        to_signed(-12539, 16),
        to_signed(-15446, 16),
        to_signed(-18204, 16),
        to_signed(-20787, 16),
        to_signed(-23170, 16),
        to_signed(-25329, 16),
        to_signed(-27245, 16),
        to_signed(-28898, 16),
        to_signed(-30273, 16),
        to_signed(-31356, 16),
        to_signed(-32137, 16),
        to_signed(-32609, 16),
        to_signed(-32767, 16),
        to_signed(-32609, 16),
        to_signed(-32137, 16),
        to_signed(-31356, 16),
        to_signed(-30273, 16),
        to_signed(-28898, 16),
        to_signed(-27245, 16),
        to_signed(-25329, 16),
        to_signed(-23170, 16),
        to_signed(-20787, 16),
        to_signed(-18204, 16),
        to_signed(-15446, 16),
        to_signed(-12539, 16),
        to_signed(-9512, 16) ,
        to_signed(-6393, 16) ,
        to_signed(-3212, 16) 
    );

end package twiddle_pkg;
