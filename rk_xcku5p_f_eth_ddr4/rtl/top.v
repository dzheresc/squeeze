// RK-XCKU5P-F Ethernet-to-DDR4 recorder: receives the frames from arty_a7_35t_eth_stream on
// the RTL8211F PHY (RGMII, 100 Mb/s), writes every good frame (all 64 bytes) into the whole 2 GB
// of DDR4 as a circular buffer of 128-byte slots (see ddr_ring.v), reads every slot back to
// check it, and shows on LED1..LED4 the first payload nibble (the Arty's rolling one-hot
// pattern) as read back from DDR4, so the LEDs only follow the Arty if the whole
// Ethernet -> RAM -> LED path works.
//   KEY1      clears the counters and restarts the ring at slot 0
//   UART      once a second, 115200 8N1 (COM6), all values hex:
//             "ku5p-f eth-ddr4 cal C bmsr XXXX gbcr XXXX good GGGGGGGG bad BBBBBBBB miss MMMMMMMM
//              ovf OOOOOOOO wr WWWWWWWW fps FFFFFFFF wrap RRRRRRRR rderr EEEEEEEE
//              old OOOOOOOO olderr EEEEEEEE led L"
//             cal = DDR4 calibrated; bmsr = PHY reg 1 (bit 2 = link); gbcr = PHY reg 9, the
//             1000BASE-T advertisement, cleared at start-up (0000) so the PHY links at 100 Mb/s
//             even to a gigabit switch;
//             good / bad = frames of ours with a good FCS / frames with a bad FCS or too short;
//             miss = sequence numbers skipped between good frames;
//             ovf = good frames dropped because the FIFO in front of the DDR4 was full;
//             wr = slots written, fps = slots written in the last second; wrap = ring wraps
//             (2^24 slots of 128 B each); rderr = read-back words that differ from what was written;
//             old / olderr = checks of the slot written 16 frames earlier / failed checks;
//             led = the LED value. Frames are only counted once the DDR4 is calibrated.
// Clocks: the 200 MHz board clock (T24/U24) goes straight into the MIG; everything but the
// RGMII receiver runs on the MIG's 300 MHz ui_clk. The receiver runs on RXC (25 MHz) and hands
// frames over through a dual-clock FIFO. PL_CLK (AC13) does not toggle on this board.
`default_nettype none
module top #(
  parameter integer UI_HZ = 300_000_000,
  parameter integer BAUD  = 115_200
) (
  input  wire        c0_sys_clk_p,
  input  wire        c0_sys_clk_n,
  input  wire        key1_n,          // low = pressed
  output wire [3:0]  led,             // LED1..LED4, high = on
  output wire        uart_tx,
  input  wire        phy_rxck,
  input  wire        phy_rxctl,
  input  wire [3:0]  phy_rxd,
  output wire        phy_txck,
  output wire        phy_txctl,
  output wire [3:0]  phy_txd,
  output wire        phy_mdc,
  inout  wire        phy_mdio,

  output wire        c0_ddr4_act_n,
  output wire [16:0] c0_ddr4_adr,
  output wire [1:0]  c0_ddr4_ba,
  output wire [0:0]  c0_ddr4_bg,
  output wire [0:0]  c0_ddr4_cke,
  output wire [0:0]  c0_ddr4_odt,
  output wire [0:0]  c0_ddr4_cs_n,
  output wire [0:0]  c0_ddr4_ck_t,
  output wire [0:0]  c0_ddr4_ck_c,
  output wire        c0_ddr4_reset_n,
  inout  wire [3:0]  c0_ddr4_dm_dbi_n,
  inout  wire [31:0] c0_ddr4_dq,
  inout  wire [3:0]  c0_ddr4_dqs_t,
  inout  wire [3:0]  c0_ddr4_dqs_c
);
  assign phy_txck  = 1'b0;
  assign phy_txctl = 1'b0;
  assign phy_txd   = 4'h0;

  // ---------------------------------------------------------------- MIG
  wire         ui_clk, ui_rst, calib;
  wire         app_en, app_rdy, app_wdf_wren, app_wdf_rdy, rd_valid;
  wire [2:0]   app_cmd;
  wire [28:0]  app_addr;
  wire [255:0] app_wdf_data, rd_data;

  ddr4_0 u_mig (
    .c0_sys_clk_p(c0_sys_clk_p), .c0_sys_clk_n(c0_sys_clk_n), .sys_rst(1'b0),
    .c0_init_calib_complete(calib), .dbg_clk(), .dbg_bus(),
    .c0_ddr4_adr(c0_ddr4_adr), .c0_ddr4_ba(c0_ddr4_ba), .c0_ddr4_cke(c0_ddr4_cke),
    .c0_ddr4_cs_n(c0_ddr4_cs_n), .c0_ddr4_dm_dbi_n(c0_ddr4_dm_dbi_n), .c0_ddr4_dq(c0_ddr4_dq),
    .c0_ddr4_dqs_c(c0_ddr4_dqs_c), .c0_ddr4_dqs_t(c0_ddr4_dqs_t), .c0_ddr4_odt(c0_ddr4_odt),
    .c0_ddr4_bg(c0_ddr4_bg), .c0_ddr4_reset_n(c0_ddr4_reset_n), .c0_ddr4_act_n(c0_ddr4_act_n),
    .c0_ddr4_ck_c(c0_ddr4_ck_c), .c0_ddr4_ck_t(c0_ddr4_ck_t),
    .c0_ddr4_ui_clk(ui_clk), .c0_ddr4_ui_clk_sync_rst(ui_rst),
    .c0_ddr4_app_en(app_en), .c0_ddr4_app_hi_pri(1'b0), .c0_ddr4_app_wdf_end(app_wdf_wren),
    .c0_ddr4_app_wdf_wren(app_wdf_wren), .c0_ddr4_app_rd_data_end(),
    .c0_ddr4_app_rd_data_valid(rd_valid), .c0_ddr4_app_rdy(app_rdy),
    .c0_ddr4_app_wdf_rdy(app_wdf_rdy), .c0_ddr4_app_addr(app_addr), .c0_ddr4_app_cmd(app_cmd),
    .c0_ddr4_app_wdf_data(app_wdf_data), .c0_ddr4_app_wdf_mask(32'h0000_0000),
    .c0_ddr4_app_rd_data(rd_data)
  );

  reg calib_q = 1'b0;                  // registered: calib comes from deep inside the MIG
  (* ASYNC_REG = "TRUE" *) reg [1:0] key_u = 2'b00;
  always @(posedge ui_clk) begin
    calib_q <= calib & ~ui_rst;
    key_u   <= {key_u[0], ~key1_n};
  end
  wire clr_u = key_u[1];

  // ---------------------------------------------------------------- RGMII receive (rx_clk)
  wire rxc_ibuf, rx_clk;
  IBUF u_rxc_ibuf (.I(phy_rxck), .O(rxc_ibuf));
  BUFG u_rxc_bufg (.I(rxc_ibuf), .O(rx_clk));
  (* IOB = "TRUE" *) reg [3:0] rxd_n = 4'h0;
  (* IOB = "TRUE" *) reg       rxctl_n = 1'b0;
  always @(negedge rx_clk) begin
    rxd_n   <= phy_rxd;
    rxctl_n <= phy_rxctl;      // RX_DV xor RX_ER on this edge; equals RX_DV without errors
  end
  reg [3:0] rxd_q = 4'h0;
  reg       dv_q = 1'b0;
  always @(posedge rx_clk) begin
    rxd_q <= rxd_n;
    dv_q  <= rxctl_n;
  end

  wire         f_done, f_crc_ok, f_ours;
  wire [31:0]  f_seq;
  wire [10:0]  f_len;
  wire [511:0] f_data;
  eth_rx_frame u_rx (
    .clk(rx_clk), .dv(dv_q), .rxd(rxd_q), .done(f_done), .crc_ok(f_crc_ok), .ours(f_ours),
    .pattern(), .seq(f_seq), .len(f_len), .data(f_data)
  );

  // Counters in rx_clk, only while the DDR4 is calibrated; KEY1 clears them.
  (* ASYNC_REG = "TRUE" *) reg [1:0] clr_s = 2'b00, en_s = 2'b00;
  reg [31:0] n_good = 0, n_bad = 0, n_miss = 0, n_ovf = 0, last_seq = 0;
  reg        have_seq = 1'b0;
  reg        upd = 1'b0;           // toggles after every frame, crosses into ui_clk
  reg        push = 1'b0;
  reg [527:0] push_d = 0;
  wire       fifo_full;
  always @(posedge rx_clk) begin
    clr_s <= {clr_s[0], ~key1_n};
    en_s  <= {en_s[0], calib_q};
    push  <= 1'b0;
    if (clr_s[1] || !en_s[1]) begin
      n_good <= 0; n_bad <= 0; n_miss <= 0; n_ovf <= 0; have_seq <= 1'b0;
    end else if (f_done) begin
      if (f_ours) begin
        n_good   <= n_good + 1'b1;
        last_seq <= f_seq;
        have_seq <= 1'b1;
        if (have_seq && f_seq != last_seq + 1) n_miss <= n_miss + (f_seq - last_seq - 1);
        if (fifo_full) n_ovf <= n_ovf + 1'b1;
        else push <= 1'b1;
        push_d <= {5'b00000, f_len, f_data};
      end else if (!f_crc_ok) begin
        n_bad <= n_bad + 1'b1;
      end
      upd <= ~upd;
    end
  end

  wire         fifo_empty;
  wire [527:0] fifo_q;
  wire         fifo_pop;
  async_fifo #(.W(528), .AB(4)) u_fifo (
    .wclk(rx_clk), .wen(push), .wdata(push_d), .wfull(fifo_full),
    .rclk(ui_clk), .ren(fifo_pop), .rdata(fifo_q), .rempty(fifo_empty)
  );

  // ---------------------------------------------------------------- DDR4 ring (ui_clk)
  wire [31:0] wr, wrap, rd_cnt, rderr, old, olderr;
  wire [3:0]  ring_led;
  ddr_ring #(.SB(24), .LAG(16), .WAIT(256), .MAW(29)) u_ring (
    .clk(ui_clk), .rst(ui_rst | ~calib_q), .clr(clr_u),
    .in_valid(~fifo_empty), .in_data(fifo_q), .in_pop(fifo_pop),
    .app_en(app_en), .app_cmd(app_cmd), .app_addr(app_addr),
    .app_wdf_wren(app_wdf_wren), .app_wdf_data(app_wdf_data),
    .app_rdy(app_rdy), .app_wdf_rdy(app_wdf_rdy), .rd_valid(rd_valid), .rd_data(rd_data),
    .wr_cnt(wr), .wrap_cnt(wrap), .rd_cnt(rd_cnt), .rd_err(rderr), .old_cnt(old),
    .old_err(olderr), .led(ring_led)
  );
  assign led = ring_led;

  // copy the rx counters into ui_clk: they were written before upd toggled and hold for a
  // whole frame
  (* ASYNC_REG = "TRUE" *) reg [2:0] upd_s = 3'b000;
  reg [31:0] good = 0, bad = 0, miss = 0, ovf = 0;
  always @(posedge ui_clk) begin
    upd_s <= {upd_s[1:0], upd};
    if (upd_s[2] ^ upd_s[1]) begin
      good <= n_good; bad <= n_bad; miss <= n_miss; ovf <= n_ovf;
    end
  end

  // ---------------------------------------------------------------- 1 Hz tick, frame rate
  reg [$clog2(UI_HZ)-1:0] sec_div = 0;
  reg        tick = 1'b0;
  reg [31:0] wr_prev = 0, fps = 0;
  always @(posedge ui_clk) begin
    tick <= 1'b0;
    if (sec_div == UI_HZ - 1) begin
      sec_div <= 0;
      tick    <= 1'b1;
      fps     <= wr - wr_prev;
      wr_prev <= wr;
    end else begin
      sec_div <= sec_div + 1'b1;
    end
  end

  // ---------------------------------------------------------------- MDIO, PHY address 0
  // On the first tick: clear the 1000BASE-T advertisement (reg 9 = 0) and restart
  // auto-negotiation (reg 0 = 1200: AN enable + restart), so that the PHY settles on 100 Mb/s
  // even with a gigabit partner. The receiver here only handles 10/100. Then once a second,
  // read BMSR (reg 1) and reg 9 back for the UART line.
  wire        md_busy, md_done, md_o, md_oe;
  wire [15:0] md_data;
  reg         md_start = 1'b0, md_wr = 1'b0;
  reg  [4:0]  md_reg = 5'd0;
  reg  [15:0] md_wdata = 16'h0000;
  reg  [15:0] bmsr = 16'h0000, gbcr = 16'hFFFF;
  reg         status_done = 1'b0;
  reg  [2:0]  md_step = 3'd0;
  localparam [2:0] M_IDLE = 3'd0, M_W9 = 3'd1, M_W0 = 3'd2, M_BMSR = 3'd3, M_GBCR = 3'd4;
  reg         md_init = 1'b0;
  always @(posedge ui_clk) begin
    md_start    <= 1'b0;
    status_done <= 1'b0;
    case (md_step)
      M_IDLE: if (tick) begin
        md_start <= 1'b1;
        if (!md_init) begin
          md_wr <= 1'b1; md_reg <= 5'd9; md_wdata <= 16'h0000; md_step <= M_W9;
        end else begin
          md_wr <= 1'b0; md_reg <= 5'd1; md_step <= M_BMSR;
        end
      end
      M_W9: if (md_done) begin
        md_wr <= 1'b1; md_reg <= 5'd0; md_wdata <= 16'h1200; md_start <= 1'b1;
        md_step <= M_W0;
      end
      M_W0: if (md_done) begin
        md_init <= 1'b1; md_wr <= 1'b0; md_reg <= 5'd1; md_start <= 1'b1; md_step <= M_BMSR;
      end
      M_BMSR: if (md_done) begin
        bmsr <= md_data; md_reg <= 5'd9; md_start <= 1'b1; md_step <= M_GBCR;
      end
      M_GBCR: if (md_done) begin
        gbcr <= md_data; status_done <= 1'b1; md_step <= M_IDLE;
      end
      default: md_step <= M_IDLE;
    endcase
  end
  mdio_rw #(.CLK_HZ(UI_HZ)) u_mdio (
    .clk(ui_clk), .start(md_start), .wr(md_wr), .phyad(5'd0), .regad(md_reg),
    .wdata(md_wdata), .busy(md_busy), .done(md_done), .data(md_data), .mdc(phy_mdc),
    .mdio_o(md_o), .mdio_oe(md_oe), .mdio_i(phy_mdio)
  );
  assign phy_mdio = md_oe ? md_o : 1'bz;

  // ---------------------------------------------------------------- UART report
  function [7:0] hex(input [3:0] n);
    hex = (n < 10) ? 8'h30 + n : 8'h57 + n;
  endfunction
  function [63:0] hex8(input [31:0] v);
    integer i;
    begin
      for (i = 0; i < 8; i = i + 1) hex8[8 * i +: 8] = hex(v[4 * i +: 4]);
    end
  endfunction
  function [31:0] hex4(input [15:0] v);
    integer i;
    begin
      for (i = 0; i < 4; i = i + 1) hex4[8 * i +: 8] = hex(v[4 * i +: 4]);
    end
  endfunction

  // "ku5p-f eth-ddr4 cal " 1 " bmsr " 4 " gbcr " 4 " good " 8 " bad " 8 " miss " 8 " ovf " 8
  // " wr " 8
  // " fps " 8 " wrap " 8 " rderr " 8 " old " 8 " olderr " 8 " led " 1 CR LF
  localparam integer LMAX = 20 + 1 + 6 + 4 + 6 + 4 + 6 + 8 + 5 + 8 + 6 + 8 + 5 + 8 + 4 + 8 + 5 + 8
                            + 6 + 8 + 7 + 8 + 5 + 8 + 8 + 8 + 5 + 1 + 2;
  reg  [8*LMAX-1:0] line = 0;
  reg  [7:0]        nleft = 0;
  reg               tx_valid = 1'b0;
  wire              tx_ready;
  always @(posedge ui_clk) begin
    tx_valid <= 1'b0;
    if (nleft == 0) begin
      if (status_done) begin
        line  <= {"ku5p-f eth-ddr4 cal ", hex({3'b000, calib_q}), " bmsr ", hex4(bmsr),
                  " gbcr ", hex4(gbcr),
                  " good ", hex8(good), " bad ", hex8(bad), " miss ", hex8(miss),
                  " ovf ", hex8(ovf), " wr ", hex8(wr), " fps ", hex8(fps),
                  " wrap ", hex8(wrap), " rderr ", hex8(rderr), " old ", hex8(old),
                  " olderr ", hex8(olderr), " led ", hex(ring_led), 8'h0d, 8'h0a};
        nleft <= LMAX;
      end
    end else if (tx_ready && !tx_valid) begin
      tx_valid <= 1'b1;
    end else if (tx_valid) begin
      line  <= line << 8;
      nleft <= nleft - 1'b1;
    end
  end
  uart_tx #(.CLK_HZ(UI_HZ), .BAUD(BAUD)) u_uart (
    .clk(ui_clk), .valid(tx_valid), .data(line[8*LMAX-1 -: 8]), .ready(tx_ready), .txd(uart_tx)
  );
endmodule
`default_nettype wire
