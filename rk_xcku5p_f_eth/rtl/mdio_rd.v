// IEEE 802.3 clause 22 MDIO read. Pulse start while busy is low; done pulses with data valid.
// MDC = CLK_HZ / (2 * HALF). The master changes MDIO while MDC is low and samples just before
// MDC rises, so read data from the PHY (valid <= 300 ns after the previous rising edge) is stable.
`default_nettype none
module mdio_rd #(
  parameter integer CLK_HZ = 100_000_000,
  parameter integer MDC_HZ = 1_000_000
) (
  input  wire        clk,
  input  wire        start,
  input  wire [4:0]  phyad,
  input  wire [4:0]  regad,
  output reg         busy = 1'b0,
  output reg         done = 1'b0,
  output reg  [15:0] data = 16'h0000,
  output reg         mdc = 1'b0,
  output reg         mdio_o = 1'b1,
  output reg         mdio_oe = 1'b0,
  input  wire        mdio_i
);
  localparam integer HALF = CLK_HZ / (2 * MDC_HZ);
  (* ASYNC_REG = "TRUE" *) reg [1:0] in_s = 2'b11;
  reg [$clog2(HALF)-1:0] div = 0;
  reg [63:0] sh = 0;
  reg [5:0]  bitn = 0;
  always @(posedge clk) begin
    in_s <= {in_s[0], mdio_i};
    done <= 1'b0;
    if (!busy) begin
      mdc <= 1'b0;
      if (start) begin
        // preamble, ST=01, OP=10 (read), PHYAD, REGAD, then turnaround + 16 data bits from the PHY
        sh      <= {32'hFFFFFFFF, 2'b01, 2'b10, phyad, regad, 18'h00000};
        mdio_o  <= 1'b1;
        mdio_oe <= 1'b1;
        bitn    <= 0;
        div     <= 0;
        busy    <= 1'b1;
      end
    end else if (div != HALF - 1) begin
      div <= div + 1'b1;
    end else begin
      div <= 0;
      if (!mdc) begin
        if (bitn >= 48) data <= {data[14:0], in_s[1]};
        mdc <= 1'b1;
      end else begin
        mdc <= 1'b0;
        if (bitn == 63) begin
          busy    <= 1'b0;
          done    <= 1'b1;
          mdio_oe <= 1'b0;
        end else begin
          bitn    <= bitn + 1'b1;
          sh      <= sh << 1;
          mdio_o  <= sh[62];
          mdio_oe <= (bitn + 1 < 46);
        end
      end
    end
  end
endmodule
`default_nettype wire
