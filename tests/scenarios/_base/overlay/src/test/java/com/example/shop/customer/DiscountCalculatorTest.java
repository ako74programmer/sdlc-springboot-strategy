package com.example.shop.customer;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;

import org.junit.jupiter.api.Test;

class DiscountCalculatorTest {

    private final DiscountCalculator calculator = new DiscountCalculator();

    @Test
    void discountPercent_NullTotal_ReturnsZero() {
        assertThat(calculator.discountPercent(null)).isZero();
    }

    @Test
    void discountPercent_Below1000_ReturnsZero() {
        assertThat(calculator.discountPercent(new BigDecimal("999.99"))).isZero();
    }

    @Test
    void discountPercent_Exactly1000_ReturnsFive() {
        assertThat(calculator.discountPercent(new BigDecimal("1000"))).isEqualTo(5);
    }

    @Test
    void discountPercent_Between1000And5000_ReturnsFive() {
        assertThat(calculator.discountPercent(new BigDecimal("2500"))).isEqualTo(5);
    }

    @Test
    void discountPercent_Exactly5000_ReturnsTen() {
        assertThat(calculator.discountPercent(new BigDecimal("5000"))).isEqualTo(10);
    }
}
