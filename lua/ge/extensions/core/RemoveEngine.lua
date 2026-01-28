local M = {}

local logTag = 'RemoveEngine'

local traceEnabled = true

local function trace(fmt, ...)
  if not traceEnabled then
    return
  end

  local argc = select('#', ...)
  if argc == 0 then
    log('I', logTag, fmt)
    return
  end

  local args = { ... }
  for i = 1, argc do
    args[i] = tostring(args[i])
  end

  local function unpackArgs(idx)
    if idx > argc then
      return
    end
    return args[idx], unpackArgs(idx + 1)
  end

  local ok, message = pcall(string.format, fmt, unpackArgs(1))
  if ok then
    log('I', logTag, message)
  else
    log('I', logTag, fmt .. ' | ' .. table.concat(args, ' | '))
  end
end

local function countEntries(tbl)
  if type(tbl) ~= 'table' then
    return 0
  end

  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count
end

trace('core_RemoveEngine extension loaded (trace=%s)', tostring(traceEnabled))

local function buildResponse(success, message, extra)
  extra = extra or {}
  extra.success = success
  extra.message = message
  return jsonEncode(extra)
end

local function humanizeSlotName(slotName)
  if not slotName then
    return nil
  end
  local label = slotName:gsub('_', ' ')
  label = label:gsub('(%l)(%u)', '%1 %2')
  label = label:gsub('%s+', ' ')
  return label:gsub('^%s+', ''):gsub('%s+$', '')
end

local preferredEngineSlots = {
  'mainEngine',
  'engine',
  'engine_rwd',
  'engine_fwd',
  'engine_block',
  'engineblock',
  'engine_core',
  'enginecore'
}

local excludedSlotTokens = {
  'mount',
  'bracket',
  'support',
  'dummy',
  'bay',
  'ecu',
  'controller',
  'computer'
}

local function isLikelyEngineSlot(slotName)
  if type(slotName) ~= 'string' then
    return false
  end
  local lowered = slotName:lower()
  if not lowered:find('engine') then
    return false
  end
  for _, token in ipairs(excludedSlotTokens) do
    if lowered:find(token) then
      return false
    end
  end
  return true
end

local function flattenPartsTree(node, bucket)
  if type(node) ~= 'table' or type(bucket) ~= 'table' then
    return
  end

  if node.id then
    local partName = node.chosenPartName
    if partName == nil then
      bucket[node.id] = bucket[node.id] or ''
    else
      bucket[node.id] = partName
    end
  end

  if node.children then
    for _, child in pairs(node.children) do
      flattenPartsTree(child, bucket)
    end
  end
end

local function ensurePartsSnapshot(config)
  if type(config) ~= 'table' then
    trace('ensurePartsSnapshot: config missing or invalid')
    return nil
  end

  if type(config.parts) == 'table' then
    trace('ensurePartsSnapshot: using existing parts (%s entries)', countEntries(config.parts))
    return config.parts
  end

  if type(config.partsTree) == 'table' then
    local flattened = {}
    flattenPartsTree(config.partsTree, flattened)
    config.parts = flattened
    trace('ensurePartsSnapshot: flattened partsTree -> %s entries', countEntries(flattened))
    return config.parts
  end

  trace('ensurePartsSnapshot: config lacks parts data')
  return nil
end

local function getVehicle()
  trace('getVehicle: locating player vehicle')
  local veh = be:getPlayerVehicle(0)
  if veh then
    local label = veh.uiName or veh.jbeam or veh.name or ''
    trace('getVehicle: primary vehicle id=%s label=%s', tostring(veh:getID()), label)
    return veh
  end

  local vehId = be:getPlayerVehicleID(0)
  trace('getVehicle: player vehicle id lookup => %s', tostring(vehId))
  if vehId and vehId ~= -1 then
    local vehById = be:getObjectByID(vehId)
    trace('getVehicle: object lookup for %s => %s', tostring(vehId), vehById and 'success' or 'nil')
    if vehById then
      return vehById
    end
  end

  trace('getVehicle: no active vehicle found')
  return nil, buildResponse(false, 'Spawn a vehicle to continue.')
end

local function fetchConfig(veh)
  trace('fetchConfig: start (vehId=%s)', veh and veh:getID() or 'nil')
  local diagnostics = {}

  local function note(message)
    diagnostics[#diagnostics + 1] = message
    trace('fetchConfig diag: %s', message)
  end

  local vehicleManager = extensions.core_vehicle_manager
  if vehicleManager and type(vehicleManager.getPlayerVehicleData) == 'function' then
    trace('fetchConfig: vehicle manager available')
    local ok, playerVehicle = pcall(vehicleManager.getPlayerVehicleData)
    if ok and playerVehicle and playerVehicle.config then
      ensurePartsSnapshot(playerVehicle.config)
      if type(playerVehicle.config.parts) == 'table' then
        trace('fetchConfig: using vehicle manager config (%s parts)', countEntries(playerVehicle.config.parts))
        return playerVehicle.config, playerVehicle
      end
      note('Vehicle config missing a parts table.')
    else
      note('Vehicle manager returned no data.')
    end
  else
    note('Vehicle manager unavailable.')
  end

  local partManager = extensions.core_vehicle_partmgmt
  if partManager and type(partManager.getConfig) == 'function' then
    trace('fetchConfig: part manager available')
    local ok, config = pcall(partManager.getConfig)
    if ok and config then
      ensurePartsSnapshot(config)
      if type(config.parts) == 'table' then
        trace('fetchConfig: using part manager config (%s parts)', countEntries(config.parts))
        return config, { config = config, vehicleDirectory = config.vehicleDirectory }
      end
      note('Part manager config missing a parts table.')
    else
      note('Part manager getConfig failed.')
    end
  else
    note('Part manager unavailable.')
  end

  local message = table.concat(diagnostics, ' ')
  if #message == 0 then
    message = 'Unable to inspect the active vehicle.'
  end
  log('W', logTag, message)
  trace('fetchConfig: returning error -> %s', message)
  return nil, nil, buildResponse(false, message)
end

local function isEmptyPart(partName)
  if partName == nil then
    return true
  end
  if partName == '' then
    return true
  end
  if type(partName) == 'string' then
    local lowered = partName:lower()
    if lowered == 'empty' or lowered == 'none' then
      return true
    end
  end
  return false
end

local function findEngineSlot(parts)
  if not parts then
    return nil
  end

  local fallbackSlot, fallbackPart

  for _, candidate in ipairs(preferredEngineSlots) do
    if parts[candidate] ~= nil then
      local partName = parts[candidate]
      trace('findEngineSlot: preferred slot %s part=%s', candidate, tostring(partName))
      if not isEmptyPart(partName) then
        return candidate, partName
      end
      if not fallbackSlot then
        fallbackSlot = candidate
        fallbackPart = partName
      end
    end
  end

  for slotName, partName in pairs(parts) do
    if isLikelyEngineSlot(slotName) then
      trace('findEngineSlot: heuristic slot %s part=%s', slotName, tostring(partName))
      if not isEmptyPart(partName) then
        return slotName, partName
      end
      if not fallbackSlot then
        fallbackSlot = slotName
        fallbackPart = partName
      end
    end
  end

  if fallbackSlot then
    trace('findEngineSlot: using fallback slot %s part=%s', tostring(fallbackSlot), tostring(fallbackPart))
    return fallbackSlot, fallbackPart
  end

  trace('findEngineSlot: no engine slot found')
  return nil
end

local function determineVehicleName(veh, vehicleData)
  if veh then
    if veh.uiName and #veh.uiName > 0 then
      return veh.uiName
    end
    if type(veh.getJBeamFilename) == 'function' then
      local jb = veh:getJBeamFilename()
      if jb and #jb > 0 then
        return jb
      end
    end
    if veh.jbeam and #veh.jbeam > 0 then
      return veh.jbeam
    end
    return string.format('Vehicle %d', veh:getID())
  end

  if vehicleData then
    if type(vehicleData.name) == 'string' and #vehicleData.name > 0 then
      return vehicleData.name
    end
    if type(vehicleData.config) == 'table' then
      if type(vehicleData.config.model) == 'string' and #vehicleData.config.model > 0 then
        return vehicleData.config.model
      end
      if type(vehicleData.config.jbeam) == 'string' and #vehicleData.config.jbeam > 0 then
        return vehicleData.config.jbeam
      end
    end
    if type(vehicleData.vehicleDirectory) == 'string' and #vehicleData.vehicleDirectory > 0 then
      return vehicleData.vehicleDirectory
    end
  end

  return 'Active vehicle'
end

local function trySetEmpty(slotName)
  local partManager = extensions.core_vehicle_partmgmt
  if not partManager or type(partManager.setConfig) ~= 'function' then
    return false, 'Part manager unavailable.'
  end

  local payload = { parts = { [slotName] = '' } }
  trace('trySetEmpty: applying user-empty payload for slot %s', tostring(slotName))
  local ok, err = pcall(partManager.setConfig, payload, true)
  if ok then
    trace('trySetEmpty: successfully cleared part for %s', tostring(slotName))
    return true
  end

  log('W', logTag, string.format('Failed to clear slot %s: %s', tostring(slotName), tostring(err)))
  return false, err or 'Unable to update part configuration.'
end

local function getEngineSlotInfo()
  trace('getEngineSlotInfo: invoked')
  local veh, vehError = getVehicle()

  local config, vehicleData, configError = fetchConfig(veh)
  if not config then
    trace('getEngineSlotInfo: config unavailable (%s)', configError or vehError or 'unknown error')
    return configError or vehError or buildResponse(false, 'Unable to inspect the active vehicle.')
  end

  local parts = ensurePartsSnapshot(config)
  trace('getEngineSlotInfo: snapshot size=%s', countEntries(parts))
  local slotName, partName = findEngineSlot(parts)
  local vehicleId = veh and veh:getID() or (vehicleData and (vehicleData.vehId or vehicleData.vehID)) or be:getPlayerVehicleID(0)
  if vehicleId == -1 then
    vehicleId = nil
  end
  local response = {
    vehicleId = vehicleId,
    vehicleName = determineVehicleName(veh, vehicleData),
    slotId = slotName,
    slotLabel = humanizeSlotName(slotName),
    isEmpty = isEmptyPart(partName),
    partName = partName or '',
    vehicleDirectory = (vehicleData and vehicleData.vehicleDirectory) or config.vehicleDirectory
  }

  trace('getEngineSlotInfo: slot=%s part=%s empty=%s', tostring(slotName), tostring(partName), tostring(response.isEmpty))
  if not slotName then
    response.message = 'No engine slot detected on this vehicle.'
    trace('getEngineSlotInfo: %s', response.message)
    return buildResponse(false, response.message, response)
  end

  if response.isEmpty then
    response.message = 'Engine already empty.'
  end

  return buildResponse(true, response.message, response)
end

local function setEngineEmpty()
  trace('setEngineEmpty: invoked')
  local veh, vehError = getVehicle()

  local config, vehicleData, configError = fetchConfig(veh)
  if not config then
    trace('setEngineEmpty: config unavailable (%s)', configError or vehError or 'unknown error')
    return configError or vehError or buildResponse(false, 'Unable to inspect the active vehicle.')
  end

  local parts = ensurePartsSnapshot(config)
  trace('setEngineEmpty: snapshot size=%s', countEntries(parts))
  local slotName, partName = findEngineSlot(parts)
  if not slotName then
    trace('setEngineEmpty: no engine slot detected')
    return buildResponse(false, 'No engine slot detected on this vehicle.')
  end

  local vehicleId = veh and veh:getID() or (vehicleData and (vehicleData.vehId or vehicleData.vehID)) or be:getPlayerVehicleID(0)
  if vehicleId == -1 then
    vehicleId = nil
  end
  local vehicleName = determineVehicleName(veh, vehicleData)

  if isEmptyPart(partName) then
    trace('setEngineEmpty: slot %s already empty', tostring(slotName))
    return buildResponse(false, 'Engine already empty.', {
      vehicleId = vehicleId,
      vehicleName = vehicleName,
      slotId = slotName,
      slotLabel = humanizeSlotName(slotName),
      alreadyEmpty = true
    })
  end

  trace('setEngineEmpty: attempting to install empty part into %s (previous=%s)', tostring(slotName), tostring(partName))
  local ok, err = trySetEmpty(slotName)
  if not ok then
    trace('setEngineEmpty: trySetEmpty failed -> %s', tostring(err))
    log('E', logTag, string.format('Unable to install empty engine in %s: %s', tostring(slotName), tostring(err)))
    return buildResponse(false, 'Unable to install Empty engine for slot ' .. slotName .. '.', {
      vehicleId = vehicleId,
      vehicleName = vehicleName,
      slotId = slotName,
      previousPart = partName
    })
  end

  if parts then
    parts[slotName] = ''
  end

  trace('setEngineEmpty: removed engine from %s (slot=%s)', vehicleName, tostring(slotName))
  return buildResponse(true, string.format('Removed engine from %s.', vehicleName), {
    vehicleId = vehicleId,
    vehicleName = vehicleName,
    slotId = slotName,
    slotLabel = humanizeSlotName(slotName),
    previousPart = partName
  })
end

M.getEngineSlotInfo = getEngineSlotInfo
M.setEngineEmpty = setEngineEmpty

return M
