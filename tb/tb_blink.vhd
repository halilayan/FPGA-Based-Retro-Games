--------------------------------------------------------------------------------
-- tb_blink.vhd
--
-- Self-checking testbench for blink.vhd. Uses small test generics
-- (CLK_HZ=100, BLINK_HZ=1) instead of the real board values so the
-- simulation stays short, and checks the observed toggle interval.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_blink is
end entity tb_blink;

architecture sim of tb_blink is

    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz sim clock

    -- Small test generics to keep simulation short
    constant TEST_CLK_HZ           : positive := 100;
    constant TEST_BLINK_HZ         : positive := 1;
    constant EXPECTED_HALF_PERIOD  : positive := TEST_CLK_HZ / (2 * TEST_BLINK_HZ);

    signal clk_i : std_logic := '0';
    signal rst_i : std_logic := '1';
    signal led_o : std_logic_vector(15 downto 0);

    signal sim_done : boolean := false;

begin

    ----------------------------------------------------------------------
    dut : entity work.blink
        generic map (
            CLK_HZ   => TEST_CLK_HZ,
            BLINK_HZ => TEST_BLINK_HZ
        )
        port map (
            clk_i => clk_i,
            rst_i => rst_i,
            led_o => led_o
        );

    ----------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------
    clk_gen : process
    begin
        while not sim_done loop
            clk_i <= '0';
            wait for CLK_PERIOD / 2;
            clk_i <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_gen;

    ----------------------------------------------------------------------
    -- Stimulus + self-checking monitor
    ----------------------------------------------------------------------
    stimulus : process
        variable toggle_count : natural := 0;
        variable cycles_since : natural := 0;
        variable last_led     : std_logic;
        variable errors       : natural := 0;
    begin
        -- Apply reset
        rst_i <= '1';
        wait for CLK_PERIOD * 5;
        wait until rising_edge(clk_i);
        rst_i <= '0';

        -- led must be '0' after reset
        wait until rising_edge(clk_i);
        if led_o(0) /= '0' then
            report "tb_blink: FAIL - reset sonrasi led_o(0) '0' degil" severity error;
            errors := errors + 1;
        end if;

        -- all bits must carry the same value
        if led_o(0) /= led_o(15) then
            report "tb_blink: FAIL - LED bitleri tutarli degil (hepsi ayni olmali)"
                severity error;
            errors := errors + 1;
        end if;

        last_led := led_o(0);

        -- verify the cycle count across a few toggles
        while toggle_count < 4 loop
            wait until rising_edge(clk_i);
            cycles_since := cycles_since + 1;

            if led_o(0) /= last_led then
                if cycles_since /= EXPECTED_HALF_PERIOD then
                    report "tb_blink: FAIL - beklenen aralik " &
                           integer'image(EXPECTED_HALF_PERIOD) & " cevrim, gozlenen " &
                           integer'image(cycles_since) & " cevrim"
                        severity error;
                    errors := errors + 1;
                end if;

                if led_o(0) /= led_o(15) then
                    report "tb_blink: FAIL - LED bitleri tutarli degil" severity error;
                    errors := errors + 1;
                end if;

                toggle_count := toggle_count + 1;
                cycles_since := 0;
                last_led := led_o(0);
            end if;
        end loop;

        if errors = 0 then
            report "tb_blink: PASS - " & integer'image(toggle_count) &
                   " toggle dogrulandi, her biri " &
                   integer'image(EXPECTED_HALF_PERIOD) & " cevrimde" severity note;
        else
            report "tb_blink: FAIL - " & integer'image(errors) & " hata bulundu"
                severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
