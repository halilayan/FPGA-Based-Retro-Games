--------------------------------------------------------------------------------
-- console_pkg.vhd
--
-- Shared record types for the cartridge interface: cart_in_t (system ->
-- cartridge, the same bus broadcast to every cartridge, see cart_slot.vhd)
-- and cart_out_t (cartridge -> system: VRAM write, blitter command,
-- scroll/sound/score), muxed down to one active cart_out_t by cart_slot.vhd
-- based on the selected slot.
--
-- VHDL-2008: safe here since only the top entity used by Vivado's "Add
-- Module" flow must stay VHDL-93; this package is only ever used via
-- `use work.console_pkg.all;` inside cart_slot.vhd.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package console_pkg is

    -- System -> cartridge (broadcast: every cartridge sees the same bus).
    type cart_in_t is record
        clk        : std_logic;                      -- clk_sys (100 MHz)
        rst        : std_logic;                      -- pulsed when this cartridge is (re)selected
        enable     : std_logic;                      -- '1' = allowed to run (pause -> '0')
        frame_tick : std_logic;                      -- VBLANK start, 1 cycle
        pad0       : std_logic_vector(15 downto 0);  -- player 1
        pad1       : std_logic_vector(15 downto 0);  -- player 2
        rng        : std_logic_vector(31 downto 0);  -- free-running LFSR
        blt_busy   : std_logic;                      -- blitter busy
        coll_hit   : std_logic_vector(63 downto 0);  -- collision results
    end record cart_in_t;

    -- Cartridge -> system.
    type cart_out_t is record
        -- direct VRAM write
        vram_we   : std_logic;
        vram_addr : std_logic_vector(16 downto 0);
        vram_din  : std_logic_vector(7 downto 0);
        -- blitter command (SAME register layout as libconsole's)
        blt_start : std_logic;
        blt_op    : std_logic_vector(1 downto 0);
        blt_x     : std_logic_vector(9 downto 0);
        blt_y     : std_logic_vector(9 downto 0);
        blt_w     : std_logic_vector(9 downto 0);
        blt_h     : std_logic_vector(9 downto 0);
        blt_src   : std_logic_vector(16 downto 0);
        blt_color : std_logic_vector(7 downto 0);
        blt_key   : std_logic_vector(7 downto 0);
        -- layer control
        scroll_x  : std_logic_vector(9 downto 0);
        scroll_y  : std_logic_vector(9 downto 0);
        -- sound
        snd_trig  : std_logic;
        snd_id    : std_logic_vector(7 downto 0);
        -- feedback to the system
        done      : std_logic;                       -- game over
        score     : std_logic_vector(23 downto 0);
    end record cart_out_t;

    -- Valid only in a record aggregate, since every unlisted field shares
    -- the same type (std_logic/std_logic_vector). NOT usable in a port map.
    constant CART_OUT_IDLE : cart_out_t := (
        vram_we => '0', blt_start => '0', snd_trig => '0', done => '0',
        others  => (others => '0'));

    type cart_out_array_t is array (natural range <>) of cart_out_t;

end package console_pkg;
