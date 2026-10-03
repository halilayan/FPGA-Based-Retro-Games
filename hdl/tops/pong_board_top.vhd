--------------------------------------------------------------------------------
-- pong_board_top.vhd
--
-- Board test for the standalone pure-VHDL Pong demo. Wraps the existing pong_top.vhd
-- unchanged, adding the pixel clock and per-domain reset synchronisation it
-- expects as ports.
--
-- Controls: keyboard (player 1 = W / S, player 2 = O / L; see kbd_to_pad.vhd,
-- arrow keys are PS/2 "extended" codes and are intentionally ignored) or
-- board switches, whichever is present:
--   sw_i(14) player 1 up     sw_i(15) player 1 down
--   sw_i(0)  player 2 up     sw_i(1)  player 2 down
--
-- LEDs:
--   led_o(0)   MMCM locked
--   led_o(15)  1 Hz heartbeat
--
-- Port list matches vga_test_top / kbd_test_top so all three board tests
-- share a single XDC.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pong_board_top is
    generic (
        SIM_MODE     : boolean  := false;
        SIM_DIV      : positive := 4;
        CLK_HZ       : positive := 100_000_000;
        HEARTBEAT_HZ : positive := 1
    );
    port (
        clk_i : in std_logic;  -- 100 MHz (W5)
        rst_i : in std_logic;  -- BTNC (U18), active high

        ps2_clk_i  : in std_logic;  -- C17 (PULLUP TRUE required)
        ps2_data_i : in std_logic;  -- B17 (PULLUP TRUE required)

        sw_i : in std_logic_vector(15 downto 0);  -- only bits 0,1,14,15 used

        vga_r_o : out std_logic_vector(3 downto 0);
        vga_g_o : out std_logic_vector(3 downto 0);
        vga_b_o : out std_logic_vector(3 downto 0);
        hsync_o : out std_logic;
        vsync_o : out std_logic;

        led_o : out std_logic_vector(15 downto 0)
    );
end entity pong_board_top;

architecture rtl of pong_board_top is

    constant HEARTBEAT_TICKS : positive := CLK_HZ / (2 * HEARTBEAT_HZ);

    signal clk_pix   : std_logic;
    signal locked    : std_logic;
    signal rst_async : std_logic;
    signal rst_sys   : std_logic;
    signal rst_pix   : std_logic;

    signal hb_cnt : natural range 0 to HEARTBEAT_TICKS := 0;
    signal hb     : std_logic := '0';

    -- Named by physical switch position; player mapping is applied at the
    -- pong_top port map below.
    signal sw0, sw1, sw14, sw15 : std_logic;

begin

    u_clk : entity work.clk_pix_gen
        generic map (SIM_MODE => SIM_MODE, SIM_DIV => SIM_DIV)
        port map (clk_sys_i => clk_i, clk_pix_o => clk_pix, locked_o => locked);

    rst_async <= rst_i or (not locked);

    u_rst_sync_sys : entity work.sync_2ff
        generic map (INIT => '1')
        port map (clk_i => clk_i, din_i => rst_async, dout_o => rst_sys);

    u_rst_sync_pix : entity work.sync_2ff
        generic map (INIT => '1')
        port map (clk_i => clk_pix, din_i => rst_async, dout_o => rst_pix);

    u_deb_sw0 : entity work.debounce
        generic map (CLK_HZ => CLK_HZ)
        port map (clk_i => clk_i, rst_i => rst_sys, d_i => sw_i(0), d_o => sw0);

    u_deb_sw1 : entity work.debounce
        generic map (CLK_HZ => CLK_HZ)
        port map (clk_i => clk_i, rst_i => rst_sys, d_i => sw_i(1), d_o => sw1);

    u_deb_sw14 : entity work.debounce
        generic map (CLK_HZ => CLK_HZ)
        port map (clk_i => clk_i, rst_i => rst_sys, d_i => sw_i(14), d_o => sw14);

    u_deb_sw15 : entity work.debounce
        generic map (CLK_HZ => CLK_HZ)
        port map (clk_i => clk_i, rst_i => rst_sys, d_i => sw_i(15), d_o => sw15);

    u_pong : entity work.pong_top
        port map (
            clk_sys_i  => clk_i,
            clk_pix_i  => clk_pix,
            rst_sys_i  => rst_sys,
            rst_pix_i  => rst_pix,
            ps2_clk_i  => ps2_clk_i,
            ps2_data_i => ps2_data_i,
            sw_up1_i   => sw14,  -- player 1 <- SW14/SW15
            sw_down1_i => sw15,
            sw_up2_i   => sw0,   -- player 2 <- SW0/SW1
            sw_down2_i => sw1,
            vga_r_o    => vga_r_o,
            vga_g_o    => vga_g_o,
            vga_b_o    => vga_b_o,
            hsync_o    => hsync_o,
            vsync_o    => vsync_o
        );

    hb_proc : process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_sys = '1' then
                hb_cnt <= 0;
                hb     <= '0';
            elsif hb_cnt = HEARTBEAT_TICKS - 1 then
                hb_cnt <= 0;
                hb     <= not hb;
            else
                hb_cnt <= hb_cnt + 1;
            end if;
        end if;
    end process hb_proc;

    led_o(0)           <= locked;
    led_o(14 downto 1) <= (others => '0');
    led_o(15)          <= hb;

end architecture rtl;
