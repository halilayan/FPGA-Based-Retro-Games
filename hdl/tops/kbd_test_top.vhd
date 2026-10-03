--------------------------------------------------------------------------------
-- kbd_test_top.vhd
--
-- Board test for the PS/2 keyboard subsystem. No monitor needed -
-- everything shows up on the LEDs.
--
-- Plug a USB keyboard into the board's USB HOST port (not PROG), load the
-- bitstream, press a key.
--
-- LEDs:
--   led_o(7..0)  last valid scan code (parity + frame checked)
--   led_o(8)     activity - lit for ~120 ms after a valid byte
--   led_o(12)    sticky parity-error flag (cleared by reset)
--   led_o(13)    sticky frame-error flag (cleared by reset)
--   led_o(15)    1 Hz heartbeat - design is alive
--
-- If led_o(15) is not blinking: bitstream/clock problem. If it blinks but
-- led_o(7..0) never changes on a keypress: check PULLUP TRUE in the XDC,
-- the keyboard port, or the keyboard's PS/2 support.
--
-- Port list matches vga_test_top / pong_board_top so all three board tests
-- share a single XDC; unused vga_*/hsync/vsync outputs are simply driven low.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kbd_test_top is
    generic (
        CLK_HZ       : positive := 100_000_000;
        HEARTBEAT_HZ : positive := 1;
        STRETCH_MS   : positive := 120
    );
    port (
        clk_i : in std_logic;  -- 100 MHz (W5)
        rst_i : in std_logic;  -- BTNC (U18), active high

        ps2_clk_i  : in std_logic;  -- C17 (PULLUP TRUE required)
        ps2_data_i : in std_logic;  -- B17 (PULLUP TRUE required)

        vga_r_o : out std_logic_vector(3 downto 0);  -- unused in this test
        vga_g_o : out std_logic_vector(3 downto 0);  -- unused in this test
        vga_b_o : out std_logic_vector(3 downto 0);  -- unused in this test
        hsync_o : out std_logic;                      -- unused in this test
        vsync_o : out std_logic;                      -- unused in this test

        led_o : out std_logic_vector(15 downto 0)
    );
end entity kbd_test_top;

architecture rtl of kbd_test_top is

    constant HEARTBEAT_TICKS : positive := CLK_HZ / (2 * HEARTBEAT_HZ);
    constant STRETCH_TICKS   : positive := (CLK_HZ / 1000) * STRETCH_MS;

    signal rst_sys : std_logic;

    signal rx_data    : std_logic_vector(7 downto 0);
    signal rx_valid   : std_logic;
    signal parity_err : std_logic;
    signal frame_err  : std_logic;

    signal last_code : std_logic_vector(7 downto 0) := (others => '0');

    signal parity_sticky : std_logic := '0';
    signal frame_sticky  : std_logic := '0';

    signal stretch_cnt : natural range 0 to STRETCH_TICKS := 0;
    signal activity    : std_logic := '0';

    signal hb_cnt : natural range 0 to HEARTBEAT_TICKS := 0;
    signal hb     : std_logic := '0';

begin

    vga_r_o <= (others => '0');
    vga_g_o <= (others => '0');
    vga_b_o <= (others => '0');
    hsync_o <= '1';
    vsync_o <= '1';

    u_rst_sync : entity work.sync_2ff
        generic map (INIT => '1')
        port map (clk_i => clk_i, din_i => rst_i, dout_o => rst_sys);

    u_ps2_rx : entity work.ps2_rx
        generic map (CLK_HZ => CLK_HZ)
        port map (
            clk_i        => clk_i,
            rst_i        => rst_sys,
            ps2_clk_i    => ps2_clk_i,
            ps2_data_i   => ps2_data_i,
            rx_data_o    => rx_data,
            rx_valid_o   => rx_valid,
            parity_err_o => parity_err,
            frame_err_o  => frame_err
        );

    capture_proc : process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_sys = '1' then
                last_code     <= (others => '0');
                parity_sticky <= '0';
                frame_sticky  <= '0';
                stretch_cnt   <= 0;
                activity      <= '0';
            else
                if rx_valid = '1' then
                    last_code   <= rx_data;
                    activity    <= '1';
                    stretch_cnt <= STRETCH_TICKS;
                elsif stretch_cnt /= 0 then
                    stretch_cnt <= stretch_cnt - 1;
                else
                    activity <= '0';
                end if;

                if parity_err = '1' then
                    parity_sticky <= '1';
                end if;
                if frame_err = '1' then
                    frame_sticky <= '1';
                end if;
            end if;
        end if;
    end process capture_proc;

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

    led_o(7 downto 0)  <= last_code;
    led_o(8)           <= activity;
    led_o(11 downto 9) <= (others => '0');
    led_o(12)          <= parity_sticky;
    led_o(13)          <= frame_sticky;
    led_o(14)          <= '0';
    led_o(15)          <= hb;

end architecture rtl;
