--------------------------------------------------------------------------------
-- axi_lite_bfm.vhd
--
-- Minimal AXI4-Lite master BFM: axi_write/axi_read each perform one
-- transaction over the standard 5-channel handshake (AW/W/B, AR/R).
-- Assumes a single in-order master against an otherwise-idle DUT
-- (no pipelining), matching how this project's CPU polls the register bus.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package axi_lite_bfm is

    procedure axi_write (
        signal clk     : in  std_logic;
        signal awaddr  : out std_logic_vector;
        signal awvalid : out std_logic;
        signal awready : in  std_logic;
        signal wdata   : out std_logic_vector;
        signal wstrb   : out std_logic_vector;
        signal wvalid  : out std_logic;
        signal wready  : in  std_logic;
        signal bvalid  : in  std_logic;
        signal bready  : out std_logic;
        constant addr  : in  std_logic_vector;
        constant data  : in  std_logic_vector
    );

    procedure axi_read (
        signal clk     : in  std_logic;
        signal araddr  : out std_logic_vector;
        signal arvalid : out std_logic;
        signal arready : in  std_logic;
        signal rdata   : in  std_logic_vector;
        signal rvalid  : in  std_logic;
        signal rready  : out std_logic;
        constant addr  : in  std_logic_vector;
        variable data  : out std_logic_vector
    );

end package axi_lite_bfm;

package body axi_lite_bfm is

    procedure axi_write (
        signal clk     : in  std_logic;
        signal awaddr  : out std_logic_vector;
        signal awvalid : out std_logic;
        signal awready : in  std_logic;
        signal wdata   : out std_logic_vector;
        signal wstrb   : out std_logic_vector;
        signal wvalid  : out std_logic;
        signal wready  : in  std_logic;
        signal bvalid  : in  std_logic;
        signal bready  : out std_logic;
        constant addr  : in  std_logic_vector;
        constant data  : in  std_logic_vector
    ) is
    begin
        -- bready stays permanently high: console_gpu_axi.vhd clears bvalid
        -- one cycle after asserting it, so dropping bready as soon as
        -- bvalid is seen would make the DUT's clear check miss it and
        -- latch bvalid high forever.
        --
        -- Drain any bvalid left over from the previous call first, so this
        -- procedure is safe to call back-to-back and awready/wready below
        -- are genuinely high (DUT idle), not a stale pre-transaction value.
        bready <= '1';
        if bvalid /= '0' then
            wait until bvalid = '0';
        end if;

        awaddr  <= addr;
        awvalid <= '1';
        wdata   <= data;
        wstrb   <= (wstrb'range => '1');
        wvalid  <= '1';

        -- One clock edge is enough: the DUT is confirmed idle (drain
        -- above), so awready/wready are already high with nothing else
        -- contending for the bus. Not polled, since the same signal means
        -- both "ready for new data" and "busy with what was just given".
        wait until rising_edge(clk);
        awvalid <= '0';
        wvalid  <= '0';

        -- Watched directly (not clock-gated): console_gpu_axi.vhd relays
        -- bvalid through an internal signal (VHDL-93 can't read its own
        -- `out` ports), adding an extra delta cycle a clock-edge poll
        -- could miss.
        if bvalid /= '1' then
            wait until bvalid = '1';
        end if;
    end procedure axi_write;

    procedure axi_read (
        signal clk     : in  std_logic;
        signal araddr  : out std_logic_vector;
        signal arvalid : out std_logic;
        signal arready : in  std_logic;
        signal rdata   : in  std_logic_vector;
        signal rvalid  : in  std_logic;
        signal rready  : out std_logic;
        constant addr  : in  std_logic_vector;
        variable data  : out std_logic_vector
    ) is
    begin
        -- Same reasoning as axi_write: rready stays high, stale rvalid is
        -- drained first, one clock edge suffices, rvalid watched directly.
        rready <= '1';
        if rvalid /= '0' then
            wait until rvalid = '0';
        end if;

        araddr  <= addr;
        arvalid <= '1';

        wait until rising_edge(clk);
        arvalid <= '0';

        if rvalid /= '1' then
            wait until rvalid = '1';
        end if;
        data := rdata;
    end procedure axi_read;

end package body axi_lite_bfm;
