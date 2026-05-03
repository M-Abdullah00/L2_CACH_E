// tag_ram.sv 
import l2_cache_pkg::*;

module tag_ram (
    input  logic        clk,
    input  logic        rst_n,

    // Read Port — Stage 1 (Combinational)
    input  logic [6:0]  rd_index,
    output cache_meta_t rd_meta_w0, 
    output cache_meta_t rd_meta_w1, 
    output cache_meta_t rd_meta_w2, 
    output cache_meta_t rd_meta_w3,

    // Write Port — Stage 3 (Synchronous)
    input  logic        wr_en,
    input  logic [6:0]  wr_index,
    input  logic [1:0]  wr_way,
    input  cache_meta_t wr_meta  // Single struct for all write data
);

    // Storage: 128 sets, each containing 4 way-structs
    cache_meta_t mem [128][4];

    // Combinational Read (Stage 1)
    assign rd_meta_w0 = mem[rd_index][0];
    assign rd_meta_w1 = mem[rd_index][1];
    assign rd_meta_w2 = mem[rd_index][2];
    assign rd_meta_w3 = mem[rd_index][3];

    // Synchronous Update (Stage 3)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int s = 0; s < 128; s++) begin
                for (int w = 0; w < 4; w++) begin
                    mem[s][w] <= '0; // Initializes tag, valid, and dirty to 0
                end
            end
        end else if (wr_en) begin
            mem[wr_index][wr_way] <= wr_meta;
        end
    end

endmodule
