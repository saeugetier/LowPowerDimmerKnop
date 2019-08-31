/* ULP Example: pulse counting

   This example code is in the Public Domain (or CC0 licensed, at your option.)

   Unless required by applicable law or agreed to in writing, this
   software is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
   CONDITIONS OF ANY KIND, either express or implied.

   This file contains assembly code which runs on the ULP.

   ULP wakes up to run this code at a certain period, determined by the values
   in SENS_ULP_CP_SLEEP_CYCx_REG registers. On each wake up, the program checks
   the input on GPIO0. If the value is different from the previous one, the
   program "debounces" the input: on the next debounce_max_count wake ups,
   it expects to see the same value of input.
   If this condition holds true, the program increments edge_count and starts
   waiting for input signal polarity to change again.
   When the edge counter reaches certain value (set by the main program),
   this program running triggers a wake up from deep sleep.
*/

/* ULP assembly files are passed through C preprocessor first, so include directives
   and C macros may be used in these files 
 */
#include "soc/rtc_cntl_reg.h"
#include "soc/rtc_io_reg.h"
#include "soc/soc_ulp.h"

	/* Define variables, which go into .bss section (zero-initialized data) */
	.bss
	/* Next input signal edge expected: 0 (negative) or 1 (positive) */
	.global next_edge_push
next_edge_push:
	.long 0

	/* Total number of signal edges acquired */
	.global pushed
pushed:
	.long 0

	/* RTC IO number used to sample the input signal.
	   Set by main program. */
	.global io_number_push
io_number_push:
	.long 0

	.global io_number_a
io_number_a:
	.long 0

	.global io_number_b
io_number_b:
	.long 0

	.global last_state_ab
last_state_ab:
	.long 0

	.global previous_state_ab
previous_state_ab:
	.long 0

	.global quadrature_counter
quadrature_counter:
	.long 0

	.global a_state
a_state:
	.long 0

	.global b_state
b_state:
	.long 0

	.global changed_ab
changed_ab:
	.long 0

	/* Code goes into .text section */
	.text
	.global entry
entry:
	/* Load io_number for push */
	move r3, io_number_push
	ld r3, r3, 0

	/* Lower 16 IOs and higher need to be handled separately,
	 * because r0-r3 registers are 16 bit wide.
	 * Check which IO this is.
	 */
	move r0, r3
	jumpr read_io_high_push, 16, ge

	/* Read the value of lower 16 RTC IOs into R0 */
	READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S, 16)
	rsh r0, r0, r3
	jump read_done_push

	/* Read the value of RTC IOs 16-17, into R0 */
read_io_high_push:
	READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S + 16, 2)
	sub r3, r3, 16
	rsh r0, r0, r3

read_done_push:
	and r0, r0, 1
	/* State of input changed? */
	move r3, next_edge_push
	ld r3, r3, 0
	add r3, r0, r3
	and r3, r3, 1
	jump changed_push, eq
	/* Not changed */
	jump decode_rotary

	.global changed_push
changed_push:
	move r3, next_edge_push
	ld r2, r3, 0
	add r2, r2, 1
	and r2, r2, 1
	st r2, r3, 0

	/* push io is HIGH? */
	and r0, r0, 1
	jump decode_rotary, eq
	/* push io is LOW --> set pushed variable*/
	move r3, pushed
	move r2, 1
	st r2, r3, 0


/* push button is evaluated */
/* next ist rotary encoder */

	.global decode_rotary
decode_rotary:
/*read a*/
	move r3, io_number_a
	ld r3, r3, 0
	move r0, r3
	jumpr read_io_high_a, 16, ge
	READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S, 16)
	rsh r0, r0, r3
	jump read_done_a
read_io_high_a:
	READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S + 16, 2)
	sub r3, r3, 16
	rsh r0, r0, r3
read_done_a:
	and r0, r0, 1
	move r1, r0

/*read b*/
	move r3, io_number_b
	ld r3, r3, 0
	move r0, r3
	jumpr read_io_high_a, 16, ge
	READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S, 16)
	rsh r0, r0, r3
	jump read_done_b
read_io_high_b:
	READ_RTC_REG(RTC_GPIO_IN_REG, RTC_GPIO_IN_NEXT_S + 16, 2)
	sub r3, r3, 16
	rsh r0, r0, r3
read_done_b:
	and r0, r0, 1
	lsh r0, r0, 1
	add r1, r1, r0 //a + b << 1
	move r2, last_state_ab
	ld r3, r2, 0 //value of last_state in r3
	sub r2, r3, r1 /* check if has changed (ALU contains last state - current state)*/ 
	jump check_values_changed, eq  /* when not changed than jump over */
    /* values has changed */
	/* r1 contains current state, r3 the last state */
	move r2, previous_state_ab //debug variable
	st r3, r2, 0
	move r2, last_state_ab
	st r1, r2, 0 //store the current value into last state
	
	rsh r0, r0, 1 // get value of B
	and r1, r1, 1 // get pure A value

	/* save debug variables */
	move r2, a_state
	st r1, r2, 0
	move r2, b_state
	st r0, r2, 0

	/* Has A or B changed? */
	and r2, r1, r3
	and r2, r2, 1 //mask A (A && A')
	jumpr b_change, 1, ge //if A == 1 && A' == 1, than has B changed
	or r2, r1, r3
	and r2, r2, 1 //mask A (A || A')
	//jumpr a_change, 1, ge // A == 1 && A' == 0 or A == 0 && A' == 1
	jump b_change, eq  // A == 0 && A' == 0
	/*and r1, r1, 1 // get value of A
	
	
//	add r3, r3, 4
	and r2, r3, 1 // A has changed
	jumpr b_change, 1, lt*/	

a_change:	// if B != 1 than count up
	move r2, changed_ab
	move r3, 1
	st r3, r2, 0
	or r3, r1, r0 //is A == 0  && B == 0? --> count down
	jump count_down, eq
	and r3, r1, r0 //if A == 1 && B == 0 or A == 0 && B == 1
	jump count_up, eq
	jumpr count_down, 1, ge

b_change:   // if A == B than count up
	move r2, changed_ab
	move r3, 2
	st r3, r2, 0
	and r3, r0, r1 //A == 1 && B == 1?
	jumpr count_up, 1, ge
	or r3, r0, r1 //A == 1 || B == 1
	jumpr count_up, 1, ge
	jumpr count_down, 1, lt

count_up:
	move r2, quadrature_counter
	ld r3, r2, 0
	add r3, r3, 1
	st r3, r2, 0
	sub r3, r3, r3
	jump check_values_changed, eq
count_down:
	move r2, quadrature_counter
	ld r3, r2, 0
	sub r3, r3, 1
	st r3, r2, 0

	.global check_values_changed
check_values_changed:
	move r2, pushed
	ld r3, r2, 0
	sub r3, r3, 1
	jump wake_up, eq
	move r2, quadrature_counter
	ld r3, r2, 0
	add r3, r3, 0
	jump end, eq /* no push and no quadrature */

	.global wake_up
wake_up:
	/* Check if the system can be woken up */
	READ_RTC_FIELD(RTC_CNTL_LOW_POWER_ST_REG, RTC_CNTL_RDY_FOR_WAKEUP)
	and r0, r0, 1
	jump wake_up, eq

	/* Wake up the SoC, end program */
	wake
	halt

	.global end
end:
	halt
