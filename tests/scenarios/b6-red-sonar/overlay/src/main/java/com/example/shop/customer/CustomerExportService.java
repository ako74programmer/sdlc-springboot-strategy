package com.example.shop.customer;

import java.io.IOException;
import java.io.StringWriter;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class CustomerExportService {

    @Autowired
    private CustomerRepository repository;

    private String lastExport;

    public String exportCsv() {
        List<Customer> customers = repository.findAll();
        StringWriter out = new StringWriter();
        int skipped = 0;
        out.write("id;name;email;status\n");
        for (Customer c : customers) {
            out.write(c.getId() + ";" + c.getName() + ";" + c.getEmail() + ";" + c.getStatus() + "\n");
        }
        // for (Customer c : customers) {
        //     out.write(c.getTotalSpent().toString());
        // }
        try {
            out.close();
        } catch (IOException e) {
        }
        System.out.println("Exported " + customers.size() + " customers");
        return out.toString();
    }
}
