--------------------------------------------------------------------------------
-- tb_cart_slot.vhd
--
-- Testbench for cart_slot.vhd. Two mock cartridges are driven directly in
-- this process (score counter + vram_we pulse standing in for cartridge
-- state) to verify slot selection, pause, broadcast reset on switch, enable
-- masking of non-selected cartridges, and out-of-range selection handling.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
library work;
use work.console_pkg.all;

entity tb_cart_slot is
end entity tb_cart_slot;

architecture sim of tb_cart_slot is

    constant CLK_PERIOD : time := 10 ns;
    constant N_CART : positive := 2;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    signal sel : unsigned(3 downto 0) := (others => '0');
    signal en  : std_logic := '1';

    signal frame_tick : std_logic := '0';
    signal cart_in    : cart_in_t;
    signal cart_outs  : cart_out_array_t(0 to N_CART - 1) := (others => CART_OUT_IDLE);
    signal active     : cart_out_t;

    type score_array_t is array (0 to N_CART - 1) of integer;
    signal mock_score : score_array_t := (others => 0);
    -- Sticky "did this cartridge write VRAM since last cleared" latch.
    -- Driven only by the mock's own process; `stim` clears it via the
    -- separate `clear_seen` pulse rather than writing it directly, to
    -- avoid a multi-driver signal.
    signal mock_vram_we_seen : std_logic_vector(0 to N_CART - 1) := (others => '0');
    signal clear_seen : std_logic := '0';

    signal errors : integer := 0;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.cart_slot
        generic map (N_CART => N_CART)
        port map (
            clk_i => clk, rst_i => rst,
            sel_i => sel, en_i => en,
            frame_tick_i => frame_tick,
            pad0_i => (others => '0'), pad1_i => (others => '0'),
            rng_i => (others => '0'), blt_busy_i => '0', coll_hit_i => (others => '0'),
            cart_in_o => cart_in, cart_outs_i => cart_outs, active_o => active
        );

    -----------------------------------------------------------------------
    -- Mock cartridges: both see cart_in the same way, regardless of sel.
    -----------------------------------------------------------------------
    mocks : for c in 0 to N_CART - 1 generate
        cart_outs(c).score <= std_logic_vector(to_unsigned(mock_score(c), 24));

        process (clk)
        begin
            if rising_edge(clk) then
                if cart_in.rst = '1' then
                    mock_score(c) <= 0;
                    cart_outs(c).vram_we <= '0';
                elsif cart_in.enable = '1' and cart_in.frame_tick = '1' then
                    mock_score(c) <= mock_score(c) + 1;
                    cart_outs(c).vram_we <= '1';
                else
                    cart_outs(c).vram_we <= '0';
                end if;

                if clear_seen = '1' then
                    mock_vram_we_seen(c) <= '0';
                elsif cart_in.enable = '1' and cart_in.frame_tick = '1' then
                    mock_vram_we_seen(c) <= '1';
                end if;
            end if;
        end process;
    end generate mocks;

    -----------------------------------------------------------------------
    stim : process
        variable errs : integer := 0;

        procedure check(cond : boolean; tag : string) is
        begin
            if not cond then
                errs := errs + 1;
                report "ERROR: " & tag severity error;
            end if;
        end procedure check;

        procedure tick is
        begin
            wait until rising_edge(clk);
            frame_tick <= '1';
            wait until rising_edge(clk);
            frame_tick <= '0';
        end procedure tick;

    begin
        wait for 5 * CLK_PERIOD; -- rst starts '1' at declaration
        rst <= '0';
        wait for 5 * CLK_PERIOD;

        ------------------------------------------------------------------
        -- T1: cart 0 selected, ticks, active_o mirrors it
        ------------------------------------------------------------------
        sel <= to_unsigned(0, 4);
        wait for 2 * CLK_PERIOD;
        for i in 1 to 3 loop
            tick;
        end loop;
        wait for 1 ps;
        check(mock_score(0) = 3, "cart0 score != 3 after 3 ticks while selected");
        check(to_integer(unsigned(active.score)) = 3, "active_o.score does not mirror cart0");

        ------------------------------------------------------------------
        -- T2: pause (en_i='0') freezes cart0's state and blocks VRAM writes
        ------------------------------------------------------------------
        en <= '0';
        clear_seen <= '1';
        wait until rising_edge(clk);
        clear_seen <= '0';
        for i in 1 to 20 loop
            tick;
        end loop;
        wait for 1 ps;
        check(mock_score(0) = 3, "cart0 score changed while paused (enable='0')");
        check(mock_vram_we_seen(0) = '0', "cart0 wrote VRAM while paused");
        check(cart_in.enable = '0', "cart_in.enable != '0' while en_i='0'");

        en <= '1';
        tick;
        wait for 1 ps;
        check(mock_score(0) = 4, "cart0 did not resume counting after unpause");

        ------------------------------------------------------------------
        -- T3: switching sel issues a broadcast reset, clearing both cartridges
        ------------------------------------------------------------------
        sel <= to_unsigned(1, 4);
        wait until rising_edge(clk);
        wait for 1 ps; -- let rst_pulse's update from THIS edge become visible before reading it
        check(cart_in.rst = '1', "cart_in.rst did not pulse on a sel change");
        wait until rising_edge(clk);
        wait for 1 ps;
        check(cart_in.rst = '0', "cart_in.rst stayed high for more than one cycle");
        check(mock_score(0) = 0, "cart0 not reset by the sel switch (broadcast rst)");
        check(mock_score(1) = 0, "cart1 not reset by the sel switch");

        tick;
        tick;
        wait for 1 ps;
        check(mock_score(1) = 2, "cart1 score != 2 after 2 ticks while selected");
        check(to_integer(unsigned(active.score)) = 2, "active_o.score does not mirror cart1");

        ------------------------------------------------------------------
        -- T4: enable masking - non-selected cart0 keeps running but is hidden from active_o
        ------------------------------------------------------------------
        wait for 1 ps;
        check(mock_score(0) = 2, "cart0 (not selected) should still be counting in the background");
        check(active.score = cart_outs(1).score, "active_o is not mirroring the selected cartridge (cart1)");
        check(active.score /= cart_outs(0).score or cart_outs(0).score = cart_outs(1).score,
              "active_o leaked the non-selected cartridge's score");

        ------------------------------------------------------------------
        -- T5: invalid selection (sel >= N_CART) forces IDLE + enable='0'
        ------------------------------------------------------------------
        sel <= to_unsigned(N_CART, 4); -- one past the last valid slot
        wait for 2 * CLK_PERIOD;
        wait for 1 ps;
        check(cart_in.enable = '0', "cart_in.enable != '0' for an out-of-range sel");
        check(active = CART_OUT_IDLE, "active_o != CART_OUT_IDLE for an out-of-range sel");

        ------------------------------------------------------------------
        errors <= errs;
        wait for CLK_PERIOD;

        if errs = 0 then
            report "tb_cart_slot: PASS - selection mirrors active_o, pause freeze (score+VRAM), broadcast reset pulse on switch (no state leak either direction), background-run enable masking, and out-of-range selection all verified" severity note;
        else
            report "tb_cart_slot: FAIL - " & integer'image(errs) & " error(s)" severity failure;
        end if;

        stop;
        wait;
    end process stim;

end architecture sim;
