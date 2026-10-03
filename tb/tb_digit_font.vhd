--------------------------------------------------------------------------------
-- tb_digit_font.vhd
--
-- Full-coverage testbench for digit_font.vhd: checks all 10 digits x 5
-- rows (50 combinations) against an independently transcribed bitmap
-- table, plus invalid digit_i (10, 15) and invalid row_i (5-7) -> "000".
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_digit_font is
end entity tb_digit_font;

architecture sim of tb_digit_font is

    signal digit_i  : unsigned(3 downto 0) := (others => '0');
    signal row_i    : unsigned(2 downto 0) := (others => '0');
    signal pixels_o : std_logic_vector(2 downto 0);

    type row_array_t  is array (0 to 4) of std_logic_vector(2 downto 0);
    type font_table_t is array (0 to 9) of row_array_t;

    -- Independent second transcription of the bitmap table (hand-written,
    -- not copied from the RTL's FONT_ROM)
    constant EXPECTED : font_table_t := (
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

    dut : entity work.digit_font
        port map (
            digit_i  => digit_i,
            row_i    => row_i,
            pixels_o => pixels_o
        );

    stimulus : process
        variable errors : natural := 0;
    begin
        ------------------------------------------------------------------
        -- 1) All 10 digits x 5 rows (50 combinations)
        ------------------------------------------------------------------
        for d in 0 to 9 loop
            for r in 0 to 4 loop
                digit_i <= to_unsigned(d, 4);
                row_i   <= to_unsigned(r, 3);
                wait for 1 ns;  -- extra delta-cycle needed to settle (wait for 0 ns is not enough)
                if pixels_o /= EXPECTED(d)(r) then
                    report "tb_digit_font: FAIL - digit=" & integer'image(d) &
                           " row=" & integer'image(r) &
                           " beklenen=" & to_string(EXPECTED(d)(r)) &
                           " gozlenen=" & to_string(pixels_o)
                        severity error;
                    errors := errors + 1;
                end if;
            end loop;
        end loop;

        ------------------------------------------------------------------
        -- 2) Invalid digit_i (10, 15) must yield "000" (blank)
        ------------------------------------------------------------------
        digit_i <= to_unsigned(10, 4);
        row_i   <= to_unsigned(0, 3);
        wait for 1 ns;
        if pixels_o /= "000" then
            report "tb_digit_font: FAIL - digit=10 row=0 beklenen=000 gozlenen=" & to_string(pixels_o)
                severity error;
            errors := errors + 1;
        end if;

        digit_i <= to_unsigned(15, 4);
        row_i   <= to_unsigned(4, 3);
        wait for 1 ns;
        if pixels_o /= "000" then
            report "tb_digit_font: FAIL - digit=15 row=4 beklenen=000 gozlenen=" & to_string(pixels_o)
                severity error;
            errors := errors + 1;
        end if;

        ------------------------------------------------------------------
        -- 3) Invalid row_i (5-7) must also yield "000" (pong_core can drive
        --    it out of range when this module is fed outside the scorebox)
        ------------------------------------------------------------------
        for r in 5 to 7 loop
            digit_i <= to_unsigned(3, 4);  -- valid digit, only row_i is under test
            row_i   <= to_unsigned(r, 3);
            wait for 1 ns;
            if pixels_o /= "000" then
                report "tb_digit_font: FAIL - digit=3 row=" & integer'image(r) &
                       " (gecersiz row) beklenen=000 gozlenen=" & to_string(pixels_o)
                    severity error;
                errors := errors + 1;
            end if;
        end loop;

        ------------------------------------------------------------------
        -- Summary
        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_digit_font: PASS - 10 rakam x 5 satir (50 kombinasyon) + gecersiz digit_i/row_i dogrulandi"
                severity note;
        else
            report "tb_digit_font: FAIL - " & integer'image(errors) & " hata bulundu" severity failure;
        end if;

        wait for 1 ns;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
