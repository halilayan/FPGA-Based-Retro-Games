--------------------------------------------------------------------------------
-- tb_clk_pix_gen.vhd
--
-- Testbench for clk_pix_gen's SIM_MODE path (not the MMCM primitive itself).
-- Verifies: SIM_DIV=4 gives a 4x period at 50% duty cycle, SIM_DIV=1
-- passes clk_sys through directly, and locked_o asserts within bound.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_clk_pix_gen is
end entity tb_clk_pix_gen;

architecture sim of tb_clk_pix_gen is

    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

    signal clk_sys  : std_logic := '0';
    signal clk_pix4 : std_logic;
    signal locked4  : std_logic;
    signal clk_pix1 : std_logic;
    signal locked1  : std_logic;

    signal sim_done : boolean := false;

begin

    dut_div4 : entity work.clk_pix_gen
        generic map (SIM_MODE => true, SIM_DIV => 4)
        port map (
            clk_sys_i => clk_sys,
            clk_pix_o => clk_pix4,
            locked_o  => locked4
        );

    dut_div1 : entity work.clk_pix_gen
        generic map (SIM_MODE => true, SIM_DIV => 1)
        port map (
            clk_sys_i => clk_sys,
            clk_pix_o => clk_pix1,
            locked_o  => locked1
        );

    clk_gen : process
    begin
        while not sim_done loop
            clk_sys <= '0'; wait for CLK_PERIOD / 2;
            clk_sys <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_gen;

    stimulus : process
        variable errors    : natural := 0;
        variable t1, t2    : time;
        variable high_time : time;
    begin
        ------------------------------------------------------------------
        -- 1) locked_o must go high
        ------------------------------------------------------------------
        wait until locked4 = '1' for 100 * CLK_PERIOD;
        if locked4 /= '1' then
            errors := errors + 1;
            report "ERROR: locked_o did not go high within 100 cycles" severity error;
        end if;
        if locked1 /= '1' then
            errors := errors + 1;
            report "ERROR: locked_o did not go high for the SIM_DIV=1 instance" severity error;
        end if;

        ------------------------------------------------------------------
        -- 2) SIM_DIV=4 -> period = 4 x clk_sys
        ------------------------------------------------------------------
        wait until rising_edge(clk_pix4);
        t1 := now;
        wait until rising_edge(clk_pix4);
        t2 := now;
        if (t2 - t1) /= 4 * CLK_PERIOD then
            errors := errors + 1;
            report "ERROR: SIM_DIV=4 period " & time'image(t2 - t1) &
                   ", expected " & time'image(4 * CLK_PERIOD) severity error;
        end if;

        ------------------------------------------------------------------
        -- 3) SIM_DIV=4 -> 50% duty cycle (2 cycles high)
        ------------------------------------------------------------------
        wait until rising_edge(clk_pix4);
        t1 := now;
        wait until falling_edge(clk_pix4);
        high_time := now - t1;
        if high_time /= 2 * CLK_PERIOD then
            errors := errors + 1;
            report "ERROR: SIM_DIV=4 high time " & time'image(high_time) &
                   ", expected " & time'image(2 * CLK_PERIOD) severity error;
        end if;

        ------------------------------------------------------------------
        -- 4) SIM_DIV=1 -> clk_pix always equal to clk_sys
        ------------------------------------------------------------------
        for i in 0 to 9 loop
            wait until rising_edge(clk_sys);
            wait for CLK_PERIOD / 4;
            if clk_pix1 /= '1' then
                errors := errors + 1;
                report "ERROR: SIM_DIV=1, clk_pix not high while clk_sys is high" severity error;
            end if;
            wait until falling_edge(clk_sys);
            wait for CLK_PERIOD / 4;
            if clk_pix1 /= '0' then
                errors := errors + 1;
                report "ERROR: SIM_DIV=1, clk_pix not low while clk_sys is low" severity error;
            end if;
        end loop;

        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_clk_pix_gen: PASS - SIM_DIV=4 period/duty cycle, SIM_DIV=1 pass-through, and locked_o verified" severity note;
        else
            report "tb_clk_pix_gen: FAIL - " & integer'image(errors) & " error(s)" severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        stop;
    end process stimulus;

end architecture sim;
