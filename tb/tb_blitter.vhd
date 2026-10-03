--------------------------------------------------------------------------------
-- tb_blitter.vhd
--
-- Golden-reference testbench for blitter.vhd: directed fill/blit/copy cases
-- plus 10,000 randomized operations, each checked byte-for-byte against an
-- independent reference model computed here in plain VHDL.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;

entity tb_blitter is
end entity tb_blitter;

architecture sim of tb_blitter is

    constant CLK_PERIOD : time := 10 ns; -- 100 MHz
    constant FB_W : positive := 320;
    constant FB_H : positive := 240;
    constant FB_SIZE : positive := FB_W * FB_H;
    constant MEM_SIZE : positive := 131072; -- 2**17, full cmd_src/fb_addr range

    constant OP_FILL : std_logic_vector(1 downto 0) := "00";
    constant OP_BLIT : std_logic_vector(1 downto 0) := "01";
    constant OP_COPY : std_logic_vector(1 downto 0) := "10";

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    signal cmd_start : std_logic := '0';
    signal cmd_op    : std_logic_vector(1 downto 0) := (others => '0');
    signal cmd_x, cmd_y, cmd_w, cmd_h : unsigned(9 downto 0) := (others => '0');
    signal cmd_src   : std_logic_vector(16 downto 0) := (others => '0');
    signal cmd_color : std_logic_vector(7 downto 0) := (others => '0');
    signal cmd_key   : std_logic_vector(7 downto 0) := (others => '0');
    signal cmd_key_en : std_logic := '1';
    signal cmd_flip  : std_logic := '0';
    signal busy      : std_logic;

    signal src_addr : std_logic_vector(16 downto 0);
    signal src_data : std_logic_vector(7 downto 0);

    signal fb_we   : std_logic;
    signal fb_addr : std_logic_vector(16 downto 0);
    signal fb_din  : std_logic_vector(7 downto 0);

    type mem_t is array (0 to MEM_SIZE - 1) of integer range 0 to 255;

    -- backing_mem has exactly one driving process (`monitor`, below): an
    -- unresolved element type can't be driven from two processes, so the
    -- sprite-ROM region (76800..131071) is baked in here as its initial value.
    function init_backing_mem return mem_t is
        variable m : mem_t := (others => 0);
    begin
        for i in FB_SIZE to MEM_SIZE - 1 loop
            m(i) := (i * 37 + 11) mod 256;
        end loop;
        return m;
    end function init_backing_mem;

    signal backing_mem : mem_t := init_backing_mem; -- "live FB" (0..76799) + "sprite ROM" (76800..131071)

    -- oob_errors is driven only by `monitor`; the golden-mismatch count is
    -- a separate variable inside `stim` for the same single-driver reason.
    signal oob_errors : integer := 0;
    signal op_count   : integer := 0;

begin

    ----------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    rst_proc : process
    begin
        rst <= '1';
        wait for 10 * CLK_PERIOD;
        rst <= '0';
        wait;
    end process rst_proc;

    ----------------------------------------------------------------------
    dut : entity work.blitter
        generic map (FB_W => FB_W, FB_H => FB_H)
        port map (
            clk => clk, rst => rst,
            cmd_start => cmd_start, cmd_op => cmd_op,
            cmd_x => cmd_x, cmd_y => cmd_y, cmd_w => cmd_w, cmd_h => cmd_h,
            cmd_src => cmd_src, cmd_color => cmd_color, cmd_key => cmd_key,
            cmd_key_en => cmd_key_en,
            cmd_flip => cmd_flip, busy => busy,
            src_addr => src_addr, src_data => src_data,
            fb_we => fb_we, fb_addr => fb_addr, fb_din => fb_din
        );

    ----------------------------------------------------------------------
    -- Synchronous "memory" behind src_addr/src_data - 1 cycle read latency,
    -- matching fb_ram.vhd's timing (blitter.vhd's ST_ADDR/ST_WRITE split
    -- depends on this).
    ----------------------------------------------------------------------
    src_mem_proc : process (clk)
    begin
        if rising_edge(clk) then
            src_data <= std_logic_vector(to_unsigned(backing_mem(to_integer(unsigned(src_addr))), 8));
        end if;
    end process src_mem_proc;

    ----------------------------------------------------------------------
    -- Write monitor: mirrors every DUT write into backing_mem and flags
    -- out-of-bounds addresses.
    ----------------------------------------------------------------------
    monitor : process (clk)
    begin
        if rising_edge(clk) then
            if fb_we = '1' then
                if to_integer(unsigned(fb_addr)) >= FB_SIZE then
                    oob_errors <= oob_errors + 1;
                    report "ERROR: write outside the frame buffer, addr=" &
                           integer'image(to_integer(unsigned(fb_addr))) severity error;
                else
                    backing_mem(to_integer(unsigned(fb_addr))) <= to_integer(unsigned(fb_din));
                end if;
            end if;
        end if;
    end process monitor;

    ----------------------------------------------------------------------
    stim : process
        variable seed1, seed2 : positive := 1;
        variable golden : mem_t := (others => 0);
        variable mismatch_errors : integer := 0;

        procedure run_op(op : std_logic_vector(1 downto 0);
                          x, y, w, h : integer;
                          src : integer := 0;
                          color : integer := 0;
                          key : integer := 0;
                          key_en : std_logic := '0'; -- default: opaque (matches gfx_sprite's contract)
                          flip : std_logic := '0') is
        begin
            wait until rising_edge(clk) and busy = '0';
            cmd_op    <= op;
            cmd_x     <= to_unsigned(x, 10);
            cmd_y     <= to_unsigned(y, 10);
            cmd_w     <= to_unsigned(w, 10);
            cmd_h     <= to_unsigned(h, 10);
            cmd_src   <= std_logic_vector(to_unsigned(src, 17));
            cmd_color <= std_logic_vector(to_unsigned(color, 8));
            cmd_key   <= std_logic_vector(to_unsigned(key mod 256, 8));
            cmd_key_en <= key_en;
            cmd_flip  <= flip;
            cmd_start <= '1';
            wait until rising_edge(clk);
            cmd_start <= '0';
            wait until rising_edge(clk) and busy = '0';
            op_count <= op_count + 1;
        end procedure run_op;

        -- Reference model for fill/blit/copy, independent of blitter.vhd's
        -- own address-generation strategy.
        procedure golden_fill(x, y, w, h, color : integer) is
        begin
            for r in 0 to h - 1 loop
                for c in 0 to w - 1 loop
                    if (x + c) < FB_W and (y + r) < FB_H then
                        golden((y + r) * FB_W + (x + c)) := color;
                    end if;
                end loop;
            end loop;
        end procedure golden_fill;

        procedure golden_blit(x, y, w, h, src, key : integer; key_en : std_logic; flip : std_logic) is
            variable sc, sv : integer;
            variable skip   : boolean;
        begin
            for r in 0 to h - 1 loop
                for c in 0 to w - 1 loop
                    if flip = '1' then
                        sc := (w - 1) - c;
                    else
                        sc := c;
                    end if;
                    sv := backing_mem(src + r * w + sc);
                    skip := (key_en = '1') and (sv = key);
                    if not skip and (x + c) < FB_W and (y + r) < FB_H then
                        golden((y + r) * FB_W + (x + c)) := sv;
                    end if;
                end loop;
            end loop;
        end procedure golden_blit;

        -- memmove semantics: snapshot the source rectangle before writing,
        -- so an overlapping copy is unambiguous - the correctness
        -- definition blitter.vhd's reverse_r logic is checked against.
        procedure golden_copy(sx, sy, dx, dy, w, h : integer) is
            type snap_t is array (0 to w * h - 1) of integer;
            variable snap : snap_t;
        begin
            for r in 0 to h - 1 loop
                for c in 0 to w - 1 loop
                    snap(r * w + c) := golden((sy + r) * FB_W + (sx + c));
                end loop;
            end loop;
            for r in 0 to h - 1 loop
                for c in 0 to w - 1 loop
                    if (dx + c) < FB_W and (dy + r) < FB_H then
                        golden((dy + r) * FB_W + (dx + c)) := snap(r * w + c);
                    end if;
                end loop;
            end loop;
        end procedure golden_copy;

        procedure check_all(tag : string) is
            variable local_errors : integer := 0;
            variable shown : integer;
        begin
            -- run_op's closing wait can resume in the same delta round as
            -- monitor's write of the last pixel; yield one delta here so
            -- that write is visible before backing_mem is read below.
            wait for 0 ns;
            for i in 0 to FB_SIZE - 1 loop
                if backing_mem(i) /= golden(i) then
                    local_errors := local_errors + 1;
                    if local_errors <= 5 then
                        report "ERROR [" & tag & "] addr=" & integer'image(i) &
                               " dut=" & integer'image(backing_mem(i)) &
                               " golden=" & integer'image(golden(i)) severity error;
                    end if;
                end if;
            end loop;
            if local_errors > 0 then
                mismatch_errors := mismatch_errors + local_errors;
                if local_errors < 5 then
                    shown := local_errors;
                else
                    shown := 5;
                end if;
                report "ERROR [" & tag & "]: " & integer'image(local_errors) &
                       " mismatching byte(s) (" & integer'image(shown) &
                       " shown above)" severity error;
            end if;
        end procedure check_all;

        variable rv : real;

        impure function rand_int(lo, hi : integer) return integer is
        begin
            uniform(seed1, seed2, rv);
            return lo + integer(floor(rv * real(hi - lo + 1)));
        end function rand_int;

        variable flip_v, key_en_v : std_logic;
        variable w_v, h_v, sx_v, sy_v : integer;
    begin
        wait until rst = '0';
        wait for 5 * CLK_PERIOD;

        ------------------------------------------------------------------
        -- T1: FILL - basic, 1x1, full-screen, edge clipping
        ------------------------------------------------------------------
        run_op(OP_FILL, 10, 10, 8, 8, color => 42);
        golden_fill(10, 10, 8, 8, 42);
        check_all("T1a fill basic");

        run_op(OP_FILL, 100, 100, 1, 1, color => 7);
        golden_fill(100, 100, 1, 1, 7);
        check_all("T1b fill 1x1");

        run_op(OP_FILL, 0, 0, FB_W, FB_H, color => 1);
        golden_fill(0, 0, FB_W, FB_H, 1);
        check_all("T1c fill full screen");

        run_op(OP_FILL, 315, 235, 20, 20, color => 99); -- runs off the right/bottom edge
        golden_fill(315, 235, 20, 20, 99);
        check_all("T1d fill edge clipping");

        ------------------------------------------------------------------
        -- T2: BLIT - opaque, transparency key, horizontal flip, clipping
        ------------------------------------------------------------------
        run_op(OP_FILL, 0, 0, FB_W, FB_H, color => 0); -- clean slate
        golden_fill(0, 0, FB_W, FB_H, 0);

        run_op(OP_BLIT, 50, 50, 4, 4, src => FB_SIZE); -- key_en defaults to '0': opaque
        golden_blit(50, 50, 4, 4, FB_SIZE, 0, '0', '0');
        check_all("T2a blit opaque");

        -- key_en='0' must draw every source pixel even when one matches
        -- cmd_key (opaque is controlled by this bit, not by the key value).
        run_op(OP_BLIT, 55, 55, 4, 4, src => FB_SIZE, key => backing_mem(FB_SIZE), key_en => '0');
        golden_blit(55, 55, 4, 4, FB_SIZE, backing_mem(FB_SIZE), '0', '0');
        check_all("T2a2 blit opaque ignores a key that would otherwise match");

        run_op(OP_BLIT, 60, 60, 4, 4, src => FB_SIZE, key => backing_mem(FB_SIZE), key_en => '1');
        golden_blit(60, 60, 4, 4, FB_SIZE, backing_mem(FB_SIZE), '1', '0');
        check_all("T2b blit transparency key");

        run_op(OP_BLIT, 70, 70, 4, 4, src => FB_SIZE, flip => '1');
        golden_blit(70, 70, 4, 4, FB_SIZE, 0, '0', '1');
        check_all("T2c blit horizontal flip");

        run_op(OP_BLIT, 318, 238, 6, 6, src => FB_SIZE); -- runs off the edge
        golden_blit(318, 238, 6, 6, FB_SIZE, 0, '0', '0');
        check_all("T2d blit edge clipping");

        ------------------------------------------------------------------
        -- T3: COPY - non-overlapping, and both overlap directions
        ------------------------------------------------------------------
        run_op(OP_FILL, 0, 0, FB_W, FB_H, color => 0);
        golden_fill(0, 0, FB_W, FB_H, 0);
        run_op(OP_FILL, 0, 0, 10, 10, color => 55); -- a distinctive 10x10 source block
        golden_fill(0, 0, 10, 10, 55);

        run_op(OP_COPY, 200, 100, 10, 10, src => 0); -- (sx,sy)=(0,0), no overlap with dest
        golden_copy(0, 0, 200, 100, 10, 10);
        check_all("T3a copy non-overlapping");

        -- Overlap, dest after src (src < dest): forward iteration would be
        -- unsafe here - exercises reverse_r='1'.
        run_op(OP_FILL, 0, 0, FB_W, FB_H, color => 0);
        golden_fill(0, 0, FB_W, FB_H, 0);
        run_op(OP_FILL, 0, 0, 20, 1, color => 77); -- one 20-pixel row
        golden_fill(0, 0, 20, 1, 77);
        run_op(OP_COPY, 5, 0, 20, 1, src => 0); -- shift that row right by 5 (overlapping)
        golden_copy(0, 0, 5, 0, 20, 1);
        check_all("T3b copy overlap, dest after src (reverse)");

        -- Overlap, dest before src (src > dest): forward iteration is
        -- correct here - exercises reverse_r='0' with real overlap.
        run_op(OP_FILL, 0, 0, FB_W, FB_H, color => 0);
        golden_fill(0, 0, FB_W, FB_H, 0);
        run_op(OP_FILL, 5, 0, 20, 1, color => 88);
        golden_fill(5, 0, 20, 1, 88);
        run_op(OP_COPY, 0, 0, 20, 1, src => 5); -- shift the same row left by 5 (overlapping)
        golden_copy(5, 0, 0, 0, 20, 1);
        check_all("T3c copy overlap, dest before src (forward)");

        ------------------------------------------------------------------
        -- T4: 10,000 randomized fill/blit/copy operations (small rectangles,
        -- including off-screen positions) against the golden reference.
        ------------------------------------------------------------------
        for n in 1 to 10000 loop
            case rand_int(0, 2) is
                when 0 =>
                    run_op(OP_FILL, rand_int(0, FB_W - 1), rand_int(0, FB_H - 1),
                           rand_int(1, 16), rand_int(1, 16), color => rand_int(0, 255));
                    golden_fill(to_integer(unsigned(cmd_x)), to_integer(unsigned(cmd_y)),
                                to_integer(unsigned(cmd_w)), to_integer(unsigned(cmd_h)),
                                to_integer(unsigned(cmd_color)));

                when 1 =>
                    if rand_int(0, 1) = 1 then
                        flip_v := '1';
                    else
                        flip_v := '0';
                    end if;
                    if rand_int(0, 1) = 1 then
                        key_en_v := '1';
                    else
                        key_en_v := '0';
                    end if;
                    run_op(OP_BLIT, rand_int(0, FB_W - 1), rand_int(0, FB_H - 1),
                           rand_int(1, 16), rand_int(1, 16),
                           src => FB_SIZE + rand_int(0, MEM_SIZE - FB_SIZE - 256),
                           key => rand_int(0, 255),
                           key_en => key_en_v,
                           flip => flip_v);
                    golden_blit(to_integer(unsigned(cmd_x)), to_integer(unsigned(cmd_y)),
                                to_integer(unsigned(cmd_w)), to_integer(unsigned(cmd_h)),
                                to_integer(unsigned(cmd_src)), to_integer(unsigned(cmd_key)), cmd_key_en, cmd_flip);

                when others =>
                    -- COPY's source must stay a real on-screen rectangle
                    -- (unlike BLIT's sprite-ROM source, an off-screen COPY
                    -- source would spill into that same region).
                    w_v := rand_int(1, 16);
                    h_v := rand_int(1, 16);
                    sx_v := rand_int(0, FB_W - w_v);
                    sy_v := rand_int(0, FB_H - h_v);
                    run_op(OP_COPY, rand_int(0, FB_W - 1), rand_int(0, FB_H - 1),
                           w_v, h_v, src => sy_v * FB_W + sx_v);
                    golden_copy(sx_v, sy_v,
                                to_integer(unsigned(cmd_x)), to_integer(unsigned(cmd_y)),
                                to_integer(unsigned(cmd_w)), to_integer(unsigned(cmd_h)));
            end case;

            if n mod 1000 = 0 then
                check_all("T4 random op #" & integer'image(n));
            end if;
        end loop;
        check_all("T4 random, final");

        ------------------------------------------------------------------
        wait for CLK_PERIOD; -- let monitor's last oob_errors update (if any) settle

        if mismatch_errors = 0 and oob_errors = 0 then
            report "tb_blitter: PASS - fill/blit/copy directed cases (clipping, 1x1, full-screen, " &
                   "opaque vs keyed transparency (key_en), horizontal flip, both copy-overlap directions) + " &
                   integer'image(op_count) & " total operations against a golden reference, all bit-exact" severity note;
        else
            report "tb_blitter: FAIL - " & integer'image(mismatch_errors) & " golden mismatch(es), " &
                   integer'image(oob_errors) & " out-of-bounds write(s), across " &
                   integer'image(op_count) & " operations" severity failure;
        end if;

        stop;
        wait;
    end process stim;

end architecture sim;
