--------------------------------------------------------------------------------
-- tb_console_gpu_axi.vhd
--
-- Testbench for console_gpu_axi.vhd, driven through axi_lite_bfm's
-- axi_write/axi_read procedures. Exercises all four regions (PAL/GPU/
-- BLT/COLL) plus VBLANK bookkeeping and a read-only-register no-op write.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
library work;
use work.axi_lite_bfm.all;

entity tb_console_gpu_axi is
end entity tb_console_gpu_axi;

architecture sim of tb_console_gpu_axi is

    constant CLK_PERIOD : time := 10 ns;
    constant N_OBJ : positive := 64;

    signal clk   : std_logic := '0';
    signal resetn : std_logic := '0';

    signal awaddr  : std_logic_vector(13 downto 0) := (others => '0');
    signal awvalid : std_logic := '0';
    signal awready : std_logic;
    signal wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb   : std_logic_vector(3 downto 0) := (others => '0');
    signal wvalid  : std_logic := '0';
    signal wready  : std_logic;
    signal bresp   : std_logic_vector(1 downto 0);
    signal bvalid  : std_logic;
    signal bready  : std_logic := '0';

    signal araddr  : std_logic_vector(13 downto 0) := (others => '0');
    signal arvalid : std_logic := '0';
    signal arready : std_logic;
    signal rdata   : std_logic_vector(31 downto 0);
    signal rresp   : std_logic_vector(1 downto 0);
    signal rvalid  : std_logic;
    signal rready  : std_logic := '0';

    signal vblank : std_logic := '0';

    signal pal_wr_en  : std_logic;
    signal pal_wr_idx : unsigned(7 downto 0);
    signal pal_wr_rgb : std_logic_vector(11 downto 0);

    signal blt_start : std_logic;
    signal blt_op    : std_logic_vector(1 downto 0);
    signal blt_x, blt_y, blt_w, blt_h : unsigned(9 downto 0);
    signal blt_src   : std_logic_vector(16 downto 0);
    signal blt_color, blt_key : std_logic_vector(7 downto 0);
    signal blt_key_en : std_logic;
    signal blt_busy  : std_logic := '0';

    signal coll_we    : std_logic;
    signal coll_idx   : unsigned(5 downto 0);
    signal coll_x, coll_y : signed(10 downto 0);
    signal coll_w, coll_h : unsigned(7 downto 0);
    signal coll_en    : std_logic;
    signal coll_qry   : unsigned(5 downto 0);
    signal coll_hit   : std_logic_vector(N_OBJ - 1 downto 0) := (others => '0');

    signal errors : integer := 0;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.console_gpu_axi
        generic map (N_OBJ => N_OBJ)
        port map (
            s_axi_aclk => clk, s_axi_aresetn => resetn,
            s_axi_awaddr => awaddr, s_axi_awvalid => awvalid, s_axi_awready => awready,
            s_axi_wdata => wdata, s_axi_wstrb => wstrb, s_axi_wvalid => wvalid, s_axi_wready => wready,
            s_axi_bresp => bresp, s_axi_bvalid => bvalid, s_axi_bready => bready,
            s_axi_araddr => araddr, s_axi_arvalid => arvalid, s_axi_arready => arready,
            s_axi_rdata => rdata, s_axi_rresp => rresp, s_axi_rvalid => rvalid, s_axi_rready => rready,
            vblank_i => vblank,
            pal_wr_en_o => pal_wr_en, pal_wr_idx_o => pal_wr_idx, pal_wr_rgb_o => pal_wr_rgb,
            blt_cmd_start_o => blt_start, blt_cmd_op_o => blt_op,
            blt_cmd_x_o => blt_x, blt_cmd_y_o => blt_y, blt_cmd_w_o => blt_w, blt_cmd_h_o => blt_h,
            blt_cmd_src_o => blt_src, blt_cmd_color_o => blt_color, blt_cmd_key_o => blt_key,
            blt_cmd_key_en_o => blt_key_en,
            blt_busy_i => blt_busy,
            coll_obj_we_o => coll_we, coll_obj_idx_o => coll_idx,
            coll_obj_x_o => coll_x, coll_obj_y_o => coll_y, coll_obj_w_o => coll_w, coll_obj_h_o => coll_h,
            coll_obj_en_o => coll_en, coll_qry_idx_o => coll_qry, coll_hit_mask_i => coll_hit
        );

    stim : process
        variable errs : integer := 0;
        variable rd : std_logic_vector(31 downto 0);

        procedure check(cond : boolean; tag : string) is
        begin
            if not cond then
                errs := errs + 1;
                report "ERROR: " & tag severity error;
            end if;
        end procedure check;

        procedure wr(addr : integer; data : std_logic_vector(31 downto 0)) is
        begin
            axi_write(clk, awaddr, awvalid, awready, wdata, wstrb, wvalid, wready,
                      bvalid, bready, std_logic_vector(to_unsigned(addr, 14)), data);
        end procedure wr;

        procedure rd_reg(addr : integer; result : out std_logic_vector(31 downto 0)) is
        begin
            axi_read(clk, araddr, arvalid, arready, rdata, rvalid, rready,
                     std_logic_vector(to_unsigned(addr, 14)), result);
        end procedure rd_reg;

    begin
        wait for 5 * CLK_PERIOD;
        resetn <= '1';
        wait for 5 * CLK_PERIOD;

        ------------------------------------------------------------------
        -- T1: palette write (region 00) - address encodes the index
        ------------------------------------------------------------------
        wr(16#0000# + 5 * 4, x"00000ABC"); -- idx 5, rgb 0xABC
        wait for 1 ps;
        check(pal_wr_en = '1', "pal_wr_en_o did not pulse on a palette write");
        check(to_integer(pal_wr_idx) = 5, "pal_wr_idx_o != 5");
        check(pal_wr_rgb = x"ABC", "pal_wr_rgb_o != 0xABC");
        wait until rising_edge(clk);
        wait for 1 ps;
        check(pal_wr_en = '0', "pal_wr_en_o did not return to a 1-cycle pulse");

        ------------------------------------------------------------------
        -- T2: GPU region - VBLANK sticky flag + frame counter
        ------------------------------------------------------------------
        rd_reg(16#1000#, rd);
        check(rd(0) = '0', "GPU_STATUS bit0 set before any VBLANK");

        vblank <= '1';
        wait for 3 * CLK_PERIOD;
        vblank <= '0';
        wait for 5 * CLK_PERIOD; -- let the 2FF sync + edge-detect settle

        rd_reg(16#1000#, rd);
        check(rd(0) = '1', "GPU_STATUS bit0 not set after a VBLANK pulse");
        rd_reg(16#1004#, rd);
        check(to_integer(unsigned(rd)) = 1, "GPU_FRAME_CNT != 1 after one VBLANK");

        wr(16#1000#, x"00000000"); -- any write clears the sticky bit
        rd_reg(16#1000#, rd);
        check(rd(0) = '0', "GPU_STATUS bit0 not cleared by a write");

        ------------------------------------------------------------------
        -- T3: BLT region - all six write registers + status readback
        ------------------------------------------------------------------
        wr(16#2004#, std_logic_vector(to_unsigned(0, 12)) & std_logic_vector(to_unsigned(50, 10)) & std_logic_vector(to_unsigned(30, 10))); -- DST: y=50,x=30
        wait for 1 ps;
        check(to_integer(blt_x) = 30, "blt_cmd_x_o != 30");
        check(to_integer(blt_y) = 50, "blt_cmd_y_o != 50");

        wr(16#2008#, std_logic_vector(to_unsigned(0, 12)) & std_logic_vector(to_unsigned(8, 10)) & std_logic_vector(to_unsigned(16, 10))); -- SIZE: h=8,w=16
        wait for 1 ps;
        check(to_integer(blt_w) = 16, "blt_cmd_w_o != 16");
        check(to_integer(blt_h) = 8, "blt_cmd_h_o != 8");

        wr(16#200C#, std_logic_vector(to_unsigned(0, 15)) & std_logic_vector(to_unsigned(12345, 17)));
        wait for 1 ps;
        check(to_integer(unsigned(blt_src)) = 12345, "blt_cmd_src_o != 12345");

        wr(16#2010#, x"000000AA");
        wait for 1 ps;
        check(blt_color = x"AA", "blt_cmd_color_o != 0xAA");

        wr(16#2014#, x"00000055");
        wait for 1 ps;
        check(blt_key = x"55", "blt_cmd_key_o != 0x55");

        wr(16#2000#, std_logic_vector(to_unsigned(11, 32))); -- CTRL: bit0=start=1, bits[2:1]=op="01" (BLIT), bit3=key_en=1 -> value 11
        wait for 1 ps;
        check(blt_start = '1', "blt_cmd_start_o did not pulse on CTRL write");
        check(blt_op = "01", "blt_cmd_op_o != 01");
        check(blt_key_en = '1', "blt_cmd_key_en_o != 1 from CTRL bit3");
        wait until rising_edge(clk);
        wait for 1 ps;
        check(blt_start = '0', "blt_cmd_start_o did not return to a 1-cycle pulse");
        check(blt_key_en = '1', "blt_cmd_key_en_o (not a pulse) should stay latched high");

        wr(16#2000#, std_logic_vector(to_unsigned(1, 32))); -- CTRL: start=1, op="00" (FILL), key_en=0
        wait for 1 ps;
        check(blt_key_en = '0', "blt_cmd_key_en_o != 0 after a CTRL write with bit3=0");

        blt_busy <= '1';
        rd_reg(16#2018#, rd);
        check(rd(0) = '1', "BLT_STATUS bit0 did not reflect blt_busy_i='1'");
        blt_busy <= '0';
        wait for 1 ps;
        rd_reg(16#2018#, rd);
        check(rd(0) = '0', "BLT_STATUS bit0 did not reflect blt_busy_i='0'");

        -- read-only register write must be a harmless no-op, not a fault
        wr(16#2018#, x"FFFFFFFF");
        wait for 1 ps;
        check(bresp = "00", "write to a read-only BLT_STATUS did not get an OKAY response");
        rd_reg(16#2018#, rd);
        check(rd(0) = '0', "writing BLT_STATUS changed its read-back value");

        ------------------------------------------------------------------
        -- T4: COLL region - two-word object write, query index, hit mask readback
        ------------------------------------------------------------------
        -- object 3, word0: en=1, y=-5, x=100 (bit31=en, [26:16]=y, [10:0]=x, rest don't-care)
        wr(16#3000# + 3 * 8 + 0,
           '1' & "0000" & std_logic_vector(to_signed(-5, 11)) & "00000" & std_logic_vector(to_signed(100, 11)));
        wait for 1 ps;
        check(coll_we = '1', "coll_obj_we_o did not pulse on word0 write");
        check(to_integer(coll_idx) = 3, "coll_obj_idx_o != 3");
        check(coll_en = '1', "coll_obj_en_o != 1 from word0");
        check(to_integer(coll_x) = 100, "coll_obj_x_o != 100");
        check(to_integer(coll_y) = -5, "coll_obj_y_o != -5");

        -- object 3, word1: h=12, w=20
        wr(16#3000# + 3 * 8 + 4, x"00000C14"); -- h=0x0C=12, w=0x14=20
        wait for 1 ps;
        check(coll_we = '1', "coll_obj_we_o did not pulse on word1 write");
        check(to_integer(coll_w) = 20, "coll_obj_w_o != 20");
        check(to_integer(coll_h) = 12, "coll_obj_h_o != 12");
        -- word1 write must combine with word0's already-latched fields
        check(coll_en = '1', "coll_obj_en_o lost on word1 write");
        check(to_integer(coll_x) = 100, "coll_obj_x_o lost on word1 write");
        check(to_integer(coll_y) = -5, "coll_obj_y_o lost on word1 write");

        wr(16#3200#, std_logic_vector(to_unsigned(3, 32)));
        wait for 1 ps;
        check(to_integer(coll_qry) = 3, "coll_qry_idx_o != 3");

        coll_hit <= x"00000000DEADBEEF"; -- arbitrary pattern for both 32-bit words
        wait for 1 ps;
        rd_reg(16#3204#, rd);
        check(rd = x"DEADBEEF", "HIT_MASK_LO != coll_hit_mask_i(31 downto 0)");
        rd_reg(16#3208#, rd);
        check(rd = x"00000000", "HIT_MASK_HI != coll_hit_mask_i(63 downto 32)");

        ------------------------------------------------------------------
        -- T5: back-to-back transactions - FSM resets correctly each time
        ------------------------------------------------------------------
        for i in 0 to 4 loop
            wr(16#0000# + i * 4, std_logic_vector(to_unsigned(i, 32)));
            wait for 1 ps;
            check(to_integer(pal_wr_idx) = i, "back-to-back palette write #" & integer'image(i) & " lost its index");
            check(pal_wr_rgb = std_logic_vector(to_unsigned(i, 12)), "back-to-back palette write #" & integer'image(i) & " lost its data");
        end loop;

        ------------------------------------------------------------------
        errors <= errs;
        wait for CLK_PERIOD;

        if errs = 0 then
            report "tb_console_gpu_axi: PASS - palette/GPU(VBLANK+frame counter)/blitter(all 6 regs incl. CTRL's key_en bit+status+read-only no-op)/collision(two-word object+query+hit mask) regions and back-to-back AXI transactions all verified" severity note;
        else
            report "tb_console_gpu_axi: FAIL - " & integer'image(errs) & " error(s)" severity failure;
        end if;

        stop;
        wait;
    end process stim;

end architecture sim;
