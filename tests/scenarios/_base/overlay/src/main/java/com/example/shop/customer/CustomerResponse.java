package com.example.shop.customer;

public record CustomerResponse(String id, String name, String email, CustomerStatus status, int discountPercent) {

    static CustomerResponse from(Customer customer, int discountPercent) {
        return new CustomerResponse(customer.getId(), customer.getName(), customer.getEmail(),
                customer.getStatus(), discountPercent);
    }
}
