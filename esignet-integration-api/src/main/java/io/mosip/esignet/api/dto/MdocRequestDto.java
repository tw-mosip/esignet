package io.mosip.esignet.api.dto;

import lombok.Data;

import java.util.Map;

@Data
public class MdocRequestDto {
    private String doctype;
    private String format;
    private Map<String, Object> claims;
}
