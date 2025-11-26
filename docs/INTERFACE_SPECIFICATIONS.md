# UART Peripheral Interface Specifications

**Status:** Phase 0 - Design Review
**Version:** 1.0
**Last Updated:** 2025-11-26

## Overview
This document defines all module interfaces for the UART peripheral implementation. All interfaces must be approved before implementation begins (Phase 0 exit criteria).

**Reference Documents:**
- `UART_Implementation_Plan.md` - Overall implementation strategy
- `DEVELOPMENT_GUIDELINES.md` - Development process and quality gates

---

## Clock Domains

### UART Clock Domain (uart_clk)
- **Frequency:** 7.3728 MHz (4× standard UART clock)
- **Purpose:** Baud rate generation, TX serialization, RX sampling
- **Modules:** baud_gen, uart_tx, uart_rx
- **Rationale:** Provides perfect integer divisors for all standard baud rates including 460800

### System Clock Domain (clk)
- **Frequency:** ~1 MHz
- **Purpose:** AXI-Lite interface, register file, control logic
- **Modules:** axi_lite_slave_if, uart_regs
- **Rationale:** Typical embedded system bus frequency

### CDC Boundaries (Critical!)
1. **TX Path:** clk → uart_clk via sync_fifo (single clock domain, both sides use uart_clk)
2. **RX Path:** uart_clk → clk via sync_fifo (single clock domain, both sides use uart_clk)
3. **RX Serial Input:** async → uart_clk via bit_sync (2-FF synchronizer)
4. **Control Signals:** If needed, use bit_sync

**Note:** Initial implementation uses sync_fifo (single clock domain) to avoid CDC complexity. All UART logic runs on uart_clk.

---

## Module 1: bit_sync

### Purpose
Synchronize single-bit asynchronous signals to destination clock domain using 2-stage flip-flop synchronizer for metastability protection.

### Parameters
- `STAGES`: Number of FF stages (default: 2, range: 2-3)

### Interface Table

| Signal      | Direction | Width | Clock Domain | Reset Value | Description |
|-------------|-----------|-------|--------------|-------------|-------------|
| clk_dst     | Input     | 1     | dst          | N/A         | Destination clock |
| rst_n_dst   | Input     | 1     | dst          | N/A         | Active-low reset (dest domain) |
| data_in     | Input     | 1     | async        | X           | Asynchronous input signal |
| data_out    | Output    | 1     | dst          | 0           | Synchronized output |

### Timing Characteristics
- **Latency:** 2-3 clock cycles (depending on STAGES parameter)
- **MTBF:** > 10^9 years for 2 stages at typical frequencies
- **Maximum input frequency:** Must be < dst_clk_freq / 3 for reliable detection

### Protocol Rules
- `data_in` may change asynchronously at any time
- `data_out` synchronized to `clk_dst` rising edge
- No handshaking required (one-way synchronization)
- Pulse stretching on input required if pulse < 2 × clk_dst periods

### Timing Diagram
```
clk_dst     : _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\
data_in     : ___/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
data_out    : _______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
                     ^^^ 2-cycle latency
```

### Usage Notes
- Use ONLY for single-bit control signals crossing clock domains
- Do NOT use for multi-bit buses (use Gray code or handshake instead)
- Adequate for slow-changing signals (e.g., uart_rx serial input)
- Synthesis attributes required: `(* ASYNC_REG = "TRUE" *)`

---

## Module 2: sync_fifo

### Purpose
Synchronous FIFO for buffering data within single clock domain. Used for TX and RX data buffering in UART paths.

### Parameters
- `DATA_WIDTH`: Width of data (default: 8, range: 1-32)
- `DEPTH`: FIFO depth, **must be power of 2** (default: 8, range: 4-256)
- `ADDR_WIDTH`: log2(DEPTH) - derived automatically

### Interface Table

| Signal      | Direction | Width          | Clock Domain | Reset Value | Description |
|-------------|-----------|----------------|--------------|-------------|-------------|
| clk         | Input     | 1              | single       | N/A         | Clock |
| rst_n       | Input     | 1              | single       | N/A         | Active-low reset |
| wr_en       | Input     | 1              | single       | 0           | Write enable (pulse) |
| wr_data     | Input     | DATA_WIDTH     | single       | X           | Write data (valid when wr_en=1) |
| wr_full     | Output    | 1              | single       | 0           | FIFO full flag |
| rd_en       | Input     | 1              | single       | 0           | Read enable (pulse) |
| rd_data     | Output    | DATA_WIDTH     | single       | 0           | Read data (registered) |
| rd_empty    | Output    | 1              | single       | 1           | FIFO empty flag |
| level       | Output    | ADDR_WIDTH+1   | single       | 0           | Current fill level (0 to DEPTH) |

### Timing Characteristics
- **Write latency:** Data stored on rising edge when wr_en=1 and wr_full=0
- **Read latency:** Data available 1 cycle after rd_en=1 (registered output)
- **Flag update:** wr_full and rd_empty update 1 cycle after write/read
- **Simultaneous access:** Can write and read in same cycle

### Protocol Rules
1. **Write Protocol:**
   - Check `wr_full=0` BEFORE asserting `wr_en`
   - Assert `wr_en` for exactly 1 cycle
   - Hold `wr_data` stable when `wr_en=1`

2. **Read Protocol:**
   - Check `rd_empty=0` BEFORE asserting `rd_en`
   - Assert `rd_en` for exactly 1 cycle
   - `rd_data` valid 1 cycle after `rd_en` (registered output)

3. **Simultaneous R/W:**
   - Allowed when FIFO not empty AND not full
   - Level remains constant (one in, one out)

### Timing Diagram - Write Operation
```
Cycle:      0     1     2     3     4
clk      : _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\
wr_en    : ___/‾\_____/‾\_________
wr_data  : XXX<D0>XXX<D1>XXXXXXXX
wr_full  : _______________________  (example: not full)
level    : <0><0><1><1><2><2><2>
                 ^^^ increment after write
```

### Timing Diagram - Read Operation
```
Cycle:      0     1     2     3     4
clk      : _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\
rd_en    : ___/‾\_____/‾\_________
rd_data  : XXX<X><D0><D0><D1><D1>
                 ^^^ data valid 1 cycle after rd_en
rd_empty : _______________________  (example: not empty)
level    : <2><2><1><1><0><0><0>
```

### Error Conditions
- **Write when wr_full=1:** Data lost silently, no error flag
- **Read when rd_empty=1:** rd_data undefined, no error flag
- **Application responsibility:** Check flags before accessing

### Implementation Notes
- Use binary pointers (not Gray code - single clock domain)
- Registered output for timing closure
- Separate read/write pointers allow simultaneous access
- Extra bit in pointers for full/empty distinction

---

## Module 3: baud_gen

### Purpose
Generate baud rate tick enable from UART clock. Produces 16× oversampling tick for RX and can be divided for TX 1× baud rate.

### Parameters
- `DIVISOR_WIDTH`: Width of divisor register (default: 8, sufficient for 1-255)
- `UART_CLK_FREQ`: UART clock frequency in Hz (default: 7372800)

### Interface Table

| Signal           | Direction | Width          | Clock Domain | Reset Value | Description |
|------------------|-----------|----------------|--------------|-------------|-------------|
| uart_clk         | Input     | 1              | uart_clk     | N/A         | UART clock (7.3728 MHz) |
| rst_n            | Input     | 1              | uart_clk     | N/A         | Active-low reset |
| baud_divisor     | Input     | DIVISOR_WIDTH  | uart_clk     | 0           | Baud rate divisor (1-255) |
| enable           | Input     | 1              | uart_clk     | 0           | Enable tick generation |
| baud_tick        | Output    | 1              | uart_clk     | 0           | Baud tick pulse (16× baud rate) |

### Timing Characteristics
- **Output frequency:** uart_clk_freq / baud_divisor
- **Pulse width:** 1 uart_clk cycle
- **Duty cycle:** 1/baud_divisor (e.g., 1/4 = 25% for 115200 baud)
- **Jitter:** None (clock-synchronous)

### Baud Rate Configuration

| Baud Rate | Oversampling | Required Tick Freq | Divisor | Formula |
|-----------|--------------|-------------------|---------|---------|
| 9600      | 16×          | 153600 Hz         | 48      | 7372800/(9600×16) |
| 19200     | 16×          | 307200 Hz         | 24      | 7372800/(19200×16) |
| 38400     | 16×          | 614400 Hz         | 12      | 7372800/(38400×16) |
| 57600     | 16×          | 921600 Hz         | 8       | 7372800/(57600×16) |
| 115200    | 16×          | 1843200 Hz        | 4       | 7372800/(115200×16) |
| 230400    | 16×          | 3686400 Hz        | 2       | 7372800/(230400×16) |
| 460800    | 16×          | 7372800 Hz        | 1       | 7372800/(460800×16) |

**Note:** All baud rates have 0% error due to 7.3728 MHz clock choice.

### Protocol Rules
- `baud_divisor` must be ≥ 1 (0 is invalid, treated as disable)
- `baud_divisor` can be changed dynamically (takes effect immediately)
- `enable=0` stops tick generation (baud_tick stays 0)
- `enable=1` starts/resumes tick generation

### Timing Diagram
```
For baud_divisor=4 (115200 baud):

uart_clk      : _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\
baud_tick     : _______/‾\_____________/‾\_____________/‾\______
counter       : <3><2><1><0><3><2><1><0><3><2><1><0><3>
                        ^^^ tick when counter reaches 0
```

### Implementation Notes
- Simple down-counter: counts from divisor-1 to 0
- Generate tick pulse when counter = 0
- Reload counter with divisor-1 after tick
- Synchronous enable (affects next cycle)

---

## Module 4: uart_tx

### Purpose
Serialize 8-bit data into UART TX frame format (8N1): 1 start bit (LOW), 8 data bits (LSB first), 1 stop bit (HIGH).

### Parameters
- `DATA_WIDTH`: Data width (default: 8, fixed for 8N1)
- `OVERSAMPLE_RATE`: Input sample rate (default: 16, matches baud_gen output)

### Interface Table

| Signal      | Direction | Width       | Clock Domain | Reset Value | Description |
|-------------|-----------|-------------|--------------|-------------|-------------|
| uart_clk    | Input     | 1           | uart_clk     | N/A         | UART clock |
| rst_n       | Input     | 1           | uart_clk     | N/A         | Active-low reset |
| baud_tick   | Input     | 1           | uart_clk     | 0           | 16× baud rate tick from baud_gen |
| tx_data     | Input     | DATA_WIDTH  | uart_clk     | X           | Data to transmit |
| tx_valid    | Input     | 1           | uart_clk     | 0           | Data valid (ready/valid handshake) |
| tx_ready    | Output    | 1           | uart_clk     | 1           | Ready to accept data |
| tx_serial   | Output    | 1           | uart_clk     | 1           | Serial output line |
| tx_active   | Output    | 1           | uart_clk     | 0           | Transmission in progress |

### Timing Characteristics
- **Throughput:** 1 byte per 10 bit periods (start + 8 data + stop)
- **Bit period:** 16 baud_ticks (16× oversampling input)
- **Frame time:** 160 baud_ticks for complete frame
- **Idle state:** tx_serial=1 (mark)

### UART Frame Format (8N1)
```
      ┌─────┬────┬────┬────┬────┬────┬────┬────┬────┬──────┐
Idle  │Start│ D0 │ D1 │ D2 │ D3 │ D4 │ D5 │ D6 │ D7 │ Stop │ Idle
(1)   │  0  │LSB │    │    │    │    │    │    │MSB │  1   │ (1)
      └─────┴────┴────┴────┴────┴────┴────┴────┴────┴──────┘
       16T   16T  16T  16T  16T  16T  16T  16T  16T   16T

T = baud_tick period (1/16 of bit time)
```

### Protocol Rules - Ready/Valid Handshake
1. **Master (upstream):**
   - Wait for `tx_ready=1`
   - Assert `tx_valid=1` and present `tx_data`
   - Hold until handshake completes

2. **Slave (uart_tx):**
   - Assert `tx_ready=1` when IDLE
   - When `tx_valid && tx_ready`: latch data, start transmission
   - Deassert `tx_ready` during transmission
   - Assert `tx_ready` after transmission complete

3. **Transaction:**
   - Occurs when both `tx_valid && tx_ready` (single cycle)
   - `tx_data` must be stable when transaction occurs

### Timing Diagram - Transaction
```
Cycle:        0     1     2     3     ...   162   163   164
uart_clk   : _/‾\_/‾\_/‾\_/‾\_/‾\_/.../_/‾\_/‾\_/‾\
baud_tick  : ___/‾\_____/‾\_____/.../_____/‾\_____  (every 1 tick shown)
tx_valid   : ___/‾‾‾‾‾‾‾‾‾‾‾\_____.../_____________
tx_ready   : ‾‾‾‾‾‾‾\_____________.../_____________/‾‾‾
tx_data    : XXX<0xAB>XXXXXXXXXXXX...XXXXXXXXXXXXX
tx_serial  : ‾‾‾‾‾‾‾\_____[data bits]_____/‾‾‾‾‾‾‾
tx_active  : _______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾...‾‾‾‾‾‾‾‾‾‾‾‾\_
                   ^^^ latch data, start transmission
```

### State Machine
```
IDLE:
  - tx_ready=1, tx_serial=1 (idle high)
  - Wait for tx_valid && tx_ready
  - Latch tx_data, transition to START

START:
  - tx_ready=0, tx_serial=0 (start bit)
  - Count 16 baud_ticks
  - Transition to DATA

DATA:
  - tx_ready=0, tx_serial=current data bit
  - Shift out 8 bits LSB first
  - Count 16 baud_ticks per bit
  - Transition to STOP after 8 bits

STOP:
  - tx_ready=0, tx_serial=1 (stop bit)
  - Count 16 baud_ticks
  - Transition to IDLE
```

### Implementation Notes
- Baud tick divider: count 16 baud_ticks per bit period
- Bit counter: track 0-7 data bits
- Shift register: shift right, MSB first internally becomes LSB first output
- Default line state: HIGH (mark)

---

## Module 5: uart_rx

### Purpose
Deserialize UART RX line (8N1 format) into 8-bit parallel data using 16× oversampling for noise immunity and accurate sampling.

### Parameters
- `DATA_WIDTH`: Data width (default: 8, fixed for 8N1)
- `OVERSAMPLE_RATE`: Oversampling rate (default: 16)

### Interface Table

| Signal           | Direction | Width       | Clock Domain | Reset Value | Description |
|------------------|-----------|-------------|--------------|-------------|-------------|
| uart_clk         | Input     | 1           | uart_clk     | N/A         | UART clock |
| rst_n            | Input     | 1           | uart_clk     | N/A         | Active-low reset |
| sample_tick      | Input     | 1           | uart_clk     | 0           | 16× baud rate tick from baud_gen |
| rx_serial_sync   | Input     | 1           | uart_clk     | 1           | Synchronized serial input (from bit_sync) |
| rx_data          | Output    | DATA_WIDTH  | uart_clk     | 0           | Received data |
| rx_valid         | Output    | 1           | uart_clk     | 0           | Data valid (ready/valid handshake) |
| rx_ready         | Input     | 1           | uart_clk     | 0           | Ready to accept (from downstream) |
| frame_error      | Output    | 1           | uart_clk     | 0           | Frame error flag (stop bit != 1) |
| rx_active        | Output    | 1           | uart_clk     | 0           | Reception in progress |

### Timing Characteristics
- **Start bit detection:** Falling edge on rx_serial_sync
- **Bit sampling:** At middle of bit period (sample 8 of 16)
- **Frame time:** 160 sample_ticks (10 bits × 16 samples/bit)
- **Idle state:** rx_serial_sync=1 (mark)

### UART Frame Timing (16× Oversampling)
```
rx_serial:  ‾‾‾‾\_____[8 data bits]_____/‾‾‾‾
                 ^                     ^
                 Start bit            Stop bit

sample_tick: (16 ticks per bit period)
Samples:     0 1 2 3 4 5 6 7 8 9 A B C D E F
                         ↑
                         Sample here (tick 8 = middle)
```

### Protocol Rules - Ready/Valid Handshake
1. **Slave (uart_rx):**
   - Detect start bit (falling edge)
   - Sample data bits at middle of each bit period
   - Assert `rx_valid=1` when complete valid frame received
   - Hold `rx_data` and `rx_valid` until handshake

2. **Master (downstream):**
   - Assert `rx_ready=1` when ready to accept
   - Latch `rx_data` when `rx_valid && rx_ready`

3. **Transaction:**
   - Occurs when both `rx_valid && rx_ready` (single cycle)
   - `rx_valid` deasserts after transaction

### Timing Diagram - Reception
```
sample_tick:  ___/‾\_/‾\_/‾\_/‾\_/‾\_/‾\...  (continues)
rx_serial:    ‾‾‾‾\_____0__1__0__1__0__1...____/‾‾‾‾
              IDLE START D0  D1  D2  D3  D4...STOP IDLE
                   ↑    ↑   ↑   ↑   ↑   ↑       ↑
sample_counter: 0  0    8   8   8   8   8       8
                   ↑detect   ↑sample at middle
                   start     of each bit

rx_valid:     ___________________________/‾‾‾‾\_____
rx_ready:     ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
rx_data:      XXXXXXXXXXXXXXXXXXXXXXXX<0xAA>XXXXXXX
```

### Sampling Strategy - CRITICAL!
```
**Start Bit Detection:**
1. Monitor for falling edge (1 → 0) on rx_serial_sync
2. When detected: Reset sample_counter to 0, go to START_BIT state
3. Wait 8 sample_ticks (to middle of start bit)
4. Sample rx_serial_sync: if LOW, valid start; if HIGH, false start → abort

**Data Bit Sampling:**
1. For each of 8 data bits:
   - Wait for sample_counter = 8 (middle of bit period)
   - Sample rx_serial_sync
   - Shift into receive register (LSB first)
   - Continue counting to 15, then reset to 0 for next bit

**Stop Bit Validation:**
1. At middle of stop bit (sample_counter = 8):
   - Sample rx_serial_sync
   - If HIGH: Valid frame, assert rx_valid
   - If LOW: Frame error, set frame_error flag
```

### State Machine
```
IDLE:
  - Wait for start bit (rx_serial_sync: 1 → 0)
  - When detected: sample_counter = 0, → START_BIT

START_BIT:
  - Count sample_ticks 0 to 15
  - At count 8: Validate rx_serial_sync = 0
    - If valid: Continue
    - If invalid (rx_serial_sync = 1): False start → IDLE
  - At count 15: → DATA_BITS

DATA_BITS:
  - For each bit (0-7):
    - Count sample_ticks 0 to 15
    - At count 8: Sample rx_serial_sync, shift into register (LSB first)
    - At count 15: Next bit or → STOP_BIT

STOP_BIT:
  - Count sample_ticks 0 to 15
  - At count 8: Validate rx_serial_sync = 1
    - If valid: Assert rx_valid, rx_data = shift_reg
    - If invalid: Set frame_error
  - Wait for rx_valid && rx_ready handshake
  - After handshake: → IDLE
```

### Error Detection
- **Frame Error:** Stop bit is not HIGH at sample point
- **Overrun Error:** (Handled by FIFO full in uart_rx_path)
- **False Start:** Start bit HIGH at center → return to IDLE

### Implementation Notes
- **Sample counter initialization:** Must start at 0 on start bit detection
- **Bit-center sampling:** Count 8 of 16 is middle of bit
- **LSB first:** Shift right, so bit 0 → LSB of output
- **Synchronizer required:** Use bit_sync module for rx_serial input

---

## Module 6: uart_tx_path

### Purpose
Integration of TX FIFO and uart_tx core for buffered transmission. AXI writes to FIFO, uart_tx automatically drains FIFO.

### Parameters
- `FIFO_DEPTH`: TX FIFO depth (default: 8, must be power of 2)
- `DATA_WIDTH`: Data width (default: 8)

### Interface Table

| Signal      | Direction | Width | Clock Domain | Reset Value | Description |
|-------------|-----------|-------|--------------|-------------|-------------|
| uart_clk    | Input     | 1     | uart_clk     | N/A         | UART clock (all logic in UART domain) |
| rst_n       | Input     | 1     | uart_clk     | N/A         | Active-low reset |
| baud_tick   | Input     | 1     | uart_clk     | 0           | 16× baud rate tick from baud_gen |
| wr_data     | Input     | 8     | uart_clk     | X           | Data to write to TX FIFO |
| wr_en       | Input     | 1     | uart_clk     | 0           | Write enable from register interface |
| tx_serial   | Output    | 1     | uart_clk     | 1           | Serial output to UART TX pin |
| tx_empty    | Output    | 1     | uart_clk     | 1           | TX FIFO empty flag |
| tx_full     | Output    | 1     | uart_clk     | 1           | TX FIFO full flag |
| tx_active   | Output    | 1     | uart_clk     | 0           | Transmission in progress |
| tx_level    | Output    | $     | uart_clk     | 0           | TX FIFO fill level |

### Architecture
```
wr_data ────→ sync_fifo ────→ uart_tx ────→ tx_serial
wr_en           (8 deep)        (8N1)
                   ↓              ↓
                 flags         tx_active
```

### Data Flow
1. **Write side:** Software writes byte to FIFO via `wr_en` and `wr_data`
2. **Read side:** uart_tx automatically reads from FIFO when ready
3. **Automatic drain:** When FIFO not empty, uart_tx fetches and transmits

### Protocol Rules
1. **FIFO Write:**
   - Check `tx_full=0` before writing
   - Assert `wr_en=1` for 1 cycle with valid `wr_data`

2. **Automatic TX:**
   - When `!tx_empty`: uart_tx reads and transmits
   - No manual intervention needed
   - Continuous transmission of queued data

### Status Flags
- **tx_empty:** No data in FIFO (safe to disable TX)
- **tx_full:** FIFO full (software must wait)
- **tx_active:** uart_tx actively transmitting
- **tx_level:** Number of bytes in FIFO (for flow control)

---

## Module 7: uart_rx_path

### Purpose
Integration of uart_rx core and RX FIFO for buffered reception. uart_rx automatically fills FIFO, AXI reads drain FIFO.

### Parameters
- `FIFO_DEPTH`: RX FIFO depth (default: 8, must be power of 2)
- `DATA_WIDTH`: Data width (default: 8)

### Interface Table

| Signal           | Direction | Width | Clock Domain | Reset Value | Description |
|------------------|-----------|-------|--------------|-------------|-------------|
| uart_clk         | Input     | 1     | uart_clk     | N/A         | UART clock (all logic in UART domain) |
| rst_n            | Input     | 1     | uart_clk     | N/A         | Active-low reset |
| sample_tick      | Input     | 1     | uart_clk     | 0           | 16× baud rate tick from baud_gen |
| rx_serial        | Input     | 1     | async        | 1           | UART RX input pin (asynchronous!) |
| rd_data          | Output    | 8     | uart_clk     | 0           | Data read from RX FIFO |
| rd_en            | Input     | 1     | uart_clk     | 0           | Read enable from register interface |
| rx_empty         | Output    | 1     | uart_clk     | 1           | RX FIFO empty flag |
| rx_full          | Output    | 1     | uart_clk     | 0           | RX FIFO full flag |
| rx_active        | Output    | 1     | uart_clk     | 0           | Reception in progress |
| frame_error      | Output    | 1     | uart_clk     | 0           | Frame error flag (sticky) |
| overrun_error    | Output    | 1     | uart_clk     | 0           | Overrun error flag (sticky) |
| rx_level         | Output    | $     | uart_clk     | 0           | RX FIFO fill level |

### Architecture
```
rx_serial → bit_sync → uart_rx → sync_fifo → rd_data
 (async)    (2-FF)      (8N1)     (8 deep)     rd_en
                          ↓          ↓
                     frame_error  flags
```

### Data Flow
1. **Async input:** `rx_serial` synchronized via bit_sync
2. **Reception:** uart_rx deserializes into bytes
3. **FIFO write:** Valid bytes automatically written to FIFO
4. **Read side:** Software reads from FIFO via `rd_en`

### Protocol Rules
1. **Automatic RX:**
   - uart_rx continuously monitors for frames
   - Valid frames automatically written to FIFO
   - No manual control needed

2. **FIFO Read:**
   - Check `rx_empty=0` before reading
   - Assert `rd_en=1` for 1 cycle
   - `rd_data` valid 1 cycle later (registered FIFO output)

3. **Error Handling:**
   - `frame_error`: Sticky flag when stop bit invalid
   - `overrun_error`: Sticky flag when FIFO full and new data arrives
   - Software must clear errors via register write

### Critical Implementation Detail - Duplicate Write Prevention

**Problem:** uart_rx asserts `rx_valid` for multiple uart_clk cycles (until handshake). If FIFO `wr_en` is simply connected to `rx_valid`, the same byte gets written multiple times!

**Solution:** Track writes to ensure only ONE FIFO write per `rx_valid` assertion:

```systemverilog
logic rx_data_written;

always_ff @(posedge uart_clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_data_written <= 1'b0;
    end else begin
        if (rx_valid_from_core && !rx_data_written && !fifo_full) begin
            rx_data_written <= 1'b1;  // Mark as written
        end else if (!rx_valid_from_core) begin
            rx_data_written <= 1'b0;  // Clear when valid drops
        end
    end
end

assign fifo_wr_en = rx_valid_from_core && !rx_data_written && !fifo_full;
```

This ensures exactly one FIFO write per received byte.

---

## Module 8: axi_lite_slave_if

### Purpose
Implement AXI-Lite slave protocol for register access. Converts AXI-Lite 5-channel protocol to simple register read/write interface.

### Parameters
- `DATA_WIDTH`: AXI data width (default: 32)
- `ADDR_WIDTH`: AXI address width (default: 32)
- `REG_ADDR_WIDTH`: Internal register address width (default: 4, supports 16 registers)

### Interface Table - AXI-Lite Side

| Channel | Signal     | Direction | Width       | Description |
|---------|------------|-----------|-------------|-------------|
| AW      | awaddr     | Input     | ADDR_WIDTH  | Write address |
|         | awvalid    | Input     | 1           | Write address valid |
|         | awready    | Output    | 1           | Write address ready |
| W       | wdata      | Input     | DATA_WIDTH  | Write data |
|         | wstrb      | Input     | DATA_WIDTH/8| Write strobe (byte enables) |
|         | wvalid     | Input     | 1           | Write data valid |
|         | wready     | Output    | 1           | Write data ready |
| B       | bresp      | Output    | 2           | Write response (OKAY/SLVERR) |
|         | bvalid     | Output    | 1           | Write response valid |
|         | bready     | Input     | 1           | Write response ready |
| AR      | araddr     | Input     | ADDR_WIDTH  | Read address |
|         | arvalid    | Input     | 1           | Read address valid |
|         | arready    | Output    | 1           | Read address ready |
| R       | rdata      | Output    | DATA_WIDTH  | Read data |
|         | rresp      | Output    | 2           | Read response (OKAY/SLVERR) |
|         | rvalid     | Output    | 1           | Read data valid |
|         | rready     | Input     | 1           | Read data ready |

### Interface Table - Register Side

| Signal     | Direction | Width          | Description |
|------------|-----------|----------------|-------------|
| reg_addr   | Output    | REG_ADDR_WIDTH | Register address |
| reg_wdata  | Output    | DATA_WIDTH     | Write data to registers |
| reg_wen    | Output    | 1              | Write enable pulse |
| reg_ren    | Output    | 1              | Read enable pulse |
| reg_rdata  | Input     | DATA_WIDTH     | Read data from registers |
| reg_error  | Input     | 1              | Register access error |

### Protocol - AXI-Lite Write
```
Master:
1. Assert awvalid + awaddr (address phase)
2. Assert wvalid + wdata + wstrb (data phase)
3. Wait for awready && wready (can be same cycle)
4. Wait for bvalid (response phase)
5. Assert bready to complete

Slave (this module):
1. Wait for awvalid && wvalid
2. Assert awready && wready
3. Decode address → reg_addr
4. Assert reg_wen for 1 cycle
5. Assert bvalid with bresp = OKAY or SLVERR
6. Wait for bready, then deassert bvalid
```

### Protocol - AXI-Lite Read
```
Master:
1. Assert arvalid + araddr
2. Wait for arready
3. Wait for rvalid + rdata
4. Assert rready to complete

Slave (this module):
1. Wait for arvalid
2. Assert arready
3. Decode address → reg_addr
4. Assert reg_ren for 1 cycle
5. Capture reg_rdata
6. Assert rvalid with rdata and rresp
7. Wait for rready, then deassert rvalid
```

### Timing - Single Cycle Access (Best Case)
```
Write:
Cycle:    0     1     2     3     4
clk    : _/‾\_/‾\_/‾\_/‾\_/‾\
awvalid: ___/‾‾‾\_____________
wvalid : ___/‾‾‾\_____________
awready: ___/‾\_______________
wready : ___/‾\_______________
reg_wen: _______/‾\___________
bvalid : ___________/‾‾‾\_____
bready : ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾

Read:
Cycle:    0     1     2     3
clk    : _/‾\_/‾\_/‾\_/‾\
arvalid: ___/‾‾‾\_________
arready: ___/‾\___________
reg_ren: _______/‾\_______
rvalid : ___________/‾‾‾\_
rready : ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
```

### Response Codes
- `OKAY (2'b00)`: Successful access to valid address
- `SLVERR (2'b10)`: Access to invalid address

### Implementation Notes
- Write and read paths are independent (can overlap)
- Single-cycle register access (no wait states)
- Byte enables (wstrb) supported for partial writes
- Invalid addresses return SLVERR response

---

## Module 9: uart_regs

### Purpose
UART register file implementing control, status, and data registers. Connects AXI interface to UART TX/RX paths.

### Parameters
- `DATA_WIDTH`: AXI data width (default: 32)
- `FIFO_ADDR_WIDTH`: FIFO address width for level reporting

### Register Map (Byte-Addressed, 32-bit Aligned)

| Offset | Register    | Access | Reset  | Description |
|--------|-------------|--------|--------|-------------|
| 0x00   | CTRL        | RW     | 0x0000 | Control register |
| 0x04   | STATUS      | RO     | 0x0005 | Status register (TX_EMPTY + RX_EMPTY) |
| 0x08   | TX_DATA     | WO     | N/A    | Transmit data (write to TX FIFO) |
| 0x0C   | RX_DATA     | RO     | 0x0000 | Receive data (read from RX FIFO) |
| 0x10   | BAUD_DIV    | RW     | 0x0004 | Baud rate divisor (default 115200) |
| 0x14   | INT_ENABLE  | RW     | 0x0000 | Interrupt enable |
| 0x18   | INT_STATUS  | RW1C   | 0x0000 | Interrupt status (write 1 to clear) |
| 0x1C   | FIFO_CTRL   | RW     | 0x0000 | FIFO control (reset FIFOs) |

### Register Definitions

#### CTRL (0x00) - Control Register
| Bit | Field | Access | Reset | Description |
|-----|-------|--------|-------|-------------|
| 0   | TX_EN | RW     | 0     | Transmit enable (1=enable, 0=disable) |
| 1   | RX_EN | RW     | 0     | Receive enable (1=enable, 0=disable) |
| 31:2| Rsvd  | RO     | 0     | Reserved (read as 0, writes ignored) |

#### STATUS (0x04) - Status Register (Read-Only)
| Bit   | Field         | Access | Description |
|-------|---------------|--------|-------------|
| 0     | TX_EMPTY      | RO     | TX FIFO empty (1=empty) |
| 1     | TX_FULL       | RO     | TX FIFO full (1=full) |
| 2     | RX_EMPTY      | RO     | RX FIFO empty (1=empty) |
| 3     | RX_FULL       | RO     | RX FIFO full (1=full) |
| 4     | TX_ACTIVE     | RO     | Transmission in progress |
| 5     | RX_ACTIVE     | RO     | Reception in progress |
| 6     | FRAME_ERROR   | RO     | Frame error detected (sticky) |
| 7     | OVERRUN_ERROR | RO     | Overrun error detected (sticky) |
| 15:8  | TX_LEVEL      | RO     | TX FIFO fill level (0-DEPTH) |
| 23:16 | RX_LEVEL      | RO     | RX FIFO fill level (0-DEPTH) |
| 31:24 | Rsvd          | RO     | Reserved (always 0) |

#### TX_DATA (0x08) - Transmit Data Register (Write-Only)
| Bit  | Field   | Access | Description |
|------|---------|--------|-------------|
| 7:0  | TX_DATA | WO     | Data to transmit (written to TX FIFO) |
| 31:8 | Rsvd    | WO     | Reserved (ignored) |

**Side Effect:** Write to this register pushes byte to TX FIFO (if not full)

#### RX_DATA (0x0C) - Receive Data Register (Read-Only)
| Bit  | Field   | Access | Description |
|------|---------|--------|-------------|
| 7:0  | RX_DATA | RO     | Received data (read from RX FIFO) |
| 31:8 | Rsvd    | RO     | Reserved (always 0) |

**Side Effect:** Read from this register pops byte from RX FIFO (if not empty)

**Critical:** Since FIFO has registered output (1-cycle latency), simple rd_en pulse causes stale data. Must implement prefetch holding register if not using async_fifo!

#### BAUD_DIV (0x10) - Baud Rate Divisor
| Bit   | Field   | Access | Reset | Description |
|-------|---------|--------|-------|-------------|
| 15:0  | DIVISOR | RW     | 0x04  | Baud rate divisor (default 4 = 115200) |
| 31:16 | Rsvd    | RO     | 0     | Reserved |

#### INT_ENABLE (0x14) - Interrupt Enable
| Bit  | Field         | Access | Reset | Description |
|------|---------------|--------|-------|-------------|
| 0    | TX_READY_IE   | RW     | 0     | TX ready interrupt enable |
| 1    | RX_READY_IE   | RW     | 0     | RX ready interrupt enable |
| 2    | FRAME_ERR_IE  | RW     | 0     | Frame error interrupt enable |
| 3    | OVERRUN_IE    | RW     | 0     | Overrun error interrupt enable |
| 31:4 | Rsvd          | RO     | 0     | Reserved |

#### INT_STATUS (0x18) - Interrupt Status (Write 1 to Clear)
| Bit  | Field        | Access | Reset | Description |
|------|--------------|--------|-------|-------------|
| 0    | TX_READY_IS  | RW1C   | 0     | TX ready interrupt status |
| 1    | RX_READY_IS  | RW1C   | 0     | RX ready interrupt status |
| 2    | FRAME_ERR_IS | RW1C   | 0     | Frame error interrupt status |
| 3    | OVERRUN_IS   | RW1C   | 0     | Overrun error interrupt status |
| 31:4 | Rsvd         | RO     | 0     | Reserved |

**Write 1 to Clear (W1C):** Writing 1 clears the bit, writing 0 has no effect

#### FIFO_CTRL (0x1C) - FIFO Control
| Bit | Field        | Access | Description |
|-----|--------------|--------|-------------|
| 0   | TX_FIFO_RST  | RW     | TX FIFO reset (self-clearing, write 1 to reset) |
| 1   | RX_FIFO_RST  | RW     | RX FIFO reset (self-clearing, write 1 to reset) |
| 31:2| Rsvd         | RO     | Reserved |

**Self-Clearing:** Bits automatically clear to 0 after 1 cycle

### Interface Connections
- **To axi_lite_slave_if:** reg_addr, reg_wdata, reg_wen, reg_ren, reg_rdata, reg_error
- **To uart_tx_path:** wr_data, wr_en, tx_empty, tx_full, tx_active, tx_level
- **To uart_rx_path:** rd_data, rd_en, rx_empty, rx_full, rx_active, rx_level, frame_error, overrun_error
- **To baud_gen:** baud_divisor, enable (from CTRL.TX_EN or CTRL.RX_EN)

### Critical Implementation Notes

1. **FIFO Side Effects:**
   - TX_DATA write → pushes to TX FIFO
   - RX_DATA read → pops from RX FIFO

2. **Registered FIFO Output Issue:**
   - sync_fifo has 1-cycle read latency
   - Simple rd_en pulse returns stale data
   - **Solution:** Prefetch holding register (see below)

3. **Prefetch Logic for RX:**
```systemverilog
// FSM states
typedef enum {RX_IDLE, RX_FETCHING, RX_READY} rx_state_t;

// When transitioning to FETCHING, pulse rd_en
assign fifo_rd_en = (state == RX_IDLE && !rx_empty) ||  // Initial fetch
                    (state == RX_READY && reg_read_rx);  // Refetch after read

// Hold fetched data in holding register
always_ff @(posedge clk) begin
    if (state == RX_FETCHING && !rx_empty)
        rx_holding_reg <= fifo_rd_data;  // Capture 1 cycle after rd_en
end
```

4. **Error Flag Handling:**
   - Error flags in STATUS are read-only
   - Clear via INT_STATUS (W1C)
   - Sticky behavior: remain set until cleared

---

## Module 10: uart_top

### Purpose
Top-level integration of all UART components. Single module instantiating complete UART peripheral with AXI-Lite interface.

### Parameters
- `DATA_WIDTH`: AXI data width (default: 32)
- `ADDR_WIDTH`: AXI address width (default: 32)
- `TX_FIFO_DEPTH`: TX FIFO depth (default: 8)
- `RX_FIFO_DEPTH`: RX FIFO depth (default: 8)
- `UART_CLK_FREQ`: UART clock frequency in Hz (default: 7372800)

### Interface Table

| Signal      | Direction | Width       | Clock Domain | Description |
|-------------|-----------|-------------|--------------|-------------|
| clk         | Input     | 1           | clk          | System clock (~1 MHz for AXI) |
| rst_n       | Input     | 1           | clk          | Active-low reset (system domain) |
| uart_clk    | Input     | 1           | uart_clk     | UART clock (7.3728 MHz) |
| uart_rst_n  | Input     | 1           | uart_clk     | Active-low reset (UART domain) |
| uart_tx     | Output    | 1           | uart_clk     | UART transmit line |
| uart_rx     | Input     | 1           | async        | UART receive line (asynchronous!) |
| irq         | Output    | 1           | clk          | Interrupt request output |

**AXI-Lite Slave Interface:** (See axi_lite_slave_if specification)

### Block Diagram
```
                   ┌────────────────────────────────────────┐
                   │           uart_top                     │
                   │                                        │
     AXI-Lite      │  ┌──────────────┐   ┌──────────────┐  │
    ───────────────┼─→│ axi_lite     │──→│  uart_regs   │  │
                   │  │ _slave_if    │←──│              │  │
                   │  └──────────────┘   └──────┬───────┘  │
                   │                            │          │
                   │                     ┌──────┴────┐     │
                   │                     │ baud_gen  │     │
                   │                     └──────┬────┘     │
                   │                            │baud_tick │
                   │        ┌───────────────────┼─────────┐│
 uart_clk ─────────┼────────┤                   ↓         ││
                   │        │          ┌─────────────┐    ││
                   │        │          │ uart_tx     │────┼┼→ uart_tx
                   │        │          │   _path     │    ││
                   │        │          └─────────────┘    ││
                   │        │                             ││
 uart_rx ──────────┼────────┤          ┌─────────────┐    ││
  (async)          │        │          │ uart_rx     │    ││
                   │        │          │   _path     │    ││
                   │        │          └─────────────┘    ││
                   │        └───────────────────────────────┘│
                   │         All UART logic in uart_clk     │
                   │                                        │
 irq ←─────────────┼────────────────────────────────────────┤
                   └────────────────────────────────────────┘
```

### Clock Domain Strategy

**Initial Implementation (Simplified):**
- All UART logic runs in `uart_clk` domain
- AXI-Lite interface runs in `clk` domain
- Use `sync_fifo` (single clock domain) - all FIFO operations in `uart_clk`
- Register file runs in `uart_clk` domain
- AXI slave interface crosses from `clk` → `uart_clk` via CDC

**Rationale:**
- Avoid async_fifo complexity in initial implementation
- Single clock domain for datapath simplifies debugging
- Can add async_fifo later as enhancement

### CDC Boundaries

1. **RX Input:** `uart_rx` (async) → `uart_clk` via bit_sync
2. **AXI → UART:** If needed, synchronize control signals

### Module Instantiation Hierarchy
```
uart_top
├── axi_lite_slave_if
├── uart_regs
├── baud_gen
├── uart_tx_path
│   ├── sync_fifo (TX)
│   └── uart_tx
└── uart_rx_path
    ├── bit_sync (RX input)
    ├── uart_rx
    └── sync_fifo (RX)
```

### Integration Checklist
- [ ] All modules instantiated with correct parameters
- [ ] All clocks connected to correct domains
- [ ] All resets synchronized to respective clock domains
- [ ] CDC paths identified and properly synchronized
- [ ] uart_rx input goes through bit_sync before uart_rx core
- [ ] baud_tick distributed to uart_tx and uart_rx
- [ ] Status flags routed from paths to registers
- [ ] Interrupt logic implemented based on INT_ENABLE and INT_STATUS

---

## Phase 0 Exit Criteria

Before proceeding to implementation, verify:

- [ ] All 10 module interfaces documented above
- [ ] Clock domains clearly defined (uart_clk, clk)
- [ ] CDC boundaries identified (3 boundaries)
- [ ] Signal tables complete for all modules
- [ ] Timing characteristics specified
- [ ] Protocol rules documented (ready/valid, FIFO, AXI-Lite)
- [ ] Critical implementation notes captured (prefetch, duplicate writes)
- [ ] Design review completed with team/stakeholder sign-off

**Git Tag:** `design_review_approved`

---

## References

- `UART_Implementation_Plan.md` - Implementation phases and schedule
- `DEVELOPMENT_GUIDELINES.md` - Process requirements and quality gates
- AXI-Lite Specification - ARM IHI0022E
- UART 8N1 Standard - Industry standard asynchronous serial

---

## Revision History

| Version | Date       | Author | Changes |
|---------|------------|--------|---------|
| 1.0     | 2025-11-26 | Claude | Initial interface specifications for clean restart |
