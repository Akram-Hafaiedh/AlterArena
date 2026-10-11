local ADDON_NAME, ns = ...

-- Shared safe accessors for WoW 12.x secret values (taint-safe).

function ns.IsIndexable(v)
    if v == nil then return false end
    if issecretvalue then
        return not issecretvalue(v)
    end
    return true
end

function ns.IsSecret(v)
    return v ~= nil and issecretvalue and issecretvalue(v) or false
end

function ns.SafeValue(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

function ns.SafeNumber(v)
    v = ns.SafeValue(v)
    if v == nil then return nil end
    return tonumber(v)
end

function ns.SafeString(v)
    v = ns.SafeValue(v)
    if v == nil then return nil end
    if type(v) ~= "string" then return nil end
    return v
end

function ns.AmbiguateName(name)
    if not name then return "" end
    if not ns.IsIndexable(name) then return "" end
    if Ambiguate then
        local ok, result = pcall(Ambiguate, name, "none")
        if ok and result then return result end
        return ""
    end
    local ok, result = pcall(string.match, name, "^([^%-]+)")
    if ok and result then return result end
    return ""
end