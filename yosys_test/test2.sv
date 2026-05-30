module props(input logic clk, input logic a);
  assert property (@(posedge clk) a || !a);
endmodule
bind dut props p(.*);
