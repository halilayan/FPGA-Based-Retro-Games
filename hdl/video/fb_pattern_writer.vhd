--------------------------------------------------------------------------------
-- fb_pattern_writer.vhd
--
-- Writes a test pattern into the frame buffer once after reset (FB_W*FB_H
-- cycles) and then stops.
--
-- Pattern: 1-pixel white border, 8 vertical colour bars, and red/green/blue
-- 16-step ramps across the bottom quarter. The bars check the RGB channel
-- wiring, the ramps check every bit of each channel, and the border shows
-- that the whole active area is scanned.
--
-- Palette indices used (the parent module must load them):
--   0        white (border)
--   1 - 8    colour bars
--   16 - 31  red ramp, 32 - 47 green ramp, 48 - 63 blue ramp
--
-- Bar and ramp boundaries are tracked with counters, so no divider is
-- synthesised.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fb_pattern_writer is
    generic (
        FB_W : positive := 320;
        FB_H : positive := 240
    );
    port (
        clk_i : in std_logic;
        rst_i : in std_logic;  -- synchronous, active high

        -- frame buffer write port (matches fb_ram port A)
        we_o   : out std_logic;
        addr_o : out unsigned(16 downto 0);
        din_o  : out std_logic_vector(7 downto 0);

        done_o : out std_logic  -- '1' = whole frame written, writer stopped
    );
end entity fb_pattern_writer;

architecture rtl of fb_pattern_writer is

    -- Pattern geometry (elaboration-time constants, no divider inferred)
    constant BAR_W   : positive := FB_W / 8;      -- width of one colour bar
    constant STEP_W  : positive := FB_W / 16;     -- width of one ramp step
    constant RAMP_Y0 : positive := (FB_H * 3) / 4;  -- first ramp row
    constant BAND_H  : positive := (FB_H - RAMP_Y0) / 3;  -- height of one ramp band

    constant LAST_ADDR : natural := FB_W * FB_H - 1;

    signal x        : natural range 0 to FB_W - 1 := 0;
    signal y        : natural range 0 to FB_H - 1 := 0;
    signal bar_cnt  : natural range 0 to BAR_W - 1 := 0;
    signal bar_idx  : natural range 0 to 7 := 0;
    signal step_cnt : natural range 0 to STEP_W - 1 := 0;
    signal step_idx : natural range 0 to 15 := 0;

    signal addr    : unsigned(16 downto 0) := (others => '0');
    signal running : std_logic := '1';

    signal idx : natural range 0 to 255;

begin

    -- Palette index for the current (x,y): combinational, valid in the same
    -- cycle as addr.
    idx <= 0                        when (x = 0) or (x = FB_W - 1) or
                                         (y = 0) or (y = FB_H - 1) else  -- border
           1 + bar_idx              when y < RAMP_Y0 else                 -- colour bars
           16 + step_idx            when y < RAMP_Y0 + BAND_H else        -- red ramp
           32 + step_idx            when y < RAMP_Y0 + 2 * BAND_H else    -- green ramp
           48 + step_idx;                                                 -- blue ramp

    din_o  <= std_logic_vector(to_unsigned(idx, 8));
    addr_o <= addr;
    we_o   <= running;
    done_o <= not running;

    -- Raster sweep: one pixel per cycle, then stop permanently.
    sweep_proc : process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                x        <= 0;
                y        <= 0;
                bar_cnt  <= 0;
                bar_idx  <= 0;
                step_cnt <= 0;
                step_idx <= 0;
                addr     <= (others => '0');
                running  <= '1';

            elsif running = '1' then
                if addr = to_unsigned(LAST_ADDR, addr'length) then
                    -- last pixel written in this cycle: stop for good
                    running <= '0';
                else
                    addr <= addr + 1;
                end if;

                if x = FB_W - 1 then
                    -- end of line: next row, clear the horizontal counters
                    x        <= 0;
                    bar_cnt  <= 0;
                    bar_idx  <= 0;
                    step_cnt <= 0;
                    step_idx <= 0;
                    if y /= FB_H - 1 then
                        y <= y + 1;
                    end if;
                else
                    x <= x + 1;

                    if bar_cnt = BAR_W - 1 then
                        bar_cnt <= 0;
                        if bar_idx < 7 then
                            bar_idx <= bar_idx + 1;
                        end if;
                    else
                        bar_cnt <= bar_cnt + 1;
                    end if;

                    if step_cnt = STEP_W - 1 then
                        step_cnt <= 0;
                        if step_idx < 15 then
                            step_idx <= step_idx + 1;
                        end if;
                    else
                        step_cnt <= step_cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process sweep_proc;

end architecture rtl;
