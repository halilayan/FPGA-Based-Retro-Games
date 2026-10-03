--------------------------------------------------------------------------------
-- vga_sync.vhd
--
-- VGA timing generator, 640x480 @ 60Hz, negative sync polarity. Adapted
-- from the user's existing VGA.vhd (same counter structure and timing
-- constants), ported to numeric_std.
--
-- All outputs (hsync/vsync/video_on/pix_x/pix_y) are combinational and
-- share the same pipeline stage with no added delay: hsync/vsync must stay
-- aligned with color data by the same number of cycles downstream, so they
-- are generated the same way as video_on/pix_x/pix_y rather than registered
-- separately.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_sync is
    generic (
        H_VISIBLE : positive := 640;
        H_FRONT   : positive := 16;
        H_SYNC    : positive := 96;
        H_BACK    : positive := 48;
        V_VISIBLE : positive := 480;
        V_FRONT   : positive := 10;
        V_SYNC    : positive := 2;
        V_BACK    : positive := 33
    );
    port (
        clk_pix_i : in  std_logic;
        rst_i     : in  std_logic;

        pix_x_o : out unsigned(9 downto 0);
        pix_y_o : out unsigned(9 downto 0);

        video_on_o : out std_logic;
        hsync_o    : out std_logic;
        vsync_o    : out std_logic;

        line_start_o  : out std_logic;  -- first cycle of each line (hcnt=0)
        frame_start_o : out std_logic   -- start of VBLANK (hcnt=0, vcnt=V_VISIBLE)
    );
end entity vga_sync;

architecture rtl of vga_sync is

    -- Max counter value; counter wraps to 0 here (counts H_TOTAL/V_TOTAL states)
    constant HM : natural := H_VISIBLE + H_FRONT + H_SYNC + H_BACK - 1;  -- 799
    constant VM : natural := V_VISIBLE + V_FRONT + V_SYNC + V_BACK - 1;  -- 524

    signal hcnt : unsigned(9 downto 0) := (others => '0');
    signal vcnt : unsigned(9 downto 0) := (others => '0');

begin

    ----------------------------------------------------------------------
    -- Horizontal/vertical pixel counters
    ----------------------------------------------------------------------
    process (clk_pix_i)
    begin
        if rising_edge(clk_pix_i) then
            if rst_i = '1' then
                hcnt <= (others => '0');
                vcnt <= (others => '0');
            elsif hcnt = HM then
                hcnt <= (others => '0');
                if vcnt = VM then
                    vcnt <= (others => '0');
                else
                    vcnt <= vcnt + 1;
                end if;
            else
                hcnt <= hcnt + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Combinational outputs - all in the same pipeline stage, no extra delay
    ----------------------------------------------------------------------
    pix_x_o <= hcnt;
    pix_y_o <= vcnt;

    video_on_o <= '1' when (hcnt < H_VISIBLE) and (vcnt < V_VISIBLE) else '0';

    -- Active-low sync pulses
    hsync_o <= '0' when (hcnt >= H_VISIBLE + H_FRONT) and
                         (hcnt <= H_VISIBLE + H_FRONT + H_SYNC - 1)
               else '1';

    vsync_o <= '0' when (vcnt >= V_VISIBLE + V_FRONT) and
                         (vcnt <= V_VISIBLE + V_FRONT + V_SYNC - 1)
               else '1';

    line_start_o <= '1' when hcnt = 0 else '0';

    -- Fires once at the start of VBLANK (entering row V_VISIBLE), giving the
    -- CPU a ~45-line (1.44 ms) window to update VRAM during blanking.
    frame_start_o <= '1' when (hcnt = 0) and (vcnt = V_VISIBLE) else '0';

end architecture rtl;
