--------------------------------------------------------------------------------
-- tb_collision.vhd
--
-- Golden-reference testbench for collision.vhd: loads N_OBJ objects
-- (random + hand-placed edge cases), then queries every object index and
-- checks the DUT's hit_mask against a reference AABB test computed here.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;

entity tb_collision is
end entity tb_collision;

architecture sim of tb_collision is

    constant CLK_PERIOD : time := 10 ns;
    constant N_OBJ : positive := 64;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    signal obj_we  : std_logic := '0';
    signal obj_idx : unsigned(5 downto 0) := (others => '0');
    signal obj_x   : signed(10 downto 0) := (others => '0');
    signal obj_y   : signed(10 downto 0) := (others => '0');
    signal obj_w   : unsigned(7 downto 0) := (others => '0');
    signal obj_h   : unsigned(7 downto 0) := (others => '0');
    signal obj_en  : std_logic := '0';

    signal qry_idx  : unsigned(5 downto 0) := (others => '0');
    signal hit_mask : std_logic_vector(N_OBJ - 1 downto 0);

    type i_arr_t  is array (0 to N_OBJ - 1) of integer;
    type en_arr_t is array (0 to N_OBJ - 1) of std_logic;

    signal model_x, model_y, model_w, model_h : i_arr_t;
    signal model_en : en_arr_t;

    signal errors : integer := 0;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.collision
        generic map (N_OBJ => N_OBJ)
        port map (
            clk => clk, rst => rst,
            obj_we => obj_we, obj_idx => obj_idx,
            obj_x => obj_x, obj_y => obj_y, obj_w => obj_w, obj_h => obj_h, obj_en => obj_en,
            qry_idx => qry_idx, hit_mask => hit_mask
        );

    stim : process
        variable seed1, seed2 : positive := 1;
        variable rv : real;
        variable en_v : std_logic;

        impure function rand_int(lo, hi : integer) return integer is
        begin
            uniform(seed1, seed2, rv);
            return lo + integer(floor(rv * real(hi - lo + 1)));
        end function rand_int;

        procedure load(idx, x, y, w, h : integer; en : std_logic) is
        begin
            wait until rising_edge(clk);
            obj_idx <= to_unsigned(idx, 6);
            obj_x   <= to_signed(x, 11);
            obj_y   <= to_signed(y, 11);
            obj_w   <= to_unsigned(w, 8);
            obj_h   <= to_unsigned(h, 8);
            obj_en  <= en;
            obj_we  <= '1';
            wait until rising_edge(clk);
            obj_we  <= '0';

            model_x(idx)  <= x;
            model_y(idx)  <= y;
            model_w(idx)  <= w;
            model_h(idx)  <= h;
            model_en(idx) <= en;
        end procedure load;

        function golden_overlap(ax, ay, aw, ah, bx, by, bw, bh : integer; aen, ben : std_logic) return std_logic is
        begin
            if aen = '1' and ben = '1' and
               ax < bx + bw and bx < ax + aw and
               ay < by + bh and by < ay + ah then
                return '1';
            else
                return '0';
            end if;
        end function golden_overlap;

        procedure check_query(idx : integer; tag : string) is
            variable expected : std_logic_vector(N_OBJ - 1 downto 0);
            variable local_err : integer := 0;
        begin
            qry_idx <= to_unsigned(idx, 6);
            wait until rising_edge(clk); -- present qry_idx
            wait until rising_edge(clk); -- registered hit_mask now reflects it
            wait for 1 ps;

            for i in 0 to N_OBJ - 1 loop
                if i = idx then
                    expected(i) := '0'; -- never self
                else
                    expected(i) := golden_overlap(model_x(idx), model_y(idx), model_w(idx), model_h(idx),
                                                   model_x(i), model_y(i), model_w(i), model_h(i),
                                                   model_en(idx), model_en(i));
                end if;
            end loop;

            if hit_mask /= expected then
                for i in 0 to N_OBJ - 1 loop
                    if hit_mask(i) /= expected(i) then
                        local_err := local_err + 1;
                        if local_err <= 3 then
                            report "ERROR [" & tag & "] qry=" & integer'image(idx) & " obj=" & integer'image(i) &
                                   " dut=" & std_logic'image(hit_mask(i)) & " expected=" & std_logic'image(expected(i))
                                   severity error;
                        end if;
                    end if;
                end loop;
                errors <= errors + local_err;
            end if;
        end procedure check_query;

    begin
        wait for 5 * CLK_PERIOD; -- rst starts '1' at declaration, hold it a few cycles
        rst <= '0';
        wait for 5 * CLK_PERIOD;

        ------------------------------------------------------------------
        -- T1: hand-placed edge cases (objects 0..4)
        ------------------------------------------------------------------
        load(0, 10, 10, 10, 10, '1');  -- box A: [10,20) x [10,20)
        load(1, 20, 10, 10, 10, '1');  -- touches A's right edge exactly - must NOT overlap
        load(2, 15, 15, 10, 10, '1');  -- overlaps A (partial)
        load(3, 12, 12, 4, 4, '1');    -- fully contained within A
        load(4, 100, 100, 5, 5, '0');  -- disabled, would overlap nothing anyway (far away)

        -- fill the rest with disabled, zero-size placeholders so the
        -- "golden" model has a defined value for every index
        for i in 5 to N_OBJ - 1 loop
            load(i, 0, 0, 0, 0, '0');
        end loop;

        for i in 0 to 4 loop
            check_query(i, "T1 edge cases");
        end loop;

        ------------------------------------------------------------------
        -- T2: a disabled query object must report an all-zero mask (proves
        -- the enable check, not just geometry, suppresses the hit)
        ------------------------------------------------------------------
        load(4, 10, 10, 10, 10, '0'); -- identical box to object 0, but disabled
        check_query(4, "T2 disabled query object");
        check_query(0, "T2 disabled object excluded from others' masks");

        ------------------------------------------------------------------
        -- T3: full random load + exhaustive query golden-reference check
        ------------------------------------------------------------------
        for i in 0 to N_OBJ - 1 loop
            if rand_int(0, 4) /= 0 then -- ~80% enabled
                en_v := '1';
            else
                en_v := '0';
            end if;
            load(i, rand_int(-20, 300), rand_int(-20, 220), rand_int(1, 40), rand_int(1, 40), en_v);
        end loop;

        for i in 0 to N_OBJ - 1 loop
            check_query(i, "T3 random #" & integer'image(i));
        end loop;

        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_collision: PASS - touching/overlapping/contained edge cases, disabled-query and disabled-object exclusion, and a full 64-object random load with exhaustive (all 64 queries) golden-reference AABB checks, all bit-exact" severity note;
        else
            report "tb_collision: FAIL - " & integer'image(errors) & " error(s)" severity failure;
        end if;

        wait for CLK_PERIOD;
        stop;
        wait;
    end process stim;

end architecture sim;
