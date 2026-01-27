local M = {}

local logTag = 'RemoveEngine'

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

local function getVehicle()
  local veh = be:getPlayerVehicle(0)
  if not veh then
    return nil, buildResponse(false, 'Spawn a vehicle to continue.')
  end
  return veh
end

local function fetchConfig(veh)
  local vid = veh:getID()
  local config = extensions.core_vehicle_manager and extensions.core_vehicle_manager.getPartConfig(vid)
  if config and config.parts then
    return config
  end
  return nil, buildResponse(false, 'Unable to read part configuration for this vehicle.')
end

local function findEngineSlot(parts)
  if not parts then
    return nil
  end
  if parts.mainEngine ~= nil then
    return 'mainEngine', parts.mainEngine
  end
  for slotName, partName in pairs(parts) do
    if type(slotName) == 'string' then
      local lowered = slotName:lower()
      if lowered:find('engine') then
        return slotName, partName
      end
    end
  end
  return nil
end

local function determineVehicleName(veh)
  if not veh then
    return 'Active vehicle'
  end
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

local function trySetEmpty(vehId, slotName)
  if not extensions.core_vehicle_manager or not extensions.core_vehicle_manager.replacePart then
    return false, 'Vehicle manager extension unavailable'
  end

  local ok, err = pcall(function()
    extensions.core_vehicle_manager.replacePart(vehId, slotName, 'empty')
  end)
  if ok then
    return true
  end

  log('W', logTag, string.format('Failed to install "empty" in %s: %s', tostring(slotName), tostring(err)))

  local okFallback, errFallback = pcall(function()
    extensions.core_vehicle_manager.replacePart(vehId, slotName, '')
  end)
  if okFallback then
    return true
  end
  return false, errFallback or err
end

local function getEngineSlotInfo()
  local veh, errorResponse = getVehicle()
  if not veh then
    return errorResponse
  end

  local config, configError = fetchConfig(veh)
  if not config then
    return configError
  end

  local slotName, partName = findEngineSlot(config.parts)
  local isEmpty = (partName == nil or partName == '' or partName == 'empty')
  local response = {
    vehicleId = veh:getID(),
    vehicleName = determineVehicleName(veh),
    slotId = slotName,
    slotLabel = humanizeSlotName(slotName),
    isEmpty = isEmpty,
    partName = partName or ''
  }

  if not slotName then
    response.message = 'No engine slot detected on this vehicle.'
    return buildResponse(false, response.message, response)
  end

  if isEmpty then
    response.message = 'Engine already empty.'
  end

  return buildResponse(true, response.message, response)
end

local function setEngineEmpty()
  local veh, errorResponse = getVehicle()
  if not veh then
    return errorResponse
  end

  local config, configError = fetchConfig(veh)
  if not config then
    return configError
  end

  local slotName, partName = findEngineSlot(config.parts)
  if not slotName then
    return buildResponse(false, 'No engine slot detected on this vehicle.')
  end

  if partName == nil or partName == '' or partName == 'empty' then
    return buildResponse(false, 'Engine already empty.', {
      slotId = slotName,
      slotLabel = humanizeSlotName(slotName),
      alreadyEmpty = true
    })
  end

  local vid = veh:getID()
  local ok, err = trySetEmpty(vid, slotName)
  if not ok then
    log('E', logTag, string.format('replacePart failed: %s', tostring(err)))
    return buildResponse(false, 'Unable to install Empty engine for slot ' .. slotName .. '.', {
      slotId = slotName,
      previousPart = partName
    })
  end

  local vehicleName = determineVehicleName(veh)
  return buildResponse(true, string.format('Removed engine from %s.', vehicleName), {
    slotId = slotName,
    slotLabel = humanizeSlotName(slotName),
    previousPart = partName
  })
end

M.getEngineSlotInfo = getEngineSlotInfo
M.setEngineEmpty = setEngineEmpty

return M
