// Arty A7-35T Ethernet stream sender: sends minimum-size raw Ethernet frames (EtherType 88B5,
// see eth_tx_frame.v) back to back at the 100 Mb/s line rate through the on-board TI DP83848J
// PHY (MII). Every frame carries a new sequence number; the one-hot 4-bit pattern in the first
// payload byte rolls over only every 2 s, so a receiver that shows it on LEDs blinks visibly.
// rk_xcku5p_f_eth_ddr4 receives the stream, stores every frame in DDR4 and drives its LEDs from
// the copy read back from RAM.
//   LD4..LD7   current pattern (0001 -> 0010 -> 0100 -> 1000 -> 0001 ..., every 2 s)
//   LD0 green  PHY link up (PHYSTS bit 0), dim
//   SW1..SW0   frame rate: 00 line rate (~148.8k frames/s), 01 10k/s, 10 1k/s, 11 100/s
//   ck_rst     red RESET button: resets the PHY, the pattern and the sequence number
//   UART       once a second, 115200 8N1 (COM3), all values hex:
//              "arty eth stream sent SSSSSSSS fps FFFFFFFF led L sw S bmsr XXXX physts XXXX"
//              sent = frames sent (= last sequence number), fps = frames in the last second.
//              PHYSTS (DP83848 reg 0x10): bit 0 link, bit 1 = 10 Mb/s, bit 2 = full duplex.
// Clocks: 100 MHz oscillator; an MMCM makes the PHY's 25 MHz reference clock (eth_ref_clk). The
// PHY returns the 25 MHz MII transmit clock eth_tx_clk, which runs the frame generator, the
// pattern timer and the frame counters.
`default_nettype none
module top #(
  parameter integer CLK_HZ = 100_000_000,
  parameter integer TX_HZ  = 25_000_000,
  parameter integer BAUD   = 115_200
) (
  input  wire       CLK100MHZ,
  input  wire       ck_rst,          // active low
  input  wire [1:0] sw,
  output wire [3:0] led,
  output wire [3:0] led_g,
  output wire       uart_rxd_out,    // FPGA -> PC
  output wire       eth_ref_clk,     // 25 MHz to the PHY's X1
  output reg        eth_rstn = 1'b0,
  input  wire       eth_tx_clk,
  output wire [3:0] eth_txd,
  output wire       eth_tx_en,
  output wire       eth_mdc,
  inout  wire       eth_mdio
);
  // ---------------------------------------------------------------- clocks
  wire clk_ibuf, clk, fb, ref_mmcm, ref_clk, locked;
  IBUF u_ibuf (.I(CLK100MHZ), .O(clk_ibuf));
  BUFG u_bufg (.I(clk_ibuf), .O(clk));
  MMCME2_BASE #(
    .CLKIN1_PERIOD(10.0), .CLKFBOUT_MULT_F(10.0), .DIVCLK_DIVIDE(1), .CLKOUT0_DIVIDE_F(40.0)
  ) u_mmcm (
    .CLKIN1(clk_ibuf), .CLKFBIN(fb), .CLKFBOUT(fb), .CLKOUT0(ref_mmcm), .LOCKED(locked),
    .RST(1'b0), .PWRDWN(1'b0),
    .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(),
    .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
  );
  BUFG u_bufg_ref (.I(ref_mmcm), .O(ref_clk));
  ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) u_ref_oddr (
    .C(ref_clk), .CE(1'b1), .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0), .Q(eth_ref_clk)
  );

  wire tx_clk;
  BUFG u_bufg_tx (.I(eth_tx_clk), .O(tx_clk));

  // ---------------------------------------------------------------- reset
  (* ASYNC_REG = "TRUE" *) reg [1:0] rst_s = 2'b11;
  always @(posedge clk) rst_s <= {rst_s[0], ~ck_rst | ~locked};
  wire rst = rst_s[1];

  // PHY reset: low for 10 ms after the reference clock runs, then 110 ms before MDIO and frames
  localparam integer MS = CLK_HZ / 1000;
  reg [$clog2(120 * MS)-1:0] prst = 0;
  reg phy_ready = 1'b0;
  always @(posedge clk) begin
    if (rst) prst <= 0;
    else if (prst != 120 * MS - 1) prst <= prst + 1'b1;
    phy_ready <= ~rst && (prst == 120 * MS - 1);
    eth_rstn  <= ~rst && (prst >= 10 * MS);
  end

  // ---------------------------------------------------------------- stream (tx_clk)
  (* ASYNC_REG = "TRUE" *) reg [1:0] run_s = 2'b00;
  (* ASYNC_REG = "TRUE" *) reg [3:0] sw_s = 4'h0;
  always @(posedge tx_clk) begin
    run_s <= {run_s[0], phy_ready};
    sw_s  <= {sw_s[1:0], sw};
  end
  wire run = run_s[1];

  // Frame period in TX_CLK cycles (one nibble each). A minimum frame is 72 bytes with the
  // preamble = 144 cycles, plus at least 24 cycles (12 bytes) of inter-frame gap.
  reg [17:0] period;
  always @* begin
    case (sw_s[3:2])
      2'd0: period = 18'd168;                // line rate: 25e6 / 168 = 148.8k frames/s
      2'd1: period = TX_HZ / 10_000;
      2'd2: period = TX_HZ / 1_000;
      default: period = TX_HZ / 100;
    endcase
  end

  reg [17:0] since = 0;           // cycles since the last start
  reg [$clog2(2 * TX_HZ)-1:0] pat_div = 0;
  reg [3:0]  pattern = 4'b0001;
  reg [31:0] seq = 0;             // sequence number of the frame being sent; first = 1
  reg        start = 1'b0;
  wire       busy;
  always @(posedge tx_clk) begin
    start <= 1'b0;
    if (!run) begin
      since   <= 0;
      pat_div <= 0;
      pattern <= 4'b0001;
      seq     <= 0;
    end else begin
      if (pat_div == 2 * TX_HZ - 1) begin
        pat_div <= 0;
        pattern <= {pattern[2:0], pattern[3]};
      end else begin
        pat_div <= pat_div + 1'b1;
      end
      if (since != 18'h3FFFF) since <= since + 1'b1;
      if (!busy && !start && since >= period - 1) begin
        start <= 1'b1;
        seq   <= seq + 1'b1;
        since <= 0;
      end
    end
  end
  assign led = pattern;

  wire [3:0] txd_i;
  wire       tx_en_i;
  eth_tx_frame u_frame (
    .clk(tx_clk), .start(start), .pattern(pattern), .seq(seq),
    .txd(txd_i), .tx_en(tx_en_i), .busy(busy)
  );
  (* IOB = "TRUE" *) reg [3:0] txd_q = 4'h0;
  (* IOB = "TRUE" *) reg       tx_en_q = 1'b0;
  always @(posedge tx_clk) begin
    txd_q   <= txd_i;
    tx_en_q <= tx_en_i;
  end
  assign eth_txd   = txd_q;
  assign eth_tx_en = tx_en_q;

  // once a second (TX_CLK), snapshot the counters and toggle snap_t for the 100 MHz side
  reg [$clog2(TX_HZ)-1:0] sec_div = 0;
  reg [31:0] seq_last = 0, snap_seq = 0, snap_fps = 0;
  reg [3:0]  snap_pat = 4'h0;
  reg [1:0]  snap_sw = 2'b00;
  reg        snap_t = 1'b0;
  always @(posedge tx_clk) begin
    if (sec_div == TX_HZ - 1) begin
      sec_div  <= 0;
      snap_seq <= seq;
      snap_fps <= seq - seq_last;
      seq_last <= seq;
      snap_pat <= pattern;
      snap_sw  <= sw_s[3:2];
      snap_t   <= ~snap_t;
    end else begin
      sec_div <= sec_div + 1'b1;
    end
    if (!run) seq_last <= 0;
  end

  // ---------------------------------------------------------------- 100 MHz side
  // The snapshot is held for a second after snap_t toggles, so it is stable when copied.
  (* ASYNC_REG = "TRUE" *) reg [2:0] snap_s = 3'b000;
  reg [31:0] sent = 0, fps = 0;
  reg [3:0]  pat = 4'h0;
  reg [1:0]  swr = 2'b00;
  reg        tick = 1'b0;
  always @(posedge clk) begin
    snap_s <= {snap_s[1:0], snap_t};
    tick   <= snap_s[2] ^ snap_s[1];
    if (snap_s[2] ^ snap_s[1]) begin
      sent <= snap_seq; fps <= snap_fps; pat <= snap_pat; swr <= snap_sw;
    end
  end

  // MDIO status (PHY address 1), read after every snapshot
  wire        md_busy, md_done, md_o, md_oe;
  wire [15:0] md_data;
  reg         md_start = 1'b0;
  reg  [4:0]  md_reg = 5'd1;
  reg  [15:0] bmsr = 16'h0000, physts = 16'h0000;
  reg  [1:0]  md_step = 2'd0;
  reg         status_done = 1'b0;
  always @(posedge clk) begin
    md_start    <= 1'b0;
    status_done <= 1'b0;
    case (md_step)
      2'd0: if (tick && phy_ready) begin
        md_reg <= 5'h01; md_start <= 1'b1; md_step <= 2'd1;
      end
      2'd1: if (md_done) begin bmsr <= md_data; md_reg <= 5'h10; md_start <= 1'b1; md_step <= 2'd2; end
      2'd2: if (md_done) begin physts <= md_data; status_done <= 1'b1; md_step <= 2'd0; end
      default: md_step <= 2'd0;
    endcase
  end
  mdio_rd #(.CLK_HZ(CLK_HZ)) u_mdio (
    .clk(clk), .start(md_start), .phyad(5'd1), .regad(md_reg), .busy(md_busy), .done(md_done),
    .data(md_data), .mdc(eth_mdc), .mdio_o(md_o), .mdio_oe(md_oe), .mdio_i(eth_mdio)
  );
  assign eth_mdio = md_oe ? md_o : 1'bz;

  // link LED: LD0 green, 1/16 duty
  reg [3:0] pwm = 0;
  always @(posedge clk) pwm <= pwm + 1'b1;
  assign led_g = {3'b000, physts[0] & (pwm == 0)};

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

  // "arty eth stream sent " 8 " fps " 8 " led " 1 " sw " 1 " bmsr " 4 " physts " 4 CR LF
  localparam integer LMAX = 21 + 8 + 5 + 8 + 5 + 1 + 4 + 1 + 6 + 4 + 8 + 4 + 2;
  reg  [8*LMAX-1:0] line = 0;
  reg  [6:0]        nleft = 0;
  reg               tx_valid = 1'b0;
  wire              tx_ready;
  always @(posedge clk) begin
    tx_valid <= 1'b0;
    if (nleft == 0) begin
      if (status_done) begin
        line  <= {"arty eth stream sent ", hex8(sent), " fps ", hex8(fps), " led ", hex(pat),
                  " sw ", hex({2'b00, swr}), " bmsr ", hex4(bmsr), " physts ", hex4(physts),
                  8'h0d, 8'h0a};
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
    .clk(clk), .valid(tx_valid), .data(line[8*LMAX-1 -: 8]), .ready(tx_ready), .txd(uart_rxd_out)
  );
endmodule
`default_nettype wire
