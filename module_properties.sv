// =============================================================================
// module_properties.sv
// Formal verification properties for axi_lite_slave.
//
// Tool flow : SymbiYosys + OSS Yosys (immediate assertions, not concurrent SVA)
// Top module: axi_lite_slave (properties instantiated inside DUT)
//
// Property groups:
//   - Master assumptions (AW/W/AR hold valid + stable while stalled)
//   - Write B-channel protocol + FSM encoding + mem update rules
//   - Read  R-channel protocol + FSM encoding + RDATA == mem
//   - Write/read mutual exclusion
//   - Cover points for reachability
//
// Induction note: response/data stability uses $past(VALID && !READY) so the
// check applies only during a stall, not on the first cycle VALID rises.
// =============================================================================

module properties (
    input  logic        ACLK,
    input  logic        ARESETN,
    input  logic [31:0] AWADDR,
    input  logic        AWVALID,
    input  logic        AWREADY,
    input  logic [31:0] WDATA,
    input  logic        WVALID,
    input  logic        WREADY,
    input  logic [1:0]  BRESP,
    input  logic        BVALID,
    input  logic        BREADY,
    input  logic [31:0] ARADDR,
    input  logic        ARVALID,
    input  logic        ARREADY,
    input  logic [31:0] RDATA,
    input  logic [1:0]  RRESP,
    input  logic        RVALID,
    input  logic        RREADY,
    input  logic [1:0]  wr_state,
    input  logic [1:0]  rd_state,
    input  logic [31:0] mem
);

    logic read_busy;
    logic write_busy;

    assign write_busy = (wr_state != ST_IDLE) ||
                        (wr_state == ST_IDLE && rd_state == RD_IDLE && (AWVALID || WVALID));

    assign read_busy  = (rd_state == RD_WAIT_R) ||
                        (rd_state == RD_IDLE && wr_state == ST_IDLE && ARVALID && !write_busy);

    localparam logic [1:0] ST_IDLE   = 2'b00;
    localparam logic [1:0] ST_GOT_AW = 2'b01;
    localparam logic [1:0] ST_GOT_W  = 2'b10;
    localparam logic [1:0] ST_WAIT_B = 2'b11;

    localparam logic [1:0] RD_IDLE   = 2'b00;
    localparam logic [1:0] RD_WAIT_R = 2'b01;

    logic formal_en;
    logic active = 1'b0;

    assign formal_en = ARESETN;

    // Skip first post-reset cycle (avoids $past edge cases at time 0)
    always @(posedge ACLK)
        active <= ARESETN;

    // -------------------------------------------------------------------------
    // Environment constraints
    // -------------------------------------------------------------------------
    initial begin
        assume(!BVALID);
        assume(!RVALID);
        assume(!AWREADY);
        assume(!WREADY);
        assume(!ARREADY);
        assume(wr_state == ST_IDLE);
        assume(rd_state == RD_IDLE);
    end

    always @(posedge ACLK)
        assume(ARESETN);

    // -------------------------------------------------------------------------
    // Master assumptions — write (AW/W)
    // -------------------------------------------------------------------------
    always @(posedge ACLK) begin
        if ((active && formal_en)) begin
            if ($past(AWVALID && !AWREADY))
                assume(AWVALID);
            if (AWVALID && !AWREADY)
                assume(AWADDR == $past(AWADDR));
            if ($past(WVALID && !WREADY))
                assume(WVALID);
            if (WVALID && !WREADY)
                assume(WDATA == $past(WDATA));
        end
    end

    // -------------------------------------------------------------------------
    // Master assumptions — read (AR)
    // -------------------------------------------------------------------------
    always @(posedge ACLK) begin
        if ((active && formal_en)) begin
            if ($past(ARVALID && !ARREADY))
                assume(ARVALID);
            if (ARVALID && !ARREADY)
                assume(ARADDR == $past(ARADDR));
        end
    end

    // -------------------------------------------------------------------------
    // Write B channel
    // -------------------------------------------------------------------------

    // p_bvalid_stable_until_bready
    always @(posedge ACLK) begin
        if (active && $past(BVALID && !BREADY))
            assert(BVALID);
    end

    // p_bresp_stable_during_b_stall (use $past guard for induction)
    always @(posedge ACLK) begin
        if ((active && formal_en) && $past(BVALID && !BREADY))
            assert(BRESP == $past(BRESP));
    end

    // p_bresp_legal_encoding
    always @(posedge ACLK) begin
        if ((active && formal_en) && BVALID)
            assert(BRESP == 2'b00 || BRESP == 2'b10);
    end

    // p_bvalid_deassert_after_handshake
    always @(posedge ACLK) begin
        if ((active && formal_en) && $past(BVALID && BREADY))
            assert(!BVALID);
    end

    // p_no_new_write_while_b_pending
    always @(posedge ACLK) begin
        if ((active && formal_en) && (BVALID && !BREADY)) begin
            assert(!(AWVALID && AWREADY));
            assert(!(WVALID && WREADY));
            assert(!AWREADY && !WREADY);
        end
    end

    // p_bvalid_only_after_complete_write
    always @(posedge ACLK) begin
        if ((active && formal_en) && BVALID && !$past(BVALID))
            assert(
                ($past(wr_state) == ST_IDLE   && $past(AWVALID && AWREADY && WVALID && WREADY)) ||
                ($past(wr_state) == ST_GOT_AW && $past(WVALID && WREADY))                       ||
                ($past(wr_state) == ST_GOT_W  && $past(AWVALID && AWREADY))
            );
    end

    // p_mem_updates_only_on_complete_write
    always @(posedge ACLK) begin
        if ((active && formal_en) && (mem != $past(mem)))
            assert(
                ($past(wr_state) == ST_IDLE   && $past(AWVALID && AWREADY && WVALID && WREADY)) ||
                ($past(wr_state) == ST_GOT_AW && $past(WVALID && WREADY))                       ||
                ($past(wr_state) == ST_GOT_W  && $past(AWVALID && AWREADY))
            );
    end

    // -------------------------------------------------------------------------
    // Write FSM encoding
    // -------------------------------------------------------------------------

    // p_wr_idle_encoding
    always @(posedge ACLK) begin
        if ((active && formal_en) && (wr_state == ST_IDLE) && (rd_state == RD_IDLE)) begin
            assert(!BVALID);
            if (!ARVALID && !AWVALID && !WVALID)
                assert(AWREADY && WREADY);
        end
    end

    // p_wr_got_aw_encoding
    always @(posedge ACLK) begin
        if ((active && formal_en) && (wr_state == ST_GOT_AW))
            assert(!AWREADY && (read_busy ? !WREADY : WREADY));
    end

    // p_wr_got_w_encoding
    always @(posedge ACLK) begin
        if ((active && formal_en) && (wr_state == ST_GOT_W))
            assert((read_busy ? !AWREADY : AWREADY) && !WREADY);
    end

    // p_wr_wait_b_encoding
    always @(posedge ACLK) begin
        if ((active && formal_en) && (wr_state == ST_WAIT_B))
            assert(!AWREADY && !WREADY && BVALID);
    end

    // -------------------------------------------------------------------------
    // Read R channel
    // -------------------------------------------------------------------------

    // p_rvalid_stable_until_rready
    always @(posedge ACLK) begin
        if ((active && formal_en) && $past(RVALID && !RREADY))
            assert(RVALID);
    end

    // p_rresp_rdata_stable_during_r_stall (use $past guard for induction)
    always @(posedge ACLK) begin
        if ((active && formal_en) && $past(RVALID && !RREADY)) begin
            assert(RRESP == $past(RRESP));
            assert(RDATA == $past(RDATA));
        end
    end

    // p_rresp_legal_encoding
    always @(posedge ACLK) begin
        if ((active && formal_en) && RVALID)
            assert(RRESP == 2'b00 || RRESP == 2'b10);
    end

    // p_rdata_matches_mem (single-word slave, no address decode)
    always @(posedge ACLK) begin
        if ((active && formal_en) && RVALID)
            assert(RDATA == mem);
    end

    // p_rvalid_deassert_after_handshake
    always @(posedge ACLK) begin
        if ((active && formal_en) && $past(RVALID && RREADY))
            assert(!RVALID);
    end

    // p_no_new_traffic_while_r_pending
    always @(posedge ACLK) begin
        if ((active && formal_en) && (RVALID && !RREADY)) begin
            assert(!(ARVALID && ARREADY));
            assert(!ARREADY);
            assert(!AWREADY && !WREADY);
        end
    end

    // -------------------------------------------------------------------------
    // Read FSM encoding
    // -------------------------------------------------------------------------

    // p_rd_idle_encoding
    always @(posedge ACLK) begin
        if ((active && formal_en) && (rd_state == RD_IDLE))
            assert(!RVALID);
    end

    // p_rd_wait_r_encoding
    always @(posedge ACLK) begin
        if ((active && formal_en) && (rd_state == RD_WAIT_R))
            assert(!ARREADY && RVALID);
    end

    // -------------------------------------------------------------------------
    // Write/read mutual exclusion
    // -------------------------------------------------------------------------

    // p_no_ar_while_write_busy
    always @(posedge ACLK) begin
        if ((active && formal_en) && (rd_state == RD_IDLE) && write_busy)
            assert(!ARREADY);
    end

    // p_no_write_while_read_pending
    always @(posedge ACLK) begin
        if ((active && formal_en) && (rd_state == RD_WAIT_R))
            assert(wr_state == ST_IDLE && !AWREADY && !WREADY);
    end

    // -------------------------------------------------------------------------
    // Cover points (reachability — not proof obligations)
    // -------------------------------------------------------------------------
    always @(posedge ACLK) begin
        if (formal_en) begin
            cover(AWVALID && AWREADY && WVALID && WREADY);
            cover(BVALID && BREADY && (BRESP == 2'b00));
            cover(ARVALID && ARREADY);
            cover(RVALID && RREADY && (RRESP == 2'b00));
        end
    end

endmodule
