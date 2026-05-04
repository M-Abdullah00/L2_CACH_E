import l2_cache_pkg::*;

module main_memory (
    input  logic           clk,
    input  logic           rst_n,

    // Interface from Write Buffer (Separate AW and W)
    input  logic [31:0]    w_axi_awaddr,
    input  logic           w_axi_awvalid,
    output logic           w_axi_awready,

    input  logic [1023:0]  w_axi_wdata,
    input  logic [127:0]   w_axi_wstrb, 
    input  logic           w_axi_wlast, 
    input  logic           w_axi_wvalid,
    output logic           w_axi_wready,

    output logic           w_axi_bvalid,
    input  logic           w_axi_bready,

    // Interface to MSHR (Read Channel)
    input  logic [31:0]    r_axi_araddr,
    input  logic           r_axi_arvalid,
    output logic           r_axi_arready,

    output logic [1023:0]  r_axi_rdata,
    output logic           r_axi_rvalid,
    input  logic           r_axi_rready
);

    // 1MB Memory depth (8192 lines * 128 bytes)
    logic [1023:0] mem [8192]; 

    logic [31:0] current_awaddr;

    // Write Channel Logic
    typedef enum logic [1:0] {W_IDLE, W_WAIT_DATA, W_RESP} w_state_t;
    w_state_t w_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state        <= W_IDLE;
            w_axi_awready  <= 1'b1;
            w_axi_wready   <= 1'b0;
            w_axi_bvalid   <= 1'b0;
            current_awaddr <= '0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    w_axi_bvalid <= 1'b0;
                    if (w_axi_awvalid && w_axi_awready) begin
                        current_awaddr <= w_axi_awaddr;
                        w_axi_awready  <= 1'b0;
                        w_axi_wready   <= 1'b1;
                        w_state        <= W_WAIT_DATA;
                    end
                end

                W_WAIT_DATA: begin
                    if (w_axi_wvalid && w_axi_wready) begin
                        // Map the 32-bit address to the 8192-line array by dropping the 7 offset bits
                        mem[current_awaddr[19:7]] <= w_axi_wdata; 
                        w_axi_wready <= 1'b0;
                        w_axi_bvalid <= 1'b1;
                        w_state      <= W_RESP;
                    end
                end

                W_RESP: begin
                    if (w_axi_bvalid && w_axi_bready) begin
                        w_axi_bvalid  <= 1'b0;
                        w_axi_awready <= 1'b1;
                        w_state       <= W_IDLE;
                    end
                end
                
                default: w_state <= W_IDLE;
            endcase
        end
    end

    // Read Channel Logic 
    typedef enum logic [1:0] {R_IDLE, R_DATA} r_state_t;
    r_state_t r_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state       <= R_IDLE;
            r_axi_arready <= 1'b1;
            r_axi_rvalid  <= 1'b0;
            r_axi_rdata   <= '0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    if (r_axi_arvalid && r_axi_arready) begin
                        r_axi_rdata   <= mem[r_axi_araddr[19:7]];
                        r_axi_rvalid  <= 1'b1;
                        
                        r_axi_arready <= 1'b0;
                        r_state       <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (r_axi_rvalid && r_axi_rready) begin
                        r_axi_rvalid  <= 1'b0;
                        r_axi_arready <= 1'b1;
                        r_state       <= R_IDLE;
                    end
                end

                default: r_state <= R_IDLE;
            endcase
        end
    end

endmodule
