--------------------------------------------------------------------------------
-- ps2_bfm.vhd
--
-- PS/2 device bus-functional model used by tb_ps2_rx: drives ps2_clk/ps2_data
-- the way a real PS/2 keyboard would.
-- Frame format (matches ps2_rx.vhd): 11 bits, LSB first,
-- [0]=start('0') [8:1]=D0..D7 [9]=odd parity [10]=stop('1').
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ps2_bfm is

    -- half bit period (full period = 2x -> ~16.7 kHz, realistic PS/2 rate)
    constant PS2_HALF_PERIOD_DEFAULT : time := 30 us;

    -- setup time before the sampling (falling) edge
    constant PS2_SETUP_TIME_DEFAULT : time := 5 us;

    -- Sends one PS/2 frame. bad_parity/bad_stop inject a corrupt frame.
    -- stall_after_bit (0..9) stops the device mid-frame after that bit
    -- index, for testing ps2_rx's watchdog/timeout recovery.
    procedure ps2_send_frame(
        signal ps2_clk_o  : out std_logic;
        signal ps2_data_o : out std_logic;
        data              : in  std_logic_vector(7 downto 0);
        bad_parity        : in  boolean := false;
        bad_stop          : in  boolean := false;
        half_period       : in  time    := PS2_HALF_PERIOD_DEFAULT;
        setup_time        : in  time    := PS2_SETUP_TIME_DEFAULT;
        stall_after_bit   : in  integer := -1;
        stall_time        : in  time    := 0 us
    );

    -- Emits a short spurious clock edge outside any frame, to test ps2_rx's
    -- recovery (via its watchdog/timeout) from a false start bit.
    procedure ps2_send_glitch(
        signal ps2_clk_o  : out std_logic;
        signal ps2_data_o : out std_logic;
        glitch_width      : in time := 3 us
    );

    -- Idles both lines high (bus idle / pull-up state).
    procedure ps2_idle(
        signal ps2_clk_o  : out std_logic;
        signal ps2_data_o : out std_logic
    );

end package ps2_bfm;

package body ps2_bfm is

    procedure ps2_idle(
        signal ps2_clk_o  : out std_logic;
        signal ps2_data_o : out std_logic
    ) is
    begin
        ps2_clk_o  <= '1';
        ps2_data_o <= '1';
    end procedure ps2_idle;

    procedure ps2_send_frame(
        signal ps2_clk_o  : out std_logic;
        signal ps2_data_o : out std_logic;
        data              : in  std_logic_vector(7 downto 0);
        bad_parity        : in  boolean := false;
        bad_stop          : in  boolean := false;
        half_period       : in  time    := PS2_HALF_PERIOD_DEFAULT;
        setup_time        : in  time    := PS2_SETUP_TIME_DEFAULT;
        stall_after_bit   : in  integer := -1;
        stall_time        : in  time    := 0 us
    ) is
        variable frame  : std_logic_vector(10 downto 0);
        variable parity : std_logic;
    begin
        -- odd parity: inverted XOR-reduction of the data bits
        parity := not (xor data);
        if bad_parity then
            parity := not parity;
        end if;

        frame              := (others => '0');
        frame(0)           := '0';      -- start bit
        frame(8 downto 1)  := data;     -- D0..D7, sent LSB first
        frame(9)           := parity;
        if bad_stop then
            frame(10) := '0';           -- stop bit forced low (bad_stop test)
        else
            frame(10) := '1';
        end if;

        for i in 0 to 10 loop
            -- data must settle before the falling (sampling) edge
            ps2_data_o <= frame(i);
            wait for setup_time;

            ps2_clk_o <= '0';           -- falling edge: receiver samples here
            wait for half_period;
            ps2_clk_o <= '1';
            wait for half_period;

            if i = stall_after_bit then
                -- simulate the device stalling mid-frame: no more edges,
                -- return without completing the frame
                ps2_clk_o  <= '1';
                ps2_data_o <= '1';
                wait for stall_time;
                return;
            end if;
        end loop;

        ps2_clk_o  <= '1';
        ps2_data_o <= '1';
    end procedure ps2_send_frame;

    procedure ps2_send_glitch(
        signal ps2_clk_o  : out std_logic;
        signal ps2_data_o : out std_logic;
        glitch_width      : in time := 3 us
    ) is
    begin
        ps2_data_o <= '1';
        ps2_clk_o  <= '0';
        wait for glitch_width;
        ps2_clk_o  <= '1';
    end procedure ps2_send_glitch;

end package body ps2_bfm;
