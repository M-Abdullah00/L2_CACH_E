import l2_cache_pkg::*;
 
module data_ram (
    input  logic clk,
 
    // Read port
    input  logic          rd_en,
    input  logic [6:0]    rd_index,
    input  logic [1:0]    rd_way,
    output logic [1023:0] rd_data,
 
    // Write port
    input  logic          wr_en,
    input  cache_req_t    wr_req,
    input  logic [1:0]    wr_way
);
 
    localparam SETS = 128;
    localparam WAYS = 4;
 
    logic [1023:0] mem [SETS][WAYS];
 
    logic [6:0] wr_index;
    assign wr_index = wr_req.addr[13:7];
 
    // Read
    always_ff @(posedge clk) begin
        if (rd_en)
            rd_data <= mem[rd_index][rd_way];
    end
 
    // Write
    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_index][wr_way] <= wr_req.data;
    end
 
endmodule