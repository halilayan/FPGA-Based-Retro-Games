--------------------------------------------------------------------------------
-- tb_kbd_test_top.vhd
--
-- Integration testbench for the board-test top module (LED behavior on top
-- of ps2_rx, whose protocol handling is verified separately by tb_ps2_rx).
-- CLK_HZ=1 MHz scales the watchdog/LED timers down for fast simulation.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

use work.ps2_bfm.all;

entity tb_kbd_test_top is
end entity tb_kbd_test_top;

architecture sim of tb_kbd_test_top is

    constant CLK_HZ       : positive := 1_000_000;
    constant CLK_PERIOD   : time     := 1 us;      -- must match CLK_HZ
    constant HEARTBEAT_HZ : positive := 1000;      -- toggles every 500 cycles
    constant STRETCH_MS   : positive := 1;         -- 1000-cycle activity light

    signal clk_i      : std_logic := '0';
    signal rst_i      : std_logic := '1';
    signal ps2_clk_i  : std_logic := '1';
    signal ps2_data_i : std_logic := '1';
    signal led_o      : std_logic_vector(15 downto 0);

    signal sim_done : boolean := false;

begin

    dut : entity work.kbd_test_top
        generic map (
            CLK_HZ       => CLK_HZ,
            HEARTBEAT_HZ => HEARTBEAT_HZ,
            STRETCH_MS   => STRETCH_MS
        )
        port map (
            clk_i      => clk_i,
            rst_i      => rst_i,
            ps2_clk_i  => ps2_clk_i,
            ps2_data_i => ps2_data_i,
            led_o      => led_o
        );

    clk_gen : process
    begin
        while not sim_done loop
            clk_i <= '0'; wait for CLK_PERIOD / 2;
            clk_i <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_gen;

    stimulus : process
        variable errors : natural := 0;
        variable hb_before : std_logic;

        procedure check_code(expected : in std_logic_vector(7 downto 0);
                             what     : in string) is
        begin
            if led_o(7 downto 0) /= expected then
                errors := errors + 1;
                report "ERROR: " & what & " - led_o(7..0) = 0x" &
                       to_hstring(led_o(7 downto 0)) & ", expected 0x" &
                       to_hstring(expected) severity error;
            end if;
        end procedure check_code;
    begin
        ps2_idle(ps2_clk_i, ps2_data_i);
        rst_i <= '1';
        wait for 10 * CLK_PERIOD;
        rst_i <= '0';
        wait for 10 * CLK_PERIOD;

        ------------------------------------------------------------------
        -- 1) Clean start after reset
        ------------------------------------------------------------------
        check_code(x"00", "after reset");
        if led_o(12) /= '0' or led_o(13) /= '0' then
            errors := errors + 1;
            report "ERROR: error flags not zero after reset" severity error;
        end if;

        ------------------------------------------------------------------
        -- 2) A valid scan code: the 'W' key's make code is 0x1D
        ------------------------------------------------------------------
        ps2_send_frame(ps2_clk_i, ps2_data_i, x"1D");
        wait for 20 * CLK_PERIOD;
        check_code(x"1D", "after sending 0x1D");
        if led_o(8) /= '1' then
            errors := errors + 1;
            report "ERROR: activity LED did not light up after a valid byte" severity error;
        end if;

        ------------------------------------------------------------------
        -- 3) Break prefix 0xF0
        ------------------------------------------------------------------
        ps2_send_frame(ps2_clk_i, ps2_data_i, x"F0");
        wait for 20 * CLK_PERIOD;
        check_code(x"F0", "after sending 0xF0");

        ------------------------------------------------------------------
        -- 4) Parity-error frame: sticky flag must light up, last code must NOT change
        ------------------------------------------------------------------
        ps2_send_frame(ps2_clk_i, ps2_data_i, x"55", bad_parity => true);
        wait for 20 * CLK_PERIOD;
        if led_o(12) /= '1' then
            errors := errors + 1;
            report "ERROR: parity-error sticky flag (led_o(12)) did not light up" severity error;
        end if;
        check_code(x"F0", "after a parity-error frame (last code must be preserved)");

        ------------------------------------------------------------------
        -- 5) Frame error (bad stop bit)
        ------------------------------------------------------------------
        ps2_send_frame(ps2_clk_i, ps2_data_i, x"66", bad_stop => true);
        wait for 20 * CLK_PERIOD;
        if led_o(13) /= '1' then
            errors := errors + 1;
            report "ERROR: frame-error sticky flag (led_o(13)) did not light up" severity error;
        end if;
        check_code(x"F0", "after a frame-error frame (last code must be preserved)");

        ------------------------------------------------------------------
        -- 6) The activity LED must turn itself off once traffic stops
        ------------------------------------------------------------------
        wait for 1200 * CLK_PERIOD;
        if led_o(8) /= '0' then
            errors := errors + 1;
            report "ERROR: activity LED did not turn off with no traffic" severity error;
        end if;

        ------------------------------------------------------------------
        -- 7) Does the heartbeat toggle (every 500 cycles)?
        ------------------------------------------------------------------
        hb_before := led_o(15);
        wait for 600 * CLK_PERIOD;
        if led_o(15) = hb_before then
            errors := errors + 1;
            report "ERROR: heartbeat (led_o(15)) did not change" severity error;
        end if;

        ------------------------------------------------------------------
        -- 8) Reset must clear the sticky flags and the last code
        ------------------------------------------------------------------
        rst_i <= '1';
        wait for 10 * CLK_PERIOD;
        rst_i <= '0';
        wait for 10 * CLK_PERIOD;
        check_code(x"00", "after reset (second time)");
        if led_o(12) /= '0' or led_o(13) /= '0' then
            errors := errors + 1;
            report "ERROR: reset did not clear the sticky error flags" severity error;
        end if;

        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_kbd_test_top: PASS - code holding, activity LED, parity/frame sticky flags, heartbeat and reset behaviour verified" severity note;
        else
            report "tb_kbd_test_top: FAIL - " & integer'image(errors) & " error(s)" severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        stop;
    end process stimulus;

end architecture sim;
