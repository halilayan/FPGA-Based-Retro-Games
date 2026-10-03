--------------------------------------------------------------------------------
-- blink.vhd
--
-- Blinks all 16 LEDs in sync at BLINK_HZ, using a counter derived from
-- clk_i. Used as a basic sanity check for the synthesis/bitstream flow.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blink is
    generic (
        CLK_HZ   : positive := 100_000_000;  -- Basys3 onboard oscillator (W5)
        BLINK_HZ : positive := 1             -- blink frequency in Hz
    );
    port (
        clk_i : in  std_logic;                 -- system clock
        rst_i : in  std_logic;                 -- synchronous reset, active-high (BTNC)
        led_o : out std_logic_vector(15 downto 0)
    );
end entity blink;

architecture rtl of blink is

    -- cycle count per half-period (LED toggles once per half-period)
    constant HALF_PERIOD_CYCLES : positive := CLK_HZ / (2 * BLINK_HZ);

    signal count       : unsigned(31 downto 0) := (others => '0');
    signal blink_state : std_logic := '0';

begin

    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                count       <= (others => '0');
                blink_state <= '0';
            elsif count = HALF_PERIOD_CYCLES - 1 then
                count       <= (others => '0');
                blink_state <= not blink_state;
            else
                count <= count + 1;
            end if;
        end if;
    end process;

    led_o <= (others => blink_state);

end architecture rtl;
