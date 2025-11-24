/*
 * UART Transmitter Module-Level Tests
 */

#include "Vuart_tx.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <vector>

BOOST_AUTO_TEST_SUITE(UartTX_ModuleTests)

struct UartTXFixture {
    Vuart_tx* dut;

    UartTXFixture() {
        dut = new Vuart_tx;
        dut->uart_clk = 0;
        dut->rst_n = 0;
        dut->baud_tick = 0;
        dut->tx_data = 0;
        dut->tx_valid = 0;
    }

    ~UartTXFixture() {
        delete dut;
    }

    void tick(bool baud_tick = false) {
        dut->baud_tick = baud_tick ? 1 : 0;
        dut->uart_clk = 0;
        dut->eval();
        dut->uart_clk = 1;
        dut->eval();
    }

    void reset() {
        dut->rst_n = 0;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n = 1;
        tick();
    }

    std::vector<int> transmit_byte(uint8_t data) {
        std::vector<int> bits;

        // Present data and wait for it to be latched
        dut->tx_data = data;
        dut->tx_valid = 1;
        tick(true);  // Baud tick to enter START state
        dut->tx_valid = 0;

        // Now capture the transmitted bits (10 total: start + 8 data + stop)
        // We're already in START state, so capture current bit
        bits.push_back(dut->tx_serial);

        // Capture remaining 9 bits
        for (int i = 0; i < 9; i++) {
            tick(true);  // Baud tick to advance state
            bits.push_back(dut->tx_serial);
        }

        // Extra tick to return to idle
        tick(true);

        return bits;
    }
};

BOOST_FIXTURE_TEST_CASE(uart_tx_idle_state, UartTXFixture) {
    reset();

    // TX line should be idle high
    BOOST_CHECK_EQUAL(dut->tx_serial, 1);
    BOOST_CHECK_EQUAL(dut->tx_ready, 1);
    BOOST_CHECK_EQUAL(dut->tx_active, 0);
}

BOOST_FIXTURE_TEST_CASE(uart_tx_frame_format, UartTXFixture) {
    reset();

    // Transmit 0x55 (01010101 binary)
    auto bits = transmit_byte(0x55);

    // Check frame format: start(0) + data(LSB first) + stop(1)
    BOOST_CHECK_EQUAL(bits[0], 0);  // Start bit
    BOOST_CHECK_EQUAL(bits[1], 1);  // Bit 0 (LSB)
    BOOST_CHECK_EQUAL(bits[2], 0);  // Bit 1
    BOOST_CHECK_EQUAL(bits[3], 1);  // Bit 2
    BOOST_CHECK_EQUAL(bits[4], 0);  // Bit 3
    BOOST_CHECK_EQUAL(bits[5], 1);  // Bit 4
    BOOST_CHECK_EQUAL(bits[6], 0);  // Bit 5
    BOOST_CHECK_EQUAL(bits[7], 1);  // Bit 6
    BOOST_CHECK_EQUAL(bits[8], 0);  // Bit 7 (MSB)
    BOOST_CHECK_EQUAL(bits[9], 1);  // Stop bit
}

BOOST_FIXTURE_TEST_CASE(uart_tx_all_zeros, UartTXFixture) {
    reset();

    auto bits = transmit_byte(0x00);

    BOOST_CHECK_EQUAL(bits[0], 0);  // Start bit
    for (int i = 1; i <= 8; i++) {
        BOOST_CHECK_EQUAL(bits[i], 0);  // All data bits 0
    }
    BOOST_CHECK_EQUAL(bits[9], 1);  // Stop bit
}

BOOST_FIXTURE_TEST_CASE(uart_tx_all_ones, UartTXFixture) {
    reset();

    auto bits = transmit_byte(0xFF);

    BOOST_CHECK_EQUAL(bits[0], 0);  // Start bit
    for (int i = 1; i <= 8; i++) {
        BOOST_CHECK_EQUAL(bits[i], 1);  // All data bits 1
    }
    BOOST_CHECK_EQUAL(bits[9], 1);  // Stop bit
}

BOOST_AUTO_TEST_SUITE_END()
