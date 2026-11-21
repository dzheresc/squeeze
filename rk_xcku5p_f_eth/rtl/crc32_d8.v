// Ethernet CRC-32 (IEEE 802.3), one byte per call, LSB first.
// Start from 32'hFFFFFFFF. The frame check sequence is ~crc, sent low byte first.
// Running the receiver over the data and the FCS leaves the residue 32'hDEBB20E3.
`default_nettype none
module crc32_d8 (
  input  wire [31:0] crc,
  input  wire [7:0]  data,
  output reg  [31:0] next
);
  integer i;
  always @* begin
    next = crc;
    for (i = 0; i < 8; i = i + 1)
      next = (next[0] ^ data[i]) ? ((next >> 1) ^ 32'hEDB88320) : (next >> 1);
  end
endmodule
`default_nettype wire
