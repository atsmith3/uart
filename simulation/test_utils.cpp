/*
 * Test Utilities
 *
 * Common helper functions for UART testing
 */

#include "test_utils.h"
#include <random>

namespace uart_test {

// Generate random data
std::vector<uint8_t> generate_random_data(size_t length) {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_int_distribution<> dis(0, 255);

    std::vector<uint8_t> data(length);
    for (size_t i = 0; i < length; i++) {
        data[i] = static_cast<uint8_t>(dis(gen));
    }
    return data;
}

// Calculate simple CRC8
uint8_t crc8(const std::vector<uint8_t>& data) {
    uint8_t crc = 0;
    for (uint8_t byte : data) {
        crc ^= byte;
        for (int i = 0; i < 8; i++) {
            if (crc & 0x80) {
                crc = (crc << 1) ^ 0x07;
            } else {
                crc <<= 1;
            }
        }
    }
    return crc;
}

} // namespace uart_test
