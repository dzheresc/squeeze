// Sends one minimum-size Ethernet frame on an MII transmit port (4 bits per TX_CLK, low nibble
// first) for each start pulse. Runs on the PHY's TX_CLK.
//   preamble 7 x 55, SFD D5
//   dst  FF:FF:FF:FF:FF:FF (broadcast)    src 02:00:00:00:A7:35 (locally administered)
//   type 88B5 (IEEE local experimental)
//   payload: byte 0 = {4'h0, pattern}, bytes 1..4 = seq (big endian), bytes 5..11 = "SQUEEZE",
//            zero padding to 46 bytes
//   FCS (CRC-32), then idle
`default_nettype none
module eth_tx_frame (
  input  wire        clk,
  input  wire        start,
  input  wire [3:0]  pattern,
  input  wire [31:0] seq,
  output reg  [3:0]  txd = 4'h0,
  output reg         tx_en = 1'b0,
  output wire        busy
);
  localparam integer PRE = 8;          // preamble + SFD bytes
  localparam integer DATA = 60;        // header + payload, before FCS
  localparam integer LAST = PRE + DATA + 4 - 1;

  reg        active = 1'b0;
  reg [6:0]  idx = 0;                  // byte index from the first preamble byte
  reg        hi = 1'b0;                // 0 = low nibble, 1 = high nibble
  reg [3:0]  pat_q = 4'h0;
  reg [31:0] seq_q = 0;
  reg [31:0] crc = 32'hFFFFFFFF;
  assign busy = active;

  // byte i of header + payload
  function [7:0] data_byte(input [6:0] i);
    case (i)
      0, 1, 2, 3, 4, 5: data_byte = 8'hFF;
      6:  data_byte = 8'h02;
      7, 8, 9: data_byte = 8'h00;
      10: data_byte = 8'hA7;
      11: data_byte = 8'h35;
      12: data_byte = 8'h88;
      13: data_byte = 8'hB5;
      14: data_byte = {4'h0, pat_q};
      15: data_byte = seq_q[31:24];
      16: data_byte = seq_q[23:16];
      17: data_byte = seq_q[15:8];
      18: data_byte = seq_q[7:0];
      19: data_byte = "S";
      20: data_byte = "Q";
      21: data_byte = "U";
      22: data_byte = "E";
      23: data_byte = "E";
      24: data_byte = "Z";
      25: data_byte = "E";
      default: data_byte = 8'h00;
    endcase
  endfunction

  wire [31:0] fcs = ~crc;
  reg  [7:0]  cur;
  always @* begin
    if (idx < PRE - 1)          cur = 8'h55;
    else if (idx == PRE - 1)    cur = 8'hD5;
    else if (idx < PRE + DATA)  cur = data_byte(idx - PRE);
    else case (idx - (PRE + DATA))
      0: cur = fcs[7:0];
      1: cur = fcs[15:8];
      2: cur = fcs[23:16];
      default: cur = fcs[31:24];
    endcase
  end

  wire [31:0] crc_next;
  crc32_d8 u_crc (.crc(crc), .data(cur), .next(crc_next));

  always @(posedge clk) begin
    if (!active) begin
      tx_en <= 1'b0;
      txd   <= 4'h0;
      if (start) begin
        active <= 1'b1;
        idx    <= 0;
        hi     <= 1'b0;
        pat_q  <= pattern;
        seq_q  <= seq;
        crc    <= 32'hFFFFFFFF;
      end
    end else begin
      tx_en <= 1'b1;
      txd   <= hi ? cur[7:4] : cur[3:0];
      // the CRC covers header + payload; it is final before the first FCS byte goes out
      if (!hi && idx >= PRE && idx < PRE + DATA) crc <= crc_next;
      hi <= ~hi;
      if (hi) begin
        if (idx == LAST) active <= 1'b0;
        else idx <= idx + 1'b1;
      end
    end
  end
endmodule
`default_nettype wire
