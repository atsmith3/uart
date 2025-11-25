# AXI-Lite UART Peripheral Implementation Plan

## Project Overview

A bidirectional UART peripheral soft IP with AXI-Lite interface for integration into system bus/NoC architectures. Features register-based control, configurable baud rates, and comprehensive verification with Verilator.

**IMPORTANT:** This implementation plan follows strict development guidelines to ensure quality and maintainability. See `DEVELOPMENT_GUIDELINES.md` for detailed process requirements.

### Architecture Summary

- **Protocol:** UART 8N1 (8 data bits, no parity, 1 stop bit)
- **Baud Rates:** 9600, 19200, 38400, 57600, 115200, 230400, 460800 bps (all with 16× oversampling)
- **Bus Interface:** AXI-Lite (simplified AXI4 for register access)
- **Clock Architecture:**
  - External 7.3728 MHz UART clock (4× standard UART frequency, 16× oversampling at 460800 baud)
  - Internal system clock ~1 MHz range for AXI-Lite interface
  - Synchronizers for clock domain crossing between domains
- **HDL:** SystemVerilog
- **Verification:** Verilator + C++/Boost.Test framework

### Key Features

- Full-duplex operation (simultaneous TX and RX)
- Programmable baud rate selection
- FIFO buffers for TX and RX (4-8 entries)
- Status flags: TX empty, TX full, RX empty, RX full, frame error, overrun error
- Interrupt support: TX ready, RX ready, error conditions

### Key Parameters

- `DATA_WIDTH` - AXI data width (default: 32)
- `ADDR_WIDTH` - AXI address width (default: 32)
- `TX_FIFO_DEPTH` - Transmit FIFO depth (default: 8)
- `RX_FIFO_DEPTH` - Receive FIFO depth (default: 8)
- `BAUD_DIVISOR_WIDTH` - Width of baud rate divisor (default: 8)
- `UART_CLK_FREQ` - UART clock frequency in Hz (default: 7372800)

---

## Development Process Overview

### Five Golden Rules

1. **Test Before You Integrate** - Every module must pass standalone tests before integration
2. **One Change at a Time** - Make orthogonal changes in separate commits
3. **Know Your Baseline** - Always maintain known-good states with git tags
4. **Validate Don't Patch** - Tests validate requirements, not implementation
5. **Test Your Tests** - Clock generators and test infrastructure must be validated

### Phase Gates (MANDATORY)

Each phase has **entrance criteria** (what must be complete before starting) and **exit criteria** (what must pass before proceeding). Cannot skip phases or bypass gates.

**Gate enforcement:**
- Module validation: All module tests must pass before integration
- Integration validation: Integration tests + all previous tests must pass
- No architectural changes without design review
- All changes tracked with git tags for rollback

### Git Tagging Strategy

Required tags at each milestone:
```bash
# Design phase
git tag -a design_review_approved -m "Interface specifications approved"

# Module development
git tag -a <module>_validated -m "<Module> tests passing"

# Integration
git tag -a <subsystem>_integration_pass -m "<Subsystem> integrated and validated"

# System validation
git tag -a system_validated -m "Full system tests passing"
```

### Test-First Development

**Process for each module:**
1. Write interface specification (signals, timing, protocol)
2. Write failing test cases
3. Implement module to pass tests
4. Validate and tag as `<module>_validated`
5. Only then proceed to integration

---

## Phase 0: Design Review (MANDATORY GATE)

### Entrance Criteria
- Project requirements documented
- Block diagram complete
- Interface specifications drafted

### Activities
1. **Define all module interfaces** (see DEVELOPMENT_GUIDELINES.md)
   - Signal tables with clock domains
   - Timing diagrams for complex handshakes
   - Protocol descriptions (ready/valid, FIFO, etc.)
   - CDC boundaries identified

2. **Document clock architecture**
   - UART clock domain (7.3728 MHz)
   - System clock domain (~1 MHz)
   - CDC synchronization strategy

3. **Review and approve design**
   - Design review meeting
   - Interface specifications approved
   - Risk assessment complete

### Exit Criteria
- [ ] All module interfaces fully documented
- [ ] Clock domains and CDC boundaries identified
- [ ] Timing requirements documented
- [ ] Design review sign-off obtained
- [ ] **Git tag:** `design_review_approved`

### Deliverables
- Interface specification document
- Block diagram
- CDC analysis
- This implementation plan

---

## Phase 1: Clock Domain Crossing and FIFO Primitives

**Entrance Criteria:**
- [ ] Design review complete (tag: `design_review_approved`)
- [ ] Test infrastructure plan approved
- [ ] Development environment setup

### Step 1.1: Bit Synchronizer (`rtl/bit_sync.sv`)

**Development Process:**
1. Write interface specification
2. Create `tests/module/bit_sync_test.cpp` with test cases
3. Implement `rtl/bit_sync.sv`
4. Run tests until passing
5. Tag: `bit_sync_validated`

**Purpose:** Safely synchronize single-bit signals across clock domains.

**Implementation Details:**
- **Inputs:**
  - `clk_dst` - Destination clock domain
  - `rst_n_dst` - Destination domain reset (active low)
  - `data_in` - Single-bit input from source domain

- **Outputs:**
  - `data_out` - Synchronized output in destination domain

**Key Features:**
- 2-stage or 3-stage synchronizer flip-flops (parameterizable)
- MTBF protection for metastability
- Parameterizable number of stages (default: 2)

**Design Notes:**
- Use `always_ff` for all sequential logic
- Add synthesis attributes for CDC paths: `(* ASYNC_REG = "TRUE" *)`
- No feedback from destination to source domain

**Test Requirements:**
- Verify synchronization with different clock frequencies
- Test pulse stretching if needed
- Check reset behavior

---

### Step 1.2: Synchronous FIFO (`rtl/sync_fifo.sv`)

**Development Process:**
1. Write interface specification (see Interface Definition Requirements in DEVELOPMENT_GUIDELINES.md)
2. Create `tests/module/sync_fifo_test.cpp` - comprehensive corner case testing
3. Implement `rtl/sync_fifo.sv`
4. Run tests until passing (100% pass rate required)
5. Tag: `sync_fifo_validated`

**Purpose:** Buffer data within a single clock domain with read/write pointers.

**Implementation Details:**

**Parameters:**
- `DATA_WIDTH` - Width of data bus (default: 8)
- `DEPTH` - FIFO depth, must be power of 2 (default: 8)
- `ADDR_WIDTH` - log2(DEPTH)

**Interfaces:**

*Single Clock Domain:*
- `clk` - Clock
- `rst_n` - Reset (active low)
- `wr_en` - Write enable
- `wr_data[DATA_WIDTH-1:0]` - Write data
- `rd_en` - Read enable
- `rd_data[DATA_WIDTH-1:0]` - Read data (output)
- `full` - Full flag (output)
- `empty` - Empty flag (output)
- `level[ADDR_WIDTH:0]` - Current fill level (output)

**Architecture:**
1. **Single-port or Dual-port RAM:** For data storage
2. **Write Pointer:** Binary counter, increments on write
3. **Read Pointer:** Binary counter, increments on read
4. **Flag Generation:**
   - Full: `(wr_ptr + 1 == rd_ptr)` in wrapped space
   - Empty: `(wr_ptr == rd_ptr)`
   - Level: `(wr_ptr - rd_ptr)` modulo DEPTH

**Design Notes:**
- Use simple binary counters (no Gray code needed for single clock domain)
- Separate read/write enables for simultaneous operation
- Output data registered for timing
- Optional almost_full and almost_empty flags

**Test Requirements:**
- Write-then-read sequences
- Simultaneous read/write operations
- Full and empty boundary conditions
- FIFO overflow/underflow prevention
- Random write/read patterns

---

### Phase 1 Exit Criteria (GATE)

**Exit Criteria:**
- [ ] bit_sync module tests 100% passing
- [ ] sync_fifo module tests 100% passing
- [ ] Code review complete for both modules
- [ ] No lint warnings
- [ ] Git tags created: `bit_sync_validated`, `sync_fifo_validated`
- [ ] **Phase tag:** `phase1_primitives_complete`

**Checkpoint:** Do NOT proceed to Phase 2 until all exit criteria met. These primitives are foundational - errors here cascade through entire design.

---

## Phase 2: UART Transmitter

**Entrance Criteria:**
- [ ] Phase 1 complete (tag: `phase1_primitives_complete`)
- [ ] Test infrastructure for UART protocol validation ready

### Step 2.1: Baud Rate Generator (`rtl/uart_baud_gen.sv`)

**Development Process:**
1. Write interface specification
2. Create `tests/module/baud_gen_test.cpp` with frequency validation tests
3. **IMPORTANT:** Validate test infrastructure (clock measurement accuracy) before testing DUT
4. Implement `rtl/uart_baud_gen.sv`
5. Run tests until passing
6. Tag: `baud_gen_validated`

**Purpose:** Generate baud rate clock enable from system clock.

**Implementation Details:**

**Parameters:**
- `DIVISOR_WIDTH` - Width of divisor register (default: 8, sufficient for divisors 1-255)
- `UART_CLK_FREQ` - UART clock frequency in Hz (default: 7372800 for 7.3728 MHz)

**Interfaces:**
- `uart_clk` - UART clock (7.3728 MHz)
- `rst_n` - Reset (active low)
- `baud_divisor[DIVISOR_WIDTH-1:0]` - Baud rate divisor value (1-255)
- `enable` - Enable signal (input)
- `baud_tick` - Baud rate tick output (one cycle pulse, 16× baud rate)

**Baud Rate Calculation:**
```
baud_divisor = UART_CLK_FREQ / (BAUD_RATE × 16)  // For 16× oversampling

Example (7.3728 MHz UART clock, 460800 baud):
baud_divisor = 7372800 / (460800 × 16) = 7372800 / 7372800 = 1

Example (7.3728 MHz UART clock, 115200 baud):
baud_divisor = 7372800 / (115200 × 16) = 7372800 / 1843200 = 4

Example (7.3728 MHz UART clock, 9600 baud):
baud_divisor = 7372800 / (9600 × 16) = 7372800 / 153600 = 48
```

**Architecture:**
- Simple counter-based divider
- Counter decrements from divisor value to 1
- Generate tick pulse when counter reaches 1
- Reload counter with divisor value after tick

**Design Notes:**
- 7.3728 MHz = 4× the standard 1.8432 MHz UART clock frequency
- Provides exact integer divisors for all standard baud rates including 460800
- No fractional divider needed - all baud rates have perfect divisors
- Clean 16× oversampling for all rates provides excellent noise immunity

**Baud Rate Table (7.3728 MHz UART clock, 16× oversampling):**
| Baud Rate | Oversampling | Required Tick Freq | Divisor | Error   |
|-----------|--------------|-------------------|---------|---------|
| 2400      | 16×          | 38400 Hz          | 192     | 0%      |
| 4800      | 16×          | 76800 Hz          | 96      | 0%      |
| 9600      | 16×          | 153600 Hz         | 48      | 0%      |
| 14400     | 16×          | 230400 Hz         | 32      | 0%      |
| 19200     | 16×          | 307200 Hz         | 24      | 0%      |
| 28800     | 16×          | 460800 Hz         | 16      | 0%      |
| 38400     | 16×          | 614400 Hz         | 12      | 0%      |
| 57600     | 16×          | 921600 Hz         | 8       | 0%      |
| 115200    | 16×          | 1843200 Hz        | 4       | 0%      |
| 230400    | 16×          | 3686400 Hz        | 2       | 0%      |
| 460800    | 16×          | 7372800 Hz        | 1       | 0%      |

**Note:** All standard baud rates up to 460800 have full 16× oversampling with perfect integer divisors

**Test Requirements:**
- Verify tick generation at various divisor values
- Check frequency accuracy
- Test enable/disable functionality

---

### Step 2.2: UART Transmitter Core (`rtl/uart_tx.sv`)

**Development Process:**
1. Write interface specification with timing diagrams
2. Create `tests/module/uart_tx_test.cpp` - test frame format (start, data LSB-first, stop)
3. Implement `rtl/uart_tx.sv`
4. Run tests until passing (verify correct bit timing!)
5. Tag: `uart_tx_validated`

**Purpose:** Serialize and transmit data over UART TX line.

**Implementation Details:**

**Parameters:**
- `DATA_WIDTH` - Data width (default: 8)

**Interfaces:**
- `clk` - System clock
- `rst_n` - Reset (active low)
- `baud_tick` - Baud rate tick from generator
- `tx_data[DATA_WIDTH-1:0]` - Data to transmit
- `tx_valid` - Data valid signal
- `tx_ready` - Ready to accept data (output)
- `tx_serial` - Serial output line (output)
- `tx_active` - Transmission in progress (output)

**UART Frame Format (8N1):**
```
Idle: HIGH
Start bit: LOW (1 bit)
Data bits: LSB first (8 bits)
Stop bit: HIGH (1 bit)
Total: 10 bits per frame
```

**Architecture:**

*TX State Machine:*
```
IDLE: Wait for tx_valid
  → Assert tx_ready
  → When tx_valid asserted: latch data, go to START
START: Transmit start bit (LOW)
  → Wait for baud_tick
  → Go to DATA
DATA: Transmit data bits LSB first
  → Wait for baud_tick for each bit
  → Shift out 8 bits
  → Go to STOP
STOP: Transmit stop bit (HIGH)
  → Wait for baud_tick
  → Go to IDLE
```

**Design Notes:**
- Default line state is HIGH (idle)
- Data is latched when tx_valid && tx_ready
- Shift register for serialization
- Bit counter for tracking position (0-9)
- tx_ready deasserted during transmission
- tx_active indicates transmission in progress

**Test Requirements:**
- Verify correct frame format (start, data, stop)
- Test with various data patterns (0x00, 0xFF, 0x55, 0xAA)
- Verify timing with baud_tick
- Test back-to-back transmissions
- Check idle line state

---

### Step 2.3: UART TX Path Integration (`rtl/uart_tx_path.sv`)

**Development Process - INTEGRATION:**
1. **Prerequisites:** `sync_fifo_validated`, `uart_tx_validated`, `baud_gen_validated` tags must exist
2. Create integration test: `tests/integration/uart_tx_path_test.cpp`
3. Integrate ONLY sync_fifo + uart_tx (one component at a time)
4. Implement `rtl/uart_tx_path.sv`
5. Run integration tests + regression (all module tests must still pass)
6. Tag: `uart_tx_path_integrated`

**IMPORTANT:** This is first integration point. If issues arise, can rollback to individual module tags.

**Purpose:** Integrate TX FIFO with transmitter for buffered transmission.

**Implementation Details:**

**Parameters:**
- `FIFO_DEPTH` - TX FIFO depth (default: 8)

**Interfaces:**
- `clk` - System clock
- `rst_n` - Reset
- `baud_tick` - Baud rate tick
- `wr_data[7:0]` - Data to write to FIFO
- `wr_en` - Write enable from AXI interface
- `tx_serial` - Serial output
- `tx_empty` - TX FIFO empty flag
- `tx_full` - TX FIFO full flag
- `tx_active` - Transmission active

**Architecture:**
```
AXI Write → TX FIFO → UART TX Core → tx_serial
                ↓
         Status flags (empty, full, active)
```

**Design Notes:**
- FIFO provides buffering for CPU
- TX core reads from FIFO when ready
- Status flags for software polling or interrupts
- Automatic transmission when FIFO not empty

**Test Requirements:**
- Single byte transmission
- Multiple byte burst
- FIFO full handling
- Continuous transmission

---

### Phase 2 Exit Criteria (GATE)

**Exit Criteria:**
- [ ] baud_gen module tests 100% passing (tag: `baud_gen_validated`)
- [ ] uart_tx module tests 100% passing (tag: `uart_tx_validated`)
- [ ] uart_tx_path integration tests passing (tag: `uart_tx_path_integrated`)
- [ ] All Phase 1 tests still passing (regression check)
- [ ] Code review complete
- [ ] No lint warnings
- [ ] **Phase tag:** `phase2_tx_complete`

**Checkpoint:** TX path must be fully validated before starting RX. RX is more complex (oversampling, error detection) - don't carry TX issues forward.

---

## Phase 3: UART Receiver

**Entrance Criteria:**
- [ ] Phase 2 complete (tag: `phase2_tx_complete`)
- [ ] Understand timing requirements for 16× oversampling

### Step 3.1: UART Receiver Core (`rtl/uart_rx.sv`)

**Development Process:**
1. Write interface specification with detailed timing analysis
2. **Draw timing diagrams** for start bit detection and data sampling
3. Create `tests/module/uart_rx_test.cpp` - test frame reception and error detection
4. Implement `rtl/uart_rx.sv`
5. **CRITICAL:** Verify sample counter initialization and bit-center sampling
6. Run tests until passing
7. Tag: `uart_rx_validated`

**NOTE:** RX is more complex than TX (oversampling, error detection). Take time to get timing right.

**Purpose:** Deserialize and receive data from UART RX line with error detection.

**Implementation Details:**

**Parameters:**
- `DATA_WIDTH` - Data width (default: 8)
- `OVERSAMPLE_RATE` - Oversampling rate (default: 16)

**Interfaces:**
- `clk` - System clock
- `rst_n` - Reset
- `sample_tick` - Oversampling tick (16× baud rate)
- `rx_serial` - Serial input line
- `rx_data[DATA_WIDTH-1:0]` - Received data (output)
- `rx_valid` - Data valid output
- `rx_ready` - Ready to accept read (input)
- `frame_error` - Frame error flag (output)
- `rx_active` - Reception in progress (output)

**Architecture:**

*RX State Machine:*
```
IDLE: Wait for start bit (falling edge on rx_serial)
  → Monitor rx_serial for HIGH → LOW transition
  → Go to START_BIT
START_BIT: Validate start bit
  → Sample at middle of bit period (8× sample_tick)
  → If LOW: Go to DATA_BITS
  → If HIGH: False start, go to IDLE (frame error)
DATA_BITS: Receive 8 data bits LSB first
  → Sample each bit at middle of period
  → Shift into receive register
  → After 8 bits: Go to STOP_BIT
STOP_BIT: Validate stop bit
  → Sample at middle of period
  → If HIGH: Valid frame, assert rx_valid, go to IDLE
  → If LOW: Frame error, go to IDLE
```

**Sampling Strategy:**
- 16× oversampling for noise immunity
- Sample at 8th tick of 16-tick period (middle of bit)
- Majority voting optional for extra noise rejection (3-5 samples)

**Design Notes:**
- Default line state is HIGH
- Start bit detection on falling edge
- Frame error if stop bit not HIGH
- Overrun error if rx_valid not cleared before next frame
- Synchronize rx_serial input with bit_sync

**Test Requirements:**
- Verify correct frame reception
- Test with various data patterns
- Frame error detection (invalid stop bit)
- Overrun error detection
- Noise tolerance with oversampling
- Back-to-back receptions

---

### Step 3.2: UART RX Path Integration (`rtl/uart_rx_path.sv`)

**Development Process - INTEGRATION:**
1. **Prerequisites:** `bit_sync_validated`, `sync_fifo_validated`, `uart_rx_validated` tags must exist
2. Create integration test: `tests/integration/uart_rx_path_test.cpp`
3. Integrate bit_sync → uart_rx → sync_fifo
4. Implement `rtl/uart_rx_path.sv`
5. **CRITICAL:** Handle rx_valid handshaking carefully to avoid duplicate FIFO writes
6. Run integration tests + regression
7. Tag: `uart_rx_path_integrated`

**IMPORTANT:** RX has handshaking complexity. Test single-byte and multi-byte reception thoroughly.

**Purpose:** Integrate RX core with FIFO for buffered reception.

**Implementation Details:**

**Parameters:**
- `FIFO_DEPTH` - RX FIFO depth (default: 8)

**Interfaces:**
- `clk` - System clock
- `rst_n` - Reset
- `sample_tick` - Oversampling tick
- `rx_serial` - Serial input
- `rd_data[7:0]` - Data read from FIFO
- `rd_en` - Read enable from AXI interface
- `rx_empty` - RX FIFO empty flag
- `rx_full` - RX FIFO full flag
- `rx_active` - Reception active
- `frame_error` - Frame error flag
- `overrun_error` - Overrun error flag

**Architecture:**
```
rx_serial → UART RX Core → RX FIFO → AXI Read
                ↓
       Status flags (empty, full, errors)
```

**Design Notes:**
- FIFO buffers received data
- Overrun error if FIFO full and new data arrives
- Error flags sticky (cleared by software)
- Separate error FIFO optional for tracking errors per byte

**Test Requirements:**
- Single byte reception
- Multiple byte reception
- FIFO full handling (overrun)
- Error flag verification
- Continuous reception

---

### Phase 3 Exit Criteria (GATE)

**Exit Criteria:**
- [ ] uart_rx module tests 100% passing (tag: `uart_rx_validated`)
- [ ] uart_rx_path integration tests passing (tag: `uart_rx_path_integrated`)
- [ ] All Phase 1 & 2 tests still passing (regression check)
- [ ] Code review complete
- [ ] No lint warnings
- [ ] **Phase tag:** `phase3_rx_complete`

**Checkpoint:** Both TX and RX paths validated independently. Ready for register interface integration.

---

## Phase 4: AXI-Lite Register Interface

**Entrance Criteria:**
- [ ] Phase 3 complete (tag: `phase3_rx_complete`)
- [ ] AXI-Lite protocol understood
- [ ] Register map designed

### Step 4.1: AXI-Lite Slave Interface (`rtl/axi_lite_slave_if.sv`)

**Development Process:**
1. Write interface specification for AXI-Lite protocol
2. Create `tests/module/axi_slave_if_test.cpp` - test all AXI transactions
3. Implement `rtl/axi_lite_slave_if.sv`
4. Test write/read transactions, backpressure, invalid addresses
5. Tag: `axi_slave_if_validated`

**Purpose:** Implement AXI-Lite slave protocol for register access.

**Implementation Details:**

**Parameters:**
- `DATA_WIDTH` - AXI data width (default: 32)
- `ADDR_WIDTH` - AXI address width (default: 32)
- `REG_ADDR_WIDTH` - Internal register address width (default: 4)

**Interfaces:**

*AXI-Lite Slave:*
- Standard 5-channel AXI-Lite interface
  - Write Address Channel (AW)
  - Write Data Channel (W)
  - Write Response Channel (B)
  - Read Address Channel (AR)
  - Read Data Channel (R)

*Register Interface:*
- `reg_addr[REG_ADDR_WIDTH-1:0]` - Register address
- `reg_wdata[DATA_WIDTH-1:0]` - Write data
- `reg_wen` - Write enable
- `reg_ren` - Read enable
- `reg_rdata[DATA_WIDTH-1:0]` - Read data
- `reg_error` - Register access error

**Architecture:**

*Write Path State Machine:*
```
IDLE: Wait for awvalid and wvalid
  → Both can arrive in any order
  → When both present: decode address, write data
  → Assert bvalid with response
  → Go to WAIT_BREADY
WAIT_BREADY: Wait for bready
  → When bready: deassert bvalid
  → Go to IDLE
```

*Read Path State Machine:*
```
IDLE: Wait for arvalid
  → Decode address
  → Assert reg_ren
  → Go to READ_DATA
READ_DATA: Wait for reg_rdata
  → Assert rvalid with data and response
  → Go to WAIT_RREADY
WAIT_RREADY: Wait for rready
  → When rready: deassert rvalid
  → Go to IDLE
```

**Design Notes:**
- Write and read paths are independent
- OKAY response for valid accesses
- SLVERR response for invalid addresses
- Single-cycle register access (no wait states)
- Byte enables (wstrb) supported for partial writes

**Test Requirements:**
- Single write transaction
- Single read transaction
- Back-to-back writes
- Back-to-back reads
- Interleaved read/write
- Invalid address handling
- Byte enable testing

---

### Step 4.2: UART Register File (`rtl/uart_regs.sv`)

**Development Process:**
1. Document complete register map (see below)
2. Create `tests/module/uart_regs_test.cpp` - test all register operations
3. Implement `rtl/uart_regs.sv`
4. Test read/write, W1C behavior, FIFO side effects, reserved bits
5. **CRITICAL:** If using async FIFOs, implement prefetch logic correctly
6. Tag: `uart_regs_validated`

**Purpose:** Define and implement UART control/status registers.

**Implementation Details:**

**Memory Map (byte-addressed, 32-bit aligned):**

```
Offset  | Register      | Access | Description
--------|---------------|--------|-------------
0x00    | CTRL          | RW     | Control register
0x04    | STATUS        | RO     | Status register
0x08    | TX_DATA       | WO     | Transmit data (write to FIFO)
0x0C    | RX_DATA       | RO     | Receive data (read from FIFO)
0x10    | BAUD_DIV      | RW     | Baud rate divisor
0x14    | INT_ENABLE    | RW     | Interrupt enable
0x18    | INT_STATUS    | RW1C   | Interrupt status (write 1 to clear)
0x1C    | FIFO_CTRL     | RW     | FIFO control (reset, thresholds)
```

**Register Definitions:**

**CTRL (0x00) - Control Register:**
```
Bit  | Field         | Description
-----|---------------|-------------
0    | TX_EN         | Transmit enable (1=enable, 0=disable)
1    | RX_EN         | Receive enable (1=enable, 0=disable)
7:2  | Reserved      | Write 0, read as 0
```

**STATUS (0x04) - Status Register (Read-Only):**
```
Bit  | Field         | Description
-----|---------------|-------------
0    | TX_EMPTY      | TX FIFO empty
1    | TX_FULL       | TX FIFO full
2    | RX_EMPTY      | RX FIFO empty
3    | RX_FULL       | RX FIFO full
4    | TX_ACTIVE     | Transmission in progress
5    | RX_ACTIVE     | Reception in progress
6    | FRAME_ERROR   | Frame error detected (sticky)
7    | OVERRUN_ERROR | Overrun error detected (sticky)
15:8 | TX_LEVEL      | TX FIFO fill level
23:16| RX_LEVEL      | RX FIFO fill level
31:24| Reserved      | Always 0
```

**TX_DATA (0x08) - Transmit Data Register (Write-Only):**
```
Bit  | Field         | Description
-----|---------------|-------------
7:0  | TX_DATA       | Data to transmit (written to TX FIFO)
31:8 | Reserved      | Ignored
```

**RX_DATA (0x0C) - Receive Data Register (Read-Only):**
```
Bit  | Field         | Description
-----|---------------|-------------
7:0  | RX_DATA       | Received data (read from RX FIFO)
31:8 | Reserved      | Always 0
```

**BAUD_DIV (0x10) - Baud Rate Divisor:**
```
Bit  | Field         | Description
-----|---------------|-------------
15:0 | DIVISOR       | Baud rate divisor value
31:16| Reserved      | Write 0, read as 0
```

**INT_ENABLE (0x14) - Interrupt Enable:**
```
Bit  | Field         | Description
-----|---------------|-------------
0    | TX_READY_IE   | TX ready interrupt enable
1    | RX_READY_IE   | RX ready interrupt enable
2    | FRAME_ERR_IE  | Frame error interrupt enable
3    | OVERRUN_IE    | Overrun error interrupt enable
31:4 | Reserved      | Write 0, read as 0
```

**INT_STATUS (0x18) - Interrupt Status (Write 1 to Clear):**
```
Bit  | Field         | Description
-----|---------------|-------------
0    | TX_READY_IS   | TX ready interrupt status
1    | RX_READY_IS   | RX ready interrupt status
2    | FRAME_ERR_IS  | Frame error interrupt status
3    | OVERRUN_IS    | Overrun error interrupt status
31:4 | Reserved      | Write 0, read as 0
```

**FIFO_CTRL (0x1C) - FIFO Control:**
```
Bit  | Field         | Description
-----|---------------|-------------
0    | TX_FIFO_RST   | TX FIFO reset (self-clearing)
1    | RX_FIFO_RST   | RX FIFO reset (self-clearing)
7:2  | Reserved      | Write 0, read as 0
```

**Architecture:**
- Register write logic updates control registers
- Register read logic multiplexes status/data registers
- Error flags are sticky (remain set until software clears)
- Write 1 to clear (W1C) for interrupt status
- FIFO reset bits self-clear after one cycle

**Design Notes:**
- All registers 32-bit aligned
- Reserved bits read as 0, writes ignored
- Error flags in STATUS are read-only, cleared via INT_STATUS W1C
- FIFO read/write side effects (pop/push data)
- Atomic read-modify-write not required (simple registers)

**Test Requirements:**
- Read/write all registers
- Verify status flag updates
- Test FIFO read/write side effects
- Verify W1C behavior for interrupt status
- Check reserved bit handling

---

### Phase 4 Exit Criteria (GATE)

**Exit Criteria:**
- [ ] axi_slave_if module tests 100% passing (tag: `axi_slave_if_validated`)
- [ ] uart_regs module tests 100% passing (tag: `uart_regs_validated`)
- [ ] All previous phase tests still passing (regression check)
- [ ] Code review complete
- [ ] No lint warnings
- [ ] **Phase tag:** `phase4_registers_complete`

**Checkpoint:** Register interface validated. Ready for top-level integration.

---

## Phase 5: Top-Level Integration

**Entrance Criteria:**
- [ ] Phase 4 complete (tag: `phase4_registers_complete`)
- [ ] All module tags exist and validated
- [ ] CDC strategy documented

### Step 5.1: UART Top Module (`rtl/uart_top.sv`)

**Development Process - TOP-LEVEL INTEGRATION:**
1. **Prerequisites:** All Phase 1-4 module tags must exist
2. Create system tests: `tests/uart_loopback_tests.cpp`
3. **Validate test infrastructure first:** Clock generators, timing accuracy
4. Integrate all components into `rtl/uart_top.sv`
5. **CRITICAL CDC checkpoint:** Verify all clock domain crossings safe
6. Run system tests (loopback at multiple baud rates)
7. Run full regression (all module + integration tests)
8. Tag: `uart_top_integrated`

**IMPORTANT:** This is the big integration. Take time, test thoroughly. If issues arise, have clear rollback path.

**Purpose:** Integrate all UART components with AXI-Lite interface.

**Implementation Details:**

**Parameters:**
- `DATA_WIDTH` - AXI data width (default: 32)
- `ADDR_WIDTH` - AXI address width (default: 32)
- `TX_FIFO_DEPTH` - TX FIFO depth (default: 8)
- `RX_FIFO_DEPTH` - RX FIFO depth (default: 8)
- `UART_CLK_FREQ` - UART clock frequency in Hz (default: 7372800)
- `SYS_CLK_FREQ` - System clock frequency in Hz (default: 1000000)

**Interfaces:**

*System:*
- `clk` - System clock (~1 MHz) for AXI-Lite interface
- `rst_n` - Active low reset
- `uart_clk` - UART clock (7.3728 MHz) for baud rate generation and sampling

*AXI-Lite Slave:*
- Standard AXI-Lite slave interface

*UART:*
- `uart_tx` - UART transmit line
- `uart_rx` - UART receive line

*Interrupts:*
- `irq` - Interrupt request output

**Architecture:**

```
┌─────────────────────────────────────────────────────────────┐
│                        UART Top                              │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │  AXI-Lite    │    │  Register    │    │   Baud Rate  │  │
│  │  Slave IF    │───→│    File      │───→│   Generator  │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│         │                    │                    │         │
│         │                    ↓                    ↓         │
│         │            ┌──────────────┐    ┌──────────────┐  │
│         │            │  TX FIFO +   │    │  RX FIFO +   │  │
│         │            │  TX Core     │    │  RX Core     │  │
│         │            └──────────────┘    └──────────────┘  │
│         │                    │                    │         │
│         └────────────────────┴────────────────────┘         │
│                              │                    │         │
│                              ↓                    ↓         │
│                          uart_tx              uart_rx       │
└─────────────────────────────────────────────────────────────┘
```

**Clock Domain Crossing:**
- `uart_rx` input synchronized with `bit_sync` to UART clock domain first, then to system clock domain if needed
- `uart_clk` domain: Baud generator, TX core, RX core (all UART logic)
- `clk` domain: AXI-Lite interface, register file
- CDC between UART clock domain and system clock domain at FIFO interfaces

**Design Notes:**
- Single module instantiates all submodules
- Clean hierarchy for verification
- Interrupt generation based on INT_ENABLE and INT_STATUS
- All control through AXI-Lite registers

**Test Requirements:**
- AXI register access through top-level
- End-to-end TX operation
- End-to-end RX operation
- Loopback test (TX → RX)
- Interrupt generation

---

### Phase 5 Exit Criteria (GATE)

**Exit Criteria:**
- [ ] uart_top integration complete (tag: `uart_top_integrated`)
- [ ] Loopback tests passing at all supported baud rates
- [ ] End-to-end TX/RX tests passing
- [ ] Full regression passing (all module + integration tests)
- [ ] CDC verification complete
- [ ] Code review complete
- [ ] No lint warnings
- [ ] **Phase tag:** `phase5_system_integrated`

**Checkpoint:** System integration complete. Ready for comprehensive verification.

---

## Phase 6: Verification and Validation

**Entrance Criteria:**
- [ ] Phase 5 complete (tag: `phase5_system_integrated`)
- [ ] Test infrastructure validated

### Step 6.1: C++ Test Infrastructure

**Files to Create:**

1. **`simulation/uart_bfm.h/cpp`** - UART Bus Functional Model
   - Methods: `send_byte(data)`, `receive_byte(&data)`, `send_frame(data)`, `check_frame_format()`
   - Bit-level UART transmission/reception
   - Configurable baud rate timing
   - Error injection (frame errors, noise)
   - Bit timing verification

2. **`simulation/axi_master_bfm.h/cpp`** - AXI-Lite Master BFM (reuse from NoC or create simple version)
   - Methods: `write32(addr, data)`, `read32(addr, &data)`
   - AXI-Lite handshaking
   - Configurable response delays

3. **`simulation/test_runner.h/cpp`** - UART Test Runner
   - Instantiate DUT (Verilated UART)
   - Manage clock generation (system clock and baud clock)
   - AXI and UART BFMs
   - Result checking and reporting
   - VCD trace management

4. **`simulation/test_utils.h/cpp`** - Test Utilities
   - Random data generation
   - CRC/checksum calculations
   - Timing calculations
   - UART frame formatting helpers

---

### Step 6.2: Module-Level Tests

**Directory: `simulation/tests/module/`**

1. **`bit_sync_test.cpp`**
   - Test single-bit synchronization
   - Verify with different clock frequencies
   - Check metastability protection (multi-stage FF)

2. **`sync_fifo_test.cpp`**
   - Basic write-then-read
   - Full and empty conditions
   - Simultaneous read/write
   - Random access patterns
   - Data integrity verification

3. **`baud_gen_test.cpp`**
   - Verify tick generation at various divisor values
   - Measure output frequency
   - Test enable/disable
   - Check for jitter

4. **`uart_tx_test.cpp`**
   - Single byte transmission
   - Verify frame format (start, data LSB-first, stop)
   - Test various data patterns (0x00, 0xFF, 0x55, 0xAA)
   - Back-to-back transmissions
   - Check idle state

5. **`uart_rx_test.cpp`**
   - Single byte reception
   - Verify correct data sampling
   - Frame error detection
   - Oversampling verification
   - Back-to-back receptions

6. **`axi_slave_if_test.cpp`**
   - Single write transaction
   - Single read transaction
   - Back-to-back accesses
   - Invalid address handling
   - Byte enable testing

7. **`uart_regs_test.cpp`**
   - Read/write all registers
   - Verify status flag updates
   - Test FIFO side effects
   - W1C behavior for interrupt status
   - Reserved bit handling

---

### Step 6.3: System-Level Tests

**Directory: `simulation/tests/`**

1. **`uart_system_tests.cpp`**

   Test Cases:
   - **Register Access:** Read/write all registers via AXI
   - **TX Basic:** Write byte to TX_DATA, verify transmission on uart_tx
   - **RX Basic:** Receive byte on uart_rx, read from RX_DATA
   - **TX FIFO:** Fill TX FIFO, verify sequential transmission
   - **RX FIFO:** Receive multiple bytes, read all from FIFO
   - **Loopback:** Connect TX to RX, verify data integrity
   - **Baud Rate:** Test multiple baud rates (9600, 115200, etc.)
   - **Error Detection:** Generate frame errors, verify status flags
   - **FIFO Overflow:** Test TX FIFO full and RX FIFO overrun
   - **Interrupts:** Verify interrupt generation on TX ready, RX ready, errors

2. **`uart_loopback_tests.cpp`** - Comprehensive Loopback Tests

   Test Cases:
   - **Simple Loopback:** Single byte TX → RX
   - **Bulk Transfer:** 256 bytes with verification
   - **Random Data:** Random data patterns with CRC checking
   - **Continuous Stream:** Sustained data rate test
   - **Error Recovery:** Inject errors, verify recovery
   - **Baud Rate Sweep:** Test all supported baud rates

3. **`uart_stress_tests.cpp`**

   Test Cases:
   - **Max Throughput:** Continuous transmission at max baud rate
   - **FIFO Saturation:** Keep FIFOs at capacity
   - **Rapid Control Changes:** Change baud rate, enable/disable rapidly
   - **Long Duration:** Run for extended time to catch rare bugs
   - **Concurrent Access:** AXI access during active TX/RX

---

### Step 6.4: Build System

**`simulation/CMakeLists.txt`**

Structure:

```cmake
######################################################################
#
# DESCRIPTION: UART Peripheral Verification CMake Configuration
#
# Builds Verilator testbench with Boost.Test integration for
# automated system-level and module-level testing.
#
######################################################################

cmake_minimum_required(VERSION 3.8)
project(uart_verification)

# Find required packages
find_package(verilator HINTS $ENV{VERILATOR_ROOT} ${VERILATOR_ROOT})
if (NOT verilator_FOUND)
  message(FATAL_ERROR "Verilator was not found. Either install it, or set the VERILATOR_ROOT environment variable")
endif()

find_package(Boost 1.65 REQUIRED COMPONENTS unit_test_framework)
if (NOT Boost_FOUND)
  message(FATAL_ERROR "Boost.Test was not found. Install with: sudo apt-get install libboost-test-dev")
endif()

# Set WORKSPACE - either from environment or auto-detect
if(DEFINED ENV{WORKSPACE})
  set(WORKSPACE "$ENV{WORKSPACE}")
else()
  # Auto-detect: go up one directory from simulation
  get_filename_component(WORKSPACE "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
  message(STATUS "WORKSPACE not set, auto-detected: ${WORKSPACE}")
endif()

set(RTL_ROOT ${WORKSPACE}/rtl)

# RTL sources for uart_top
set(RTL_SRC
  ${RTL_ROOT}/uart_top.sv
  ${RTL_ROOT}/bit_sync.sv
  ${RTL_ROOT}/sync_fifo.sv
  ${RTL_ROOT}/uart_baud_gen.sv
  ${RTL_ROOT}/uart_tx.sv
  ${RTL_ROOT}/uart_rx.sv
  ${RTL_ROOT}/uart_tx_path.sv
  ${RTL_ROOT}/uart_rx_path.sv
  ${RTL_ROOT}/axi_lite_slave_if.sv
  ${RTL_ROOT}/uart_regs.sv
)

# Verilated UART library for system tests
add_library(verilated_uart STATIC
  uart_bfm.cpp
  axi_master_bfm.cpp
  test_runner.cpp
  test_utils.cpp
)

# Verilate the RTL into the library
verilate(verilated_uart COVERAGE TRACE
  PREFIX Vuart_top
  INCLUDE_DIRS ${RTL_ROOT}
  VERILATOR_ARGS -f ./input.vc -O3 --x-assign unique --x-initial unique
  SOURCES ${RTL_SRC}
)

target_include_directories(verilated_uart PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${Boost_INCLUDE_DIRS}
)

# System-level tests
add_executable(uart_system_tests
  tests/test_main.cpp
  tests/uart_system_tests.cpp
  tests/uart_loopback_tests.cpp
  tests/uart_stress_tests.cpp
)

target_link_libraries(uart_system_tests
  verilated_uart
  ${Boost_LIBRARIES}
)

# Module-level tests (separate verilated libraries for each module)

# Bit Synchronizer
add_library(verilated_bit_sync STATIC)
verilate(verilated_bit_sync COVERAGE TRACE
  PREFIX Vbit_sync
  SOURCES ${RTL_ROOT}/bit_sync.sv
)

# Synchronous FIFO
add_library(verilated_sync_fifo STATIC)
verilate(verilated_sync_fifo COVERAGE TRACE
  PREFIX Vsync_fifo
  SOURCES ${RTL_ROOT}/sync_fifo.sv
)

# Baud Rate Generator
add_library(verilated_baud_gen STATIC)
verilate(verilated_baud_gen COVERAGE TRACE
  PREFIX Vuart_baud_gen
  SOURCES ${RTL_ROOT}/uart_baud_gen.sv
)

# UART Transmitter
add_library(verilated_uart_tx STATIC)
verilate(verilated_uart_tx COVERAGE TRACE
  PREFIX Vuart_tx
  SOURCES ${RTL_ROOT}/uart_tx.sv
)

# UART Receiver
add_library(verilated_uart_rx STATIC)
verilate(verilated_uart_rx COVERAGE TRACE
  PREFIX Vuart_rx
  SOURCES ${RTL_ROOT}/uart_rx.sv ${RTL_ROOT}/bit_sync.sv
)

# AXI-Lite Slave Interface
add_library(verilated_axi_slave STATIC)
verilate(verilated_axi_slave COVERAGE TRACE
  PREFIX Vaxi_lite_slave_if
  SOURCES ${RTL_ROOT}/axi_lite_slave_if.sv
)

# UART Register File
add_library(verilated_uart_regs STATIC)
verilate(verilated_uart_regs COVERAGE TRACE
  PREFIX Vuart_regs
  SOURCES ${RTL_ROOT}/uart_regs.sv
)

# Module test executable
add_executable(module_tests
  tests/test_main.cpp
  tests/module/bit_sync_test.cpp
  tests/module/sync_fifo_test.cpp
  tests/module/baud_gen_test.cpp
  tests/module/uart_tx_test.cpp
  tests/module/uart_rx_test.cpp
  tests/module/axi_slave_if_test.cpp
  tests/module/uart_regs_test.cpp
)

target_link_libraries(module_tests
  verilated_bit_sync
  verilated_sync_fifo
  verilated_baud_gen
  verilated_uart_tx
  verilated_uart_rx
  verilated_axi_slave
  verilated_uart_regs
  ${Boost_LIBRARIES}
)

# CTest integration
enable_testing()
add_test(NAME module_tests COMMAND module_tests)
add_test(NAME system_tests COMMAND uart_system_tests)
```

**`simulation/input.vc`** - Verilator configuration:
```
+define+SIMULATION
+define+VERILATOR
-Wno-WIDTH
-Wno-UNOPTFLAT
```

---

## Phase 7: Documentation

### Step 7.1: User Documentation

**`README.md`** - Project overview
- Features and capabilities
- Quick start guide
- Build instructions
- Testing instructions

**`docs/ARCHITECTURE.md`** - Detailed architecture
- Block diagram
- Signal descriptions
- Timing diagrams
- Clock domain considerations

**`docs/REGISTER_MAP.md`** - Register reference
- Complete register map
- Field descriptions
- Usage examples
- Driver code examples

**`docs/INTEGRATION.md`** - Integration guide
- How to integrate UART into SoC
- AXI-Lite connection
- Clock and reset requirements
- Pin assignments

**`docs/VERIFICATION.md`** - Verification strategy
- Test plan
- Coverage goals
- Known limitations

### Step 7.2: Example Software

**`examples/uart_driver.h/c`** - Software driver example
- Initialization function
- Send/receive functions
- Interrupt handler
- Configuration functions

**`examples/uart_test_app.c`** - Test application
- Basic TX/RX example
- Loopback test
- Performance measurement

---

## Implementation Order Summary

**Phase 1: Primitives (Week 1)**
1. Bit synchronizer
2. Synchronous FIFO with tests
3. Module-level verification complete

**Phase 2: TX Path (Week 2)**
4. Baud rate generator
5. UART TX core
6. TX path integration (FIFO + TX)
7. Module-level tests

**Phase 3: RX Path (Week 3)**
8. UART RX core with oversampling
9. RX path integration (FIFO + RX)
10. Module-level tests

**Phase 4: AXI Interface (Week 4)**
11. AXI-Lite slave interface
12. Register file implementation
13. Module-level tests

**Phase 5: Integration (Week 5)**
14. Top-level integration
15. Clock domain crossing verification
16. System-level loopback tests

**Phase 6: Verification (Week 6-7)**
17. C++ BFMs (UART and AXI)
18. Test runner and utilities
19. Comprehensive system tests
20. Stress tests
21. Coverage analysis

**Phase 7: Documentation (Week 8)**
22. User documentation
23. Register map reference
24. Integration guide
25. Example software driver
26. Final review

---

## Success Criteria

- [ ] All module-level tests pass
- [ ] All system-level tests pass
- [ ] Loopback tests pass at all supported baud rates
- [ ] Code coverage > 95%
- [ ] Functional coverage > 90%
- [ ] Zero Verilator lint warnings
- [ ] Synthesis clean (no timing violations)
- [ ] Documentation complete
- [ ] Example driver tested
- [ ] Verified with real UART device (if FPGA available)

---

## Tools and Dependencies

**Required:**
- Verilator >= 4.0
- CMake >= 3.8
- Boost Test >= 1.65
- GCC/Clang with C++14 support
- SystemVerilog simulator (for RTL development)

**Optional:**
- GTKWave (waveform viewing)
- Vivado/Quartus (FPGA synthesis)
- Python with pyserial (for host-side testing)
- Logic analyzer (for hardware debug)

---

## Supported Baud Rates

Given constraints:
- UART clock: 7.3728 MHz (4× standard UART clock frequency)
- System clock: ~1 MHz range (for AXI-Lite interface)
- 16× oversampling for all supported baud rates including 460800

**Standard Baud Rates with 7.3728 MHz Clock:**

| Baud Rate | Oversampling | Tick Freq  | Divisor | Actual Baud | Error   |
|-----------|--------------|------------|---------|-------------|---------|
| 2400      | 16×          | 38400 Hz   | 192     | 2400        | 0%      |
| 4800      | 16×          | 76800 Hz   | 96      | 4800        | 0%      |
| 9600      | 16×          | 153600 Hz  | 48      | 9600        | 0%      |
| 14400     | 16×          | 230400 Hz  | 32      | 14400       | 0%      |
| 19200     | 16×          | 307200 Hz  | 24      | 19200       | 0%      |
| 28800     | 16×          | 460800 Hz  | 16      | 28800       | 0%      |
| 38400     | 16×          | 614400 Hz  | 12      | 38400       | 0%      |
| 57600     | 16×          | 921600 Hz  | 8       | 57600       | 0%      |
| 115200    | 16×          | 1843200 Hz | 4       | 115200      | 0%      |
| 230400    | 16×          | 3686400 Hz | 2       | 230400      | 0%      |
| 460800    | 16×          | 7372800 Hz | 1       | 460800      | 0%      |

**Why 7.3728 MHz?**
- 4× the standard UART frequency (7.3728 MHz = 4 × 1.8432 MHz)
- Enables 460800 baud support: 7.3728 MHz = 460800 × 16
- Perfect integer divisors for all standard baud rates up to 460800
- No baud rate error (0% for all rates)
- Full 16× oversampling for all rates provides excellent noise immunity
- Common clock frequency for high-speed UART applications

---

## Design Trade-offs and Decisions

### 1. Oversampling Rate
**Decision:** 16× for RX, 1× for TX (TX uses direct baud tick)
**Rationale:** RX needs oversampling for start bit detection and noise immunity. TX can operate at baud rate directly.

### 2. FIFO Depth
**Decision:** 8 entries for both TX and RX
**Rationale:** Balance between resource usage and buffering. Sufficient for typical burst transfers without frequent CPU intervention.

### 3. Clock Architecture
**Decision:** External 7.3728 MHz UART clock + internal ~1 MHz system clock
**Rationale:** 7.3728 MHz (4× standard UART frequency) provides perfect integer divisors for all standard baud rates including 460800 baud with full 16× oversampling. System clock for AXI and control logic. Clean separation of timing domains.

### 4. Error Handling
**Decision:** Sticky error flags, cleared by software
**Rationale:** Ensures software doesn't miss error conditions. W1C for interrupt status provides clean clearing mechanism.

### 5. Interrupt Support
**Decision:** Single IRQ output with maskable sources
**Rationale:** Flexible for different use cases. Software can poll or use interrupts.

---

## Future Enhancements

**Phase 2 Features (Post-Initial Release):**
- Parity support (odd, even, mark, space)
- 2 stop bit support
- Hardware flow control (RTS/CTS)
- 9-bit mode
- LIN protocol support
- DMA interface
- Deeper FIFOs (parameterizable)
- Auto-baud detection
- Per-byte error tracking

---

## Notes

- All RTL should be synthesizable
- Use SystemVerilog features: `always_ff`, `always_comb`, packages, typedefs
- Follow consistent naming conventions:
  - Active-low signals: `*_n` suffix
  - Clock signals: `clk*` prefix or `*_clk` suffix
  - Reset signals: `rst_n` or `*_rst_n`
  - AXI signals: Follow AXI-Lite naming conventions
- Add comprehensive assertions (SVA) for formal verification
- Comment complex state machines and timing-critical sections
- Consider lint rules for clock domain crossing

---

## Appendix A: UART Protocol Details

### Frame Format (8N1)

```
      ┌─────┬────┬────┬────┬────┬────┬────┬────┬────┬──────┐
Idle  │Start│ D0 │ D1 │ D2 │ D3 │ D4 │ D5 │ D6 │ D7 │ Stop │ Idle
(1)   │  0  │    │    │    │    │    │    │    │    │  1   │ (1)
      └─────┴────┴────┴────┴────┴────┴────┴────┴────┴──────┘
       1 bit  LSB                                MSB  1 bit
```

- **Idle state:** Logic HIGH (mark)
- **Start bit:** Logic LOW (space) - 1 bit duration
- **Data bits:** 8 bits, LSB first
- **Stop bit:** Logic HIGH (mark) - 1 bit duration
- **Total frame time:** 10 bit periods

### Timing

For 115200 baud:
- Bit time = 1 / 115200 ≈ 8.68 μs
- Frame time = 10 × 8.68 μs ≈ 86.8 μs
- Byte rate = 115200 / 10 = 11520 bytes/second

### Oversampling

16× oversampling at 115200 baud:
- Sample rate = 115200 × 16 = 1843200 Hz
- Sample period ≈ 0.543 μs
- Samples per bit = 16

**Start bit detection:**
- Detect falling edge on RX line
- Wait 8 sample periods (to middle of start bit)
- Sample and verify LOW
- If HIGH: false start, return to idle

**Data bit sampling:**
- For each of 8 data bits:
  - Wait 16 sample periods from previous sample point
  - Sample at middle of bit period
  - Shift into receive register

---

## Appendix B: AXI-Lite Protocol Summary

### Write Transaction

```
Cycle  | AWVALID | AWADDR | WVALID | WDATA | BVALID | BRESP
-------|---------|--------|--------|-------|--------|-------
1      | 1       | 0x08   | 1      | 0xAB  | 0      | --
2      | 0       | --     | 0      | --    | 1      | OKAY
```

**Transaction steps:**
1. Master asserts AWVALID with address and WVALID with data
2. Slave asserts AWREADY and WREADY when accepted (may be same cycle)
3. Slave performs write operation
4. Slave asserts BVALID with response
5. Master asserts BREADY to acknowledge
6. Transaction complete

### Read Transaction

```
Cycle  | ARVALID | ARADDR | RVALID | RDATA | RRESP
-------|---------|--------|--------|-------|-------
1      | 1       | 0x04   | 0      | --    | --
2      | 0       | --     | 1      | 0x12  | OKAY
```

**Transaction steps:**
1. Master asserts ARVALID with address
2. Slave asserts ARREADY when accepted
3. Slave performs read operation
4. Slave asserts RVALID with data and response
5. Master asserts RREADY to acknowledge
6. Transaction complete

---

## Appendix C: FIFO Implementation Details

### FIFO Pointer Logic

For a FIFO with depth = 8 (2^3):
- Address width = 3 bits
- Pointer width = 4 bits (extra bit for full/empty distinction)

**Full condition:**
```systemverilog
assign full = (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]) &&
              (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]);
```

**Empty condition:**
```systemverilog
assign empty = (wr_ptr == rd_ptr);
```

**Level calculation:**
```systemverilog
assign level = wr_ptr - rd_ptr;
```

### Example FIFO State

```
FIFO depth = 8
rd_ptr = 4'b0010 (reading from index 2)
wr_ptr = 4'b0101 (writing to index 5)
level = 5 - 2 = 3 (3 entries in FIFO)
```

---

## Appendix D: Clock Domain Crossing Guidelines

### Safe CDC Practices

1. **Single-bit signals:** Use multi-stage synchronizer (2-3 FFs)
2. **Multi-bit signals:** Use Gray code or handshake protocol
3. **Pulse signals:** Stretch pulse or use toggle synchronizer
4. **Bus signals:** Use async FIFO or valid/ready handshake

### Metastability Protection

Mean Time Between Failures (MTBF):
```
MTBF = (e^(Tr/C2)) / (C1 × f_clk × f_data)

Where:
  Tr = resolution time (time for FF to settle)
  C1, C2 = device-specific constants
  f_clk = destination clock frequency
  f_data = data transition rate
```

For 2-stage synchronizer:
- MTBF typically > 10^9 years (more than lifetime of device)

### Verification

- Formal verification recommended for CDC paths
- Verify all paths with CDC tools (Synopsys SpyGlass, Mentor CDC)
- Simulation coverage of CDC scenarios

---

## Appendix E: Synthesis Considerations

### Resource Estimates (FPGA)

For Xilinx 7-series or Lattice ECP5:

| Component      | LUTs | FFs | BRAM |
|----------------|------|-----|------|
| Bit Sync       | 2    | 4   | 0    |
| Sync FIFO (8)  | 50   | 70  | 0    |
| Baud Gen       | 30   | 20  | 0    |
| UART TX        | 40   | 30  | 0    |
| UART RX        | 60   | 40  | 0    |
| AXI Slave IF   | 100  | 80  | 0    |
| Register File  | 150  | 100 | 0    |
| **Total**      | ~500 | ~400| 0    |

**Note:** FIFO can optionally use BRAM for deeper configurations.

### Timing Constraints

**Clock definitions:**
```tcl
create_clock -period 1000.0 -name sys_clk [get_ports clk]
create_clock -period 135.63 -name uart_clk [get_ports uart_clk]
```

**Async paths:**
```tcl
set_false_path -from [get_ports uart_rx]
set_false_path -to [get_ports uart_tx]
```

**CDC constraints:**
```tcl
set_max_delay -from [get_clocks sys_clk] -to [get_clocks uart_clk] 1000.0
set_max_delay -from [get_clocks uart_clk] -to [get_clocks sys_clk] 1000.0
```

---

## Appendix F: Software Driver Example

### Initialization

```c
#define UART_CLK_FREQ 7372800  // 7.3728 MHz

void uart_init(uint32_t base_addr, uint32_t baud_rate) {
    // Calculate baud divisor (16× oversampling)
    uint32_t divisor = UART_CLK_FREQ / (baud_rate * 16);

    // Reset FIFOs
    UART_WRITE(base_addr, FIFO_CTRL, 0x03);

    // Set baud rate
    UART_WRITE(base_addr, BAUD_DIV, divisor);

    // Enable TX and RX
    UART_WRITE(base_addr, CTRL, 0x03);

    // Enable interrupts
    UART_WRITE(base_addr, INT_ENABLE, 0x0F);
}

// Example: For 460800 baud: divisor = 7372800 / (460800 * 16) = 1
// Example: For 115200 baud: divisor = 7372800 / (115200 * 16) = 4
// Example: For 9600 baud: divisor = 7372800 / (9600 * 16) = 48
```

### Transmit

```c
int uart_putc(uint32_t base_addr, uint8_t data) {
    uint32_t status;

    // Wait for TX FIFO not full
    do {
        status = UART_READ(base_addr, STATUS);
    } while (status & TX_FULL);

    // Write data
    UART_WRITE(base_addr, TX_DATA, data);

    return 0;
}
```

### Receive

```c
int uart_getc(uint32_t base_addr, uint8_t *data) {
    uint32_t status;

    // Check if RX FIFO has data
    status = UART_READ(base_addr, STATUS);
    if (status & RX_EMPTY) {
        return -1;  // No data available
    }

    // Read data
    *data = UART_READ(base_addr, RX_DATA) & 0xFF;

    // Check for errors
    if (status & (FRAME_ERROR | OVERRUN_ERROR)) {
        // Clear error flags
        UART_WRITE(base_addr, INT_STATUS, 0x0C);
        return -2;  // Error
    }

    return 0;
}
```

---

## Recovery Procedures and Troubleshooting

### When Tests Start Failing

**DO NOT:**
- Try to fix multiple failures simultaneously
- Patch tests to make them pass
- Keep making changes hoping something works
- Skip running regression tests

**DO:**
1. **Identify last known-good state:**
   ```bash
   git tag  # Find last validated tag
   git log --oneline --decorate
   ```

2. **Rollback to baseline:**
   ```bash
   git reset --hard <last-known-good-tag>
   # Verify tests pass at baseline
   ./build/module_tests
   ./build/system_tests
   ```

3. **Incremental re-integration:**
   - Reapply changes one at a time
   - Test after each change
   - Tag successful states
   - Stop and debug at first failure

### Architectural Change Process

If making architectural changes (e.g., sync_fifo → async_fifo):

1. **Create design document:** `docs/arch_change_<name>.md`
2. **Get approval** before implementation
3. **Create rollback point:** `git tag -a before_<change>`
4. **Validate new component in isolation** before integration
5. **Incremental integration** with testing at each step

### Common Issues and Solutions

**Issue: Module tests pass but integration fails**
- **Cause:** Interface mismatch or timing assumption
- **Solution:** Check interface specifications, verify clock domains

**Issue: Single byte works but multi-byte fails**
- **Cause:** Handshaking issue, prefetch logic, duplicate writes
- **Solution:** Check FSM state transitions, FIFO read/write logic

**Issue: Random failures or timing-dependent bugs**
- **Cause:** CDC issues, metastability, race conditions
- **Solution:** Review CDC synchronization, add constraints

### For Detailed Recovery Procedures

See `DEVELOPMENT_GUIDELINES.md` for:
- Complete recovery decision tree
- Phase gate enforcement procedures
- Test infrastructure validation
- Hardware-specific debugging checklist
- Project-specific learnings from UART development
