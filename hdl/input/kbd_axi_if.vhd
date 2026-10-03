--------------------------------------------------------------------------------
-- kbd_axi_if.vhd
--
-- Bridges the existing ps2_rx + scancode_fifo modules to an AXI GPIO so the
-- CPU can read scan codes.
--
-- AXI GPIO channels are simple level registers, not single-cycle pulses, but
-- scancode_fifo's rd_en_i pops one entry on every cycle it sees '1'. If the
-- CPU's GPIO write held rd_strobe_i high for more than one clk_i cycle (it
-- always will, since an AXI write is far slower than 10 ns), the FIFO would
-- be popped many times per intended read. rd_strobe_i is therefore rising-
-- edge detected here into a single-cycle pulse.
--
-- Expected software handshake (see sw/libconsole/port/hw.c):
--   1) poll empty_o; if '0', a byte is available in data_o
--   2) write GPIO output bit to '1' (pop one entry)
--   3) write GPIO output bit back to '0' (arms the next rising edge)
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kbd_axi_if is
    generic (
        CLK_HZ : positive := 100_000_000
    );
    port (
        clk_i : in std_logic;
        rst_i : in std_logic;  -- synchronous, active high

        ps2_clk_i  : in std_logic;
        ps2_data_i : in std_logic;

        rd_strobe_i : in  std_logic;  -- level from an AXI GPIO output bit
        data_o      : out std_logic_vector(7 downto 0);
        empty_o     : out std_logic
    );
end entity kbd_axi_if;

architecture rtl of kbd_axi_if is

    signal rx_data  : std_logic_vector(7 downto 0);
    signal rx_valid : std_logic;

    signal rd_strobe_d1 : std_logic := '0';
    signal rd_en_pulse   : std_logic;

begin

    u_ps2_rx : entity work.ps2_rx
        generic map (CLK_HZ => CLK_HZ)
        port map (
            clk_i        => clk_i,
            rst_i        => rst_i,
            ps2_clk_i    => ps2_clk_i,
            ps2_data_i   => ps2_data_i,
            rx_data_o    => rx_data,
            rx_valid_o   => rx_valid,
            parity_err_o => open,
            frame_err_o  => open
        );

    -- Rising-edge detect on the GPIO strobe -> exactly one FIFO pop per edge.
    edge_detect : process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                rd_strobe_d1 <= '0';
            else
                rd_strobe_d1 <= rd_strobe_i;
            end if;
        end if;
    end process edge_detect;

    rd_en_pulse <= rd_strobe_i and (not rd_strobe_d1);

    u_scancode_fifo : entity work.scancode_fifo
        generic map (DEPTH => 16, WIDTH => 8)
        port map (
            clk_i     => clk_i,
            rst_i     => rst_i,
            wr_en_i   => rx_valid,
            wr_data_i => rx_data,
            rd_en_i   => rd_en_pulse,
            rd_data_o => data_o,
            empty_o   => empty_o,
            full_o    => open
        );

end architecture rtl;
