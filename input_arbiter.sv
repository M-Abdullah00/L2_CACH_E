import l2_cache_pkg::*;
 
module input_arbiter (
    input  logic clk,
    input  logic rst_n,
 
    input  cache_req_t  cpu_req,
    input  logic        cpu_req_valid,
    output logic        cpu_req_ready,
 
    input  cache_req_t  mshr_req,
    input  logic        mshr_req_valid,
    output logic        mshr_req_ready,
 
    output cache_req_t  win_req,
    output logic        win_valid,
    input  logic        win_ready
);
 
    always_comb begin
        win_req        = '0;
        win_valid      = 1'b0;
        cpu_req_ready  = 1'b0;
        mshr_req_ready = 1'b1;
 
        if (mshr_req_valid) begin
            win_req       = mshr_req;
            win_valid     = 1'b1;
            cpu_req_ready = 1'b0;
 
        end else if (cpu_req_valid) begin
            win_req       = cpu_req;
            win_valid     = 1'b1;
            cpu_req_ready = win_ready;
        end
    end
 
endmodule