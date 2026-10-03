--------------------------------------------------------------------------------
-- console_gpu_axi.vhd
--
-- Single AXI4-Lite slave covering four console_gpu register regions,
-- decoded by address bits [13:12]:
--   00  Palette RAM      (1 KiB) - relayed to palette_lut.vhd
--   01  console_gpu regs (256 B) - VBLANK status, frame counter
--   10  Blitter regs     (256 B) - relayed to blitter.vhd
--   11  Collision regs   (1 KiB) - object table + query, relayed to collision.vhd
--
-- Read-only offsets and the palette region ignore writes rather than
-- erroring; AXI still returns a normal OKAY response.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity console_gpu_axi is
    generic (
        N_OBJ : positive := 64
    );
    port (
        s_axi_aclk    : in  std_logic;
        s_axi_aresetn : in  std_logic;

        s_axi_awaddr  : in  std_logic_vector(13 downto 0);
        s_axi_awvalid : in  std_logic;
        s_axi_awready : out std_logic;

        s_axi_wdata   : in  std_logic_vector(31 downto 0);
        s_axi_wstrb   : in  std_logic_vector(3 downto 0);
        s_axi_wvalid  : in  std_logic;
        s_axi_wready  : out std_logic;

        s_axi_bresp   : out std_logic_vector(1 downto 0);
        s_axi_bvalid  : out std_logic;
        s_axi_bready  : in  std_logic;

        s_axi_araddr  : in  std_logic_vector(13 downto 0);
        s_axi_arvalid : in  std_logic;
        s_axi_arready : out std_logic;

        s_axi_rdata   : out std_logic_vector(31 downto 0);
        s_axi_rresp   : out std_logic_vector(1 downto 0);
        s_axi_rvalid  : out std_logic;
        s_axi_rready  : in  std_logic;

        -- VBLANK: an ASYNCHRONOUS single-bit input (clk_pix domain,
        -- ~25 MHz, video_out.vhd's vblank_o) - synchronised internally.
        vblank_i : in std_logic;

        pal_wr_en_o  : out std_logic;
        pal_wr_idx_o : out unsigned(7 downto 0);
        pal_wr_rgb_o : out std_logic_vector(11 downto 0);

        blt_cmd_start_o : out std_logic;
        blt_cmd_op_o    : out std_logic_vector(1 downto 0);
        blt_cmd_x_o     : out unsigned(9 downto 0);
        blt_cmd_y_o     : out unsigned(9 downto 0);
        blt_cmd_w_o     : out unsigned(9 downto 0);
        blt_cmd_h_o     : out unsigned(9 downto 0);
        blt_cmd_src_o   : out std_logic_vector(16 downto 0);
        blt_cmd_color_o : out std_logic_vector(7 downto 0);
        blt_cmd_key_o   : out std_logic_vector(7 downto 0);
        -- Opaque vs. keyed blit: no palette value can be reserved as
        -- "never a valid sprite pixel", so opaque mode needs its own flag.
        blt_cmd_key_en_o : out std_logic;
        blt_busy_i      : in  std_logic;

        coll_obj_we_o  : out std_logic;
        coll_obj_idx_o : out unsigned(5 downto 0);
        coll_obj_x_o   : out signed(10 downto 0);
        coll_obj_y_o   : out signed(10 downto 0);
        coll_obj_w_o   : out unsigned(7 downto 0);
        coll_obj_h_o   : out unsigned(7 downto 0);
        coll_obj_en_o  : out std_logic;
        coll_qry_idx_o : out unsigned(5 downto 0);
        coll_hit_mask_i : in std_logic_vector(N_OBJ - 1 downto 0)
    );
end entity console_gpu_axi;

architecture rtl of console_gpu_axi is

    component sync_2ff is
        generic (INIT : std_logic := '0');
        port (
            clk_i  : in  std_logic;
            din_i  : in  std_logic;
            dout_o : out std_logic
        );
    end component sync_2ff;

    signal vblank_sync, vblank_sync_d : std_logic;
    signal vblank_pulse : std_logic; -- 1-cycle pulse in s_axi_aclk, rising edge of vblank_sync

    signal vblank_pending : std_logic := '0';
    -- Own counter incremented on each synchronised VBLANK pulse - not a
    -- cross-domain copy of video_out.vhd's counter, which would need a
    -- 32-bit bus sync and risk a torn value across bits.
    signal frame_cnt      : unsigned(31 downto 0) := (others => '0');

    -- Collision object table shadow: each object occupies two AXI words
    -- (written in either order); obj_we pulses on each write using the
    -- other word's current shadow value, so a lone write leaves that
    -- object's other fields at their previous value until both arrive.
    type coll_word0_t is array (0 to N_OBJ - 1) of std_logic_vector(31 downto 0);
    type coll_word1_t is array (0 to N_OBJ - 1) of std_logic_vector(31 downto 0);
    signal coll_w0 : coll_word0_t := (others => (others => '0'));
    signal coll_w1 : coll_word1_t := (others => (others => '0'));

    -- VHDL-93 can't read back an `out` port, so awready/wready/bvalid are
    -- kept as internal signals and copied out.
    signal aw_done, w_done : std_logic := '0';
    signal awaddr_r : std_logic_vector(13 downto 0);
    signal wdata_r  : std_logic_vector(31 downto 0);
    signal do_write : std_logic; -- 1-cycle pulse: both AW and W are ready to commit
    signal awready_i, wready_i, bvalid_i : std_logic := '0';

    -- AXI read channel handshake (same out-port-read restriction).
    signal ar_pending : std_logic := '0';
    signal araddr_r   : std_logic_vector(13 downto 0);
    signal arready_i, rvalid_i : std_logic := '0';

    -- Independent decode for read and write paths (not shared/muxed):
    -- AXI4-Lite's channels can have transactions in flight on the same
    -- cycle, so sharing one decode could leak the write address into the
    -- read path (or vice versa).
    signal wr_region : std_logic_vector(1 downto 0);
    signal wr_offset : std_logic_vector(11 downto 0);
    signal rd_region : std_logic_vector(1 downto 0);
    signal rd_offset : std_logic_vector(11 downto 0);

begin

    wr_region <= awaddr_r(13 downto 12);
    wr_offset <= awaddr_r(11 downto 0);
    rd_region <= araddr_r(13 downto 12);
    rd_offset <= araddr_r(11 downto 0);

    -----------------------------------------------------------------------
    -- VBLANK: 2FF synchroniser, then a 1-cycle pulse on its rising edge.
    -----------------------------------------------------------------------
    u_sync_vblank : sync_2ff
        generic map (INIT => '0')
        port map (clk_i => s_axi_aclk, din_i => vblank_i, dout_o => vblank_sync);

    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            vblank_sync_d <= vblank_sync;
        end if;
    end process;

    vblank_pulse <= vblank_sync and not vblank_sync_d;

    -----------------------------------------------------------------------
    -- AXI write channel: accept AW/W independently, commit once both have
    -- landed, one outstanding transaction at a time.
    -----------------------------------------------------------------------
    awready_i <= not aw_done;
    wready_i  <= not w_done;
    do_write  <= aw_done and w_done;

    s_axi_awready <= awready_i;
    s_axi_wready  <= wready_i;
    s_axi_bvalid  <= bvalid_i;

    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                aw_done <= '0';
                w_done  <= '0';
                bvalid_i <= '0';
            else
                if s_axi_awvalid = '1' and awready_i = '1' then
                    awaddr_r <= s_axi_awaddr;
                    aw_done  <= '1';
                end if;
                if s_axi_wvalid = '1' and wready_i = '1' then
                    wdata_r <= s_axi_wdata;
                    w_done  <= '1';
                end if;

                if do_write = '1' then
                    bvalid_i <= '1';
                    aw_done <= '0';
                    w_done  <= '0';
                elsif bvalid_i = '1' and s_axi_bready = '1' then
                    bvalid_i <= '0';
                end if;
            end if;
        end if;
    end process;

    s_axi_bresp <= "00"; -- OKAY, always

    -----------------------------------------------------------------------
    -- AXI read channel.
    -----------------------------------------------------------------------
    arready_i <= not ar_pending;
    s_axi_arready <= arready_i;
    s_axi_rvalid  <= rvalid_i;

    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                ar_pending <= '0';
                rvalid_i   <= '0';
            else
                if s_axi_arvalid = '1' and arready_i = '1' then
                    araddr_r   <= s_axi_araddr;
                    ar_pending <= '1';
                end if;

                if ar_pending = '1' and rvalid_i = '0' then
                    rvalid_i <= '1';
                elsif rvalid_i = '1' and s_axi_rready = '1' then
                    rvalid_i   <= '0';
                    ar_pending <= '0';
                end if;
            end if;
        end if;
    end process;

    s_axi_rresp <= "00"; -- OKAY, always

    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if ar_pending = '1' and rvalid_i = '0' then
                case rd_region is
                    when "01" => -- GPU
                        case rd_offset(7 downto 0) is
                            when x"00" => -- GPU_STATUS: bit0 = vblank_pending (sticky)
                                s_axi_rdata <= (31 downto 1 => '0') & vblank_pending;
                            when x"04" => -- GPU_FRAME_CNT: VBLANK count since reset
                                s_axi_rdata <= std_logic_vector(frame_cnt);
                            when others =>
                                s_axi_rdata <= (others => '0');
                        end case;
                    when "10" => -- BLT
                        case rd_offset(7 downto 0) is
                            when x"18" => -- BLT_STATUS: bit0=busy, bit1=fifo_full (always 0, no queue)
                                s_axi_rdata <= (31 downto 1 => '0') & blt_busy_i;
                            when others =>
                                s_axi_rdata <= (others => '0');
                        end case;
                    when "11" => -- COLL
                        if rd_offset = x"204" then -- HIT_MASK_LO: hit_mask[31:0]
                            s_axi_rdata <= coll_hit_mask_i(31 downto 0);
                        elsif rd_offset = x"208" then
                            -- HIT_MASK_HI: hit_mask[63:32]. N_OBJ is fixed at 64
                            -- everywhere in this project (two full 32-bit words,
                            -- no partial top word to mask off).
                            s_axi_rdata <= coll_hit_mask_i(63 downto 32);
                        else
                            s_axi_rdata <= (others => '0');
                        end if;
                    when others => -- PAL: write-only
                        s_axi_rdata <= (others => '0');
                end case;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- Register writes + the peripherals' own state.
    -----------------------------------------------------------------------
    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                vblank_pending  <= '0';
                frame_cnt       <= (others => '0');
                pal_wr_en_o     <= '0';
                blt_cmd_start_o <= '0';
                coll_obj_we_o   <= '0';
            else
                pal_wr_en_o     <= '0';
                blt_cmd_start_o <= '0';
                coll_obj_we_o   <= '0';

                -- VBLANK bookkeeping - independent of any AXI activity.
                if vblank_pulse = '1' then
                    vblank_pending <= '1';
                    frame_cnt      <= frame_cnt + 1;
                end if;

                if do_write = '1' then
                    case wr_region is
                        when "00" => -- PAL: relayed straight to palette_lut.vhd (which already holds the state)
                            pal_wr_en_o  <= '1';
                            pal_wr_idx_o <= unsigned(awaddr_r(9 downto 2));
                            pal_wr_rgb_o <= wdata_r(11 downto 0);

                        when "01" => -- GPU
                            if wr_offset(7 downto 0) = x"00" then
                                vblank_pending <= '0'; -- any write clears the sticky flag
                            end if;

                        when "10" => -- BLT
                            case wr_offset(7 downto 0) is
                                when x"00" => -- BLT_CTRL: bit0=start, bits[2:1]=op, bit3=key_en
                                    blt_cmd_start_o  <= wdata_r(0);
                                    blt_cmd_op_o     <= wdata_r(2 downto 1);
                                    blt_cmd_key_en_o <= wdata_r(3);
                                when x"04" => -- BLT_DST: {y[9:0], x[9:0]}
                                    blt_cmd_x_o <= unsigned(wdata_r(9 downto 0));
                                    blt_cmd_y_o <= unsigned(wdata_r(19 downto 10));
                                when x"08" => -- BLT_SIZE: {h[9:0], w[9:0]}
                                    blt_cmd_w_o <= unsigned(wdata_r(9 downto 0));
                                    blt_cmd_h_o <= unsigned(wdata_r(19 downto 10));
                                when x"0C" => -- BLT_SRC: source address
                                    blt_cmd_src_o <= wdata_r(16 downto 0);
                                when x"10" => -- BLT_COLOR: fill color / palette index
                                    blt_cmd_color_o <= wdata_r(7 downto 0);
                                when x"14" => -- BLT_KEY: transparency key
                                    blt_cmd_key_o <= wdata_r(7 downto 0);
                                when others =>
                                    null;
                            end case;

                        when others => -- COLL
                            if wr_offset = x"200" then -- QRY_IDX: bits[5:0] select object to query
                                coll_qry_idx_o <= unsigned(wdata_r(5 downto 0));
                            elsif wr_offset(11 downto 9) = "000" and wr_offset(2) = '0' then
                                -- idx*8+0x00: bit31=en, bits[26:16]=y (signed), bits[10:0]=x (signed)
                                coll_w0(to_integer(unsigned(wr_offset(8 downto 3)))) <= wdata_r;
                                coll_obj_we_o  <= '1';
                                coll_obj_idx_o <= unsigned(wr_offset(8 downto 3));
                                coll_obj_en_o  <= wdata_r(31);
                                coll_obj_y_o   <= signed(wdata_r(26 downto 16));
                                coll_obj_x_o   <= signed(wdata_r(10 downto 0));
                                coll_obj_h_o   <= unsigned(coll_w1(to_integer(unsigned(wr_offset(8 downto 3))))(15 downto 8));
                                coll_obj_w_o   <= unsigned(coll_w1(to_integer(unsigned(wr_offset(8 downto 3))))(7 downto 0));
                            elsif wr_offset(11 downto 9) = "000" and wr_offset(2) = '1' then
                                -- idx*8+0x04: bits[15:8]=h, bits[7:0]=w
                                coll_w1(to_integer(unsigned(wr_offset(8 downto 3)))) <= wdata_r;
                                coll_obj_we_o  <= '1';
                                coll_obj_idx_o <= unsigned(wr_offset(8 downto 3));
                                coll_obj_h_o   <= unsigned(wdata_r(15 downto 8));
                                coll_obj_w_o   <= unsigned(wdata_r(7 downto 0));
                                coll_obj_en_o  <= coll_w0(to_integer(unsigned(wr_offset(8 downto 3))))(31);
                                coll_obj_y_o   <= signed(coll_w0(to_integer(unsigned(wr_offset(8 downto 3))))(26 downto 16));
                                coll_obj_x_o   <= signed(coll_w0(to_integer(unsigned(wr_offset(8 downto 3))))(10 downto 0));
                            end if;
                    end case;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
