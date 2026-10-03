--------------------------------------------------------------------------------
-- collision.vhd
--
-- Hardware AABB (axis-aligned bounding box) collision table for up to
-- N_OBJ objects, loaded via obj_we/obj_idx/obj_x/obj_y/obj_w/obj_h/obj_en.
-- Each cycle, hit_mask reports which other enabled objects overlap
-- qry_idx's box (brute-force N-way compare, registered, 1-cycle latency).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity collision is
    generic (
        N_OBJ : positive := 64
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        obj_we  : in std_logic;
        obj_idx : in unsigned(5 downto 0);
        -- Signed: an object may be positioned partly or fully off-screen
        -- without the box math wrapping around.
        obj_x   : in signed(10 downto 0);
        obj_y   : in signed(10 downto 0);
        obj_w   : in unsigned(7 downto 0);
        obj_h   : in unsigned(7 downto 0);
        obj_en  : in std_logic;

        qry_idx  : in  unsigned(5 downto 0);
        hit_mask : out std_logic_vector(N_OBJ - 1 downto 0)
    );
end entity collision;

architecture rtl of collision is

    type x_array_t  is array (0 to N_OBJ - 1) of signed(10 downto 0);
    type wh_array_t is array (0 to N_OBJ - 1) of unsigned(7 downto 0);
    type en_array_t is array (0 to N_OBJ - 1) of std_logic;

    signal tbl_x, tbl_y   : x_array_t;
    signal tbl_w, tbl_h   : wh_array_t;
    signal tbl_en         : en_array_t := (others => '0');

    signal qry_idx_r : unsigned(5 downto 0);

begin

    -----------------------------------------------------------------------
    -- Object table write port.
    -----------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tbl_en <= (others => '0');
            elsif obj_we = '1' then
                tbl_x(to_integer(obj_idx))  <= obj_x;
                tbl_y(to_integer(obj_idx))  <= obj_y;
                tbl_w(to_integer(obj_idx))  <= obj_w;
                tbl_h(to_integer(obj_idx))  <= obj_h;
                tbl_en(to_integer(obj_idx)) <= obj_en;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- Query: registered qry_idx and hit_mask, so the wide N-way compare
    -- has a full cycle to settle at 100 MHz regardless of N_OBJ.
    -----------------------------------------------------------------------
    process (clk)
        variable ax, ay : signed(11 downto 0);
        variable aw, ah : unsigned(8 downto 0);
        variable bx, by : signed(11 downto 0);
        variable bw, bh : unsigned(8 downto 0);
        variable overlap : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                qry_idx_r <= (others => '0');
                hit_mask  <= (others => '0');
            else
                qry_idx_r <= qry_idx;

                ax := resize(tbl_x(to_integer(qry_idx)), 12);
                ay := resize(tbl_y(to_integer(qry_idx)), 12);
                aw := resize(tbl_w(to_integer(qry_idx)), 9);
                ah := resize(tbl_h(to_integer(qry_idx)), 9);

                for i in 0 to N_OBJ - 1 loop
                    bx := resize(tbl_x(i), 12);
                    by := resize(tbl_y(i), 12);
                    bw := resize(tbl_w(i), 9);
                    bh := resize(tbl_h(i), 9);

                    -- Standard AABB overlap test, half-open on the high edge
                    -- (boxes that only touch don't register a hit).
                    if tbl_en(to_integer(qry_idx)) = '1' and tbl_en(i) = '1' and i /= to_integer(qry_idx) and
                       ax < bx + signed(resize(bw, 12)) and bx < ax + signed(resize(aw, 12)) and
                       ay < by + signed(resize(bh, 12)) and by < ay + signed(resize(ah, 12)) then
                        overlap := '1';
                    else
                        overlap := '0';
                    end if;

                    hit_mask(i) <= overlap;
                end loop;
            end if;
        end if;
    end process;

end architecture rtl;
