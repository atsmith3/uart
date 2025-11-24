/*
 * Test Utilities Header
 *
 * Common helper functions for UART testing
 */

#pragma once

#include <vector>
#include <cstdint>

namespace uart_test {

// Generate random data
std::vector<uint8_t> generate_random_data(size_t length);

// Calculate simple CRC8
uint8_t crc8(const std::vector<uint8_t>& data);

// UART frame timing helpers
constexpr int BITS_PER_FRAME = 10;  // 1 start + 8 data + 1 stop
constexpr int OVERSAMPLE_RATE = 16;

// Baud rate divisor calculations (for 7.3728 MHz clock)
constexpr uint8_t get_baud_divisor(uint32_t baud_rate) {
    return static_cast<uint8_t>(7372800 / (baud_rate * 16));
}

// Common baud rates
namespace baud {
    constexpr uint32_t BAUD_9600   = 9600;
    constexpr uint32_t BAUD_19200  = 19200;
    constexpr uint32_t BAUD_38400  = 38400;
    constexpr uint32_t BAUD_57600  = 57600;
    constexpr uint32_t BAUD_115200 = 115200;
    constexpr uint32_t BAUD_230400 = 230400;
    constexpr uint32_t BAUD_460800 = 460800;
}

// Register addresses (word-aligned)
namespace reg {
    constexpr uint32_t CTRL       = 0x00;
    constexpr uint32_t STATUS     = 0x04;
    constexpr uint32_t TX_DATA    = 0x08;
    constexpr uint32_t RX_DATA    = 0x0C;
    constexpr uint32_t BAUD_DIV   = 0x10;
    constexpr uint32_t INT_ENABLE = 0x14;
    constexpr uint32_t INT_STATUS = 0x18;
    constexpr uint32_t FIFO_CTRL  = 0x1C;
}

// Register bit fields
namespace ctrl {
    constexpr uint32_t TX_EN = (1 << 0);
    constexpr uint32_t RX_EN = (1 << 1);
}

namespace status {
    constexpr uint32_t TX_EMPTY       = (1 << 0);
    constexpr uint32_t TX_FULL        = (1 << 1);
    constexpr uint32_t RX_EMPTY       = (1 << 2);
    constexpr uint32_t RX_FULL        = (1 << 3);
    constexpr uint32_t TX_ACTIVE      = (1 << 4);
    constexpr uint32_t RX_ACTIVE      = (1 << 5);
    constexpr uint32_t FRAME_ERROR    = (1 << 6);
    constexpr uint32_t OVERRUN_ERROR  = (1 << 7);
}

namespace fifo_ctrl {
    constexpr uint32_t TX_FIFO_RST = (1 << 0);
    constexpr uint32_t RX_FIFO_RST = (1 << 1);
}

} // namespace uart_test
