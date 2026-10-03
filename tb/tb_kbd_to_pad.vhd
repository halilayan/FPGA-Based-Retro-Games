--------------------------------------------------------------------------------
-- tb_kbd_to_pad.vhd
--
-- Self-checking testbench for kbd_to_pad. rx_data_i/rx_valid_i are driven
-- directly (this module works on already-decoded bytes, so no PS/2-level
-- BFM is needed); rx_valid_i is held '1' for exactly 1 cycle per byte.
--
-- Covers: key make/break, all 4 keys independently plus two held at once,
-- an untracked scancode leaving outputs untouched (and not misread as a
-- break prefix), 0xF0 + untracked code not clearing tracked flags, and a
-- mid-test reset clearing all outputs.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_kbd_to_pad is
end entity tb_kbd_to_pad;

architecture sim of tb_kbd_to_pad is

    constant CLK_PERIOD : time := 10 ns;

    -- DUT port isimleriyle birebir ayni (VHDL isimlendirme standardi)
    signal clk_i      : std_logic := '0';
    signal rst_i      : std_logic := '1';
    signal rx_data_i  : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid_i : std_logic := '0';
    signal up1_o      : std_logic;
    signal down1_o    : std_logic;
    signal up2_o      : std_logic;
    signal down2_o    : std_logic;

    signal sim_done : boolean := false;

    -- Izlenen 4 tarama kodu ile DUT'un varsayilan generic degerleri ayni
    -- (generic map verilmiyor, DUT'un kendi varsayilanlari kullaniliyor)
    constant SC_UP1   : std_logic_vector(7 downto 0) := x"1D";  -- W
    constant SC_DOWN1 : std_logic_vector(7 downto 0) := x"1B";  -- S
    constant SC_UP2   : std_logic_vector(7 downto 0) := x"44";  -- O
    constant SC_DOWN2 : std_logic_vector(7 downto 0) := x"4B";  -- L
    constant SC_UNTRACKED : std_logic_vector(7 downto 0) := x"29";  -- bosluk (space)
    constant SC_BREAK     : std_logic_vector(7 downto 0) := x"F0";

begin

    ----------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------
    dut : entity work.kbd_to_pad
        port map (
            clk_i      => clk_i,
            rst_i      => rst_i,
            rx_data_i  => rx_data_i,
            rx_valid_i => rx_valid_i,
            up1_o      => up1_o,
            down1_o    => down1_o,
            up2_o      => up2_o,
            down2_o    => down2_o
        );

    ----------------------------------------------------------------------
    -- Saat uretimi
    ----------------------------------------------------------------------
    clk_gen : process
    begin
        while not sim_done loop
            clk_i <= '0';
            wait for CLK_PERIOD / 2;
            clk_i <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_gen;

    ----------------------------------------------------------------------
    -- Uyarici + kendi kendini kontrol eden gozlemci
    ----------------------------------------------------------------------
    stimulus : process
        variable errors : natural := 0;

        procedure wait_cycles (n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk_i);
            end loop;
            -- DUT'un bu kenardaki senkron atamalarinin (delta-cycle) yerlesmesi
            -- icin kucuk gecikme.
            wait for 1 ns;
        end procedure wait_cycles;

        -- Tek bir ham PS/2 baytini, rx_valid_i'yi tam 1 cevrim '1' tutarak DUT'a besler.
        procedure send_byte (code : std_logic_vector(7 downto 0)) is
        begin
            rx_data_i  <= code;
            rx_valid_i <= '1';
            wait_cycles(1);
            rx_valid_i <= '0';
        end procedure send_byte;

        procedure check (cond : in boolean; tag : in string) is
        begin
            if not cond then
                report "tb_kbd_to_pad: FAIL - " & tag severity error;
                errors := errors + 1;
            end if;
        end procedure check;

    begin
        ------------------------------------------------------------------
        -- Baslangic: reset aktif, tum cikislar '0' olmali
        ------------------------------------------------------------------
        rst_i      <= '1';
        rx_valid_i <= '0';
        wait_cycles(3);

        check(up1_o = '0' and down1_o = '0' and up2_o = '0' and down2_o = '0',
              "reset sonrasi tum cikislar '0' degil");

        rst_i <= '0';
        wait_cycles(2);

        ------------------------------------------------------------------
        -- Test 1: W basma -> up1_o '1' olmali ve oyle kalmali
        ------------------------------------------------------------------
        send_byte(SC_UP1);
        check(up1_o = '1' and down1_o = '0' and up2_o = '0' and down2_o = '0',
              "Test1: W basildi ama up1_o '1' olmadi");

        wait_cycles(3);
        check(up1_o = '1', "Test1: up1_o basili durumda kalmadi");

        ------------------------------------------------------------------
        -- Test 2: W birakma (0xF0 sonra 0x1D) -> up1_o tekrar '0'
        ------------------------------------------------------------------
        send_byte(SC_BREAK);
        check(up1_o = '1', "Test2: 0xF0 tek basina up1_o'yu erken degistirdi");

        send_byte(SC_UP1);
        check(up1_o = '0' and down1_o = '0' and up2_o = '0' and down2_o = '0',
              "Test2: W birakildi ama up1_o '0' olmadi");

        ------------------------------------------------------------------
        -- Test 3: 4 tusun tamami bagimsiz basma/birakma + W ve O ayni anda
        ------------------------------------------------------------------
        -- S (down1) basma/birakma
        send_byte(SC_DOWN1);
        check(down1_o = '1' and up1_o = '0' and up2_o = '0' and down2_o = '0',
              "Test3: S basildi ama down1_o '1' olmadi");
        send_byte(SC_BREAK);
        send_byte(SC_DOWN1);
        check(down1_o = '0', "Test3: S birakildi ama down1_o '0' olmadi");

        -- O (up2) basma, W (up1) basiliyken - ikisi de ayni anda basili olmali
        send_byte(SC_UP2);
        check(up2_o = '1' and down1_o = '0' and down2_o = '0',
              "Test3: O basildi ama up2_o '1' olmadi");

        send_byte(SC_UP1);
        check(up1_o = '1' and up2_o = '1' and down1_o = '0' and down2_o = '0',
              "Test3: W ve O ayni anda basiliyken durum yanlis (ikisi de '1' olmali)");

        -- ikisini de birak
        send_byte(SC_BREAK);
        send_byte(SC_UP1);
        check(up1_o = '0' and up2_o = '1', "Test3: W birakildi ama up1_o '0' olmadi (up2_o etkilenmemeli)");

        send_byte(SC_BREAK);
        send_byte(SC_UP2);
        check(up1_o = '0' and up2_o = '0', "Test3: O birakildi ama up2_o '0' olmadi");

        -- L (down2) basma/birakma
        send_byte(SC_DOWN2);
        check(down2_o = '1' and up1_o = '0' and down1_o = '0' and up2_o = '0',
              "Test3: L basildi ama down2_o '1' olmadi");
        send_byte(SC_BREAK);
        send_byte(SC_DOWN2);
        check(down2_o = '0', "Test3: L birakildi ama down2_o '0' olmadi");

        ------------------------------------------------------------------
        -- Test 4: izlenmeyen kod (0x29, bosluk) hicbir cikisi etkilememeli
        -- ve break-prefix olarak da yanlis algilanmamali
        ------------------------------------------------------------------
        send_byte(SC_UNTRACKED);
        check(up1_o = '0' and down1_o = '0' and up2_o = '0' and down2_o = '0',
              "Test4: izlenmeyen kod cikislari etkiledi");

        -- 0x29 break-prefix olarak yanlis algilandiysa, bunu izleyen W make
        -- kodu bir "birakma" gibi islenir ve up1_o '0' kalirdi; dogru
        -- davranista bu normal bir BASMA olmali (up1_o -> '1').
        send_byte(SC_UP1);
        check(up1_o = '1',
              "Test4: izlenmeyen kod (0x29) yanlislikla break-prefix olarak islendi");
        send_byte(SC_BREAK);
        send_byte(SC_UP1);
        check(up1_o = '0', "Test4 temizlik: W birakilamadi");

        ------------------------------------------------------------------
        -- Test 5: 0xF0 + izlenmeyen kod (0xF0 0x29), W ve O basiliyken,
        -- hicbir izlenen bayragi hatali temizlememeli
        ------------------------------------------------------------------
        send_byte(SC_UP1);
        send_byte(SC_UP2);
        check(up1_o = '1' and up2_o = '1', "Test5 hazirlik: W ve O basilamadi");

        send_byte(SC_BREAK);
        send_byte(SC_UNTRACKED);
        check(up1_o = '1' and up2_o = '1' and down1_o = '0' and down2_o = '0',
              "Test5: 0xF0+izlenmeyen kod, basili tuslari hatali temizledi");

        -- temizlik: W ve O'yu birak
        send_byte(SC_BREAK);
        send_byte(SC_UP1);
        send_byte(SC_BREAK);
        send_byte(SC_UP2);
        check(up1_o = '0' and up2_o = '0', "Test5 temizlik: W/O birakilamadi");

        ------------------------------------------------------------------
        -- Test 6: test ortasinda reset, bazi tuslar basiliyken tum
        -- cikislari senkron olarak '0' yapmali
        ------------------------------------------------------------------
        send_byte(SC_UP1);
        send_byte(SC_DOWN2);
        check(up1_o = '1' and down2_o = '1', "Test6 hazirlik: W ve L basilamadi");

        rst_i <= '1';
        wait_cycles(1);
        check(up1_o = '0' and down1_o = '0' and up2_o = '0' and down2_o = '0',
              "Test6: calisirken reset uygulaninca cikislar '0' olmadi");
        rst_i <= '0';
        wait_cycles(1);

        ------------------------------------------------------------------
        if errors = 0 then
            report "tb_kbd_to_pad: PASS - basma/birakma, 4 tus bagimsiz+es zamanli, " &
                   "izlenmeyen kod ve reset davranisi dogrulandi" severity note;
        else
            report "tb_kbd_to_pad: FAIL - " & integer'image(errors) & " hata bulundu"
                severity failure;
        end if;

        sim_done <= true;
        wait_cycles(2);
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
