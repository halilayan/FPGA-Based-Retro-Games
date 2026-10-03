--------------------------------------------------------------------------------
-- fb_arbiter.vhd
--
-- Fixed-priority combinational multiplexer for fb_ram.vhd's single write
-- port (Port A), arbitrating between three possible writers: blitter,
-- cartridge, and CPU.
--
-- Priority order (fixed, not round-robin): blitter > cartridge > CPU.
--
-- fb_we_o='0' when no writer is active (addr/din don't-care). Fully
-- combinational (no clock/reset), same style as fb_reader.vhd.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fb_arbiter is
    port (
        -- CPU write port (via AXI BRAM Controller)
        cpu_we_i   : in  std_logic;
        cpu_addr_i : in  unsigned(16 downto 0);
        cpu_din_i  : in  std_logic_vector(7 downto 0);

        -- Blitter write port
        blt_we_i   : in  std_logic;
        blt_addr_i : in  unsigned(16 downto 0);
        blt_din_i  : in  std_logic_vector(7 downto 0);

        -- Cartridge write port
        cart_we_i   : in  std_logic;
        cart_addr_i : in  unsigned(16 downto 0);
        cart_din_i  : in  std_logic_vector(7 downto 0);

        -- Single arbitrated output to fb_ram Port A
        fb_we_o   : out std_logic;
        fb_addr_o : out unsigned(16 downto 0);
        fb_din_o  : out std_logic_vector(7 downto 0)
    );
end entity fb_arbiter;

architecture rtl of fb_arbiter is
begin

    arb_proc : process (cpu_we_i, cpu_addr_i, cpu_din_i,
                         blt_we_i, blt_addr_i, blt_din_i,
                         cart_we_i, cart_addr_i, cart_din_i)
    begin
        if blt_we_i = '1' then
            fb_we_o   <= '1';
            fb_addr_o <= blt_addr_i;
            fb_din_o  <= blt_din_i;
        elsif cart_we_i = '1' then
            fb_we_o   <= '1';
            fb_addr_o <= cart_addr_i;
            fb_din_o  <= cart_din_i;
        elsif cpu_we_i = '1' then
            fb_we_o   <= '1';
            fb_addr_o <= cpu_addr_i;
            fb_din_o  <= cpu_din_i;
        else
            fb_we_o   <= '0';
            fb_addr_o <= (others => '0');
            fb_din_o  <= (others => '0');
        end if;
    end process arb_proc;

end architecture rtl;
