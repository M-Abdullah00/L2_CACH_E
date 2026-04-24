Package l2_cache_pkg;

    // Request packet from Arbiter/CPU/MSHR
    Typedef struct packed {
        Logic [31:0]    addr;
        Logic [1023:0]  data;
        Logic [127:0]   strobe;   
        Logic           write;
    } cache_req_t;

    // Metadata packet for Tag RAM storage
    Typedef struct packed {
        Logic [17:0] tag;
        Logic        valid;
        Logic        dirty;
    } cache_meta_t;

Endpackage
