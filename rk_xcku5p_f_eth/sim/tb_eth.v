// Loopback test: arty_a7_35t_eth's frame generator feeds rk_xcku5p_f_eth's receiver.
`timescale 1ns/1ps
`default_nettype none
module tb_eth;
  reg clk = 0;
  always #20 clk = ~clk;            // 25 MHz
  reg start = 0;
  reg [3:0] pattern = 0;
  reg [31:0] seq = 0;
  wire [3:0] txd;
  wire tx_en, busy;
  eth_tx_frame u_tx (.clk(clk), .start(start), .pattern(pattern), .seq(seq),
                     .txd(txd), .tx_en(tx_en), .busy(busy));
  reg corrupt = 0;
  wire done, crc_ok, ours;
  wire [3:0] rx_pat;
  wire [31:0] rx_seq;
  wire [10:0] len;
  eth_rx_frame u_rx (.clk(clk), .dv(tx_en), .rxd(txd ^ {3'b000, corrupt}), .done(done),
                     .crc_ok(crc_ok), .ours(ours), .pattern(rx_pat), .seq(rx_seq), .len(len));
  // CRC-32 check value for "123456789" is CBF43926
  reg [31:0] c;
  wire [31:0] cn;
  reg [7:0] b;
  crc32_d8 u_chk (.crc(c), .data(b), .next(cn));
  integer i, errors = 0;
  always @(posedge clk) if (done)
    $display("%0t rx done len=%0d crc_ok=%0d ours=%0d pattern=%b seq=%08x",
             $time, len, crc_ok, ours, rx_pat, rx_seq);
  task send(input [3:0] p, input [31:0] s, input bad);
    begin
      @(posedge clk); pattern <= p; seq <= s; start <= 1; corrupt <= 0;
      @(posedge clk); start <= 0;
      if (bad) begin repeat (100) @(posedge clk); corrupt <= 1; @(posedge clk); corrupt <= 0; end
      wait (done); @(posedge clk);
      if (bad ? crc_ok : !(ours && rx_pat == p && rx_seq == s && len == 64)) begin
        $display("FAIL frame p=%b s=%08x", p, s); errors = errors + 1;
      end
      repeat (30) @(posedge clk);
    end
  endtask
  initial begin
    c = 32'hFFFFFFFF;
    for (i = 0; i < 9; i = i + 1) begin b = "1" + i; #1; c = cn; end
    if (~c != 32'hCBF43926) begin $display("FAIL crc check %08x", ~c); errors = errors + 1; end
    send(4'b0001, 32'h00000001, 0);
    send(4'b0010, 32'h00000002, 0);
    send(4'b0100, 32'hDEADBEEF, 0);
    send(4'b1000, 32'h00000004, 1);
    send(4'b0001, 32'h00000005, 0);
    if (errors == 0) $display("PASS"); else $display("FAILED %0d", errors);
    $finish;
  end
endmodule
`default_nettype wire
