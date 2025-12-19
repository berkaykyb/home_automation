;====================================================================
; Proje: Board #1 (Ev Tipi Klima) - FIX v4.0 (CRASH FIX)
;====================================================================

    list p=16f877a
    #include <p16f877a.inc>
    
    ; Bank uyar?s?n? gizle
    errorlevel -302

    ; Konfigürasyon: HS Osilatör, WDT Kapal?
    __CONFIG _FOSC_HS & _WDTE_OFF & _PWRTE_ON & _BOREN_ON & _LVP_OFF & _CPD_OFF & _WRT_OFF & _CP_OFF

;====================================================================
; DE???KENLER
;====================================================================
    CBLOCK 0x20
        ; Interrupt De?i?kenleri (BUNLARA MAIN'DE DOKUNMA!)
        w_temp, status_temp
        
        ; Program De?i?kenleri
        des_temp_int, des_temp_frac      ; ?stenen S?cakl?k
        amb_temp_int, amb_temp_frac      ; Ortam S?cakl???
        fan_speed_rps                    ; Fan H?z?
        adc_val_L, adc_val_H             ; ADC Okuma
        disp_digit_1, disp_digit_2       ; Ekran Haneleri
        disp_digit_3, disp_digit_4
        digit_scan_idx, disp_mode, timer0_cnt
        key_state, key_pressed           ; Keypad De?i?kenleri
        temp_input_int, temp_input_frac
        uart_data, bcd_tens, bcd_ones
        bcd_hund
    ENDC

    ORG 0x000
    goto Main
    ORG 0x004
    goto ISR_Handler

;====================================================================
; ANA PROGRAM
;====================================================================
Main:
    call Init_Ports
    call Init_ADC
    call Init_Timers
    call Init_UART
    
    ; Varsay?lan S?cakl?k: 25.0 C
    movlw d'25'
    movwf des_temp_int
    clrf des_temp_frac
    
    clrf disp_mode
    clrf key_state
    
    bsf INTCON, GIE      ; Kesmeleri Aç
    bsf INTCON, PEIE

Loop:
    call Read_Ambient_Temp    ; Sensörü Oku
    call Control_HVAC         ; Klima Kontrolü
    call Prepare_Display_Data ; Ekrana ne yaz?lacak?
    call Keypad_Scanner       ; Tu? Tak?m? Tara
    goto Loop

;====================================================================
; KESME (INTERRUPT) RUT?N?
;====================================================================
ISR_Handler:
    movwf w_temp        ; W'yi sakla
    swapf STATUS, W
    movwf status_temp   ; Status'u sakla

    ; Timer0 Kesmesi (Ekran Tarama)
    btfss INTCON, T0IF
    goto Check_UART
    
    call Refresh_Display
    call Time_Keeper
    bcf INTCON, T0IF

Check_UART:
    btfss PIR1, RCIF
    goto ISR_Exit
    call UART_Handler

ISR_Exit:
    swapf status_temp, W
    movwf STATUS        ; Status'u geri al
    swapf w_temp, F
    swapf w_temp, W     ; W'yi geri al (Burada w_temp kullan?lmas? do?ru)
    retfie

;====================================================================
; AYARLAR (INITIALIZATION)
;====================================================================
Init_Ports:
    bsf STATUS, RP0     ; Bank 1
    clrf TRISD          ; PORTD Ç?k?? (Segmentler)
    clrf TRISE          ; PORTE Ç?k?? (D1, D2, D3)
    bcf TRISA, 5        ; RA5 Ç?k?? (D4)
    movlw 0xF0          
    movwf TRISB         ; Keypad (RB4-7 Giris, RB0-3 Cikis)
    bcf TRISC, 2        ; Heater Output
    bcf TRISC, 5        ; Cooler Output
    bsf TRISC, 0        ; Tach Input
    bsf TRISC, 7        ; RX Input
    bcf TRISC, 6        ; TX Output
    bcf STATUS, RP0     ; Bank 0
    return

Init_ADC:
    bsf STATUS, RP0
    ; -----------------------------------------------------------
    ; KR?T?K AYAR: b'10001110' (0x8E)
    ; -----------------------------------------------------------
    movlw b'10001110'   
    movwf ADCON1
    bcf STATUS, RP0
    movlw b'01000001'   ; ADC Aç?k, Kanal 0
    movwf ADCON0
    return

Init_Timers:
    bsf STATUS, RP0
    movlw b'00000100'   ; Pull-up AÇIK, Prescaler 1:32
    movwf OPTION_REG
    bcf STATUS, RP0
    bsf INTCON, T0IE
    movlw b'00000111'   ; Timer1 Aç?k (Tach için)
    movwf T1CON
    return

Init_UART:
    bsf STATUS, RP0
    movlw d'25'         ; 9600 Baud @ 4MHz
    movwf SPBRG
    bsf TXSTA, TXEN
    bsf TXSTA, BRGH
    bcf STATUS, RP0
    bsf RCSTA, SPEN
    bsf RCSTA, CREN
    bsf PIE1, RCIE
    return

;====================================================================
; EKRAN TARAMA
;====================================================================
Refresh_Display:
    ; Önce tüm digitleri kapat
    bcf PORTE, 0
    bcf PORTE, 1
    bcf PORTE, 2
    bcf PORTA, 5
    
    ; S?radaki haneye geç
    incf digit_scan_idx, F
    movf digit_scan_idx, W
    andlw b'00000011'   ; 0-3 aras? döngü
    movwf digit_scan_idx
    
    movf digit_scan_idx, W
    sublw d'0'
    btfsc STATUS, Z
    goto Show_D1
    movf digit_scan_idx, W
    sublw d'1'
    btfsc STATUS, Z
    goto Show_D2
    movf digit_scan_idx, W
    sublw d'2'
    btfsc STATUS, Z
    goto Show_D3
    goto Show_D4

Show_D1:
    movf disp_digit_1, W
    call Get_Seg
    movwf PORTD
    bsf PORTE, 0
    return
Show_D2:
    movf disp_digit_2, W
    call Get_Seg
    btfss disp_mode, 1  ; E?er disp_mode=2 (Fan) ise nokta koyma
    iorlw b'10000000'   ; De?ilse nokta koy
    movwf PORTD
    bsf PORTE, 1
    return
Show_D3:
    movf disp_digit_3, W
    call Get_Seg
    movwf PORTD
    bsf PORTE, 2
    return
Show_D4:
    movf disp_digit_4, W
    call Get_Seg
    movwf PORTD
    bsf PORTA, 5
    return

;====================================================================
; YARDIMCI FONKS?YONLAR
;====================================================================
Get_Seg: 
    andlw 0x0F
    addwf PCL, F
    retlw b'00111111' ; 0
    retlw b'00000110' ; 1
    retlw b'01011011' ; 2
    retlw b'01001111' ; 3
    retlw b'01100110' ; 4
    retlw b'01101101' ; 5
    retlw b'01111101' ; 6
    retlw b'00000111' ; 7
    retlw b'01111111' ; 8
    retlw b'01101111' ; 9
    retlw b'01110111' ; A
    retlw b'01111100' ; b
    retlw b'00111001' ; C
    retlw b'01011110' ; d
    retlw b'01111001' ; E
    retlw b'01110001' ; F

Prepare_Display_Data:
    movf disp_mode, W
    sublw d'0'
    btfsc STATUS, Z
    goto P_Des
    movf disp_mode, W
    sublw d'1'
    btfsc STATUS, Z
    goto P_Amb
    goto P_Fan

P_Des:
    movf des_temp_int, W
    call Bin2BCD
    movf bcd_tens, W
    movwf disp_digit_1
    movf bcd_ones, W
    movwf disp_digit_2
    movf des_temp_frac, W
    movwf disp_digit_3
    movlw d'12' ; 'C'
    movwf disp_digit_4
    return
P_Amb:
    movf amb_temp_int, W
    call Bin2BCD
    movf bcd_tens, W
    movwf disp_digit_1
    movf bcd_ones, W
    movwf disp_digit_2
    movf amb_temp_frac, W
    movwf disp_digit_3
    movlw d'10' ; 'A'
    movwf disp_digit_4
    return
P_Fan:
    movf fan_speed_rps, W
    call Bin2BCD
    movlw d'15' ; F
    movwf disp_digit_1
    movf bcd_hund, W
    movwf disp_digit_2
    movf bcd_tens, W
    movwf disp_digit_3
    movf bcd_ones, W
    movwf disp_digit_4
    return

Bin2BCD:
    movwf bcd_ones      ; Say?y? al
    clrf bcd_tens
    clrf bcd_hund       ; Yüzleri s?f?rla
BCD_Hund_Loop:
    movlw d'100'
    subwf bcd_ones, W
    btfss STATUS, C
    goto BCD_Tens_Loop
    movwf bcd_ones
    incf bcd_hund, F
    goto BCD_Hund_Loop
BCD_Tens_Loop:
    movlw d'10'
    subwf bcd_ones, W
    btfss STATUS, C
    return
    movwf bcd_ones
    incf bcd_tens, F
    goto BCD_Tens_Loop

Control_HVAC:
    ; 1. Tam Say? K?yaslamas?
    movf amb_temp_int, W
    subwf des_temp_int, W
    btfss STATUS, C     ; Des < Amb
    goto Cool
    btfss STATUS, Z     ; Des > Amb
    goto Heat
    
    ; 2. Tam say?lar E??T ise (Örn: ?stenen 35.8, Ortam 35.5)
    ; Sistemi "Dengede" kabul et ve ikisini de kapat.
    ; Bu sayede 35.5 ile 36.0 aras?nda z?plama yapmaz.
    goto All_Off

Heat:
    bsf PORTC, 2        ; Is?t?c? AÇ
    bcf PORTC, 5        ; So?utucu KAPAT
    return

Cool:
    bcf PORTC, 2        ; Is?t?c? KAPAT
    bsf PORTC, 5        ; So?utucu AÇ
    return

All_Off:
    bcf PORTC, 2        ; Is?t?c? KAPAT
    bcf PORTC, 5        ; So?utucu KAPAT
    return

Read_Ambient_Temp:
    bsf ADCON0, GO
Wait_ADC:
    btfsc ADCON0, GO
    goto Wait_ADC
    bsf STATUS, RP0
    movf ADRESL, W
    bcf STATUS, RP0
    movwf adc_val_L
    movf ADRESH, W
    movwf adc_val_H
    bcf STATUS, C
    rrf adc_val_L, F
    movf adc_val_L, W
    movwf amb_temp_int
    clrf amb_temp_frac
    btfsc STATUS, C
    movlw d'5'
    btfsc STATUS, C
    movwf amb_temp_frac
    return

Time_Keeper:
    incf timer0_cnt, F
    movlw d'125'
    subwf timer0_cnt, W
    btfss STATUS, Z
    return
    clrf timer0_cnt
    movf TMR1L, W
    movwf fan_speed_rps
    clrf TMR1L
    clrf TMR1H
    incf disp_mode, F
    movlw d'3'
    subwf disp_mode, W
    btfsc STATUS, Z
    clrf disp_mode
    return

UART_Handler:
    movf RCREG, W
    movwf uart_data
    return

;====================================================================
; KEYPAD TARAMA - BEKLEMEL? YÖNTEM (Ç?FT YAZMAYI VE ÇÖKMEY? ENGELLER)
;====================================================================
; BURADAK? DE????KL?K SAYES?NDE ARTIK "3"E BASINCA "33" YAZMAYACAK.
; AYRICA w_temp KULLANILMADI?I ?Ç?N S?STEM RESET YEMEYECEK.
;====================================================================

Keypad_Scanner:
    ; --- Sütun 1 ---
    bcf PORTB, 1
    bsf PORTB, 2
    bsf PORTB, 3
    bsf PORTB, 0
    btfss PORTB, 4
    call Key_1
    btfss PORTB, 5
    call Key_4
    btfss PORTB, 6
    call Key_7
    btfss PORTB, 7
    call Key_Star
    
    ; --- Sütun 2 ---
    bsf PORTB, 1
    bcf PORTB, 2
    bsf PORTB, 3
    bsf PORTB, 0
    btfss PORTB, 4
    call Key_2
    btfss PORTB, 5
    call Key_5
    btfss PORTB, 6
    call Key_8
    btfss PORTB, 7
    call Key_0
    
    ; --- Sütun 3 ---
    bsf PORTB, 1
    bsf PORTB, 2
    bcf PORTB, 3
    bsf PORTB, 0
    btfss PORTB, 4
    call Key_3
    btfss PORTB, 5
    call Key_6
    btfss PORTB, 6
    call Key_9
    btfss PORTB, 7
    call Key_Hash
    
    ; --- Sütun 4 (A Tu?u) ---
    bsf PORTB, 1
    bsf PORTB, 2
    bsf PORTB, 3
    bcf PORTB, 0
    btfss PORTB, 4
    call Key_A
    return

; --- TU? ??LEMLER? (VE TU? BIRAKILANA KADAR BEKLEME) ---

Key_1: movlw d'1' 
       call Process_Digit
       goto Wait_Release_Row1
Key_2: movlw d'2'
       call Process_Digit
       goto Wait_Release_Row1
Key_3: movlw d'3'
       call Process_Digit
       goto Wait_Release_Row1

Key_4: movlw d'4'
       call Process_Digit
       goto Wait_Release_Row2
Key_5: movlw d'5'
       call Process_Digit
       goto Wait_Release_Row2
Key_6: movlw d'6'
       call Process_Digit
       goto Wait_Release_Row2
       
Key_7: movlw d'7'
       call Process_Digit
       goto Wait_Release_Row3
Key_8: movlw d'8'
       call Process_Digit
       goto Wait_Release_Row3
Key_9: movlw d'9'
       call Process_Digit
       goto Wait_Release_Row3

Key_0: movlw d'0'
       call Process_Digit
       goto Wait_Release_Row4
       
Key_A: 
    clrf temp_input_int
    clrf temp_input_frac
    movlw d'1'
    movwf key_state
    goto Wait_Release_Row1

Key_Star:
    movlw d'3'
    movwf key_state
    goto Wait_Release_Row4

Key_Hash:
    movlw d'10'
    subwf temp_input_int, W
    btfss STATUS, C
    goto Hash_Exit ; <10 ise ç?k
    movlw d'50'
    subwf temp_input_int, W
    btfsc STATUS, C
    goto Hash_Exit ; >=50 ise ç?k
    ; Kaydet
    movf temp_input_int, W
    movwf des_temp_int
    movf temp_input_frac, W
    movwf des_temp_frac
Hash_Exit:
    clrf key_state
    goto Wait_Release_Row4

; --- RAKAM ??LEME (Senin kodunla ayn?) ---
Process_Digit:
    movwf key_pressed
    movf key_state, W
    sublw d'1'
    btfsc STATUS, Z
    goto Do_Tens
    movf key_state, W
    sublw d'2'
    btfsc STATUS, Z
    goto Do_Ones
    movf key_state, W
    sublw d'3'
    btfsc STATUS, Z
    goto Do_Frac
    return

Do_Tens:
    movf key_pressed, W
    movwf temp_input_int
    movlw d'2'
    movwf key_state
    return
Do_Ones:
    movf temp_input_int, W
    movwf bcd_tens
    bcf STATUS, C
    rlf bcd_tens, F
    rlf bcd_tens, F
    addwf bcd_tens, F
    rlf bcd_tens, F
    movf key_pressed, W
    addwf bcd_tens, W
    movwf temp_input_int
    movlw d'3'
    movwf key_state
    return
Do_Frac:
    movf key_pressed, W
    movwf temp_input_frac
    return

; --- BEKLEME DÖNGÜLER? (BU SAYEDE Ç?FT YAZMAZ) ---
Wait_Release_Row1:
    btfss PORTB, 4     
    goto Wait_Release_Row1
    return
Wait_Release_Row2:
    btfss PORTB, 5
    goto Wait_Release_Row2
    return
Wait_Release_Row3:
    btfss PORTB, 6
    goto Wait_Release_Row3
    return
Wait_Release_Row4:
    btfss PORTB, 7
    goto Wait_Release_Row4
    return

    END