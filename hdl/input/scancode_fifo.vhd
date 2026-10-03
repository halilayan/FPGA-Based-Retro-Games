--------------------------------------------------------------------------------
-- scancode_fifo.vhd
--
-- Synchronous, single-clock FIFO that buffers scan codes from ps2_rx
-- until the CPU reads them.
--
-- Simple counter-based circular buffer: read/write pointers plus an
-- element count. DEPTH must be a power of two (pointer wraparound relies
-- on it).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity scancode_fifo is
    generic (
        DEPTH : positive := 16;
        WIDTH : positive := 8
    );
    port (
        clk_i : in std_logic;
        rst_i : in std_logic;  -- synchronous reset, active-high

        wr_en_i   : in std_logic;
        wr_data_i : in std_logic_vector(WIDTH - 1 downto 0);

        rd_en_i   : in  std_logic;
        rd_data_o : out std_logic_vector(WIDTH - 1 downto 0);

        empty_o : out std_logic;
        full_o  : out std_logic
    );
end entity scancode_fifo;

architecture rtl of scancode_fifo is

    -- log2(DEPTH), hardcoded since DEPTH is always 16 here; update if DEPTH changes.
    constant PTR_BITS : positive := 4;

    type mem_t is array (0 to DEPTH - 1) of std_logic_vector(WIDTH - 1 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    signal wr_ptr : unsigned(PTR_BITS - 1 downto 0) := (others => '0');
    signal rd_ptr : unsigned(PTR_BITS - 1 downto 0) := (others => '0');
    signal count  : unsigned(PTR_BITS downto 0)     := (others => '0');  -- 0..DEPTH

    signal empty, full : std_logic;
    signal do_write, do_read : std_logic;

begin

    empty <= '1' when count = 0 else '0';
    full  <= '1' when count = DEPTH else '0';

    empty_o <= empty;
    full_o  <= full;

    -- Simultaneous write+read is allowed (count unchanged); full/empty
    -- only blocks the affected side.
    do_write <= '1' when (wr_en_i = '1') and (full = '0' or rd_en_i = '1') else '0';
    do_read  <= '1' when (rd_en_i = '1') and (empty = '0') else '0';

    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                wr_ptr <= (others => '0');
                rd_ptr <= (others => '0');
                count  <= (others => '0');
            else
                if do_write = '1' then
                    mem(to_integer(wr_ptr)) <= wr_data_i;
                    wr_ptr <= wr_ptr + 1;
                end if;

                if do_read = '1' then
                    rd_ptr <= rd_ptr + 1;
                end if;

                if do_write = '1' and do_read = '0' then
                    count <= count + 1;
                elsif do_write = '0' and do_read = '1' then
                    count <= count - 1;
                end if;
            end if;
        end if;
    end process;

    rd_data_o <= mem(to_integer(rd_ptr));

end architecture rtl;
