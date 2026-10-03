--------------------------------------------------------------------------------
-- asset_rom.vhd
--
-- Dedicated sprite/asset storage for the blitter's BLIT source reads, kept
-- separate from fb_ram.vhd so a blitter source read never contends with
-- fb_ram's CPU/blitter-destination/cartridge write arbitration on Port A.
--
-- True dual-port (same structure as fb_ram.vhd, for reliable Block RAM
-- inference):
--   Port A: CPU read/write via axi_bram_byte_adapter.vhd, memory-mapped
--           at ASSET_BASE.
--   Port B: read-only, wired directly to blitter.vhd's src_addr/src_data.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity asset_rom is
    generic (
        SIZE_BYTES : positive := 16384 -- 16 KiB; ADDR_BITS below must match (log2(SIZE_BYTES))
    );
    port (
        -- Port A: CPU write/read (via axi_bram_byte_adapter.vhd, same as fb_ram.vhd's Port A)
        clk_a_i  : in  std_logic;
        we_a_i   : in  std_logic;
        addr_a_i : in  unsigned(13 downto 0);
        din_a_i  : in  std_logic_vector(7 downto 0);
        dout_a_o : out std_logic_vector(7 downto 0);

        -- Port B: blitter's dedicated read-only source port
        clk_b_i  : in  std_logic;
        addr_b_i : in  unsigned(13 downto 0);
        dout_b_o : out std_logic_vector(7 downto 0)
    );
end entity asset_rom;

architecture rtl of asset_rom is

    type rom_t is array (0 to SIZE_BYTES - 1) of std_logic_vector(7 downto 0);

    signal mem : rom_t := (others => (others => '0'));

begin

    port_a_proc : process (clk_a_i)
    begin
        if rising_edge(clk_a_i) then
            if we_a_i = '1' then
                mem(to_integer(addr_a_i)) <= din_a_i;
            end if;
            dout_a_o <= mem(to_integer(addr_a_i));
        end if;
    end process port_a_proc;

    port_b_proc : process (clk_b_i)
    begin
        if rising_edge(clk_b_i) then
            dout_b_o <= mem(to_integer(addr_b_i));
        end if;
    end process port_b_proc;

end architecture rtl;
