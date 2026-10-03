--------------------------------------------------------------------------------
-- tb_palette_lut.vhd
--
-- Testbench for palette_lut.vhd: default content (all black), write/read
-- across two clock domains (7 ns / 40 ns, intentionally asynchronous),
-- write isolation between indices, and same-index read/write collision.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_palette_lut is
end entity tb_palette_lut;

architecture sim of tb_palette_lut is

    constant CLK_WR_PERIOD  : time := 7 ns;
    constant CLK_PIX_PERIOD : time := 40 ns;

    signal clk_pix_i : std_logic := '0';
    signal clk_wr_i  : std_logic := '0';

    signal idx_i    : unsigned(7 downto 0) := (others => '0');
    signal rgb_o    : std_logic_vector(11 downto 0);
    signal wr_en_i  : std_logic := '0';
    signal wr_idx_i : unsigned(7 downto 0) := (others => '0');
    signal wr_rgb_i : std_logic_vector(11 downto 0) := (others => '0');

    signal sim_done : boolean := false;

    -- err_count is a variable (not a signal), so updates apply immediately -
    -- no delta-cycle risk across repeated calls
    procedure check_rgb(
        actual    : in std_logic_vector(11 downto 0);
        expected  : in std_logic_vector(11 downto 0);
        tag       : in string;
        variable err_count : inout natural
    ) is
    begin
        if actual /= expected then
            report "tb_palette_lut: FAIL - " & tag &
                   " beklenen=" & to_hstring(unsigned(expected)) &
                   " gozlenen=" & to_hstring(unsigned(actual))
                severity error;
            err_count := err_count + 1;
        end if;
    end procedure;

begin

    dut : entity work.palette_lut
        port map (
            clk_pix_i => clk_pix_i,
            idx_i     => idx_i,
            rgb_o     => rgb_o,
            clk_wr_i  => clk_wr_i,
            wr_en_i   => wr_en_i,
            wr_idx_i  => wr_idx_i,
            wr_rgb_i  => wr_rgb_i
        );

    clk_pix_gen : process
    begin
        while not sim_done loop
            clk_pix_i <= '0'; wait for CLK_PIX_PERIOD / 2;
            clk_pix_i <= '1'; wait for CLK_PIX_PERIOD / 2;
        end loop;
        wait;
    end process clk_pix_gen;

    clk_wr_gen : process
    begin
        while not sim_done loop
            clk_wr_i <= '0'; wait for CLK_WR_PERIOD / 2;
            clk_wr_i <= '1'; wait for CLK_WR_PERIOD / 2;
        end loop;
        wait;
    end process clk_wr_gen;

    stimulus : process
        variable errors : natural := 0;
    begin
        ------------------------------------------------------------------
        -- 1) Default content: entire table should be black (x"000")
        ------------------------------------------------------------------
        idx_i <= to_unsigned(0, 8);
        wait until rising_edge(clk_pix_i);
        wait until rising_edge(clk_pix_i);  -- 1 cevrim okuma gecikmesi icin ekstra bekle
        check_rgb(rgb_o, x"000", "varsayilan idx=0", errors);

        idx_i <= to_unsigned(255, 8);
        wait until rising_edge(clk_pix_i);
        wait until rising_edge(clk_pix_i);
        check_rgb(rgb_o, x"000", "varsayilan idx=255", errors);

        idx_i <= to_unsigned(128, 8);
        wait until rising_edge(clk_pix_i);
        wait until rising_edge(clk_pix_i);
        check_rgb(rgb_o, x"000", "varsayilan idx=128", errors);

        ------------------------------------------------------------------
        -- 2) Write (clk_wr_i) + read (clk_pix_i) across different clock domains
        ------------------------------------------------------------------
        wait until rising_edge(clk_wr_i);
        wr_idx_i <= to_unsigned(10, 8);
        wr_rgb_i <= x"F0A";
        wr_en_i  <= '1';
        wait until rising_edge(clk_wr_i);
        wr_en_i <= '0';

        -- wait enough clk_pix_i cycles for a safe margin across the async boundary
        for i in 1 to 4 loop
            wait until rising_edge(clk_pix_i);
        end loop;
        idx_i <= to_unsigned(10, 8);
        wait until rising_edge(clk_pix_i);
        wait until rising_edge(clk_pix_i);
        check_rgb(rgb_o, x"F0A", "yazma sonrasi idx=10", errors);

        ------------------------------------------------------------------
        -- 3) Write isolation: neighboring indices must remain unaffected (still black)
        ------------------------------------------------------------------
        idx_i <= to_unsigned(9, 8);
        wait until rising_edge(clk_pix_i);
        wait until rising_edge(clk_pix_i);
        check_rgb(rgb_o, x"000", "komsu idx=9 (bozulmamis olmali)", errors);

        idx_i <= to_unsigned(11, 8);
        wait until rising_edge(clk_pix_i);
        wait until rising_edge(clk_pix_i);
        check_rgb(rgb_o, x"000", "komsu idx=11 (bozulmamis olmali)", errors);

        ------------------------------------------------------------------
        -- 4) Near-simultaneous write+read collision on the same index - a
        --    consistent (new) value must be readable a few cycles later
        ------------------------------------------------------------------
        idx_i <= to_unsigned(200, 8);
        wait until rising_edge(clk_wr_i);
        wr_idx_i <= to_unsigned(200, 8);
        wr_rgb_i <= x"123";
        wr_en_i  <= '1';
        wait until rising_edge(clk_wr_i);
        wr_en_i <= '0';

        for i in 1 to 6 loop
            wait until rising_edge(clk_pix_i);
        end loop;
        wait until rising_edge(clk_pix_i);
        check_rgb(rgb_o, x"123", "collision sonrasi idx=200", errors);

        ------------------------------------------------------------------
        -- Summary
        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_palette_lut: PASS - varsayilan icerik, yazma/okuma, izolasyon ve collision testleri dogrulandi"
                severity note;
        else
            report "tb_palette_lut: FAIL - " & integer'image(errors) & " hata bulundu" severity failure;
        end if;

        sim_done <= true;
        wait for 1 ns;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
