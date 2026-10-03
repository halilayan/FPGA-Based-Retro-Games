--------------------------------------------------------------------------------
-- debounce.vhd
--
-- General-purpose single-bit debouncer for mechanical switches/buttons
-- (Basys3 push-buttons, slide switches). The PS/2 receiver does its own
-- synchronization and does NOT use this module.
--
-- d_i is sampled each cycle; any change resets the stability counter and
-- tracks the new sample. Once the input has held steady for STABLE_CYCLES
-- cycles (derived from STABLE_TIME_US), d_o is updated.
--
-- NOTE: CLK_HZ must be a multiple of 1_000_000 (true for typical FPGA
-- system clocks). Otherwise STABLE_CYCLES can elaborate to 0, which
-- intentionally fails the generic's POSITIVE constraint rather than
-- silently synthesizing with a zero threshold.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debounce is
    generic (
        CLK_HZ         : positive := 100_000_000;  -- system clock (must be a multiple of 1_000_000)
        STABLE_TIME_US : positive := 5000          -- required stable time, in microseconds
    );
    port (
        clk_i : in  std_logic;
        rst_i : in  std_logic;   -- synchronous reset, active-high
        d_i   : in  std_logic;   -- raw (bouncy) input
        d_o   : out std_logic    -- debounced output
    );
end entity debounce;

architecture rtl of debounce is

    -- cycle count corresponding to STABLE_TIME_US
    constant STABLE_CYCLES : positive := (CLK_HZ / 1_000_000) * STABLE_TIME_US;

    signal d_prev : std_logic := '0';  -- most recent sample (candidate stable value)
    signal d_reg  : std_logic := '0';  -- registered (debounced) output
    signal cnt    : natural range 0 to STABLE_CYCLES - 1 := 0;

begin

    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                d_prev <= '0';
                d_reg  <= '0';
                cnt    <= 0;
            elsif d_i /= d_prev then
                -- input changed: possible bounce, restart the stability count
                d_prev <= d_i;
                cnt    <= 0;
            elsif cnt = STABLE_CYCLES - 1 then
                -- threshold reached: input has been stable for STABLE_CYCLES cycles
                d_reg <= d_prev;
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;

    d_o <= d_reg;

end architecture rtl;
