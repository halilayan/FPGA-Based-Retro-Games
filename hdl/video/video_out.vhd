--------------------------------------------------------------------------------
-- video_out.vhd
--
-- Combines vga_sync + fb_reader + palette_lut into the VGA output stage.
--
-- The frame buffer itself lives outside this module (external BRAM /
-- fb_ram: port A written by CPU/blitter/cart, port B read here). This
-- module only generates the read address (fb_addr_o) and receives the
-- BRAM's registered output (fb_dout_i) one cycle later.
--
-- Pipeline: external BRAM read (1 cycle) + palette_lut read (1 cycle) =
-- PIPE_LAT=2, plus a final output register (1 cycle) = 3 cycles total.
-- hsync/vsync/video_on are delayed through a matching shift register so
-- they stay aligned with the correspondingly delayed pixel color.
--
-- RGB output is always forced to zero outside video_on, rather than
-- relying on fb_reader's address being zeroed.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_out is
    generic (
        H_VISIBLE : positive := 640;
        H_FRONT   : positive := 16;
        H_SYNC    : positive := 96;
        H_BACK    : positive := 48;
        V_VISIBLE : positive := 480;
        V_FRONT   : positive := 10;
        V_SYNC    : positive := 2;
        V_BACK    : positive := 33;

        FB_W : positive := 320;
        FB_H : positive := 240;

        PIPE_LAT : positive := 2  -- external BRAM (1) + palette LUT (1) read latency
    );
    port (
        clk_pix_i : in std_logic;
        rst_i     : in std_logic;

        -- External frame buffer (Block Memory Generator / fb_ram) connection
        fb_addr_o : out unsigned(16 downto 0);
        fb_dout_i : in  std_logic_vector(7 downto 0);

        -- Palette write path (CPU/AXI, clk_wr_i may differ from clk_pix_i)
        clk_wr_i : in std_logic;
        wr_en_i  : in std_logic;
        wr_idx_i : in unsigned(7 downto 0);
        wr_rgb_i : in std_logic_vector(11 downto 0);

        -- Physical VGA outputs
        vga_r_o : out std_logic_vector(3 downto 0);
        vga_g_o : out std_logic_vector(3 downto 0);
        vga_b_o : out std_logic_vector(3 downto 0);
        hsync_o : out std_logic;
        vsync_o : out std_logic;

        -- For the CPU side
        vblank_o    : out std_logic;
        frame_cnt_o : out unsigned(31 downto 0)
    );
end entity video_out;

architecture rtl of video_out is

    signal pix_x, pix_y                   : unsigned(9 downto 0);
    signal video_on, hsync_raw, vsync_raw : std_logic;
    signal line_start, frame_start         : std_logic;

    signal fb_addr : unsigned(16 downto 0);
    signal rgb     : std_logic_vector(11 downto 0);

    type delay_line_t is array (0 to PIPE_LAT - 1) of std_logic;
    signal von_delay : delay_line_t := (others => '0');
    signal hs_delay  : delay_line_t := (others => '1');
    signal vs_delay  : delay_line_t := (others => '1');

    signal rgb_final : std_logic_vector(11 downto 0) := (others => '0');
    signal von_final  : std_logic := '0';
    signal hs_final   : std_logic := '1';
    signal vs_final   : std_logic := '1';

    signal frame_cnt : unsigned(31 downto 0) := (others => '0');

    signal vblank_reg : std_logic := '0';  -- registered output for vblank_o (see process below)

begin

    ----------------------------------------------------------------------
    -- VGA timing
    ----------------------------------------------------------------------
    u_vga_sync : entity work.vga_sync
        generic map (
            H_VISIBLE => H_VISIBLE, H_FRONT => H_FRONT, H_SYNC => H_SYNC, H_BACK => H_BACK,
            V_VISIBLE => V_VISIBLE, V_FRONT => V_FRONT, V_SYNC => V_SYNC, V_BACK => V_BACK
        )
        port map (
            clk_pix_i     => clk_pix_i,
            rst_i         => rst_i,
            pix_x_o       => pix_x,
            pix_y_o       => pix_y,
            video_on_o    => video_on,
            hsync_o       => hsync_raw,
            vsync_o       => vsync_raw,
            line_start_o  => line_start,
            frame_start_o => frame_start
        );

    ----------------------------------------------------------------------
    -- Frame buffer address calculation (goes to external BRAM)
    ----------------------------------------------------------------------
    u_fb_reader : entity work.fb_reader
        generic map (
            FB_W => FB_W,
            FB_H => FB_H
        )
        port map (
            pix_x_i    => pix_x,
            pix_y_i    => pix_y,
            video_on_i => video_on,
            fb_addr_o  => fb_addr
        );

    fb_addr_o <= fb_addr;

    ----------------------------------------------------------------------
    -- Palette lookup (processes the external BRAM's 1-cycle-delayed output)
    ----------------------------------------------------------------------
    u_palette_lut : entity work.palette_lut
        port map (
            clk_pix_i => clk_pix_i,
            idx_i     => unsigned(fb_dout_i),
            rgb_o     => rgb,
            clk_wr_i  => clk_wr_i,
            wr_en_i   => wr_en_i,
            wr_idx_i  => wr_idx_i,
            wr_rgb_i  => wr_rgb_i
        );

    ----------------------------------------------------------------------
    -- Pipeline delay alignment (keeps hsync/vsync/video_on in step with rgb)
    ----------------------------------------------------------------------
    delay_proc : process (clk_pix_i)
    begin
        if rising_edge(clk_pix_i) then
            von_delay(0) <= video_on;
            hs_delay(0)  <= hsync_raw;
            vs_delay(0)  <= vsync_raw;
            for i in 1 to PIPE_LAT - 1 loop
                von_delay(i) <= von_delay(i - 1);
                hs_delay(i)  <= hs_delay(i - 1);
                vs_delay(i)  <= vs_delay(i - 1);
            end loop;
        end if;
    end process delay_proc;

    ----------------------------------------------------------------------
    -- Output register: rgb and the aligned hs/vs/video_on are registered
    -- together for one more cycle, so alignment is preserved.
    ----------------------------------------------------------------------
    out_reg : process (clk_pix_i)
    begin
        if rising_edge(clk_pix_i) then
            rgb_final <= rgb;
            hs_final  <= hs_delay(PIPE_LAT - 1);
            vs_final  <= vs_delay(PIPE_LAT - 1);
            von_final <= von_delay(PIPE_LAT - 1);
        end if;
    end process out_reg;

    ----------------------------------------------------------------------
    -- Physical outputs - RGB is always forced to zero outside video_on
    ----------------------------------------------------------------------
    vga_r_o <= rgb_final(11 downto 8) when von_final = '1' else (others => '0');
    vga_g_o <= rgb_final(7 downto 4)  when von_final = '1' else (others => '0');
    vga_b_o <= rgb_final(3 downto 0)  when von_final = '1' else (others => '0');

    hsync_o <= hs_final;
    vsync_o <= vs_final;

    -- vblank_o is derived from pix_y >= V_VISIBLE directly (same condition
    -- vga_sync uses for frame_start), NOT from inverting video_on:
    -- video_on also drops during horizontal blanking on every line, which
    -- would make vblank_o pulse once per line instead of once per frame.
    vblank_proc : process (clk_pix_i)
    begin
        if rising_edge(clk_pix_i) then
            if pix_y >= V_VISIBLE then
                vblank_reg <= '1';
            else
                vblank_reg <= '0';
            end if;
        end if;
    end process vblank_proc;

    vblank_o <= vblank_reg;

    ----------------------------------------------------------------------
    -- Frame counter (uses raw frame_start - no pipeline alignment needed,
    -- just increments once per frame)
    ----------------------------------------------------------------------
    frame_cnt_proc : process (clk_pix_i)
    begin
        if rising_edge(clk_pix_i) then
            if rst_i = '1' then
                frame_cnt <= (others => '0');
            elsif frame_start = '1' then
                frame_cnt <= frame_cnt + 1;
            end if;
        end if;
    end process frame_cnt_proc;

    frame_cnt_o <= frame_cnt;

end architecture rtl;
