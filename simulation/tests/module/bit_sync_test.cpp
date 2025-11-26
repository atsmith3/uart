/*
 * bit_sync Module Tests
 *
 * Tests 2-stage flip-flop synchronizer for single-bit CDC
 *
 * Test Coverage:
 * - Basic synchronization (2-cycle latency)
 * - Reset behavior
 * - Data persistence through synchronizer
 * - Different input patterns
 */

#include "Vbit_sync.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>

BOOST_AUTO_TEST_SUITE(BitSync_ModuleTests)

struct BitSyncFixture {
    Vbit_sync* dut;
    int cycle_count;

    BitSyncFixture() {
        dut = new Vbit_sync;
        cycle_count = 0;

        // Initialize inputs
        dut->clk_dst = 0;
        dut->rst_n_dst = 0;
        dut->data_in = 0;
    }

    ~BitSyncFixture() {
        delete dut;
    }

    void tick() {
        dut->clk_dst = 0;
        dut->eval();
        dut->clk_dst = 1;
        dut->eval();
        cycle_count++;
    }

    void reset() {
        dut->rst_n_dst = 0;
        dut->data_in = 0;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n_dst = 1;
        tick();
        cycle_count = 0;  // Reset cycle counter after reset
    }
};

// Test 1: Reset behavior
BOOST_FIXTURE_TEST_CASE(bit_sync_reset_state, BitSyncFixture) {
    reset();

    // After reset, output should be 0
    BOOST_CHECK_EQUAL(dut->data_out, 0);
}

// Test 2: Basic synchronization - low to high transition
BOOST_FIXTURE_TEST_CASE(bit_sync_low_to_high, BitSyncFixture) {
    reset();

    // data_in = 0, data_out should be 0
    dut->data_in = 0;
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 0);

    // Change data_in to 1
    dut->data_in = 1;

    // After 1 cycle: data_out still 0 (in 1st FF)
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 0);

    // After 2 cycles: data_out = 1 (reached output)
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 1);

    // Should stay at 1
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 1);
}

// Test 3: Basic synchronization - high to low transition
BOOST_FIXTURE_TEST_CASE(bit_sync_high_to_low, BitSyncFixture) {
    reset();

    // Set data_in high and wait for synchronization
    dut->data_in = 1;
    tick();
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 1);

    // Change data_in to 0
    dut->data_in = 0;

    // After 1 cycle: data_out still 1
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 1);

    // After 2 cycles: data_out = 0
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 0);
}

// Test 4: Data persistence - stable input
BOOST_FIXTURE_TEST_CASE(bit_sync_stable_input, BitSyncFixture) {
    reset();

    // Set input high
    dut->data_in = 1;
    tick();
    tick();

    // data_out should be 1 and stay stable
    for (int i = 0; i < 10; i++) {
        BOOST_CHECK_EQUAL(dut->data_out, 1);
        tick();
    }
}

// Test 5: Multiple transitions
BOOST_FIXTURE_TEST_CASE(bit_sync_multiple_transitions, BitSyncFixture) {
    reset();

    // Transition 1: 0 → 1
    dut->data_in = 1;
    tick(); // cycle 1: in 1st FF
    BOOST_CHECK_EQUAL(dut->data_out, 0);
    tick(); // cycle 2: at output
    BOOST_CHECK_EQUAL(dut->data_out, 1);

    // Hold for a few cycles
    tick();
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 1);

    // Transition 2: 1 → 0
    dut->data_in = 0;
    tick(); // cycle 1: in 1st FF
    BOOST_CHECK_EQUAL(dut->data_out, 1);
    tick(); // cycle 2: at output
    BOOST_CHECK_EQUAL(dut->data_out, 0);

    // Hold for a few cycles
    tick();
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 0);

    // Transition 3: 0 → 1 again
    dut->data_in = 1;
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 0);
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 1);
}

// Test 6: Pulse input (less than 2 cycles - should be ignored/missed)
// Note: This demonstrates why input pulses must be stretched
BOOST_FIXTURE_TEST_CASE(bit_sync_short_pulse, BitSyncFixture) {
    reset();

    // 1-cycle pulse on data_in
    dut->data_in = 1;
    tick();
    dut->data_in = 0;

    // data_out should never see this short pulse
    // (it might, depending on timing, but we can't guarantee it)
    // This test just verifies synchronizer doesn't crash
    for (int i = 0; i < 5; i++) {
        tick();
    }

    // The key is that the output is stable (either 0 or 1, no glitches)
    // We don't assert a specific value since short pulses are undefined
}

// Test 7: Reset during operation
BOOST_FIXTURE_TEST_CASE(bit_sync_reset_during_operation, BitSyncFixture) {
    reset();

    // Set input high and synchronize
    dut->data_in = 1;
    tick();
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 1);

    // Apply reset while data_in is high
    dut->rst_n_dst = 0;
    tick();

    // Output should immediately become 0
    BOOST_CHECK_EQUAL(dut->data_out, 0);

    // Release reset
    dut->rst_n_dst = 1;
    tick();

    // data_in is still 1, so it should resynchronize
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 1);
}

// Test 8: Verify 2-cycle latency precisely
BOOST_FIXTURE_TEST_CASE(bit_sync_exact_latency, BitSyncFixture) {
    reset();

    // Before applying input, output should be 0
    BOOST_CHECK_EQUAL(dut->data_out, 0);

    // Apply input change
    dut->data_in = 1;

    // Cycle 1: data_in is captured into 1st FF on this clock edge
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 0); // Not yet at output

    // Cycle 2: data propagates from 1st FF to 2nd FF (output)
    tick();
    BOOST_CHECK_EQUAL(dut->data_out, 1); // Now visible at output!

    // This confirms 2-cycle (2-FF) latency
    // Rising edge 1: data_in → sync_chain[0]
    // Rising edge 2: sync_chain[0] → sync_chain[1] (data_out)
}

BOOST_AUTO_TEST_SUITE_END()
