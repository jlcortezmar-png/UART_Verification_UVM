`timescale 1ns / 1ps
interface uart_if;
    logic clk;
    logic rst;
    logic rx;
    logic [7:0] tx_data;
    logic newd;
    logic uclktx;
    logic uclkrx;
    logic tx;
    logic [7:0] rx_data;
    logic done_tx;
    logic done_rx;
endinterface

module uart_top#(
    parameter clk_freq = 1000000,
    parameter baud_rate = 9600
)(
    input clk,rst,
    input rx,
    input [7:0] tx_data,
    input newd,

    output tx,
    output [7:0] rx_data,
    output done_tx,
    output done_rx
);
    uart_tx #(clk_freq, baud_rate) dut_tx (clk,rst,newd,tx_data,tx,done_tx);
    uart_rx #(clk_freq, baud_rate) dut_rx (clk,rst,rx,rx_data,done_rx);

endmodule

module uart_tx#(
    parameter clk_freq = 1000000,
    parameter baud_rate = 9600
)(
    input clk,
    input rst,
    input newd,
    input [7:0] tx_data,

    output reg tx,
    output reg done_tx
);
    localparam clkcount = (clk_freq/baud_rate);
    enum bit [1:0] {idle = 2'b00, start = 2'b01, transfer = 2'b10, done = 2'b11} state;

    int count = 0;
    int count_bits = 0;
    reg uclk = 1'b0;
    reg [7:0] mem;

    always @(posedge clk) begin
        if(count < (clkcount/2))
            count <= count + 1;
        else begin
            count <= 0;
            uclk <= ~uclk;
        end 
    end

    always @(posedge uclk) begin
        if(rst)
            state <= idle;
        else begin
            case (state) 
                idle: begin
                    count_bits <= 0;
                    tx <= 1'b1;
                    done_tx <= 1'b0;

                    if(newd == 1) begin
                        tx <= 1'b0;
                        mem <= tx_data;
                        state <= transfer;
                    end else
                        state <= idle;
                end

                transfer: begin
                    if (count_bits < 8) begin
                        tx <= mem[count_bits];
                        count_bits <= count_bits + 1;
                        state <= transfer;

                    end else begin
                        tx <= 1'b1;
                        count_bits <= 0;
                        done_tx <= 1'b1;
                        state <= idle;
                    end
                end
            endcase
        end
    end
endmodule

module uart_rx#(
    parameter clk_freq = 1000000,
    parameter baud_rate = 9600
)(
    input clk,
    input rst,
    input rx,          

    output reg [7:0] rx_data,   
    output reg done_rx
);                              

    localparam clkcount = (clk_freq/baud_rate);
    enum bit [1:0] {idle = 2'b00, start = 2'b01} state;
    int count = 0;
    int count_bits = 0;
    reg uclk = 0;

    always @(posedge clk) begin
        if(count < (clkcount/2))
            count <= count + 1;
        else begin
            count <= 0;
            uclk <= ~uclk;
        end 
    end

    always @(posedge uclk) begin
        if(rst) begin
            count_bits <= 0;
            done_rx <= 1'b0;
            rx_data <= 8'b00000000;
        end else begin
            case (state)
                idle: begin
                    done_rx <= 1'b0;
                    count_bits <= 0;
                    if(rx == 0) begin
                        state <= start;
                    end else
                        state <= idle;
                end

                start: begin
                    if(count_bits < 8) begin
                        rx_data <= {rx,rx_data[7:1]};
                        count_bits <= count_bits + 1;
                        state <= start;
                    end else begin
                        state <= idle;
                        done_rx <= 1'b1;
                        count_bits <= 0;
                    end
                end
            endcase
        end 
    end
endmodule

