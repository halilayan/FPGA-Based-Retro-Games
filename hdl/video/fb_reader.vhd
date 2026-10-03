--------------------------------------------------------------------------------
-- fb_reader.vhd
--
-- Converts VGA pixel coordinates (640x480, from vga_sync) into a frame
-- buffer address (320x240, 8bpp, 17-bit).
--
-- Fully combinational (no clock): fb_addr_o is recomputed every cycle from
-- pix_x_i/pix_y_i. The 1-cycle read latency comes from the external BRAM
-- itself, so adding delay here would break video_out's pipeline alignment.
--
-- Scale is fixed at 2x (320x240 -> 640x480), so a plain 1-bit right shift
-- is used instead of a general divide.
--
-- Address calc is specific to FB_W=320: 320 = 256 + 64 = 2^8 + 2^6, so
-- sy*320 = (sy << 8) + (sy << 6) - computed with shifts/adds, no
-- multiplier. NOTE: update this if FB_W changes.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fb_reader is
    generic (
        FB_W : positive := 320;
        FB_H : positive := 240
    );
    port (
        pix_x_i    : in  unsigned(9 downto 0);
        pix_y_i    : in  unsigned(9 downto 0);
        video_on_i : in  std_logic;

        fb_addr_o : out unsigned(16 downto 0)
    );
end entity fb_reader;

architecture rtl of fb_reader is

    signal sx, sy         : unsigned(9 downto 0);
    signal sx_ext, sy_ext : unsigned(16 downto 0);
    signal addr           : unsigned(16 downto 0);

begin

    -- Scale to 320x240 logical coordinates (SCALE=2, shift instead of divide)
    sx <= shift_right(pix_x_i, 1);
    sy <= shift_right(pix_y_i, 1);

    sx_ext <= resize(sx, 17);
    sy_ext <= resize(sy, 17);

    -- addr = sy*320 + sx = (sy<<8) + (sy<<6) + sx  (specific to FB_W=320)
    addr <= shift_left(sy_ext, 8) + shift_left(sy_ext, 6) + sx_ext;

    fb_addr_o <= addr when video_on_i = '1' else (others => '0');

end architecture rtl;
