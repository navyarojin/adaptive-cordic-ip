module hardware_command_queue #(
  parameter int WIDTH=32,
  parameter int DEPTH=4
) (
  input logic clk,rst_n,
  input logic push_valid_i,
  output logic push_ready_o,
  input logic [WIDTH-1:0] push_data_i,
  output logic pop_valid_o,
  input logic pop_ready_i,
  output logic [WIDTH-1:0] pop_data_o,
  output logic [$clog2(DEPTH+1)-1:0] count_o
);
  localparam int PTR_WIDTH=DEPTH<=1 ? 1 : $clog2(DEPTH);
  (* ram_style="registers" *) logic [WIDTH-1:0] entries [0:DEPTH-1];
  logic [PTR_WIDTH-1:0] read_ptr,write_ptr;
  wire pop=pop_valid_o && pop_ready_i;
  wire push=push_valid_i && push_ready_o;
  assign pop_valid_o=count_o!=0 && rst_n;
  assign push_ready_o=(int'(count_o)<DEPTH || pop) && rst_n;
  assign pop_data_o=entries[read_ptr];
  initial if (DEPTH<1 || WIDTH<1) $fatal(1,"Invalid command queue dimensions");
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      read_ptr<=0;
      write_ptr<=0;
      count_o<=0;
    end else begin
      if (push) begin
        entries[write_ptr]<=push_data_i;
        write_ptr<=int'(write_ptr)==DEPTH-1 ? '0 : write_ptr+1'b1;
      end
      if (pop) read_ptr<=int'(read_ptr)==DEPTH-1 ? '0 : read_ptr+1'b1;
      case ({push,pop})
        2'b10:count_o<=count_o+1'b1;
        2'b01:count_o<=count_o-1'b1;
        default: ;
      endcase
    end
  end
endmodule
