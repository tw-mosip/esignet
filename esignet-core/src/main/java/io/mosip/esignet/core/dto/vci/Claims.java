package io.mosip.esignet.core.dto.vci;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.mosip.esignet.core.constants.ErrorConstants;
import lombok.Data;

import javax.validation.constraints.NotEmpty;
import java.util.Map;

@Data
public class Claims {

    @NotEmpty(message = ErrorConstants.INVALID_REQUEST)
    @JsonProperty("org.iso.18013.5.1")
    private Map<String, Object> nameSpace;

}