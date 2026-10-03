--------------------------------------------------------------------------------
-- tb_pong_core.vhd
--
-- Physics testbench for pong_core.vhd. Reset state is fully deterministic
-- (ball centered, vx=+2/vy=+1, paddles centered), so expected event ticks
-- are hand-calculated and checked directly, with no separate reference model.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_pong_core is
end entity tb_pong_core;

architecture sim of tb_pong_core is

    constant CLK_PERIOD : time := 10 ns;

    -- Scaled-down tick rate for faster simulation (physics unchanged, only cycles-per-tick changes)
    constant TEST_CLK_HZ  : positive := 1000;
    constant TEST_TICK_HZ : positive := 100;
    constant TICK_PERIOD  : positive := TEST_CLK_HZ / TEST_TICK_HZ;  -- 10 cevrim/tick

    signal clk_i : std_logic := '0';
    signal rst_i : std_logic := '1';

    signal up1_i, down1_i, up2_i, down2_i : std_logic := '0';

    signal fb_we_o   : std_logic;
    signal fb_addr_o : unsigned(16 downto 0);
    signal fb_din_o  : std_logic_vector(7 downto 0);

    signal score1_o, score2_o : unsigned(3 downto 0);

    signal ball_x_o, ball_y_o : signed(10 downto 0);
    signal ball_vx_o, ball_vy_o : signed(4 downto 0);
    signal paddle1_y_o, paddle2_y_o : signed(10 downto 0);

    signal sim_done : boolean := false;

begin

    dut : entity work.pong_core
        generic map (
            CLK_HZ  => TEST_CLK_HZ,
            TICK_HZ => TEST_TICK_HZ
        )
        port map (
            clk_i       => clk_i,
            rst_i       => rst_i,
            up1_i       => up1_i,
            down1_i     => down1_i,
            up2_i       => up2_i,
            down2_i     => down2_i,
            fb_we_o     => fb_we_o,
            fb_addr_o   => fb_addr_o,
            fb_din_o    => fb_din_o,
            score1_o    => score1_o,
            score2_o    => score2_o,
            ball_x_o    => ball_x_o,
            ball_y_o    => ball_y_o,
            ball_vx_o   => ball_vx_o,
            ball_vy_o   => ball_vy_o,
            paddle1_y_o => paddle1_y_o,
            paddle2_y_o => paddle2_y_o
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

        procedure check(cond : in boolean; tag : in string) is
        begin
            if not cond then
                report "tb_pong_core: FAIL - " & tag severity error;
                errors := errors + 1;
            end if;
        end procedure;

        -- Advance time by n game ticks (+2 cycles settle margin)
        procedure run_ticks(n : in natural) is
        begin
            for i in 1 to n * TICK_PERIOD + 2 loop
                wait until rising_edge(clk_i);
            end loop;
        end procedure;

        procedure do_reset is
        begin
            rst_i <= '1';
            up1_i <= '0'; down1_i <= '0'; up2_i <= '0'; down2_i <= '0';
            wait until rising_edge(clk_i);
            wait until rising_edge(clk_i);
            rst_i <= '0';
            wait until rising_edge(clk_i);
        end procedure;

    begin
        ------------------------------------------------------------------
        -- 1) Default state after reset
        ------------------------------------------------------------------
        do_reset;
        check(ball_x_o = 158, "reset sonrasi ball_x_o=158 degil");
        check(ball_y_o = 118, "reset sonrasi ball_y_o=118 degil");
        check(ball_vx_o = 2, "reset sonrasi ball_vx_o=+2 degil");
        check(ball_vy_o = 1, "reset sonrasi ball_vy_o=+1 degil");
        check(paddle1_y_o = 100, "reset sonrasi paddle1_y_o=100 degil");
        check(paddle2_y_o = 100, "reset sonrasi paddle2_y_o=100 degil");
        check(score1_o = 0 and score2_o = 0, "reset sonrasi skorlar sifir degil");

        ------------------------------------------------------------------
        -- 2) Paddle movement and boundary clamping
        ------------------------------------------------------------------
        up1_i <= '1';
        run_ticks(60);  -- 100->0 needs 50 ticks; 60 overshoots on purpose
        up1_i <= '0';
        check(paddle1_y_o = 0, "paddle1 yukari kenetlenmesi basarisiz (0 bekleniyor)");

        down1_i <= '1';
        run_ticks(110);  -- 0->200 needs 100 ticks; 110 overshoots on purpose
        down1_i <= '0';
        check(paddle1_y_o = 200, "paddle1 asagi kenetlenmesi basarisiz (200 bekleniyor)");

        ------------------------------------------------------------------
        -- 3) Ball MISSES with paddle2 at the default position -> score1++ at tick 82 (nx=158+2*82=322>320)
        ------------------------------------------------------------------
        do_reset;
        run_ticks(82);
        check(score1_o = 1, "beklenen kacirma sonrasi score1_o=1 degil");
        check(score2_o = 0, "beklenmedik sekilde score2_o degisti");
        check(ball_x_o = 158 and ball_y_o = 118, "skor sonrasi top merkeze sifirlanmadi");
        check(ball_vx_o = 2 and ball_vy_o = 1, "skor sonrasi hiz varsayilana donmedi");

        ------------------------------------------------------------------
        -- 4) Paddle2 collision and bounce angle
        ------------------------------------------------------------------
        do_reset;
        down2_i <= '1';
        run_ticks(40);   -- paddle2: 100 -> 180
        down2_i <= '0';
        run_ticks(33);   -- reach a total of 73 ticks
        check(paddle2_y_o = 180, "raket2 hedef konuma (180) ulasmadi");
        check(ball_vx_o = -2, "raket2 carpismasi sonrasi vx=-2 degil (sekme olmadi?)");
        check(ball_vy_o = -1, "raket2 carpisma acisi yanlis (vy=-1 bekleniyor)");
        check(score1_o = 0 and score2_o = 0, "raket2 carpismasinda beklenmedik skor");

        ------------------------------------------------------------------
        -- 5) Paddle1 collision with a different bounce angle
        ------------------------------------------------------------------
        up1_i <= '1';
        run_ticks(35);   -- paddle1: 100 -> 30
        up1_i <= '0';
        run_ticks(111);  -- reach a total of 219 ticks (73+146)
        check(paddle1_y_o = 30, "raket1 hedef konuma (30) ulasmadi");
        check(ball_vx_o = 2, "raket1 carpismasi sonrasi vx=+2 degil (sekme olmadi?)");
        check(ball_vy_o = -1, "raket1 carpisma acisi yanlis (vy=-1 bekleniyor)");
        check(score1_o = 0 and score2_o = 0, "raket1 carpismasinda beklenmedik skor");

        ------------------------------------------------------------------
        -- 6) Top wall bounce
        ------------------------------------------------------------------
        run_ticks(45);   -- reach a total of 264 ticks (219+45)
        check(ball_y_o = 0, "ust duvarda ball_y_o=0 degil");
        check(ball_vy_o = 1, "ust duvar sekmesi sonrasi vy=+1 degil");
        check(ball_vx_o = 2, "ust duvar sekmesi vx'i etkilememeli (+2 kalmali)");
        check(score1_o = 0 and score2_o = 0, "duvar sekmesinde beklenmedik skor");

        ------------------------------------------------------------------
        -- Summary
        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_pong_core: PASS - raket hareketi/kenetlenme, kacirma/skor, iki farkli raket sekme acisi ve ust duvar sekmesi dogrulandi"
                severity note;
        else
            report "tb_pong_core: FAIL - " & integer'image(errors) & " hata bulundu" severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
