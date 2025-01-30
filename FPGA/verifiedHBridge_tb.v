`timescale 1ns/100ps

module hbridge_controller_tb;

// Testbench signals
reg clk;
reg rst_n;
reg InVGSf;
reg InVGSr;
wire Q1_out, Q2_out, Q3_out, Q4_out;

// Testbench-only signals for MOSFET set monitoring
wire TB_FWD_SET;
wire TB_REV_SET;

// Instantiate the H-bridge controller
hbridge_controller uut (
    .clk(clk),
    .rst_n(rst_n),
    .InVGSf(InVGSf),
    .InVGSr(InVGSr),
    .Q1_out(Q1_out),
    .Q2_out(Q2_out),
    .Q3_out(Q3_out),
    .Q4_out(Q4_out)
);

assign TB_FWD_SET = Q1_out && Q4_out;
assign TB_REV_SET = Q3_out && Q2_out;

// Clock generation
initial begin
    clk = 0;
    forever #41.667 clk = ~clk;  // 12MHz clock
end

// Task for Forward PWM testing
task test_forward_pwm;
    input integer on_cycles;
    input integer off_cycles;
    input integer repeat_count;
    begin
        $display("\nTesting Forward PWM: on=%0d, off=%0d, repeat=%0d", 
                 on_cycles, off_cycles, repeat_count);
        repeat(repeat_count) begin
            InVGSf = 1;
            repeat(on_cycles) @(posedge clk);
            InVGSf = 0;
            repeat(off_cycles) @(posedge clk);
        end
    end
endtask

// Task for Reverse PWM testing
task test_reverse_pwm;
    input integer on_cycles;
    input integer off_cycles;
    input integer repeat_count;
    begin
        $display("\nTesting Reverse PWM: on=%0d, off=%0d, repeat=%0d", 
                 on_cycles, off_cycles, repeat_count);
        repeat(repeat_count) begin
            InVGSr = 1;
            repeat(on_cycles) @(posedge clk);
            InVGSr = 0;
            repeat(off_cycles) @(posedge clk);
        end
    end
endtask

// Task for testing direction change
task test_direction_change;
    input integer first_dir_cycles;
    input integer wait_cycles;
    input integer second_dir_cycles;
    input integer start_forward;
    begin
        $display("\nDirection Change Test:");
        $display("First direction cycles: %0d", first_dir_cycles);
        $display("Wait cycles: %0d", wait_cycles);
        $display("Second direction cycles: %0d", second_dir_cycles);
        
        if (start_forward) begin
            InVGSf = 1;
            repeat(first_dir_cycles) @(posedge clk);
            InVGSf = 0;
            repeat(wait_cycles) @(posedge clk);
            InVGSr = 1;
            repeat(second_dir_cycles) @(posedge clk);
            InVGSr = 0;
        end else begin
            InVGSr = 1;
            repeat(first_dir_cycles) @(posedge clk);
            InVGSr = 0;
            repeat(wait_cycles) @(posedge clk);
            InVGSf = 1;
            repeat(second_dir_cycles) @(posedge clk);
            InVGSf = 0;
        end
        repeat(50) @(posedge clk);  // Additional settling time
    end
endtask

// Test stimulus
initial begin
    $dumpfile("hbridge_test.vcd");
    $dumpvars(0, hbridge_controller_tb);
    
    // Initialize inputs
    rst_n = 0;
    InVGSf = 0;
    InVGSr = 0;
    
    // Reset sequence
    #100;
    rst_n = 1;
    #100;

    // SECTION 1: Forward Direction Tests
    $display("\n=== FORWARD DIRECTION TESTS ===");
    
    // Long pulses
    test_forward_pwm(30, 30, 3);  // 30 clock cycles on/off
    #200;
    
    // Medium pulses
    test_forward_pwm(15, 15, 5);  // 15 clock cycles on/off
    #200;
    
    // Short pulses
    test_forward_pwm(5, 5, 10);   // 5 clock cycles on/off
    #200;
    
    // Very short pulses
    test_forward_pwm(2, 2, 15);   // 2 clock cycles on/off
    #200;
    
    // Single clock pulses
    test_forward_pwm(1, 1, 20);   // 1 clock cycle on/off
    #300;

    // SECTION 2: Reverse Direction Tests
    $display("\n=== REVERSE DIRECTION TESTS ===");
    
    // Long pulses
    test_reverse_pwm(30, 30, 3);
    #200;
    
    // Medium pulses
    test_reverse_pwm(15, 15, 5);
    #200;
    
    // Short pulses
    test_reverse_pwm(5, 5, 10);
    #200;
    
    // Very short pulses
    test_reverse_pwm(2, 2, 15);
    #200;
    
    // Single clock pulses
    test_reverse_pwm(1, 1, 20);
    #300;

    // SECTION 3: Direction Change Tests
    $display("\n=== DIRECTION CHANGE TESTS ===");
    
    // Test Case 1: Long ON with insufficient wait (should block)
    test_direction_change(30, 15, 30, 1);
    #500;
    
    // Test Case 2: Long ON with sufficient wait (should allow)
    test_direction_change(30, 35, 30, 1);
    #500;
    
    // Test Case 3: Medium ON with insufficient wait (should block)
    test_direction_change(15, 7, 15, 0);
    #500;
    
    // Test Case 4: Medium ON with sufficient wait (should allow)
    test_direction_change(15, 20, 15, 0);
    #500;
    
    // Test Case 5: Short ON with quick change attempt (should block)
    test_direction_change(5, 2, 5, 1);
    #500;
    
    // Test Case 6: Short ON with sufficient wait (should allow)
    test_direction_change(5, 7, 5, 1);
    #500;

    // SECTION 4: Mixed Frequency Tests
    $display("\n=== MIXED FREQUENCY TESTS ===");
    
    // Forward long to reverse short
    test_direction_change(30, 35, 5, 1);
    #500;
    
    // Reverse long to forward short
    test_direction_change(30, 35, 5, 0);
    #500;
    
    // Forward short to reverse long
    test_direction_change(5, 7, 30, 1);
    #500;
    
    // Reverse short to forward long
    test_direction_change(5, 7, 30, 0);
    #500;

    // SECTION 5: Rapid Alternation Tests
    $display("\n=== RAPID ALTERNATION TESTS ===");
    
    // Multiple short transitions with proper timing
    repeat(5) begin
        test_direction_change(5, 7, 5, 1);
        test_direction_change(5, 7, 5, 0);
    end

    // Multiple medium transitions with proper timing
    repeat(3) begin
        test_direction_change(15, 20, 15, 1);
        test_direction_change(15, 20, 15, 0);
    end

    $display("\n=== Test Complete ===");
    #100;
    $finish;
end

// Enhanced monitoring with debug signals
initial begin
    $monitor("Time=%0t rst_n=%b InVGSf=%b InVGSr=%b FWD_SET=%b REV_SET=%b LastDirFwd=%b FwdCnt=%d RevCnt=%d FlybackCnt=%d",
             $time, rst_n, InVGSf, InVGSr, TB_FWD_SET, TB_REV_SET,
             uut.last_dir_forward, uut.fwd_on_counter, uut.rev_on_counter, uut.flyback_counter);
end

endmodule
