import l2_cache_pkg::*;

module write_buffer_separate (
    input  logic           clk,
    input  logic           rst_n,

    // Internal Interface from Control Stage
    input  logic           wb_en,       
    input  wb_req_t        wb_req,      
    output logic           wb_ready,    

    // Separate AXI Write Channels
    output logic [31:0]    m_axi_awaddr,
    output logic           m_axi_awvalid,
    input  logic           m_axi_awready,

    output logic [1023:0]  m_axi_wdata,
    output logic           m_axi_wvalid,
    input  logic           m_axi_wready,

    input  logic           m_axi_bvalid,
    output logic           m_axi_bready
);

    wb_entry_t mem [4]; 
    logic [1:0] wr_ptr, rd_ptr;
    logic [2:0] count;

  assign wb_ready = (count < 3'd4);
    logic empty     = (count == 3'd0);

    // --- FIFO Push Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            count  <= '0;
        end else begin
            // CASE statement 
            case ({wb_en && wb_ready, m_axi_bvalid && !empty})
                2'b10: begin // Push
                    mem[wr_ptr] <= wb_req;
                    wr_ptr      <= wr_ptr + 1;
                    count       <= count + 1;
                end
                2'b01: begin // Pop
                    count       <= count - 1;
                end
                2'b11: begin // Simultaneous
                    mem[wr_ptr] <= wb_req;
                    wr_ptr      <= wr_ptr + 1;
                end
                default: begin // Explicit default: do nothing
                    count <= count; 
                    wr_ptr <= wr_ptr;
                end
            endcase
        end
    end

    // --- Separate Channel State Machine ---
    typedef enum logic [1:0] { IDLE, TRANSFERRING, WAIT_RESPONSE } state_t;
    state_t state;

    logic aw_done, w_done;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            rd_ptr        <= '0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (!empty) begin
                        state         <= TRANSFERRING;
                        m_axi_awvalid <= 1'b1;
                        m_axi_wvalid  <= 1'b1;
                        aw_done       <= 1'b0;
                        w_done        <= 1'b0;
                    end
                end

                TRANSFERRING: begin
                    if (m_axi_awready && m_axi_awvalid) begin
                        m_axi_awvalid <= 1'b0;
                        aw_done       <= 1'b1;
                    end
                    
                    if (m_axi_wready && m_axi_wvalid) begin
                        m_axi_wvalid  <= 1'b0;
                        w_done        <= 1'b1;
                    end

                    if ((aw_done || (m_axi_awready && m_axi_awvalid)) && 
                        (w_done  || (m_axi_wready  && m_axi_wvalid))) begin
                        state        <= WAIT_RESPONSE;
                        m_axi_bready <= 1'b1;
                    end
                end

                WAIT_RESPONSE: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        rd_ptr       <= rd_ptr + 1;
                        state        <= IDLE;
                    end
                end

                default: begin // Default case for FSM safety
                    state <= IDLE;
                end
            endcase
        end
    end

    assign m_axi_awaddr = mem[rd_ptr].addr;
    assign m_axi_wdata  = mem[rd_ptr].data;

endmodule
