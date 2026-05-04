import l2_cache_pkg::*;

module mshr (
    input  logic           clk,
    input  logic           rst_n,

    // Interface from Control (Allocation)
    input  logic           mshr_alloc_en,
    input  mshr_alloc_t    mshr_alloc_req,   
    output logic           mshr_ready,

    // Interface to Main Memory (AXI Read Channel)
    output logic [31:0]    m_axi_araddr,
    output logic           m_axi_arvalid,
    input  logic           m_axi_arready,

    input  logic [1023:0]  m_axi_rdata,
    input  logic           m_axi_rvalid,
    output logic           m_axi_rready,

    // Interface to Arbiter (Replay)
    output cache_req_t     mshr_replay_req,
    output logic           mshr_replay_valid,
    input  logic           mshr_replay_ready
);

    typedef enum logic [1:0] {
        IDLE,           // Slot is free
        WAIT_MEM_BUS,   // Waiting to send ARADDR to memory
        WAIT_MEM_DATA,  // Sent ARADDR, waiting for RDATA
        WAIT_REPLAY     // Received data, waiting for Arbiter access
    } mshr_state_t;

    // Unpacked array dimension ordering
    mshr_state_t   state [4];
    mshr_alloc_t   entry_req [4];
    logic [1023:0] fetched_data [4];

    // Combinational Priority Encoders (FIX 2: Replaces non-synthesizable loops)

    // 1. Allocation Priority: Find first IDLE slot
    logic [1:0] alloc_idx;
    logic       alloc_rdy;
    always_comb begin
        alloc_idx = 2'b00;
        alloc_rdy = 1'b0;
        if      (state[0] == IDLE) begin alloc_idx = 2'd0; alloc_rdy = 1'b1; end
        else if (state[1] == IDLE) begin alloc_idx = 2'd1; alloc_rdy = 1'b1; end
        else if (state[2] == IDLE) begin alloc_idx = 2'd2; alloc_rdy = 1'b1; end
        else if (state[3] == IDLE) begin alloc_idx = 2'd3; alloc_rdy = 1'b1; end
    end
    assign mshr_ready = alloc_rdy;

    // 2. Memory Request Priority: Find first slot waiting for AXI Bus
    logic [1:0] ar_idx;
    logic       ar_req;
    always_comb begin
        ar_idx = 2'b00;
        ar_req = 1'b0;
        if      (state[0] == WAIT_MEM_BUS) begin ar_idx = 2'd0; ar_req = 1'b1; end
        else if (state[1] == WAIT_MEM_BUS) begin ar_idx = 2'd1; ar_req = 1'b1; end
        else if (state[2] == WAIT_MEM_BUS) begin ar_idx = 2'd2; ar_req = 1'b1; end
        else if (state[3] == WAIT_MEM_BUS) begin ar_idx = 2'd3; ar_req = 1'b1; end
    end

    // 3. Replay Priority: Find first slot ready to write to Data RAM
    logic [1:0] rep_idx;
    logic       rep_req;
    always_comb begin
        rep_idx = 2'b00;
        rep_req = 1'b0;
        if      (state[0] == WAIT_REPLAY) begin rep_idx = 2'd0; rep_req = 1'b1; end
        else if (state[1] == WAIT_REPLAY) begin rep_idx = 2'd1; rep_req = 1'b1; end
        else if (state[2] == WAIT_REPLAY) begin rep_idx = 2'd2; rep_req = 1'b1; end
        else if (state[3] == WAIT_REPLAY) begin rep_idx = 2'd3; rep_req = 1'b1; end
    end

    // Data Merging Helper Function for Partial Writes
    function logic [1023:0] merge_data(input mshr_alloc_t req, input logic [1023:0] mem_data);
        logic [1023:0] result;
        result = mem_data;
        for (int i = 0; i < 128; i++) begin
            if (req.strobe[i]) result[i*8 +: 8] = req.data[i*8 +: 8];
        end
        return result;
    endfunction

    // Main MSHR Synchronous Logic
    
    // Track the active AXI request to prevent pointer skipping
    logic       outstanding_read;
    logic [1:0] read_idx;
    logic [1:0] active_replay_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) begin
                state[i]        <= IDLE;
                entry_req[i]    <= '0;
                fetched_data[i] <= '0;
            end
            m_axi_arvalid     <= 1'b0;
            m_axi_rready      <= 1'b0;
            m_axi_araddr      <= '0;
            mshr_replay_valid <= 1'b0;
            mshr_replay_req   <= '0;
            outstanding_read  <= 1'b0;
            read_idx          <= '0;
            active_replay_idx <= '0;
        end else begin

            // 1. ALLOCATION: Capture new miss from Control Pipeline
            if (mshr_alloc_en && alloc_rdy) begin
                state[alloc_idx]     <= WAIT_MEM_BUS;
                entry_req[alloc_idx] <= mshr_alloc_req;
            end

            // 2. MEMORY REQUEST & RECEIVE (AXI Read Channel)
            if (!outstanding_read) begin
                // Bus is free, launch the next request if one is pending
                if (ar_req) begin
                    outstanding_read <= 1'b1;
                    read_idx         <= ar_idx;
                    m_axi_arvalid    <= 1'b1;
                    m_axi_araddr     <= {entry_req[ar_idx].addr[31:7], 7'b0};
                end
            end else begin
                // Bus is busy, wait for handshakes to complete
                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid   <= 1'b0;
                    m_axi_rready    <= 1'b1;
                    state[read_idx] <= WAIT_MEM_DATA;
                end
                
                if (m_axi_rready && m_axi_rvalid) begin
                    m_axi_rready     <= 1'b0;
                    outstanding_read <= 1'b0; // Free the bus for the next request
                    
                    // Merge incoming memory data with CPU data if this was a write miss
                    fetched_data[read_idx] <= (entry_req[read_idx].is_write) ? 
                                              merge_data(entry_req[read_idx], m_axi_rdata) : 
                                              m_axi_rdata;
                                              
                    state[read_idx]  <= WAIT_REPLAY;
                end
            end

            // 3. REPLAY: Send the fetched/merged line back to the Arbiter
            if (!mshr_replay_valid) begin
                // Arbiter is free, send the next pending replay
                if (rep_req) begin
                    mshr_replay_valid      <= 1'b1;
                    active_replay_idx      <= rep_idx;
                    
                    mshr_replay_req.addr   <= entry_req[rep_idx].addr;
                    mshr_replay_req.data   <= fetched_data[rep_idx];
                    mshr_replay_req.write  <= 1'b1; // Refill is always written into Data RAM
                    mshr_replay_req.strobe <= '1;   // Enable all 128 bytes
                end
            end else begin
                // Wait for the Arbiter to accept the replay
                if (mshr_replay_ready) begin
                    mshr_replay_valid        <= 1'b0;
                    state[active_replay_idx] <= IDLE; // Free the slot
                end
            end

        end
    end

endmodule
