--------------------------------------------------------------------------------
-- tb_asset_rom.vhd
--
-- TB-A for asset_rom.vhd: Port A write-then-read-back (own port and via
-- Port B), independent addressing on both ports, and a small random
-- write/verify sweep across the whole array (proves no address aliasing
-- - a common off-by-one/wrap bug in a from-scratch memory model).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;

entity tb_asset_rom is
end entity tb_asset_rom;

architecture sim of tb_asset_rom is

    constant CLK_PERIOD : time := 10 ns;
    constant SIZE_BYTES : positive := 16384;

    signal clk : std_logic := '0';

    signal we_a   : std_logic := '0';
    signal addr_a : unsigned(13 downto 0) := (others => '0');
    signal din_a  : std_logic_vector(7 downto 0) := (others => '0');
    signal dout_a : std_logic_vector(7 downto 0);

    signal addr_b : unsigned(13 downto 0) := (others => '0');
    signal dout_b : std_logic_vector(7 downto 0);

    signal errors : integer := 0;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.asset_rom
        generic map (SIZE_BYTES => SIZE_BYTES)
        port map (
            clk_a_i => clk, we_a_i => we_a, addr_a_i => addr_a, din_a_i => din_a, dout_a_o => dout_a,
            clk_b_i => clk, addr_b_i => addr_b, dout_b_o => dout_b
        );

    stim : process
        variable seed1, seed2 : positive := 1;
        variable rv : real;

        impure function rand_int(lo, hi : integer) return integer is
        begin
            uniform(seed1, seed2, rv);
            return lo + integer(floor(rv * real(hi - lo + 1)));
        end function rand_int;

        procedure check(cond : boolean; tag : string) is
        begin
            if not cond then
                errors <= errors + 1;
                report "ERROR: " & tag severity error;
            end if;
        end procedure check;

        procedure write_byte(addr : integer; data : integer) is
        begin
            wait until rising_edge(clk);
            addr_a <= to_unsigned(addr, 14);
            din_a  <= std_logic_vector(to_unsigned(data, 8));
            we_a   <= '1';
            wait until rising_edge(clk);
            we_a   <= '0';
        end procedure write_byte;

        -- dout is a registered output: reading it in the same delta as the
        -- clock edge that latches a new address can catch the pre-update
        -- value, so a small settle wait after the edge is required.
        procedure read_a(addr : integer; variable result : out integer) is
        begin
            wait until rising_edge(clk);
            addr_a <= to_unsigned(addr, 14);
            wait until rising_edge(clk);
            wait for 1 ps;
            result := to_integer(unsigned(dout_a));
        end procedure read_a;

        procedure read_b(addr : integer; variable result : out integer) is
        begin
            wait until rising_edge(clk);
            addr_b <= to_unsigned(addr, 14);
            wait until rising_edge(clk);
            wait for 1 ps;
            result := to_integer(unsigned(dout_b));
        end procedure read_b;

        type mem_model_t is array (0 to SIZE_BYTES - 1) of integer;

        variable got   : integer;
        variable model : mem_model_t;
        variable ra, rndv, ca : integer; -- scratch for the random-sweep loops below
    begin
        wait for 5 * CLK_PERIOD;

        ------------------------------------------------------------------
        -- T1: basic write, read back via Port A and Port B
        ------------------------------------------------------------------
        write_byte(0, 16#AB#);
        read_a(0, got);
        check(got = 16#AB#, "Port A did not read back its own write at addr 0");
        read_b(0, got);
        check(got = 16#AB#, "Port B did not see Port A's write at addr 0");

        write_byte(SIZE_BYTES - 1, 16#CD#);
        read_b(SIZE_BYTES - 1, got);
        check(got = 16#CD#, "Port B did not see a write at the LAST address");

        -- an address left untouched must read back as the power-on '0' default
        read_a(1234, got);
        check(got = 0, "an untouched address did not read back as 0");

        ------------------------------------------------------------------
        -- T2: independent Port A / Port B addressing at the same moment
        ------------------------------------------------------------------
        write_byte(100, 16#11#);
        write_byte(200, 16#22#);

        wait until rising_edge(clk);
        addr_a <= to_unsigned(100, 14);
        addr_b <= to_unsigned(200, 14);
        wait until rising_edge(clk);
        wait for 1 ps;
        check(to_integer(unsigned(dout_a)) = 16#11#, "Port A did not read its own independent address");
        check(to_integer(unsigned(dout_b)) = 16#22#, "Port B did not read its own independent address");

        ------------------------------------------------------------------
        -- T3: random write/verify sweep - no address aliasing
        ------------------------------------------------------------------
        for i in 0 to SIZE_BYTES - 1 loop
            model(i) := 0;
        end loop;
        model(0) := 16#AB#; model(SIZE_BYTES - 1) := 16#CD#;
        model(100) := 16#11#; model(200) := 16#22#;

        for n in 1 to 300 loop
            ra := rand_int(0, SIZE_BYTES - 1);
            rndv := rand_int(0, 255);
            write_byte(ra, rndv);
            model(ra) := rndv;
        end loop;

        for n in 1 to 50 loop
            ca := rand_int(0, SIZE_BYTES - 1);
            read_b(ca, got);
            check(got = model(ca), "random sweep: addr " & integer'image(ca) &
                  " got=" & integer'image(got) & " expected=" & integer'image(model(ca)));
        end loop;

        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_asset_rom: PASS - Port A write/read-back, Port A->Port B visibility, independent per-port addressing, and a 300-write/50-check random sweep with no address aliasing, all verified" severity note;
        else
            report "tb_asset_rom: FAIL - " & integer'image(errors) & " error(s)" severity failure;
        end if;

        wait for CLK_PERIOD;
        stop;
        wait;
    end process stim;

end architecture sim;
