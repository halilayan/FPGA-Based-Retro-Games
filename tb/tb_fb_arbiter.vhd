--------------------------------------------------------------------------------
-- tb_fb_arbiter.vhd
--
-- Directed test for fb_arbiter: fixed priority order (blitter > cart > CPU)
-- holds in every combination, fb_we_o='0' when no writer is active, and the
-- CPU is never starved when it is the sole active requester.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_fb_arbiter is
end entity tb_fb_arbiter;

architecture sim of tb_fb_arbiter is

    signal cpu_we_i   : std_logic := '0';
    signal cpu_addr_i : unsigned(16 downto 0) := (others => '0');
    signal cpu_din_i  : std_logic_vector(7 downto 0) := (others => '0');

    signal blt_we_i   : std_logic := '0';
    signal blt_addr_i : unsigned(16 downto 0) := (others => '0');
    signal blt_din_i  : std_logic_vector(7 downto 0) := (others => '0');

    signal cart_we_i   : std_logic := '0';
    signal cart_addr_i : unsigned(16 downto 0) := (others => '0');
    signal cart_din_i  : std_logic_vector(7 downto 0) := (others => '0');

    signal fb_we_o   : std_logic;
    signal fb_addr_o : unsigned(16 downto 0);
    signal fb_din_o  : std_logic_vector(7 downto 0);

begin

    dut : entity work.fb_arbiter
        port map (
            cpu_we_i   => cpu_we_i,
            cpu_addr_i => cpu_addr_i,
            cpu_din_i  => cpu_din_i,

            blt_we_i   => blt_we_i,
            blt_addr_i => blt_addr_i,
            blt_din_i  => blt_din_i,

            cart_we_i   => cart_we_i,
            cart_addr_i => cart_addr_i,
            cart_din_i  => cart_din_i,

            fb_we_o   => fb_we_o,
            fb_addr_o => fb_addr_o,
            fb_din_o  => fb_din_o
        );

    stimulus : process
        variable errors : natural := 0;

        procedure check_route(msg      : string;
                               exp_we   : std_logic;
                               exp_addr : unsigned(16 downto 0);
                               exp_din  : std_logic_vector(7 downto 0)) is
        begin
            if fb_we_o /= exp_we then
                report "tb_fb_arbiter: FAIL - " & msg & " - fb_we_o beklenen=" &
                       std_logic'image(exp_we) & " gozlenen=" & std_logic'image(fb_we_o)
                    severity error;
                errors := errors + 1;
            end if;

            -- addr/data are not checked when we_o='0'
            if exp_we = '1' then
                if fb_addr_o /= exp_addr then
                    report "tb_fb_arbiter: FAIL - " & msg & " - fb_addr_o beklenen=" &
                           integer'image(to_integer(exp_addr)) & " gozlenen=" &
                           integer'image(to_integer(fb_addr_o))
                        severity error;
                    errors := errors + 1;
                end if;

                if fb_din_o /= exp_din then
                    report "tb_fb_arbiter: FAIL - " & msg & " - fb_din_o beklenen=" &
                           to_string(exp_din) & " gozlenen=" & to_string(fb_din_o)
                        severity error;
                    errors := errors + 1;
                end if;
            end if;
        end procedure check_route;
    begin
        -- 1) CPU only active -> cpu_* passes through
        cpu_we_i   <= '1';
        cpu_addr_i <= to_unsigned(100, 17);
        cpu_din_i  <= x"AA";
        blt_we_i   <= '0';
        cart_we_i  <= '0';
        wait for 1 ns;
        check_route("test1: sadece CPU", '1', to_unsigned(100, 17), x"AA");

        -- 2) Blitter only active -> blt_* passes through
        cpu_we_i   <= '0';
        blt_we_i   <= '1';
        blt_addr_i <= to_unsigned(200, 17);
        blt_din_i  <= x"BB";
        cart_we_i  <= '0';
        wait for 1 ns;
        check_route("test2: sadece blitter", '1', to_unsigned(200, 17), x"BB");

        -- 3) Cart only active -> cart_* passes through
        cpu_we_i    <= '0';
        blt_we_i    <= '0';
        cart_we_i   <= '1';
        cart_addr_i <= to_unsigned(300, 17);
        cart_din_i  <= x"CC";
        wait for 1 ns;
        check_route("test3: sadece kartus", '1', to_unsigned(300, 17), x"CC");

        -- 4) CPU + blitter simultaneously -> blitter wins (priority test)
        cpu_we_i   <= '1';
        cpu_addr_i <= to_unsigned(111, 17);
        cpu_din_i  <= x"11";
        blt_we_i   <= '1';
        blt_addr_i <= to_unsigned(222, 17);
        blt_din_i  <= x"22";
        cart_we_i  <= '0';
        wait for 1 ns;
        check_route("test4: CPU+blitter, blitter kazanmali", '1', to_unsigned(222, 17), x"22");

        -- 5) Cart + CPU simultaneously (no blitter) -> cart wins
        blt_we_i    <= '0';
        cpu_we_i    <= '1';
        cpu_addr_i  <= to_unsigned(333, 17);
        cpu_din_i   <= x"33";
        cart_we_i   <= '1';
        cart_addr_i <= to_unsigned(444, 17);
        cart_din_i  <= x"44";
        wait for 1 ns;
        check_route("test5: kartus+CPU, kartus kazanmali", '1', to_unsigned(444, 17), x"44");

        -- Extra: all three active at once -> blitter still wins
        blt_we_i   <= '1';
        blt_addr_i <= to_unsigned(555, 17);
        blt_din_i  <= x"55";
        wait for 1 ns;
        check_route("test5b: CPU+kartus+blitter, blitter kazanmali", '1', to_unsigned(555, 17), x"55");

        -- 6) All three idle -> fb_we_o='0'
        cpu_we_i  <= '0';
        blt_we_i  <= '0';
        cart_we_i <= '0';
        wait for 1 ns;
        check_route("test6: hicbir yazici aktif degil", '0', (others => '0'), (others => '0'));

        -- 7) No starvation: CPU as sole active requester always passes through
        blt_we_i  <= '0';
        cart_we_i <= '0';
        for i in 0 to 9 loop
            cpu_we_i   <= '1';
            cpu_addr_i <= to_unsigned(1000 + i * 37, 17);
            cpu_din_i  <= std_logic_vector(to_unsigned(i * 17 mod 256, 8));
            wait for 1 ns;
            check_route("test7: starvation-yok adim " & integer'image(i),
                        '1', to_unsigned(1000 + i * 37, 17),
                        std_logic_vector(to_unsigned(i * 17 mod 256, 8)));
        end loop;

        -- Summary
        if errors = 0 then
            report "tb_fb_arbiter: PASS - oncelik sirasi (blitter>kartus>CPU), bos durum ve starvation-yok testleri dogrulandi"
                severity note;
        else
            report "tb_fb_arbiter: FAIL - " & integer'image(errors) & " hata bulundu" severity failure;
        end if;

        wait for 1 ns;
        std.env.stop;
        wait;
    end process stimulus;

end architecture sim;
