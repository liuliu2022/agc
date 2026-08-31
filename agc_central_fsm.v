`timescale 1ns / 1ps

module agc_central_fsm #(
    parameter integer CODE_WIDTH       = 5,
    parameter integer DSA_RANGE_DB     = 27,
    parameter integer STEP_FAST_DB     = 5,
    parameter integer STEP_SLOW_DB     = 1,
    parameter integer WAIT_OV_SETTLE   = 20,
    parameter integer DEAD_TIME_OV     = 100000,
    parameter integer DEAD_TIME_OR     = 500,
    parameter integer DEAD_TIME_TH1    = 200,
    parameter integer DEAD_TIME_TH2    = 5000
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  global_ov_alert,
    input  wire                  global_or_alert,
    input  wire                  global_th1_alert,
    input  wire                  global_th2_weak,

    // Level request from ARM. Keep high for the complete DMA interval.
    input  wire                  freeze_req,
    output wire                  freeze_active,
    output wire [3:0]            fsm_state,

    output reg  [CODE_WIDTH-1:0] global_dsa_code,
    output reg                   global_dsa_update,
    output reg                   global_clear_ov,
    output reg                   global_clear_or
);

    localparam [CODE_WIDTH-1:0] DSA_MAX_VAL = DSA_RANGE_DB;
    localparam [CODE_WIDTH-1:0] DSA_MIN_VAL = {CODE_WIDTH{1'b0}};
    localparam [CODE_WIDTH-1:0] STEP_FAST   = STEP_FAST_DB;
    localparam [CODE_WIDTH-1:0] STEP_SLOW   = STEP_SLOW_DB;

    localparam [3:0] S_IDLE           = 4'd0,
                     S_OV_SET_DSA     = 4'd1,
                     S_OV_WAIT_SETTLE = 4'd2,
                     S_OV_CLEAR_LOCK  = 4'd3,
                     S_DEAD_TIME      = 4'd15;

    reg [3:0]  state;
    reg [31:0] delay_cnt;
    reg [31:0] current_dead_time;

    // The acknowledgement is delayed until every update accepted before the
    // request has reached the RFDC-facing DSA output registers.
    // Four cycles include the FSM command register, converter register and
    // the two fanout registers.
    reg [3:0] freeze_pipe;
    reg       init_pending;
    wire freeze_hold = freeze_req | (|freeze_pipe);

    assign freeze_active = freeze_req & freeze_pipe[3] & ~init_pending;
    assign fsm_state     = state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            freeze_pipe <= 4'b0000;
        else
            freeze_pipe <= {freeze_pipe[2:0], freeze_req};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            delay_cnt         <= 32'd0;
            current_dead_time <= 32'd0;
            init_pending      <= 1'b1;
            global_dsa_code   <= DSA_MAX_VAL;
            global_dsa_update <= 1'b0;
            global_clear_ov   <= 1'b0;
            global_clear_or   <= 1'b0;
        end else begin
            global_dsa_update <= 1'b0;
            global_clear_ov   <= 1'b0;
            global_clear_or   <= 1'b0;

            if (init_pending) begin
                // Explicitly latch the safe maximum attenuation into RFDC;
                // driving the code bus alone is not enough without update.
                init_pending      <= 1'b0;
                global_dsa_code   <= DSA_MAX_VAL;
                global_dsa_update <= 1'b1;
                state             <= S_IDLE;
                delay_cnt         <= 32'd0;
            end else if (freeze_hold) begin
                // Hold the last attenuation. Detector sticky bits continue to
                // record alarms while DMA capture is in progress.
                state             <= S_IDLE;
                delay_cnt         <= 32'd0;
                current_dead_time <= 32'd0;
            end else begin
                case (state)
                    S_IDLE: begin
                        delay_cnt <= 32'd0;

                        if (global_ov_alert) begin
                            state <= S_OV_SET_DSA;
                        end else if (global_or_alert) begin
                            if (global_dsa_code >= (DSA_MAX_VAL - STEP_FAST))
                                global_dsa_code <= DSA_MAX_VAL;
                            else
                                global_dsa_code <= global_dsa_code + STEP_FAST;

                            if (global_dsa_code != DSA_MAX_VAL)
                                global_dsa_update <= 1'b1;
                            global_clear_or   <= 1'b1;
                            current_dead_time <= DEAD_TIME_OR;
                            state             <= S_DEAD_TIME;
                        end else if (global_th1_alert) begin
                            if (global_dsa_code != DSA_MAX_VAL) begin
                                if (global_dsa_code >= (DSA_MAX_VAL - STEP_SLOW))
                                    global_dsa_code <= DSA_MAX_VAL;
                                else
                                    global_dsa_code <= global_dsa_code + STEP_SLOW;
                                global_dsa_update <= 1'b1;
                            end
                            current_dead_time <= DEAD_TIME_TH1;
                            state             <= S_DEAD_TIME;
                        end else if (global_th2_weak) begin
                            if (global_dsa_code != DSA_MIN_VAL) begin
                                if (global_dsa_code <= STEP_SLOW)
                                    global_dsa_code <= DSA_MIN_VAL;
                                else
                                    global_dsa_code <= global_dsa_code - STEP_SLOW;
                                global_dsa_update <= 1'b1;
                                current_dead_time <= DEAD_TIME_TH2;
                                state             <= S_DEAD_TIME;
                            end
                        end
                    end

                    S_OV_SET_DSA: begin
                        global_dsa_code <= DSA_MAX_VAL;
                        if (global_dsa_code != DSA_MAX_VAL)
                            global_dsa_update <= 1'b1;
                        delay_cnt <= 32'd0;
                        state     <= S_OV_WAIT_SETTLE;
                    end

                    S_OV_WAIT_SETTLE: begin
                        if (delay_cnt + 1 < WAIT_OV_SETTLE)
                            delay_cnt <= delay_cnt + 1'b1;
                        else begin
                            delay_cnt <= 32'd0;
                            state     <= S_OV_CLEAR_LOCK;
                        end
                    end

                    S_OV_CLEAR_LOCK: begin
                        global_clear_ov   <= 1'b1;
                        current_dead_time <= DEAD_TIME_OV;
                        state             <= S_DEAD_TIME;
                    end

                    S_DEAD_TIME: begin
                        if (global_ov_alert) begin
                            delay_cnt <= 32'd0;
                            state     <= S_OV_SET_DSA;
                        end else if (delay_cnt + 1 < current_dead_time) begin
                            delay_cnt <= delay_cnt + 1'b1;
                        end else begin
                            delay_cnt <= 32'd0;
                            state     <= S_IDLE;
                        end
                    end

                    default: begin
                        delay_cnt <= 32'd0;
                        state     <= S_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
