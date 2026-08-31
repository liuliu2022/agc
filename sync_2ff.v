`timescale 1ns / 1ps
//======================================================================
// Module: sync_nff
// Function: Generic N-flip-flop synchronizer for CDC. Supports an
//           arbitrary-width vector of INDEPENDENT single-bit status
//           signals, each bit synchronized by its own independent
//           STAGES-deep flip-flop chain.
//
// Parameters:
//   WIDTH       - number of independent bits to synchronize
//   STAGES      - number of flip-flop stages (>=2). 2 is the standard
//                 minimum for CDC; use 3+ only if MTBF analysis for your
//                 specific silicon/frequency requires it (each extra
//                 stage adds one dst_clk cycle of latency and roughly
//                 squares the MTBF improvement from the previous stage).
//   RESET_VALUE - reset value applied to all stages
//
// IMPORTANT CORRECTNESS NOTE:
//   Safe ONLY for vectors of mutually-independent bits (e.g. per-channel
//   alarm flags), NOT for a multi-bit value that must be captured
//   coherently as a single number (e.g. a binary counter or address).
//   See sync_2ff header for full explanation.
//
// Notes:
//   - ASYNC_REG prevents Vivado from retiming/optimizing the chain.
//   - Add XDC: set_false_path -to [get_pins -hier -filter
//              {NAME =~ *sync_chain_reg[0]*/D}]
//======================================================================

module sync_nff #(
    parameter WIDTH       = 1,
    parameter STAGES      = 2,
    parameter RESET_VALUE = {WIDTH{1'b0}}
) (
    input  wire             dst_clk,
    input  wire             dst_rst_n,   // active-low, synchronous to dst_clk
    input  wire [WIDTH-1:0] async_in,
    output wire [WIDTH-1:0] sync_out
);

    // sync_chain[0] is the metastability-prone first stage;
    // sync_chain[STAGES-1] is the final, clean output stage.
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync_chain [0:STAGES-1];

    integer i;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            for (i = 0; i < STAGES; i = i + 1)
                sync_chain[i] <= RESET_VALUE;
        end else begin
            sync_chain[0] <= async_in;
            for (i = 1; i < STAGES; i = i + 1)
                sync_chain[i] <= sync_chain[i-1];
        end
    end

    assign sync_out = sync_chain[STAGES-1];

endmodule
