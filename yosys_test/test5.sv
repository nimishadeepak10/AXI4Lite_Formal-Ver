module dut(input logic clk, rst, input logic a, b);
  always @(posedge clk) if (rst) begin
    if ($past(a && !b)) assert(a);
  end
endmodule
