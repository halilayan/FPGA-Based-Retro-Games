--------------------------------------------------------------------------------
-- cart_slot.vhd
--
-- Arbitrates N_CART cartridges down to one active cart_out_t and builds
-- the shared cart_in_t bus broadcast to every cartridge.
--
-- Guarantees: a non-selected cartridge's output is never muxed to
-- active_o; cart_in_o.rst pulses for one cycle whenever sel_i selects a
-- new valid slot (so a newly-selected cartridge always starts from reset,
-- with no state leaking from the previous one); en_i='0' forces
-- cart_in_o.enable='0' to freeze every cartridge for pause.
--
-- sel_i >= N_CART means "no cartridge selected" (active_o = CART_OUT_IDLE,
-- enable forced '0'), not a wrapped/aliased index.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.console_pkg.all;

entity cart_slot is
    generic (
        N_CART : positive := 4
    );
    port (
        clk_i : in std_logic;
        rst_i : in std_logic;

        sel_i : in unsigned(3 downto 0);
        en_i  : in std_logic; -- system-level enable; pause drives this '0'

        -- Broadcast straight into cart_in_o for every cartridge.
        frame_tick_i : in std_logic;
        pad0_i       : in std_logic_vector(15 downto 0);
        pad1_i       : in std_logic_vector(15 downto 0);
        rng_i        : in std_logic_vector(31 downto 0);
        blt_busy_i   : in std_logic;
        coll_hit_i   : in std_logic_vector(63 downto 0);

        cart_in_o   : out cart_in_t;
        cart_outs_i : in  cart_out_array_t(0 to N_CART - 1);
        active_o    : out cart_out_t
    );
end entity cart_slot;

architecture rtl of cart_slot is

    signal sel_prev  : unsigned(3 downto 0);
    signal rst_pulse : std_logic;

begin

    -----------------------------------------------------------------------
    -- One-cycle reset pulse whenever sel_i changes to a new value (also
    -- held while rst_i is asserted, so a global reset always resets
    -- whichever cartridge ends up selected).
    -----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                sel_prev  <= sel_i;
                rst_pulse <= '1';
            else
                rst_pulse <= '0';
                if sel_i /= sel_prev then
                    rst_pulse <= '1';
                end if;
                sel_prev <= sel_i;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- cart_in_t: common bus broadcast to every cartridge.
    -----------------------------------------------------------------------
    cart_in_o.clk        <= clk_i;
    cart_in_o.rst        <= rst_i or rst_pulse;
    -- Computed directly from sel_i here (not via an intermediate signal)
    -- to avoid a reconvergent-path hazard: relaying through a signal let
    -- this process and the mux below briefly disagree on sel_i's value,
    -- which once caused an out-of-bounds cart_outs_i index.
    cart_in_o.enable     <= en_i when to_integer(sel_i) < N_CART else '0';
    cart_in_o.frame_tick <= frame_tick_i;
    cart_in_o.pad0       <= pad0_i;
    cart_in_o.pad1       <= pad1_i;
    cart_in_o.rng        <= rng_i;
    cart_in_o.blt_busy   <= blt_busy_i;
    cart_in_o.coll_hit   <= coll_hit_i;

    -----------------------------------------------------------------------
    -- Mux the selected cartridge's output; an invalid/no selection (or
    -- reset) yields CART_OUT_IDLE, never a stray/uninitialised cart_out_t.
    -----------------------------------------------------------------------
    process (sel_i, cart_outs_i)
    begin
        if to_integer(sel_i) < N_CART then
            active_o <= cart_outs_i(to_integer(sel_i));
        else
            active_o <= CART_OUT_IDLE;
        end if;
    end process;

end architecture rtl;
