# UART - RTL Design and UVM Verification
A UART (Universal Asynchronous Receiver-Transmitter) transmitter/receiver pair implemented in SystemVerilog, 
verified with a full UVM (Universal Verification Methodology) 
testbench and simulated in Xilinx Vivado (Xsim).

## Overview
This Project implements a configurable UART core (`uart_top`) composed of a transmitter (`uart_tx`) and a receiver (`uart_rx`), each generating
its own internal bit-clock (`uclk`) from the system clock based on a configurable `clk_freq`/`baud_rate` ratio. The design is verified with a
layered, class-based UVM environment that drives random stimuli for both transmit and receive paths, monitors the DUT passively, and selfchecks results
in a scoreboard.

## UART Frame Format
```
Idle   Start   D0  D1  D2  D3  D4  D5  D6  D7    Idle
 (1)    (0)    <-- 8 data bits, LSB first -->    (1)
```
- Line idles high (`1`).
- A falling edge (`0`).
- 8 data bits follow, ** LSB first **.
- The line returns to `1` (stop condition).

## RTL Architecture 

| Module | Description |
|---|---|
|`uart_top` | Top-level wrapper instantiating `uart_tx` and `uart_rx`, sharing `clk`/`rst`. |
|`uart_tx` | Transmitter FSM (`Idle` -> `transfer`). Captures `tx_data` on `newd`, shifts it out LSB-first on `tx`, asserts `done_tx` on completion.|
|`uart_rx` | Receiver FSM (`Idle` -> `start`). Detects the start bit on `rx`, reconstructs the byte via a shift register, asserts `done_rx` on completion|

### Parameters 

| Parameters | Default | Description |
|---|---|---|
|`clk_freq` | 1,000,000 | System clock frequency (Hz) |
|`baud_rate`| 9,600 | UART line speed (bits/sec) |

Internally, `clkcount = clk_freq / baud_rate` determines how many system clock cycles form one UART bit-time; each TX/RX module derives its own internal bit-clock
(`uclk`) by toggling every `clkcount/2` cycles.

## UVM Verification Environment

```
uart_test
  |
  +-- uart_env
        |
        +-- uart_agent
        |     |
        |     +-- uvm_sequencer #(uart_seq_item)
        |     +-- uart_driver   -> analysis_port --+
        |     +-- uart_monitor  -> analysis_port --+
        |                                          |
        +-- uart_scoreboard  <---------------------+
              (dual uvm_analysis_imp: _drv / _mon)
```

| Component | Role |
|---|---|
|`uart_seq_item` | Transaction: randomized `op` (`TRANSFER`/`receive`) and `tx_data`; result fields `rx_data`, `tx`, `rx`, `done_tx`, `done_rx`.|
|`uart_sequence` | Generates a configurable number of randomized transaction via `start_item()`/`finish_item()`.|
|`uart_driver` | Drives the interface according to `op`: pulses `newd`/`tx_data` for a transmit, or bit-bangs `rx` for a simulated receive. Publishes what it drove via its own analysis_port|
|`uart_monitor`| Passively observes vif (no driving), reconstructs the byte seen on `tx` or `rx_data`, and publishes it via analysis_port|
|`uart_scoreboard`| Receives from both driver and monitor (via `uvm_analysis_imp_decl(_drv/mon)), queues expected values per operation type, and compares them against observed values|
|`uart_agent`| bundles sequencer + driver + monitor|
|`uart_env`| bundles agent + scoreboard, wires up the analysis ports.|
|`uart_test`| configures and starts the sequence; manages `raise_objections`/`drop_objection`|

## Repository Structure

```
├── design.sv        # RTL: uart_top, uart_tx, uart_rx, uart_if
├── testbench.sv      # UVM environment + tb_top
└── README.md
```

## Sample Output

```
UVM_INFO ... [DRV] Reset is done
UVM_INFO ... [DRV] DATA sent: 96
UVM_INFO ... [SCO] DRV (tx_data) : 96 MON (tx_data) : 96
UVM_INFO ... [SCO] DATA MATCHED
UVM_INFO ... [MON] DATA sent on UART TX 96
...
--- UVM Report Summary ---
UVM_ERROR :    0
UVM_WARNING :    0
```



