package com.example.shop.customer;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import com.example.shop.common.DuplicateEmailException;
import com.example.shop.common.NotFoundException;

@WebMvcTest(CustomerController.class)
class CustomerControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private CustomerService service;

    @Test
    void create_Valid_Returns201() throws Exception {
        when(service.create(any())).thenReturn(
                new CustomerResponse("c1", "Jan", "jan@example.com", CustomerStatus.ACTIVE, 0));

        mockMvc.perform(post("/api/customers").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Jan\",\"email\":\"jan@example.com\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value("c1"));
    }

    @Test
    void create_InvalidEmail_Returns400() throws Exception {
        mockMvc.perform(post("/api/customers").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Jan\",\"email\":\"not-an-email\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void create_DuplicateEmail_Returns409() throws Exception {
        when(service.create(any())).thenThrow(new DuplicateEmailException());

        mockMvc.perform(post("/api/customers").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Jan\",\"email\":\"jan@example.com\"}"))
                .andExpect(status().isConflict());
    }

    @Test
    void get_Missing_Returns404() throws Exception {
        when(service.get("x")).thenThrow(new NotFoundException("Customer x not found"));

        mockMvc.perform(get("/api/customers/x")).andExpect(status().isNotFound());
    }
}
