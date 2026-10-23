local _, private = ...
local interfaceVersion = select(4, GetBuildInfo())
private.IsLegion = interfaceVersion >= 70000 and interfaceVersion < 80000

if not private.IsLegion then
	return
end

-- Legion has Mainline specializations, not Classic talent trees.
WOW_PROJECT_MAINLINE = WOW_PROJECT_MAINLINE or 1
WOW_PROJECT_CLASSIC = WOW_PROJECT_CLASSIC or 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5
WOW_PROJECT_WRATH_CLASSIC = WOW_PROJECT_WRATH_CLASSIC or 11
WOW_PROJECT_ID = WOW_PROJECT_ID or WOW_PROJECT_MAINLINE

local UnitAura = UnitAura
function private.UnitAura(...)
	local name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable,
		nameplateShowPersonal, spellID, canApplyAura, isBossDebuff, castByPlayer,
		nameplateShowAll, timeMod, value1, value2, value3 = UnitAura(...)
	return name, icon, count, dispelType, duration, expirationTime, source, isStealable,
		nameplateShowPersonal, spellID, canApplyAura, isBossDebuff, castByPlayer,
		nameplateShowAll, timeMod, value1, value2, value3
end

local xpcall = xpcall
function private.xpcall(callback, errorHandler, ...)
	local args, count = {...}, select("#", ...)
	return xpcall(function()
		return callback(unpack(args, 1, count))
	end, errorHandler)
end

local unavailableCVars = {}
function private.SetCVar(name, value, ...)
	if GetCVar(name) == nil then
		if not unavailableCVars[name] then
			unavailableCVars[name] = true
			print("|cFFFFAA00Plater: CVar '" .. name .. "' is unavailable on this Legion client; this setting cannot be applied.|r")
		end
		return
	end
	return _G.SetCVar(name, value, ...)
end
