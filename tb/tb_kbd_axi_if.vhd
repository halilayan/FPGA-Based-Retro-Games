--------------------------------------------------------------------------------
-- tb_kbd_axi_if.vhd
--
-- Testbench for kbd_axi_if. Sub-modules (ps2_rx, scancode_fifo) have their
-- own TBs, so this covers only kbd_axi_if's own addition: turning the
-- rd_strobe_i level into a single-cycle rd_en pulse.
--
-- Key test: holding rd_strobe_i HIGH for a long time must pop only one
-- byte, not repeatedly drain the FIFO.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

use work.ps2_bfm.all;

entity tb_kbd_axi_if is
end entity tb_kbd_axi_if;

architecture sim of tb_kbd_axi_if is

    constant CLK_HZ     : positive := 1_000_000;
    constant CLK_PERIOD : time     := 1 us;

    signal clk_i       : std_logic := '0';
    signal rst_i       : std_logic := '1';
    signal ps2_clk_i    : std_logic := '1';
    signal ps2_data_i   : std_logic := '1';
    signal rd_strobe_i  : std_logic := '0';
    signal data_o       : std_logic_vector(7 downto 0);
    signal empty_o      : std_logic;

    signal sim_done : boolean := false;

begin

    dut : entity work.kbd_axi_if
        generic map (CLK_HZ => CLK_HZ)
        port map (
            clk_i       => clk_i,
            rst_i       => rst_i,
            ps2_clk_i   => ps2_clk_i,
            ps2_data_i  => ps2_data_i,
            rd_strobe_i => rd_strobe_i,
            data_o      => data_o,
            empty_o     => empty_o
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

        procedure check(cond : in boolean; tag : in string) is
        begin
            if not cond then
                errors := errors + 1;
                report "ERROR: " & tag severity error;
            end if;
        end procedure check;

        -- Full CPU handshake: write 1, hold, return to 0.
        procedure sw_pop(hold_cycles : in natural) is
        begin
            rd_strobe_i <= '1';
            for i in 1 to hold_cycles loop
                wait until rising_edge(clk_i);
            end loop;
            rd_strobe_i <= '0';
            wait until rising_edge(clk_i);
        end procedure sw_pop;
    begin
        ps2_idle(ps2_clk_i, ps2_data_i);
        rst_i <= '1';
        wait for 10 * CLK_PERIOD;
        rst_i <= '0';
        wait for 5 * CLK_PERIOD;

        ------------------------------------------------------------------
        -- 1) FIFO must be empty after reset
        ------------------------------------------------------------------
        check(empty_o = '1', "empty_o=0 after reset (should be empty)");

        ------------------------------------------------------------------
        -- 2) Send two bytes, they should land in the FIFO
        ------------------------------------------------------------------
        ps2_send_frame(ps2_clk_i, ps2_data_i, x"1D");  -- 'W'
        wait for 5 * CLK_PERIOD;
        ps2_send_frame(ps2_clk_i, ps2_data_i, x"F0");  -- break prefix
        wait for 5 * CLK_PERIOD;
        check(empty_o = '0', "2 bytes were sent but empty_o=1");

        ------------------------------------------------------------------
        -- 3) Hold rd_strobe_i HIGH for 200 cycles - only 1 byte should pop
        ------------------------------------------------------------------
        check(data_o = x"1D", "first byte data_o=" & to_hstring(data_o) & ", expected 0x1D");
        sw_pop(200);
        check(data_o = x"F0", "second byte not visible after the long hold - " &
                               "the FIFO may have been popped more than once");
        check(empty_o = '0', "second byte should still be in the FIFO (empty_o=1)");

        ------------------------------------------------------------------
        -- 4) Pop the second byte with a normal (short) handshake too
        ------------------------------------------------------------------
        sw_pop(3);
        check(empty_o = '1', "both bytes were popped but empty_o=0 (should be empty)");

        ------------------------------------------------------------------
        -- 5) A strobe on an already-empty FIFO -> nothing should happen, stays empty
        ------------------------------------------------------------------
        sw_pop(3);
        check(empty_o = '1', "empty_o changed after a strobe on an empty FIFO");

        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_kbd_axi_if: PASS - edge-detected pop, single pop on a long-held strobe, and empty-FIFO behaviour verified" severity note;
        else
            report "tb_kbd_axi_if: FAIL - " & integer'image(errors) & " error(s)" severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        stop;
    end process stimulus;

end architecture sim;
