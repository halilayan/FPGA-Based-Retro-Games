--------------------------------------------------------------------------------
-- tb_scancode_fifo.vhd
--
-- Self-checking testbench for scancode_fifo.vhd.
-- Verifies reset, fill/full, empty/full write-read protection, FIFO
-- ordering, and simultaneous read+write.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_scancode_fifo is
end entity tb_scancode_fifo;

architecture sim of tb_scancode_fifo is

    constant CLK_PERIOD : time := 10 ns;
    constant DEPTH      : positive := 16;
    constant WIDTH      : positive := 8;

    signal clk_i     : std_logic := '0';
    signal rst_i     : std_logic := '1';
    signal wr_en_i   : std_logic := '0';
    signal wr_data_i : std_logic_vector(WIDTH - 1 downto 0) := (others => '0');
    signal rd_en_i   : std_logic := '0';
    signal rd_data_o : std_logic_vector(WIDTH - 1 downto 0);
    signal empty_o   : std_logic;
    signal full_o    : std_logic;

    signal sim_done : boolean := false;

begin

    dut : entity work.scancode_fifo
        generic map (
            DEPTH => DEPTH,
            WIDTH => WIDTH
        )
        port map (
            clk_i     => clk_i,
            rst_i     => rst_i,
            wr_en_i   => wr_en_i,
            wr_data_i => wr_data_i,
            rd_en_i   => rd_en_i,
            rd_data_o => rd_data_o,
            empty_o   => empty_o,
            full_o    => full_o
        );

    clk_gen : process
    begin
        while not sim_done loop
            clk_i <= '0'; wait for CLK_PERIOD / 2;
            clk_i <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_gen;

    stimulus : process
        variable errors : natural := 0;

        procedure check(cond : in boolean; tag : in string) is
        begin
            if not cond then
                report "tb_scancode_fifo: FAIL - " & tag severity error;
                errors := errors + 1;
            end if;
        end procedure;
    begin
        ------------------------------------------------------------------
        -- 1) Must be empty after reset
        ------------------------------------------------------------------
        rst_i <= '1';
        wait for CLK_PERIOD * 3;
        wait until rising_edge(clk_i);
        rst_i <= '0';
        wait until rising_edge(clk_i);

        check(empty_o = '1', "reset sonrasi empty_o='1' degil");
        check(full_o = '0', "reset sonrasi full_o='0' degil");

        ------------------------------------------------------------------
        -- 2) Write DEPTH elements, checking full_o after each write
        ------------------------------------------------------------------
        for i in 0 to DEPTH - 1 loop
            wr_data_i <= std_logic_vector(to_unsigned(i, WIDTH));
            wr_en_i   <= '1';
            wait until rising_edge(clk_i);
            wr_en_i <= '0';
            wait until rising_edge(clk_i);

            if i = DEPTH - 1 then
                check(full_o = '1', "DEPTH eleman sonrasi full_o='1' degil");
            else
                check(full_o = '0', "erken full_o='1' oldu (i=" & integer'image(i) & ")");
            end if;
            check(empty_o = '0', "yazmadan sonra empty_o hala '1' (i=" & integer'image(i) & ")");
        end loop;

        ------------------------------------------------------------------
        -- 3) A write attempt while full must be protected (no corruption)
        ------------------------------------------------------------------
        wr_data_i <= x"FF";
        wr_en_i   <= '1';
        wait until rising_edge(clk_i);
        wr_en_i <= '0';
        wait until rising_edge(clk_i);
        check(full_o = '1', "full iken fazladan yazmadan sonra hala full_o='1' degil");

        ------------------------------------------------------------------
        -- 4) Read DEPTH elements; must come back in order 0..DEPTH-1
        ------------------------------------------------------------------
        for i in 0 to DEPTH - 1 loop
            check(to_integer(unsigned(rd_data_o)) = i,
                  "okuma sirasi yanlis: beklenen " & integer'image(i) &
                  " gozlenen " & integer'image(to_integer(unsigned(rd_data_o))));
            rd_en_i <= '1';
            wait until rising_edge(clk_i);
            rd_en_i <= '0';
            wait until rising_edge(clk_i);
        end loop;

        check(empty_o = '1', "DEPTH eleman okunduktan sonra empty_o='1' degil");
        check(full_o = '0', "bosalttiktan sonra full_o hala '1'");

        ------------------------------------------------------------------
        -- 5) A read attempt while empty must not corrupt state
        ------------------------------------------------------------------
        rd_en_i <= '1';
        wait until rising_edge(clk_i);
        rd_en_i <= '0';
        wait until rising_edge(clk_i);
        check(empty_o = '1', "bos iken fazladan okumadan sonra hala empty_o='1' degil");

        ------------------------------------------------------------------
        -- 6) Simultaneous read+write in the same cycle must keep count
        --    unchanged and still return the oldest element
        ------------------------------------------------------------------
        for i in 0 to 3 loop
            wr_data_i <= std_logic_vector(to_unsigned(100 + i, WIDTH));
            wr_en_i   <= '1';
            wait until rising_edge(clk_i);
            wr_en_i <= '0';
            wait until rising_edge(clk_i);
        end loop;

        check(to_integer(unsigned(rd_data_o)) = 100, "es-zamanli test oncesi bas eleman yanlis");

        wr_data_i <= std_logic_vector(to_unsigned(200, WIDTH));
        wr_en_i   <= '1';
        rd_en_i   <= '1';
        wait until rising_edge(clk_i);
        wr_en_i <= '0';
        rd_en_i <= '0';
        wait until rising_edge(clk_i);

        check(to_integer(unsigned(rd_data_o)) = 101,
              "es-zamanli okuma+yazma sonrasi siradaki eleman yanlis");
        check(empty_o = '0' and full_o = '0', "es-zamanli okuma+yazma sonrasi durum bayraklari tutarsiz");

        ------------------------------------------------------------------
        -- Summary
        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_scancode_fifo: PASS - doldurma/bosaltma, siralama, tasma korumasi ve es-zamanli okuma+yazma dogrulandi"
                severity note;
        else
            report "tb_scancode_fifo: FAIL - " & integer'image(errors) & " hata bulundu" severity failure;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
