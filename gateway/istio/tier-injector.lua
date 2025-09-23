function envoy_on_request(handle)
  local path = handle:headers():get(":path") or "/"
  local tier = "standard"
  if string.find(path, "/api/premium") then
    tier = "premium"
  elseif string.find(path, "/api/enterprise") then
    tier = "enterprise"
  end
  if not handle:headers():get("x-customer-tier") then
    handle:headers():add("x-customer-tier", tier)
  end
  handle:logInfo("[tier-injector] tier=" .. tier .. " path=" .. path)
end
