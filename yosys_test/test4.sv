module dut(input logic clk, rst, input logic a);
  always @(posedge clk) if (!rst) assert(a || !a);
endmodule
