import l2_cache_pkg::*;

module mshr_4entry (
    input  logic           clk,
    input  logic           rst_n,

    // Interface from Control (Allocation)
    input  logic           mshr_alloc_en,
    input  cache_req_t     mshr_alloc_req, 
    output logic           mshr_ready,      // Low if all 4 entries are full

    // Interface to Main Memory (AXI Read)
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

    // Entry States
    typedef enum logic [2:0] {
        IDLE,           // Slot is free
        WAIT_MEM_BUS,   // Waiting to send ARADDR to memory
        WAIT_MEM_DATA,  // Sent ARADDR, waiting for RDATA
        WAIT_REPLAY     // Received data, waiting for Arbiter access
    } mshr_state_t;

    // 4-entry storage table
    mshr_state_t [3:0] state;
    cache_req_t  [3:0] entry_req;
    logic [1023:0] [3:0] fetched_data;

    // --- Status & Stall Logic ---
    logic [2:0] active_count;
    always_comb begin
        active_count = 0;
        for (int i = 0; i < 4; i++) begin
            if (state[i] != IDLE) active_count++;
        end
        mshr_ready = (active_count < 3'd4); // Stall if 4 entries are full
    end

    // -mData Merging Logic (Internal Helper)
    function logic [1023:0] merge_data(input cache_req_t req, input logic [1023:0] mem_data);
        logic [1023:0] result;
        result = mem_data;
        for (int i = 0; i < 128; i++) begin
          if (req.strobe[i]) result[i*8 +: 8] = req.data[i*8 +: 8];
        end
        return result;
    endfunction

    // Pointer for Round-Robin Scheduling
    logic [1:0] mem_req_ptr; // Which entry gets the AXI bus next
    logic [1:0] replay_ptr;  // Which entry replays to Arbiter next

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= '{default: IDLE};
            entry_req         <= '{default: '0};
            fetched_data      <= '{default: '0};
            m_axi_arvalid     <= 1'b0;
            m_axi_rready      <= 1'b0;
            mshr_replay_valid <= 1'b0;
            mem_req_ptr       <= '0;
            replay_ptr        <= '0;
        end else begin
            
            // 1. ALLOCATION: Capture new miss from Control
            if (mshr_alloc_en && mshr_ready) begin
                for (int i = 0; i < 4; i++) begin
                    if (state[i] == IDLE) begin
                        state[i]     <= WAIT_MEM_BUS;
                        entry_req[i] <= mshr_alloc_req;
                        break; 
                    end
                end
            end

            // 2. MEMORY REQUEST: Send ARADDR
            if (!m_axi_arvalid && state[mem_req_ptr] == WAIT_MEM_BUS) begin
                m_axi_arvalid <= 1'b1;
                m_axi_araddr  <= entry_req[mem_req_ptr].addr;
            end else if (m_axi_arvalid && m_axi_arready) begin
                m_axi_arvalid      <= 1'b0;
                state[mem_req_ptr] <= WAIT_MEM_DATA;
                m_axi_rready       <= 1'b1;
                mem_req_ptr        <= mem_req_ptr + 1;
            end

            // 3. MEMORY DATA: Receive RDATA and Merged 
            // Note: Simplification: This assumes in-order returns for AXI-Lite
            if (m_axi_rready && m_axi_rvalid) begin
                for (int i = 0; i < 4; i++) begin
                    if (state[i] == WAIT_MEM_DATA) begin
                        m_axi_rready    <= 1'b0;
                      fetched_data[i] <= (entry_req[i].write) ? merge_data(entry_req[i], m_axi_rdata) : m_axi_rdata;
                        state[i]        <= WAIT_REPLAY;
                        break;
                    end
                end
            end

            // 4. REPLAY: Send back to Arbiter
            if (!mshr_replay_valid && state[replay_ptr] == WAIT_REPLAY) begin
                mshr_replay_valid      <= 1'b1;
                mshr_replay_req.addr   <= entry_req[replay_ptr].addr;
                mshr_replay_req.data   <= fetched_data[replay_ptr];
                mshr_replay_req.write  <= 1'b1; // Refill is always a write
                mshr_replay_req.strobe <= '1;   // Full line entries 
            end else if (mshr_replay_valid && mshr_replay_ready) begin
                mshr_replay_valid <= 1'b0;
                state[replay_ptr] <= IDLE; // Slot is now free
                replay_ptr        <= replay_ptr + 1;
            end
        end
    end

endmodule
