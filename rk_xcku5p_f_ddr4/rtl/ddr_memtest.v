// Full-rate memory test on the MIG native interface (ui_clk domain).
// Writes a pattern over [base, base+len) words, reads it back and checks it, one 32*LANES-bit
// word (one BL8 burst) per ui_clk whenever the MIG is ready.
// Same engine as arty_a7_35t_ddr3; here LANES = 8 (256-bit word, 32-bit DDR4 x BL8).
//
// Pattern for 32-bit lane j of word w (byte address a = 4*LANES*w + 4*j):
//   mode 0: a ^ seed               (address in data: catches aliasing)
//   mode 1: ~(a ^ seed)
//   mode 2: xorshift32(a ^ seed)   (pseudo-random, address dependent)
//   mode 3: seed on even words, ~seed on odd words (all DQ toggle every burst)
`default_nettype none
module ddr_memtest #(
  parameter integer AW    = 24,    // word address bits (2^24 x 16 B = 256 MB)
  parameter integer LANES = 4,     // 32-bit lanes per word
  parameter integer MAW   = 28     // MIG app_addr width
) (
  input  wire                 clk,
  input  wire                 rst,
  input  wire                 start,        // one-cycle pulse while !busy
  input  wire [AW-1:0]        cfg_base,
  input  wire [AW:0]          cfg_len,      // words, 1 .. 2^AW
  input  wire [1:0]           cfg_mode,
  input  wire [31:0]          cfg_seed,

  output wire                 app_en,
  output wire [2:0]           app_cmd,
  output wire [MAW-1:0]       app_addr,
  output wire                 app_wdf_wren,
  output wire [32*LANES-1:0]  app_wdf_data,
  input  wire                 app_rdy,
  input  wire                 app_wdf_rdy,
  input  wire                 rd_valid,
  input  wire [32*LANES-1:0]  rd_data,

  output reg                  busy = 1'b0,
  output reg  [31:0]          errs,         // mismatched 32-bit lanes (saturating)
  output reg  [31:0]          wcyc,         // ui_clk cycles of the write pass
  output reg  [31:0]          rcyc,         // ui_clk cycles of the read pass
  output reg  [31:0]          err_addr,     // byte address of the first bad lane (ffffffff: none)
  output reg  [31:0]          err_exp,
  output reg  [31:0]          err_got
);
  localparam integer LB = $clog2(LANES);
  localparam integer W  = 32 * LANES;

  function [31:0] lanepat(input [AW-1:0] w, input [LB-1:0] j, input [1:0] mode, input [31:0] seed);
    reg [31:0] a, x;
    begin
      a = {w, j, 2'b00};
      a = a ^ seed;
      x = a ^ (a << 13);
      x = x ^ (x >> 17);
      x = x ^ (x << 5);
      case (mode)
        2'd0: lanepat = a;
        2'd1: lanepat = ~a;
        2'd2: lanepat = x;
        default: lanepat = w[0] ? ~seed : seed;
      endcase
    end
  endfunction
  function [W-1:0] wordpat(input [AW-1:0] w, input [1:0] mode, input [31:0] seed);
    integer j;
    begin
      for (j = 0; j < LANES; j = j + 1) wordpat[32 * j +: 32] = lanepat(w, j[LB-1:0], mode, seed);
    end
  endfunction

  localparam S_IDLE = 3'd0, S_WR = 3'd1, S_RD = 3'd2, S_DRAIN = 3'd3, S_END = 3'd4;
  reg [2:0]    st = S_IDLE;
  reg [AW-1:0] a_cur, a_nxt;
  reg [AW:0]   left;
  reg [W-1:0]  wd;
  reg [AW:0]   r_left = 0;
  reg [AW-1:0] r_w, r_nxt;
  reg [W-1:0]  r_exp;

  wire issue_wr = (st == S_WR) && left != 0;
  wire issue_rd = (st == S_RD) && left != 0;
  assign app_en       = issue_rd | (issue_wr & app_wdf_rdy);
  assign app_cmd      = issue_wr ? 3'd0 : 3'd1;
  assign app_addr     = {a_cur, 3'b000};                   // zero-extended to MAW; BL8 column step
  assign app_wdf_wren = issue_wr & app_wdf_rdy & app_rdy;
  assign app_wdf_data = wd;
  wire acc = app_en & app_rdy;

  // read check: stage 1 register data + expected, stage 2 lane compare, then count
  reg              v1 = 1'b0, v2 = 1'b0;
  reg [W-1:0]      d1, e1, d2, e2;
  reg [AW-1:0]     w1, w2;
  reg [LANES-1:0]  bad2 = 0;
  reg [LB:0]       nbad;
  reg [LB-1:0]     first_lane;
  integer k;
  always @* begin
    nbad = 0;
    first_lane = 0;
    for (k = LANES - 1; k >= 0; k = k - 1)
      if (bad2[k]) begin
        nbad = nbad + 1'b1;
        first_lane = k[LB-1:0];
      end
  end

  reg have_err = 1'b0;
  always @(posedge clk) begin
    v1 <= 1'b0;
    v2 <= v1;
    if (rd_valid && r_left != 0) begin
      v1 <= 1'b1;
      d1 <= rd_data;
      e1 <= r_exp;
      w1 <= r_w;
      r_w <= r_nxt;
      r_nxt <= r_nxt + 1'b1;
      r_exp <= wordpat(r_nxt, cfg_mode, cfg_seed);
      r_left <= r_left - 1'b1;
    end
    d2 <= d1;  e2 <= e1;  w2 <= w1;
    for (k = 0; k < LANES; k = k + 1) bad2[k] <= v1 && (d1[32 * k +: 32] != e1[32 * k +: 32]);
    if (v2 && nbad != 0) begin
      errs <= (errs > 32'hFFFF_FFF0) ? 32'hFFFF_FFFF : errs + nbad;
      if (!have_err) begin
        have_err <= 1'b1;
        err_addr <= {w2, first_lane, 2'b00};
        err_exp  <= e2[32 * first_lane +: 32];
        err_got  <= d2[32 * first_lane +: 32];
      end
    end

    if (acc) begin
      a_cur <= a_nxt;
      a_nxt <= a_nxt + 1'b1;
      wd <= wordpat(a_nxt, cfg_mode, cfg_seed);
      left <= left - 1'b1;
    end

    case (st)
      S_IDLE: if (start) begin
        busy <= 1'b1;
        errs <= 0;  wcyc <= 0;  rcyc <= 0;
        err_addr <= 32'hFFFF_FFFF;  err_exp <= 0;  err_got <= 0;
        have_err <= 1'b0;
        a_cur <= cfg_base;  a_nxt <= cfg_base + 1'b1;
        wd <= wordpat(cfg_base, cfg_mode, cfg_seed);
        left <= cfg_len;
        st <= S_WR;
      end
      S_WR: begin
        wcyc <= wcyc + 1'b1;
        if (left == 0 || (left == 1 && acc)) begin
          a_cur <= cfg_base;  a_nxt <= cfg_base + 1'b1;
          left <= cfg_len;
          r_w <= cfg_base;  r_nxt <= cfg_base + 1'b1;
          r_exp <= wordpat(cfg_base, cfg_mode, cfg_seed);
          r_left <= cfg_len;
          st <= S_RD;
        end
      end
      S_RD: begin
        rcyc <= rcyc + 1'b1;
        if (left == 0 || (left == 1 && acc)) st <= S_DRAIN;
      end
      S_DRAIN: begin
        rcyc <= rcyc + 1'b1;
        if (r_left == 0) st <= S_END;
      end
      S_END: if (!v1 && !v2) begin
        busy <= 1'b0;
        st <= S_IDLE;
      end
      default: st <= S_IDLE;
    endcase

    if (rst) begin
      st <= S_IDLE;
      busy <= 1'b0;
      v1 <= 1'b0;
      v2 <= 1'b0;
      r_left <= 0;
    end
  end
endmodule
`default_nettype wire
