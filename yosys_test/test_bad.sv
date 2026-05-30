module dut(input logic clk);
  reg [3:0] past_a;
  always @(posedge clk) past_a <= a;
  input a;
endmodule
