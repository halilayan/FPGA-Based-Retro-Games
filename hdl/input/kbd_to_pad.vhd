--------------------------------------------------------------------------------
-- kbd_to_pad.vhd
--
-- Small, temporary decoder: converts PS/2 scan code set 2 bytes from
-- ps2_rx into 4 press/release flags for a 2-player Pong (up/down per
-- paddle). A general keyboard map belongs in software; only 4 fixed keys
-- are tracked here.
--
-- Scan code set 2: a "make" (press) is the key's code by itself -> flag
-- '1'. A "break" (release) is 0xF0 followed by the key's code -> flag
-- '0'. 0xE0 (extended-key prefix, e.g. arrow keys) is not handled: none
-- of the 4 tracked keys are extended, so it never matches and is
-- harmlessly ignored.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kbd_to_pad is
    generic (
        SC_UP1   : std_logic_vector(7 downto 0) := x"1D";  -- W
        SC_DOWN1 : std_logic_vector(7 downto 0) := x"1B";  -- S
        SC_UP2   : std_logic_vector(7 downto 0) := x"44";  -- O
        SC_DOWN2 : std_logic_vector(7 downto 0) := x"4B"   -- L
    );
    port (
        clk_i      : in  std_logic;
        rst_i      : in  std_logic;   -- synchronous reset, active-high

        rx_data_i  : in  std_logic_vector(7 downto 0);  -- raw incoming PS/2 byte
        rx_valid_i : in  std_logic;                      -- rx_data_i valid this cycle (one-cycle pulse)

        up1_o   : out std_logic;   -- 1 = key pressed
        down1_o : out std_logic;
        up2_o   : out std_logic;
        down2_o : out std_logic
    );
end entity kbd_to_pad;

architecture rtl of kbd_to_pad is

    -- set after a 0xF0 break-prefix byte; cleared once the next byte is processed
    signal brk_pending : std_logic := '0';

begin

    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                up1_o       <= '0';
                down1_o     <= '0';
                up2_o       <= '0';
                down2_o     <= '0';
                brk_pending <= '0';
            elsif rx_valid_i = '1' then
                if brk_pending = '1' then
                    -- byte right after a 0xF0: release
                    brk_pending <= '0';
                    if rx_data_i = SC_UP1 then
                        up1_o <= '0';
                    elsif rx_data_i = SC_DOWN1 then
                        down1_o <= '0';
                    elsif rx_data_i = SC_UP2 then
                        up2_o <= '0';
                    elsif rx_data_i = SC_DOWN2 then
                        down2_o <= '0';
                    end if;
                    -- break of an untracked key (e.g. 0xF0+0x29) is silently ignored
                elsif rx_data_i = x"F0" then
                    -- break prefix seen; next byte will be a release
                    brk_pending <= '1';
                elsif rx_data_i = SC_UP1 then
                    up1_o <= '1';
                elsif rx_data_i = SC_DOWN1 then
                    down1_o <= '1';
                elsif rx_data_i = SC_UP2 then
                    up2_o <= '1';
                elsif rx_data_i = SC_DOWN2 then
                    down2_o <= '1';
                end if;
                -- other untracked bytes (including 0xE0) are silently ignored
            end if;
        end if;
    end process;

end architecture rtl;
