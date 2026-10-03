--------------------------------------------------------------------------------
-- digit_font.vhd
--
-- Minimal 3x5-pixel digit font (0-9 only), used for the Pong score display.
-- Purely combinational lookup: digit_i/row_i select pixels_o (3 bits, MSB
-- = leftmost pixel, '1' = lit). Out-of-range inputs (digit_i > 9 or
-- row_i > 4) output "000" instead of causing a simulation error.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity digit_font is
    port (
        digit_i  : in  unsigned(3 downto 0);        -- valid 0-9; 10-15 -> blank output
        row_i    : in  unsigned(2 downto 0);         -- 0-4 (5 rows, top to bottom)
        pixels_o : out std_logic_vector(2 downto 0)  -- 3 horizontal pixels, MSB = leftmost, '1' = lit
    );
end entity digit_font;

architecture rtl of digit_font is

    type row_array_t  is array (0 to 4) of std_logic_vector(2 downto 0);
    type font_table_t is array (0 to 9) of row_array_t;

    -- Digit -> 5-row bitmap.
    constant FONT_ROM : font_table_t := (
        0 => ("111", "101", "101", "101", "111"),
        1 => ("010", "110", "010", "010", "111"),
        2 => ("111", "001", "111", "100", "111"),
        3 => ("111", "001", "111", "001", "111"),
        4 => ("101", "101", "111", "001", "001"),
        5 => ("111", "100", "111", "001", "111"),
        6 => ("111", "100", "111", "101", "111"),
        7 => ("111", "001", "010", "010", "010"),
        8 => ("111", "101", "111", "101", "111"),
        9 => ("111", "101", "111", "001", "111")
    );

begin

    -- row_i must also be range-checked: it's a 3-bit port (0-7) but the ROM
    -- only defines rows 0-4. Without this check, row_i > 4 causes a
    -- simulation index-out-of-bounds error (occurs in practice, since the
    -- caller keeps computing row_i even when the digit isn't displayed).
    pixels_o <= FONT_ROM(to_integer(digit_i))(to_integer(row_i)) when (digit_i <= 9 and row_i <= 4) else
                "000";

end architecture rtl;
