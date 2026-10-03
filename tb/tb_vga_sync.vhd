--------------------------------------------------------------------------------
-- tb_vga_sync.vhd
--
-- Directed testbench for vga_sync: checks counter bounds, sync polarities/
-- windows, video_on edges, and line/frame_start pulses against an
-- independent reference model (derived from total elapsed clock edges, not
-- the DUT's own counter logic), over one full frame plus wraparound.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_vga_sync is
end entity tb_vga_sync;

architecture sim of tb_vga_sync is

    constant CLK_PERIOD : time := 40 ns;  -- ~25 MHz; exact value doesn't matter, only cycle count does

    constant H_VISIBLE : positive := 640;
    constant H_FRONT    : positive := 16;
    constant H_SYNC_W   : positive := 96;
    constant H_BACK     : positive := 48;
    constant V_VISIBLE  : positive := 480;
    constant V_FRONT    : positive := 10;
    constant V_SYNC_W   : positive := 2;
    constant V_BACK     : positive := 33;

    constant H_SYNC_BEG : natural := H_VISIBLE + H_FRONT;
    constant H_SYNC_END : natural := H_SYNC_BEG + H_SYNC_W;
    constant H_TOTAL    : natural := H_SYNC_END + H_BACK;   -- 800

    constant V_SYNC_BEG : natural := V_VISIBLE + V_FRONT;
    constant V_SYNC_END : natural := V_SYNC_BEG + V_SYNC_W;
    constant V_TOTAL    : natural := V_SYNC_END + V_BACK;   -- 525

    -- one full frame plus a few cycles of the next (checks wraparound)
    constant NUM_CYCLES : natural := H_TOTAL * V_TOTAL + 50;

    signal clk_pix_i : std_logic := '0';
    signal rst_i     : std_logic := '1';

    signal pix_x_o       : unsigned(9 downto 0);
    signal pix_y_o       : unsigned(9 downto 0);
    signal video_on_o    : std_logic;
    signal hsync_o       : std_logic;
    signal vsync_o       : std_logic;
    signal line_start_o  : std_logic;
    signal frame_start_o : std_logic;

    signal sim_done : boolean := false;

begin

    ----------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------
    dut : entity work.vga_sync
        generic map (
            H_VISIBLE => H_VISIBLE, H_FRONT => H_FRONT, H_SYNC => H_SYNC_W, H_BACK => H_BACK,
            V_VISIBLE => V_VISIBLE, V_FRONT => V_FRONT, V_SYNC => V_SYNC_W, V_BACK => V_BACK
        )
        port map (
            clk_pix_i     => clk_pix_i,
            rst_i         => rst_i,
            pix_x_o       => pix_x_o,
            pix_y_o       => pix_y_o,
            video_on_o    => video_on_o,
            hsync_o       => hsync_o,
            vsync_o       => vsync_o,
            line_start_o  => line_start_o,
            frame_start_o => frame_start_o
        );

    ----------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------
    clk_gen : process
    begin
        while not sim_done loop
            clk_pix_i <= '0';
            wait for CLK_PERIOD / 2;
            clk_pix_i <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_gen;

    ----------------------------------------------------------------------
    -- Reference model + comparison
    ----------------------------------------------------------------------
    stimulus : process
        variable cycle_count : natural := 0;
        variable exp_hcnt    : natural;
        variable exp_vcnt    : natural;
        variable exp_video_on, exp_hsync, exp_vsync : std_logic;
        variable exp_line_start, exp_frame_start    : std_logic;
        variable errors        : natural := 0;
        variable reported      : natural := 0;
        constant MAX_REPORTS   : natural := 20;
    begin
        rst_i <= '1';
        wait for CLK_PERIOD * 3;
        wait until rising_edge(clk_pix_i);
        rst_i <= '0';

        -- hcnt/vcnt must be 0 right after reset, before the first edge
        wait until falling_edge(clk_pix_i);
        if pix_x_o /= 0 or pix_y_o /= 0 then
            report "tb_vga_sync: FAIL - reset sonrasi pix_x_o/pix_y_o sifir degil" severity error;
            errors := errors + 1;
        end if;

        for i in 1 to NUM_CYCLES loop
            wait until rising_edge(clk_pix_i);
            cycle_count := cycle_count + 1;
            wait until falling_edge(clk_pix_i);

            exp_hcnt := cycle_count mod H_TOTAL;
            exp_vcnt := (cycle_count / H_TOTAL) mod V_TOTAL;

            if (exp_hcnt < H_VISIBLE) and (exp_vcnt < V_VISIBLE) then
                exp_video_on := '1';
            else
                exp_video_on := '0';
            end if;

            if (exp_hcnt >= H_SYNC_BEG) and (exp_hcnt < H_SYNC_END) then
                exp_hsync := '0';
            else
                exp_hsync := '1';
            end if;

            if (exp_vcnt >= V_SYNC_BEG) and (exp_vcnt < V_SYNC_END) then
                exp_vsync := '0';
            else
                exp_vsync := '1';
            end if;

            if exp_hcnt = 0 then
                exp_line_start := '1';
            else
                exp_line_start := '0';
            end if;

            if (exp_hcnt = 0) and (exp_vcnt = V_VISIBLE) then
                exp_frame_start := '1';
            else
                exp_frame_start := '0';
            end if;

            if to_integer(pix_x_o) /= exp_hcnt or to_integer(pix_y_o) /= exp_vcnt or
               video_on_o /= exp_video_on or hsync_o /= exp_hsync or vsync_o /= exp_vsync or
               line_start_o /= exp_line_start or frame_start_o /= exp_frame_start
            then
                errors := errors + 1;
                if reported < MAX_REPORTS then
                    report "tb_vga_sync: FAIL - cevrim " & integer'image(cycle_count) &
                           " beklenen (x=" & integer'image(exp_hcnt) &
                           ",y=" & integer'image(exp_vcnt) &
                           ",von=" & std_logic'image(exp_video_on) &
                           ",hs=" & std_logic'image(exp_hsync) &
                           ",vs=" & std_logic'image(exp_vsync) & ") gozlenen (x=" &
                           integer'image(to_integer(pix_x_o)) & ",y=" &
                           integer'image(to_integer(pix_y_o)) & ",von=" &
                           std_logic'image(video_on_o) & ",hs=" & std_logic'image(hsync_o) &
                           ",vs=" & std_logic'image(vsync_o) & ")"
                        severity error;
                    reported := reported + 1;
                end if;
            end if;
        end loop;

        if errors = 0 then
            report "tb_vga_sync: PASS - " & integer'image(NUM_CYCLES) &
                   " cevrim (1 tam kare + sarma) dogrulandi" severity note;
        else
            report "tb_vga_sync: FAIL - " & integer'image(errors) & " hata bulundu" severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
