`ifndef  TEST_BENCH
 `include "config.v"
 `include "sigmoid.v"
 `include "RandomGenerator.v"
 `include "ap_adder.v"
 `include "i_ap_adder.v"  //approximate adder
`else
 `include "../sigmoid.v"
 `include "../RandomGenerator.v"
 `include "../ap_adder.v" 
 `include "../i_ap_adder.v"  //approximate adder
`endif

`define bit_12_16(b) {b[11],b[11],b[11],b[11],b}


module RBMLayer 				#(parameter integer bitlength = 16,
              parameter integer w_bitlength = 12,
						  parameter integer sigmoid_bitlength = 8,
						  parameter integer general_input_dim = 15, // 784,441
						  parameter integer sparse_input_dim = 8, //64
						  parameter integer output_dim = 5, //441,10
						  parameter  Inf = 16'b0111_1111_1111_1111,
						  parameter weight_path = "../build/data/Hweight15x5.txt",  // load a different weight for sparse case 64x441
						  parameter bias_path = "../build/data/Hbias1x5.txt",
						  parameter seed_path = "../build/data/seed1x10.txt",
              parameter ord_path = "../build/data/order/example/c_adder_ord_example.txt",
						  parameter integer adder_num  = 28,
						  parameter [7:0] SeedData = 32,
						  parameter integer id = 0
						  )
   (input reset,
    input rand_reset,
    input clock,
    input data_valid,
    input wire [`PORT_1D(general_input_dim, 1)] InputData,
    output reg [`PORT_1D(output_dim, 1)] OutputData,
    output reg finish
    );




`ifndef SPARSE
   localparam input_dim = general_input_dim;
`else
   localparam input_dim = sparse_input_dim;
`endif

   // `DEFINE_PRINTING_VAR;
   // synopsys translate_off
   initial begin
      `ReadMem(weight_path, Weight);
      `ReadMem(bias_path, Bias);
      `ReadMem(ord_path, Switch);
   end
   // synopsys translate_on

   reg [w_bitlength-1:0] Weight`DIM_2D(input_dim, output_dim);
   reg [w_bitlength-1:0] Bias`DIM_1D(output_dim);
   reg Switch`DIM_1D(output_dim); //0=>adder, 1=>iadder

   reg [9:0] 	     cursor, adding_cursor;
   reg [9:0] 	     i,j,k;
   genvar 	     g;
  //  reg mask;
  reg mask;

   wire [sigmoid_bitlength-1:0] 	     RandomData;
   wire [sigmoid_bitlength-1:0] 	     SigmoidOutput;


   reg [bitlength-1:0] Temp;
   // two adder "tree"
   wire signed [bitlength-1:0] Adder_Input_Temp_Exact[adder_num-1:0];
   wire signed [bitlength-1:0] Adder_Input_Temp_Approximate[adder_num-1:0];
   wire signed [bitlength-1:0] Next_Temp;
   sigmoid #(bitlength,sigmoid_bitlength) sg(Temp, SigmoidOutput);
   RandomGenerator  #(sigmoid_bitlength) rnd(rand_reset, clock, SeedData, RandomData);


   generate
      if (adder_num > 1) begin
        // currently not supported
	      // ap_adder #(bitlength, Inf) adder_first(
        //                               `bit_12_16(Weight[adding_cursor][cursor]) & {16{InputData[adding_cursor]}},
        //                               `bit_12_16(Weight[adding_cursor+1][cursor]) & {16{InputData[adding_cursor+1]}},
        //                             Adder_Input_Temp[0]);
	      // for(g = 1; g<adder_num-1; g=g+1) begin : generate_adders
        //     ap_adder #(bitlength, Inf)  adder_middle(Adder_Input_Temp[g-1], `bit_12_16(Weight[adding_cursor+g+1][cursor]) & {16{InputData[adding_cursor+g+1]}}, Adder_Input_Temp[g]);
	      // end
	      // ap_adder #(bitlength, Inf) adder_last(Adder_Input_Temp[adder_num-2], Temp, Adder_Input_Temp[adder_num-1]);
      end else begin
            // now, only support adder==1 for Switch

            //exact
	           ap_adder #(bitlength, Inf) adder_only(
                            `bit_12_16(Weight[adding_cursor][cursor]) 
                            & {16{InputData[adding_cursor] & (~Switch[cursor])}},
                            Temp & {16{~Switch[cursor]}}, 
                            Adder_Input_Temp_Exact[adder_num-1]);

             i_ap_adder #(bitlength, Inf) iadder_only(
                            `bit_12_16(Weight[adding_cursor][cursor]) 
                            & {16{InputData[adding_cursor] & Switch[cursor]}},

                            Temp & {16{Switch[cursor]}},
                            Adder_Input_Temp_Approximate[adder_num-1]);
              
             assign Next_Temp = Adder_Input_Temp_Exact[adder_num-1] | Adder_Input_Temp_Approximate[adder_num-1];
      end
   endgenerate


   always @ ( posedge clock or posedge reset) begin
      if(reset) begin
         finish = 0;
         cursor = 0;
         adding_cursor = 0;
         Temp = 0;
         mask = 0;
      end else begin
         if (data_valid) begin
            // if (id == 2)
            // $display("in layer: %0d, adding_cursor: %0d, random = %0d",id, adding_cursor, RandomData);
            if (cursor == output_dim) begin
               finish = 1;
            end else begin
               finish = 0;
               if (adding_cursor == input_dim) begin
		              //  $display("%0d,%0d", id, RandomData); //#important for exporting random number
		            $display("%0d: %0d => %0d >< %0d", id,$signed(Temp) ,SigmoidOutput, RandomData);
		              `GET_1D(OutputData, 1, cursor) <= SigmoidOutput > RandomData;
                  adding_cursor = 0;
                  mask = 0;
                  cursor = cursor + 1;
               end else begin
                  if (adding_cursor == 0 && mask == 0) begin
                     Temp =  `bit_12_16(Bias[cursor]);// + (`bit_12_16(Weight[adding_cursor][cursor])  & {16{InputData[adding_cursor]}}); // problem here,
                  end else begin
                  //   if (id == 1 && cursor == 0) begin
                  //  $display("layer: %0d, inputdata[%0d] = %0d, temp = %0d", id,adding_cursor, InputData[adding_cursor],Temp);
                  //  end
                     Temp =  Next_Temp;
                  end
                  // if (id == 2 && cursor == 0) begin
                  //   $display("layer: %0d, cursor = %d, inputdata[%0d] = %0d, temp = %0d", id,cursor,adding_cursor, InputData[adding_cursor],Temp);
                  // end
                  adding_cursor = adding_cursor + adder_num & {10{mask}};
                  mask = 1;
               end
            end
         end
      end
   end
endmodule
