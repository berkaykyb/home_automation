;==============================================================================
; Home Automation - Air Conditioner System
; PIC16F877A Microcontroller
; Crystal: 4 MHz
;==============================================================================
; WORKING VERSION - Keypad using polling mode (same as keypad_test.asm)
; Pin Configuration:
;   RA0: LM35 Temperature Sensor (Analog)
;   RA1-RA3: Keypad Columns 1-3
;   RB0: Keypad Column 4
;   RB4-RB7: Keypad Rows 1-4
;   RC0: Heater
;   RC1: Fan/Cooler
;   RC2: Tachometer input
;   RC3: Input Mode LED (Blue)
;   RC4: Success LED (Green)
;   RC5: Error LED (Red)
;   RD0-RD7: 7-Segment Display
;==============================================================================

    PROCESSOR 16F877A
    #include <xc.inc>
    
; Configuration Bits
    CONFIG CP = OFF
    CONFIG CPD = OFF
    CONFIG WDTE = OFF
    CONFIG BOREN = OFF
    CONFIG PWRTE = ON
    CONFIG FOSC = HS
    CONFIG LVP = OFF
    CONFIG WRT = OFF

;==============================================================================
; Variable Definitions
;==============================================================================
    PSECT udata_bank0

; Temperature Variables
DESIRED_TEMP_INT:   DS 1
DESIRED_TEMP_FRAC:  DS 1
AMBIENT_TEMP_INT:   DS 1
AMBIENT_TEMP_FRAC:  DS 1

; Fan Speed
FAN_SPEED:          DS 1

; Keypad Variables
KEY_VALUE:          DS 1
INPUT_MODE:         DS 1
DIGIT_COUNT:        DS 1
TEMP_DIGIT1:        DS 1
TEMP_DIGIT2:        DS 1
TEMP_FRAC:          DS 1
HAS_DECIMAL:        DS 1

; ADC Variables
ADC_RESULT_H:       DS 1
ADC_RESULT_L:       DS 1

; Display Variables [R2.1.3-1]
DISPLAY_MODE:       DS 1    ; 0=Desired, 1=Ambient, 2=Fan Speed
DISPLAY_TIMER:      DS 1    ; Counter for 2-second intervals
CURRENT_DIGIT:      DS 1    ; Current digit being displayed (0-3 for MUX)
MUX_DIGIT0:         DS 1    ; Digit 0 value (tens)
MUX_DIGIT1:         DS 1    ; Digit 1 value (ones)
MUX_DIGIT2:         DS 1    ; Digit 2 value (decimal point indicator)
MUX_DIGIT3:         DS 1    ; Digit 3 value (fraction)

; Temporary Registers
TEMP_W:             DS 1
TEMP_REG:           DS 1
ROW_VAL:            DS 1
CALC_TEMP:          DS 1
DELAY_CNT1:         DS 1
DELAY_CNT2:         DS 1
DELAY_CNT3:         DS 1

;==============================================================================
; Key Codes
;==============================================================================
#define KEY_1       0x00
#define KEY_2       0x01
#define KEY_3       0x02
#define KEY_A       0x03
#define KEY_4       0x04
#define KEY_5       0x05
#define KEY_6       0x06
#define KEY_B       0x07
#define KEY_7       0x08
#define KEY_8       0x09
#define KEY_9       0x0A
#define KEY_C       0x0B
#define KEY_STAR    0x0C
#define KEY_0       0x0D
#define KEY_HASH    0x0E
#define KEY_D       0x0F
#define KEY_NONE    0xFF

;==============================================================================
; Reset Vector
;==============================================================================
    PSECT resetVec,class=CODE,delta=2
    ORG     0x0000
    GOTO    MAIN

;==============================================================================
; Interrupt Vector (not used - polling mode)
;==============================================================================
    PSECT intVec,class=CODE,delta=2
    ORG     0x0004
    RETFIE

;==============================================================================
; Main Program
;==============================================================================
    PSECT code
MAIN:
    CALL    INIT_PORTS
    CALL    INIT_ADC
    CALL    INIT_UART
    CALL    INIT_VARIABLES
    
    ; Default desired temperature 25.0 C
    MOVLW   25
    banksel DESIRED_TEMP_INT
    MOVWF   DESIRED_TEMP_INT
    CLRF    DESIRED_TEMP_FRAC

;==============================================================================
; Main Loop
;==============================================================================
MAIN_LOOP:
    ; Read temperature
    CALL    READ_TEMPERATURE
    
    ; Update fan speed based on fan state (simulated)
    CALL    UPDATE_FAN_SPEED
    
    ; Control heater/fan
    CALL    CONTROL_TEMPERATURE
    
    ; Process keypad
    CALL    PROCESS_KEYPAD
    
    ; Update display multiple times for stable multiplexing
    ; Each call shows one digit, need 4 calls per full refresh
    CALL    UPDATE_DISPLAY
    CALL    DELAY_5MS
    CALL    UPDATE_DISPLAY
    CALL    DELAY_5MS
    CALL    UPDATE_DISPLAY
    CALL    DELAY_5MS
    CALL    UPDATE_DISPLAY
    CALL    DELAY_5MS
    
    ; Additional display refreshes for stability
    CALL    UPDATE_DISPLAY
    CALL    DELAY_5MS
    CALL    UPDATE_DISPLAY
    CALL    DELAY_5MS
    CALL    UPDATE_DISPLAY
    CALL    DELAY_5MS
    CALL    UPDATE_DISPLAY
    CALL    DELAY_5MS
    
    ; Check for UART commands
    CALL    CHECK_UART_COMMAND
    
    GOTO    MAIN_LOOP

;==============================================================================
; INIT_PORTS
;==============================================================================
INIT_PORTS:
    ; ADCON1: RA0 analog, RA1-RA5 digital, RE0-RE2 digital, RIGHT JUSTIFIED
    banksel ADCON1
    MOVLW   0x8E                ; Right justified, RA0 analog, RE as digital
    MOVWF   ADCON1
    
    ; TRISA: RA0=input (ADC), RA1-RA3=output (keypad cols)
    banksel TRISA
    MOVLW   0x01
    MOVWF   TRISA
    
    ; TRISB: RB0=output (col4), RB4-RB7=input (rows)
    MOVLW   0xF0
    MOVWF   TRISB
    
    ; Enable pull-ups
    banksel OPTION_REG
    BCF     OPTION_REG, 7
    
    ; TRISC: RC2=input (tach), RC6=input (UART TX override), RC7=input (UART RX), RC4=output (digit4)
    banksel TRISC
    MOVLW   0xC4                ; RC2, RC6, RC7 as inputs (bits 2,6,7)
    MOVWF   TRISC
    
    ; TRISD: All outputs (7-segment data)
    CLRF    TRISD
    
    ; TRISE: RE0-RE2 outputs (digit select 1-3)
    CLRF    TRISE
    
    ; Initialize outputs
    banksel PORTA
    MOVLW   0x0E                ; RA1-RA3 HIGH
    MOVWF   PORTA
    
    banksel PORTB
    BSF     PORTB, 0            ; RB0 HIGH
    
    banksel PORTC
    CLRF    PORTC               ; All LEDs OFF, RC6 LOW (digit4 off)
    
    banksel PORTE
    CLRF    PORTE               ; All digit selects OFF
    
    banksel PORTD
    MOVLW   0x40                ; Show "-"
    MOVWF   PORTD
    
    RETURN

;==============================================================================
; INIT_ADC
;==============================================================================
INIT_ADC:
    banksel ADCON0
    MOVLW   0x81                ; Fosc/32, CH0, ADC ON
    MOVWF   ADCON0
    RETURN

;==============================================================================
; INIT_VARIABLES
;==============================================================================
INIT_VARIABLES:
    banksel INPUT_MODE
    CLRF    INPUT_MODE
    CLRF    DIGIT_COUNT
    CLRF    TEMP_DIGIT1
    CLRF    TEMP_DIGIT2
    CLRF    TEMP_FRAC
    CLRF    HAS_DECIMAL
    CLRF    FAN_SPEED
    CLRF    DISPLAY_MODE        ; Start with Desired temp
    CLRF    DISPLAY_TIMER
    CLRF    CURRENT_DIGIT       ; Start with digit 0
    CLRF    MUX_DIGIT0
    CLRF    MUX_DIGIT1
    CLRF    MUX_DIGIT2
    CLRF    MUX_DIGIT3
    MOVLW   KEY_NONE
    MOVWF   KEY_VALUE
    RETURN

;==============================================================================
; INIT_UART - Initialize UART for 9600 baud @ 4MHz
;==============================================================================
INIT_UART:
    ; SPBRG for 9600 baud @ 4MHz with BRGH=1 (High Speed Mode)
    ; Baud = Fosc / (16 * (SPBRG + 1))
    ; 9600 = 4000000 / (16 * (SPBRG + 1))
    ; SPBRG = 25 → 9615 baud (0.16% error)
    banksel SPBRG
    MOVLW   25
    MOVWF   SPBRG
    
    ; TXSTA: BRGH=1 (High Speed), TXEN=1 (Enable TX), SYNC=0 (Async)
    banksel TXSTA
    MOVLW   0x24                ; 0b00100100: BRGH=1, TXEN=1
    MOVWF   TXSTA
    
    ; RCSTA: SPEN=1 (Serial Port Enable)
    banksel RCSTA
    MOVLW   0x90                ; 0b10010000: SPEN=1, CREN=1
    MOVWF   RCSTA
    
    RETURN

;==============================================================================
; READ_TEMPERATURE
;==============================================================================
READ_TEMPERATURE:
    banksel ADCON0
    BSF     ADCON0, 2           ; Start conversion
    
WAIT_ADC:
    BTFSC   ADCON0, 2
    GOTO    WAIT_ADC
    
    MOVF    ADRESH, W
    banksel ADC_RESULT_H
    MOVWF   ADC_RESULT_H
    
    banksel ADRESL
    MOVF    ADRESL, W
    banksel ADC_RESULT_L
    MOVWF   ADC_RESULT_L
    
    ; Convert: Temp ? ADC / 2
    banksel ADC_RESULT_L
    MOVF    ADC_RESULT_L, W
    banksel TEMP_REG
    MOVWF   TEMP_REG
    BCF     STATUS, 0
    RRF     TEMP_REG, F
    
    banksel ADC_RESULT_H
    BTFSC   ADC_RESULT_H, 0
    BSF     TEMP_REG, 7
    
    banksel TEMP_REG
    MOVF    TEMP_REG, W
    banksel AMBIENT_TEMP_INT
    MOVWF   AMBIENT_TEMP_INT
    
    banksel ADC_RESULT_L
    BTFSC   ADC_RESULT_L, 0
    GOTO    SET_FRAC_5
    banksel AMBIENT_TEMP_FRAC
    CLRF    AMBIENT_TEMP_FRAC
    RETURN
    
SET_FRAC_5:
    MOVLW   5
    banksel AMBIENT_TEMP_FRAC
    MOVWF   AMBIENT_TEMP_FRAC
    RETURN

;==============================================================================
; UPDATE_FAN_SPEED - Simulated fan speed based on fan state
; If fan (RC1) is ON, show speed; if OFF, show 0
;==============================================================================
UPDATE_FAN_SPEED:
    banksel PORTC
    BTFSS   PORTC, 1            ; Is fan ON (RC1)?
    GOTO    FAN_SPEED_ZERO
    
    ; Fan is ON - set simulated speed (12 RPS)
    MOVLW   12
    banksel FAN_SPEED
    MOVWF   FAN_SPEED
    RETURN

FAN_SPEED_ZERO:
    banksel FAN_SPEED
    CLRF    FAN_SPEED
    RETURN

;==============================================================================
; CONTROL_TEMPERATURE - Physically correct logic
; Desired > Ambient -> Heat needed -> Heater ON, Fan OFF
; Desired < Ambient -> Cool needed -> Heater OFF, Fan ON
; Desired = Ambient -> Both OFF
;==============================================================================
CONTROL_TEMPERATURE:
    ; Compare Desired vs Ambient (integer parts first)
    ; We want to know: is Desired > Ambient, < Ambient, or = Ambient?
    
    banksel AMBIENT_TEMP_INT
    MOVF    AMBIENT_TEMP_INT, W     ; W = Ambient
    banksel DESIRED_TEMP_INT
    SUBWF   DESIRED_TEMP_INT, W     ; W = Desired - Ambient
    
    ; After SUBWF:
    ; If Desired > Ambient: result positive, C=1, Z=0
    ; If Desired < Ambient: result negative (underflow), C=0, Z=0
    ; If Desired = Ambient: result zero, Z=1
    
    BTFSC   STATUS, 2               ; Z=1? (equal integers)
    GOTO    CHECK_FRACTIONS         ; Yes, check fractions
    
    ; Integers not equal
    BTFSC   STATUS, 0               ; C=1? (Desired >= Ambient, no borrow)
    GOTO    CTRL_HEAT               ; Yes, Desired > Ambient -> HEAT
    GOTO    CTRL_COOL               ; No, Desired < Ambient -> COOL

CHECK_FRACTIONS:
    ; Integer parts equal, compare fractions
    banksel AMBIENT_TEMP_FRAC
    MOVF    AMBIENT_TEMP_FRAC, W
    banksel DESIRED_TEMP_FRAC
    SUBWF   DESIRED_TEMP_FRAC, W    ; W = Desired_frac - Ambient_frac
    
    BTFSC   STATUS, 2               ; Z=1? (equal)
    GOTO    CTRL_OFF                ; Yes, equal -> both off
    
    BTFSC   STATUS, 0               ; C=1? (Desired_frac >= Ambient_frac)
    GOTO    CTRL_HEAT               ; Yes, Desired > Ambient -> HEAT
    GOTO    CTRL_COOL               ; No, Desired < Ambient -> COOL

CTRL_HEAT:
    banksel PORTC
    BSF     PORTC, 0                ; Heater ON
    BCF     PORTC, 1                ; Fan OFF
    RETURN

CTRL_COOL:
    banksel PORTC
    BCF     PORTC, 0                ; Heater OFF
    BSF     PORTC, 1                ; Fan ON
    RETURN

CTRL_OFF:
    banksel PORTC
    BCF     PORTC, 0                ; Heater OFF
    BCF     PORTC, 1                ; Fan OFF
    RETURN

;==============================================================================
; PROCESS_KEYPAD - Polling mode
;==============================================================================
PROCESS_KEYPAD:
    CALL    SCAN_KEYPAD
    
    ; Check if any key pressed
    banksel KEY_VALUE
    MOVLW   KEY_NONE
    SUBWF   KEY_VALUE, W
    BTFSC   STATUS, 2
    RETURN                          ; No key
    
    ; Check for 'A' to enter input mode
    banksel INPUT_MODE
    BTFSC   INPUT_MODE, 0
    GOTO    HANDLE_INPUT_KEY        ; Already in input mode
    
    ; Not in input mode - check for 'A'
    banksel KEY_VALUE
    MOVF    KEY_VALUE, W
    SUBLW   KEY_A
    BTFSS   STATUS, 2
    GOTO    KEY_DONE                ; Not 'A', ignore
    
    ; 'A' pressed - enter input mode
    CALL    ENTER_INPUT_MODE
    GOTO    KEY_DONE

HANDLE_INPUT_KEY:
    CALL    PROCESS_INPUT_KEY

KEY_DONE:
    CALL    DEBOUNCE_DELAY
    CALL    WAIT_KEY_RELEASE
    RETURN

;==============================================================================
; ENTER_INPUT_MODE
;==============================================================================
ENTER_INPUT_MODE:
    banksel INPUT_MODE
    BSF     INPUT_MODE, 0
    CLRF    DIGIT_COUNT
    CLRF    TEMP_DIGIT1
    CLRF    TEMP_DIGIT2
    CLRF    TEMP_FRAC
    CLRF    HAS_DECIMAL
    
    ; LED ON
    banksel PORTC
    BSF     PORTC, 3
    
    ; Show 'A'
    banksel PORTD
    MOVLW   0x77
    MOVWF   PORTD
    
    RETURN

;==============================================================================
; SCAN_KEYPAD - Same as working keypad_test.asm
;==============================================================================
SCAN_KEYPAD:
    banksel KEY_VALUE
    MOVLW   KEY_NONE
    MOVWF   KEY_VALUE
    
    ; Column 1 (RA1 LOW)
    banksel PORTA
    BCF     PORTA, 1
    BSF     PORTA, 2
    BSF     PORTA, 3
    banksel PORTB
    BSF     PORTB, 0
    NOP
    NOP
    NOP
    
    MOVF    PORTB, W
    ANDLW   0xF0
    banksel ROW_VAL
    MOVWF   ROW_VAL
    
    BTFSS   ROW_VAL, 4
    GOTO    SK_1
    BTFSS   ROW_VAL, 5
    GOTO    SK_4
    BTFSS   ROW_VAL, 6
    GOTO    SK_7
    BTFSS   ROW_VAL, 7
    GOTO    SK_STAR
    
    ; Column 2 (RA2 LOW)
    banksel PORTA
    BSF     PORTA, 1
    BCF     PORTA, 2
    BSF     PORTA, 3
    NOP
    NOP
    NOP
    
    banksel PORTB
    MOVF    PORTB, W
    ANDLW   0xF0
    banksel ROW_VAL
    MOVWF   ROW_VAL
    
    BTFSS   ROW_VAL, 4
    GOTO    SK_2
    BTFSS   ROW_VAL, 5
    GOTO    SK_5
    BTFSS   ROW_VAL, 6
    GOTO    SK_8
    BTFSS   ROW_VAL, 7
    GOTO    SK_0
    
    ; Column 3 (RA3 LOW)
    banksel PORTA
    BSF     PORTA, 1
    BSF     PORTA, 2
    BCF     PORTA, 3
    NOP
    NOP
    NOP
    
    banksel PORTB
    MOVF    PORTB, W
    ANDLW   0xF0
    banksel ROW_VAL
    MOVWF   ROW_VAL
    
    BTFSS   ROW_VAL, 4
    GOTO    SK_3
    BTFSS   ROW_VAL, 5
    GOTO    SK_6
    BTFSS   ROW_VAL, 6
    GOTO    SK_9
    BTFSS   ROW_VAL, 7
    GOTO    SK_HASH
    
    ; Column 4 (RB0 LOW)
    banksel PORTA
    BSF     PORTA, 1
    BSF     PORTA, 2
    BSF     PORTA, 3
    banksel PORTB
    BCF     PORTB, 0
    NOP
    NOP
    NOP
    
    MOVF    PORTB, W
    ANDLW   0xF0
    banksel ROW_VAL
    MOVWF   ROW_VAL
    
    BTFSS   ROW_VAL, 4
    GOTO    SK_A
    BTFSS   ROW_VAL, 5
    GOTO    SK_B
    BTFSS   ROW_VAL, 6
    GOTO    SK_C
    BTFSS   ROW_VAL, 7
    GOTO    SK_D
    
    ; No key - restore
    banksel PORTA
    BSF     PORTA, 1
    BSF     PORTA, 2
    BSF     PORTA, 3
    banksel PORTB
    BSF     PORTB, 0
    RETURN

SK_0:
    MOVLW   KEY_0
    GOTO    SK_SAVE
SK_1:
    MOVLW   KEY_1
    GOTO    SK_SAVE
SK_2:
    MOVLW   KEY_2
    GOTO    SK_SAVE
SK_3:
    MOVLW   KEY_3
    GOTO    SK_SAVE
SK_4:
    MOVLW   KEY_4
    GOTO    SK_SAVE
SK_5:
    MOVLW   KEY_5
    GOTO    SK_SAVE
SK_6:
    MOVLW   KEY_6
    GOTO    SK_SAVE
SK_7:
    MOVLW   KEY_7
    GOTO    SK_SAVE
SK_8:
    MOVLW   KEY_8
    GOTO    SK_SAVE
SK_9:
    MOVLW   KEY_9
    GOTO    SK_SAVE
SK_A:
    MOVLW   KEY_A
    GOTO    SK_SAVE
SK_B:
    MOVLW   KEY_B
    GOTO    SK_SAVE
SK_C:
    MOVLW   KEY_C
    GOTO    SK_SAVE
SK_D:
    MOVLW   KEY_D
    GOTO    SK_SAVE
SK_STAR:
    MOVLW   KEY_STAR
    GOTO    SK_SAVE
SK_HASH:
    MOVLW   KEY_HASH
    GOTO    SK_SAVE

SK_SAVE:
    banksel KEY_VALUE
    MOVWF   KEY_VALUE
    banksel PORTA
    BSF     PORTA, 1
    BSF     PORTA, 2
    BSF     PORTA, 3
    banksel PORTB
    BSF     PORTB, 0
    RETURN

;==============================================================================
; PROCESS_INPUT_KEY
;==============================================================================
PROCESS_INPUT_KEY:
    banksel KEY_VALUE
    MOVF    KEY_VALUE, W
    banksel TEMP_W
    MOVWF   TEMP_W
    
    ; Check '#' - confirm
    MOVLW   KEY_HASH
    SUBWF   TEMP_W, W
    BTFSC   STATUS, 2
    GOTO    CONFIRM_INPUT
    
    ; Check '*' - decimal
    MOVLW   KEY_STAR
    SUBWF   TEMP_W, W
    BTFSC   STATUS, 2
    GOTO    SET_DECIMAL
    
    ; Convert to digit
    CALL    KEY_TO_DIGIT
    
    ; Check valid
    banksel TEMP_W
    MOVF    TEMP_W, W
    SUBLW   9
    BTFSS   STATUS, 0
    RETURN
    
    ; Display digit
    banksel TEMP_W
    MOVF    TEMP_W, W
    CALL    DISPLAY_DIGIT
    
    ; Store digit
    CALL    STORE_DIGIT
    
    RETURN

;==============================================================================
; SET_DECIMAL
;==============================================================================
SET_DECIMAL:
    banksel DIGIT_COUNT
    MOVF    DIGIT_COUNT, W
    BTFSC   STATUS, 2
    RETURN
    
    banksel HAS_DECIMAL
    BTFSC   HAS_DECIMAL, 0
    RETURN
    
    BSF     HAS_DECIMAL, 0
    banksel PORTD
    BSF     PORTD, 7
    RETURN

;==============================================================================
; STORE_DIGIT
;==============================================================================
STORE_DIGIT:
    banksel HAS_DECIMAL
    BTFSC   HAS_DECIMAL, 0
    GOTO    STORE_FRAC
    
    banksel DIGIT_COUNT
    MOVF    DIGIT_COUNT, W
    BTFSC   STATUS, 2
    GOTO    STORE_D1
    
    SUBLW   1
    BTFSC   STATUS, 2
    GOTO    STORE_D2
    
    RETURN

STORE_D1:
    banksel TEMP_W
    MOVF    TEMP_W, W
    banksel TEMP_DIGIT1
    MOVWF   TEMP_DIGIT1
    INCF    DIGIT_COUNT, F
    RETURN

STORE_D2:
    banksel TEMP_W
    MOVF    TEMP_W, W
    banksel TEMP_DIGIT2
    MOVWF   TEMP_DIGIT2
    INCF    DIGIT_COUNT, F
    RETURN

STORE_FRAC:
    banksel TEMP_W
    MOVF    TEMP_W, W
    banksel TEMP_FRAC
    MOVWF   TEMP_FRAC
    RETURN

;==============================================================================
; KEY_TO_DIGIT
;==============================================================================
KEY_TO_DIGIT:
    banksel TEMP_W
    
    MOVF    TEMP_W, W
    SUBLW   KEY_0
    BTFSC   STATUS, 2
    GOTO    KD_0
    
    MOVF    TEMP_W, W
    SUBLW   KEY_1
    BTFSC   STATUS, 2
    GOTO    KD_1
    
    MOVF    TEMP_W, W
    SUBLW   KEY_2
    BTFSC   STATUS, 2
    GOTO    KD_2
    
    MOVF    TEMP_W, W
    SUBLW   KEY_3
    BTFSC   STATUS, 2
    GOTO    KD_3
    
    MOVF    TEMP_W, W
    SUBLW   KEY_4
    BTFSC   STATUS, 2
    GOTO    KD_4
    
    MOVF    TEMP_W, W
    SUBLW   KEY_5
    BTFSC   STATUS, 2
    GOTO    KD_5
    
    MOVF    TEMP_W, W
    SUBLW   KEY_6
    BTFSC   STATUS, 2
    GOTO    KD_6
    
    MOVF    TEMP_W, W
    SUBLW   KEY_7
    BTFSC   STATUS, 2
    GOTO    KD_7
    
    MOVF    TEMP_W, W
    SUBLW   KEY_8
    BTFSC   STATUS, 2
    GOTO    KD_8
    
    MOVF    TEMP_W, W
    SUBLW   KEY_9
    BTFSC   STATUS, 2
    GOTO    KD_9
    
    MOVLW   0xFF
    MOVWF   TEMP_W
    RETURN

KD_0:
    CLRF    TEMP_W
    RETURN
KD_1:
    MOVLW   1
    MOVWF   TEMP_W
    RETURN
KD_2:
    MOVLW   2
    MOVWF   TEMP_W
    RETURN
KD_3:
    MOVLW   3
    MOVWF   TEMP_W
    RETURN
KD_4:
    MOVLW   4
    MOVWF   TEMP_W
    RETURN
KD_5:
    MOVLW   5
    MOVWF   TEMP_W
    RETURN
KD_6:
    MOVLW   6
    MOVWF   TEMP_W
    RETURN
KD_7:
    MOVLW   7
    MOVWF   TEMP_W
    RETURN
KD_8:
    MOVLW   8
    MOVWF   TEMP_W
    RETURN
KD_9:
    MOVLW   9
    MOVWF   TEMP_W
    RETURN

;==============================================================================
; CONFIRM_INPUT - Validate and save
;==============================================================================
CONFIRM_INPUT:
    banksel DIGIT_COUNT
    MOVF    DIGIT_COUNT, W
    BTFSC   STATUS, 2
    GOTO    REJECT
    
    SUBLW   1
    BTFSC   STATUS, 2
    GOTO    CONF_SINGLE
    
    ; Two digits: value = DIGIT1 * 10 + DIGIT2
    banksel TEMP_DIGIT1
    MOVF    TEMP_DIGIT1, W
    banksel CALC_TEMP
    MOVWF   CALC_TEMP           ; CALC_TEMP = first digit (x)
    
    ; Multiply by 10: x*10 = x*8 + x*2
    ; First calculate x*2 and save it
    BCF     STATUS, 0           ; Clear carry
    RLF     CALC_TEMP, F        ; CALC_TEMP = x*2
    MOVF    CALC_TEMP, W        ; W = x*2
    banksel DELAY_CNT1
    MOVWF   DELAY_CNT1          ; Save x*2
    
    ; Now calculate x*8 (continue from x*2)
    banksel CALC_TEMP
    RLF     CALC_TEMP, F        ; CALC_TEMP = x*4
    RLF     CALC_TEMP, F        ; CALC_TEMP = x*8
    
    ; Add x*2 to get x*10
    banksel DELAY_CNT1
    MOVF    DELAY_CNT1, W       ; W = x*2
    banksel CALC_TEMP
    ADDWF   CALC_TEMP, F        ; CALC_TEMP = x*8 + x*2 = x*10
    
    ; Add second digit
    banksel TEMP_DIGIT2
    MOVF    TEMP_DIGIT2, W
    banksel CALC_TEMP
    ADDWF   CALC_TEMP, F        ; CALC_TEMP = x*10 + second digit
    GOTO    CHECK_RANGE

CONF_SINGLE:
    banksel TEMP_DIGIT1
    MOVF    TEMP_DIGIT1, W
    banksel CALC_TEMP
    MOVWF   CALC_TEMP

CHECK_RANGE:
    ; 10 <= value <= 50
    banksel CALC_TEMP
    MOVF    CALC_TEMP, W
    SUBLW   9
    BTFSC   STATUS, 0
    GOTO    REJECT
    
    banksel CALC_TEMP
    MOVF    CALC_TEMP, W
    SUBLW   50
    BTFSS   STATUS, 0
    GOTO    REJECT
    
    ; Valid - save
    banksel CALC_TEMP
    MOVF    CALC_TEMP, W
    banksel DESIRED_TEMP_INT
    MOVWF   DESIRED_TEMP_INT
    
    banksel TEMP_FRAC
    MOVF    TEMP_FRAC, W
    banksel DESIRED_TEMP_FRAC
    MOVWF   DESIRED_TEMP_FRAC
    
    ; Exit input mode
    banksel INPUT_MODE
    CLRF    INPUT_MODE
    
    ; LEDs
    banksel PORTC
    BCF     PORTC, 3
    BSF     PORTC, 4
    CALL    DELAY_500MS
    BCF     PORTC, 4
    
    ; Show dash
    banksel PORTD
    MOVLW   0x40
    MOVWF   PORTD
    
    CALL    INIT_VARIABLES
    RETURN

REJECT:
    banksel PORTC
    BSF     PORTC, 5
    CALL    DELAY_500MS
    BCF     PORTC, 5
    CALL    DELAY_500MS
    BSF     PORTC, 5
    CALL    DELAY_500MS
    BCF     PORTC, 5
    
    banksel DIGIT_COUNT
    CLRF    DIGIT_COUNT
    CLRF    TEMP_DIGIT1
    CLRF    TEMP_DIGIT2
    CLRF    TEMP_FRAC
    CLRF    HAS_DECIMAL
    
    banksel PORTD
    MOVLW   0x79
    MOVWF   PORTD
    RETURN

;==============================================================================
; DISPLAY_DIGIT
;==============================================================================
DISPLAY_DIGIT:
    banksel TEMP_REG
    MOVWF   TEMP_REG
    
    MOVF    TEMP_REG, W
    SUBLW   0
    BTFSC   STATUS, 2
    GOTO    DD0
    
    MOVF    TEMP_REG, W
    SUBLW   1
    BTFSC   STATUS, 2
    GOTO    DD1
    
    MOVF    TEMP_REG, W
    SUBLW   2
    BTFSC   STATUS, 2
    GOTO    DD2
    
    MOVF    TEMP_REG, W
    SUBLW   3
    BTFSC   STATUS, 2
    GOTO    DD3
    
    MOVF    TEMP_REG, W
    SUBLW   4
    BTFSC   STATUS, 2
    GOTO    DD4
    
    MOVF    TEMP_REG, W
    SUBLW   5
    BTFSC   STATUS, 2
    GOTO    DD5
    
    MOVF    TEMP_REG, W
    SUBLW   6
    BTFSC   STATUS, 2
    GOTO    DD6
    
    MOVF    TEMP_REG, W
    SUBLW   7
    BTFSC   STATUS, 2
    GOTO    DD7
    
    MOVF    TEMP_REG, W
    SUBLW   8
    BTFSC   STATUS, 2
    GOTO    DD8
    
    GOTO    DD9

DD0:
    MOVLW   0x3F
    GOTO    DD_WR
DD1:
    MOVLW   0x06
    GOTO    DD_WR
DD2:
    MOVLW   0x5B
    GOTO    DD_WR
DD3:
    MOVLW   0x4F
    GOTO    DD_WR
DD4:
    MOVLW   0x66
    GOTO    DD_WR
DD5:
    MOVLW   0x6D
    GOTO    DD_WR
DD6:
    MOVLW   0x7D
    GOTO    DD_WR
DD7:
    MOVLW   0x07
    GOTO    DD_WR
DD8:
    MOVLW   0x7F
    GOTO    DD_WR
DD9:
    MOVLW   0x6F

DD_WR:
    banksel PORTD
    MOVWF   PORTD
    RETURN

;==============================================================================
; WAIT_KEY_RELEASE
;==============================================================================
WAIT_KEY_RELEASE:
    CALL    SCAN_KEYPAD
    banksel KEY_VALUE
    MOVLW   KEY_NONE
    SUBWF   KEY_VALUE, W
    BTFSS   STATUS, 2
    GOTO    WAIT_KEY_RELEASE
    RETURN

;==============================================================================
; DEBOUNCE_DELAY
;==============================================================================
DEBOUNCE_DELAY:
    MOVLW   40
    banksel DELAY_CNT1
    MOVWF   DELAY_CNT1
DEB_O:
    MOVLW   250
    MOVWF   DELAY_CNT2
DEB_I:
    NOP
    DECFSZ  DELAY_CNT2, F
    GOTO    DEB_I
    DECFSZ  DELAY_CNT1, F
    GOTO    DEB_O
    RETURN

;==============================================================================
; DELAY_50MS
;==============================================================================
DELAY_50MS:
    MOVLW   100
    banksel DELAY_CNT1
    MOVWF   DELAY_CNT1
D50_O:
    MOVLW   244
    MOVWF   DELAY_CNT2
D50_I:
    DECFSZ  DELAY_CNT2, F
    GOTO    D50_I
    DECFSZ  DELAY_CNT1, F
    GOTO    D50_O
    RETURN

;==============================================================================
; DELAY_5MS - 5ms delay for display multiplexing
;==============================================================================
DELAY_5MS:
    MOVLW   10
    banksel DELAY_CNT1
    MOVWF   DELAY_CNT1
D5MS_O:
    MOVLW   244
    MOVWF   DELAY_CNT2
D5MS_I:
    DECFSZ  DELAY_CNT2, F
    GOTO    D5MS_I
    DECFSZ  DELAY_CNT1, F
    GOTO    D5MS_O
    RETURN

;==============================================================================
; DELAY_500MS
;==============================================================================
DELAY_500MS:
    MOVLW   250
    banksel DELAY_CNT3
    MOVWF   DELAY_CNT3
D5_L1:
    MOVLW   200
    banksel DELAY_CNT1
    MOVWF   DELAY_CNT1
D5_L2:
    MOVLW   10
    MOVWF   DELAY_CNT2
D5_L3:
    NOP
    DECFSZ  DELAY_CNT2, F
    GOTO    D5_L3
    DECFSZ  DELAY_CNT1, F
    GOTO    D5_L2
    banksel DELAY_CNT3
    DECFSZ  DELAY_CNT3, F
    GOTO    D5_L1
    RETURN

;==============================================================================
; UPDATE_DISPLAY - Show values on 4-digit MUX 7-segment [R2.1.3-1]
; Single display: Used for keypad input feedback
; MUX display: Cycles through Desired Temp -> Ambient Temp -> Fan Speed
; Each mode displayed for ~2 seconds
;
; MUX Digit Select Pins:
;   D1 (tens)     -> RE0
;   D2 (ones)     -> RE1
;   D3 (decimal)  -> RE2
;   D4 (fraction) -> RC6
;==============================================================================
UPDATE_DISPLAY:
    ; If in input mode, turn off MUX and return (single display shows keypad)
    banksel INPUT_MODE
    BTFSC   INPUT_MODE, 0
    GOTO    DISABLE_MUX_DISPLAY
    
    ; Increment timer for mode switching (~250 cycles = ~2.5 sec per mode)
    banksel DISPLAY_TIMER
    INCF    DISPLAY_TIMER, F
    
    ; Check if timer reached limit (wrap at 255, switch every ~2.5 sec)
    MOVF    DISPLAY_TIMER, W
    BTFSS   STATUS, 2           ; Z=1 if timer wrapped to 0
    GOTO    PREPARE_MUX_DATA
    
    ; Timer wrapped - switch to next mode
    banksel DISPLAY_MODE
    INCF    DISPLAY_MODE, F
    
    ; Check if mode > 2, reset to 0
    MOVF    DISPLAY_MODE, W
    SUBLW   2
    BTFSS   STATUS, 0
    CLRF    DISPLAY_MODE

PREPARE_MUX_DATA:
    ; Prepare digit values based on current mode
    banksel DISPLAY_MODE
    MOVF    DISPLAY_MODE, W
    
    BTFSC   STATUS, 2           ; Mode 0
    GOTO    PREP_DESIRED_DATA
    
    SUBLW   1
    BTFSC   STATUS, 2           ; Mode 1
    GOTO    PREP_AMBIENT_DATA
    
    ; Mode 2: Fan Speed
    GOTO    PREP_FAN_DATA

PREP_DESIRED_DATA:
    banksel DESIRED_TEMP_INT
    MOVF    DESIRED_TEMP_INT, W
    CALL    CALC_TENS_ONES
    banksel DESIRED_TEMP_FRAC
    MOVF    DESIRED_TEMP_FRAC, W
    banksel MUX_DIGIT3
    MOVWF   MUX_DIGIT3
    GOTO    DO_MUX_DISPLAY

PREP_AMBIENT_DATA:
    banksel AMBIENT_TEMP_INT
    MOVF    AMBIENT_TEMP_INT, W
    CALL    CALC_TENS_ONES
    banksel AMBIENT_TEMP_FRAC
    MOVF    AMBIENT_TEMP_FRAC, W
    banksel MUX_DIGIT3
    MOVWF   MUX_DIGIT3
    GOTO    DO_MUX_DISPLAY

PREP_FAN_DATA:
    banksel FAN_SPEED
    MOVF    FAN_SPEED, W
    CALL    CALC_TENS_ONES
    banksel MUX_DIGIT3
    CLRF    MUX_DIGIT3          ; No fraction for fan speed
    GOTO    DO_MUX_DISPLAY

;----------------------------------------------------------------------
; CALC_TENS_ONES - Calculate tens and ones digits
; Input: W = value to split
; Output: MUX_DIGIT0 = tens, MUX_DIGIT1 = ones, MUX_DIGIT2 = 10 (decimal indicator)
;----------------------------------------------------------------------
CALC_TENS_ONES:
    banksel TEMP_REG
    MOVWF   TEMP_REG
    CLRF    MUX_DIGIT0          ; Tens digit
    
    ; Divide by 10 to get tens
CTO_DIV10:
    MOVLW   10
    SUBWF   TEMP_REG, W
    BTFSS   STATUS, 0           ; C=0 if < 10
    GOTO    CTO_DIV10_DONE
    MOVWF   TEMP_REG
    INCF    MUX_DIGIT0, F
    GOTO    CTO_DIV10

CTO_DIV10_DONE:
    ; TEMP_REG now has ones digit
    MOVF    TEMP_REG, W
    banksel MUX_DIGIT1
    MOVWF   MUX_DIGIT1          ; Ones digit
    
    MOVLW   10                  ; Special value for decimal point
    MOVWF   MUX_DIGIT2
    
    RETURN

;----------------------------------------------------------------------
; DO_MUX_DISPLAY - Multiplex the 4 digits (one per call)
;----------------------------------------------------------------------
DO_MUX_DISPLAY:
    ; Turn off all digits first
    banksel PORTE
    CLRF    PORTE
    banksel PORTC
    BCF     PORTC, 6
    
    ; Increment current digit (0->1->2->3->0...)
    banksel CURRENT_DIGIT
    INCF    CURRENT_DIGIT, F
    MOVF    CURRENT_DIGIT, W
    SUBLW   3
    BTFSS   STATUS, 0           ; C=0 if > 3
    CLRF    CURRENT_DIGIT       ; Reset to 0
    
    ; Display current digit
    banksel CURRENT_DIGIT
    MOVF    CURRENT_DIGIT, W
    
    BTFSC   STATUS, 2           ; Digit 0?
    GOTO    DISPLAY_MUX_D0
    
    SUBLW   1
    BTFSC   STATUS, 2           ; Digit 1?
    GOTO    DISPLAY_MUX_D1
    
    banksel CURRENT_DIGIT
    MOVF    CURRENT_DIGIT, W
    SUBLW   2
    BTFSC   STATUS, 2           ; Digit 2?
    GOTO    DISPLAY_MUX_D2
    
    ; Digit 3
    GOTO    DISPLAY_MUX_D3

DISPLAY_MUX_D0:
    ; Tens digit on D1 (RE0)
    banksel MUX_DIGIT0
    MOVF    MUX_DIGIT0, W
    CALL    GET_SEGMENT_CODE
    banksel PORTD
    MOVWF   PORTD
    banksel PORTE
    BSF     PORTE, 0            ; Enable D1
    RETURN

DISPLAY_MUX_D1:
    ; Ones digit on D2 (RE1) with decimal point
    banksel MUX_DIGIT1
    MOVF    MUX_DIGIT1, W
    CALL    GET_SEGMENT_CODE
    IORLW   0x80                ; Add decimal point
    banksel PORTD
    MOVWF   PORTD
    banksel PORTE
    BSF     PORTE, 1            ; Enable D2
    RETURN

DISPLAY_MUX_D2:
    ; Fraction digit on D3 (RE2)
    banksel MUX_DIGIT3
    MOVF    MUX_DIGIT3, W
    CALL    GET_SEGMENT_CODE
    banksel PORTD
    MOVWF   PORTD
    banksel PORTE
    BSF     PORTE, 2            ; Enable D3
    RETURN

DISPLAY_MUX_D3:
    ; Show mode indicator on D4 (RC6): d=desired, A=ambient, F=fan
    banksel DISPLAY_MODE
    MOVF    DISPLAY_MODE, W
    
    BTFSC   STATUS, 2           ; Mode 0 = d
    GOTO    SHOW_MODE_D
    
    SUBLW   1
    BTFSC   STATUS, 2           ; Mode 1 = A
    GOTO    SHOW_MODE_A
    
    ; Mode 2 = F
    MOVLW   0x71                ; F
    GOTO    WRITE_MODE_DIGIT

SHOW_MODE_D:
    MOVLW   0x5E                ; d
    GOTO    WRITE_MODE_DIGIT

SHOW_MODE_A:
    MOVLW   0x77                ; A
    GOTO    WRITE_MODE_DIGIT

WRITE_MODE_DIGIT:
    banksel PORTD
    MOVWF   PORTD
    banksel PORTC
    BSF     PORTC, 6            ; Enable D4
    RETURN

;----------------------------------------------------------------------
; DISABLE_MUX_DISPLAY - Turn off MUX display during input mode
;----------------------------------------------------------------------
DISABLE_MUX_DISPLAY:
    banksel PORTE
    CLRF    PORTE               ; All digit selects off
    banksel PORTC
    BCF     PORTC, 6            ; D4 off
    RETURN

;==============================================================================
; UART Communication Functions
;==============================================================================

;------------------------------------------------------------------------------
; UART_SEND_BYTE - Send one byte via UART
; Input: W = byte to send
;------------------------------------------------------------------------------
UART_SEND_BYTE:
    banksel TXREG
    MOVWF   TXREG               ; Write to transmit register
    
    ; Wait for transmission to complete (check TXIF flag in PIR1)
UART_WAIT:
    banksel PIR1
    BTFSS   PIR1, 4             ; Check if TXIF=1 (bit 4 of PIR1)
    GOTO    UART_WAIT
    
    RETURN

;------------------------------------------------------------------------------
; SEND_UART_MESSAGE - Send test message "D:25.0,A:22.5,F:50\r\n"
;------------------------------------------------------------------------------
SEND_UART_MESSAGE:
    MOVLW   'D'
    CALL    UART_SEND_BYTE
    MOVLW   ':'
    CALL    UART_SEND_BYTE
    MOVLW   '2'
    CALL    UART_SEND_BYTE
    MOVLW   '5'
    CALL    UART_SEND_BYTE
    MOVLW   '.'
    CALL    UART_SEND_BYTE
    MOVLW   '0'
    CALL    UART_SEND_BYTE
    MOVLW   ','
    CALL    UART_SEND_BYTE
    MOVLW   'A'
    CALL    UART_SEND_BYTE
    MOVLW   ':'
    CALL    UART_SEND_BYTE
    MOVLW   '2'
    CALL    UART_SEND_BYTE
    MOVLW   '2'
    CALL    UART_SEND_BYTE
    MOVLW   '.'
    CALL    UART_SEND_BYTE
    MOVLW   '5'
    CALL    UART_SEND_BYTE
    MOVLW   ','
    CALL    UART_SEND_BYTE
    MOVLW   'F'
    CALL    UART_SEND_BYTE
    MOVLW   ':'
    CALL    UART_SEND_BYTE
    MOVLW   '5'
    CALL    UART_SEND_BYTE
    MOVLW   '0'
    CALL    UART_SEND_BYTE
    MOVLW   0x0D                ; CR
    CALL    UART_SEND_BYTE
    MOVLW   0x0A                ; LF
    CALL    UART_SEND_BYTE
    RETURN

;------------------------------------------------------------------------------
; CHECK_UART_COMMAND - Check if UART data received and process
;------------------------------------------------------------------------------
CHECK_UART_COMMAND:
    banksel PIR1
    BTFSS   PIR1, 5             ; Check RCIF (bit 5) - receive flag
    RETURN                      ; No data, return
    
    ; Data received, read it
    banksel RCREG
    MOVF    RCREG, W            ; Read byte (clears RCIF)
    banksel TEMP_W
    MOVWF   TEMP_W              ; Save command
    
    ; Check SET commands FIRST (0x80-0xBF and 0xC0-0xFF)
    ; Check if W >= 0x80
    banksel TEMP_W
    MOVF    TEMP_W, W
    SUBLW   0x7F                ; 0x7F - W, C=1 if W <= 0x7F
    BTFSC   STATUS, 0           ; Skip if C=0 (W > 0x7F)
    GOTO    CHECK_GET_CMDS      ; W <= 0x7F, check GET commands
    
    ; W >= 0x80, check which SET range
    banksel TEMP_W
    MOVF    TEMP_W, W
    SUBLW   0xBF                ; 0xBF - W, C=1 if W <= 0xBF
    BTFSC   STATUS, 0           ; C=1 if W <= 0xBF
    GOTO    CMD_SET_DESIRED_FRAC ; 0x80 <= W <= 0xBF (10xxxxxx)
    
    ; W > 0xBF (W >= 0xC0), it's SET INT
    GOTO    CMD_SET_DESIRED_INT ; 0xC0 <= W <= 0xFF (11xxxxxx)

CHECK_GET_CMDS:
    ; Check GET commands (0x01-0x05)
    banksel TEMP_W
    MOVLW   0x01
    SUBWF   TEMP_W, W
    BTFSC   STATUS, 2           ; Z=1 if cmd = 0x01
    GOTO    CMD_GET_DESIRED_FRAC
    
    MOVLW   0x02
    banksel TEMP_W
    SUBWF   TEMP_W, W
    BTFSC   STATUS, 2
    GOTO    CMD_GET_DESIRED_INT
    
    MOVLW   0x03
    banksel TEMP_W
    SUBWF   TEMP_W, W
    BTFSC   STATUS, 2
    GOTO    CMD_GET_AMBIENT_FRAC
    
    MOVLW   0x04
    banksel TEMP_W
    SUBWF   TEMP_W, W
    BTFSC   STATUS, 2
    GOTO    CMD_GET_AMBIENT_INT
    
    MOVLW   0x05
    banksel TEMP_W
    SUBWF   TEMP_W, W
    BTFSC   STATUS, 2
    GOTO    CMD_GET_FAN_SPEED
    
    RETURN                      ; Unknown command

CMD_GET_DESIRED_FRAC:
    banksel DESIRED_TEMP_FRAC
    MOVF    DESIRED_TEMP_FRAC, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_GET_DESIRED_INT:
    banksel DESIRED_TEMP_INT
    MOVF    DESIRED_TEMP_INT, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_GET_AMBIENT_FRAC:
    banksel AMBIENT_TEMP_FRAC
    MOVF    AMBIENT_TEMP_FRAC, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_GET_AMBIENT_INT:
    banksel AMBIENT_TEMP_INT
    MOVF    AMBIENT_TEMP_INT, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_GET_FAN_SPEED:
    banksel FAN_SPEED
    MOVF    FAN_SPEED, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_SET_DESIRED_FRAC:
    banksel TEMP_W
    MOVF    TEMP_W, W
    ANDLW   0x3F                ; Extract lower 6 bits (0-63)
    banksel DESIRED_TEMP_FRAC
    MOVWF   DESIRED_TEMP_FRAC
    RETURN

CMD_SET_DESIRED_INT:
    banksel TEMP_W
    MOVF    TEMP_W, W
    ANDLW   0x3F                ; Extract lower 6 bits (0-63)
    
    ; Check if value >= 10
    SUBLW   9                   ; 9 - W, C=0 if W > 9
    BTFSC   STATUS, 0           ; C=1 means W <= 9
    RETURN                      ; Reject: W < 10
    
    ; Check if value <= 50
    banksel TEMP_W
    MOVF    TEMP_W, W
    ANDLW   0x3F
    SUBLW   50                  ; 50 - W, C=1 if W <= 50
    BTFSS   STATUS, 0           ; C=0 means W > 50
    RETURN                      ; Reject: W > 50
    
    ; Value is valid (10-50), save it
    banksel TEMP_W
    MOVF    TEMP_W, W
    ANDLW   0x3F
    banksel DESIRED_TEMP_INT
    MOVWF   DESIRED_TEMP_INT
    RETURN

;----------------------------------------------------------------------
; GET_SEGMENT_CODE - Convert digit to 7-segment code
; Input: W = digit (0-9)
; Output: W = segment pattern
;----------------------------------------------------------------------
GET_SEGMENT_CODE:
    banksel TEMP_W
    MOVWF   TEMP_W
    
    MOVF    TEMP_W, W
    SUBLW   0
    BTFSC   STATUS, 2
    RETLW   0x3F                ; 0
    
    MOVF    TEMP_W, W
    SUBLW   1
    BTFSC   STATUS, 2
    RETLW   0x06                ; 1
    
    MOVF    TEMP_W, W
    SUBLW   2
    BTFSC   STATUS, 2
    RETLW   0x5B                ; 2
    
    MOVF    TEMP_W, W
    SUBLW   3
    BTFSC   STATUS, 2
    RETLW   0x4F                ; 3
    
    MOVF    TEMP_W, W
    SUBLW   4
    BTFSC   STATUS, 2
    RETLW   0x66                ; 4
    
    MOVF    TEMP_W, W
    SUBLW   5
    BTFSC   STATUS, 2
    RETLW   0x6D                ; 5
    
    MOVF    TEMP_W, W
    SUBLW   6
    BTFSC   STATUS, 2
    RETLW   0x7D                ; 6
    
    MOVF    TEMP_W, W
    SUBLW   7
    BTFSC   STATUS, 2
    RETLW   0x07                ; 7
    
    MOVF    TEMP_W, W
    SUBLW   8
    BTFSC   STATUS, 2
    RETLW   0x7F                ; 8
    
    RETLW   0x6F                ; 9

    END
