package com.example.shop.common;

public class DuplicateEmailException extends RuntimeException {

    public DuplicateEmailException() {
        super("Customer with this email already exists");
    }
}
