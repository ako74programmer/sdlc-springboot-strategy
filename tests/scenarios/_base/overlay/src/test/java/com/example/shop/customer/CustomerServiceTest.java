package com.example.shop.customer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.example.shop.common.DuplicateEmailException;
import com.example.shop.common.NotFoundException;

@ExtendWith(MockitoExtension.class)
class CustomerServiceTest {

    @Mock
    private CustomerRepository repository;

    private CustomerService service;

    @BeforeEach
    void setUp() {
        service = new CustomerService(repository, new DiscountCalculator());
    }

    @Test
    void create_NewEmail_SavesCustomer() {
        when(repository.findByEmail("jan@example.com")).thenReturn(Optional.empty());
        when(repository.save(any(Customer.class))).thenAnswer(inv -> {
            Customer c = inv.getArgument(0);
            c.setId("c1");
            return c;
        });

        CustomerResponse response = service.create(new CustomerRequest("Jan", "jan@example.com"));

        assertThat(response.id()).isEqualTo("c1");
        assertThat(response.status()).isEqualTo(CustomerStatus.ACTIVE);
        assertThat(response.discountPercent()).isZero();
    }

    @Test
    void create_ExistingEmail_ThrowsDuplicate() {
        when(repository.findByEmail("jan@example.com")).thenReturn(Optional.of(new Customer("Jan", "jan@example.com")));
        CustomerRequest request = new CustomerRequest("Jan", "jan@example.com");

        assertThatThrownBy(() -> service.create(request))
                .isInstanceOf(DuplicateEmailException.class);
        verify(repository, never()).save(any());
    }

    @Test
    void get_Missing_ThrowsNotFound() {
        when(repository.findById("x")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.get("x")).isInstanceOf(NotFoundException.class);
    }

    @Test
    void get_LoyalCustomer_ReturnsDiscount() {
        Customer customer = new Customer("Ala", "ala@example.com");
        customer.setId("c2");
        customer.setTotalSpent(new BigDecimal("6000"));
        when(repository.findById("c2")).thenReturn(Optional.of(customer));

        assertThat(service.get("c2").discountPercent()).isEqualTo(10);
    }

    @Test
    void block_Existing_SetsBlocked() {
        Customer customer = new Customer("Ola", "ola@example.com");
        customer.setId("c3");
        when(repository.findById("c3")).thenReturn(Optional.of(customer));
        when(repository.save(customer)).thenReturn(customer);

        assertThat(service.block("c3").status()).isEqualTo(CustomerStatus.BLOCKED);
    }
}
