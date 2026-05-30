module dut(input logic clk, input logic a);
  assert property (@(posedge clk) a || !a);
endmodule
