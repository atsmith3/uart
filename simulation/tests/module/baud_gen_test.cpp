/*
 * baud_gen Module Tests
 *
 * Tests baud rate generator for UART timing
 *
 * Test Coverage:
 * - Reset behavior
 * - Basic tick generation (various divisors)
 * - Enable/disable functionality
 * - Divisor changes during operation
 * - Edge cases (divisor=1, divisor=0)
 * - Tick frequency accuracy
 * - Timing characteristics (pulse width, period)
 * - Standard baud rate divisors (115200, 9600, etc.)
 */

#include "Vbaud_gen.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <vector>

BOOST_AUTO_TEST_SUITE(BaudGen_ModuleTests)

struct BaudGenFixture {
    Vbaud_gen* dut;
    int cycle_count;

    BaudGenFixture() {
        dut = new Vbaud_gen;
        cycle_count = 0;

        // Initialize inputs
        dut->uart_clk = 0;
        dut->rst_n = 0;
        dut->baud_divisor = 0;
        dut->enable = 0;
    }

    ~BaudGenFixture() {
        delete dut;
    }

    void tick() {
        dut->uart_clk = 0;
        dut->eval();
        dut->uart_clk = 1;
        dut->eval();
        cycle_count++;
    }

    void reset() {
        dut->rst_n = 0;
        dut->enable = 0;
        dut->baud_divisor = 0;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n = 1;
        tick();
        cycle_count = 0;  // Reset cycle counter after reset
    }

    // Helper: Count ticks over N cycles
    int count_ticks(int cycles) {
        int tick_count = 0;
        for (int i = 0; i < cycles; i++) {
            tick();
            if (dut->baud_tick) {
                tick_count++;
            }
        }
        return tick_count;
    }

    // Helper: Measure cycles between ticks (including the tick cycle)
    int cycles_until_tick() {
        int cycles = 0;
        do {
            tick();
            cycles++;
        } while (!dut->baud_tick && cycles < 1000);
        return cycles;
    }
};

// Test 1: Reset state
BOOST_FIXTURE_TEST_CASE(baud_gen_reset_state, BaudGenFixture) {
    reset();

    // After reset, baud_tick should be 0
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);
}

// Test 2: Disabled (enable=0)
BOOST_FIXTURE_TEST_CASE(baud_gen_disabled, BaudGenFixture) {
    reset();

    dut->baud_divisor = 4;
    dut->enable = 0;

    // Run for many cycles, baud_tick should stay 0
    for (int i = 0; i < 20; i++) {
        tick();
        BOOST_CHECK_EQUAL(dut->baud_tick, 0);
    }
}

// Test 3: Basic tick generation (divisor=4)
BOOST_FIXTURE_TEST_CASE(baud_gen_divisor_4, BaudGenFixture) {
    reset();

    dut->baud_divisor = 4;
    dut->enable = 1;

    // First tick should occur after 4 cycles
    tick(); // cycle 1
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);
    tick(); // cycle 2
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);
    tick(); // cycle 3
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);
    tick(); // cycle 4
    BOOST_CHECK_EQUAL(dut->baud_tick, 1); // Tick!

    // Tick should be only 1 cycle wide
    tick(); // cycle 5
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);

    // Next tick at cycle 8
    tick(); // cycle 6
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);
    tick(); // cycle 7
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);
    tick(); // cycle 8
    BOOST_CHECK_EQUAL(dut->baud_tick, 1); // Tick!
}

// Test 4: Divisor=1 (maximum rate)
BOOST_FIXTURE_TEST_CASE(baud_gen_divisor_1, BaudGenFixture) {
    reset();

    dut->baud_divisor = 1;
    dut->enable = 1;

    // Should tick every cycle
    for (int i = 0; i < 10; i++) {
        tick();
        BOOST_CHECK_EQUAL(dut->baud_tick, 1);
    }
}

// Test 5: Divisor=0 (invalid, should disable)
BOOST_FIXTURE_TEST_CASE(baud_gen_divisor_0, BaudGenFixture) {
    reset();

    dut->baud_divisor = 0;
    dut->enable = 1;

    // Should not generate ticks (divisor=0 is invalid)
    for (int i = 0; i < 20; i++) {
        tick();
        BOOST_CHECK_EQUAL(dut->baud_tick, 0);
    }
}

// Test 6: Frequency accuracy (divisor=8)
BOOST_FIXTURE_TEST_CASE(baud_gen_frequency_accuracy, BaudGenFixture) {
    reset();

    dut->baud_divisor = 8;
    dut->enable = 1;

    // Over 80 cycles, should get exactly 10 ticks
    int tick_count = count_ticks(80);
    BOOST_CHECK_EQUAL(tick_count, 10);
}

// Test 7: Enable/disable during operation
BOOST_FIXTURE_TEST_CASE(baud_gen_enable_disable, BaudGenFixture) {
    reset();

    dut->baud_divisor = 4;
    dut->enable = 1;

    // Let it run for a couple ticks
    tick(); tick(); tick();
    tick(); // Tick at cycle 4
    BOOST_CHECK_EQUAL(dut->baud_tick, 1);

    // Disable
    dut->enable = 0;
    tick();
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);

    // Should stay disabled
    for (int i = 0; i < 10; i++) {
        tick();
        BOOST_CHECK_EQUAL(dut->baud_tick, 0);
    }

    // Re-enable (counter should restart)
    dut->enable = 1;
    tick(); // cycle 1
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);
    tick(); tick(); tick(); // cycles 2,3,4
    BOOST_CHECK_EQUAL(dut->baud_tick, 1); // Tick!
}

// Test 8: Divisor change during operation
BOOST_FIXTURE_TEST_CASE(baud_gen_divisor_change, BaudGenFixture) {
    reset();

    // Start with divisor=4
    dut->baud_divisor = 4;
    dut->enable = 1;

    tick(); tick(); tick(); tick(); // Tick at cycle 4
    BOOST_CHECK_EQUAL(dut->baud_tick, 1);
    tick(); // cycle 5, counter resets to 0, no tick
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);

    // Change to divisor=2 (counter continues from current value)
    dut->baud_divisor = 2;
    // counter is now at 1

    // Counter will reach divisor-1 (2-1=1) on next cycle
    tick(); // cycle 6: counter=1, equals divisor-1, so tick!
    BOOST_CHECK_EQUAL(dut->baud_tick, 1);

    tick(); // cycle 7: counter resets, no tick
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);

    tick(); // cycle 8: counter=1, tick again
    BOOST_CHECK_EQUAL(dut->baud_tick, 1);
}

// Test 9: Standard baud rate - 115200 (divisor=4)
BOOST_FIXTURE_TEST_CASE(baud_gen_115200, BaudGenFixture) {
    reset();

    dut->baud_divisor = 4;  // 115200 baud, 16x oversampling
    dut->enable = 1;

    // Expected: 7372800 / 4 = 1843200 ticks/sec
    // Over 40 cycles, expect 10 ticks
    int tick_count = count_ticks(40);
    BOOST_CHECK_EQUAL(tick_count, 10);
}

// Test 10: Standard baud rate - 9600 (divisor=48)
BOOST_FIXTURE_TEST_CASE(baud_gen_9600, BaudGenFixture) {
    reset();

    dut->baud_divisor = 48;  // 9600 baud, 16x oversampling
    dut->enable = 1;

    // Expected: 7372800 / 48 = 153600 ticks/sec
    // Over 480 cycles, expect 10 ticks
    int tick_count = count_ticks(480);
    BOOST_CHECK_EQUAL(tick_count, 10);
}

// Test 11: Pulse width (always 1 cycle)
BOOST_FIXTURE_TEST_CASE(baud_gen_pulse_width, BaudGenFixture) {
    reset();

    dut->baud_divisor = 5;
    dut->enable = 1;

    // Wait for first tick
    while (!dut->baud_tick) {
        tick();
    }

    // Tick is high for exactly 1 cycle
    BOOST_CHECK_EQUAL(dut->baud_tick, 1);
    tick();
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);

    // Stays low until next period
    for (int i = 0; i < 3; i++) {
        tick();
        BOOST_CHECK_EQUAL(dut->baud_tick, 0);
    }

    // Next tick
    tick();
    BOOST_CHECK_EQUAL(dut->baud_tick, 1);
}

// Test 12: Period accuracy (divisor=10)
BOOST_FIXTURE_TEST_CASE(baud_gen_period_accuracy, BaudGenFixture) {
    reset();

    dut->baud_divisor = 10;
    dut->enable = 1;

    std::vector<int> periods;

    // Measure 5 periods
    for (int i = 0; i < 5; i++) {
        // Wait for tick (cycles_until_tick includes the tick cycle)
        int cycles = cycles_until_tick();
        periods.push_back(cycles);
        // No need to tick again - already past the tick
    }

    // All periods should be exactly 10 cycles
    for (auto period : periods) {
        BOOST_CHECK_EQUAL(period, 10);
    }
}

// Test 13: Large divisor (divisor=255)
BOOST_FIXTURE_TEST_CASE(baud_gen_large_divisor, BaudGenFixture) {
    reset();

    dut->baud_divisor = 255;
    dut->enable = 1;

    // First tick after 255 cycles
    for (int i = 1; i < 255; i++) {
        tick();
        BOOST_CHECK_EQUAL(dut->baud_tick, 0);
    }
    tick(); // cycle 255
    BOOST_CHECK_EQUAL(dut->baud_tick, 1);
}

// Test 14: Reset during operation
BOOST_FIXTURE_TEST_CASE(baud_gen_reset_during_operation, BaudGenFixture) {
    reset();

    dut->baud_divisor = 4;
    dut->enable = 1;

    // Run for 2 cycles
    tick(); tick();
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);

    // Reset
    dut->rst_n = 0;
    tick();
    BOOST_CHECK_EQUAL(dut->baud_tick, 0);

    // Release reset
    dut->rst_n = 1;
    tick();

    // Counter should restart, tick at cycle 4
    tick(); tick(); tick();
    BOOST_CHECK_EQUAL(dut->baud_tick, 1);
}

BOOST_AUTO_TEST_SUITE_END()
