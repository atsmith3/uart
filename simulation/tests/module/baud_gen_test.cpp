/*
 * Baud Rate Generator Module-Level Tests
 *
 * Tests the baud rate generator with various divisor values.
 */

#include "Vuart_baud_gen.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>

BOOST_AUTO_TEST_SUITE(BaudGen_ModuleTests)

// Test fixture
struct BaudGenFixture {
    Vuart_baud_gen* dut;
    uint64_t time_counter;
    int tick_count;

    BaudGenFixture() : time_counter(0), tick_count(0) {
        dut = new Vuart_baud_gen;
        dut->uart_clk = 0;
        dut->rst_n = 0;
        dut->baud_divisor = 1;
        dut->enable = 0;
    }

    ~BaudGenFixture() {
        delete dut;
    }

    void tick() {
        dut->uart_clk = 0;
        dut->eval();
        time_counter++;

        dut->uart_clk = 1;
        dut->eval();
        if (dut->baud_tick) {
            tick_count++;
        }
        time_counter++;
    }

    void reset() {
        dut->rst_n = 0;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n = 1;
        tick();
        tick_count = 0;
    }
};

// Test divisor = 1 (highest rate)
BOOST_FIXTURE_TEST_CASE(baud_gen_divisor_1, BaudGenFixture) {
    reset();

    dut->baud_divisor = 1;
    dut->enable = 1;

    // Should generate tick every clock cycle
    for (int i = 0; i < 10; i++) {
        tick();
    }

    BOOST_CHECK_EQUAL(tick_count, 10);
}

// Test divisor = 4 (115200 baud)
BOOST_FIXTURE_TEST_CASE(baud_gen_divisor_4, BaudGenFixture) {
    reset();

    dut->baud_divisor = 4;
    dut->enable = 1;

    // Should generate tick every 4 clock cycles
    for (int i = 0; i < 40; i++) {
        tick();
    }

    BOOST_CHECK_EQUAL(tick_count, 10);  // 40 / 4 = 10 ticks
}

// Test divisor = 12 (9600 baud)
BOOST_FIXTURE_TEST_CASE(baud_gen_divisor_12, BaudGenFixture) {
    reset();

    dut->baud_divisor = 12;
    dut->enable = 1;

    // Should generate tick every 12 clock cycles
    for (int i = 0; i < 120; i++) {
        tick();
    }

    BOOST_CHECK_EQUAL(tick_count, 10);  // 120 / 12 = 10 ticks
}

// Test enable control
BOOST_FIXTURE_TEST_CASE(baud_gen_enable_control, BaudGenFixture) {
    reset();

    dut->baud_divisor = 4;
    dut->enable = 0;  // Disabled

    // Should not generate any ticks
    for (int i = 0; i < 40; i++) {
        tick();
    }

    BOOST_CHECK_EQUAL(tick_count, 0);

    // Enable
    dut->enable = 1;

    for (int i = 0; i < 40; i++) {
        tick();
    }

    BOOST_CHECK_EQUAL(tick_count, 10);
}

// Test divisor change during operation
BOOST_FIXTURE_TEST_CASE(baud_gen_divisor_change, BaudGenFixture) {
    reset();

    // Start with divisor = 4
    dut->baud_divisor = 4;
    dut->enable = 1;

    for (int i = 0; i < 20; i++) {
        tick();
    }

    BOOST_CHECK_EQUAL(tick_count, 5);

    // Change to divisor = 2
    dut->baud_divisor = 2;
    tick_count = 0;

    for (int i = 0; i < 20; i++) {
        tick();
    }

    BOOST_CHECK_EQUAL(tick_count, 10);
}

BOOST_AUTO_TEST_SUITE_END()
