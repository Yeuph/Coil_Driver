//`timescale 1ns/100ps

/*
H-Bridge Controller with Flyback Protection
----------------------------------------
This module controls an H-bridge circuit for driving inductive loads with integrated
flyback protection and energy tracking.

Key Features:
- Bidirectional control (forward/reverse)
- Automatic flyback handling through high-side switches
- Energy tracking and safe direction switching
- Synchronous timing for switch transitions

Operating Principles:
1. Energy Management:
   - Tracks energy buildup in the coil during ON time
   - Manages discharge through flyback circuit
   - Prevents direction switching until sufficient energy discharge
   - Energy counters decrease during flyback cycles

2. Switch Configuration:
   - Q1/Q3: High-side switches
   - Q2/Q4: Low-side switches
   - Forward operation: Q1+Q4
   - Reverse operation: Q3+Q2
   - Flyback path: Q1+Q3 (both high-side)

Timing Relationships:
1. Switch Transitions:
   - OutVGS activation: 0.5 clock after input signal (negedge after posedge)
   - FlybackVGS activation: Immediate on input signal removal
   - OutVGS deactivation: 0.5 clock after FlybackVGS activation
   NOTE: These timings may need adjustment based on MOSFET characteristics
         during physical testing to optimize voltage stability

2. Direction Changes:
   - Requires complete energy discharge via flyback
   - Enforces discharge time equal to previous ON time
   - Blocked direction changes don't interrupt flyback counting

Limitations and Requirements:
1. Frequency Limits:
   - Verified operation: >3 clock cycles (4MHz at 12MHz clock)
   - Recommended: >12 clock cycles (<1MHz switching at 12MHz clock)
   - Flyback energy tracking may be incomplete at highest frequencies

2. Reset State:
   - Both high-side switches active (Q1+Q3)
   - Both low-side switches inactive (Q2+Q4)

Usage Notes:
- InVGSf/InVGSr should not be active simultaneously
- For reliable operation, maintain switching frequency below 1MHz
- Energy tracking ensures safe direction changes
- Flyback counting continues during blocked direction attempts
*/

module hbridge_controller (
    input wire clk,                // 12MHz clock input
    input wire rst_n,              // Active-low reset
    input wire InVGSf,             // Forward drive input (>12 clocks recommended)
    input wire InVGSr,             // Reverse drive input (>12 clocks recommended)
    output reg Q1_out,             // High side forward switch
    output reg Q2_out,             // Low side reverse switch
    output reg Q3_out,             // High side reverse switch
    output reg Q4_out              // Low side forward switch
);

// Internal control signals
reg OutVGSf, OutVGSr;             // Drive set controls
reg FlybackVGS;                    // Flyback control
reg rising_edge_detected;          // Flag to track DriveSet rising edge
reg falling_edge_detected;         // Flag to track falling edge for sequencing

// Counter registers
reg [15:0] fwd_on_counter;        // Counts how long forward was on
reg [15:0] rev_on_counter;        // Counts how long reverse was on
reg [15:0] flyback_counter;       // Counts current flyback duration
reg last_dir_forward;             // Tracks which direction was last active
reg in_flyback_mode;              // Indicates we're in flyback waiting period
reg direction_blocked;            // Indicates direction change is blocked

// Handle positive edge of clock - FlybackVGS control and edge detection
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        FlybackVGS <= 1;           // Default state is high (both high side on)
        rising_edge_detected <= 0;
        falling_edge_detected <= 0;
        fwd_on_counter <= 0;
        rev_on_counter <= 0;
        flyback_counter <= 0;
        in_flyback_mode <= 0;
        direction_blocked <= 0;
    end else begin
        // Counter logic for active states
        if (OutVGSf && InVGSf) begin
            fwd_on_counter <= fwd_on_counter + 1;
        end else if (OutVGSr && InVGSr) begin
            rev_on_counter <= rev_on_counter + 1;
        end

        // Flyback counting logic and energy discharge tracking
        if (FlybackVGS && in_flyback_mode && !OutVGSf && !OutVGSr) begin
            flyback_counter <= flyback_counter + 1;
            
            // Decrease the relevant counter based on last direction
            if (last_dir_forward && fwd_on_counter > 0) begin
                fwd_on_counter <= fwd_on_counter - 1;
            end else if (!last_dir_forward && rev_on_counter > 0) begin
                rev_on_counter <= rev_on_counter - 1;
            end
            
            // Check if we've fully discharged
            if ((last_dir_forward && fwd_on_counter <= 1) ||
                (!last_dir_forward && rev_on_counter <= 1)) begin
                direction_blocked <= 0;  // Unblock direction changes
                in_flyback_mode <= 0;    // Exit flyback mode
                fwd_on_counter <= 0;     // Reset counters after discharge
                rev_on_counter <= 0;
                flyback_counter <= 0;
            end
        end

        // Main control logic
        if (InVGSf || InVGSr) begin
            if (!rising_edge_detected) begin
                // New drive input detected
                if ((InVGSf && !last_dir_forward && in_flyback_mode) ||
                    (InVGSr && last_dir_forward && in_flyback_mode)) begin
                    // Attempting opposite direction during flyback
                    if ((last_dir_forward && fwd_on_counter < flyback_counter) ||
                        (!last_dir_forward && rev_on_counter < flyback_counter)) begin
                        direction_blocked <= 1;
                    end
                end else begin
                    // Same direction or flyback complete
                    FlybackVGS <= 0;
                    rising_edge_detected <= 1;
                    falling_edge_detected <= 0;
                    in_flyback_mode <= 0;
                    flyback_counter <= 0;
                    direction_blocked <= 0;
                    if (!in_flyback_mode) begin
                        // Reset the inactive direction's counter
                        if (InVGSf) begin
                            rev_on_counter <= 0;
                        end else begin
                            fwd_on_counter <= 0;
                        end
                    end
                end
            end
        end else begin  // Both inputs are low
            rising_edge_detected <= 0;
            if (OutVGSf || OutVGSr) begin
                // Drive set is active, start turn-off sequence
                FlybackVGS <= 1;
                falling_edge_detected <= 1;
                in_flyback_mode <= 1;
                flyback_counter <= 0;
            end else if (!FlybackVGS && !falling_edge_detected) begin
                // Short pulse case
                FlybackVGS <= 1;
                falling_edge_detected <= 0;
            end
        end
    end
end

// Handle negative edge of clock - DriveSet control
always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
        OutVGSf <= 0;
        OutVGSr <= 0;
        last_dir_forward <= 0;     // Reset direction tracking
    end else begin
        if (rising_edge_detected && !direction_blocked) begin
            if (InVGSf) begin
                OutVGSf <= 1;
                OutVGSr <= 0;
                last_dir_forward <= 1;  // Update only on successful activation
            end else if (InVGSr) begin
                OutVGSf <= 0;
                OutVGSr <= 1;
                last_dir_forward <= 0;  // Update only on successful activation
            end
        end else if (falling_edge_detected || direction_blocked) begin
            OutVGSf <= 0;
            OutVGSr <= 0;
            // Direction state maintained during flyback
        end
    end
end

// Final switch output control
always @(*) begin
    // High side switches (Q1 and Q3)
    Q1_out = OutVGSf || FlybackVGS;
    Q3_out = OutVGSr || FlybackVGS;
    
    // Low side switches (Q2 and Q4)
    Q2_out = OutVGSr;
    Q4_out = OutVGSf;
end

endmodule
