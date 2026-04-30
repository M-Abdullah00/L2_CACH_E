import l2_cache_pkg::*;

module control (
    input  logic          clk,
    input  logic          rst_n,

    input  logic          winner_req_valid,
    input  cache_req_t    winner_req,
    input  cache_addr_t   addr_split,

    input  logic          hit,
    input  logic [1:0]    hit_way,

    input  cache_meta_t   meta_w0,
    input  cache_meta_t   meta_w1,
    input  cache_meta_t   meta_w2,
    input  cache_meta_t   meta_w3,

    input  logic          mshr_ready,
    input  logic          wb_ready,

    input  logic [1023:0] data_ram_rdata,

    output logic          data_ram_rd_en,
    output logic          data_ram_wr_en,
    output logic [1:0]    data_ram_way,
    output logic [6:0]    data_ram_index,
    output logic [1023:0] data_ram_wdata,

    output logic          tag_wr_en,
    output logic [6:0]    tag_wr_index,
    output logic [1:0]    tag_wr_way,
    output cache_meta_t   tag_wr_meta,

    // no external PLRU input needed
    // control owns PLRU state internally

    output logic          mshr_alloc_en,
    output logic [31:0]   mshr_addr,
    output logic          mshr_is_write,
    output logic [1023:0] mshr_wr_data,
    output logic [127:0]  mshr_wr_strobe,

    output logic          wb_en,
    output logic [31:0]   wb_addr,
    output logic [1023:0] wb_data,

    output logic          cpu_resp_valid,
    output logic [1023:0] cpu_resp_data,

    output logic          stall
);

    logic [2:0] plru_mem [128];

    cache_meta_t  victim_meta;      // metadata of victim way
    logic [1:0]   victim_way;       // which way to evict
    logic [1023:0] merged_line;     // partial write merged result
    logic [2:0]   current_plru;    // PLRU bits for current set
    logic [2:0]   updated_plru;    // new PLRU bits after access


    // get current PLRU bits for the requested set
    assign current_plru = plru_mem[addr_split.index];

    // decode victim way from PLRU tree
    // bit2=0 → left  → look at bit1
    // bit2=1 → right → look at bit0
    always_comb begin
        if (!current_plru[2]) begin
            // go left subtree
            if (!current_plru[1])
                victim_way = 2'd0;   // bit1=0 → W0
            else
                victim_way = 2'd1;   // bit1=1 → W1
        end else begin
            // go right subtree
            if (!current_plru[0])
                victim_way = 2'd2;   // bit0=0 → W2
            else
                victim_way = 2'd3;   // bit0=1 → W3
        end
    end

    // get metadata of victim way
    // needed to check dirty bit before eviction
    always_comb begin
        case (victim_way)
            2'd0:    victim_meta = meta_w0;
            2'd1:    victim_meta = meta_w1;
            2'd2:    victim_meta = meta_w2;
            2'd3:    victim_meta = meta_w3;
            default: victim_meta = meta_w0;
        endcase
    end

    logic [1:0]  plru_way_accessed; // which way triggered PLRU update
    logic        plru_update_en;    // should PLRU be updated this cycle

    always_comb begin
        updated_plru = current_plru; // default keep same

        if (plru_update_en) begin
            case (plru_way_accessed)

                2'd0: begin
                    // path to W0: bit2=LEFT, bit1=LEFT
                    // flip to point away: bit2=1, bit1=1
                    updated_plru[2] = 1'b1;
                    updated_plru[1] = 1'b1;
                    // bit0 unchanged
                end

                2'd1: begin
                    // path to W1: bit2=LEFT, bit1=RIGHT
                    // flip to point away: bit2=1, bit1=0
                    updated_plru[2] = 1'b1;
                    updated_plru[1] = 1'b0;
                    // bit0 unchanged
                end

                2'd2: begin
                    // path to W2: bit2=RIGHT, bit0=LEFT
                    // flip to point away: bit2=0, bit0=1
                    updated_plru[2] = 1'b0;
                    updated_plru[0] = 1'b1;
                    // bit1 unchanged
                end

                2'd3: begin
                    // path to W3: bit2=RIGHT, bit0=RIGHT
                    // flip to point away: bit2=0, bit0=0
                    updated_plru[2] = 1'b0;
                    updated_plru[0] = 1'b0;
                    // bit1 unchanged
                end

                default: updated_plru = current_plru;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // clear all PLRU bits on reset
            for (int i = 0; i < 128; i++)
                plru_mem[i] <= 3'b000;
        end else if (plru_update_en) begin
            // write updated PLRU for this set
            plru_mem[addr_split.index] <= updated_plru;
        end
    end

    always_comb begin
        merged_line = data_ram_rdata; // start with existing line
        for (int i = 0; i < 128; i++) begin
            if (winner_req.strobe[i])
                merged_line[i*8 +: 8] = winner_req.data[i*8 +: 8];
            // else keep data_ram_rdata byte unchanged
        end
    end

    always_comb begin

        data_ram_rd_en  = 1'b0;
        data_ram_wr_en  = 1'b0;
        data_ram_way    = 2'd0;
        data_ram_index  = 7'd0;
        data_ram_wdata  = '0;

        tag_wr_en       = 1'b0;
        tag_wr_index    = 7'd0;
        tag_wr_way      = 2'd0;
        tag_wr_meta     = '0;

        plru_update_en      = 1'b0;
        plru_way_accessed   = 2'd0;

        mshr_alloc_en   = 1'b0;
        mshr_addr       = 32'd0;
        mshr_is_write   = 1'b0;
        mshr_wr_data    = '0;
        mshr_wr_strobe  = '0;

        wb_en           = 1'b0;
        wb_addr         = 32'd0;
        wb_data         = '0;

        cpu_resp_valid  = 1'b0;
        cpu_resp_data   = '0;

        stall           = 1'b0;

        if (winner_req_valid) begin

            if (hit) begin

                if (!winner_req.write) begin

                    // read correct way from Data RAM
                    data_ram_rd_en = 1'b1;
                    data_ram_way   = hit_way;
                    data_ram_index = addr_split.index;

                    // send data to CPU immediately
                    cpu_resp_valid = 1'b1;
                    cpu_resp_data  = data_ram_rdata;

                    // update PLRU — protect hit way
                    plru_update_en    = 1'b1;
                    plru_way_accessed = hit_way;

                    // no memory access needed
                    // no tag RAM update needed
                    // no stall needed
                    stall = 1'b0;

                end else begin

                    // step 1: read existing line from Data RAM
                    //         needed for partial write merge
                    data_ram_rd_en = 1'b1;
                    data_ram_way   = hit_way;
                    data_ram_index = addr_split.index;

                    // step 2: write merged line back to Data RAM
                    // merged_line computed above in PART 4
                    // combines existing bytes with new CPU bytes
                    data_ram_wr_en = 1'b1;
                    data_ram_wdata = merged_line;

                    // step 3: update Tag RAM — set dirty=1
                    // memory no longer has latest copy
                    tag_wr_en             = 1'b1;
                    tag_wr_index          = addr_split.index;
                    tag_wr_way            = hit_way;
                    tag_wr_meta.tag       = addr_split.tag;
                    tag_wr_meta.valid     = 1'b1;
                    tag_wr_meta.dirty     = 1'b1;

                    // step 4: update PLRU — protect hit way
                    plru_update_en    = 1'b1;
                    plru_way_accessed = hit_way;

                    // acknowledge CPU
                    cpu_resp_valid = 1'b1;
                    stall          = 1'b0;

                end

            end else begin

                // stall pipeline — miss takes time
                stall = 1'b1;

                if (victim_meta.valid && victim_meta.dirty) begin

                    if (wb_ready) begin

                        // read dirty line from Data RAM
                        data_ram_rd_en = 1'b1;
                        data_ram_way   = victim_way;
                        data_ram_index = addr_split.index;

                        // send dirty line to write buffer
                        // IMPORTANT: use victim_meta.tag for address
                        // NOT addr_split.tag
                        // victim has its own tag, not the new request tag
                        wb_en   = 1'b1;
                        wb_addr = {victim_meta.tag,    // victim's tag
                                   addr_split.index,   // same set
                                   7'b0};              // offset=0 full line
                        wb_data = data_ram_rdata;      // dirty line content

                    end
                    // if wb_ready=0: stay stalled, do nothing
                    // pipeline will retry next cycle

                end
                if (mshr_ready &&
                    (!victim_meta.dirty ||
                     !victim_meta.valid ||
                     wb_ready))
                begin

                    mshr_alloc_en = 1'b1;
                    mshr_addr     = {addr_split.tag,
                                     addr_split.index,
                                     7'b0};

                    if (!winner_req.write) begin
                        mshr_is_write  = 1'b0;
                        mshr_wr_data   = '0;
                        mshr_wr_strobe = '0;

                    end else begin

                        mshr_is_write  = 1'b1;
                        mshr_wr_data   = winner_req.data;
                        mshr_wr_strobe = winner_req.strobe;

                    end

                    // MSHR accepted — release stall
                    // MSHR now owns the miss handling
                    // it will generate replay when data returns
                    stall = 1'b0;

                end

            end
        end
    end

endmodule