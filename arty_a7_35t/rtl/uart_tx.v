// 8N1 UART transmitter. Pulse valid for one cycle while ready is high.
`default_nettype none
module uart_tx #(
  parameter integer CLK_HZ = 100_000_000,
  parameter integer BAUD   = 115_200
) (
  input  wire       clk,
  input  wire       valid,
  input  wire [7:0] data,
  output wire       ready,
  output reg        txd = 1'b1
);
  localparam integer DIV = CLK_HZ / BAUD;
  reg [$clog2(DIV)-1:0] div = 0;
  reg [9:0] sh = 10'h3ff;
  reg [3:0] bits = 0;
  assign ready = (bits == 0);
  always @(posedge clk) begin
    if (ready) begin
      if (valid) begin sh <= {1'b1, data, 1'b0}; bits <= 10; div <= 0; end
    end else if (div == DIV - 1) begin
      div  <= 0;
      txd  <= sh[0];
      sh   <= {1'b1, sh[9:1]};
      bits <= bits - 1;
    end else begin
      div <= div + 1;
    end
  end
endmodule
`default_nettype wire
