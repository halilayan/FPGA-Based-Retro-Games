--------------------------------------------------------------------------------
-- tb_fb_ram.vhd
--
-- Self-checking testbench for fb_ram.vhd: write via Port A, read back via
-- Port A and via Port B (separate clock domain) to prove cross-port
-- visibility, and check that an unwritten address and the boundary
-- addresses (0 and DEPTH-1) behave correctly.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_fb_ram is
end entity tb_fb_ram;

architecture sim of tb_fb_ram is

    constant CLK_A_PERIOD : time := 40 ns;
    constant CLK_B_PERIOD : time := 40 ns;

    constant FB_W : positive := 320;
    constant FB_H : positive := 240;
    constant DEPTH : positive := FB_W * FB_H;

    signal clk_a_i  : std_logic := '0';
    signal we_a_i    : std_logic := '0';
    signal addr_a_i  : unsigned(16 downto 0) := (others => '0');
    signal din_a_i   : std_logic_vector(7 downto 0) := (others => '0');
    signal dout_a_o  : std_logic_vector(7 downto 0);

    signal clk_b_i  : std_logic := '0';
    signal addr_b_i  : unsigned(16 downto 0) := (others => '0');
    signal dout_b_o  : std_logic_vector(7 downto 0);

    signal sim_done : boolean := false;

    -- Address/data pairs for the test: distributed samples + boundary addresses
    type addr_arr_t is array (natural range <>) of natural;
    type data_arr_t is array (natural range <>) of natural;

    constant N_SAMPLES : natural := 32;

    -- 30 scattered addresses + 0 and DEPTH-1 boundaries = 32 samples
    function build_addrs return addr_arr_t is
        variable a : addr_arr_t(0 to N_SAMPLES - 1);
    begin
        a(0) := 0;
        a(1) := DEPTH - 1;
        for i in 2 to N_SAMPLES - 1 loop
            a(i) := ((i * 2477) + i) mod DEPTH;
        end loop;
        return a;
    end function build_addrs;

    function build_data(addrs : addr_arr_t) return data_arr_t is
        variable d : data_arr_t(addrs'range);
    begin
        for i in addrs'range loop
            d(i) := (addrs(i) * 37 + i * 11 + 5) mod 256;
        end loop;
        return d;
    end function build_data;

    constant TEST_ADDRS : addr_arr_t(0 to N_SAMPLES - 1) := build_addrs;
    constant TEST_DATA  : data_arr_t(0 to N_SAMPLES - 1)  := build_data(TEST_ADDRS);

    -- An address intentionally never written (for the default/zero content test)
    constant UNTOUCHED_ADDR : natural := DEPTH / 2 + 3;

begin

    ----------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------
    dut : entity work.fb_ram
        generic map (
            FB_W => FB_W,
            FB_H => FB_H
        )
        port map (
            clk_a_i  => clk_a_i,
            we_a_i   => we_a_i,
            addr_a_i => addr_a_i,
            din_a_i  => din_a_i,
            dout_a_o => dout_a_o,

            clk_b_i  => clk_b_i,
            addr_b_i => addr_b_i,
            dout_b_o => dout_b_o
        );

    ----------------------------------------------------------------------
    -- Clock generation (two independent processes - two clock domains)
    ----------------------------------------------------------------------
    clk_a_gen : process
    begin
        while not sim_done loop
            clk_a_i <= '0';
            wait for CLK_A_PERIOD / 2;
            clk_a_i <= '1';
            wait for CLK_A_PERIOD / 2;
        end loop;
        wait;
    end process clk_a_gen;

    clk_b_gen : process
    begin
        while not sim_done loop
            clk_b_i <= '0';
            wait for CLK_B_PERIOD / 2;
            clk_b_i <= '1';
            wait for CLK_B_PERIOD / 2;
        end loop;
        wait;
    end process clk_b_gen;

    ----------------------------------------------------------------------
    -- Main test sequence
    ----------------------------------------------------------------------
    stimulus : process
        variable err_cnt : natural := 0;
        variable exp      : std_logic_vector(7 downto 0);
    begin
        wait until rising_edge(clk_a_i);
        wait until rising_edge(clk_a_i);

        ------------------------------------------------------------------
        -- Step 1: write the TEST_ADDRS/TEST_DATA set via Port A
        ------------------------------------------------------------------
        for i in 0 to N_SAMPLES - 1 loop
            wait until rising_edge(clk_a_i);
            we_a_i   <= '1';
            addr_a_i <= to_unsigned(TEST_ADDRS(i), 17);
            din_a_i  <= std_logic_vector(to_unsigned(TEST_DATA(i), 8));
        end loop;
        wait until rising_edge(clk_a_i);
        we_a_i <= '0';

        ------------------------------------------------------------------
        -- Step 2: read back via Port A (1-cycle sync read latency) and verify
        ------------------------------------------------------------------
        for i in 0 to N_SAMPLES - 1 loop
            wait until rising_edge(clk_a_i);
            addr_a_i <= to_unsigned(TEST_ADDRS(i), 17);
            wait until rising_edge(clk_a_i);
            -- wait past the falling edge for delta-cycles to settle, else
            -- the previous read's value is observed instead
            wait until falling_edge(clk_a_i);
            exp := std_logic_vector(to_unsigned(TEST_DATA(i), 8));
            if dout_a_o /= exp then
                err_cnt := err_cnt + 1;
                report "tb_fb_ram: FAIL - Port A okuma, adr=" & integer'image(TEST_ADDRS(i)) &
                       " beklenen=" & integer'image(to_integer(unsigned(exp))) &
                       " gozlenen=" & integer'image(to_integer(unsigned(dout_a_o)))
                    severity error;
            end if;
        end loop;

        ------------------------------------------------------------------
        -- Step 3: read same addresses via Port B (different clock domain),
        -- verify cross-port visibility
        ------------------------------------------------------------------
        for i in 0 to N_SAMPLES - 1 loop
            wait until rising_edge(clk_b_i);
            addr_b_i <= to_unsigned(TEST_ADDRS(i), 17);
            wait until rising_edge(clk_b_i);
            wait until falling_edge(clk_b_i);
            exp := std_logic_vector(to_unsigned(TEST_DATA(i), 8));
            if dout_b_o /= exp then
                err_cnt := err_cnt + 1;
                report "tb_fb_ram: FAIL - Port B okuma, adr=" & integer'image(TEST_ADDRS(i)) &
                       " beklenen=" & integer'image(to_integer(unsigned(exp))) &
                       " gozlenen=" & integer'image(to_integer(unsigned(dout_b_o)))
                    severity error;
            end if;
        end loop;

        ------------------------------------------------------------------
        -- Step 4: an address never written must return default (zero) via Port B
        ------------------------------------------------------------------
        wait until rising_edge(clk_b_i);
        addr_b_i <= to_unsigned(UNTOUCHED_ADDR, 17);
        wait until rising_edge(clk_b_i);
        wait until falling_edge(clk_b_i);
        if dout_b_o /= x"00" then
            err_cnt := err_cnt + 1;
            report "tb_fb_ram: FAIL - bakir adres " & integer'image(UNTOUCHED_ADDR) &
                   " sifir degil, gozlenen=" & integer'image(to_integer(unsigned(dout_b_o)))
                severity error;
        end if;

        ------------------------------------------------------------------
        -- Step 5: explicitly re-verify boundary addresses (0 and DEPTH-1)
        -- via Port A and Port B
        ------------------------------------------------------------------
        wait until rising_edge(clk_a_i);
        addr_a_i <= to_unsigned(0, 17);
        wait until rising_edge(clk_a_i);
        wait until falling_edge(clk_a_i);
        exp := std_logic_vector(to_unsigned(TEST_DATA(0), 8));
        if dout_a_o /= exp then
            err_cnt := err_cnt + 1;
            report "tb_fb_ram: FAIL - sinir adresi 0 (Port A) beklenen=" &
                   integer'image(to_integer(unsigned(exp))) & " gozlenen=" &
                   integer'image(to_integer(unsigned(dout_a_o)))
                severity error;
        end if;

        wait until rising_edge(clk_b_i);
        addr_b_i <= to_unsigned(DEPTH - 1, 17);
        wait until rising_edge(clk_b_i);
        wait until falling_edge(clk_b_i);
        exp := std_logic_vector(to_unsigned(TEST_DATA(1), 8));
        if dout_b_o /= exp then
            err_cnt := err_cnt + 1;
            report "tb_fb_ram: FAIL - sinir adresi " & integer'image(DEPTH - 1) &
                   " (Port B) beklenen=" & integer'image(to_integer(unsigned(exp))) &
                   " gozlenen=" & integer'image(to_integer(unsigned(dout_b_o)))
                severity error;
        end if;

        ------------------------------------------------------------------
        -- Result
        ------------------------------------------------------------------
        if err_cnt = 0 then
            report "tb_fb_ram: PASS - " & integer'image(N_SAMPLES) &
                   " dagitik adres + sinir adresleri + bakir adres, Port A ve Port B uzerinden dogrulandi"
                severity note;
        else
            report "tb_fb_ram: FAIL - " & integer'image(err_cnt) & " hata bulundu" severity failure;
        end if;

        sim_done <= true;
        wait for CLK_A_PERIOD;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
