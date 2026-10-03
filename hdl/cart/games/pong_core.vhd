--------------------------------------------------------------------------------
-- pong_core.vhd
--
-- Pure-VHDL Pong (deliberately CPU-less): exercises the full video +
-- keyboard pipeline end to end.
--
-- Two independent processes:
--   game_update - updates paddle/ball physics on a ~60 Hz tick.
--   draw_scan   - every clk_i cycle, scans 320x240 and redraws the current
--                 game state into fb_ram (no separate clear/draw phase).
--
-- Uses its own free-running ~60 Hz tick in the clk_i domain rather than
-- video_out's frame_start (clk_pix domain), avoiding a clock-domain
-- crossing here.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pong_core is
    generic (
        CLK_HZ  : positive := 100_000_000;
        TICK_HZ : positive := 60;
        FB_W    : positive := 320;
        FB_H    : positive := 240
    );
    port (
        clk_i : in std_logic;
        rst_i : in std_logic;

        up1_i   : in std_logic;
        down1_i : in std_logic;
        up2_i   : in std_logic;
        down2_i : in std_logic;

        -- continuous write into fb_ram Port A
        fb_we_o   : out std_logic;
        fb_addr_o : out unsigned(16 downto 0);
        fb_din_o  : out std_logic_vector(7 downto 0);

        score1_o : out unsigned(3 downto 0);  -- 0-9 (saturates, does not wrap)
        score2_o : out unsigned(3 downto 0);

        -- Test/debug visibility - physics testbench reads internal state directly
        ball_x_o    : out signed(10 downto 0);
        ball_y_o    : out signed(10 downto 0);
        ball_vx_o   : out signed(4 downto 0);
        ball_vy_o   : out signed(4 downto 0);
        paddle1_y_o : out signed(10 downto 0);
        paddle2_y_o : out signed(10 downto 0)
    );
end entity pong_core;

architecture rtl of pong_core is

    ----------------------------------------------------------------------
    -- Constants (field geometry)
    ----------------------------------------------------------------------
    constant PADDLE_W : positive := 4;
    constant PADDLE_H : positive := 40;
    constant PADDLE1_X : natural := 8;
    constant PADDLE2_X : natural := FB_W - 8 - PADDLE_W;  -- 308
    constant BALL_SIZE : positive := 4;

    constant PADDLE_SPEED : positive := 2;   -- pixels/tick
    constant BALL_SPEED_X : positive := 2;
    constant BALL_SPEED_Y : positive := 1;

    constant BG_COLOR     : std_logic_vector(7 downto 0) := x"00";
    constant BALL_COLOR   : std_logic_vector(7 downto 0) := x"01";
    constant PADDLE_COLOR : std_logic_vector(7 downto 0) := x"02";
    constant LINE_COLOR   : std_logic_vector(7 downto 0) := x"03";
    constant TEXT_COLOR   : std_logic_vector(7 downto 0) := x"04";

    -- On-screen position of the (3x5) score digits
    constant SCORE1_X : natural := FB_W / 2 - 20;
    constant SCORE1_Y : natural := 8;
    constant SCORE2_X : natural := FB_W / 2 + 17;
    constant SCORE2_Y : natural := 8;

    constant TICK_PERIOD : positive := CLK_HZ / TICK_HZ;

    ----------------------------------------------------------------------
    -- Game state (updated only by the game_update process)
    ----------------------------------------------------------------------
    signal paddle1_y, paddle2_y : signed(10 downto 0) := to_signed((FB_H - PADDLE_H) / 2, 11);
    signal ball_x, ball_y       : signed(10 downto 0) := to_signed(FB_W / 2 - BALL_SIZE / 2, 11);
    signal ball_x_init          : signed(10 downto 0) := to_signed(FB_W / 2 - BALL_SIZE / 2, 11);
    signal ball_y_init          : signed(10 downto 0) := to_signed(FB_H / 2 - BALL_SIZE / 2, 11);
    signal ball_vx              : signed(4 downto 0) := to_signed(BALL_SPEED_X, 5);
    signal ball_vy              : signed(4 downto 0) := to_signed(BALL_SPEED_Y, 5);
    signal score1, score2       : unsigned(3 downto 0) := (others => '0');

    signal tick_cnt : natural range 0 to TICK_PERIOD - 1 := 0;
    signal tick     : std_logic := '0';
    signal tick_d1  : std_logic := '0';  -- tick delayed by 1 cycle (stage-2 pipeline pulse)

    -- Pipeline registers between game_update's two stages. TICK_PERIOD is
    -- ~1.67M cycles at 60 Hz/100 MHz, so splitting the physics update across
    -- 2 cycles instead of 1 is free timing slack, not a behaviour change.
    signal p_nx, p_ny     : signed(10 downto 0);
    signal p_nvx, p_nvy   : signed(4 downto 0);
    signal p_p1y, p_p2y   : signed(10 downto 0);

    ----------------------------------------------------------------------
    -- Scan counters (draw_scan process, advance every cycle at 100 MHz)
    ----------------------------------------------------------------------
    signal x_cnt : unsigned(9 downto 0) := (others => '0');
    signal y_cnt : unsigned(9 downto 0) := (others => '0');

    signal digit1_pixels, digit2_pixels : std_logic_vector(2 downto 0);

    -- row_i inputs of digit_font. Required: VHDL-93 does not allow an
    -- expression as a port map actual.
    signal digit1_row, digit2_row : unsigned(2 downto 0);

begin

    score1_o  <= score1;
    score2_o  <= score2;
    ball_x_o  <= ball_x;
    ball_y_o  <= ball_y;
    ball_vx_o <= ball_vx;
    ball_vy_o <= ball_vy;
    paddle1_y_o <= paddle1_y;
    paddle2_y_o <= paddle2_y;

    ----------------------------------------------------------------------
    -- ~60 Hz tick generator
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                tick_cnt <= 0;
                tick     <= '0';
            elsif tick_cnt = TICK_PERIOD - 1 then
                tick_cnt <= 0;
                tick     <= '1';
            else
                tick_cnt <= tick_cnt + 1;
                tick     <= '0';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Game physics - updated ONLY on the tick pulse
    ----------------------------------------------------------------------
    -- Split into two pipeline stages to shorten the combinational path
    -- (was a single 12-logic-level cloud, the tightest timing path in the
    -- design). Stage 1 (on tick): paddle move + wall bounce. Stage 2 (on
    -- tick_d1, one cycle later): paddle-hit test + score + final commit.
    -- One extra cycle of latency is invisible at a ~60 Hz tick rate.
    game_update : process (clk_i)
        variable nx, ny : signed(10 downto 0);
        variable nvx    : signed(4 downto 0);
        variable nvy    : signed(4 downto 0);
        variable hit_offset : signed(10 downto 0);
        variable p1y, p2y   : signed(10 downto 0);
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                paddle1_y <= to_signed((FB_H - PADDLE_H) / 2, 11);
                paddle2_y <= to_signed((FB_H - PADDLE_H) / 2, 11);
                ball_x    <= ball_x_init;
                ball_y    <= ball_y_init;
                ball_vx   <= to_signed(BALL_SPEED_X, 5);
                ball_vy   <= to_signed(BALL_SPEED_Y, 5);
                score1    <= (others => '0');
                score2    <= (others => '0');
                tick_d1   <= '0';
            else
                tick_d1 <= tick;

                if tick = '1' then
                    ------------------------------------------------------
                    -- Stage 1: paddles (clamped to 0..FB_H-PADDLE_H)
                    ------------------------------------------------------
                    p1y := paddle1_y;
                    p2y := paddle2_y;

                    if up1_i = '1' and p1y > 0 then
                        p1y := p1y - PADDLE_SPEED;
                    elsif down1_i = '1' and p1y < to_signed(FB_H - PADDLE_H, 11) then
                        p1y := p1y + PADDLE_SPEED;
                    end if;

                    if up2_i = '1' and p2y > 0 then
                        p2y := p2y - PADDLE_SPEED;
                    elsif down2_i = '1' and p2y < to_signed(FB_H - PADDLE_H, 11) then
                        p2y := p2y + PADDLE_SPEED;
                    end if;

                    paddle1_y <= p1y;
                    paddle2_y <= p2y;
                    p_p1y     <= p1y;
                    p_p2y     <= p2y;

                    -- Ball - candidate next position + top/bottom wall bounce
                    nx  := ball_x + resize(ball_vx, 11);
                    ny  := ball_y + resize(ball_vy, 11);
                    nvx := ball_vx;
                    nvy := ball_vy;

                    if ny <= 0 then
                        ny  := -ny;
                        nvy := -nvy;
                    elsif ny + BALL_SIZE >= FB_H then
                        ny  := to_signed(2 * (FB_H - BALL_SIZE), 11) - ny;
                        nvy := -nvy;
                    end if;

                    p_nx  <= nx;
                    p_ny  <= ny;
                    p_nvx <= nvx;
                    p_nvy <= nvy;
                end if;

                if tick_d1 = '1' then
                    ------------------------------------------------------
                    -- Stage 2: paddle bounce + score + final commit
                    ------------------------------------------------------
                    nx  := p_nx;
                    ny  := p_ny;
                    nvx := p_nvx;
                    nvy := p_nvy;
                    p1y := p_p1y;
                    p2y := p_p2y;

                    -- Paddle 1 (left) bounce: ball moving toward it (vx<0)
                    -- and the x/y ranges overlap
                    if nvx < 0 and nx <= to_signed(PADDLE1_X + PADDLE_W, 11) and
                       ny + BALL_SIZE >= p1y and ny <= p1y + PADDLE_H
                    then
                        nvx := -nvx;
                        hit_offset := (ny + BALL_SIZE / 2) - (p1y + PADDLE_H / 2);
                        nvy := resize(shift_right(hit_offset, 3), 5);

                    -- Paddle 2 (right) bounce
                    elsif nvx > 0 and nx + BALL_SIZE >= to_signed(PADDLE2_X, 11) and
                          ny + BALL_SIZE >= p2y and ny <= p2y + PADDLE_H
                    then
                        nvx := -nvx;
                        hit_offset := (ny + BALL_SIZE / 2) - (p2y + PADDLE_H / 2);
                        nvy := resize(shift_right(hit_offset, 3), 5);
                    end if;

                    -- Score conditions: the ball fully passed a paddle
                    if nx + BALL_SIZE < 0 then
                        if score2 < 9 then
                            score2 <= score2 + 1;
                        end if;
                        ball_x  <= ball_x_init;
                        ball_y  <= ball_y_init;
                        ball_vx <= to_signed(-BALL_SPEED_X, 5);
                        ball_vy <= to_signed(BALL_SPEED_Y, 5);
                    elsif nx > FB_W then
                        if score1 < 9 then
                            score1 <= score1 + 1;
                        end if;
                        ball_x  <= ball_x_init;
                        ball_y  <= ball_y_init;
                        ball_vx <= to_signed(BALL_SPEED_X, 5);
                        ball_vy <= to_signed(BALL_SPEED_Y, 5);
                    else
                        ball_x  <= nx;
                        ball_y  <= ny;
                        ball_vx <= nvx;
                        ball_vy <= nvy;
                    end if;
                end if;
            end if;
        end if;
    end process game_update;

    ----------------------------------------------------------------------
    -- Score digit pixel lookup (combinational)
    ----------------------------------------------------------------------
    -- Subtraction is done at full width (y_cnt'length) then resized to 3
    -- bits; truncating first (y_cnt(2 downto 0) - N) would give the wrong
    -- row whenever SCORE*_Y isn't a multiple of 8.
    digit1_row <= resize(y_cnt - to_unsigned(SCORE1_Y, y_cnt'length), 3);
    digit2_row <= resize(y_cnt - to_unsigned(SCORE2_Y, y_cnt'length), 3);

    u_digit1 : entity work.digit_font
        port map (
            digit_i  => score1,
            row_i    => digit1_row,
            pixels_o => digit1_pixels
        );

    u_digit2 : entity work.digit_font
        port map (
            digit_i  => score2,
            row_i    => digit2_row,
            pixels_o => digit2_pixels
        );

    ----------------------------------------------------------------------
    -- Continuous scan + draw: x_cnt/y_cnt advance every cycle; the color
    -- for the current (x_cnt,y_cnt) is computed and written to fb_ram.
    ----------------------------------------------------------------------
    draw_scan : process (clk_i)
        variable addr       : unsigned(16 downto 0);
        variable color      : std_logic_vector(7 downto 0);
        variable sx, sy      : signed(10 downto 0);
        variable in_ball, in_p1, in_p2, in_line : boolean;
        variable in_score1, in_score2 : boolean;
        variable col_in_digit : integer range 0 to 2;
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                x_cnt <= (others => '0');
                y_cnt <= (others => '0');
            else
                sx := signed(resize(x_cnt, 11));
                sy := signed(resize(y_cnt, 11));

                in_ball := (sx >= ball_x) and (sx < ball_x + BALL_SIZE) and
                           (sy >= ball_y) and (sy < ball_y + BALL_SIZE);

                in_p1 := (x_cnt >= PADDLE1_X) and (x_cnt < PADDLE1_X + PADDLE_W) and
                         (sy >= paddle1_y) and (sy < paddle1_y + PADDLE_H);

                in_p2 := (x_cnt >= PADDLE2_X) and (x_cnt < PADDLE2_X + PADDLE_W) and
                         (sy >= paddle2_y) and (sy < paddle2_y + PADDLE_H);

                in_line := (x_cnt = FB_W / 2) and (y_cnt(3) = '0');  -- dashed center line

                in_score1 := (x_cnt >= SCORE1_X) and (x_cnt < SCORE1_X + 3) and
                             (y_cnt >= SCORE1_Y) and (y_cnt < SCORE1_Y + 5);

                in_score2 := (x_cnt >= SCORE2_X) and (x_cnt < SCORE2_X + 3) and
                             (y_cnt >= SCORE2_Y) and (y_cnt < SCORE2_Y + 5);

                if in_ball then
                    color := BALL_COLOR;
                elsif in_p1 or in_p2 then
                    color := PADDLE_COLOR;
                elsif in_score1 then
                    col_in_digit := to_integer(x_cnt) - SCORE1_X;
                    if digit1_pixels(2 - col_in_digit) = '1' then
                        color := TEXT_COLOR;
                    else
                        color := BG_COLOR;
                    end if;
                elsif in_score2 then
                    col_in_digit := to_integer(x_cnt) - SCORE2_X;
                    if digit2_pixels(2 - col_in_digit) = '1' then
                        color := TEXT_COLOR;
                    else
                        color := BG_COLOR;
                    end if;
                elsif in_line then
                    color := LINE_COLOR;
                else
                    color := BG_COLOR;
                end if;

                addr := shift_left(resize(y_cnt, 17), 8) + shift_left(resize(y_cnt, 17), 6) +
                        resize(x_cnt, 17);

                fb_we_o   <= '1';
                fb_addr_o <= addr;
                fb_din_o  <= color;

                if x_cnt = FB_W - 1 then
                    x_cnt <= (others => '0');
                    if y_cnt = FB_H - 1 then
                        y_cnt <= (others => '0');
                    else
                        y_cnt <= y_cnt + 1;
                    end if;
                else
                    x_cnt <= x_cnt + 1;
                end if;
            end if;
        end if;
    end process draw_scan;

end architecture rtl;
