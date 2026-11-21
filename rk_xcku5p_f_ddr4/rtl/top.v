// RK-XCKU5P-F DDR4 demo: UltraScale MIG (native port) + endless full-memory test, results on the UART.
//
// Memory: two MT40A512M16LY (x16) = 32-bit, 2 GB, at 2400 MT/s. The MIG takes the 200 MHz
//         differential board clock directly; all user logic here is on ui_clk = 300 MHz.
// UART (115200 8N1, FT2232H channel B):
//   "ddr4 calib ok"                                                  once, after calibration
//   "ddr4 calib wait"                                                every ~1 s until then
//   "pass PPPPPPPP mode M errs EEEEEEEE wcyc WWWWWWWW rcyc RRRRRRRR bad AAAAAAAA exp XXXXXXXX got GGGGGGGG"
//                                                                    after every full 2 GB write+read pass
//   all numbers hex; wcyc/rcyc are ui_clk cycles; bad = byte address of the first bad 32-bit lane
//   (ffffffff = none). Mode cycles 0..3 (address, ~address, xorshift, toggle), seed changes each pass.
// LEDs: LED1 calibrated, LED2 toggles per pass, LED3 sticky error, LED4 test running.
// Keys: KEY1 (held) resets the MIG; on release it recalibrates and the test restarts.
`default_nettype none
module top (
  input  wire        c0_sys_clk_p,
  input  wire        c0_sys_clk_n,
  input  wire        key1_n,          // low = pressed
  output wire [3:0]  led,
  output wire        uart_tx,

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
  localparam integer UI_HZ = 300_000_000;
  localparam integer AW    = 26;          // 2^26 words x 32 B = 2 GB

  // ---------------------------------------------------------------- MIG
  wire         ui_clk, ui_rst, calib;
  wire         app_en, app_rdy, app_wdf_wren, app_wdf_rdy, rd_valid;
  wire [2:0]   app_cmd;
  wire [28:0]  app_addr;
  wire [255:0] app_wdf_data, rd_data;

  ddr4_0 u_mig (
    .c0_sys_clk_p(c0_sys_clk_p), .c0_sys_clk_n(c0_sys_clk_n), .sys_rst(~key1_n),
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

  // ---------------------------------------------------------------- memory test
  reg         mt_start = 1'b0;
  reg  [31:0] pass = 0;
  reg  [31:0] seed = 0;               // + golden-ratio step per pass
  wire        mt_busy;
  wire [31:0] errs, wcyc, rcyc, err_addr, err_exp, err_got;

  ddr_memtest #(.AW(AW), .LANES(8), .MAW(29)) u_mt (
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
        n = v[4 * i +: 4];
        hex8[8 * i +: 8] = (n < 10) ? 8'h30 + n : 8'h57 + n;
      end
    end
  endfunction

  localparam integer LMAX = 103;                    // bytes in a pass line
  // "pass " 8 " mode " 1 " errs " 8 " wcyc " 8 " rcyc " 8 " bad " 8 " exp " 8 " got " 8 "\r\n"
  wire [8*LMAX-1:0] pass_line = {"pass ", hex8(pass), " mode ", 8'h30 + pass[1:0],
                                 " errs ", hex8(errs), " wcyc ", hex8(wcyc), " rcyc ", hex8(rcyc),
                                 " bad ", hex8(err_addr), " exp ", hex8(err_exp), " got ", hex8(err_got),
                                 8'h0d, 8'h0a};
  localparam [8*15-1:0] CALIB_LINE = {"ddr4 calib ok", 8'h0d, 8'h0a};
  localparam [8*17-1:0] WAIT_LINE  = {"ddr4 calib wait", 8'h0d, 8'h0a};

  reg [8*LMAX-1:0] line = 0;
  reg [7:0]        nleft = 0;
  reg              tx_valid = 1'b0;
  wire             tx_ready;

  localparam C_CAL = 2'd0, C_RUN = 2'd1, C_WAIT = 2'd2, C_REPORT = 2'd3;
  reg [1:0]  cst = C_CAL;
  reg        any_err = 1'b0;
  reg [28:0] wait_div = 0;             // ~1.07 s at 300 MHz between "calib wait" lines
  reg        calib_q = 1'b0;           // registered: calib comes from deep inside the MIG

  always @(posedge ui_clk) begin
    mt_start <= 1'b0;
    tx_valid <= 1'b0;
    calib_q  <= calib;
    if (nleft != 0 && tx_ready && !tx_valid) begin
      tx_valid <= 1'b1;
    end else if (tx_valid) begin
      line  <= line << 8;
      nleft <= nleft - 1'b1;
    end

    case (cst)
      C_CAL: if (nleft == 0) begin
        wait_div <= wait_div + 1'b1;
        if (calib_q) begin
          line  <= {CALIB_LINE, {(LMAX-15){8'h00}}};
          nleft <= 15;
          cst   <= C_RUN;
        end else if (&wait_div) begin
          line  <= {WAIT_LINE, {(LMAX-17){8'h00}}};
          nleft <= 17;
        end
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
      wait_div <= 0;
    end
  end

  uart_tx #(.CLK_HZ(UI_HZ), .BAUD(115_200)) u_tx (
    .clk(ui_clk), .valid(tx_valid), .data(line[8*LMAX-1 -: 8]), .ready(tx_ready), .txd(uart_tx)
  );

  assign led = {mt_busy, any_err, pass[0], calib_q};
endmodule
`default_nettype wire
