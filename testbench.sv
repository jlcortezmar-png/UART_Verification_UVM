`include "uvm_macros.svh"
import uvm_pkg::*;

`uvm_analysis_imp_decl(_drv)
`uvm_analysis_imp_decl(_mon)

/////////////////////////////////////////////////////////////////////////////
class uart_seq_item extends uvm_sequence_item;
    typedef enum bit {TRANSFER = 1'b0, RECEIVE = 1'b1} oper_type;

    rand oper_type op;
    rand bit [7:0] tx_data;
    bit [7:0] rx_data;
    bit rx;
    bit tx;
    bit done_tx;
    bit done_rx;

    `uvm_object_utils_begin(uart_seq_item)
        `uvm_field_enum(oper_type, op, UVM_ALL_ON)
        `uvm_field_int(tx_data, UVM_ALL_ON)
        `uvm_field_int(rx_data, UVM_ALL_ON)
        `uvm_field_int(rx, UVM_ALL_ON)
        `uvm_field_int(tx, UVM_ALL_ON)
        `uvm_field_int(done_tx, UVM_ALL_ON)
        `uvm_field_int(done_rx, UVM_ALL_ON)
    `uvm_object_utils_end
    
    function new(string name = "uart_seq_item");
        super.new(name);
    endfunction
endclass
///////////////////////////////////////////////////////////////////////////////////

class uart_sequence extends uvm_sequence #(uart_seq_item);
    `uvm_object_utils(uart_sequence)
    uart_seq_item req;

    int stimulus = 0;

    function new(string name = "uart_sequence");
        super.new(name);
    endfunction

    task body();
        repeat (stimulus) begin
            req = uart_seq_item::type_id::create("req");
            start_item(req);
            assert(req.randomize());
            finish_item(req);
        end
    endtask
endclass

//////////////////////////////////////////////////////////////////////////////////////

class uart_driver extends uvm_driver #(uart_seq_item);
    bit random_bit;
    bit [7:0] aux_data;
    `uvm_component_utils(uart_driver)

    virtual uart_if vif;

    uvm_analysis_port #(uart_seq_item) port_driver;

    function new(string name = "uart_driver", uvm_component parent = null);
        super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if(!uvm_config_db#(virtual uart_if)::get(this,"", "vif",vif))
            `uvm_fatal("DRV", "vif has not been found");
        
        port_driver = new("port_driver", this);
    endfunction

    task run_phase(uvm_phase phase);
        vif.rst <= 1'b1;
        vif.tx_data <= '0;
        vif.newd <= 1'b0;
        vif.rx <= 1'b1;

        repeat(2) @(posedge vif.uclktx);
        vif.rst <= 1'b0;
        @(posedge vif.uclktx);
        `uvm_info("DRV", "Reset is done", UVM_LOW);

        forever begin
            seq_item_port.get_next_item(req);
                if(req.op == uart_seq_item::TRANSFER) begin
                    @(posedge vif.uclktx);
                    vif.rst <= 1'b0;
                    vif.newd <= 1'b1;
                    vif.rx <= 1'b1;
                    vif.tx_data <= req.tx_data;

                    @(posedge vif.uclktx);
                    vif.newd <= 1'b0;
                    wait(vif.done_tx == 1'b1);
                    port_driver.write(req);
                    `uvm_info("DRV",$sformatf("DATA sent: %0d",req.tx_data), UVM_LOW);
                end

                else if(req.op == uart_seq_item::RECEIVE) begin
                    @(posedge vif.uclkrx);
                    vif.rst <= 1'b0;
                    vif.rx <= 1'b0;
                    vif.newd <= 1'b0;

                    for(int i = 0; i < 8; i++) begin
                        @(posedge vif.uclkrx);
                        random_bit = $urandom;
                        vif.rx <= random_bit;
                        aux_data[i] = random_bit;
                    end
                    req.rx_data = aux_data;
                    wait(vif.done_rx == 1'b1);
                    port_driver.write(req);
                    `uvm_info("DRV",$sformatf("DATA sent: %0d",aux_data), UVM_LOW);
                    vif.rx <= 1'b1;
                end
            seq_item_port.item_done();
        end
    endtask
endclass

class uart_monitor extends uvm_monitor;
    `uvm_component_utils(uart_monitor)

    virtual uart_if vif;
    uart_seq_item seq;

    uvm_analysis_port #(uart_seq_item) port_monitor;

    function new(string name = "uart_monitor", uvm_component parent = null);
        super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if(!uvm_config_db#(virtual uart_if)::get(this,"","vif",vif))
            `uvm_fatal("MON", "vif has not been found");
    
        port_monitor = new ("monitor_port", this);
    endfunction

    task run_phase(uvm_phase phase);
        bit [7:0] aux_tx;
        bit [7:0] aux_rx;

        forever begin
            @(posedge vif.uclktx);
            if(vif.newd && vif.rx) begin
                @(posedge vif.uclktx);
                for(int i = 0; i < 8; i++)begin
                    @(posedge vif.uclktx);
                    aux_tx[i] = vif.tx;
                end
                seq = uart_seq_item::type_id::create("seq");
                seq.op = uart_seq_item::TRANSFER;
                seq.tx_data = aux_tx;
                #1;
                `uvm_info("MON",$sformatf("DATA sent on UART TX %0d",aux_tx), UVM_LOW);
                port_monitor.write(seq);
                
            end
            else if (!vif.newd && !vif.rx) begin
                wait(vif.done_rx == 1'b1);
                aux_rx = vif.rx_data;
                @(posedge vif.uclktx);
                seq = uart_seq_item::type_id::create("seq");
                seq.op = uart_seq_item::RECEIVE;
                seq.rx_data = aux_rx;
                `uvm_info("MON",$sformatf("DATA sent on UART RX %0d",aux_rx), UVM_LOW);
                port_monitor.write(seq);
                
            end
        end
    endtask
endclass



class uart_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(uart_scoreboard)

    bit [7:0] transfer_aux[$];
    bit [7:0] receive_aux[$];

    uvm_analysis_imp_drv #(uart_seq_item, uart_scoreboard) imp_drv;
    uvm_analysis_imp_mon #(uart_seq_item, uart_scoreboard) imp_mon;

    function new(string name = "uart_scoreboard", uvm_component parent = null);
        super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        imp_drv = new("imp_drv", this);
        imp_mon = new("imp_mon", this);
    endfunction

    function void write_drv(uart_seq_item seq);
        if(seq.op == uart_seq_item::TRANSFER) begin
            transfer_aux.push_back(seq.tx_data);
        end else if (seq.op == uart_seq_item::RECEIVE) begin
            receive_aux.push_back(seq.rx_data);
        end
    endfunction

    function void write_mon(uart_seq_item seq);
        bit [7:0] expected;

        if(seq.op == uart_seq_item::TRANSFER)begin
            if (transfer_aux.size() == 0) begin
                `uvm_warning("SCO", "Received data from monitor with no pending driver data")
                return;
            end

            expected = transfer_aux.pop_front();
            `uvm_info("SCO",$sformatf("DRV (tx_data) : %0d MON (tx_data) : %0d", expected, seq.tx_data), UVM_LOW);
            if(expected == seq.tx_data)
                `uvm_info("SCO", "DATA MATCHED", UVM_LOW)
            else
                `uvm_error("SCO", "DATA MISMATCHED")
        end

        if(seq.op == uart_seq_item::RECEIVE)begin
            if (receive_aux.size() == 0) begin
                `uvm_warning("SCO", "Received data from monitor with no pending driver data")
                return;
            end

            expected = receive_aux.pop_front();
            `uvm_info("SCO",$sformatf("DRV (tx_data) : %0d MON (rx_data) : %0d", expected, seq.rx_data), UVM_LOW);
            if(expected == seq.rx_data)
                `uvm_info("SCO", "DATA MATCHED", UVM_LOW)
            else
                `uvm_error("SCO", "DATA MISMATCHED")
        end

        $display("*******************************************************************************************************************************************************************************");

    endfunction
endclass

class uart_agent extends uvm_agent;
    `uvm_component_utils(uart_agent)

    uvm_sequencer #(uart_seq_item) seqr;
    uart_driver drv;
    uart_monitor mon;

    function new(string name = "uart_agent", uvm_component parent = null);
        super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        drv = uart_driver::type_id::create("drv",this);
        mon = uart_monitor::type_id::create("mon",this);
        seqr = uvm_sequencer #(uart_seq_item)::type_id::create("seqr",this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
endclass

class uart_env extends uvm_env;
    `uvm_component_utils(uart_env)

    uart_agent age;
    uart_scoreboard sco;

    function new(string name = "uart_env", uvm_component parent = null);
        super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        age = uart_agent::type_id::create("age",this);
        sco = uart_scoreboard::type_id::create("sco", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        age.drv.port_driver.connect(sco.imp_drv);
        age.mon.port_monitor.connect(sco.imp_mon);
    endfunction
endclass

class uart_test extends uvm_test;
    `uvm_component_utils(uart_test)

    uart_env env;

    function new(string name = "uart_test", uvm_component parent = null);
        super.new(name,parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = uart_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        uart_sequence seq;
        phase.raise_objection(this);

        seq = uart_sequence::type_id::create("seq");
        seq.stimulus = 10;
        seq.start(env.age.seqr);
        
        phase.drop_objection(this);
    endtask
endclass

module tb_top;
    uart_if vif();
    uart_top #(1000000,9600) dut(vif.clk,vif.rst,vif.rx,vif.tx_data,vif.newd,vif.tx,vif.rx_data,vif.done_tx,vif.done_rx);


    initial begin
        vif.clk = 1'b0;
    end

    always #500 vif.clk <= ~vif.clk;

    assign vif.uclktx = dut.dut_tx.uclk;
    assign vif.uclkrx = dut.dut_rx.uclk;

    initial begin
        uvm_config_db#(virtual uart_if)::set(null,"*","vif",vif);
        run_test("uart_test");
    end
endmodule