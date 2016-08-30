/*

Copyright (c) 2016 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`timescale 1ns / 1ps

/*
 * LFSR PRBS checker
 */
module lfsr_prbs_check #
(
    // width of LFSR
    parameter LFSR_WIDTH = 31,
    // LFSR polynomial
    parameter LFSR_POLY = 31'h10000001,
    // Initial state
    parameter LFSR_INIT = {LFSR_WIDTH{1'b1}},
    // LFSR configuration: "GALOIS", "FIBONACCI"
    parameter LFSR_CONFIG = "FIBONACCI",
    // bit-reverse input and output
    parameter REVERSE = 0,
    // invert input
    parameter INVERT = 1,
    // width of data input and output
    parameter DATA_WIDTH = 8,
    // implementation style: "AUTO", "LOOP", "REDUCTION"
    parameter STYLE = "AUTO"
)
(
    input  wire                    clk,
    input  wire                    rst,
    input  wire [DATA_WIDTH-1:0]   data_in,
    input  wire                    data_in_valid,
    output wire [DATA_WIDTH-1:0]   data_out
);

/*

Fully parametrizable combinatorial parallel LFSR PRBS checker.  Implements an unrolled LFSR
PRBS checker.  

Ports:

clk

Clock input

rst

Reset input, set state to LFSR_INIT

data_in

PRBS data input (DATA_WIDTH bits)

data_in_valid

Shift input data through LFSR when asserted

data_out

Error output (DATA_WIDTH bits)

Parameters:

LFSR_WIDTH

Specify width of LFSR/CRC register

LFSR_POLY

Specify the LFSR/CRC polynomial in hex format.  For example, the polynomial

x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1

would be represented as

32'h04c11db7

Note that the largest term (x^32) is suppressed.  This term is generated automatically based
on LFSR_WIDTH.

LFSR_INIT

Initial state of LFSR.  Defaults to all 1s.

LFSR_CONFIG

Specify the LFSR configuration, either Fibonacci or Galois.  Fibonacci is generally used
for linear-feedback shift registers (LFSR) for pseudorandom binary sequence (PRBS) generators,
scramblers, and descrambers, while Galois is generally used for cyclic redundancy check
generators and checkers.

Fibonacci style (example for 64b66b scrambler, 0x8000000001)

    ,-----------------------------(+)<------------------------------,
    |                              ^                                |
    |  .----.  .----.       .----. |  .----.       .----.  .----.   |
    `->|  0 |->|  1 |->...->| 38 |-+->| 39 |->...->| 56 |->| 57 |->(+)<-DIN (LSB first)
       '----'  '----'       '----'    '----'       '----'  '----'

Galois style (example for CRC16, 0x8005)

    ,-------------------+---------------------------------+------------,
    |                   |                                 |            |
    |  .----.  .----.   V   .----.  .----.       .----.   V   .----.   |
    `->|  0 |->|  1 |->(+)->|  2 |->|  3 |->...->| 14 |->(+)->| 15 |->(+)<-DIN (MSB first)
       '----'  '----'       '----'  '----'       '----'       '----'

REVERSE

Bit-reverse LFSR output.  Shifts MSB first by default, set REVERSE for LSB first.

INVERT

Bitwise invert PRBS input.

DATA_WIDTH

Specify width of output data bus.

STYLE

Specify implementation style.  Can be "AUTO", "LOOP", or "REDUCTION".  When "AUTO"
is selected, implemenation will be "LOOP" or "REDUCTION" based on synthesis translate
directives.  "REDUCTION" and "LOOP" are functionally identical, however they simulate
and synthesize differently.  "REDUCTION" is implemented with a loop over a Verilog
reduction operator.  "LOOP" is implemented as a doubly-nested loop with no reduction
operator.  "REDUCTION" is very fast for simulation in iverilog and synthesizes well in
Quartus but synthesizes poorly in ISE, likely due to large inferred XOR gates causing
problems with the optimizer.  "LOOP" synthesizes will in both ISE and Quartus.  "AUTO"
will default to "REDUCTION" when simulating and "LOOP" for synthesizers that obey
synthesis translate directives.

Settings for common LFSR/CRC implementations:

Name        Configuration           Length  Polynomial      Initial value   Notes
CRC32       Galois, bit-reverse     32      32'h04c11db7    32'hffffffff    Ethernet FCS; invert final output
PRBS6       Fibonacci               6       6'h21           any
PRBS7       Fibonacci               7       7'h41           any
PRBS9       Fibonacci               9       9'h021          any             ITU V.52
PRBS10      Fibonacci               10      10'h081         any             ITU
PRBS11      Fibonacci               11      11'h201         any             ITU O.152
PRBS15      Fibonacci, inverted     15      15'h4001        any             ITU O.152
PRBS17      Fibonacci               17      17'h04001       any
PRBS20      Fibonacci               20      20'h00009       any             ITU V.57
PRBS23      Fibonacci, inverted     23      23'h040001      any             ITU O.151
PRBS29      Fibonacci, inverted     29      29'h08000001    any
PRBS31      Fibonacci, inverted     31      31'h10000001    any
64b66b      Fibonacci, bit-reverse  58      58'h8000000001  any             10G Ethernet
128b130b    Galois, bit-reverse     23      23'h210125      any             PCIe gen 3

*/

// STATE_WIDTH LFSR_WIDTH extended by DATA_WIDTH
parameter STATE_WIDTH = DATA_WIDTH + LFSR_WIDTH;

reg [LFSR_WIDTH-1:0] state_reg = LFSR_INIT;
reg [DATA_WIDTH-1:0] output_reg = 0;

wire [STATE_WIDTH-1:0] lfsr_out;

assign data_out = output_reg;

lfsr #(
    .LFSR_WIDTH(STATE_WIDTH),
    .LFSR_POLY({LFSR_POLY, {DATA_WIDTH{1'b0}}}),
    .LFSR_CONFIG(LFSR_CONFIG),
    .REVERSE(REVERSE),
    .DATA_WIDTH(DATA_WIDTH),
    .OUTPUT_WIDTH(STATE_WIDTH),
    .STYLE(STYLE)
)
lfsr_inst (
    .data_in({DATA_WIDTH{1'b0}}),
    .lfsr_in(REVERSE ? {INVERT ? ~data_in : data_in, state_reg} : {state_reg, INVERT ? ~data_in : data_in}),
    .lfsr_out(lfsr_out)
);

always @(posedge clk) begin
    if (rst) begin
        state_reg <= LFSR_INIT;
        output_reg <= 0;
    end else begin
        if (data_in_valid) begin
            if (REVERSE) begin
                state_reg <= lfsr_out[LFSR_WIDTH-1:0];
                output_reg <= lfsr_out[STATE_WIDTH-1:STATE_WIDTH-DATA_WIDTH];
            end else begin
                state_reg <= lfsr_out[STATE_WIDTH-1:STATE_WIDTH-LFSR_WIDTH];
                output_reg <= lfsr_out[DATA_WIDTH-1:0];
            end
        end
    end
end

endmodule
