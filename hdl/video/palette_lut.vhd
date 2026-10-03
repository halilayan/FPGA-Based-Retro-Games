--------------------------------------------------------------------------------
-- palette_lut.vhd
--
-- 256-entry color palette: converts an 8-bit color index to 12-bit RGB444
-- ({R[3:0],G[3:0],B[3:0]}). True dual-clock-domain module:
--   * Read side  (clk_pix_i) - video output, one index read per cycle
--   * Write side (clk_wr_i)  - CPU/AXI, can update the palette live
--
-- Default content is all-black (x"000") until a real palette is loaded.
-- Index 0 stays black, consistent with its use as the blitter's
-- transparency key.
--
-- Read is synchronous (1-cycle latency) -> infers as distributed RAM.
-- This latency is one of the cycles counted in video_out's PIPE_LAT.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity palette_lut is
    port (
        -- Read (video pipeline, clk_pix_i domain)
        clk_pix_i : in  std_logic;
        idx_i     : in  unsigned(7 downto 0);
        rgb_o     : out std_logic_vector(11 downto 0);

        -- Write (CPU/AXI domain, clk_wr_i - may differ from clk_pix_i)
        clk_wr_i : in  std_logic;
        wr_en_i  : in  std_logic;
        wr_idx_i : in  unsigned(7 downto 0);
        wr_rgb_i : in  std_logic_vector(11 downto 0)
    );
end entity palette_lut;

architecture rtl of palette_lut is

    type pal_t is array (0 to 255) of std_logic_vector(11 downto 0);

    signal palette : pal_t := (others => (others => '0'));

begin

    ----------------------------------------------------------------------
    -- Write (clk_wr_i domain)
    ----------------------------------------------------------------------
    write_proc : process (clk_wr_i)
    begin
        if rising_edge(clk_wr_i) then
            if wr_en_i = '1' then
                palette(to_integer(wr_idx_i)) <= wr_rgb_i;
            end if;
        end if;
    end process write_proc;

    ----------------------------------------------------------------------
    -- Read (clk_pix_i domain, synchronous - 1-cycle latency)
    ----------------------------------------------------------------------
    read_proc : process (clk_pix_i)
    begin
        if rising_edge(clk_pix_i) then
            rgb_o <= palette(to_integer(idx_i));
        end if;
    end process read_proc;

end architecture rtl;
