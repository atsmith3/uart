/*
 * UART Receiver Module-Level Tests
 */

#include "Vuart_rx.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <verilated_vcd_c.h>

BOOST_AUTO_TEST_SUITE(UartRX_ModuleTests)

struct UartRXFixture {
    Vuart_rx* dut;
    VerilatedVcdC* tfp;
    int sample_counter;

    UartRXFixture() : sample_counter(0), tfp(nullptr) {
        dut = new Vuart_rx;
        dut->uart_clk = 0;
        dut->rst_n = 0;
        dut->sample_tick = 0;
        dut->rx_serial_sync = 1;  // Idle high
        dut->rx_ready = 1;
    }

    ~UartRXFixture() {
        if (tfp) {
            tfp->close();
            delete tfp;
        }
        delete dut;
    }

    void enable_trace(const char* filename) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        dut->trace(tfp, 99);
        tfp->open(filename);
    }

    void tick(bool sample_tick = false) {
        static vluint64_t time = 0;
        dut->sample_tick = sample_tick ? 1 : 0;
        dut->uart_clk = 0;
        dut->eval();
        if (tfp) tfp->dump(time++);
        dut->uart_clk = 1;
        dut->eval();
        if (tfp) tfp->dump(time++);
    }

    void reset() {
        dut->rst_n = 0;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n = 1;
        tick();
    }

    // Send one bit period (16 samples + 1 for state machine transition)
    void send_bit(int bit_value) {
        dut->rx_serial_sync = bit_value;
        for (int i = 0; i < 16; i++) {
            tick(true);  // Sample tick every clock
        }
        // Hold the bit value for one more cycle to allow state machine to transition
        // before the next bit changes rx_serial_sync
        tick(true);
    }

    // Send complete frame: start + 8 data + partial stop
    void send_frame(uint8_t data) {
        // Ensure line is idle before start bit (for falling edge detection)
        dut->rx_serial_sync = 1;
        for (int i = 0; i < 4; i++) {
            tick(true);  // A few idle samples
        }

        // Start bit
        send_bit(0);

        // Data bits (LSB first)
        for (int i = 0; i < 8; i++) {
            send_bit((data >> i) & 1);
        }

        // Stop bit - send only 9 ticks (samples 0-8) to catch rx_valid when it's set
        dut->rx_serial_sync = 1;
        for (int i = 0; i < 9; i++) {
            tick(true);
        }
        // At this point, rx_valid should be set (at sample 8 of stop bit)
    }
};

BOOST_FIXTURE_TEST_CASE(uart_rx_idle_state, UartRXFixture) {
    reset();

    BOOST_CHECK_EQUAL(dut->rx_valid, 0);
    BOOST_CHECK_EQUAL(dut->rx_active, 0);
    BOOST_CHECK_EQUAL(dut->frame_error, 0);
}

BOOST_FIXTURE_TEST_CASE(uart_rx_start_detect, UartRXFixture) {
    reset();

    // Ensure line is idle
    dut->rx_serial_sync = 1;
    for (int i = 0; i < 10; i++) tick(true);

    BOOST_CHECK_EQUAL(dut->rx_active, 0);

    // Create falling edge (start bit)
    dut->rx_serial_sync = 0;
    tick(true);

    // After one sample tick with start bit, should enter START_BIT state
    for (int i = 0; i < 5; i++) tick(true);

    // RX should become active
    BOOST_CHECK_EQUAL(dut->rx_active, 1);
}

BOOST_FIXTURE_TEST_CASE(uart_rx_receive_byte, UartRXFixture) {
    reset();

    // Set rx_ready=0 to prevent rx_valid from being auto-cleared
    dut->rx_ready = 0;

    send_frame(0xA5);

    // rx_valid should be set and held (because rx_ready=0)
    BOOST_CHECK_EQUAL(dut->rx_valid, 1);
    BOOST_CHECK_EQUAL(dut->rx_data, 0xA5);
    BOOST_CHECK_EQUAL(dut->frame_error, 0);
}

BOOST_FIXTURE_TEST_CASE(uart_rx_all_zeros, UartRXFixture) {
    reset();
    dut->rx_ready = 0;

    send_frame(0x00);

    BOOST_CHECK_EQUAL(dut->rx_valid, 1);
    BOOST_CHECK_EQUAL(dut->rx_data, 0x00);
    BOOST_CHECK_EQUAL(dut->frame_error, 0);
}

BOOST_FIXTURE_TEST_CASE(uart_rx_all_ones, UartRXFixture) {
    reset();
    dut->rx_ready = 0;

    send_frame(0xFF);

    BOOST_CHECK_EQUAL(dut->rx_valid, 1);
    BOOST_CHECK_EQUAL(dut->rx_data, 0xFF);
    BOOST_CHECK_EQUAL(dut->frame_error, 0);
}

BOOST_FIXTURE_TEST_CASE(uart_rx_frame_error, UartRXFixture) {
    reset();

    // Ensure idle state first
    dut->rx_serial_sync = 1;
    for (int i = 0; i < 4; i++) tick(true);

    // Send start bit
    send_bit(0);

    // Send data bits (all 1s)
    for (int i = 0; i < 8; i++) {
        send_bit(1);
    }

    // Send invalid stop bit (0 instead of 1)
    send_bit(0);

    // Wait for frame_error to be set
    for (int i = 0; i < 10; i++) {
        tick(false);
        if (dut->frame_error) break;
    }

    BOOST_CHECK_EQUAL(dut->frame_error, 1);
}

BOOST_AUTO_TEST_SUITE_END()
