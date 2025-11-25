/*
 * Clock Driver for Verilator Testbenches
 *
 * Provides time-accurate clock generation with configurable frequencies
 * and automatic 50% duty cycle. Designed for multi-clock domain testing.
 *
 * Usage:
 *   ClockDriver uart_clk(&dut->uart_clk, 8000000);  // 8 MHz
 *   ClockDriver axi_clk(&dut->axi_clk, 1000000);    // 1 MHz
 *
 *   while (sim_time < end_time) {
 *       uart_clk.update(sim_time);
 *       axi_clk.update(sim_time);
 *       dut->eval();
 *       sim_time++;
 *   }
 */

#ifndef CLOCK_DRIVER_H
#define CLOCK_DRIVER_H

#include <cstdint>

class ClockDriver {
private:
    uint8_t* signal_ptr;        // Pointer to DUT clock signal
    uint64_t period_ns;         // Clock period in nanoseconds
    uint64_t half_period_ns;    // Half period for 50% duty cycle
    uint64_t next_edge_time;    // Next time (in ns) to toggle clock
    bool current_state;         // Current clock level (0 or 1)

public:
    /**
     * Constructor
     * @param signal Pointer to DUT clock signal (e.g., &dut->uart_clk)
     * @param freq_hz Clock frequency in Hz (e.g., 8000000 for 8 MHz)
     */
    ClockDriver(uint8_t* signal, uint64_t freq_hz)
        : signal_ptr(signal)
        , current_state(false)
        , next_edge_time(0)
    {
        // Calculate period in nanoseconds: period = 1/freq * 1e9
        period_ns = 1000000000ULL / freq_hz;
        half_period_ns = period_ns / 2;

        // Initialize signal to low
        *signal_ptr = 0;
    }

    /**
     * Update clock based on current simulation time
     * Call this every simulation time step
     * @param current_time Current simulation time in nanoseconds
     */
    void update(uint64_t current_time) {
        // Check if it's time to toggle the clock
        if (current_time >= next_edge_time) {
            // Toggle clock state
            current_state = !current_state;
            *signal_ptr = current_state ? 1 : 0;

            // Schedule next edge
            next_edge_time = current_time + half_period_ns;
        }
    }

    /**
     * Reset clock to initial state
     * @param start_time Time to start clock from (usually 0)
     */
    void reset(uint64_t start_time = 0) {
        current_state = false;
        *signal_ptr = 0;
        next_edge_time = start_time + half_period_ns;
    }

    /**
     * Get the clock period in nanoseconds
     */
    uint64_t get_period_ns() const {
        return period_ns;
    }

    /**
     * Get current clock state
     */
    bool get_state() const {
        return current_state;
    }
};

#endif // CLOCK_DRIVER_H
