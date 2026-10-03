--------------------------------------------------------------------------------
-- axi_bram_byte_adapter.vhd
--
-- Adapts axi_bram_ctrl's native BRAM port (32-bit data, byte-lane write
-- enables) to fb_arbiter's CPU interface (8-bit data, flat per-byte
-- address, single write-enable bit). Purely combinational, no clock/reset.
-- Supports single-byte stores only (at most one bram_we_a bit set).
--
-- axi_bram_ctrl's BRAM port addresses whole 32-bit words, so
-- bram_addr_a's low 2 bits are always "00"; which byte lane is targeted
-- is carried only by bram_we_a. The missing low address bits are
-- reconstructed here from bram_we_a rather than copied from bram_addr_a.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_bram_byte_adapter is
    generic (
        ADDR_WIDTH_G : positive := 17  -- cpu_addr_o width: 17 bits = 128 KiB, covers a 320x240 8bpp framebuffer (76,800 bytes)
    );
    port (
        bram_we_a_i     : in  std_logic_vector(3 downto 0);
        bram_addr_a_i   : in  std_logic_vector(ADDR_WIDTH_G - 1 downto 0);
        bram_wrdata_a_i : in  std_logic_vector(31 downto 0);

        cpu_we_o   : out std_logic;
        cpu_addr_o : out unsigned(ADDR_WIDTH_G - 1 downto 0);
        cpu_din_o  : out std_logic_vector(7 downto 0)
    );
end entity axi_bram_byte_adapter;

architecture rtl of axi_bram_byte_adapter is

    signal lane_sel : std_logic_vector(1 downto 0);

begin

    cpu_we_o <= bram_we_a_i(0) or bram_we_a_i(1) or bram_we_a_i(2) or bram_we_a_i(3);

    cpu_din_o <= bram_wrdata_a_i(7 downto 0)   when bram_we_a_i(0) = '1' else
                 bram_wrdata_a_i(15 downto 8)  when bram_we_a_i(1) = '1' else
                 bram_wrdata_a_i(23 downto 16) when bram_we_a_i(2) = '1' else
                 bram_wrdata_a_i(31 downto 24) when bram_we_a_i(3) = '1' else
                 (others => '0');

    -- Which byte lane is being written - the two low address bits
    -- bram_addr_a_i cannot supply (see header note).
    lane_sel <= "00" when bram_we_a_i(0) = '1' else
                "01" when bram_we_a_i(1) = '1' else
                "10" when bram_we_a_i(2) = '1' else
                "11" when bram_we_a_i(3) = '1' else
                "00";

    cpu_addr_o <= unsigned(bram_addr_a_i(ADDR_WIDTH_G - 1 downto 2)) & unsigned(lane_sel);

end architecture rtl;
