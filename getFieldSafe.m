% Helper function to safely extract fields from the header
function value = getFieldSafe(hdr, fieldName, defaultValue)
    try
        if isfield(hdr, fieldName)
            value = hdr.(fieldName);
        else
            value = defaultValue;
        end
    catch
        value = defaultValue;
    end
end
