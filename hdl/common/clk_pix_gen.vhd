--------------------------------------------------------------------------------
-- clk_pix_gen.vhd
--
-- Pixel clock generator: 100 MHz -> 25.155 MHz (VGA 640x480@60 nominally
-- needs 25.175 MHz; the 0.08% error is within monitor tolerance).
-- MMCME2_BASE is instantiated directly as local components (keeps this
-- file VHDL-93) instead of via the Clocking Wizard IP.
-- SIM_MODE substitutes a plain clock divider for simulation; SIM_DIV=1
-- makes clk_pix = clk_sys for fast full-frame testbenches.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity clk_pix_gen is
    generic (
        SIM_MODE : boolean  := false;
        SIM_DIV  : positive := 4
    );
    port (
        clk_sys_i : in  std_logic;  -- 100 MHz (W5)
        clk_pix_o : out std_logic;  -- 25.155 MHz
        locked_o  : out std_logic   -- '1' = clock stable
    );
end entity clk_pix_gen;

architecture rtl of clk_pix_gen is

    component MMCME2_BASE is
        generic (
            BANDWIDTH          : string  := "OPTIMIZED";
            CLKFBOUT_MULT_F    : real    := 5.0;
            CLKFBOUT_PHASE     : real    := 0.0;
            CLKIN1_PERIOD      : real    := 0.0;
            CLKOUT0_DIVIDE_F   : real    := 1.0;
            CLKOUT0_DUTY_CYCLE : real    := 0.5;
            CLKOUT0_PHASE      : real    := 0.0;
            DIVCLK_DIVIDE      : integer := 1;
            REF_JITTER1        : real    := 0.0;
            STARTUP_WAIT       : boolean := false
        );
        port (
            CLKOUT0   : out std_logic;
            CLKOUT0B  : out std_logic;
            CLKOUT1   : out std_logic;
            CLKOUT1B  : out std_logic;
            CLKOUT2   : out std_logic;
            CLKOUT2B  : out std_logic;
            CLKOUT3   : out std_logic;
            CLKOUT3B  : out std_logic;
            CLKOUT4   : out std_logic;
            CLKOUT5   : out std_logic;
            CLKOUT6   : out std_logic;
            CLKFBOUT  : out std_logic;
            CLKFBOUTB : out std_logic;
            LOCKED    : out std_logic;
            CLKIN1    : in  std_logic;
            PWRDWN    : in  std_logic;
            RST       : in  std_logic;
            CLKFBIN   : in  std_logic
        );
    end component MMCME2_BASE;

    component BUFG is
        port (
            O : out std_logic;
            I : in  std_logic
        );
    end component BUFG;

    function half_minus_one(d : positive) return natural is
    begin
        if d < 2 then
            return 0;
        else
            return d / 2 - 1;
        end if;
    end function half_minus_one;

    signal clk_fb_out  : std_logic;
    signal clk_fb_in   : std_logic;
    signal clk_pix_raw : std_logic;

begin

    hw_gen : if not SIM_MODE generate
    begin
        u_mmcm : MMCME2_BASE
            generic map (
                BANDWIDTH          => "OPTIMIZED",
                CLKFBOUT_MULT_F    => 10.125,
                CLKFBOUT_PHASE     => 0.0,
                CLKIN1_PERIOD      => 10.000,
                CLKOUT0_DIVIDE_F   => 40.250,
                CLKOUT0_DUTY_CYCLE => 0.5,
                CLKOUT0_PHASE      => 0.0,
                DIVCLK_DIVIDE      => 1,
                REF_JITTER1        => 0.010,
                STARTUP_WAIT       => false
            )
            port map (
                CLKOUT0   => clk_pix_raw,
                CLKOUT0B  => open,
                CLKOUT1   => open,
                CLKOUT1B  => open,
                CLKOUT2   => open,
                CLKOUT2B  => open,
                CLKOUT3   => open,
                CLKOUT3B  => open,
                CLKOUT4   => open,
                CLKOUT5   => open,
                CLKOUT6   => open,
                CLKFBOUT  => clk_fb_out,
                CLKFBOUTB => open,
                LOCKED    => locked_o,
                CLKIN1    => clk_sys_i,
                PWRDWN    => '0',
                RST       => '0',   -- tied low: locks at power-up; reset button
                                    -- resets the logic, not the clock
                CLKFBIN   => clk_fb_in
            );

        -- The feedback path must go through a BUFG as well, so that the BUFG
        -- delay on the output clock is compensated.
        u_bufg_fb  : BUFG port map (I => clk_fb_out,  O => clk_fb_in);
        u_bufg_pix : BUFG port map (I => clk_pix_raw, O => clk_pix_o);
    end generate hw_gen;

    sim_gen : if SIM_MODE generate
        constant TOGGLE_AT : natural := half_minus_one(SIM_DIV);
        signal div_cnt  : natural   := 0;
        signal clk_div  : std_logic := '0';
        signal lock_cnt : natural   := 0;
        signal locked_s : std_logic := '0';
    begin
        div_proc : process (clk_sys_i)
        begin
            if rising_edge(clk_sys_i) then
                if div_cnt >= TOGGLE_AT then
                    div_cnt <= 0;
                    clk_div <= not clk_div;
                else
                    div_cnt <= div_cnt + 1;
                end if;

                if lock_cnt < 16 then
                    lock_cnt <= lock_cnt + 1;
                else
                    locked_s <= '1';
                end if;
            end if;
        end process div_proc;

        clk_pix_o <= clk_sys_i when SIM_DIV = 1 else clk_div;
        locked_o  <= locked_s;
    end generate sim_gen;

end architecture rtl;
