// Dual-clock FIFO, 2^AB entries of W bits, Gray-coded pointers through 2-flop synchronisers.
// The memory has a combinational read port (LUT RAM): rdata is the oldest entry while rempty is
// low; pulse ren to drop it. Writes while wfull are ignored.
`default_nettype none
module async_fifo #(
  parameter integer W  = 384,
  parameter integer AB = 4
) (
  input  wire         wclk,
  input  wire         wen,
  input  wire [W-1:0] wdata,
  output wire         wfull,
  input  wire         rclk,
  input  wire         ren,
  output wire [W-1:0] rdata,
  output wire         rempty
);
  (* ram_style = "distributed" *) reg [W-1:0] mem [0:(1 << AB) - 1];
  reg [AB:0] wbin = 0, wgray = 0, rbin = 0, rgray = 0;
  (* ASYNC_REG = "TRUE" *) reg [AB:0] rg_w1 = 0, rg_w2 = 0;   // rgray in wclk
  (* ASYNC_REG = "TRUE" *) reg [AB:0] wg_r1 = 0, wg_r2 = 0;   // wgray in rclk

  wire [AB:0] wbin_n = wbin + 1'b1;
  wire [AB:0] rbin_n = rbin + 1'b1;
  assign wfull  = (wgray == {~rg_w2[AB:AB-1], rg_w2[AB-2:0]});
  assign rempty = (rgray == wg_r2);
  assign rdata  = mem[rbin[AB-1:0]];

  always @(posedge wclk) begin
    rg_w1 <= rgray;
    rg_w2 <= rg_w1;
    if (wen && !wfull) begin
      mem[wbin[AB-1:0]] <= wdata;
      wbin  <= wbin_n;
      wgray <= wbin_n ^ (wbin_n >> 1);
    end
  end

  always @(posedge rclk) begin
    wg_r1 <= wgray;
    wg_r2 <= wg_r1;
    if (ren && !rempty) begin
      rbin  <= rbin_n;
      rgray <= rbin_n ^ (rbin_n >> 1);
    end
  end
endmodule
`default_nettype wire
