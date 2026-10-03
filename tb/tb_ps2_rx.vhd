--------------------------------------------------------------------------------
-- tb_ps2_rx.vhd
--
-- Self-checking testbench for ps2_rx: drives ps2_clk_i/ps2_data_i via the
-- ps2_bfm package to emulate a real PS/2 device.
--
-- Covers valid frames, bad-parity/bad-stop rejection, a clock glitch, and
-- a mid-frame stall/timeout, each followed by a clean frame to confirm
-- recovery. A monitor process cumulatively counts the single-cycle
-- rx_valid_o/parity_err_o/frame_err_o pulses for before/after comparison.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

use work.ps2_bfm.all;

entity tb_ps2_rx is
end entity tb_ps2_rx;

architecture sim of tb_ps2_rx is

    constant CLK_PERIOD : time     := 10 ns;          -- 100 MHz simulation clock
    constant CLK_HZ_C   : positive := 100_000_000;    -- actual board value for the DUT

    signal clk_i        : std_logic := '0';
    signal rst_i        : std_logic := '1';
    signal ps2_clk_i     : std_logic := '1';   -- idle high (pull-up)
    signal ps2_data_i    : std_logic := '1';   -- idle high (pull-up)
    signal rx_data_o     : std_logic_vector(7 downto 0);
    signal rx_valid_o    : std_logic;
    signal parity_err_o  : std_logic;
    signal frame_err_o   : std_logic;

    signal sim_done : boolean := false;

    -- Cumulative counters / last captured byte, kept by the monitor process
    signal valid_count      : natural := 0;
    signal parity_err_count : natural := 0;
    signal frame_err_count  : natural := 0;
    signal last_rx_data     : std_logic_vector(7 downto 0) := (others => '0');

begin

    ----------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------
    dut : entity work.ps2_rx
        generic map (
            CLK_HZ => CLK_HZ_C
        )
        port map (
            clk_i        => clk_i,
            rst_i        => rst_i,
            ps2_clk_i    => ps2_clk_i,
            ps2_data_i   => ps2_data_i,
            rx_data_o    => rx_data_o,
            rx_valid_o   => rx_valid_o,
            parity_err_o => parity_err_o,
            frame_err_o  => frame_err_o
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
    -- Monitor: cumulative counters so single-cycle pulses aren't missed
    ----------------------------------------------------------------------
    monitor : process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rx_valid_o = '1' then
                valid_count  <= valid_count + 1;
                last_rx_data <= rx_data_o;
            end if;
            if parity_err_o = '1' then
                parity_err_count <= parity_err_count + 1;
            end if;
            if frame_err_o = '1' then
                frame_err_count <= frame_err_count + 1;
            end if;
        end if;
    end process monitor;

    ----------------------------------------------------------------------
    -- Stimulus + self-checking monitor
    ----------------------------------------------------------------------
    stimulus : process
        variable errors : natural := 0;

        -- Checks a condition, counting failures and reporting them.
        procedure check(cond : boolean; msg : string; variable err : inout natural) is
        begin
            if not cond then
                err := err + 1;
                report "tb_ps2_rx: FAIL - " & msg severity error;
            end if;
        end procedure check;

        variable v0, p0, f0 : natural;
        variable test_byte  : std_logic_vector(7 downto 0);
    begin
        --------------------------------------------------------------
        -- Reset
        --------------------------------------------------------------
        rst_i <= '1';
        ps2_clk_i  <= '1';
        ps2_data_i <= '1';
        wait for CLK_PERIOD * 5;
        wait until rising_edge(clk_i);
        rst_i <= '0';
        wait for CLK_PERIOD * 5;

        check(rx_valid_o = '0' and parity_err_o = '0' and frame_err_o = '0',
              "reset sonrasi cikis bayraklari '0' degil", errors);

        --------------------------------------------------------------
        -- Test 1: valid frames with several different byte values
        --------------------------------------------------------------
        for idx in 0 to 4 loop
            case idx is
                when 0 => test_byte := x"1D";
                when 1 => test_byte := x"00";
                when 2 => test_byte := x"FF";
                when 3 => test_byte := x"A5";
                when others => test_byte := x"5A";
            end case;

            v0 := valid_count;
            p0 := parity_err_count;
            f0 := frame_err_count;

            ps2_send_frame(ps2_clk_i, ps2_data_i, test_byte);
            wait for 200 ns;

            check(valid_count = v0 + 1,
                  "test1: gecerli cerceve icin rx_valid_o darbesi gelmedi (bayt=" &
                  integer'image(to_integer(unsigned(test_byte))) & ")", errors);
            check(last_rx_data = test_byte,
                  "test1: rx_data_o beklenen bayta esit degil", errors);
            check(parity_err_count = p0, "test1: beklenmedik parity_err_o", errors);
            check(frame_err_count  = f0, "test1: beklenmedik frame_err_o", errors);
        end loop;

        --------------------------------------------------------------
        -- Test 2: bad-parity frame is rejected, next valid frame is received
        --------------------------------------------------------------
        v0 := valid_count;
        p0 := parity_err_count;
        f0 := frame_err_count;

        ps2_send_frame(ps2_clk_i, ps2_data_i, x"3C", bad_parity => true);
        wait for 200 ns;

        check(valid_count = v0,
              "test2: bozuk paritede rx_valid_o yanlislikla yukseldi", errors);
        check(parity_err_count = p0 + 1,
              "test2: parity_err_o darbesi gelmedi", errors);
        check(frame_err_count = f0,
              "test2: bozuk paritede beklenmedik frame_err_o", errors);

        v0 := valid_count;
        ps2_send_frame(ps2_clk_i, ps2_data_i, x"7E");
        wait for 200 ns;
        check(valid_count = v0 + 1,
              "test2: parite hatasindan sonraki gecerli cerceve alinamadi", errors);
        check(last_rx_data = x"7E",
              "test2: toparlanma sonrasi rx_data_o yanlis", errors);

        --------------------------------------------------------------
        -- Test 3: bad-stop-bit frame is rejected, next valid frame is received
        --------------------------------------------------------------
        v0 := valid_count;
        p0 := parity_err_count;
        f0 := frame_err_count;

        ps2_send_frame(ps2_clk_i, ps2_data_i, x"66", bad_stop => true);
        wait for 200 ns;

        check(valid_count = v0,
              "test3: bozuk stop bitinde rx_valid_o yanlislikla yukseldi", errors);
        check(frame_err_count = f0 + 1,
              "test3: frame_err_o darbesi gelmedi", errors);
        check(parity_err_count = p0,
              "test3: bozuk stop bitinde beklenmedik parity_err_o", errors);

        v0 := valid_count;
        ps2_send_frame(ps2_clk_i, ps2_data_i, x"81");
        wait for 200 ns;
        check(valid_count = v0 + 1,
              "test3: frame hatasindan sonraki gecerli cerceve alinamadi", errors);
        check(last_rx_data = x"81",
              "test3: toparlanma sonrasi rx_data_o yanlis", errors);

        --------------------------------------------------------------
        -- Test 4: a clock glitch does not corrupt the next clean frame.
        -- ps2_rx has no debounce filter, so a short pulse can be mistaken
        -- for a start edge; recovery relies on the ~100us watchdog, hence
        -- the 150us wait below.
        --------------------------------------------------------------
        v0 := valid_count;
        p0 := parity_err_count;
        f0 := frame_err_count;

        ps2_send_glitch(ps2_clk_i, ps2_data_i);
        wait for 150 us;  -- longer than the 100us watchdog, to allow recovery

        check(valid_count = v0 and parity_err_count = p0 and frame_err_count = f0,
              "test4: glitch sonrasi (toparlanma penceresinde) beklenmedik bayrak", errors);

        v0 := valid_count;
        ps2_send_frame(ps2_clk_i, ps2_data_i, x"E0");
        wait for 200 ns;
        check(valid_count = v0 + 1,
              "test4: glitch sonrasi temiz cerceve alinamadi", errors);
        check(last_rx_data = x"E0",
              "test4: glitch sonrasi rx_data_o yanlis", errors);

        --------------------------------------------------------------
        -- Test 5: watchdog/timeout - clock stalls mid-frame, receiver
        -- returns to idle and correctly receives the next fresh frame.
        -- stall_time (200us) exceeds the DUT's ~100us timeout.
        --------------------------------------------------------------
        v0 := valid_count;
        p0 := parity_err_count;
        f0 := frame_err_count;

        ps2_send_frame(ps2_clk_i, ps2_data_i, x"9A",
                       stall_after_bit => 2, stall_time => 200 us);

        check(valid_count = v0 and parity_err_count = p0 and frame_err_count = f0,
              "test5: takilan (stall) cercevede beklenmedik bayrak", errors);

        v0 := valid_count;
        ps2_send_frame(ps2_clk_i, ps2_data_i, x"C3");
        wait for 200 ns;
        check(valid_count = v0 + 1,
              "test5: watchdog sonrasi taze cerceve alinamadi (alici kilitli kalmis olabilir)",
              errors);
        check(last_rx_data = x"C3",
              "test5: watchdog sonrasi rx_data_o yanlis", errors);

        --------------------------------------------------------------
        -- Result
        --------------------------------------------------------------
        if errors = 0 then
            report "tb_ps2_rx: PASS - gecerli cerceveler, parite hatasi reddi, " &
                   "frame hatasi reddi, gurultu bagisikligi ve watchdog kurtarma testleri dogrulandi"
                severity note;
        else
            report "tb_ps2_rx: FAIL - " & integer'image(errors) & " hata bulundu"
                severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
