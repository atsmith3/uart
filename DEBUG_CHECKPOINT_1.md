# UART Multi-Byte Debug Checkpoint 1

## Current Status

Working on fixing multi-byte loopback test failures in UART design. System tests timing out and module tests showing 19 failures.

## Issues Fixed So Far

### 1. FIFO Clear Functionality (COMPLETED)
**Problem**: Software FIFO reset was not implemented - fifo_reset signals were ignored.

**Solution**:
- Added `wr_clear` and `rd_clear` ports to `async_fifo.sv` (lines 34, 43)
- Added clear logic to write pointer (lines 103-106)
- Added clear logic to read pointer (lines 158-161)
- Connected in `uart_tx_path.sv`: wr_clear=fifo_reset, rd_clear=0 (lines 83, 92)
- Connected in `uart_rx_path.sv`: wr_clear=0, rd_clear=fifo_reset (lines 108, 117)

**Files Modified**:
- `/home/andrew/prj/chip/potato/uart/rtl/async_fifo.sv`
- `/home/andrew/prj/chip/potato/uart/rtl/uart_tx_path.sv`
- `/home/andrew/prj/chip/potato/uart/rtl/uart_rx_path.sv`

### 2. RX Prefetch FSM rd_en Assertion (COMPLETED)
**Problem**: RX holding register was stuck on first value. The `rx_rd_en` signal only pulsed when transitioning IDLE→FETCHING, not READY→FETCHING. When reading a register in READY state, the FSM would transition to FETCHING but rd_en wouldn't pulse.

**Root Cause**:
```systemverilog
// OLD (BROKEN):
assign rx_rd_en = (rx_state == RX_IDLE) && !rx_empty && ctrl_rx_en;
```

**Solution**: Added logic to pulse rd_en when transitioning from READY→FETCHING:
```systemverilog
// NEW (uart_regs.sv:348-353):
logic rx_entering_fetching;
assign rx_entering_fetching = ((rx_state == RX_IDLE) && !rx_empty && ctrl_rx_en) ||
                               ((rx_state == RX_READY) && reg_ren && (reg_addr == ADDR_RX_DATA) && ctrl_rx_en && !rx_empty);
assign rx_rd_en = rx_entering_fetching;
```

**Files Modified**:
- `/home/andrew/prj/chip/potato/uart/rtl/uart_regs.sv`

### 3. RX Duplicate FIFO Writes (COMPLETED)
**Problem**: RX was writing the same byte to FIFO multiple times. Debug output showed:
```
[uart_rx_path] 0: Writing 0x00 to RX FIFO
[uart_rx_path] 0: Writing 0x00 to RX FIFO
[uart_rx_path] 0: Writing 0x00 to RX FIFO
[uart_rx_path] 0: Writing 0x00 to RX FIFO
```

**Root Cause**: The `rx_valid_core` signal stays HIGH for multiple uart_clk cycles (until cleared by handshake on next sample_tick). During this time, `fifo_wr_en` was continuously asserted, causing multiple FIFO writes.

**Solution**: Added `rx_data_written` tracking flag to ensure only one write per rx_valid assertion:
```systemverilog
// uart_rx_path.sv:131-148
always_ff @(posedge uart_clk or negedge uart_rst_n) begin
    if (!uart_rst_n) begin
        rx_data_written <= 1'b0;
    end else begin
        if (rx_valid_core && !rx_data_written && !fifo_wr_full) begin
            rx_data_written <= 1'b1;
        end else if (!rx_valid_core) begin
            rx_data_written <= 1'b0;
        end
    end
end

assign fifo_wr_en = rx_valid_core && !rx_data_written && !fifo_wr_full;
```

**Files Modified**:
- `/home/andrew/prj/chip/potato/uart/rtl/uart_rx_path.sv`

## Current Problems

### 1. Module Tests Failing (19 failures)
**Symptoms**:
- TX tests: Start bits being read as 1 instead of 0
- RX tests: Incorrect data reception, frame errors

**Example Errors**:
```
uart_tx_frame_format: check bits[0] == 0 has failed [1 != 0]  // Start bit should be 0
uart_rx_receive_byte: check dut->rx_data == 0xA5 has failed [0x4b != 0xa5]
uart_rx_all_zeros: check dut->rx_valid == 1 has failed [0 != 0x1]
```

**Likely Cause**: Regression introduced by recent RX changes, possibly in sampling timing.

### 2. System Tests Timing Out
**Symptoms**: Tests run but timeout after 120 seconds

**Status**: May be related to module test failures - if basic TX/RX is broken, system tests will hang.

## Test Results Summary

- **Before fixes**: 67 failures (mostly repeated data issue)
- **After RX prefetch fix**: 38 failures (progress!)
- **After RX duplicate write fix**: Module tests broken (19 failures), system tests timeout

## Files Modified This Session

1. `/home/andrew/prj/chip/potato/uart/rtl/async_fifo.sv` - Added wr_clear/rd_clear
2. `/home/andrew/prj/chip/potato/uart/rtl/uart_tx_path.sv` - Connected FIFO clear
3. `/home/andrew/prj/chip/potato/uart/rtl/uart_rx_path.sv` - Connected FIFO clear, added duplicate write prevention
4. `/home/andrew/prj/chip/potato/uart/rtl/uart_regs.sv` - Fixed RX prefetch rd_en assertion
5. `/home/andrew/prj/chip/potato/uart/rtl/uart_rx.sv` - Added debug message filter (cosmetic)

## Key Debug Observations

1. **Multi-byte pattern**: First byte reads correctly, subsequent bytes stuck on first value
   - Example: Expected [0x55, 0xaa, 0xff, 0x12], Got [0, 0, 0, 0x55, 0x55, 0x55, 0x55]

2. **FIFO debug showed fetching working**: After prefetch fix, saw different values being fetched
   ```
   [uart_regs] 0: RX_READY consumed (data=0xcd, rx_empty=0)
   [uart_regs] 0: RX_FETCHING -> RX_READY (data=0xa4)
   ```

3. **Duplicate writes confirmed**: Same byte written to FIFO 4 times before fix

## Next Steps

1. **IMMEDIATE**: Debug module test failures - likely regression in RX/TX timing
2. Verify duplicate write fix doesn't break handshaking
3. Re-run system tests after module tests pass
4. Add accurate FIFO level reporting (pending task)

## Previous Session Context

This session continued from context limit. Prior work included:
- Reverted async_fifo to registered read output (industry standard)
- Implemented prefetch holding registers in uart_regs.sv and uart_tx_path.sv
- Fixed TX baud rate divider (16× to 1×)
- Fixed RX sample counter alignment (user's critical insight!)
- Single byte loopback was working

## Build Info

- Build directory: `/home/andrew/prj/chip/potato/uart/simulation/build`
- Last successful build: All modules compiled
- Test executables: `./uart_system_tests`, `./module_tests`
