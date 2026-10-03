--------------------------------------------------------------------------------
-- tb_fb_reader.vhd
--
-- Testbench for fb_reader.vhd: verifies address generation
-- (addr = (y/2)*FB_W + (x/2)) across the full 640x480 input space, and
-- that the address is forced to zero when video_on_i='0'.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_fb_reader is
end entity tb_fb_reader;

architecture sim of tb_fb_reader is

    constant FB_W  : positive := 320;
    constant FB_H  : positive := 240;
    constant SCALE : positive := 2;  -- fixed value assumed by the DUT

    signal pix_x_i    : unsigned(9 downto 0) := (others => '0');
    signal pix_y_i    : unsigned(9 downto 0) := (others => '0');
    signal video_on_i : std_logic := '1';
    signal fb_addr_o  : unsigned(16 downto 0);

begin

    dut : entity work.fb_reader
        generic map (
            FB_W => FB_W,
            FB_H => FB_H
        )
        port map (
            pix_x_i    => pix_x_i,
            pix_y_i    => pix_y_i,
            video_on_i => video_on_i,
            fb_addr_o  => fb_addr_o
        );

    stimulus : process
        variable expected  : natural;
        variable errors    : natural := 0;
        variable reported  : natural := 0;
        variable checked   : natural := 0;
        constant MAX_REPORTS : natural := 20;
    begin
        video_on_i <= '1';

        -- Full sweep: for each (x,y), addr = (y/SCALE)*FB_W + (x/SCALE)
        for y in 0 to 479 loop
            for x in 0 to 639 loop
                pix_x_i <= to_unsigned(x, 10);
                pix_y_i <= to_unsigned(y, 10);
                wait for 1 ns;

                expected := (y / SCALE) * FB_W + (x / SCALE);
                checked  := checked + 1;

                if to_integer(fb_addr_o) /= expected then
                    errors := errors + 1;
                    if reported < MAX_REPORTS then
                        report "tb_fb_reader: FAIL - x=" & integer'image(x) &
                               " y=" & integer'image(y) &
                               " beklenen=" & integer'image(expected) &
                               " gozlenen=" & integer'image(to_integer(fb_addr_o))
                            severity error;
                        reported := reported + 1;
                    end if;
                end if;
            end loop;
        end loop;

        -- video_on_i='0' should force the address to zero (a few sample points)
        video_on_i <= '0';
        pix_x_i <= to_unsigned(100, 10);
        pix_y_i <= to_unsigned(200, 10);
        wait for 1 ns;
        if to_integer(fb_addr_o) /= 0 then
            errors := errors + 1;
            report "tb_fb_reader: FAIL - video_on_i='0' iken fb_addr_o sifir degil (" &
                   integer'image(to_integer(fb_addr_o)) & ")" severity error;
        end if;

        video_on_i <= '0';
        pix_x_i <= to_unsigned(639, 10);
        pix_y_i <= to_unsigned(479, 10);
        wait for 1 ns;
        if to_integer(fb_addr_o) /= 0 then
            errors := errors + 1;
            report "tb_fb_reader: FAIL - video_on_i='0' iken (kose) fb_addr_o sifir degil" severity error;
        end if;

        if errors = 0 then
            report "tb_fb_reader: PASS - " & integer'image(checked) &
                   " koordinat + video_on sinir testleri dogrulandi" severity note;
        else
            report "tb_fb_reader: FAIL - " & integer'image(errors) & " hata bulundu" severity failure;
        end if;

        wait for 1 ns;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
