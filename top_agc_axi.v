`timescale 1ns / 1ps

// Complete single-clock AGC peripheral for direct AXI-Lite connection to ARM.
// All alarm inputs are synchronized inside top_agc detector modules.
module top_agc_axi #(
    parameter integer AXI_ADDRESS_WIDTH = 16,
    parameter integer DSA_RANGE_DB      = 27,
    parameter integer DSA_STEP_DB       = 1,
    parameter integer CODE_WIDTH        = 5
) (
    input  wire                         s_axi_aclk,
    input  wire                         s_axi_aresetn,

    input  wire                         s_axi_awvalid,
    input  wire [AXI_ADDRESS_WIDTH-1:0] s_axi_awaddr,
    output wire                         s_axi_awready,
    input  wire                         s_axi_wvalid,
    input  wire [31:0]                  s_axi_wdata,
    input  wire [3:0]                   s_axi_wstrb,
    output wire                         s_axi_wready,
    output wire                         s_axi_bvalid,
    output wire [1:0]                   s_axi_bresp,
    input  wire                         s_axi_bready,
    input  wire                         s_axi_arvalid,
    input  wire [AXI_ADDRESS_WIDTH-1:0] s_axi_araddr,
    output wire                         s_axi_arready,
    output wire                         s_axi_rvalid,
    output wire [1:0]                   s_axi_rresp,
    output wire [31:0]                  s_axi_rdata,
    input  wire                         s_axi_rready,

    input  wire [7:0]                   adc_ov,
    input  wire [7:0]                   adc_or,
    input  wire [7:0]                   adc_th1,
    input  wire [7:0]                   adc_th2,

    output wire [7:0]                   adc_clear_ov,
    output wire [7:0]                   adc_clear_or,

    output wire [CODE_WIDTH-1:0]        adc0_01_dsa_code,
    output wire [CODE_WIDTH-1:0]        adc0_23_dsa_code,
    output wire                         adc0_dsa_update,
    output wire [CODE_WIDTH-1:0]        adc1_01_dsa_code,
    output wire [CODE_WIDTH-1:0]        adc1_23_dsa_code,
    output wire                         adc1_dsa_update,
    output wire [CODE_WIDTH-1:0]        adc2_01_dsa_code,
    output wire [CODE_WIDTH-1:0]        adc2_23_dsa_code,
    output wire                         adc2_dsa_update,
    output wire [CODE_WIDTH-1:0]        adc3_01_dsa_code,
    output wire [CODE_WIDTH-1:0]        adc3_23_dsa_code,
    output wire                         adc3_dsa_update,

    output wire                         agc_freeze_active,
    output wire [CODE_WIDTH-1:0]        current_atten_db,
    output wire [CODE_WIDTH-1:0]        current_hw_dsa_code
);

    localparam integer UP_ADDRESS_WIDTH = AXI_ADDRESS_WIDTH - 2;

    wire                        up_wreq;
    wire [UP_ADDRESS_WIDTH-1:0] up_waddr;
    wire [31:0]                 up_wdata;
    wire                        up_wack;
    wire                        up_rreq;
    wire [UP_ADDRESS_WIDTH-1:0] up_raddr;
    wire [31:0]                 up_rdata;
    wire                        up_rack;

    wire                        axi_clear_ov;
    wire                        axi_clear_or;
    wire                        axi_clear_th1;
    wire                        axi_clear_th2;
    wire                        agc_freeze_req;
    wire [3:0]                  current_fsm_state;
    wire [7:0]                  ov_status_bus_sticky;
    wire [7:0]                  or_status_bus_sticky;
    wire [7:0]                  th1_status_bus_sticky;
    wire [7:0]                  th2_status_bus_sticky;
    wire [31:0]                 unused_config_1;
    wire [31:0]                 unused_config_2;

    up_axi #(
        .AXI_ADDRESS_WIDTH (AXI_ADDRESS_WIDTH)
    ) u_up_axi (
        .up_rstn          (s_axi_aresetn),
        .up_clk           (s_axi_aclk),
        .up_axi_awvalid   (s_axi_awvalid),
        .up_axi_awaddr    (s_axi_awaddr),
        .up_axi_awready   (s_axi_awready),
        .up_axi_wvalid    (s_axi_wvalid),
        .up_axi_wdata     (s_axi_wdata),
        .up_axi_wstrb     (s_axi_wstrb),
        .up_axi_wready    (s_axi_wready),
        .up_axi_bvalid    (s_axi_bvalid),
        .up_axi_bresp     (s_axi_bresp),
        .up_axi_bready    (s_axi_bready),
        .up_axi_arvalid   (s_axi_arvalid),
        .up_axi_araddr    (s_axi_araddr),
        .up_axi_arready   (s_axi_arready),
        .up_axi_rvalid    (s_axi_rvalid),
        .up_axi_rresp     (s_axi_rresp),
        .up_axi_rdata     (s_axi_rdata),
        .up_axi_rready    (s_axi_rready),
        .up_wreq          (up_wreq),
        .up_waddr         (up_waddr),
        .up_wdata         (up_wdata),
        .up_wack          (up_wack),
        .up_rreq          (up_rreq),
        .up_raddr         (up_raddr),
        .up_rdata         (up_rdata),
        .up_rack          (up_rack)
    );

    agc_regmap #(
        .ADDRESS_WIDTH (UP_ADDRESS_WIDTH),
        .CODE_WIDTH    (CODE_WIDTH)
    ) u_agc_regmap (
        .up_clk                 (s_axi_aclk),
        .up_rstn                (s_axi_aresetn),
        .up_wreq                (up_wreq),
        .up_waddr               (up_waddr),
        .up_wdata               (up_wdata),
        .up_wack                (up_wack),
        .up_rreq                (up_rreq),
        .up_raddr               (up_raddr),
        .up_rdata               (up_rdata),
        .up_rack                (up_rack),
        .axi_clear_ov           (axi_clear_ov),
        .axi_clear_or           (axi_clear_or),
        .axi_clear_th1          (axi_clear_th1),
        .axi_clear_th2          (axi_clear_th2),
        .agc_freeze_req         (agc_freeze_req),
        .agc_freeze_active      (agc_freeze_active),
        .current_atten_db       (current_atten_db),
        .current_hw_dsa_code    (current_hw_dsa_code),
        .current_fsm_state      (current_fsm_state),
        .ov_status_bus_sticky   (ov_status_bus_sticky),
        .or_status_bus_sticky   (or_status_bus_sticky),
        .th1_status_bus_sticky  (th1_status_bus_sticky),
        .th2_status_bus_sticky  (th2_status_bus_sticky),
        .agc_config_1           (unused_config_1),
        .agc_config_2           (unused_config_2)
    );

    top_agc #(
        .DSA_RANGE_DB (DSA_RANGE_DB),
        .DSA_STEP_DB  (DSA_STEP_DB),
        .CODE_WIDTH   (CODE_WIDTH)
    ) u_top_agc (
        .clk                    (s_axi_aclk),
        .rst_n                  (s_axi_aresetn),
        .adc0_ov(adc_ov[0]), .adc1_ov(adc_ov[1]), .adc2_ov(adc_ov[2]), .adc3_ov(adc_ov[3]),
        .adc4_ov(adc_ov[4]), .adc5_ov(adc_ov[5]), .adc6_ov(adc_ov[6]), .adc7_ov(adc_ov[7]),
        .adc0_or(adc_or[0]), .adc1_or(adc_or[1]), .adc2_or(adc_or[2]), .adc3_or(adc_or[3]),
        .adc4_or(adc_or[4]), .adc5_or(adc_or[5]), .adc6_or(adc_or[6]), .adc7_or(adc_or[7]),
        .adc0_th1(adc_th1[0]), .adc1_th1(adc_th1[1]), .adc2_th1(adc_th1[2]), .adc3_th1(adc_th1[3]),
        .adc4_th1(adc_th1[4]), .adc5_th1(adc_th1[5]), .adc6_th1(adc_th1[6]), .adc7_th1(adc_th1[7]),
        .adc0_th2(adc_th2[0]), .adc1_th2(adc_th2[1]), .adc2_th2(adc_th2[2]), .adc3_th2(adc_th2[3]),
        .adc4_th2(adc_th2[4]), .adc5_th2(adc_th2[5]), .adc6_th2(adc_th2[6]), .adc7_th2(adc_th2[7]),
        .axi_clear_ov           (axi_clear_ov),
        .axi_clear_or           (axi_clear_or),
        .axi_clear_th1          (axi_clear_th1),
        .axi_clear_th2          (axi_clear_th2),
        .ov_status_bus_sticky   (ov_status_bus_sticky),
        .or_status_bus_sticky   (or_status_bus_sticky),
        .th1_status_bus_sticky  (th1_status_bus_sticky),
        .th2_status_bus_sticky  (th2_status_bus_sticky),
        .agc_freeze_req         (agc_freeze_req),
        .agc_freeze_active      (agc_freeze_active),
        .current_atten_db       (current_atten_db),
        .current_hw_dsa_code    (current_hw_dsa_code),
        .current_fsm_state      (current_fsm_state),
        .adc0_clear_ov(adc_clear_ov[0]), .adc1_clear_ov(adc_clear_ov[1]),
        .adc2_clear_ov(adc_clear_ov[2]), .adc3_clear_ov(adc_clear_ov[3]),
        .adc4_clear_ov(adc_clear_ov[4]), .adc5_clear_ov(adc_clear_ov[5]),
        .adc6_clear_ov(adc_clear_ov[6]), .adc7_clear_ov(adc_clear_ov[7]),
        .adc0_clear_or(adc_clear_or[0]), .adc1_clear_or(adc_clear_or[1]),
        .adc2_clear_or(adc_clear_or[2]), .adc3_clear_or(adc_clear_or[3]),
        .adc4_clear_or(adc_clear_or[4]), .adc5_clear_or(adc_clear_or[5]),
        .adc6_clear_or(adc_clear_or[6]), .adc7_clear_or(adc_clear_or[7]),
        .adc0_01_dsa_code(adc0_01_dsa_code), .adc0_23_dsa_code(adc0_23_dsa_code), .adc0_dsa_update(adc0_dsa_update),
        .adc1_01_dsa_code(adc1_01_dsa_code), .adc1_23_dsa_code(adc1_23_dsa_code), .adc1_dsa_update(adc1_dsa_update),
        .adc2_01_dsa_code(adc2_01_dsa_code), .adc2_23_dsa_code(adc2_23_dsa_code), .adc2_dsa_update(adc2_dsa_update),
        .adc3_01_dsa_code(adc3_01_dsa_code), .adc3_23_dsa_code(adc3_23_dsa_code), .adc3_dsa_update(adc3_dsa_update)
    );

endmodule
