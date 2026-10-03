--------------------------------------------------------------------------------
-- fb_ram.vhd
--
-- Frame buffer memory: 320x240, 8 bits/pixel (palette index), 76,800 bytes
-- total. True dual-port BRAM: port A is written by the game logic, port B
-- is continuously read by video_out.vhd (fb_addr_o -> addr_b_i, dout_b_o
-- -> fb_dout_i). Port B is read-only; video never writes to it.
--
-- Both ports read synchronously (registered, 1-cycle latency): this is
-- the only pattern Vivado will infer as a true Block RAM instead of
-- distributed RAM. At 76,800 bytes, distributed RAM would not fit on the
-- XC7A35T, so there is no async/combinational read path here, and each
-- port is handled in its own process on its own clock.
--
-- Port A's registered read (dout_a_o) is unused for now (Pong only
-- writes) but kept for future CPU/blitter use; read-during-write-to-same-
-- address behaviour is left undefined.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fb_ram is
    generic (
        FB_W : positive := 320;
        FB_H : positive := 240
    );
    port (
        -- Port A: write side (game logic / future CPU)
        clk_a_i  : in  std_logic;
        we_a_i   : in  std_logic;
        addr_a_i : in  unsigned(16 downto 0);
        din_a_i  : in  std_logic_vector(7 downto 0);
        dout_a_o : out std_logic_vector(7 downto 0);

        -- Port B: read side (matches video_out.fb_addr_o / fb_dout_i)
        clk_b_i  : in  std_logic;
        addr_b_i : in  unsigned(16 downto 0);
        dout_b_o : out std_logic_vector(7 downto 0)
    );
end entity fb_ram;

architecture rtl of fb_ram is

    constant DEPTH : positive := FB_W * FB_H;

    type ram_t is array (0 to DEPTH - 1) of std_logic_vector(7 downto 0);

    signal ram : ram_t := (others => (others => '0'));

begin

    ----------------------------------------------------------------------
    -- Port A: write + registered read (clk_a_i domain)
    ----------------------------------------------------------------------
    port_a_proc : process (clk_a_i)
    begin
        if rising_edge(clk_a_i) then
            if we_a_i = '1' then
                ram(to_integer(addr_a_i)) <= din_a_i;
            end if;
            dout_a_o <= ram(to_integer(addr_a_i));
        end if;
    end process port_a_proc;

    ----------------------------------------------------------------------
    -- Port B: read-only (clk_b_i domain) - matches video_out
    ----------------------------------------------------------------------
    port_b_proc : process (clk_b_i)
    begin
        if rising_edge(clk_b_i) then
            dout_b_o <= ram(to_integer(addr_b_i));
        end if;
    end process port_b_proc;

end architecture rtl;
