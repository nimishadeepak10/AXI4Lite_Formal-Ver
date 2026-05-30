// =============================================================================
// axi4lite_slave.sv
// Single-word AXI4-Lite slave with write + read support.
//
// Write FSM: ST_IDLE -> ST_GOT_AW / ST_GOT_W -> ST_WAIT_B -> ST_IDLE
//   - AW and W may arrive in either order.
// Read FSM:  RD_IDLE -> RD_WAIT_R -> RD_IDLE
//   - AR handshake loads mem into RDATA; RVALID held until RREADY.
//
// Mutual exclusion: only one transaction at a time (write has priority at idle).
// Ready signals are combinational (always_comb) for same-cycle handshake clarity.
// Formal properties are instantiated as props_inst (SymbiYosys / OSS Yosys).
// =============================================================================

module axi_lite_slave (
    input  logic        ACLK,
    input  logic        ARESETN,

    // Write address channel
    input  logic [31:0] AWADDR,
    input  logic        AWVALID,
    output logic        AWREADY,

    // Write data channel
    input  logic [31:0] WDATA,
    input  logic        WVALID,
    output logic        WREADY,

    // Write response channel
    output logic [1:0]  BRESP,
    output logic        BVALID,
    input  logic        BREADY,

    // Read address channel
    input  logic [31:0] ARADDR,
    input  logic        ARVALID,
    output logic        ARREADY,

    // Read data channel
    output logic [31:0] RDATA,
    output logic [1:0]  RRESP,
    output logic        RVALID,
    input  logic        RREADY
);

    typedef enum logic [1:0] {
        ST_IDLE   = 2'b00,
        ST_GOT_AW = 2'b01,
        ST_GOT_W  = 2'b10,
        ST_WAIT_B = 2'b11
    } wr_state_t;

    typedef enum logic [1:0] {
        RD_IDLE   = 2'b00,
        RD_WAIT_R = 2'b01
    } rd_state_t;

    wr_state_t   wr_state;
    rd_state_t   rd_state;
    logic [31:0] mem;
    logic [31:0] awaddr_l;
    logic [31:0] wdata_l;
    logic [31:0] araddr_l;

    logic write_busy;
    logic read_busy;

    // write_busy: FSM active, or master presenting AW/W while both FSMs idle.
    assign write_busy = (wr_state != ST_IDLE) ||
                        (wr_state == ST_IDLE && rd_state == RD_IDLE && (AWVALID || WVALID));

    // read_busy: waiting for RREADY, or AR presented while idle and not write_busy.
    assign read_busy  = (rd_state == RD_WAIT_R) ||
                        (rd_state == RD_IDLE && wr_state == ST_IDLE && ARVALID && !write_busy);

    // -------------------------------------------------------------------------
    // Combinational ready generation
    // -------------------------------------------------------------------------
    always_comb begin
        AWREADY = 1'b0;
        WREADY  = 1'b0;
        ARREADY = 1'b0;

        unique case (wr_state)
            ST_IDLE: begin
                // Stall write channel when read active or AR presented
                if (!read_busy && !ARVALID) begin
                    AWREADY = 1'b1;
                    WREADY  = 1'b1;
                end
            end
            ST_GOT_AW: WREADY  = !read_busy;
            ST_GOT_W:  AWREADY = !read_busy;
            default: ;
        endcase

        // Accept reads only when fully idle on write side and no AW/W presented
        if (rd_state == RD_IDLE && wr_state == ST_IDLE && !AWVALID && !WVALID)
            ARREADY = 1'b1;
    end

    // -------------------------------------------------------------------------
    // Sequential state and datapath
    // -------------------------------------------------------------------------
    always_ff @(posedge ACLK) begin
        if (!ARESETN) begin
            wr_state  <= ST_IDLE;
            rd_state  <= RD_IDLE;
            BVALID    <= 1'b0;
            BRESP     <= 2'b00;
            RVALID    <= 1'b0;
            RDATA     <= 32'b0;
            RRESP     <= 2'b00;
            mem       <= 32'b0;
            awaddr_l  <= 32'b0;
            wdata_l   <= 32'b0;
            araddr_l  <= 32'b0;
        end else begin
            unique case (wr_state)
                ST_IDLE: begin
                    BVALID <= 1'b0;

                    if (!read_busy && (rd_state == RD_IDLE) &&
                        AWVALID && AWREADY && WVALID && WREADY) begin
                        mem      <= WDATA;
                        BRESP    <= 2'b00;
                        BVALID   <= 1'b1;
                        wr_state <= ST_WAIT_B;
                    end else if (!read_busy && (rd_state == RD_IDLE) && AWVALID && AWREADY) begin
                        awaddr_l <= AWADDR;
                        wr_state <= ST_GOT_AW;
                    end else if (!read_busy && (rd_state == RD_IDLE) && WVALID && WREADY) begin
                        wdata_l  <= WDATA;
                        wr_state <= ST_GOT_W;
                    end
                end

                ST_GOT_AW: begin
                    if (WVALID && WREADY && !read_busy) begin
                        mem      <= WDATA;
                        BRESP    <= 2'b00;
                        BVALID   <= 1'b1;
                        wr_state <= ST_WAIT_B;
                    end
                end

                ST_GOT_W: begin
                    if (AWVALID && AWREADY && !read_busy) begin
                        mem      <= wdata_l;
                        BRESP    <= 2'b00;
                        BVALID   <= 1'b1;
                        wr_state <= ST_WAIT_B;
                    end
                end

                ST_WAIT_B: begin
                    BVALID <= 1'b1;
                    if (BREADY) begin
                        BVALID   <= 1'b0;
                        wr_state <= ST_IDLE;
                    end
                end

                default: wr_state <= ST_IDLE;
            endcase

            unique case (rd_state)
                RD_IDLE: begin
                    RVALID <= 1'b0;
                    if (ARVALID && ARREADY) begin
                        araddr_l <= ARADDR;
                        RDATA    <= mem;
                        RRESP    <= 2'b00;
                        RVALID   <= 1'b1;
                        rd_state <= RD_WAIT_R;
                    end
                end

                RD_WAIT_R: begin
                    RVALID <= 1'b1;
                    if (RREADY) begin
                        RVALID   <= 1'b0;
                        rd_state <= RD_IDLE;
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // Direct instantiation required for OSS Yosys (bind is stripped as unused)
    properties props_inst (
        .ACLK     (ACLK),
        .ARESETN  (ARESETN),
        .AWADDR   (AWADDR),
        .AWVALID  (AWVALID),
        .AWREADY  (AWREADY),
        .WDATA    (WDATA),
        .WVALID   (WVALID),
        .WREADY   (WREADY),
        .BRESP    (BRESP),
        .BVALID   (BVALID),
        .BREADY   (BREADY),
        .ARADDR   (ARADDR),
        .ARVALID  (ARVALID),
        .ARREADY  (ARREADY),
        .RDATA    (RDATA),
        .RRESP    (RRESP),
        .RVALID   (RVALID),
        .RREADY   (RREADY),
        .wr_state (wr_state),
        .rd_state (rd_state),
        .mem      (mem)
    );

endmodule
