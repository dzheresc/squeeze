// Arty A7-35T DDR3 demo: MIG 7-series (native port) + endless full-memory test, results on the UART.
//
// Clocks: 100 MHz board clock -> MMCM -> 100 MHz (MIG system clock) and 200 MHz (IDELAYCTRL reference).
//         MIG runs the DDR3L at 325 MHz (650 MT/s); all user logic here is on ui_clk = 81.25 MHz.
// UART (115200 8N1, board USB serial port):
//   "ddr3 calib ok"                                                  once, after calibration
//   "pass PPPPPPPP mode M errs EEEEEEEE wcyc WWWWWWWW rcyc RRRRRRRR bad AAAAAAAA exp XXXXXXXX got GGGGGGGG"
//                                                                    after every full 256 MB write+read pass
//   all numbers hex; wcyc/rcyc are ui_clk cycles; bad = byte address of the first bad 32-bit lane
//   (ffffffff = none). Mode cycles 0..3 (address, ~address, xorshift, toggle), seed changes each pass.
// LEDs: LD4 calibrated, LD5 toggles per pass, LD6 sticky error, LD7 test running.
//       RGB LD0 dim green while all passes are clean, red once any pass failed.
// Buttons: red RESET restarts the MIG (recalibrates) and the test.
`default_nettype none
module top (
  input  wire        CLK100MHZ,
  input  wire        ck_rst,          // active low
  output wire [3:0]  led,
  output wire        led0_r,
  output wire        led0_g,
  output wire        uart_rxd_out,    // FPGA -> PC

  output wire [13:0] ddr3_addr,
  output wire [2:0]  ddr3_ba,
  output wire        ddr3_cas_n,
  output wire [0:0]  ddr3_ck_n,
  output wire [0:0]  ddr3_ck_p,
  output wire [0:0]  ddr3_cke,
  output wire        ddr3_ras_n,
  output wire        ddr3_reset_n,
  output wire        ddr3_we_n,
  inout  wire [15:0] ddr3_dq,
  inout  wire [1:0]  ddr3_dqs_n,
  inout  wire [1:0]  ddr3_dqs_p,
  output wire [0:0]  ddr3_cs_n,
  output wire [1:0]  ddr3_dm,
  output wire [0:0]  ddr3_odt
);
  localparam integer UI_HZ = 81_250_000;
  localparam integer AW    = 24;          // 2^24 words x 16 B = 256 MB

  // ---------------------------------------------------------------- clocks
  wire clk_fb, clk100_mmcm, clk200_mmcm, locked;
  MMCME2_BASE #(
    .CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(10.0),   // VCO 1000 MHz
    .CLKOUT0_DIVIDE_F(10.0),                                           // 100 MHz
    .CLKOUT1_DIVIDE(5)                                                 // 200 MHz
  ) u_mmcm (
    .CLKIN1(CLK100MHZ), .CLKFBIN(clk_fb), .CLKFBOUT(clk_fb),
    .CLKOUT0(clk100_mmcm), .CLKOUT1(clk200_mmcm),
    .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
    .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB(),
    .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0)
  );
  wire clk100, clk200;
  BUFG u_bufg100 (.I(clk100_mmcm), .O(clk100));
  BUFG u_bufg200 (.I(clk200_mmcm), .O(clk200));

  // ---------------------------------------------------------------- MIG
  wire         ui_clk, ui_rst, calib;
  wire         app_en, app_rdy, app_wdf_wren, app_wdf_rdy, rd_valid;
  wire [2:0]   app_cmd;
  wire [27:0]  app_addr;
  wire [127:0] app_wdf_data, rd_data;

  mig_ddr3 u_mig (
    .ddr3_addr(ddr3_addr), .ddr3_ba(ddr3_ba), .ddr3_cas_n(ddr3_cas_n),
    .ddr3_ck_n(ddr3_ck_n), .ddr3_ck_p(ddr3_ck_p), .ddr3_cke(ddr3_cke),
    .ddr3_ras_n(ddr3_ras_n), .ddr3_reset_n(ddr3_reset_n), .ddr3_we_n(ddr3_we_n),
    .ddr3_dq(ddr3_dq), .ddr3_dqs_n(ddr3_dqs_n), .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_cs_n(ddr3_cs_n), .ddr3_dm(ddr3_dm), .ddr3_odt(ddr3_odt),
    .init_calib_complete(calib),
    .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en),
    .app_wdf_data(app_wdf_data), .app_wdf_end(app_wdf_wren), .app_wdf_wren(app_wdf_wren),
    .app_wdf_mask(16'h0000),
    .app_rd_data(rd_data), .app_rd_data_end(), .app_rd_data_valid(rd_valid),
    .app_rdy(app_rdy), .app_wdf_rdy(app_wdf_rdy),
    .app_sr_req(1'b0), .app_ref_req(1'b0), .app_zq_req(1'b0),
    .app_sr_active(), .app_ref_ack(), .app_zq_ack(),
    .ui_clk(ui_clk), .ui_clk_sync_rst(ui_rst),
    .sys_clk_i(clk100), .clk_ref_i(clk200),
    .sys_rst(locked & ck_rst)               // active low
  );

  // ---------------------------------------------------------------- memory test
  reg         mt_start = 1'b0;
  reg  [31:0] pass = 0;
  reg  [31:0] seed = 0;               // + golden-ratio step per pass
  wire        mt_busy;
  wire [31:0] errs, wcyc, rcyc, err_addr, err_exp, err_got;

  ddr_memtest #(.AW(AW), .LANES(4), .MAW(28)) u_mt (
    .clk(ui_clk), .rst(ui_rst | ~calib), .start(mt_start),
    .cfg_base({AW{1'b0}}), .cfg_len({1'b1, {AW{1'b0}}}),
    .cfg_mode(pass[1:0]), .cfg_seed(seed),
    .app_en(app_en), .app_cmd(app_cmd), .app_addr(app_addr),
    .app_wdf_wren(app_wdf_wren), .app_wdf_data(app_wdf_data),
    .app_rdy(app_rdy), .app_wdf_rdy(app_wdf_rdy), .rd_valid(rd_valid), .rd_data(rd_data),
    .busy(mt_busy), .errs(errs), .wcyc(wcyc), .rcyc(rcyc),
    .err_addr(err_addr), .err_exp(err_exp), .err_got(err_got)
  );

  // ---------------------------------------------------------------- UART report
  function [63:0] hex8(input [31:0] v);
    integer i;
    reg [3:0] n;
    begin
      for (i = 0; i < 8; i = i + 1) begin
        n = v[4 * (7 - i) +: 4];
        hex8[8 * (7 - i) +: 8] = (n < 10) ? 8'h30 + n : 8'h57 + n;
      end
    end
  endfunction

  localparam integer LMAX = 103;                    // bytes in a pass line
  // "pass " 8 " mode " 1 " errs " 8 " wcyc " 8 " rcyc " 8 " bad " 8 " exp " 8 " got " 8 "\r\n"
  wire [8*LMAX-1:0] pass_line = {"pass ", hex8(pass), " mode ", 8'h30 + pass[1:0],
                                 " errs ", hex8(errs), " wcyc ", hex8(wcyc), " rcyc ", hex8(rcyc),
                                 " bad ", hex8(err_addr), " exp ", hex8(err_exp), " got ", hex8(err_got),
                                 8'h0d, 8'h0a};
  localparam [8*15-1:0] CALIB_LINE = {"ddr3 calib ok", 8'h0d, 8'h0a};

  reg [8*LMAX-1:0] line = 0;
  reg [7:0]        nleft = 0;
  reg              tx_valid = 1'b0;
  wire             tx_ready;

  localparam C_CAL = 2'd0, C_RUN = 2'd1, C_WAIT = 2'd2, C_REPORT = 2'd3;
  reg [1:0] cst = C_CAL;
  reg       any_err = 1'b0;

  always @(posedge ui_clk) begin
    mt_start <= 1'b0;
    tx_valid <= 1'b0;
    if (nleft != 0 && tx_ready && !tx_valid) begin
      tx_valid <= 1'b1;
    end else if (tx_valid) begin
      line  <= line << 8;
      nleft <= nleft - 1'b1;
    end

    case (cst)
      C_CAL: if (calib && nleft == 0) begin
        line  <= {CALIB_LINE, {(LMAX-15){8'h00}}};
        nleft <= 15;
        cst   <= C_RUN;
      end
      C_RUN: if (!mt_busy) begin mt_start <= 1'b1; cst <= C_WAIT; end
      C_WAIT: if (!mt_start && !mt_busy) cst <= C_REPORT;
      C_REPORT: if (nleft == 0) begin
        line    <= pass_line;
        nleft   <= LMAX;
        if (errs != 0) any_err <= 1'b1;
        pass    <= pass + 1'b1;
        seed    <= seed + 32'h9E37_79B9;
        cst     <= C_RUN;
      end
    endcase

    if (ui_rst) begin
      cst <= C_CAL;
      pass <= 0;
      seed <= 0;
      any_err <= 1'b0;
      nleft <= 0;
    end
  end

  uart_tx #(.CLK_HZ(UI_HZ), .BAUD(115_200)) u_tx (
    .clk(ui_clk), .valid(tx_valid), .data(line[8*LMAX-1 -: 8]), .ready(tx_ready), .txd(uart_rxd_out)
  );

  // ---------------------------------------------------------------- LEDs
  reg [3:0] pwm = 0;
  always @(posedge ui_clk) pwm <= pwm + 1'b1;
  assign led    = {mt_busy, any_err, pass[0], calib};
  assign led0_g = calib & ~any_err & (pwm == 0);
  assign led0_r = any_err & (pwm == 0);
endmodule
`default_nettype wire
