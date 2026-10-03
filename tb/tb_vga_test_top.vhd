--------------------------------------------------------------------------------
-- tb_vga_test_top.vhd
--
-- Integration testbench for the board-test top module. Sub-modules already
-- have their own pixel-exact TBs, so this only proves the WIRING is
-- correct: VGA timing (hsync/frame period), both writers finishing, a
-- white border row, and the 8 colour bars' order/colours on row 100.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_vga_test_top is
end entity tb_vga_test_top;

architecture sim of tb_vga_test_top is

    constant CLK_PERIOD : time := 10 ns;

    constant H_TOTAL      : natural := 800;
    constant V_TOTAL      : natural := 525;
    constant SYNC_TO_ACT  : natural := 96 + 48;  -- from the hsync falling edge to the start of active video

    signal clk_i : std_logic := '0';
    signal rst_i : std_logic := '1';

    signal vga_r_o : std_logic_vector(3 downto 0);
    signal vga_g_o : std_logic_vector(3 downto 0);
    signal vga_b_o : std_logic_vector(3 downto 0);
    signal hsync_o : std_logic;
    signal vsync_o : std_logic;
    signal led_o   : std_logic_vector(15 downto 0);

    signal sim_done : boolean := false;

    -- Expected bar colours (palette index 1..8 in order)
    type rgb_array_t is array (0 to 7) of std_logic_vector(11 downto 0);
    constant BAR_RGB : rgb_array_t := (
        0 => x"FF0",  -- yellow
        1 => x"0FF",  -- cyan
        2 => x"0F0",  -- green
        3 => x"F0F",  -- magenta
        4 => x"F00",  -- red
        5 => x"00F",  -- blue
        6 => x"888",  -- gray
        7 => x"444"   -- dark gray
    );

begin

    dut : entity work.vga_test_top
        generic map (
            SIM_MODE => true,
            SIM_DIV  => 1     -- clk_pix = clk_sys (speeds up the simulation)
        )
        port map (
            clk_i      => clk_i,
            rst_i      => rst_i,
            ps2_clk_i  => '1',
            ps2_data_i => '1',
            vga_r_o    => vga_r_o,
            vga_g_o => vga_g_o,
            vga_b_o => vga_b_o,
            hsync_o => hsync_o,
            vsync_o => vsync_o,
            led_o   => led_o
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
        variable errors  : natural := 0;
        variable t1, t2  : time;
        variable rgb     : std_logic_vector(11 downto 0);
        variable next_x  : natural;
        variable cur_x   : natural;

        -- Advance to the start of the given active line, counting from the vsync falling edge
        procedure goto_line(line_no : in natural) is
        begin
            wait until falling_edge(vsync_o);
            for i in 1 to 35 + line_no loop
                wait until falling_edge(hsync_o);
            end loop;
        end procedure goto_line;
    begin
        rst_i <= '1';
        wait for 10 * CLK_PERIOD;
        wait until falling_edge(clk_i);
        rst_i <= '0';

        ------------------------------------------------------------------
        -- 1) The pattern writer and palette writer must both finish
        ------------------------------------------------------------------
        wait until led_o(1) = '1' for 100_000 * CLK_PERIOD;
        if led_o(1) /= '1' then
            errors := errors + 1;
            report "ERROR: pattern writer did not finish within 100,000 cycles (led_o(1))" severity error;
        end if;
        if led_o(2) /= '1' then
            errors := errors + 1;
            report "ERROR: palette writer did not finish (led_o(2))" severity error;
        end if;
        if led_o(0) /= '1' then
            errors := errors + 1;
            report "ERROR: clock did not lock (led_o(0))" severity error;
        end if;

        ------------------------------------------------------------------
        -- 2) hsync period = 800 pixel clocks
        ------------------------------------------------------------------
        wait until falling_edge(hsync_o);
        t1 := now;
        wait until falling_edge(hsync_o);
        t2 := now;
        if (t2 - t1) /= H_TOTAL * CLK_PERIOD then
            errors := errors + 1;
            report "ERROR: hsync period " & time'image(t2 - t1) & ", expected " &
                   time'image(H_TOTAL * CLK_PERIOD) severity error;
        end if;

        ------------------------------------------------------------------
        -- 3) The first active line (L=0) must be WHITE end to end (border)
        ------------------------------------------------------------------
        goto_line(0);
        cur_x := 0;
        for i in 1 to SYNC_TO_ACT loop
            wait until rising_edge(clk_i);
        end loop;
        wait for CLK_PERIOD / 4;

        for k in 0 to 3 loop
            next_x := k * 200;  -- pixels 0, 200, 400, 600
            while cur_x < next_x loop
                wait until rising_edge(clk_i);
                cur_x := cur_x + 1;
            end loop;
            wait for CLK_PERIOD / 4;
            rgb := vga_r_o & vga_g_o & vga_b_o;
            if rgb /= x"FFF" then
                errors := errors + 1;
                report "ERROR: border row, x=" & integer'image(cur_x) & " colour 0x" &
                       to_hstring(rgb) & ", expected 0xFFF (white)" severity error;
            end if;
        end loop;

        ------------------------------------------------------------------
        -- 4) Row 100: centres of the 8 colour bars (screen x = 80*b + 40)
        ------------------------------------------------------------------
        goto_line(100);
        for i in 1 to SYNC_TO_ACT loop
            wait until rising_edge(clk_i);
        end loop;
        cur_x := 0;
        wait for CLK_PERIOD / 4;

        for b in 0 to 7 loop
            next_x := 80 * b + 40;
            while cur_x < next_x loop
                wait until rising_edge(clk_i);
                cur_x := cur_x + 1;
            end loop;
            wait for CLK_PERIOD / 4;
            rgb := vga_r_o & vga_g_o & vga_b_o;
            if rgb /= BAR_RGB(b) then
                errors := errors + 1;
                report "ERROR: bar " & integer'image(b) & " (x=" & integer'image(cur_x) &
                       ") colour 0x" & to_hstring(rgb) & ", expected 0x" &
                       to_hstring(BAR_RGB(b)) severity error;
            end if;
        end loop;

        ------------------------------------------------------------------
        -- 5) Frame period = 800 x 525 pixel clocks
        ------------------------------------------------------------------
        wait until falling_edge(vsync_o);
        t1 := now;
        wait until falling_edge(vsync_o);
        t2 := now;
        if (t2 - t1) /= H_TOTAL * V_TOTAL * CLK_PERIOD then
            errors := errors + 1;
            report "ERROR: frame period " & time'image(t2 - t1) & ", expected " &
                   time'image(H_TOTAL * V_TOTAL * CLK_PERIOD) severity error;
        end if;

        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_vga_test_top: PASS - hsync/frame period, writer+palette completion, white border row and the 8 colour bars' order verified" severity note;
        else
            report "tb_vga_test_top: FAIL - " & integer'image(errors) & " error(s)" severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        stop;
    end process stimulus;

end architecture sim;
