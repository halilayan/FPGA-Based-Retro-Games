--------------------------------------------------------------------------------
-- tb_axi_bram_byte_adapter.vhd
--
-- Testbench for axi_bram_byte_adapter. Fully combinational (no clock/
-- reset): for every single-byte bram_we_a lane, verifies cpu_we_o/
-- cpu_din_o select the correct byte and cpu_addr_o equals the word
-- address (bram_addr_a_i shifted up by 2) with the lane in the low 2 bits.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_axi_bram_byte_adapter is
end entity tb_axi_bram_byte_adapter;

architecture sim of tb_axi_bram_byte_adapter is

    constant ADDR_WIDTH : positive := 17;

    signal bram_we_a     : std_logic_vector(3 downto 0) := (others => '0');
    signal bram_addr_a   : std_logic_vector(ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal bram_wrdata_a : std_logic_vector(31 downto 0) := (others => '0');
    signal cpu_we        : std_logic;
    signal cpu_addr      : unsigned(ADDR_WIDTH - 1 downto 0);
    signal cpu_din       : std_logic_vector(7 downto 0);

    constant WRDATA : std_logic_vector(31 downto 0) := x"AABBCCDD";

begin

    dut : entity work.axi_bram_byte_adapter
        generic map (
            ADDR_WIDTH_G => ADDR_WIDTH
        )
        port map (
            bram_we_a_i     => bram_we_a,
            bram_addr_a_i   => bram_addr_a,
            bram_wrdata_a_i => bram_wrdata_a,
            cpu_we_o        => cpu_we,
            cpu_addr_o      => cpu_addr,
            cpu_din_o       => cpu_din
        );

    stimulus : process
        variable errors : natural := 0;

        procedure check(cond : in boolean; tag : in string) is
        begin
            if not cond then
                errors := errors + 1;
                report "ERROR: " & tag severity error;
            end if;
        end procedure check;
    begin
        bram_wrdata_a <= WRDATA;

        -- Non-zero word index (word 5) so a bug that passes bram_addr_a_i
        -- straight through (dropping the byte lane) is caught, not masked.
        bram_addr_a <= std_logic_vector(to_unsigned(5 * 4, ADDR_WIDTH));

        ------------------------------------------------------------------
        -- 1) Lane 0 (LSB) written -> we=1, din=0xDD, addr=20+0=20
        ------------------------------------------------------------------
        bram_we_a <= "0001";
        wait for 1 ns;
        check(cpu_we = '1', "lane0: cpu_we_o=0, expected 1");
        check(cpu_din = x"DD", "lane0: cpu_din_o=" & to_hstring(cpu_din) & ", expected 0xDD");
        check(cpu_addr = 20, "lane0: cpu_addr_o=" & integer'image(to_integer(cpu_addr)) & ", expected 20");

        ------------------------------------------------------------------
        -- 2) Lane 1 -> addr=20+1=21
        ------------------------------------------------------------------
        bram_we_a <= "0010";
        wait for 1 ns;
        check(cpu_we = '1', "lane1: cpu_we_o=0, expected 1");
        check(cpu_din = x"CC", "lane1: cpu_din_o=" & to_hstring(cpu_din) & ", expected 0xCC");
        check(cpu_addr = 21, "lane1: cpu_addr_o=" & integer'image(to_integer(cpu_addr)) & ", expected 21");

        ------------------------------------------------------------------
        -- 3) Lane 2 -> addr=20+2=22
        ------------------------------------------------------------------
        bram_we_a <= "0100";
        wait for 1 ns;
        check(cpu_we = '1', "lane2: cpu_we_o=0, expected 1");
        check(cpu_din = x"BB", "lane2: cpu_din_o=" & to_hstring(cpu_din) & ", expected 0xBB");
        check(cpu_addr = 22, "lane2: cpu_addr_o=" & integer'image(to_integer(cpu_addr)) & ", expected 22");

        ------------------------------------------------------------------
        -- 4) Lane 3 (MSB) -> addr=20+3=23
        ------------------------------------------------------------------
        bram_we_a <= "1000";
        wait for 1 ns;
        check(cpu_we = '1', "lane3: cpu_we_o=0, expected 1");
        check(cpu_din = x"AA", "lane3: cpu_din_o=" & to_hstring(cpu_din) & ", expected 0xAA");
        check(cpu_addr = 23, "lane3: cpu_addr_o=" & integer'image(to_integer(cpu_addr)) & ", expected 23");

        ------------------------------------------------------------------
        -- 5) No lane written -> we=0
        ------------------------------------------------------------------
        bram_we_a <= "0000";
        wait for 1 ns;
        check(cpu_we = '0', "we=0000: cpu_we_o=1, expected 0");

        ------------------------------------------------------------------
        -- 6) Different word index + data pattern, to rule out a coincidental pass
        ------------------------------------------------------------------
        bram_addr_a   <= std_logic_vector(to_unsigned(100 * 4, ADDR_WIDTH));
        bram_wrdata_a <= x"11223344";
        bram_we_a     <= "0001";
        wait for 1 ns;
        check(cpu_din = x"44", "second pattern lane0: cpu_din_o=" & to_hstring(cpu_din) & ", expected 0x44");
        check(cpu_addr = 400, "second pattern lane0: cpu_addr_o=" & integer'image(to_integer(cpu_addr)) & ", expected 400");

        bram_we_a <= "1000";
        wait for 1 ns;
        check(cpu_din = x"11", "second pattern lane3: cpu_din_o=" & to_hstring(cpu_din) & ", expected 0x11");
        check(cpu_addr = 403, "second pattern lane3: cpu_addr_o=" & integer'image(to_integer(cpu_addr)) & ", expected 403");

        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_axi_bram_byte_adapter: PASS - all 4 byte lanes' data AND reconstructed byte address (word*4 + lane) + we=0 case + cross-check with a second word/data pattern verified" severity note;
        else
            report "tb_axi_bram_byte_adapter: FAIL - " & integer'image(errors) & " error(s)" severity failure;
        end if;

        stop;
    end process stimulus;

end architecture sim;
