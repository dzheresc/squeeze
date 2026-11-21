// RK-XCKU5P-F Ethernet receiver: shows on LED1..LED4 the one-hot pattern carried by the frames
// that arty_a7_35t_eth sends once a second, received through the on-board Realtek RTL8211F PHY
// (RGMII, bank 66, 1.8 V) at 100 Mb/s over a direct cable.
//   LED1..4   pattern of the last good frame (EtherType 88B5, correct FCS); off until the first
//   KEY1      clears the counters
//   UART      once a second, 115200 8N1 (COM6):
//             "ku5p-f eth phy AA id IIIIIIII bmsr XXXX lpa XXXX good GGGGGGGG bad BBBBBBBB
//              miss MMMMMMMM seq SSSSSSSS led L"
//             AA = PHY address found by the MDIO scan, id = PHYID1:PHYID2 (RTL8211F 001cc916),
//             bmsr = reg 1 (bit 2 = link), lpa = reg 5, link partner abilities (bit 8 = 100 full);
//             good = frames of ours with a good FCS, bad = frames with a bad FCS or too short,
//             miss = sequence numbers skipped between good frames, seq = last sequence number.
//             All values hex.
// RGMII at 100 Mb/s: RXC is 25 MHz and each nibble is held for a whole clock (the same value on
// both edges), so the receiver samples on the falling edge of RXC, mid-way through the nibble.
// That works whether or not the PHY's RX clock delay strap is set. This design never transmits;
// TXCTL is held low so the PHY stays quiet.
// Clock: 200 MHz differential oscillator (T24/U24). PL_CLK (AC13) does not toggle on this board.
`default_nettype none
module top #(
  parameter integer CLK_HZ = 200_000_000,
  parameter integer BAUD   = 115_200
) (
  input  wire       sys_clk_p,
  input  wire       sys_clk_n,
  input  wire [3:0] key_n,          // KEY1..KEY4, low = pressed
  output wire [3:0] led,            // LED1..LED4, high = on
  output wire       uart_tx,
  input  wire       phy_rxck,
  input  wire       phy_rxctl,
  input  wire [3:0] phy_rxd,
  output wire       phy_txck,
  output wire       phy_txctl,
  output wire [3:0] phy_txd,
  output wire       phy_mdc,
  inout  wire       phy_mdio
);
  wire clk_ibuf, clk;
  IBUFDS u_ibufds (.I(sys_clk_p), .IB(sys_clk_n), .O(clk_ibuf));
  BUFG   u_bufg   (.I(clk_ibuf), .O(clk));

  assign phy_txck  = 1'b0;
  assign phy_txctl = 1'b0;
  assign phy_txd   = 4'h0;

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

  wire        f_done, f_crc_ok, f_ours;
  wire [3:0]  f_pattern;
  wire [31:0] f_seq;
  eth_rx_frame u_rx (
    .clk(rx_clk), .dv(dv_q), .rxd(rxd_q), .done(f_done), .crc_ok(f_crc_ok), .ours(f_ours),
    .pattern(f_pattern), .seq(f_seq), .len()
  );

  // counters in rx_clk; KEY1 (synchronised) clears them
  (* ASYNC_REG = "TRUE" *) reg [1:0] clr_s = 2'b00;
  reg [31:0] n_good = 0, n_bad = 0, n_miss = 0, last_seq = 0;
  reg [3:0]  last_pat = 4'h0;
  reg        have_seq = 1'b0;
  reg        upd = 1'b0;           // toggles after every frame, crosses into clk
  always @(posedge rx_clk) begin
    clr_s <= {clr_s[0], ~key_n[0]};
    if (clr_s[1]) begin
      n_good <= 0; n_bad <= 0; n_miss <= 0; have_seq <= 1'b0;
    end else if (f_done) begin
      if (f_ours) begin
        n_good   <= n_good + 1'b1;
        last_pat <= f_pattern;
        last_seq <= f_seq;
        have_seq <= 1'b1;
        if (have_seq && f_seq != last_seq + 1) n_miss <= n_miss + (f_seq - last_seq - 1);
      end else if (!f_crc_ok) begin
        n_bad <= n_bad + 1'b1;
      end
      upd <= ~upd;
    end
  end

  // copy into clk: the values were written before upd toggled and hold for a whole frame
  (* ASYNC_REG = "TRUE" *) reg [2:0] upd_s = 3'b000;
  reg [31:0] good = 0, bad = 0, miss = 0, seq = 0;
  reg [3:0]  pat = 4'h0;
  always @(posedge clk) begin
    upd_s <= {upd_s[1:0], upd};
    if (upd_s[2] ^ upd_s[1]) begin
      good <= n_good; bad <= n_bad; miss <= n_miss; seq <= last_seq; pat <= last_pat;
    end
  end
  assign led = pat;

  // ---------------------------------------------------------------- 1 Hz tick
  reg [$clog2(CLK_HZ)-1:0] sec_div = 0;
  reg tick = 1'b0;
  always @(posedge clk) begin
    tick <= 1'b0;
    if (sec_div == CLK_HZ - 1) begin sec_div <= 0; tick <= 1'b1; end
    else sec_div <= sec_div + 1'b1;
  end

  // ---------------------------------------------------------------- MDIO
  // Find the PHY by reading PHYID1 at every address, then read BMSR and the link partner
  // abilities once a second.
  wire        md_busy, md_done, md_o, md_oe;
  wire [15:0] md_data;
  reg         md_start = 1'b0;
  reg  [4:0]  md_ad = 5'd0, md_reg = 5'd2;
  reg  [4:0]  phyad = 5'd0;
  reg         found = 1'b0;
  reg  [31:0] phyid = 32'hFFFFFFFF;
  reg  [15:0] bmsr = 16'h0000, lpa = 16'h0000;
  reg  [2:0]  md_step = 3'd0;
  reg         status_done = 1'b0;
  localparam [2:0] M_WAIT = 3'd0, M_SCAN = 3'd1, M_ID2 = 3'd2, M_BMSR = 3'd3, M_LPA = 3'd4;
  always @(posedge clk) begin
    md_start    <= 1'b0;
    status_done <= 1'b0;
    case (md_step)
      M_WAIT: if (tick) begin
        md_start <= 1'b1;
        if (!found) begin md_ad <= 5'd0; md_reg <= 5'h02; md_step <= M_SCAN; end
        else begin md_ad <= phyad; md_reg <= 5'h01; md_step <= M_BMSR; end
      end
      M_SCAN: if (md_done) begin
        if (md_data != 16'hFFFF && md_data != 16'h0000) begin
          phyad <= md_ad; found <= 1'b1; phyid[31:16] <= md_data;
          md_reg <= 5'h03; md_start <= 1'b1; md_step <= M_ID2;
        end else if (md_ad == 5'd31) begin
          status_done <= 1'b1; md_step <= M_WAIT;   // nothing answered; report and retry
        end else begin
          md_ad <= md_ad + 1'b1; md_start <= 1'b1;
        end
      end
      M_ID2: if (md_done) begin
        phyid[15:0] <= md_data; md_reg <= 5'h01; md_start <= 1'b1; md_step <= M_BMSR;
      end
      M_BMSR: if (md_done) begin
        bmsr <= md_data; md_reg <= 5'h05; md_start <= 1'b1; md_step <= M_LPA;
      end
      M_LPA: if (md_done) begin
        lpa <= md_data; status_done <= 1'b1; md_step <= M_WAIT;
      end
      default: md_step <= M_WAIT;
    endcase
  end
  mdio_rd #(.CLK_HZ(CLK_HZ)) u_mdio (
    .clk(clk), .start(md_start), .phyad(md_ad), .regad(md_reg), .busy(md_busy), .done(md_done),
    .data(md_data), .mdc(phy_mdc), .mdio_o(md_o), .mdio_oe(md_oe), .mdio_i(phy_mdio)
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
  function [15:0] hex2(input [7:0] v);
    hex2 = {hex(v[7:4]), hex(v[3:0])};
  endfunction

  // "ku5p-f eth phy " 2 " id " 8 " bmsr " 4 " lpa " 4 " good " 8 " bad " 8 " miss " 8
  // " seq " 8 " led " 1 CR LF
  localparam integer LMAX = 110;
  reg  [8*LMAX-1:0] line = 0;
  reg  [6:0]        nleft = 0;
  reg               tx_valid = 1'b0;
  wire              tx_ready;
  always @(posedge clk) begin
    tx_valid <= 1'b0;
    if (nleft == 0) begin
      if (status_done) begin
        line  <= {"ku5p-f eth phy ", hex2({3'b000, phyad}), " id ", hex8(phyid),
                  " bmsr ", hex4(bmsr), " lpa ", hex4(lpa), " good ", hex8(good),
                  " bad ", hex8(bad), " miss ", hex8(miss), " seq ", hex8(seq),
                  " led ", hex(pat), 8'h0d, 8'h0a};
        nleft <= LMAX;
      end
    end else if (tx_ready && !tx_valid) begin
      tx_valid <= 1'b1;
    end else if (tx_valid) begin
      line  <= line << 8;
      nleft <= nleft - 1'b1;
    end
  end
  uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
    .clk(clk), .valid(tx_valid), .data(line[8*LMAX-1 -: 8]), .ready(tx_ready), .txd(uart_tx)
  );
endmodule
`default_nettype wire
