--------------------------------------------------------------------------------
-- palette_init.vhd
--
-- Temporary RTL palette initializer. palette_lut otherwise defaults to
-- all-black, so framebuffer indices would be invisible on screen. This
-- module writes a 256-entry greyscale ramp after reset (index's top 4
-- bits repeated into R=G=B, 16 grey levels) so written indices are
-- visually distinguishable until a real color palette is loaded.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity palette_init is
    port (
        clk_i : in std_logic;
        rst_i : in std_logic;

        wr_en_o  : out std_logic;
        wr_idx_o : out unsigned(7 downto 0);
        wr_rgb_o : out std_logic_vector(11 downto 0)
    );
end entity palette_init;

architecture rtl of palette_init is

    -- 9 bits so the counter can reach 256 (one past the last valid index) to stop
    signal idx : unsigned(8 downto 0) := (others => '0');

begin

    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                idx <= (others => '0');
            elsif idx < 256 then
                idx <= idx + 1;
            end if;
        end if;
    end process;

    wr_en_o  <= '1' when idx < 256 else '0';
    wr_idx_o <= idx(7 downto 0);

    -- Greyscale: top 4 bits repeated into R/G/B (16 levels)
    wr_rgb_o <= std_logic_vector(idx(7 downto 4)) &
                std_logic_vector(idx(7 downto 4)) &
                std_logic_vector(idx(7 downto 4));

end architecture rtl;
