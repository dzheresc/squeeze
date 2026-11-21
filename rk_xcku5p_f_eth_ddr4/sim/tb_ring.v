// End-to-end test without the PHYs: arty_a7_35t_eth_stream's frame generator -> eth_rx_frame ->
// async_fifo -> ddr_ring -> a simple MIG native-port model (random app_rdy / app_wdf_rdy,
// in-order read data after a fixed latency). A small ring (64 slots, old-slot check 16 back)
// so the test wraps several times. Then a stuck data bit in the model must show up as errors.
`timescale 1ns/1ps
`default_nettype none
module tb_ring;
  localparam integer SB = 6, LAG = 16, NFR = 200;
  reg rx_clk = 0, ui_clk = 0;
  always #20 rx_clk = ~rx_clk;          // 25 MHz
  always #1.666 ui_clk = ~ui_clk;       // ~300 MHz

  // ---- frame source
  reg        start = 0;
  reg [3:0]  pattern = 4'b0001;
  reg [31:0] seq = 0;
  wire [3:0] txd;
  wire       tx_en, busy;
  eth_tx_frame u_tx (.clk(rx_clk), .start(start), .pattern(pattern), .seq(seq),
                     .txd(txd), .tx_en(tx_en), .busy(busy));

  // ---- receiver + FIFO, as in top.v
  wire f_done, f_crc_ok, f_ours;
  wire [31:0] f_seq;
  wire [10:0] f_len;
  wire [367:0] f_payload;
  eth_rx_frame u_rx (.clk(rx_clk), .dv(tx_en), .rxd(txd), .done(f_done), .crc_ok(f_crc_ok),
                     .ours(f_ours), .pattern(), .seq(f_seq), .len(f_len), .payload(f_payload));
  reg push = 0;
  reg [383:0] push_d = 0;
  wire full, empty, pop;
  wire [383:0] q;
  integer n_ovf = 0;
  always @(posedge rx_clk) begin
    push <= 1'b0;
    if (f_done && f_ours) begin
      if (full) n_ovf = n_ovf + 1; else push <= 1'b1;
      push_d <= {5'b0, f_len, f_payload};
    end
  end
  async_fifo #(.W(384), .AB(4)) u_fifo (.wclk(rx_clk), .wen(push), .wdata(push_d), .wfull(full),
                                       .rclk(ui_clk), .ren(pop), .rdata(q), .rempty(empty));

  // ---- ring
  wire app_en, app_wdf_wren, rd_valid;
  wire [2:0] app_cmd;
  wire [28:0] app_addr;
  wire [255:0] app_wdf_data;
  reg  [255:0] rd_data = 0;
  reg app_rdy = 0, app_wdf_rdy = 0;
  reg rst = 1, clr = 0;
  wire [31:0] wr, wrap, rdn, rderr, old, olderr;
  wire [3:0] led;
  ddr_ring #(.SB(SB), .LAG(LAG), .WAIT(32), .MAW(29)) u_ring (
    .clk(ui_clk), .rst(rst), .clr(clr), .in_valid(~empty), .in_data(q), .in_pop(pop),
    .app_en(app_en), .app_cmd(app_cmd), .app_addr(app_addr), .app_wdf_wren(app_wdf_wren),
    .app_wdf_data(app_wdf_data), .app_rdy(app_rdy), .app_wdf_rdy(app_wdf_rdy),
    .rd_valid(rd_valid), .rd_data(rd_data), .wr_cnt(wr), .wrap_cnt(wrap), .rd_cnt(rdn),
    .rd_err(rderr), .old_cnt(old), .old_err(olderr), .led(led));

  // ---- MIG model
  reg [255:0] mem [0:(1 << (SB + 1)) - 1];
  reg [255:0] rq_data [0:63];
  integer rq_t [0:63];
  integer rq_w = 0, rq_r = 0, cyc = 0, bad_wr = 0;
  reg stuck = 0;                         // forces data bit 5 of every write to 1
  wire [SB:0] widx = app_addr[SB+3:3];
  reg rv = 0;
  assign rd_valid = rv;
  always @(posedge ui_clk) begin
    cyc = cyc + 1;
    app_rdy     <= ($random & 3) != 0;
    app_wdf_rdy <= ($random & 7) != 0;
    if (app_en && app_rdy) begin
      if (app_addr[2:0] != 0 || app_addr[28:SB+4] != 0) bad_wr = bad_wr + 1;
      if (app_cmd == 3'd0) begin
        if (!app_wdf_wren) bad_wr = bad_wr + 1;
        mem[widx] <= app_wdf_data | (stuck ? 256'h20 : 256'h0);
      end else begin
        rq_data[rq_w % 64] = mem[widx];
        rq_t[rq_w % 64] = cyc + 20;
        rq_w = rq_w + 1;
      end
    end else if (app_wdf_wren) bad_wr = bad_wr + 1;
    rv <= 1'b0;
    if (rq_r != rq_w && rq_t[rq_r % 64] <= cyc) begin
      rv <= 1'b1;
      rd_data <= rq_data[rq_r % 64];
      rq_r = rq_r + 1;
    end
  end

  // ---- check: LED follows the pattern of the frame read back
  integer errors = 0, i;
  task send(input integer n);
    integer k;
    begin
      for (k = 0; k < n; k = k + 1) begin
        @(posedge rx_clk); while (busy) @(posedge rx_clk);
        repeat (24) @(posedge rx_clk);
        seq <= seq + 1; start <= 1;
        if ((seq % 25) == 24) pattern <= {pattern[2:0], pattern[3]};
        @(posedge rx_clk); start <= 0;
      end
      repeat (400) @(posedge rx_clk);
    end
  endtask

  initial begin
    for (i = 0; i < (1 << (SB + 1)); i = i + 1) mem[i] = 0;
    repeat (20) @(posedge ui_clk); rst <= 0;
    send(NFR);
    $display("clean: wr=%0d wrap=%0d rd=%0d rderr=%0d old=%0d olderr=%0d ovf=%0d led=%b pattern=%b",
             wr, wrap, rdn, rderr, old, olderr, n_ovf, led, pattern);
    if (wr != NFR || rdn != NFR || wrap != NFR / (1 << SB) || rderr != 0 || old != NFR - LAG ||
        olderr != 0 || n_ovf != 0 || led != pattern || bad_wr != 0) begin
      $display("FAIL clean run"); errors = errors + 1;
    end
    // slot 0 holds frame 192 (= 3 * 64): payload byte 0 = pattern, bytes 1..4 = seq 193
    $display("slot 0: %h", mem[0]);
    if (mem[0][39:8] != 32'hC1000000) begin
      $display("FAIL slot 0 seq"); errors = errors + 1;
    end
    if (mem[1][159:128] != 192 || mem[1][255:224] != {"4", "R", "D", "D"} || mem[1][191:160] != 3) begin
      $display("FAIL slot 0 metadata"); errors = errors + 1;
    end
    stuck = 1;
    send(4);
    $display("stuck bit: wr=%0d rderr=%0d olderr=%0d", wr, rderr, olderr);
    if (rderr == 0) begin $display("FAIL stuck bit not seen"); errors = errors + 1; end
    if (errors == 0) $display("PASS"); else $display("FAILED %0d", errors);
    $finish;
  end
endmodule
`default_nettype wire
