// comparator.sv — Stage 3 Hit Detection (Binary Optimized)

import l2_cache_pkg::*;

module comparator (
    // Tag from the current request (passed from Stage 1/2)
    input  logic [17:0]  req_tag,     

    // Metadata from all 4 ways (read in Stage 1)
    input  cache_meta_t  meta_w0, 
    input  cache_meta_t  meta_w1, 
    input  cache_meta_t  meta_w2, 
    input  cache_meta_t  meta_w3,

    // Results
    output logic         hit,         
    output logic [1:0]   hit_way      
);

    logic [3:0] match;

    always_comb begin
        // Parallel comparison: Tag must match AND Valid bit must be high
        match[0] = meta_w0.valid && (meta_w0.tag == req_tag);
        match[1] = meta_w1.valid && (meta_w1.tag == req_tag);
        match[2] = meta_w2.valid && (meta_w2.tag == req_tag);
        match[3] = meta_w3.valid && (meta_w3.tag == req_tag);

        // Reduction OR: Are there any matches?
        hit = |match;

        // Binary Priority Encoding
        // We use a priority case to ensure that if multiple matches 
        // somehow occur (though they shouldn't), we pick one.
        priority case (1'b1)
            match[0]: hit_way = 2'd0;
            match[1]: hit_way = 2'd1;
            match[2]: hit_way = 2'd2;
            match[3]: hit_way = 2'd3;
            default:  hit_way = 2'd0; 
        endcase
    end

endmodule
