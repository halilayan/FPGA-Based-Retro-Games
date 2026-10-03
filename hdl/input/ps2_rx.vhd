--------------------------------------------------------------------------------
-- ps2_rx.vhd
--
-- PS/2 receive-only module: captures 11-bit frames (start + 8 data bits
-- LSB-first + odd parity + stop) from a keyboard. Does not transmit.
--
-- ps2_clk_i/ps2_data_i are asynchronous external signals; each is brought
-- into clk_i via its own sync_2ff instance (INIT='1', since both lines
-- idle high) to avoid metastability. The falling edge used to sample each
-- bit is detected synchronously, by comparing clk_s against its registered
-- previous value, rather than clocking logic directly off ps2_clk_i.
--
-- A watchdog silently returns to idle if no falling edge arrives for
-- ~100us (CLK_HZ/10_000 cycles) mid-frame, so a stuck or dropped clock
-- edge can't permanently hang the receiver. rx_valid_o pulses only on a
-- frame that passes both parity and start/stop checks.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ps2_rx is
    generic (
        CLK_HZ : positive := 100_000_000  -- clk_i frequency, for the watchdog counter
    );
    port (
        clk_i : in  std_logic;   -- 100 MHz system clock
        rst_i : in  std_logic;   -- synchronous reset, active-high

        ps2_clk_i  : in  std_logic;  -- external, pulled up on-board
        ps2_data_i : in  std_logic;  -- external, pulled up on-board

        rx_data_o    : out std_logic_vector(7 downto 0);  -- received byte
        rx_valid_o   : out std_logic;  -- one-cycle pulse, only on a valid (parity+frame ok) frame
        parity_err_o : out std_logic;  -- one-cycle pulse on a parity error
        frame_err_o  : out std_logic   -- one-cycle pulse on a bad start/stop bit
    );
end entity ps2_rx;

architecture rtl of ps2_rx is

    -- ~100us timeout: silently reset to idle if stuck mid-frame
    constant TIMEOUT : natural := CLK_HZ / 10_000;

    -- synchronized (metastability-safe) ps2 lines
    signal clk_s, data_s : std_logic;

    -- one-cycle-delayed copy of clk_s, used to detect its falling edge synchronously
    signal clk_s_d : std_logic := '1';
    signal falling : std_logic;

    -- frame shift register: [0]=start [8:1]=D0..D7 [9]=parity [10]=stop
    signal shreg  : std_logic_vector(10 downto 0) := (others => '0');
    signal bitcnt : integer range 0 to 10       := 0;
    signal wdog   : integer range 0 to TIMEOUT  := 0;

begin

    ----------------------------------------------------------------------
    -- Metastability synchronization: one sync_2ff instance per line
    ----------------------------------------------------------------------
    u_sync_clk : entity work.sync_2ff
        generic map (
            INIT => '1'  -- line idles high
        )
        port map (
            clk_i  => clk_i,
            din_i  => ps2_clk_i,
            dout_o => clk_s
        );

    u_sync_data : entity work.sync_2ff
        generic map (
            INIT => '1'  -- line idles high
        )
        port map (
            clk_i  => clk_i,
            din_i  => ps2_data_i,
            dout_o => data_s
        );

    ----------------------------------------------------------------------
    -- Falling-edge detection in the synchronous domain (no direct use of
    -- the external clock): a falling edge is clk_s = '1' last cycle,
    -- '0' now.
    ----------------------------------------------------------------------
    edge_reg : process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                clk_s_d <= '1';
            else
                clk_s_d <= clk_s;
            end if;
        end if;
    end process edge_reg;

    falling <= '1' when (clk_s_d = '1' and clk_s = '0') else '0';

    ----------------------------------------------------------------------
    -- Frame assembly + parity/start/stop check + watchdog
    ----------------------------------------------------------------------
    rx_proc : process (clk_i)
        -- Value shreg will hold after this cycle's shift. Since a signal
        -- assignment isn't visible until the next cycle, the stop-bit
        -- check below reads next_shreg (not shreg) to avoid an off-by-one.
        variable next_shreg   : std_logic_vector(10 downto 0);
        variable parity_calc  : std_logic;
    begin
        if rising_edge(clk_i) then
            -- one-cycle pulse outputs: default low, set '1' below if needed
            rx_valid_o   <= '0';
            parity_err_o <= '0';
            frame_err_o  <= '0';

            if rst_i = '1' then
                shreg  <= (others => '0');
                bitcnt <= 0;
                wdog   <= 0;
            else
                ------------------------------------------------------------
                -- Watchdog: return to idle if no new falling edge arrives
                -- for ~100us while mid-frame (bitcnt /= 0).
                ------------------------------------------------------------
                if bitcnt /= 0 then
                    if wdog = TIMEOUT then
                        bitcnt <= 0;
                        wdog   <= 0;
                    else
                        wdog <= wdog + 1;
                    end if;
                end if;

                ------------------------------------------------------------
                -- New bit: falling edge on the synchronized clock
                ------------------------------------------------------------
                if falling = '1' then
                    wdog <= 0;

                    next_shreg := data_s & shreg(10 downto 1);  -- shift in LSB-first
                    shreg      <= next_shreg;

                    if bitcnt = 10 then
                        -- 11th bit (stop) arrived on this edge; frame complete.
                        bitcnt <= 0;

                        -- Odd parity: XOR of the 8 data bits and the parity
                        -- bit must be '1'. Written as an explicit loop
                        -- because VHDL-93 has no unary reduction operator.
                        parity_calc := '0';
                        for b in 1 to 9 loop
                            parity_calc := parity_calc xor next_shreg(b);
                        end loop;

                        if next_shreg(0) /= '0' or next_shreg(10) /= '1' then
                            frame_err_o <= '1';
                        elsif parity_calc /= '1' then
                            parity_err_o <= '1';
                        else
                            rx_data_o  <= next_shreg(8 downto 1);
                            rx_valid_o <= '1';
                        end if;
                    else
                        bitcnt <= bitcnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process rx_proc;

end architecture rtl;
