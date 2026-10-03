--------------------------------------------------------------------------------
-- sync_2ff.vhd
--
-- Two-flip-flop synchronizer: brings an asynchronous single-bit signal
-- into the clk_i clock domain with metastability protection. For
-- single-bit control signals only; multi-bit data needs a FIFO or gray
-- coding instead.
--
-- The ASYNC_REG attribute tells Vivado to place s1/s2 appropriately and
-- relax timing analysis between them; required for metastability MTBF.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sync_2ff is
    generic (
        INIT : std_logic := '0'
    );
    port (
        clk_i  : in  std_logic;
        din_i  : in  std_logic;
        dout_o : out std_logic
    );
end entity sync_2ff;

architecture rtl of sync_2ff is

    signal s1, s2 : std_logic := INIT;

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of s1 : signal is "TRUE";
    attribute ASYNC_REG of s2 : signal is "TRUE";

begin

    process (clk_i)
    begin
        if rising_edge(clk_i) then
            s1 <= din_i;
            s2 <= s1;
        end if;
    end process;

    dout_o <= s2;

end architecture rtl;
