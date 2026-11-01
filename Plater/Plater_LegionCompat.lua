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

-- 8.0 renamed Scale:SetFromScale/SetToScale to SetScaleFrom/SetScaleTo; scripts use the new names.
do
	local scaleAnimation = CreateFrame("Frame"):CreateAnimationGroup():CreateAnimation("Scale")
	local scaleMethods = getmetatable(scaleAnimation).__index
	if type(scaleMethods) == "table" then
		scaleMethods.SetScaleFrom = scaleMethods.SetScaleFrom or scaleMethods.SetFromScale
		scaleMethods.SetScaleTo = scaleMethods.SetScaleTo or scaleMethods.SetToScale
		scaleMethods.GetScaleFrom = scaleMethods.GetScaleFrom or scaleMethods.GetFromScale
		scaleMethods.GetScaleTo = scaleMethods.GetScaleTo or scaleMethods.GetToScale
	end

	-- Alpha:SetChange(delta) is the pre-7.0 API; map it to SetFromAlpha/SetToAlpha
	-- assuming a fade in from 0 (delta > 0) or a fade out to 0 (delta < 0).
	local alphaAnimation = scaleAnimation:GetParent():CreateAnimation("Alpha")
	local alphaMethods = getmetatable(alphaAnimation).__index
	if type(alphaMethods) == "table" and not alphaMethods.SetChange and alphaMethods.SetFromAlpha then
		alphaMethods.SetChange = function(animation, delta)
			delta = tonumber(delta) or 0
			if delta >= 0 then
				animation:SetFromAlpha(0)
				animation:SetToAlpha(math.min(delta, 1))
			else
				animation:SetFromAlpha(math.min(-delta, 1))
				animation:SetToAlpha(0)
			end
		end
	end
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
