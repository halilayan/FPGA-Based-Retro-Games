--------------------------------------------------------------------------------
-- blitter.vhd
--
-- Command-driven 2D fill/blit/copy engine for the frame buffer. The CPU
-- (via console_gpu_axi.vhd) writes the cmd_* registers and pulses
-- cmd_start; the blitter then owns fb_we/fb_addr/fb_din until the whole
-- rectangle is done, holding busy='1' throughout.
--
-- cmd_op: 00 FILL (cmd_color, no source read), 01 BLIT (copies a w x h
-- sprite from src_addr/src_data, with optional cmd_key color-key
-- transparency and cmd_flip horizontal mirroring), 10 COPY (screen-to-
-- screen rectangle copy within the frame buffer; no transparency/flip).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blitter is
    generic (
        FB_W : positive := 320;
        FB_H : positive := 240
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        cmd_start : in  std_logic;
        cmd_op    : in  std_logic_vector(1 downto 0);
        cmd_x     : in  unsigned(9 downto 0);
        cmd_y     : in  unsigned(9 downto 0);
        cmd_w     : in  unsigned(9 downto 0);
        cmd_h     : in  unsigned(9 downto 0);
        cmd_src   : in  std_logic_vector(16 downto 0);
        cmd_color : in  std_logic_vector(7 downto 0);
        cmd_key   : in  std_logic_vector(7 downto 0);
        cmd_key_en : in std_logic;
        cmd_flip  : in  std_logic;
        busy      : out std_logic;

        src_addr : out std_logic_vector(16 downto 0);
        src_data : in  std_logic_vector(7 downto 0);

        fb_we   : out std_logic;
        fb_addr : out std_logic_vector(16 downto 0);
        fb_din  : out std_logic_vector(7 downto 0)
    );
end entity blitter;

architecture rtl of blitter is

    constant OP_FILL : std_logic_vector(1 downto 0) := "00";
    constant OP_BLIT : std_logic_vector(1 downto 0) := "01";
    constant OP_COPY : std_logic_vector(1 downto 0) := "10";

    constant FB_W_U : unsigned(9 downto 0) := to_unsigned(FB_W, 10);
    constant FB_H_U : unsigned(9 downto 0) := to_unsigned(FB_H, 10);

    constant ADDR_W : positive := 24; -- generous headroom for intermediate math; only the low 17 bits ever reach a port

    -- src_data is a registered memory read: it only reflects src_addr
    -- starting one cycle after ST_ADDR presents it, so ST_WAIT provides
    -- that extra cycle before ST_WRITE consumes src_data.
    type state_t is (ST_IDLE, ST_ADDR, ST_WAIT, ST_WRITE);
    signal state : state_t := ST_IDLE;

    -- Latched for the whole operation on the cmd_start cycle, so a
    -- register write that arrives before busy drops can't corrupt an
    -- in-flight operation.
    signal op_r       : std_logic_vector(1 downto 0);
    signal x0_r, y0_r : unsigned(9 downto 0);
    signal w0_r, h0_r : unsigned(9 downto 0);
    signal src0_r     : unsigned(16 downto 0);
    signal color_r    : std_logic_vector(7 downto 0);
    signal key_r      : std_logic_vector(7 downto 0);
    signal key_en_r   : std_logic;
    signal flip_r     : std_logic;
    -- COPY only: source and destination share the frame buffer, so an
    -- overlapping copy can overwrite source pixels before they're read
    -- (memmove hazard). Set when that would happen; reverses column/row
    -- iteration order to read high-to-low instead.
    signal reverse_r  : std_logic;

    -- Position within the w0 x h0 rectangle, counted 0..w0-1 / 0..h0-1
    -- forward; reverse_r/flip_r only affect which source/destination
    -- column or row this position maps to, never these counters.
    signal col_idx : unsigned(9 downto 0);
    signal row_idx : unsigned(9 downto 0);

    signal dst_col, dst_row : unsigned(9 downto 0);
    signal src_col, src_row : unsigned(9 downto 0);
    signal px, py           : unsigned(9 downto 0);
    signal in_bounds        : std_logic;

    signal dst_addr_c : unsigned(ADDR_W - 1 downto 0);
    signal src_addr_c : unsigned(ADDR_W - 1 downto 0);

    signal dst_xy_prod : unsigned(19 downto 0); -- py * FB_W  (10x10 bits)
    signal src_row_prod_blit : unsigned(19 downto 0); -- src_row * w0   (BLIT stride)
    signal src_row_prod_copy : unsigned(19 downto 0); -- src_row * FB_W (COPY stride)

begin

    busy <= '0' when state = ST_IDLE else '1';

    ----------------------------------------------------------------------
    -- Combinational: where the CURRENT (col_idx,row_idx) position lands,
    -- for both the destination and (when relevant) the source.
    ----------------------------------------------------------------------
    dst_col <= (w0_r - 1) - col_idx when reverse_r = '1' else col_idx;
    dst_row <= (h0_r - 1) - row_idx when reverse_r = '1' else row_idx;

    src_col <= (w0_r - 1) - col_idx when (op_r = OP_BLIT and flip_r = '1') or reverse_r = '1' else col_idx;
    src_row <= dst_row; -- no vertical flip; COPY's reverse already lives in dst_row

    px <= x0_r + dst_col;
    py <= y0_r + dst_row;
    -- cmd_x/y/w/h are unsigned, so only the upper bound needs checking;
    -- out-of-range destination pixels are skipped (fb_we stays '0').
    in_bounds <= '1' when (px < FB_W_U) and (py < FB_H_U) else '0';

    dst_xy_prod       <= py * FB_W_U;
    src_row_prod_blit <= src_row * w0_r;
    src_row_prod_copy <= src_row * FB_W_U;

    dst_addr_c <= resize(dst_xy_prod, ADDR_W) + resize(px, ADDR_W);

    src_addr_c <= resize(src0_r, ADDR_W) + resize(src_row_prod_blit, ADDR_W) + resize(src_col, ADDR_W)
                      when op_r = OP_BLIT else
                  resize(src0_r, ADDR_W) + resize(src_row_prod_copy, ADDR_W) + resize(src_col, ADDR_W);

    ----------------------------------------------------------------------
    process (clk)
        variable dst_base_v : unsigned(ADDR_W - 1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= ST_IDLE;
                fb_we <= '0';
            else
                fb_we <= '0'; -- one-cycle pulse, re-asserted below when a pixel is actually written

                case state is
                    ------------------------------------------------------
                    when ST_IDLE =>
                        if cmd_start = '1' then
                            op_r    <= cmd_op;
                            x0_r    <= cmd_x;
                            y0_r    <= cmd_y;
                            w0_r    <= cmd_w;
                            h0_r    <= cmd_h;
                            src0_r  <= unsigned(cmd_src);
                            color_r <= cmd_color;
                            key_r   <= cmd_key;
                            key_en_r <= cmd_key_en;
                            flip_r  <= cmd_flip;
                            col_idx <= (others => '0');
                            row_idx <= (others => '0');

                            dst_base_v := resize(cmd_y * FB_W_U, ADDR_W) + resize(cmd_x, ADDR_W);
                            if cmd_op = OP_COPY and unsigned(cmd_src) < dst_base_v then
                                reverse_r <= '1';
                            else
                                reverse_r <= '0';
                            end if;

                            if cmd_w = 0 or cmd_h = 0 then
                                state <= ST_IDLE; -- degenerate: nothing to do
                            elsif cmd_op = OP_FILL then
                                state <= ST_WRITE;
                            else
                                state <= ST_ADDR;
                            end if;
                        end if;

                    ------------------------------------------------------
                    when ST_ADDR =>
                        -- src_data reflects this address starting next cycle (see ST_WAIT).
                        src_addr <= std_logic_vector(src_addr_c(16 downto 0));
                        state    <= ST_WAIT;

                    ------------------------------------------------------
                    when ST_WAIT =>
                        state <= ST_WRITE;

                    ------------------------------------------------------
                    when ST_WRITE =>
                        if in_bounds = '1' and
                           not (op_r = OP_BLIT and key_en_r = '1' and src_data = key_r) then
                            fb_we   <= '1';
                            fb_addr <= std_logic_vector(dst_addr_c(16 downto 0));
                            if op_r = OP_FILL then
                                fb_din <= color_r;
                            else
                                fb_din <= src_data;
                            end if;
                        end if;

                        if col_idx = w0_r - 1 and row_idx = h0_r - 1 then
                            state <= ST_IDLE; -- last pixel of the rectangle
                        else
                            if col_idx = w0_r - 1 then
                                col_idx <= (others => '0');
                                row_idx <= row_idx + 1;
                            else
                                col_idx <= col_idx + 1;
                            end if;

                            if op_r = OP_FILL then
                                state <= ST_WRITE;
                            else
                                state <= ST_ADDR;
                            end if;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
