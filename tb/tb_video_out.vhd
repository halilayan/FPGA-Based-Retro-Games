--------------------------------------------------------------------------------
-- tb_video_out.vhd
--
-- Golden-reference testbench for video_out: compares the full video chain
-- (vga_sync + fb_reader + mock BRAM + palette_lut + pipeline alignment)
-- pixel-exact against an independent reference model over one full frame,
-- accounting for the DUT's fixed PIPE_LAT+1 cycle latency.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_video_out is
end entity tb_video_out;

architecture sim of tb_video_out is

    constant CLK_PERIOD : time := 40 ns;

    constant H_VISIBLE : positive := 640;
    constant H_FRONT    : positive := 16;
    constant H_SYNC_W   : positive := 96;
    constant H_BACK     : positive := 48;
    constant V_VISIBLE  : positive := 480;
    constant V_FRONT    : positive := 10;
    constant V_SYNC_W   : positive := 2;
    constant V_BACK     : positive := 33;

    constant FB_W     : positive := 320;
    constant FB_H     : positive := 240;
    constant PIPE_LAT : positive := 2;

    constant TOTAL_LATENCY : natural := PIPE_LAT + 1;

    constant H_SYNC_BEG : natural := H_VISIBLE + H_FRONT;
    constant H_SYNC_END : natural := H_SYNC_BEG + H_SYNC_W;
    constant H_TOTAL    : natural := H_SYNC_END + H_BACK;   -- 800

    constant V_SYNC_BEG : natural := V_VISIBLE + V_FRONT;
    constant V_SYNC_END : natural := V_SYNC_BEG + V_SYNC_W;
    constant V_TOTAL    : natural := V_SYNC_END + V_BACK;   -- 525

    constant NUM_CYCLES : natural := H_TOTAL * V_TOTAL + 50;

    signal clk_pix_i : std_logic := '0';
    signal rst_i     : std_logic := '1';

    signal fb_addr_o : unsigned(16 downto 0);
    signal fb_dout_i : std_logic_vector(7 downto 0) := (others => '0');

    signal wr_en_i  : std_logic := '0';
    signal wr_idx_i : unsigned(7 downto 0) := (others => '0');
    signal wr_rgb_i : std_logic_vector(11 downto 0) := (others => '0');

    signal vga_r_o, vga_g_o, vga_b_o : std_logic_vector(3 downto 0);
    signal hsync_o, vsync_o          : std_logic;
    signal vblank_o                  : std_logic;
    signal frame_cnt_o               : unsigned(31 downto 0);

    signal sim_done : boolean := false;

begin

    ----------------------------------------------------------------------
    -- DUT (clk_wr_i tied to clk_pix_i; palette write CDC is verified
    -- separately in tb_palette_lut)
    ----------------------------------------------------------------------
    dut : entity work.video_out
        generic map (
            H_VISIBLE => H_VISIBLE, H_FRONT => H_FRONT, H_SYNC => H_SYNC_W, H_BACK => H_BACK,
            V_VISIBLE => V_VISIBLE, V_FRONT => V_FRONT, V_SYNC => V_SYNC_W, V_BACK => V_BACK,
            FB_W => FB_W, FB_H => FB_H, PIPE_LAT => PIPE_LAT
        )
        port map (
            clk_pix_i   => clk_pix_i,
            rst_i       => rst_i,
            fb_addr_o   => fb_addr_o,
            fb_dout_i   => fb_dout_i,
            clk_wr_i    => clk_pix_i,
            wr_en_i     => wr_en_i,
            wr_idx_i    => wr_idx_i,
            wr_rgb_i    => wr_rgb_i,
            vga_r_o     => vga_r_o,
            vga_g_o     => vga_g_o,
            vga_b_o     => vga_b_o,
            hsync_o     => hsync_o,
            vsync_o     => vsync_o,
            vblank_o    => vblank_o,
            frame_cnt_o => frame_cnt_o
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
    -- Mock BRAM: synchronous read, 1-cycle latency; index = low 8 bits of
    -- the address (deterministic synthetic image, no real art yet)
    ----------------------------------------------------------------------
    mock_bram : process (clk_pix_i)
    begin
        if rising_edge(clk_pix_i) then
            fb_dout_i <= std_logic_vector(fb_addr_o(7 downto 0));
        end if;
    end process mock_bram;

    ----------------------------------------------------------------------
    -- Reference model + comparison
    ----------------------------------------------------------------------
    stimulus : process
        variable cycle_count : natural := 0;
        variable n           : natural;
        variable exp_hcnt, exp_vcnt : natural;
        variable exp_video_on, exp_hsync, exp_vsync : std_logic;
        variable exp_addr, exp_index : natural;
        variable exp_r, exp_g, exp_b : natural;
        -- vblank_o has its own latency: registered directly from pix_y
        -- (1 cycle), not through the PIPE_LAT+1 delay line other outputs use
        variable n_vb : natural;
        variable exp_vcnt_vb : natural;
        variable exp_vblank : std_logic;
        variable errors      : natural := 0;
        variable reported    : natural := 0;
        constant MAX_REPORTS : natural := 20;
    begin
        rst_i <= '1';
        wait for CLK_PERIOD * 3;
        wait until rising_edge(clk_pix_i);
        rst_i <= '0';
        -- cycle_count counts continuously from reset (including preload) to
        -- stay in sync with the DUT's internal vga_sync counter, which also
        -- starts at 0 here and never stops advancing.

        --------------------------------------------------------------
        -- Palette preload: palette[k] = {k[7:4], k[3:0], k[7:4]}
        --------------------------------------------------------------
        for k in 0 to 255 loop
            wait until rising_edge(clk_pix_i);
            cycle_count := cycle_count + 1;
            wr_idx_i <= to_unsigned(k, 8);
            wr_rgb_i <= std_logic_vector(to_unsigned(k / 16, 4)) &
                        std_logic_vector(to_unsigned(k mod 16, 4)) &
                        std_logic_vector(to_unsigned(k / 16, 4));
            wr_en_i <= '1';
        end loop;
        wait until rising_edge(clk_pix_i);
        cycle_count := cycle_count + 1;
        wr_en_i <= '0';

        -- allow a few cycles for the palette writes to take effect
        for i in 1 to 4 loop
            wait until rising_edge(clk_pix_i);
            cycle_count := cycle_count + 1;
        end loop;

        --------------------------------------------------------------
        -- Main verification loop: one full frame + wraparound
        -- (cycle_count continues from preload, not reset)
        --------------------------------------------------------------
        for i in 1 to NUM_CYCLES loop
            wait until rising_edge(clk_pix_i);
            cycle_count := cycle_count + 1;
            wait until falling_edge(clk_pix_i);

            if cycle_count > TOTAL_LATENCY then
                n := cycle_count - TOTAL_LATENCY;

                exp_hcnt := n mod H_TOTAL;
                exp_vcnt := (n / H_TOTAL) mod V_TOTAL;

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

                if exp_video_on = '1' then
                    exp_addr  := (exp_vcnt / 2) * FB_W + (exp_hcnt / 2);
                    exp_index := exp_addr mod 256;
                    exp_r := exp_index / 16;
                    exp_g := exp_index mod 16;
                    exp_b := exp_index / 16;
                else
                    exp_r := 0;
                    exp_g := 0;
                    exp_b := 0;
                end if;

                if to_integer(unsigned(vga_r_o)) /= exp_r or
                   to_integer(unsigned(vga_g_o)) /= exp_g or
                   to_integer(unsigned(vga_b_o)) /= exp_b or
                   hsync_o /= exp_hsync or vsync_o /= exp_vsync
                then
                    errors := errors + 1;
                    if reported < MAX_REPORTS then
                        report "tb_video_out: FAIL - cevrim " & integer'image(cycle_count) &
                               " (n=" & integer'image(n) & ") beklenen r=" &
                               integer'image(exp_r) & " g=" & integer'image(exp_g) &
                               " b=" & integer'image(exp_b) & " hs=" &
                               std_logic'image(exp_hsync) & " vs=" & std_logic'image(exp_vsync) &
                               " gozlenen r=" & integer'image(to_integer(unsigned(vga_r_o))) &
                               " g=" & integer'image(to_integer(unsigned(vga_g_o))) &
                               " b=" & integer'image(to_integer(unsigned(vga_b_o))) &
                               " hs=" & std_logic'image(hsync_o) & " vs=" & std_logic'image(vsync_o)
                            severity error;
                        reported := reported + 1;
                    end if;
                end if;

                -- vblank_o must be high for the whole vertical-blanking
                -- period, not gated by hcnt (horizontal blanking within
                -- visible lines must not raise it)
                n_vb := cycle_count - 1;
                exp_vcnt_vb := (n_vb / H_TOTAL) mod V_TOTAL;
                if exp_vcnt_vb >= V_VISIBLE then
                    exp_vblank := '1';
                else
                    exp_vblank := '0';
                end if;

                if vblank_o /= exp_vblank then
                    errors := errors + 1;
                    if reported < MAX_REPORTS then
                        report "tb_video_out: FAIL - cevrim " & integer'image(cycle_count) &
                               " (n_vb=" & integer'image(n_vb) & ", vcnt=" & integer'image(exp_vcnt_vb) &
                               ") vblank_o beklenen=" & std_logic'image(exp_vblank) &
                               " gozlenen=" & std_logic'image(vblank_o)
                            severity error;
                        reported := reported + 1;
                    end if;
                end if;
            end if;
        end loop;

        if errors = 0 then
            report "tb_video_out: PASS - " & integer'image(NUM_CYCLES) &
                   " cevrim (1 tam kare + sarma) piksel-tam dogrulandi, vblank_o kare basina TEK KEZ (2026-09-26 duzeltmesi) dahil" severity note;
        else
            report "tb_video_out: FAIL - " & integer'image(errors) & " hata bulundu" severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
