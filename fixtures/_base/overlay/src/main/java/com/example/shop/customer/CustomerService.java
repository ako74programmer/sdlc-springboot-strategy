package com.example.shop.customer;

import java.util.Locale;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.example.shop.common.DuplicateEmailException;
import com.example.shop.common.NotFoundException;

@Service
public class CustomerService {

    private static final Logger log = LoggerFactory.getLogger(CustomerService.class);

    private final CustomerRepository repository;
    private final DiscountCalculator discountCalculator;

    public CustomerService(CustomerRepository repository, DiscountCalculator discountCalculator) {
        this.repository = repository;
        this.discountCalculator = discountCalculator;
    }

    public CustomerResponse create(CustomerRequest request) {
        String email = request.email().trim().toLowerCase(Locale.ROOT);
        if (repository.findByEmail(email).isPresent()) {
            throw new DuplicateEmailException();
        }
        Customer saved = repository.save(new Customer(request.name().trim(), email));
        log.info("Customer created: {}", saved.getId());
        return toResponse(saved);
    }

    public CustomerResponse get(String id) {
        return toResponse(find(id));
    }

    public CustomerResponse block(String id) {
        Customer customer = find(id);
        customer.setStatus(CustomerStatus.BLOCKED);
        Customer saved = repository.save(customer);
        log.info("Customer blocked: {}", saved.getId());
        return toResponse(saved);
    }

    private Customer find(String id) {
        return repository.findById(id).orElseThrow(() -> new NotFoundException("Customer " + id + " not found"));
    }

    private CustomerResponse toResponse(Customer customer) {
        return CustomerResponse.from(customer, discountCalculator.discountPercent(customer.getTotalSpent()));
    }
}
