--------------------------------------------------------------------------------
-- pong_top.vhd
--
-- Top-level wiring for the pure-VHDL Pong demo: keyboard -> pad input ->
-- game physics/draw -> frame buffer -> video output.
--
-- clk_sys_i (100 MHz, board pin W5) and clk_pix_i (25.155 MHz, from
-- clk_pix_gen's MMCM) are separate clock domains. Each clock domain has
-- its own reset port, since a single reset shared across both domains
-- would create an unmeetable clk_sys -> clk_pix setup path.
--
-- video_out/palette_lut defaults every palette entry to black, which would
-- make Pong invisible (every color index maps to black); the first 5
-- cycles after reset write the actual colors pong_core's 5 color indices
-- (0-4) need.
--
-- Paddle input: keyboard (PS/2) and board switches both feed pong_core,
-- OR'd together, so either source works.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pong_top is
    port (
        clk_sys_i : in std_logic;  -- 100 MHz (W5)
        clk_pix_i : in std_logic;  -- 25,155 MHz (clk_pix_gen)

        -- Synchronous, active high; one per clock domain.
        rst_sys_i : in std_logic;
        rst_pix_i : in std_logic;

        ps2_clk_i  : in std_logic;
        ps2_data_i : in std_logic;

        -- Board switches, debounced by the caller. Same sense as the
        -- keyboard-decoded signals: '1' while held.
        sw_up1_i   : in std_logic;
        sw_down1_i : in std_logic;
        sw_up2_i   : in std_logic;
        sw_down2_i : in std_logic;

        vga_r_o : out std_logic_vector(3 downto 0);
        vga_g_o : out std_logic_vector(3 downto 0);
        vga_b_o : out std_logic_vector(3 downto 0);
        hsync_o : out std_logic;
        vsync_o : out std_logic
    );
end entity pong_top;

architecture rtl of pong_top is

    signal ps2_byte  : std_logic_vector(7 downto 0);
    signal ps2_valid : std_logic;

    signal kbd_up1, kbd_down1, kbd_up2, kbd_down2 : std_logic;
    signal up1, down1, up2, down2 : std_logic;

    signal fb_we   : std_logic;
    signal fb_addr : unsigned(16 downto 0);
    signal fb_din  : std_logic_vector(7 downto 0);

    signal video_fb_addr : unsigned(16 downto 0);
    signal video_fb_dout : std_logic_vector(7 downto 0);

    -- Palette init write sequence: index 0..4, then stops
    signal pal_cnt   : unsigned(2 downto 0) := (others => '0');
    signal pal_wr_en : std_logic;
    signal pal_idx   : unsigned(7 downto 0);
    signal pal_rgb   : std_logic_vector(11 downto 0);

begin

    ----------------------------------------------------------------------
    -- Keyboard: PS/2 receiver -> pad decoder (clk_sys_i domain)
    ----------------------------------------------------------------------
    u_ps2_rx : entity work.ps2_rx
        port map (
            clk_i        => clk_sys_i,
            rst_i        => rst_sys_i,
            ps2_clk_i    => ps2_clk_i,
            ps2_data_i   => ps2_data_i,
            rx_data_o    => ps2_byte,
            rx_valid_o   => ps2_valid,
            parity_err_o => open,
            frame_err_o  => open
        );

    u_kbd_to_pad : entity work.kbd_to_pad
        port map (
            clk_i      => clk_sys_i,
            rst_i      => rst_sys_i,
            rx_data_i  => ps2_byte,
            rx_valid_i => ps2_valid,
            up1_o      => kbd_up1,
            down1_o    => kbd_down1,
            up2_o      => kbd_up2,
            down2_o    => kbd_down2
        );

    up1   <= kbd_up1   or sw_up1_i;
    down1 <= kbd_down1 or sw_down1_i;
    up2   <= kbd_up2   or sw_up2_i;
    down2 <= kbd_down2 or sw_down2_i;

    ----------------------------------------------------------------------
    -- Game physics + continuous scan/draw (clk_sys_i domain)
    ----------------------------------------------------------------------
    u_pong_core : entity work.pong_core
        port map (
            clk_i       => clk_sys_i,
            rst_i       => rst_sys_i,
            up1_i       => up1,
            down1_i     => down1,
            up2_i       => up2,
            down2_i     => down2,
            fb_we_o     => fb_we,
            fb_addr_o   => fb_addr,
            fb_din_o    => fb_din,
            score1_o    => open,
            score2_o    => open,
            ball_x_o    => open,
            ball_y_o    => open,
            ball_vx_o   => open,
            ball_vy_o   => open,
            paddle1_y_o => open,
            paddle2_y_o => open
        );

    ----------------------------------------------------------------------
    -- Frame buffer: Port A write (clk_sys_i), Port B read (clk_pix_i)
    ----------------------------------------------------------------------
    u_fb_ram : entity work.fb_ram
        port map (
            clk_a_i  => clk_sys_i,
            we_a_i   => fb_we,
            addr_a_i => fb_addr,
            din_a_i  => fb_din,
            dout_a_o => open,
            clk_b_i  => clk_pix_i,
            addr_b_i => video_fb_addr,
            dout_b_o => video_fb_dout
        );

    ----------------------------------------------------------------------
    -- Palette init sequence (clk_sys_i domain, completes 5 cycles after
    -- reset): 0=black(bg), 1=white(ball), 2=light gray(paddle),
    -- 3=dark gray(center line), 4=white(score text)
    ----------------------------------------------------------------------
    process (clk_sys_i)
    begin
        if rising_edge(clk_sys_i) then
            if rst_sys_i = '1' then
                pal_cnt <= (others => '0');
            elsif pal_cnt < 5 then
                pal_cnt <= pal_cnt + 1;
            end if;
        end if;
    end process;

    pal_wr_en <= '1' when pal_cnt < 5 else '0';
    pal_idx   <= resize(pal_cnt, 8);

    pal_rgb <= x"000" when pal_cnt = 0 else
               x"FFF" when pal_cnt = 1 else
               x"CCC" when pal_cnt = 2 else
               x"666" when pal_cnt = 3 else
               x"FFF";  -- pal_cnt = 4

    ----------------------------------------------------------------------
    -- Video output (clk_pix_i domain)
    ----------------------------------------------------------------------
    u_video_out : entity work.video_out
        port map (
            clk_pix_i   => clk_pix_i,
            rst_i       => rst_pix_i,
            fb_addr_o   => video_fb_addr,
            fb_dout_i   => video_fb_dout,
            clk_wr_i    => clk_sys_i,
            wr_en_i     => pal_wr_en,
            wr_idx_i    => pal_idx,
            wr_rgb_i    => pal_rgb,
            vga_r_o     => vga_r_o,
            vga_g_o     => vga_g_o,
            vga_b_o     => vga_b_o,
            hsync_o     => hsync_o,
            vsync_o     => vsync_o,
            vblank_o    => open,
            frame_cnt_o => open
        );

end architecture rtl;
