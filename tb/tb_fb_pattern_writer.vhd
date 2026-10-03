--------------------------------------------------------------------------------
-- tb_fb_pattern_writer.vhd
--
-- Golden-reference test for fb_pattern_writer: every write (address + data)
-- is checked against a value computed independently by the testbench.
-- Uses a small 64x48 frame so the same generic-scaled code paths run in
-- just 3,072 cycles.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_fb_pattern_writer is
end entity tb_fb_pattern_writer;

architecture sim of tb_fb_pattern_writer is

    constant CLK_PERIOD : time := 10 ns;

    constant FB_W : positive := 64;
    constant FB_H : positive := 48;

    -- Same geometry constants as the RTL (written independently here too)
    constant BAR_W   : positive := FB_W / 8;              -- 8
    constant STEP_W  : positive := FB_W / 16;             -- 4
    constant RAMP_Y0 : positive := (FB_H * 3) / 4;        -- 36
    constant BAND_H  : positive := (FB_H - RAMP_Y0) / 3;  -- 4

    constant PIXELS : natural := FB_W * FB_H;             -- 3072

    signal clk_i  : std_logic := '0';
    signal rst_i  : std_logic := '1';
    signal we_o   : std_logic;
    signal addr_o : unsigned(16 downto 0);
    signal din_o  : std_logic_vector(7 downto 0);
    signal done_o : std_logic;

    signal sim_done : boolean := false;

    -- Expected palette index - computed INDEPENDENTLY of the RTL (via division)
    function expected_idx(x : integer; y : integer) return integer is
        variable bar  : integer;
        variable step : integer;
    begin
        if (x = 0) or (x = FB_W - 1) or (y = 0) or (y = FB_H - 1) then
            return 0;  -- border
        end if;

        bar := x / BAR_W;
        if bar > 7 then
            bar := 7;
        end if;

        step := x / STEP_W;
        if step > 15 then
            step := 15;
        end if;

        if y < RAMP_Y0 then
            return 1 + bar;
        elsif y < RAMP_Y0 + BAND_H then
            return 16 + step;
        elsif y < RAMP_Y0 + 2 * BAND_H then
            return 32 + step;
        else
            return 48 + step;
        end if;
    end function expected_idx;

begin

    dut : entity work.fb_pattern_writer
        generic map (
            FB_W => FB_W,
            FB_H => FB_H
        )
        port map (
            clk_i  => clk_i,
            rst_i  => rst_i,
            we_o   => we_o,
            addr_o => addr_o,
            din_o  => din_o,
            done_o => done_o
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
        variable errors   : natural := 0;
        variable x, y     : integer;
        variable exp_idx  : integer;
        variable got_idx  : integer;
        variable got_addr : integer;
    begin
        -- Release reset on a falling edge: the next RISING edge is then the
        -- one where the first write happens, so address 0 shows up right away.
        rst_i <= '1';
        wait until falling_edge(clk_i);
        wait until falling_edge(clk_i);
        rst_i <= '0';
        wait for 1 ns;

        ------------------------------------------------------------------
        -- Scan the whole frame: one write per cycle, in order 0..PIXELS-1
        ------------------------------------------------------------------
        for a in 0 to PIXELS - 1 loop
            x := a mod FB_W;
            y := a / FB_W;

            if we_o /= '1' then
                errors := errors + 1;
                report "ERROR: we_o low for address " & integer'image(a) severity error;
                exit;
            end if;

            got_addr := to_integer(addr_o);
            if got_addr /= a then
                errors := errors + 1;
                report "ERROR: address order broken - expected " & integer'image(a) &
                       ", got " & integer'image(got_addr) severity error;
                exit;
            end if;

            exp_idx := expected_idx(x, y);
            got_idx := to_integer(unsigned(din_o));
            if got_idx /= exp_idx then
                errors := errors + 1;
                report "ERROR: index " & integer'image(got_idx) & " for (x=" & integer'image(x) &
                       ", y=" & integer'image(y) & "), expected " & integer'image(exp_idx) severity error;
                exit;
            end if;

            wait until falling_edge(clk_i);
        end loop;

        ------------------------------------------------------------------
        -- Sweep done: the writer must stop for good
        ------------------------------------------------------------------
        if errors = 0 then
            if we_o /= '0' then
                errors := errors + 1;
                report "ERROR: we_o still high after the frame finished" severity error;
            end if;
            if done_o /= '1' then
                errors := errors + 1;
                report "ERROR: done_o did not go high after the frame finished" severity error;
            end if;

            -- 100 more cycles: must not write again (stays stopped)
            for i in 1 to 100 loop
                wait until falling_edge(clk_i);
                if we_o /= '0' then
                    errors := errors + 1;
                    report "ERROR: wrote again after stopping" severity error;
                    exit;
                end if;
            end loop;
        end if;

        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_fb_pattern_writer: PASS - all " & integer'image(PIXELS) &
                   " pixels (border, 8 bars, 3 ramps) verified as address+data, then stayed stopped" severity note;
        else
            report "tb_fb_pattern_writer: FAIL - " & integer'image(errors) & " error(s)" severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        stop;
    end process stimulus;

end architecture sim;
