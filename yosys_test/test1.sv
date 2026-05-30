module dut(input logic clk, input logic a);
  always @(posedge clk) assert(a || !a);
endmodule
