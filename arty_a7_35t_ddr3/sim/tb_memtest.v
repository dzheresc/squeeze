// ddr_memtest against a behavioural MIG native-interface model.
// The model accepts commands only while app_rdy is high and write data only while app_wdf_rdy is
// high (both random), returns reads in order after a random latency, and can flip one bit on the
// way back. Checks: all four modes pass on a clean memory, base/length are honoured (words outside
// the window are never touched), memory holds the expected pattern, an injected fault is counted
// once and reported at the right byte address with the right expected/got values.
// LANES and MAW are parameters so the same bench runs the 128-bit (Arty DDR3) and 256-bit
// (KU5P-F DDR4) builds of the engine: xelab -generic_top LANES=8 -generic_top MAW=31.
`timescale 1ns/1ps
`default_nettype none
module tb_memtest #(
  parameter integer LANES = 4,
  parameter integer MAW   = 28
);
  localparam integer AW = 8;                 // 256 words in the model
  localparam integer W  = 32 * LANES;
  localparam integer LB = $clog2(LANES);
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst = 1;

  reg           start = 0;
  reg [AW-1:0]  cfg_base = 0;
  reg [AW:0]    cfg_len = 0;
  reg [1:0]     cfg_mode = 0;
  reg [31:0]    cfg_seed = 0;
  wire          app_en, app_wdf_wren;
  wire [2:0]    app_cmd;
  wire [MAW-1:0] app_addr;
  wire [W-1:0]  app_wdf_data;
  reg           app_rdy = 0, app_wdf_rdy = 0;
  reg           rd_valid = 0;
  reg  [W-1:0]  rd_data = 0;
  wire          busy;
  wire [31:0]   errs, wcyc, rcyc, err_addr, err_exp, err_got;

  ddr_memtest #(.AW(AW), .LANES(LANES), .MAW(MAW)) dut (
    .clk(clk), .rst(rst), .start(start), .cfg_base(cfg_base), .cfg_len(cfg_len),
    .cfg_mode(cfg_mode), .cfg_seed(cfg_seed),
    .app_en(app_en), .app_cmd(app_cmd), .app_addr(app_addr), .app_wdf_wren(app_wdf_wren),
    .app_wdf_data(app_wdf_data), .app_rdy(app_rdy), .app_wdf_rdy(app_wdf_rdy),
    .rd_valid(rd_valid), .rd_data(rd_data),
    .busy(busy), .errs(errs), .wcyc(wcyc), .rcyc(rcyc), .err_addr(err_addr),
    .err_exp(err_exp), .err_got(err_got));

  // ------------------------------------------------------------------ MIG model
  reg  [W-1:0] mem [0:(1 << AW) - 1];
  reg  [W-1:0] rq_data [0:255];
  integer      rq_due [0:255];
  integer      rq_wr = 0, rq_rd = 0, now = 0, errors = 0, i;
  integer      fault_w = -1, fault_bit = 0;
  integer      writes = 0, reads = 0;
  wire [AW-1:0] word = app_addr[AW+2:3];
  always @(posedge clk) begin
    now <= now + 1;
    app_rdy     <= ($random & 3) != 0;     // ~75 %
    app_wdf_rdy <= ($random & 7) != 0;     // ~88 %
    if (app_addr[2:0] != 3'b000 || app_addr[MAW-1:AW+3] != 0) begin
      if (app_en) begin $display("FAIL bad app_addr %h", app_addr); errors = errors + 1; end
    end
    if (app_wdf_wren && !(app_en && app_rdy && app_wdf_rdy && app_cmd == 3'd0)) begin
      $display("FAIL write data without an accepted write command"); errors = errors + 1;
    end
    if (app_en && app_rdy) begin
      if (app_cmd == 3'd0) begin
        if (!app_wdf_wren) begin $display("FAIL write command without data"); errors = errors + 1; end
        mem[word] <= app_wdf_data;
        writes = writes + 1;
      end else if (app_cmd == 3'd1) begin
        rq_data[rq_wr[7:0]] = mem[word];
        if (word == fault_w) rq_data[rq_wr[7:0]][fault_bit] = ~mem[word][fault_bit];
        rq_due[rq_wr[7:0]] = now + 12 + ($random & 15);
        rq_wr = rq_wr + 1;
        reads = reads + 1;
      end else begin
        $display("FAIL unknown app_cmd %0d", app_cmd); errors = errors + 1;
      end
    end
    // in-order return; a later read never overtakes an earlier one
    rd_valid <= 1'b0;
    if (rq_rd != rq_wr && now >= rq_due[rq_rd[7:0]] && ($random & 3) != 0) begin
      rd_valid <= 1'b1;
      rd_data  <= rq_data[rq_rd[7:0]];
      rq_rd = rq_rd + 1;
    end
  end

  // ------------------------------------------------------------------ reference pattern
  function [31:0] lanepat(input [AW-1:0] w, input integer j, input [1:0] mode, input [31:0] seed);
    reg [31:0] a, x;
    begin
      a = (w * LANES + j) * 4;
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

  localparam [W-1:0] FILL = {LANES{32'h5A5A_C3C3}};
  task run(input [AW-1:0] base, input integer len, input [1:0] mode, input [31:0] seed,
           input integer fw, input integer fb);
    integer w, j, e_errs;
    reg [31:0] e_addr, e_exp, e_got;
    begin
      for (w = 0; w < (1 << AW); w = w + 1) mem[w] = FILL;
      fault_w = fw;  fault_bit = fb;
      writes = 0;  reads = 0;
      @(posedge clk);
      cfg_base <= base;  cfg_len <= len;  cfg_mode <= mode;  cfg_seed <= seed;  start <= 1;
      @(posedge clk);  start <= 0;
      @(posedge clk);
      wait (!busy);
      @(posedge clk);
      // memory: pattern inside the window, untouched outside
      for (w = 0; w < (1 << AW); w = w + 1)
        for (j = 0; j < LANES; j = j + 1)
          if (mem[w][32 * j +: 32] !== ((w >= base && w < base + len) ? lanepat(w, j, mode, seed)
                                                                       : FILL[32 * j +: 32])) begin
            if (errors < 10) $display("FAIL mem[%0d] lane %0d = %08x", w, j, mem[w][32 * j +: 32]);
            errors = errors + 1;
          end
      if (fw >= 0) begin
        e_errs = 1;
        e_addr = (fw * LANES + fb / 32) * 4;
        e_exp  = lanepat(fw, fb / 32, mode, seed);
        e_got  = e_exp ^ (32'd1 << (fb % 32));
      end else begin
        e_errs = 0;  e_addr = 32'hFFFF_FFFF;  e_exp = 0;  e_got = 0;
      end
      $display("run base=%0d len=%0d mode=%0d seed=%08x fault=%0d: errs=%0d err_addr=%08x exp=%08x got=%08x wcyc=%0d rcyc=%0d",
               base, len, mode, seed, fw, errs, err_addr, err_exp, err_got, wcyc, rcyc);
      if (writes != len || reads != len) begin
        $display("FAIL %0d writes, %0d reads, expected %0d each", writes, reads, len); errors = errors + 1;
      end
      if (errs != e_errs || err_addr != e_addr || (fw >= 0 && (err_exp != e_exp || err_got != e_got))) begin
        $display("FAIL result: expected errs=%0d err_addr=%08x exp=%08x got=%08x", e_errs, e_addr, e_exp, e_got);
        errors = errors + 1;
      end
      if (wcyc < len || rcyc < len) begin
        $display("FAIL cycle counters too small"); errors = errors + 1;
      end
    end
  endtask

  initial begin
    repeat (5) @(posedge clk);
    rst <= 0;
    repeat (5) @(posedge clk);
    run(0, 256, 0, 32'h0000_0000, -1, 0);
    run(0, 256, 1, 32'h1234_5678, -1, 0);
    run(16, 200, 2, 32'hCAFE_F00D, -1, 0);
    run(255, 1, 3, 32'hA5A5_A5A5, -1, 0);
    run(3, 100, 2, 32'h0BAD_BEEF, 77, 32 * (LANES - 1) + 9);   // fault in the top lane
    run(0, 256, 3, 32'hFFFF_0000, 0, 0);                        // fault in the very first bit
    if (errors == 0) $display("PASS"); else $display("FAILED %0d", errors);
    $finish;
  end
  initial begin
    #5_000_000;
    $display("FAIL timeout");
    $finish;
  end
endmodule
`default_nettype wire
