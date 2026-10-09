package com.example.shop.customer;

import java.math.BigDecimal;

import org.springframework.stereotype.Component;

/**
 * Loyalty discount: 5% from 1000 spent, 10% from 5000 spent (thresholds inclusive).
 */
@Component
public class DiscountCalculator {

    private static final BigDecimal SILVER = new BigDecimal("1000");
    private static final BigDecimal GOLD = new BigDecimal("5000");

    public int discountPercent(BigDecimal totalSpent) {
        if (totalSpent == null) {
            return 0;
        }
        if (totalSpent.compareTo(GOLD) >= 0) {
            return 10;
        }
        if (totalSpent.compareTo(SILVER) >= 0) {
            return 5;
        }
        return 0;
    }
}
