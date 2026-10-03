--------------------------------------------------------------------------------
-- vga_test_top.vhd
--
-- Board test for the video subsystem. Writes a test pattern into the
-- frame buffer once, loads the palette, and drives VGA. No MicroBlaze, no
-- Block Design.
--
-- Expected image: white border, 8 vertical colour bars, red/green/blue
-- brightness ramps (see fb_pattern_writer.vhd).
--
-- LEDs:
--   led_o(0)      MMCM locked
--   led_o(1)      pattern writer done
--   led_o(2)      palette writer done
--   led_o(15..8)  frame counter (slow-moving)
--
-- Port list matches kbd_test_top / pong_board_top so all three board tests
-- share a single XDC; unused ps2_* inputs are simply ignored.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_test_top is
    generic (
        SIM_MODE : boolean  := false;
        SIM_DIV  : positive := 4
    );
    port (
        clk_i : in std_logic;  -- 100 MHz (W5)
        rst_i : in std_logic;  -- BTNC (U18), active high

        ps2_clk_i  : in std_logic;  -- unused in this test
        ps2_data_i : in std_logic;  -- unused in this test

        vga_r_o : out std_logic_vector(3 downto 0);
        vga_g_o : out std_logic_vector(3 downto 0);
        vga_b_o : out std_logic_vector(3 downto 0);
        hsync_o : out std_logic;
        vsync_o : out std_logic;

        led_o : out std_logic_vector(15 downto 0)
    );
end entity vga_test_top;

architecture rtl of vga_test_top is

    constant FB_W : positive := 320;
    constant FB_H : positive := 240;
    constant PAL_LAST : natural := 56;  -- 9 fixed colours + 48 ramp entries

    signal clk_pix   : std_logic;
    signal locked    : std_logic;
    signal rst_async : std_logic;
    signal rst_sys   : std_logic;
    signal rst_pix   : std_logic;

    signal wr_we   : std_logic;
    signal wr_addr : unsigned(16 downto 0);
    signal wr_din  : std_logic_vector(7 downto 0);
    signal wr_done : std_logic;

    signal fb_addr : unsigned(16 downto 0);
    signal fb_dout : std_logic_vector(7 downto 0);

    signal pal_cnt   : natural range 0 to PAL_LAST + 1 := 0;
    signal pal_wr_en : std_logic;
    signal pal_idx   : unsigned(7 downto 0);
    signal pal_rgb   : std_logic_vector(11 downto 0);
    signal pal_done  : std_logic;

    signal frame_cnt : unsigned(31 downto 0);

begin

    u_clk : entity work.clk_pix_gen
        generic map (
            SIM_MODE => SIM_MODE,
            SIM_DIV  => SIM_DIV
        )
        port map (
            clk_sys_i => clk_i,
            clk_pix_o => clk_pix,
            locked_o  => locked
        );

    rst_async <= rst_i or (not locked);

    u_rst_sync_sys : entity work.sync_2ff
        generic map (INIT => '1')
        port map (clk_i => clk_i, din_i => rst_async, dout_o => rst_sys);

    u_rst_sync_pix : entity work.sync_2ff
        generic map (INIT => '1')
        port map (clk_i => clk_pix, din_i => rst_async, dout_o => rst_pix);

    u_writer : entity work.fb_pattern_writer
        generic map (FB_W => FB_W, FB_H => FB_H)
        port map (
            clk_i  => clk_i,
            rst_i  => rst_sys,
            we_o   => wr_we,
            addr_o => wr_addr,
            din_o  => wr_din,
            done_o => wr_done
        );

    u_fb_ram : entity work.fb_ram
        generic map (FB_W => FB_W, FB_H => FB_H)
        port map (
            clk_a_i  => clk_i,
            we_a_i   => wr_we,
            addr_a_i => wr_addr,
            din_a_i  => wr_din,
            dout_a_o => open,
            clk_b_i  => clk_pix,
            addr_b_i => fb_addr,
            dout_b_o => fb_dout
        );

    ----------------------------------------------------------------------
    -- Palette load sequence (clk_i domain, 57 cycles):
    --   idx 0      white  - border
    --   idx 1-8    8 bar colours
    --   idx 16-31  red ramp, 32-47 green ramp, 48-63 blue ramp
    ----------------------------------------------------------------------
    pal_seq : process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_sys = '1' then
                pal_cnt <= 0;
            elsif pal_cnt <= PAL_LAST then
                pal_cnt <= pal_cnt + 1;
            end if;
        end if;
    end process pal_seq;

    pal_wr_en <= '1' when pal_cnt <= PAL_LAST else '0';
    pal_done  <= '1' when pal_cnt > PAL_LAST else '0';

    pal_comb : process (pal_cnt)
        variable step : unsigned(3 downto 0);
    begin
        case pal_cnt is
            when 0 => pal_idx <= to_unsigned(0, 8); pal_rgb <= x"FFF";
            when 1 => pal_idx <= to_unsigned(1, 8); pal_rgb <= x"FF0";
            when 2 => pal_idx <= to_unsigned(2, 8); pal_rgb <= x"0FF";
            when 3 => pal_idx <= to_unsigned(3, 8); pal_rgb <= x"0F0";
            when 4 => pal_idx <= to_unsigned(4, 8); pal_rgb <= x"F0F";
            when 5 => pal_idx <= to_unsigned(5, 8); pal_rgb <= x"F00";
            when 6 => pal_idx <= to_unsigned(6, 8); pal_rgb <= x"00F";
            when 7 => pal_idx <= to_unsigned(7, 8); pal_rgb <= x"888";
            when 8 => pal_idx <= to_unsigned(8, 8); pal_rgb <= x"444";
            when others =>
                if pal_cnt <= 24 then
                    step    := to_unsigned(pal_cnt - 9, 4);
                    pal_idx <= to_unsigned(16 + (pal_cnt - 9), 8);
                    pal_rgb <= std_logic_vector(step) & x"00";
                elsif pal_cnt <= 40 then
                    step    := to_unsigned(pal_cnt - 25, 4);
                    pal_idx <= to_unsigned(32 + (pal_cnt - 25), 8);
                    pal_rgb <= x"0" & std_logic_vector(step) & x"0";
                else
                    step    := to_unsigned(pal_cnt - 41, 4);
                    pal_idx <= to_unsigned(48 + (pal_cnt - 41), 8);
                    pal_rgb <= x"00" & std_logic_vector(step);
                end if;
        end case;
    end process pal_comb;

    u_video_out : entity work.video_out
        generic map (FB_W => FB_W, FB_H => FB_H)
        port map (
            clk_pix_i   => clk_pix,
            rst_i       => rst_pix,
            fb_addr_o   => fb_addr,
            fb_dout_i   => fb_dout,
            clk_wr_i    => clk_i,
            wr_en_i     => pal_wr_en,
            wr_idx_i    => pal_idx,
            wr_rgb_i    => pal_rgb,
            vga_r_o     => vga_r_o,
            vga_g_o     => vga_g_o,
            vga_b_o     => vga_b_o,
            hsync_o     => hsync_o,
            vsync_o     => vsync_o,
            vblank_o    => open,
            frame_cnt_o => frame_cnt
        );

    led_o(0)           <= locked;
    led_o(1)           <= wr_done;
    led_o(2)           <= pal_done;
    led_o(7 downto 3)  <= (others => '0');
    led_o(15 downto 8) <= std_logic_vector(frame_cnt(12 downto 5));

end architecture rtl;
