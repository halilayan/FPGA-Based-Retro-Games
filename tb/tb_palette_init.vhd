--------------------------------------------------------------------------------
-- tb_palette_init.vhd
--
-- Testbench for palette_init.vhd: verifies all 256 writes occur in the
-- correct order/value, then that wr_en_o stays deasserted permanently.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_palette_init is
end entity tb_palette_init;

architecture sim of tb_palette_init is

    constant CLK_PERIOD : time := 10 ns;

    signal clk_i    : std_logic := '0';
    signal rst_i    : std_logic := '1';
    signal wr_en_o  : std_logic;
    signal wr_idx_o : unsigned(7 downto 0);
    signal wr_rgb_o : std_logic_vector(11 downto 0);

    signal sim_done : boolean := false;

begin

    dut : entity work.palette_init
        port map (
            clk_i    => clk_i,
            rst_i    => rst_i,
            wr_en_o  => wr_en_o,
            wr_idx_o => wr_idx_o,
            wr_rgb_o => wr_rgb_o
        );

    clk_gen : process
    begin
        while not sim_done loop
            clk_i <= '0'; wait for CLK_PERIOD / 2;
            clk_i <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_gen;

    stimulus : process
        variable errors : natural := 0;
        variable expected_gray : std_logic_vector(3 downto 0);
        variable expected_rgb  : std_logic_vector(11 downto 0);
    begin
        rst_i <= '1';
        wait for CLK_PERIOD * 3;
        rst_i <= '0';
        wait for 1 ns;  -- let reset deassertion settle - idx=0, no edge has passed yet

        -- NOTE: wr_idx_o=k is valid from edge k until edge k+1, so checking
        -- must happen before advancing to the next edge (else off-by-one)
        for i in 0 to 255 loop
            if wr_en_o /= '1' then
                report "tb_palette_init: FAIL - i=" & integer'image(i) &
                       " icin wr_en_o='1' degil" severity error;
                errors := errors + 1;
            end if;

            if to_integer(wr_idx_o) /= i then
                report "tb_palette_init: FAIL - i=" & integer'image(i) &
                       " beklenen wr_idx_o=" & integer'image(i) &
                       " gozlenen=" & integer'image(to_integer(wr_idx_o))
                    severity error;
                errors := errors + 1;
            end if;

            expected_gray := std_logic_vector(to_unsigned(i, 8)(7 downto 4));
            expected_rgb  := expected_gray & expected_gray & expected_gray;
            if wr_rgb_o /= expected_rgb then
                report "tb_palette_init: FAIL - i=" & integer'image(i) &
                       " rgb yanlis" severity error;
                errors := errors + 1;
            end if;

            -- advance only after checking
            wait until rising_edge(clk_i);
            wait for 1 ns;
        end loop;

        -- wr_en_o must stay low after all 256 writes
        for k in 1 to 5 loop
            wait until rising_edge(clk_i);
            wait for 1 ns;
            if wr_en_o /= '0' then
                report "tb_palette_init: FAIL - 256 yazmadan sonra wr_en_o hala '1'"
                    severity error;
                errors := errors + 1;
            end if;
        end loop;

        if errors = 0 then
            report "tb_palette_init: PASS - 256 yazmanin tamami (idx+rgb) ve sonraki durma dogrulandi"
                severity note;
        else
            report "tb_palette_init: FAIL - " & integer'image(errors) & " hata bulundu" severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
