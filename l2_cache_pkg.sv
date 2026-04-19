package l2_cache_pkg;
 
    typedef struct packed {
        logic [31:0]    addr;
        logic [1023:0]  data;
        logic [127:0]   strobe;   
        logic  write;
    } cache_req_t;
 
endpackage