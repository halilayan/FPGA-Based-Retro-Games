--------------------------------------------------------------------------------
-- tb_sync_2ff.vhd
--
-- Self-checking testbench for sync_2ff.vhd.
-- Behavioral sim can't observe real metastability, so this checks only
-- functional correctness: INIT value at start, and a fixed 2-cycle
-- latency for both edge-aligned and edge-unaligned input transitions.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_sync_2ff is
end entity tb_sync_2ff;

architecture sim of tb_sync_2ff is

    constant CLK_PERIOD : time      := 10 ns;
    constant TEST_INIT   : std_logic := '1';

    signal clk_i  : std_logic := '0';
    signal din_i  : std_logic := '0';
    signal dout_o : std_logic;

    signal sim_done : boolean := false;

begin

    ----------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------
    dut : entity work.sync_2ff
        generic map (
            INIT => TEST_INIT
        )
        port map (
            clk_i  => clk_i,
            din_i  => din_i,
            dout_o => dout_o
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
        variable errors  : natural   := 0;
        variable old_val : std_logic;
        variable new_val : std_logic;
    begin
        ------------------------------------------------------------------
        -- Test 1: before the first clock edge, dout_o must equal INIT
        ------------------------------------------------------------------
        wait for 1 ns;
        if dout_o /= TEST_INIT then
            report "tb_sync_2ff: FAIL - baslangicta dout_o INIT degerine esit degil"
                severity error;
            errors := errors + 1;
        end if;

        -- Let a few cycles pass with din_i='0' held, so s1/s2 fully settle
        -- to '0' (INIT effect fully clears).
        wait for CLK_PERIOD * 3;

        ------------------------------------------------------------------
        -- Test 2: edge-aligned transition -> must appear exactly 2 cycles later
        ------------------------------------------------------------------
        old_val := dout_o;
        new_val := '1';

        wait until rising_edge(clk_i);
        wait for 1 ns;              -- just after the edge
        din_i <= new_val;

        wait until rising_edge(clk_i);   -- 1st edge (1 cycle after transition)
        wait for 1 ns;
        if dout_o /= old_val then
            report "tb_sync_2ff: FAIL - hizali gecisten 1 cevrim sonra dout_o erken degisti"
                severity error;
            errors := errors + 1;
        end if;

        wait until rising_edge(clk_i);   -- 2nd edge (2 cycles after transition)
        wait for 1 ns;
        if dout_o /= new_val then
            report "tb_sync_2ff: FAIL - hizali gecisten 2 cevrim sonra dout_o din_i'yi izlemedi"
                severity error;
            errors := errors + 1;
        end if;

        wait for CLK_PERIOD * 3;

        ------------------------------------------------------------------
        -- Test 3: edge-unaligned (mid-cycle) transition -> still exactly
        -- 2 cycles after the next valid edges
        ------------------------------------------------------------------
        old_val := dout_o;
        new_val := '0';

        wait until rising_edge(clk_i);
        wait for CLK_PERIOD / 2;    -- mid-cycle, not edge-aligned
        din_i <= new_val;

        wait until rising_edge(clk_i);   -- 1st edge after transition
        wait for 1 ns;
        if dout_o /= old_val then
            report "tb_sync_2ff: FAIL - hizasiz gecisten 1 cevrim sonra dout_o erken degisti"
                severity error;
            errors := errors + 1;
        end if;

        wait until rising_edge(clk_i);   -- 2nd edge after transition
        wait for 1 ns;
        if dout_o /= new_val then
            report "tb_sync_2ff: FAIL - hizasiz gecisten 2 cevrim sonra dout_o din_i'yi izlemedi"
                severity error;
            errors := errors + 1;
        end if;

        wait for CLK_PERIOD * 3;

        if errors = 0 then
            report "tb_sync_2ff: PASS - INIT degeri ve 2 cevrimlik gecikme (hizali ve hizasiz gecislerde) dogrulandi"
                severity note;
        else
            report "tb_sync_2ff: FAIL - " & integer'image(errors) & " hata bulundu"
                severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
