import l2_cache_pkg::*;
 
module pipeline_register1 (
    input  logic        clk,
    input  logic        rst_n,
 
    // From arbiter 
    input  cache_req_t  win_req_s1,
    input  logic        win_valid_s1,    
 
    // From add_split — diagram: addr
    input  addr_split_t addr_s1,         // tag, index, offset
 
    // From Tag RAM
    input  cache_meta_t rd_tag_meta_w0,
    input  cache_meta_t rd_tag_meta_w1,
    input  cache_meta_t rd_tag_meta_w2,
    input  cache_meta_t rd_tag_meta_w3,
 
    // Registered outputs
    output cache_req_t  win_req_s2,
    output logic        win_valid_s2,
    output addr_split_t addr_s2,
    output cache_meta_t rd_tag_meta_s2_w0,
    output cache_meta_t rd_tag_meta_s2_w1,
    output cache_meta_t rd_tag_meta_s2_w2,
    output cache_meta_t rd_tag_meta_s2_w3
);
 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            win_req_s2        <= '0;
            win_valid_s2      <= 1'b0;
            addr_s2           <= '0;
            rd_tag_meta_s2_w0 <= '0;
            rd_tag_meta_s2_w1 <= '0;
            rd_tag_meta_s2_w2 <= '0;
            rd_tag_meta_s2_w3 <= '0;
        end else begin
            win_req_s2        <= win_req_s1;
            win_valid_s2      <= win_valid_s1;
            addr_s2           <= addr_s1;
            rd_tag_meta_s2_w0 <= rd_tag_meta_w0;
            rd_tag_meta_s2_w1 <= rd_tag_meta_w1;
            rd_tag_meta_s2_w2 <= rd_tag_meta_w2;
            rd_tag_meta_s2_w3 <= rd_tag_meta_w3;
        end
    end
 
endmodule