--------------------------------------------------------------------------------
-- tb_debounce.vhd
--
-- Self-checking testbench for debounce.vhd. Uses small test generics
-- (CLK_HZ=1_000_000, STABLE_TIME_US=20) to keep simulation short.
-- DUT's output updates STABLE_CYCLES+1 cycles after an input change, so
-- each test checks the output is still old at +STABLE_CYCLES, then new
-- one cycle later. Covers clean transitions, bounce, and reset.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_debounce is
end entity tb_debounce;

architecture sim of tb_debounce is

    constant CLK_PERIOD : time := 10 ns;

    -- Small test generics to keep simulation short
    constant TEST_CLK_HZ         : positive := 1_000_000;
    constant TEST_STABLE_TIME_US : positive := 20;
    constant STABLE_CYCLES       : positive := (TEST_CLK_HZ / 1_000_000) * TEST_STABLE_TIME_US;

    signal clk_i : std_logic := '0';
    signal rst_i : std_logic := '1';
    signal d_i   : std_logic := '0';
    signal d_o   : std_logic;

    signal sim_done : boolean := false;

begin

    ----------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------
    dut : entity work.debounce
        generic map (
            CLK_HZ         => TEST_CLK_HZ,
            STABLE_TIME_US => TEST_STABLE_TIME_US
        )
        port map (
            clk_i => clk_i,
            rst_i => rst_i,
            d_i   => d_i,
            d_o   => d_o
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
    -- Stimulus + self-checking observer
    ----------------------------------------------------------------------
    stimulus : process
        variable errors : natural := 0;

        procedure wait_cycles (n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk_i);
            end loop;
            -- Small delay so the DUT's synchronous update settles; otherwise
            -- d_o could be read in the same delta as the edge and show the
            -- previous value (edge/read race).
            wait for 1 ns;
        end procedure wait_cycles;

    begin
        ------------------------------------------------------------------
        -- Initial state: input held at '1', reset active (also sets up Test 3)
        ------------------------------------------------------------------
        d_i   <= '1';
        rst_i <= '1';
        wait_cycles(3);

        -- Test 4a: d_o must be '0' while reset is active, regardless of d_i
        if d_o /= '0' then
            report "tb_debounce: FAIL - reset aktifken d_o '0' degil" severity error;
            errors := errors + 1;
        end if;

        ------------------------------------------------------------------
        -- Test 3: input stable through reset; output still only updates
        -- after the threshold, not immediately
        ------------------------------------------------------------------
        rst_i <= '0';

        wait_cycles(STABLE_CYCLES);
        if d_o /= '0' then
            report "tb_debounce: FAIL - Test3: esik dolmadan d_o erken degisti" severity error;
            errors := errors + 1;
        end if;

        wait_cycles(1);
        if d_o /= '1' then
            report "tb_debounce: FAIL - Test3: esik doldu ama d_o '1' olmadi" severity error;
            errors := errors + 1;
        end if;

        ------------------------------------------------------------------
        -- Test 1: clean (bounce-free) single transition, '1' -> '0'
        ------------------------------------------------------------------
        d_i <= '0';

        wait_cycles(STABLE_CYCLES);
        if d_o /= '1' then
            report "tb_debounce: FAIL - Test1: esik dolmadan d_o erken degisti" severity error;
            errors := errors + 1;
        end if;

        wait_cycles(1);
        if d_o /= '0' then
            report "tb_debounce: FAIL - Test1: esik doldu ama d_o '0' olmadi" severity error;
            errors := errors + 1;
        end if;

        ------------------------------------------------------------------
        -- Test 2: bounce - several spurious transitions faster than the
        -- threshold, settling at '1'; output must only follow the final value
        ------------------------------------------------------------------
        d_i <= '1'; wait_cycles(2);
        d_i <= '0'; wait_cycles(2);
        d_i <= '1'; wait_cycles(2);
        d_i <= '0'; wait_cycles(2);
        d_i <= '1';  -- final (stable) value

        if d_o /= '0' then
            report "tb_debounce: FAIL - Test2: sicrama sirasinda d_o degisti" severity error;
            errors := errors + 1;
        end if;

        wait_cycles(STABLE_CYCLES);
        if d_o /= '0' then
            report "tb_debounce: FAIL - Test2: son gecisten sonra esik dolmadan d_o erken degisti"
                severity error;
            errors := errors + 1;
        end if;

        wait_cycles(1);
        if d_o /= '1' then
            report "tb_debounce: FAIL - Test2: esik doldu ama d_o nihai degere ('1') gecmedi"
                severity error;
            errors := errors + 1;
        end if;

        ------------------------------------------------------------------
        -- Test 4b: reset applied mid-run must force d_o to '0' synchronously
        -- (even with d_i='1')
        ------------------------------------------------------------------
        rst_i <= '1';
        wait_cycles(1);
        if d_o /= '0' then
            report "tb_debounce: FAIL - Test4: calisirken reset uygulaninca d_o '0' olmadi"
                severity error;
            errors := errors + 1;
        end if;
        rst_i <= '0';

        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_debounce: PASS - temiz gecis, sicrama reddi, reset-sonrasi sabit giris " &
                   "ve reset davranisi dogrulandi" severity note;
        else
            report "tb_debounce: FAIL - " & integer'image(errors) & " hata bulundu"
                severity failure;
        end if;

        sim_done <= true;
        wait_cycles(2);
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
