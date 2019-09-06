/* ULP Example

   This example code is in the Public Domain (or CC0 licensed, at your option.)

   Unless required by applicable law or agreed to in writing, this
   software is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
   CONDITIONS OF ANY KIND, either express or implied.
*/

#include <stdio.h>
#include "esp_sleep.h"
#include "soc/rtc_cntl_reg.h"
#include "soc/sens_reg.h"
#include "soc/rtc_periph.h"
#include "driver/gpio.h"
#include "driver/rtc_io.h"
#include "esp32/ulp.h"
#include "ulp_main.h"

extern const uint8_t ulp_main_bin_start[] asm("_binary_ulp_main_bin_start");
extern const uint8_t ulp_main_bin_end[]   asm("_binary_ulp_main_bin_end");

static void init_ulp_program(void);
static void update_pulse_count(void);

void app_main(void)
{
    esp_sleep_wakeup_cause_t cause = esp_sleep_get_wakeup_cause();
    if (cause != ESP_SLEEP_WAKEUP_ULP) {
        printf("Not ULP wakeup, initializing ULP\n");
        init_ulp_program();
    } else {
        printf("ULP wakeup, saving pulse count\n");
        update_pulse_count();
    }

    printf("Entering deep sleep\n\n");
    ESP_ERROR_CHECK( esp_sleep_enable_ulp_wakeup() );
    esp_deep_sleep_start();
}

static void init_ulp_program(void)
{
    esp_err_t err = ulp_load_binary(0, ulp_main_bin_start,
            (ulp_main_bin_end - ulp_main_bin_start) / sizeof(uint32_t));
    ESP_ERROR_CHECK(err);

    /* GPIO used for pulse counting. */
    gpio_num_t gpio_num = GPIO_NUM_0;
    assert(rtc_gpio_desc[gpio_num].reg && "GPIO used for pulse counting must be an RTC IO");

    /* Initialize some variables used by ULP program.
     * Each 'ulp_xyz' variable corresponds to 'xyz' variable in the ULP program.
     * These variables are declared in an auto generated header file,
     * 'ulp_main.h', name of this file is defined in component.mk as ULP_APP_NAME.
     * These variables are located in RTC_SLOW_MEM and can be accessed both by the
     * ULP and the main CPUs.
     *
     * Note that the ULP reads only the lower 16 bits of these variables.
     */
    ulp_pushed = 0;
    ulp_io_number_push = rtc_gpio_desc[gpio_num].rtc_num; /* map from GPIO# to RTC_IO# */

    /* Initialize selected GPIO as RTC IO, enable input, disable pullup and pulldown */
    rtc_gpio_init(gpio_num);
    rtc_gpio_set_direction(gpio_num, RTC_GPIO_MODE_INPUT_ONLY);
    rtc_gpio_pulldown_dis(gpio_num);
    rtc_gpio_pullup_dis(gpio_num);
    rtc_gpio_hold_en(gpio_num);


    /* initialization of quadrature IOs */
    gpio_num_t gpio_num_a = GPIO_NUM_25;
    gpio_num_t gpio_num_b = GPIO_NUM_26;
    assert(rtc_gpio_desc[gpio_num_a].reg && "GPIO used for pulse counting must be an RTC IO");
    assert(rtc_gpio_desc[gpio_num_b].reg && "GPIO used for pulse counting must be an RTC IO");

    rtc_gpio_init(gpio_num_a);
    rtc_gpio_set_direction(gpio_num_a, RTC_GPIO_MODE_INPUT_ONLY);
    rtc_gpio_pulldown_dis(gpio_num_a);
    rtc_gpio_pullup_dis(gpio_num_a);
    rtc_gpio_hold_en(gpio_num_a);

    rtc_gpio_init(gpio_num_b);
    rtc_gpio_set_direction(gpio_num_b, RTC_GPIO_MODE_INPUT_ONLY);
    rtc_gpio_pulldown_dis(gpio_num_b);
    rtc_gpio_pullup_dis(gpio_num_b);
    rtc_gpio_hold_en(gpio_num_b);

    ulp_io_number_a = rtc_gpio_desc[gpio_num_a].rtc_num;
    ulp_io_number_b = rtc_gpio_desc[gpio_num_b].rtc_num;

    /* Disconnect GPIO12 and GPIO15 to remove current drain through
     * pullup/pulldown resistors.
     * GPIO12 may be pulled high to select flash voltage.
     */
    rtc_gpio_isolate(GPIO_NUM_12);
    rtc_gpio_isolate(GPIO_NUM_15);
    esp_deep_sleep_disable_rom_logging(); // suppress boot messages

    /* Set ULP wake up period to T = 10ms.
     * Frequency is 100 Hz
     */
    ulp_set_wakeup_period(0, 10000);

    /* Start the program */
    err = ulp_run(&ulp_entry - RTC_SLOW_MEM);
    ESP_ERROR_CHECK(err);
}

static void update_pulse_count(void)
{
    int16_t pulse_count_from_ulp = ulp_quadrature_counter;
    uint32_t pushed_from_ulp = (ulp_pushed & UINT16_MAX);

    ulp_quadrature_counter = 0;
    ulp_pushed = 0;

    printf("Pulse count from ULP: %5d\n", pulse_count_from_ulp);
    printf("Pushed state = %d\n", pushed_from_ulp);
    printf("Last state = %d\n", ulp_last_state_ab & UINT16_MAX);
    printf("Previous state = %d\n", ulp_previous_state_ab & UINT16_MAX);
    printf("A: %d\n", ulp_a_state & UINT16_MAX);
    printf("B: %d\n", ulp_b_state & UINT16_MAX);
    printf("changed: %d\n", ulp_changed_ab & UINT16_MAX);
    printf("decision was: %d\n", ulp_decision & UINT16_MAX);

    ulp_changed_ab = 0;
    ulp_decision = 4;
}
