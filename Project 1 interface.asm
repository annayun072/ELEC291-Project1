$MOD9351

  TIMER0_RELOAD_L DATA 0xf2
  TIMER1_RELOAD_L DATA 0xf3
  TIMER0_RELOAD_H DATA 0xf4
  TIMER1_RELOAD_H DATA 0xf5

  XTAL EQU 7373000
  BAUD EQU 115200
  BRVAL EQU ((XTAL/BAUD)-16)


  ;---------------;
  ;  Constants    ;
  ;---------------;
  CLK           EQU 14746000 ; Microcontroller system crystal frequency in Hz
  TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
  TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
  TIMER1_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
  TIMER1_RELOAD EQU ((65536-(CLK/TIMER1_RATE)))


  ; Reset vector
  org 0x0000
      ljmp main

  ; External interrupt 0 vector (not used in this code)
  org 0x0003
    reti

  ; Timer/Counter 0 overflow interrupt vector
  org 0x000B
    ljmp Timer0_ISR

  ; External interrupt 1 vector (not used in this code)
  org 0x0013
    reti

  ; Timer/Counter 1 overflow interrupt vector (not used in this code)
  org 0x001B
    reti

  ; Serial port receive/transmit interrupt vector (not used in this code)
  org 0x0023 
    reti

  ; Timer/Counter 2 overflow interrupt vector
  org 0x002B
    ljmp Timer1_ISR

  ; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
  dseg at 0x30
  Count1ms:     	ds 2; Used to determine when half second has passed
  BCD_counter: 		ds 1; The BCD counter incrememted in the ISR and displayed in the main loop
  cold_temp: 		ds 1;
  hot_temp:			ds 1;

  Reflow_time:		ds 2;
  Reflow_temp:		ds 2;
  Soak_time:		ds 2;
  Soak_temp:		ds 2;

  Mode_sel:     	ds 2;
  state:			ds 1;
  sec:				ds 2;
  temp:				ds 1;

  ReflowTemp_UB:	ds 2;
  ReflowTemp_LB:	ds 2;
  ReflowTime_UB:	ds 2;
  ReflowTime_LB:	ds 2;
  SoakTemp_UB:		ds 2;
  SoakTemp_LB:		ds 2;
  SoakTime_UB:		ds 2;
  SoakTime_LB:		ds 2;
  pwm:				ds 7;

  Result: 			ds 2;
  x:				ds 4;
  y:				ds 4;
  bcd:				ds 5;


  ; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
  ; instructions with these variables.  This is how you define a 1-bit variable:
  bseg
  error_flag:       dbit 1 ; Set to one in the ISR every time 1000 ms had passed 
  speak_flag:       dbit 1 ;
  activation_flag:  dbit 1 ;
  soaking_flag:     dbit 1 ;
  rampUp_flag:      dbit 1 ;
  reflow_flag:      dbit 1 ;
  coolDown_flag:    dbit 1 ;
  finished_flag:    dbit 1 ;
  one_seconds_flag:	dbit 1 ;
  PB0:        		dbit 1 ;time inc
  PB1:				dbit 1 ;time dec
  PB2:				dbit 1 ;temp inc
  PB3:				dbit 1 ;temp dec
  PB4:				dbit 1 ;increment mode from continueReflowSetting
  PB5:				dbit 1 ;increment mode from continueSoakSetting
  PB6:				dbit 1 ;start button 
  mf:				dbit 1 ;

  cseg
  ;CE_ADC    EQU  P2.0 
  ;MY_MOSI   EQU  P2.1  
  ;MY_MISO   EQU  P2.2 
  ;MY_SCLK   EQU  P2.3 

  ;----------------;
  ;button variables;
  ;----------------;
  ;BLUE_LED 			equ P0.0
  RED_LED  			equ P0.1
  ORAGN_LED 		equ P0.2
  YELLOW_LED 		equ P0.3
  SOUND_LONGGREEN 	equ P0.4

  LCD_RS equ P0.5
  LCD_RW equ P0.6
  LCD_E  equ P0.7
  LCD_D4 equ P3.0
  LCD_D5 equ P3.1
  LCD_D6 equ P1.2
  LCD_D7 equ P1.3

  ;ADC_7PB				equ P1.7
  MODE_BUTTON    		equ P1.6 ;mode
  ;OP_VOUT				equ P1.4 ;for temp
  OVEN					equ P2.0
  ALARM					equ P2.1
  SOUND_OUT				EQU P2.7


  $NOLIST
  $include(LCD_4bit_LPC9351.inc) ; A library of LCD related functions and utility macros
  $include(math32.inc)
  $include(macros.inc)
  $LIST

  ;                    	1234567890123456    <- This helps determine the location of the counter
  DONEZO: 			db 'd o n e .', 0
  Select_Language:	db 'Select language:', 0
  Error:			db 'ERROR', 0
  Time:				db 'Time:', 0

  TP:				db 'Tp:', 0
  Celsius:			db 'C', 0  
  ReflowMessage:	db 'Reflow Settings:', 0

  ConfirmStart:		db 'Begin?', 0
  blank:			db '     ', 0
  ;rfl, sk, rps, rpp, coo

  Activation: 		db 'ACTIVATION', 0
  Ramp_Up:			db 'RAMP UP', 0
  Soaking: 			db 'SOAKING', 0
  Reflow:			db 'REFLOW'
  Cool_Down:		db 'COOL DOWN', 0

  ;                     1234567890123456    <- This helps determine the location of the counter
  Initial_Message:  db 'Welcome! To cont', 0
  ToContinueClick:  db 'pls click mode  ', 0

  SoakMessage:      db 'Soak Settings:  ', 0
  OvenDisplay:      db 't=   s tmp=    C', 0
  OvenDisplay2:     db 'st:    otmp=   C', 0
  RPS:				db 'rps', 0
  SK:				db 'sk', 0
  HexAscii: 		db '0123456789ABCDEF'



  ;---------------------------------;
  ; Routine to initialize the ISR   ;
  ; for timer 0                     ;
  ;---------------------------------;
  Timer0_Init:
    mov a, TMOD
    anl a, #0xf0 ; Clear the bits for timer 0
    orl a, #0x01 ; Configure timer 0 as 16-timer
    mov TMOD, a
    mov TH0, #high(TIMER0_RELOAD)
    mov TL0, #low(TIMER0_RELOAD)
    ; Set autoreload value
    mov TIMER0_RELOAD_H, #high(TIMER0_RELOAD)
    mov TIMER0_RELOAD_L, #low(TIMER0_RELOAD)
    ; Enable the timer and interrupts
        clr ET0  ; Enable timer 0 interrupt
        setb TR0  ; Start timer 0
    ret

  ;---------------------------------;
  ; ISR for timer 0.  Set to execute;
  ; every 1/4096Hz to generate a    ;
  ; 2048 Hz square wave at pin P3.7 ;
  ;---------------------------------;
  Timer0_ISR:
    cpl SOUND_OUT ; Connect speaker to P3.7!
    jnb error_flag, notOn
      reti
  notOn:
    clr SOUND_OUT
    reti
  ;---------------------------------;
  ; Routine to initialize the ISR   ;
  ; for timer 1                     ;
  ;---------------------------------;

  Timer1_Init:
    mov a, TMOD
    anl a, #0x0f ; Clear the bits for timer 1
    orl a, #0x10 ; Configure timer 1 as 16-timer
    mov TMOD, a
    mov TH1, #high(TIMER1_RELOAD)
    mov TL1, #low(TIMER1_RELOAD)
    
    mov Count1ms+0, #0
    mov Count1ms+1, #0
    clr one_seconds_flag
    
    ; Enable the timer and interrupts
    setb ET1  ; Enable timer 0 interrupt
    setb TR1  ; Start timer 0
    ret
  ;---------------------------------;
  ; ISR for timer 1                 ;
  ;---------------------------------;
  Timer1_ISR:
    clr TF1  ; Timer 2 doesn't clear TF1 automatically. Do it in ISR

    ; The two registers used in the ISR must be saved in the stack
    push acc
    push psw

    ; Increment the 16-bit one mili second counter
    inc Count1ms+0    ; Increment the low 8-bits first
    mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
    jnz Inc_Done
    inc Count1ms+1

  Inc_Done:
    ; Check if a second has passed
    mov a, Count1ms+0
    cjne a, #low(1000), cant_reach ; Warning: this instruction changes the carry flag!
    mov a, Count1ms+1
    cjne a, #high(1000), cant_reach
    sjmp one_millisecond


  cant_reach:
    ljmp Timer1_ISR_done

  one_millisecond:
    ; 1000 milliseconds have passed.  Set a flag so the main program knows
    setb one_seconds_flag ; Let the main program know one second had passed
    cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
    ; Reset to zero the milli-seconds counter, it is a 16-bit variable
    clr a
    mov Count1ms+0, a
    mov Count1ms+1, a

  Increment_Sec:
    mov a, BCD_counter
    add a, #0x01
    da a
    mov BCD_counter, a
    clr a

  Timer1_ISR_done:
    pop psw
    pop acc
    reti

  Timer1_ISR_decrement:
    add a, #0x99 ; Adding the 10-complement of -1 is like subtracting 1.

  ;---------------;
  ;	ADC_TO_PB   ;
  ;---------------;

  ADC_to_PB:
    setb PB6
    setb PB5
    setb PB4
    setb PB3
    setb PB2
    setb PB1
    setb PB0
    ; Check PB6
    clr c
    mov a, AD0DAT1
    subb a, #(216-10) ; 2.8V=216*(3.3/255); the -10 is to prevent false readings
    jc ADC_to_PB_L6
    clr PB6
    ret
  ADC_to_PB_L6:
    ; Check PB5
    clr c
    mov a, AD0DAT1
    subb a, #(185-10) ; 2.4V=185*(3.3/255); the -10 is to prevent false readings
    jc ADC_to_PB_L5
    clr PB5
    ret
  ADC_to_PB_L5:
    ; Check PB4
    clr c
    mov a, AD0DAT1
    subb a, #(154-10) ; 2.0V=154*(3.3/255); the -10 is to prevent false readings
    jc ADC_to_PB_L4
    clr PB4
    ret
  ADC_to_PB_L4:
    ; Check PB3
    clr c
    mov a, AD0DAT1
    subb a, #(123-10) ; 1.6V=123*(3.3/255); the -10 is to prevent false readings
    jc ADC_to_PB_L3
    clr PB3
    ret
  ADC_to_PB_L3:
    ; Check PB2
    clr c
    mov a, AD0DAT1
    subb a, #(92-10) ; 1.2V=92*(3.3/255); the -10 is to prevent false readings
    jc ADC_to_PB_L2
    clr PB2
    ret
  ADC_to_PB_L2:
    ; Check PB1
    clr c
    mov a, AD0DAT1
    subb a, #(61-10) ; 0.8V=61*(3.3/255); the -10 is to prevent false readings
    jc ADC_to_PB_L1
    clr PB1
    ret
  ADC_to_PB_L1:
    ; Check PB1
    clr c
    mov a, AD0DAT1
    subb a, #(30-10) ; 0.4V=30*(3.3/255); the -10 is to prevent false readings
    jc ADC_to_PB_L0
    clr PB0
    ret
  ADC_to_PB_L0:
    ; No pusbutton pressed	
    ret

  ;---------------;
  ; SPI and init  ;
  ;---------------;

  ; Configure the serial port and baud rate
  InitSerialPort:
    mov	BRGCON,#0x00
    mov	BRGR1,#high(BRVAL)
    mov	BRGR0,#low(BRVAL)
    mov	BRGCON,#0x03 ; Turn-on the baud rate generator
    mov	SCON,#0x52 ; Serial port in mode 1, ren, txrdy, rxempty
    mov	P1M1,#0x00 ; Enable pins RxD and TXD
    mov	P1M2,#0x00 ; Enable pins RxD and TXD
    ret

InitADC0:
	; ADC0_0 is connected to P1.7
	; ADC0_1 is connected to P0.0

    ; Configure pins P1.7, P0.0  as inputs
    orl P0M1, #00000001b
    anl P0M2, #11111110b
    
    orl P1M1, #10000000b
    anl P1M2, #01111111b
    
	; Setup ADC0
	setb BURST0 ; Autoscan continuos conversion mode
	mov	ADMODB,#0x20 ;ADC0 clock is 7.3728MHz/2
	mov	ADINS,#0x03 ; Select two channels of ADC0 for conversion
	mov	ADCON0,#0x05 ; Enable the converter and start immediately
	; Wait for first conversion to complete
  InitADC0_L1:
    mov	a,ADCON0
    jnb	acc.3,InitADC0_L1
    ret
  ;-------------------------------------------

  Delay_one_second:
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)
    ret

  ; Send a character using the serial port
  putchar:
      jnb TI, putchar
      clr TI
      mov SBUF, a
      ret

  ; Send a constant-zero-terminated string using the serial port

  ;---------------------------------;
  ; USEFUL FUCNTIONS
  ;---------------------------------;

  ; Display a 3-digit BCD number in the LCD
  LCD_3BCD:
    mov a, bcd+1
    anl a, #0x0f
    orl a, #'0'
    lcall ?WriteData
    mov a, bcd+0
    swap a
    anl a, #0x0f
    orl a, #'0'
    lcall ?WriteData
    mov a, bcd+0
    anl a, #0x0f
    orl a, #'0'
    lcall ?WriteData
    ret

  Display_ADC_Values:
    ; Analog input to pin P2.1
    mov x+0, AD0DAT0
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0
    lcall Hex2BCD
    Set_Cursor(2, 13)
    lcall LCD_3BCD
    ; Some delay so the LCD looks ok
    Wait_Milli_Seconds(#250)
    ret
  
	
  SendString:
    clr a
    movc a, @a+dptr
    jz SendString_L1
    lcall putchar
    inc dptr
    sjmp SendString  
  SendString_L1:
	ret

  Wait10us:
    mov R0, #18
    djnz R0, $ ; 2 machine cycles-> 2*0.27126us*18=10us
	ret

  ;---------------------------------;
  ; Main program. Includes hardware ;
  ; initialization and 'forever'    ;
  ; loop.                           ;
  ;---------------------------------;
  main:
      mov SP, #0x7F

      ; Configure all the ports in bidirectional mode:
      mov P0M1, #00H
      mov P0M2, #00H
      mov P1M1, #00H
      mov P1M2, #00H ; WARNING: P1.2 and P1.3 need 1kohm pull-up resistors!
      mov P2M1, #00H
      mov P2M2, #00H
      mov P3M1, #00H
      mov P3M2, #00H
      
      lcall InitADC0

      lcall LCD_4BIT

      mov Soak_temp, 	#0x40
      mov Soak_temp+1, 	#0x01
      mov Soak_time, 	#0x30
      mov Reflow_temp, 	#0x00
      mov Reflow_temp+1,#0x02
      mov Reflow_time, 	#0x20
      mov BCD_counter, 	#0x00


      lcall defaultMessageDisplay
      Wait_Milli_Seconds(#50)

      lcall setReflow
      Wait_Milli_Seconds(#50)
      WriteCommand(#1)
      Wait_Milli_Seconds(#50)
      
      lcall activateOven  ;technically our 'state 0' 
      Wait_Milli_Seconds(#50)
      WriteCommand(#1)
      Wait_Milli_Seconds(#50)
      
      lcall Timer1_Init
      setb EA
      
      lcall forever 		;retrieve temp from beginning
      ljmp state1



forever:
	Set_Cursor(1,1)
    Send_Constant_String(#OvenDisplay)
    Set_Cursor(2,1)
    Send_Constant_String(#OvenDisplay2)
    Set_Cursor(1,12)

    lcall read_temperature
    lcall hex2bcd
    lcall LCD_3BCD

    Set_Cursor(2,13)		;display 'room temp'
    mov a, #0x22
    mov bcd, a
    Display_BCD(bcd)
    
    Set_Cursor(1,3)
    Display_BCD(BCD_counter)

    mov a, state			;compare what state its in 
    cjne a, #0, return		;if not state 0, its already in fsm, return to where it was called

    mov a, #1				;so it doesnt skip over state 1 upon entry
    ljmp state1				;otherwise, start fsm by going to state1

    ret

  return:
    ret

  ;-------checking to see what state its in--------;  
  next1:
    mov a, state 
    cjne a, #1, next2
    sjmp state1
  next2:
    mov a, state
    cjne a, #2, next3
    ljmp state2
  next3:
    mov a, state
    cjne a, #3, next4
    ljmp state3
  next4:
    mov a, state
    cjne a, #4, next4
    ljmp state4
  next5:
    mov a, state
    cjne a, #5, next1
    ljmp state5

;---------------------------------------------------------

  GOTOstate2:
    ljmp state2
  you_is_done2:
    ljmp you_is_done

state1:
    cjne a, #1, GOTOstate2
    mov pwm, #100			;just an indicator for coder
    
    
    Set_Cursor(2,4)			;display what state currently in
    Send_Constant_String(#RPS)
    
    clr OVEN				;turn on oven
    
    mov BCD_counter, #1
    mov a, Soak_temp

whatthehell:
	lcall ADC_to_PB
    jnb PB5, you_is_done2
    sjmp whatthehell

    clr c
    
    subb a, temp
    lcall forever
    
    lcall ADC_to_PB
    jnb PB5, you_is_done2	;user can abort whenever they want to
    
    mov a, BCD_counter
    cjne a, #60, check_temp   ;auto termination thing

  backtoState1:	
    jnc state1_done
    mov state, #2

  state1_done:
    lcall forever

  check_temp:
    lcall read_temperature
    load_y(30)
    lcall x_lteq_y

  highTemp:
    jbc mf, abort
    sjmp	backtoState1


  abort:
    setb error_flag
    setb OVEN
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
    Wait_Milli_Seconds(#200)
      clr error_flag
    ljmp replacerdonzo

  state2:
    cjne a, #2, state3
    mov pwm, #20

    Set_Cursor(2,4)
    Send_Constant_String(#SK)

    lcall twenty_percent
    lcall twenty_percent2

    mov a, Soak_time
    clr c
    subb a, sec
    jnc state2_done
    mov state, #3

  twenty_percent:
    lcall read_temperature
    mov x, bcd
    mov y, Soak_Temp
    lcall x_gt_y
    mov a, mf
    cjne a, #1, go_back
    sjmp turn_off

  twenty_percent2:
    lcall read_temperature
    mov x, bcd
    mov y, Soak_Temp
    lcall x_lt_y
    mov a, mf
    cjne a, #1, go_back
    sjmp turn_on

  turn_on:
    clr OVEN
    ret

  turn_off:
    setb OVEN
    ret 

  go_back:
    ret



  state2_done:
    lcall ADC_to_PB
      jnb PB5, you_is_done4
    lcall forever

  you_is_done4:
    ret

state3:
    cjne a, #3, state4
    mov pwm, #100

    Set_Cursor(2,4)
    Send_Constant_String(#RPS)
    clr OVEN
    mov sec, #0
    mov a, Reflow_temp
    clr c
    subb a, temp
    jnc state3_done
    mov state, #4



turn_on_jump:
    ljmp turn_on

state3_done:
    lcall ADC_to_PB
    jnb PB5, you_is_done
    lcall forever

  state4:
    cjne a, #4, state5
    mov pwm, #20

    lcall twenty_percent3
    lcall twenty_percent4

    mov a, Reflow_time
    clr c
    subb a, sec
    jnc state4_done
    mov state, #5

twenty_percent3:
    lcall read_temperature
    mov x, bcd
    mov y, Reflow_Temp
    lcall x_gt_y
    mov a, mf
    cjne a, #1, go_back1
    sjmp turn_off

twenty_percent4:
    lcall read_temperature
    mov x, bcd
    mov y, Reflow_Temp
    lcall x_lt_y
    mov a, mf
    cjne a, #1, go_back1
    ljmp turn_on

  go_back1:
    ret

  state4_done:
    lcall ADC_to_PB
    jnb PB5, you_is_done
    lcall forever

  state5:
    cjne a, #5, you_is_done
    mov pwm, #0
    setb OVEN
    mov a, Reflow_temp
    clr c
    subb a, temp
    jnc state5_done
    mov state, #0

  state5_done:
    lcall ADC_to_PB
    jnb PB5, you_is_done
    lcall forever


  you_is_done:
    ljmp replacerdonzo ;idkw hat to put here rn 		

  ;change number to BCD for display
  ;for oven temp
    lcall hex2bcd
    Display_BCD(bcd)
    mov a, #'\r'
    lcall putchar
    mov a, #'\n'
    lcall putchar

    Set_Cursor(1,6)
    Display_BCD(bcd)
    Set_Cursor(1,9)
    Display_char(#'C')


  ;for outside temp
    lcall hex2bcd
    Display_BCD(bcd)
    mov a, #'\r'
    lcall putchar
    mov a, #'\n'
    lcall putchar

    Set_Cursor(1,6)
    Display_BCD(bcd)
    Set_Cursor(1,9)
    Display_char(#'C')

    lcall SendString 	

  ;------------------------------------------------------------    
  defaultMessageDisplay:

    WriteCommand(#1)
    Wait_Milli_Seconds(#2)

    Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
    Wait_Milli_Seconds(#2)
    Set_Cursor(2, 1)
    Send_Constant_String(#ToContinueClick)
	

waiting_to_continue:
	jb MODE_BUTTON, waiting_to_continue
	Wait_Milli_Seconds(#50)
	jb MODE_BUTTON, waiting_to_continue
	jnb MODE_BUTTON, $
	

setSoak:


    Set_Cursor(1, 1)
    Send_Constant_String(#SoakMessage)

    Set_Cursor(2,1)
    Display_BCD(Soak_temp+1)
    Display_BCD(Soak_temp)

    WriteData(#0b11011111) ; degree sign 
    Set_Cursor(2,6)
    Send_Constant_String(#Celsius)
    Set_Cursor(2, 7)
    Send_Constant_String(#blank)
    Set_Cursor(2,12)
    Display_BCD(Soak_time)
    Set_Cursor(2, 14)
    WriteData(#'s')



checkSoakTimeINC:
    lcall ADC_to_PB
    jb PB0, checkSoakTimeDEC

    mov a, Soak_time
    cjne a, #0x50, jumpINCSoakTime

checkSoakTimeDEC:
    jb PB1, checkSoakTempINC

    mov a, Soak_time
    cjne a, #0x60, jumpDECSoakTime

setSoakJump:		;can't reach branch
    ljmp setSoak

checkSoakTempINC:
    jb PB2, checkSoakTempDEC
    mov a, Soak_temp
    cjne a, #205, jumpINCSoakTemp

checkSoakTempDEC:
    jb PB3, continueSoakSetting
    mov a, Soak_temp
    cjne a, #140, jumpDECSoakTemp

continueSoakSetting:
    jb MODE_BUTTON, jmpstsoak
	Wait_Milli_Seconds(#50)
	jb MODE_BUTTON, jmpstsoak
	jnb MODE_BUTTON, $
    ret
      

jmpstsoak:
    ljmp setSoak
  ;--------------------------------

  jumpINCSoakTime:
      ljmp INCSoakTime

  jumpDECSoakTime:
      ljmp DECSoakTime

  jumpINCSoakTemp:
      ljmp INCSoakTemp

  jumpDECSoakTemp:
      ljmp DECSoakTemp
  ;----------------------------------------------------------------------------------------------------------
  setReflow:
    Wait_Milli_Seconds(#50)
      Set_Cursor(1, 1)
    Send_Constant_String(#ReflowMessage)

      Set_Cursor(2,1)
      Send_Constant_String(#TP)
      Display_BCD(Reflow_temp+1)
      Display_BCD(Reflow_temp)
      WriteData(#0b11011111)
      Send_Constant_String(#Celsius)
    WriteData(#' ')
    WriteData(#' ')
    WriteData(#' ')
    Display_BCD(Reflow_time)
      WriteData(#'s')

  checkReflowTimeINC:
    lcall ADC_TO_PB
      jb PB0, checkReflowTimeDEC
      mov a, Reflow_time
      cjne a, #0x90, jumpINCReflowTime

  checkReflowTimeDEC:

    jb PB1, checkReflowTempINC
      mov a, Reflow_time
      cjne a, #0x00, jumpDECReflowTime

  setReflowJump:
    ljmp setReflow

  checkReflowTempINC:
      jb PB2, checkReflowTempDEC
      mov a, Reflow_temp
      cjne a, #0x90, jumpINCReflowTemp

  checkReflowTempDEC:
      jb PB3, continueReflowSetting
      mov a, Reflow_temp
      cjne a, #0x00, jumpDECReflowTemp

  continueReflowSetting:
	jb MODE_BUTTON, setReflowJump
	Wait_Milli_Seconds(#50)
	jb MODE_BUTTON, setReflowJump
	jnb MODE_BUTTON, $

    ret
  ;----------------------------------------------
  jumpINCReflowTime:
      ljmp INCReflowTime

  jumpDECReflowTime:
      ljmp DECReflowTime

  jumpINCReflowTemp:
      ljmp INCReflowTemp

  jumpDECReflowTemp:
      ljmp DECReflowTemp

  replacerdonzo:
    setb OVEN ;setb turns oven OFF (reverse logic), clr turns oven ON 
    WriteCommand(#0x01)
	Wait_Milli_Seconds(#3)
      Set_Cursor(1,1)
      Send_Constant_String(#DONEZO)

  donzo_loop:
  	Wait_Milli_Seconds(#250)
  	Wait_Milli_Seconds(#250)
	cpl OVEN
    sjmp donzo_loop


  ;----------------------------------------------------------------------------------------------------------
activateOven:
    mov a, #0
    mov state, a  ;state=0 for fsm 
    Set_Cursor(1, 1)
    Send_Constant_String(#ConfirmStart)

wait_activate:
	jb MODE_BUTTON, wait_activate
	Wait_Milli_Seconds(#50)
	jb MODE_BUTTON, wait_activate
	jnb MODE_BUTTON, $

    ret
  ;----------------------------------------------------------------------------------------------------------

  INCSoakTime:
      mov a, Soak_time
      add a, #0x05
      da a
      mov Soak_time, a
      Wait_Milli_Seconds(#200)
      ljmp setSoak

  DECSoakTime:
      mov a, Soak_time
      add a, #0x95
      da a
      mov Soak_time, a
      Wait_Milli_Seconds(#200)
      ljmp setSoak

  INCSoakTemp:
      mov a, Soak_temp
      add a, #0x05
      da a
      mov Soak_temp, a
      Wait_Milli_Seconds(#200)
      ljmp setSoak

  DECSoakTemp:
      mov a, Soak_temp
      add a, #0x95
      da a
      mov Soak_temp, a
      Wait_Milli_Seconds(#200)
      ljmp setSoak

  ;-------------------------
  INCReflowTime:
      mov a, Reflow_time
      add a, #0x05
      da a
      mov Reflow_time, a  
      Wait_Milli_Seconds(#200)
      ljmp setReflow

  DECReflowTime:
      mov a, Reflow_time
      add a, #0x95
      da a
      mov Reflow_time, a
      Wait_Milli_Seconds(#200)
      ljmp setReflow

  INCReflowTemp:
      mov a, Reflow_temp
      add a, #0x05
      da a
      mov Reflow_temp, a
      Wait_Milli_Seconds(#200)
      ljmp setReflow

  DECReflowTemp:
      mov a, Reflow_temp
      add a, #0x95
      da a
      mov Reflow_temp, a
      Wait_Milli_Seconds(#200)
      ljmp setReflow




      END