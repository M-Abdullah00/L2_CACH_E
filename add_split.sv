import l2_cache_pkg::*;
 
module add_split (
    input  cache_req_t  req_in,       // win_req_s1 from arbiter
    output addr_split_t split_out    
);
 
    assign split_out.tag = req_in.addr[31:14];
    assign split_out.index = req_in.addr[13:7];
    assign split_out.offset = req_in.addr[6:0];
 
endmodule