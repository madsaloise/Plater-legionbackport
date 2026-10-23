local passed = 0

local function read(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

local function section(path, first, last)
	local text = read(path)
	local start = assert(text:find(first, 1, true), first)
	local finish = assert(text:find(last, start + #first, true), last)
	return text:sub(start, finish - 1)
end

local function run(source, env, ...)
	local chunk = assert(loadstring(source))
	setfenv(chunk, env)
	return chunk(...)
end

local function environment(version)
	local env = setmetatable({}, {__index = _G})
	env._G = env
	env.GetBuildInfo = function() return "test", "test", "test", version end
	env.CreateFrame = function() error("unexpected frame construction") end
	env.UnitAura = function() end
	local private = {}
	run(read("Plater_LegionCompat.lua"), env, "Plater", private)
	return env, private
end

local function equal(actual, expected)
	assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end

local function test(name, callback)
	callback()
	passed = passed + 1
	print("PASS " .. name)
end

test("Legion is Mainline without replacing native functions", function()
	local env, private = environment(70300)
	assert(private.IsLegion)
	equal(env.WOW_PROJECT_ID, env.WOW_PROJECT_MAINLINE)
	assert(env.WOW_PROJECT_ID ~= env.WOW_PROJECT_CLASSIC)
	equal(env.xpcall, xpcall)
	assert(env.UnitAura ~= private.UnitAura)
	equal(env.C_UnitAuras, nil)
	local create = env.CreateFrame
	run(read("Plater_LegionCompat.lua"), env, "Plater", private)
	equal(env.CreateFrame, create)
	equal(read("Plater_LegionCompat.xml"):find('name="BackdropTemplate"', 1, true) ~= nil, true)
end)

test("Retail and Classic bootstrap are unchanged", function()
	for _, version in ipairs({100205, 30403, 11501}) do
		local env, private = environment(version)
		assert(not private.IsLegion)
		equal(private.UnitAura, nil)
		equal(private.xpcall, nil)
		equal(env.WOW_PROJECT_ID, nil)
	end
end)

test("WeakAuras project constants coexist in either load order", function()
	local env = setmetatable({_G = false}, {__index = _G})
	env._G = env
	env.GetBuildInfo = function() return "7.3.5", "", "", 70300 end
	env.UnitAura = function() end
	for _, waFirst in ipairs({true, false}) do
		env.WOW_PROJECT_ID = nil
		if waFirst then
			env.WOW_PROJECT_MAINLINE, env.WOW_PROJECT_ID = 1, 1
		end
		local private = {}
		run(read("Plater_LegionCompat.lua"), env, "Plater", private)
		equal(env.WOW_PROJECT_ID, 1)
		equal(env.WOW_PROJECT_MAINLINE, 1)
	end
end)

test("protected calls preserve nil arguments, return values and errors", function()
	local env, private = environment(70300)
	local ok, count, first, second, third = private.xpcall(function(...)
		return select("#", ...), ...
	end, function(err) return err end, "a", nil, "c")
	equal(ok, true)
	equal(count, 3)
	equal(first, "a")
	equal(second, nil)
	equal(third, "c")
	local errorSeen
	ok = private.xpcall(function() error("expected failure") end, function(err) errorSeen = err end)
	equal(ok, false)
	assert(errorSeen:find("expected failure", 1, true))
end)

test("Legion aura tuple removes rank and preserves stacks and spell ID", function()
	local env, private = environment(70300)
	env.UnitAura = function(unit, index, filter)
		equal(unit, "nameplate1")
		equal(index, 1)
		equal(filter, "HARMFUL")
		return "Burn", "Rank 1", 135812, 3, "Magic", 12, 112, "player", false, true, 12345, true, false, true, false, 1, 42
	end
	run(read("Plater_LegionCompat.lua"), env, "Plater", private)
	local aura = {private.UnitAura("nameplate1", 1, "HARMFUL")}
	equal(aura[1], "Burn")
	equal(aura[2], 135812)
	equal(aura[3], 3)
	equal(aura[5], 12)
	equal(aura[10], 12345)
	equal(aura[16], 42)
end)

local popupSource = section(
	"libs\\AceConfig-3.0\\AceConfigDialog-3.0\\AceConfigDialog-3.0.lua",
	"do\n\tlocal frame = AceConfigDialog.popup",
	"local function confirmPopup"
)

local function popupEnvironment(version)
	local env = environment(version)
	local frames = {}
	local function newFrame(kind, name, parent, template)
		if version < 80000 then
			assert(template == nil, "Legion inherited an unavailable template: " .. tostring(template))
		end
		local frame = {parent = parent, template = template, scripts = {}}
		for _, method in ipairs({
			"Hide", "SetPoint", "SetSize", "EnableMouse", "SetFrameStrata", "SetFrameLevel",
			"SetAllPoints", "SetNormalFontObject", "SetHighlightFontObject", "SetNormalTexture",
			"SetPushedTexture", "SetHighlightTexture", "SetText", "SetTexCoord",
		}) do
			frame[method] = function() end
		end
		frame.SetScript = function(self, event, callback) self.scripts[event] = callback end
		frame.SetBackdrop = function(self, info) self.backdrop = info end
		frame.SetBackdropColor = function(self, ...) self.color = {...} end
		frame.CreateFontString = function(self, name, layer, template)
			equal(template, "GameFontHighlight")
			return newFrame("FontString", name, self)
		end
		frame.GetNormalTexture = function(self) return self end
		frame.GetPushedTexture = frame.GetNormalTexture
		frame.GetHighlightTexture = frame.GetNormalTexture
		if version >= 80000 then
			frame.SetFixedFrameStrata = function(self, value) self.fixedStrata = value end
			frame.SetFixedFrameLevel = function(self, value) self.fixedLevel = value end
		end
		frames[#frames + 1] = frame
		return frame
	end
	env.CreateFrame = newFrame
	env.UIParent = {}
	env.AceConfigDialog = {}
	env.oldminor = 0
	env.GameFontHighlight, env.GameFontNormal = {}, {}
	env.ACCEPT, env.CANCEL = "Accept", "Cancel"
	run(popupSource, env)
	return env, frames
end

test("reported AceConfig popup error is fixed without WeakAuras templates", function()
	local env, frames = popupEnvironment(70300)
	assert(env.AceConfigDialog.popup.accept)
	assert(env.AceConfigDialog.popup.cancel)
	local border = frames[2]
	assert(border.backdrop.edgeFile:find("UI-DialogBox-Border", 1, true))
	equal(border.color[4], 1)
end)

test("Retail popup still uses the native dialog template", function()
	local env, frames = popupEnvironment(100205)
	equal(frames[2].template, "DialogBorderOpaqueTemplate")
	equal(env.AceConfigDialog.popup.fixedLevel, true)
	equal(env.AceConfigDialog.popup.fixedStrata, true)
end)

test("cast and channel adapters remove Legion rank fields", function()
	local env, private = environment(70300)
	env.DetailsFramework = {IsLegion = function() return true end}
	env.DetailsFrameworkCanLoad = true
	env.UnitCastingInfo = function()
		return "Fireball", "", "Fireball", 135812, 1000, 3000, false, 17, true, 133
	end
	env.UnitChannelInfo = function()
		return "Drain", "", "Drain", 136163, 1000, 4000, false, false, 689
	end
	run(read("libs\\DF\\externals.lua"), env, "Plater", private)
	local cast = {env.DetailsFramework.CastInfo.UnitCastingInfo("nameplate1")}
	equal(cast[2], "Fireball")
	equal(cast[3], 135812)
	equal(cast[7], 17)
	equal(cast[8], true)
	equal(cast[9], 133)
	local channel = {env.DetailsFramework.CastInfo.UnitChannelInfo("nameplate1")}
	equal(channel[3], 136163)
	equal(channel[7], false)
	equal(channel[8], 689)
end)

test("cast events normalize Legion payloads but preserve Retail payloads", function()
	local source = section("libs\\DF\\unitframe.lua",
		"\t--it's triggering several events since it's not registered",
		"\n\tOnTick_LazyTick =")
	for _, isLegion in ipairs({true, false}) do
		local env = {detailsFramework = {IsLegion = function() return isLegion end}}
		setmetatable(env, {__index = _G})
		local methods = run("return {" .. source .. "}", env)
		local received
		local bar = {unit = "nameplate1", UNIT_SPELLCAST_STOP = function(self, ...)
			received = {...}
		end}
		if isLegion then
			methods.OnEvent(bar, "UNIT_SPELLCAST_STOP", "nameplate1", "Fireball", "", 17, 133)
		else
			methods.OnEvent(bar, "UNIT_SPELLCAST_STOP", "nameplate1", "Cast-17", 133)
		end
		equal(received[1], "nameplate1")
		equal(received[2], "nameplate1")
		equal(received[3], isLegion and 17 or "Cast-17")
		equal(received[4], 133)
	end
end)

test("combat-log dispatch uses Legion event arguments or Retail API", function()
	local source = section("Plater.lua", "\tPlaterCLEUParser.Parser = function", '\n\tPlaterCLEUParser:SetScript')
	for _, isLegion in ipairs({true, false}) do
		local env = environment(isLegion and 70300 or 100205)
		env.platerInternal = {IsLegion = isLegion}
		env.PlaterCLEUParser = {}
		env.Plater = {LastCombat = {npcNames = {}}, StartLogPerformanceCore = function() end, EndLogPerformanceCore = function() end}
		local captured
		env.parserFunctions = {SPELL_CAST_START = function(...) captured = {...} end}
		env.CombatLogGetCurrentEventInfo = function()
			assert(not isLegion, "Legion called the unavailable combat log API")
			return 100, "SPELL_CAST_START", false, "source", "Caster", 0, 0, "target", "Victim", 0, 0, 133
		end
		run(source, env)
		env.PlaterCLEUParser.Parser(nil, "COMBAT_LOG_EVENT_UNFILTERED",
			100, "SPELL_CAST_START", false, "source", "Caster", 0, 0, "target", "Victim", 0, 0, 133)
		equal(captured[12], 133)
		equal(env.Plater.LastCombat.npcNames.Victim, true)
	end
end)

test("aura lookup works without aura-slot APIs", function()
	local env, private = environment(70300)
	env.Plater = {}
	env.BUFF_MAX_DISPLAY = 40
	env.GetSpellInfo = function() return "Burn" end
	env.UnitAura = function(unit, index, filter)
		if index == 1 and filter == "HARMFUL" then
			return "Burn", 135812, 3, "Magic", 12, 112, "player", false, true, 12345
		end
	end
	local source = section("Plater_Auras.lua", "\tfunction Plater.GetBuff(unitId, spellName)", "\n\tfunction Plater.UpdateAuras_Self_Automatic")
	run(source, env)
	local aura = {env.Plater.GetBuff("nameplate1", 12345)}
	equal(aura[3], 3)
	equal(aura[10], 12345)
	equal(env.Plater.GetBuff("nameplate1", "absent"), nil)
end)

test("CVar adapter reports unsupported settings once and honors later hooks", function()
	local env, private = environment(70300)
	local messages, writes = 0, 0
	env.GetCVar = function(name) return name == "known" and "1" or nil end
	env.print = function() messages = messages + 1 end
	env.SetCVar = function() error("unexpected old setter") end
	env.SetCVar = function(name, value) writes = writes + 1; equal(value, 2) end
	private.SetCVar("known", 2)
	private.SetCVar("missing", 1)
	private.SetCVar("missing", 1)
	equal(writes, 1)
	equal(messages, 1)
end)

test("pixel utility works without modern screen and math APIs", function()
	local env = environment(70300)
	env.GetScreenHeight = function() return 1440 end
	env.UIParent = {GetEffectiveScale = function() return 0.75 end}
	run(read("libs\\DF\\DFPixelUtil.lua"), env)
	equal(env.DFPixelUtil.GetPixelToUIUnitFactor(), 768 / 1080)
	local bar = {
		GetWidth = function() return 100 end,
		GetMinMaxValues = function() return 0, 100 end,
		GetEffectiveScale = function() return 1 end,
		SetValue = function(self, value) self.value = value end,
	}
	env.Lerp = function(a, b, amount) return a + (b - a) * amount end
	env.DFPixelUtil.SetStatusBarValue(bar, 150)
	equal(bar.value, 150)
	env.DFPixelUtil.SetStatusBarValue(bar, 50)
	assert(math.abs(bar.value - 50) < 1)
end)

test("framework atlas and resize adapters preserve native behavior", function()
	local source = section("libs\\DF\\fw.lua", "function DF:SetResizeBounds", "\n---return if the wow version the player is playing is dragonflight\n")
	for _, isLegion in ipairs({true, false}) do
		local env = environment(isLegion and 70300 or 100205)
		env.DF = {IsLegion = function() return isLegion end}
		env.GetAtlasInfo = function(atlas)
			if atlas == "existing" then
				return "atlas-file", 16, 20, 0.1, 0.2, 0.3, 0.4, false, true
			end
		end
		run(source, env)
		local info = env.DF:GetAtlasInfo("existing")
		equal(info.file, "atlas-file")
		equal(info.height, 20)
		equal(info.topTexCoord, 0.3)
		equal(info.tilesVertically, true)
		equal(env.DF:GetAtlasInfo("missing"), nil)
		local texture = {
			SetTexture = function(self, path) self.path = path end,
			SetAtlas = function(self, atlas, size) self.atlas, self.size = atlas, size end,
		}
		env.DF:SetAtlas(texture, "common-search-clearbutton", true)
		if isLegion then
			equal(texture.path, "Interface\\AddOns\\Plater\\media\\x_64")
		else
			equal(texture.atlas, "common-search-clearbutton")
			equal(texture.size, true)
		end
		env.DF:SetAtlas(texture, "existing", true)
		equal(texture.atlas, "existing")
		env.DF:SetAtlas(texture, "ComboPoints-ComboPoint")
		equal(texture.atlas, isLegion and "ClassOverlay-ComboPoint" or "ComboPoints-ComboPoint")
		env.DF:SetAtlas(texture, "unknown")
		equal(texture.atlas, "unknown")

		local frame = {
			SetMinResize = function(self, w, h) self.min = {w, h} end,
			SetMaxResize = function(self, w, h) self.max = {w, h} end,
		}
		env.DF:SetResizeBounds(frame, 20, 30, 200, 300)
		equal(frame.min[1], 20)
		equal(frame.max[2], 300)
		frame.SetResizeBounds = function(self, ...) self.modern = {...} end
		env.DF:SetResizeBounds(frame, 40, 50, 400, 500)
		equal(frame.modern[4], 500)
	end
end)

test("CallbackHandler dispatches through Legion securecall with nil arguments", function()
	local env = environment(70300)
	env.strmatch = string.match
	local calls = 0
	env.securecall = function(callback, ...)
		calls = calls + 1
		return callback(...)
	end
	run(read("libs\\LibStub\\LibStub.lua"), env)
	run(read("libs\\CallbackHandler-1.0\\CallbackHandler-1.0.lua"), env)
	local target, received = {}, nil
	local registry = env.LibStub("CallbackHandler-1.0"):New(target)
	target.RegisterCallback("receiver", "CHECK", function(...)
		received = {n = select("#", ...), ...}
	end)
	registry:Fire("CHECK", "first", nil, "last")
	equal(calls, 1)
	equal(received.n, 4)
	equal(received[1], "CHECK")
	equal(received[3], nil)
	equal(received[4], "last")
	target.UnregisterCallback("receiver", "CHECK")
	registry:Fire("CHECK")
	equal(calls, 1)
end)

test("resource events omit charged points on Legion and retain them on Retail", function()
	local source = section("Plater_Resources.lua", "\tfunction Plater.Resources.EnableEvents()", "\n\n--> called when use plater resource bar")
	for _, isLegion in ipairs({true, false}) do
		local env = environment(isLegion and 70300 or 100205)
		env.IS_WOW_PROJECT_MAINLINE, env.PlayerClass = true, "ROGUE"
		if not isLegion then
			env.GetUnitChargedPowerPoints = function() return {} end
		end
		local registered, removed = {}, {}
		local frame = {
			RegisterUnitEvent = function(_, event, unit) equal(unit, "player"); registered[event] = true end,
			UnregisterEvent = function(_, event) removed[event] = true end,
			currentResourceBarShown = {updateResourceFunc = function() end},
		}
		env.Plater = {Resources = {GetMainResourceFrame = function() return frame end}}
		run(source, env)
		env.Plater.Resources.EnableEvents()
		assert(registered.UNIT_POWER_FREQUENT and registered.UNIT_MAXPOWER)
		equal(not not registered.UNIT_POWER_POINT_CHARGE, not isLegion)
		env.Plater.Resources.DisableEvents()
		equal(frame.eventsEnabled, false)
		equal(not not removed.UNIT_POWER_POINT_CHARGE, not isLegion)
	end
end)

test("Legion combo points refresh without the charged-point API", function()
	local env = environment(70300)
	env.IS_WOW_PROJECT_MAINLINE = true
	env.resourceWidgetsFunctions = {}
	env.UnitPower = function() return 3 end
	local updated
	env.Plater = {Resources = {
		playerResourceId = 4,
		UpdateResources_NoDepleted = function(_, amount) updated = amount end,
	}}
	local source = section("Plater_Resources.lua", "\tfunction resourceWidgetsFunctions.OnComboPointsChanged", "\n\t--DK runes update")
	run(source, env)
	env.resourceWidgetsFunctions.OnComboPointsChanged({}, {}, true)
	equal(updated, 3)
end)

test("soft-target refresh works without Legion-absent APIs", function()
	local env = environment(70300)
	env.platerInternal = {IsLegion = true}
	env.MEMBER_UNITID = "unit"
	env.UnitIsUnit = function() error("Legion must not query soft-target unit tokens") end
	env.UnitReaction = function() return 3 end
	env.Plater = {}
	local source = section("Plater.lua", "\tfunction Plater.UpdateSoftInteractTarget", "\n\t-- ~target ~selection")
	run(source, env)
	local hidden = false
	local plate = {unit = "nameplate1", unitFrame = {
		softInteractIconFrame = {Hide = function() hidden = true end},
	}}
	plate.unitFrame.PlateFrame = plate
	env.Plater.UpdateSoftInteractTarget(plate)
	equal(plate.isLooseTarget, false)
	equal(plate.isObject, false)
	equal(plate.unitFrame.isSoftEnemy, false)
	assert(hidden)
end)

test("adjustment slider needs no vector API and handles zero distance", function()
	local source = section("libs\\DF\\slider.lua", "\t\t\t\t\tlocal directionX = ", "\n\t\t\t\tend")
	for _, position in ipairs({{0, 0}, {3, 4}, {200, 0}}) do
		local env = environment(70300)
		local result
		env.mouseX, env.mouseY, env.speed = position[1], position[2], 6
		env.DF = {MapRangeClamped = function(_, min, max, low, high, value)
			return low + (high - low) * math.max(0, math.min(1, (value - min) / (max - min)))
		end}
		env.adjustmentSlider = {
			initialMouseX = 0, initialMouseY = 0, centerButton = {widget = {}},
			centerArrowArtwork = {SetPoint = function(_, _, _, _, x, y) result = {x, y} end},
		}
		run(source, env)
		equal(result[1], result[1])
		equal(result[2], result[2])
		assert(math.sqrt(result[1]^2 + result[2]^2) <= 6.00001)
		if position[1] == 3 then
			assert(math.abs(result[1] - 0.18) < 0.00001)
			assert(math.abs(result[2] - 0.24) < 0.00001)
		end
	end
end)

test("shared unpatched AceAddon can initialize Plater without callback arguments", function()
	local env, private = environment(70300)
	local addon = {}
	local database = {profile = {}}
	env.detailsFramework = {}
	env.xpcall = private.xpcall
	env.LibStub = function(name)
		if name == "AceAddon-3.0" then
			return {NewAddon = function() return addon end}
		elseif name == "AceDB-3.0" then
			return {New = function(_, name, defaults)
				equal(name, "PlaterDB")
				return database
			end}
		end
		error("unexpected library: " .. name)
	end
	local reported
	env.geterrorhandler = function() return function(err) reported = err end end
	local text = read("libs\\DF\\addon.lua")
	local start = assert(text:find("function detailsFramework:CreateAddOn(", 1, true))
	run(text:sub(start), env)
	equal(env.detailsFramework:CreateAddOn("Plater", "PlaterDB", {}), addon)
	local initialized = false
	addon.OnInit = function(self)
		equal(self, addon)
		equal(self.db, database)
		initialized = true
	end
	-- Shared AceAddon copies can still use native Lua 5.1 xpcall.
	local ok, err = xpcall(addon.OnInitialize, function(err) return err end, addon)
	assert(ok, err)
	equal(reported, nil)
	assert(initialized)
	equal(addon.db, database)
end)

test("specialization refresh only subscribes after database initialization", function()
	local env = environment(70300)
	local registered, handler
	env.CreateFrame = function()
		return {
			RegisterEvent = function(_, event) registered = event end,
			SetScript = function(_, script, callback)
				equal(script, "OnEvent")
				handler = callback
			end,
		}
	end
	local refreshes, updates = 0, 0
	env.Plater = {
		Auras = {},
		RefreshAuraCache = function() assert(env.Plater.db); refreshes = refreshes + 1 end,
		UpdateAuraCache = function() assert(env.Plater.db); updates = updates + 1 end,
	}
	run(read("Plater_GhostAuras.lua"), env)
	equal(registered, nil)
	equal(refreshes, 0)
	env.Plater.db = {profile = {}}
	env.Plater.Auras.GhostAuras.Initialize()
	equal(registered, "PLAYER_SPECIALIZATION_CHANGED")
	handler(nil, registered, "player")
	equal(refreshes, 1)
	equal(updates, 1)
	local init = section("Plater.lua", "function Plater.OnInit()", "\n\tPlater.UpdateBlizzardNameplateFonts()")
	assert(init:find("Plater.RefreshDBUpvalues()", 1, true) < init:find("Plater.Auras.GhostAuras.Initialize()", 1, true))
end)

test("script environment handles missing Legion namespaces without exposing restricted methods", function()
	local source = section("libs\\DF\\fw.lua", "    local C_SubFunctionsTable = {}", "\n\tfunction DF:SetEnvironment")
	for _, hasNamespace in ipairs({false, true}) do
		local env = environment(70300)
		env.DF = {}
		env.forbiddenFunction = {blocked = true}
		env.C_RestrictedSubFunctions = {C_GuildInfo = {RemoveFromGuild = true}}
		local allowed = function() end
		if hasNamespace then
			env.C_GuildInfo = {RemoveFromGuild = function() end, Allowed = allowed}
		end
		run(source, env)
		local sandbox = setmetatable({}, env.DF.DefaultSecureScriptEnvironmentHandle)
		equal(sandbox._G, sandbox)
		equal(sandbox.blocked, nil)
		if hasNamespace then
			equal(sandbox.C_GuildInfo.RemoveFromGuild, nil)
			equal(sandbox.C_GuildInfo.Allowed, allowed)
			assert(sandbox.C_GuildInfo ~= env.C_GuildInfo)
		else
			equal(sandbox.C_GuildInfo, nil)
		end
	end
end)

test("pixel sizing and anchors use the owning frame scale for Legion textures", function()
	local env = environment(70300)
	env.GetPhysicalScreenSize = function() return 1920, 1080 end
	run(read("libs\\DF\\DFPixelUtil.lua"), env)
	local parent = {GetEffectiveScale = function() return 0.75 end}
	local textureParent = {GetParent = function() return parent end}
	local texture = {
		GetParent = function() return textureParent end,
		SetWidth = function(self, width) self.width = width end,
		SetHeight = function(self, height) self.height = height end,
		SetPoint = function(self, ...) self.point = {...} end,
	}
	local expected = env.DFPixelUtil.GetNearestPixelSize(10, 0.75)
	env.DFPixelUtil.SetSize(texture, 10, 10)
	equal(texture.width, expected)
	equal(texture.height, expected)
	env.DFPixelUtil.SetPoint(texture, "TOPLEFT", parent, "TOPRIGHT", 10, -10)
	equal(texture.point[2], parent)
	equal(texture.point[4], expected)
	equal(texture.point[5], -expected)
	env.DFPixelUtil.SetSize(texture, 0, 0, 1, 1)
	equal(texture.width, (768 / 1080) / 0.75)
	equal(texture.height, texture.width)
	texture.GetEffectiveScale = function() return 1.25 end
	env.DFPixelUtil.SetWidth(texture, 10)
	equal(texture.width, env.DFPixelUtil.GetNearestPixelSize(10, 1.25))
end)

test("framework button constructor does not require BackdropTemplate on Legion", function()
	local source = section("libs\\DF\\button.lua", "\tfunction detailsFramework:NewButton(", "\n\t\tbuttonObject.widget = buttonObject.button")
	local declaration = assert(read("libs\\DF\\button.lua"):match("local PixelUtil = [^\n]+"))
	source = declaration .. "\n" .. source
	source = source .. "\nreturn buttonObject.button\nend"
	for _, version in ipairs({70300, 100205}) do
		local env = environment(version)
		env.GetPhysicalScreenSize = function() return 1920, 768 end
		run(read("libs\\DF\\DFPixelUtil.lua"), env)
		if version ~= 70300 then
			env.PixelUtil = env.DFPixelUtil
		end
		env.detailsFramework = {
			IsLegion = function() return version == 70300 end,
			Mixin = function() end,
		}
		env.createButtonWidgets = function() end
		local created = {
			SetBackdrop = function() end,
			GetEffectiveScale = function() return 1 end,
			SetWidth = function(self, width) self.width = width end,
			SetHeight = function(self, height) self.height = height end,
		}
		env.CreateFrame = function(frameType, name, parent, template)
			equal(frameType, "button")
			equal(name, "TestButton")
			if version == 70300 then
				equal(template, nil)
			else
				equal(template, "BackdropTemplate")
			end
			return created
		end
		run(source, env)
		equal(env.detailsFramework:NewButton({}, nil, "TestButton"), created)
		equal(created.width, 100)
		equal(created.height, 20)
		assert(created.SetBackdrop)
	end
end)

test("all pixel-aware controls bind the fallback without replacing the native global", function()
	local paths = {
		"Plater.lua", "Plater_OptionsPanel.lua", "Plater_Script_Include.lua",
		"libs\\DF\\button.lua", "libs\\DF\\dropdown.lua", "libs\\DF\\slider.lua",
		"libs\\DF\\buildmenu.lua", "libs\\DF\\icon.lua", "libs\\DF\\icongeneric.lua",
		"libs\\DF\\tabcontainer.lua", "libs\\DF\\cooltip.lua", "libs\\DF\\fw.lua",
		"libs\\DF\\panel.lua", "libs\\DF\\loadconditions.lua",
		"libs\\DF\\rounded_panel.lua", "libs\\DF\\unitframe.lua",
	}
	for _, path in ipairs(paths) do
		local declaration = assert(read(path):match("local PixelUtil = [^\n]+"), path)
		for _, hasNative in ipairs({false, true}) do
			local env = environment(hasNative and 100205 or 70300)
			local native, fallback = {}, {}
			env.DFPixelUtil = fallback
			if hasNative then env.PixelUtil = native end
			local result = run(declaration .. "\nreturn PixelUtil", env)
			equal(result, hasNative and native or fallback)
			equal(env.PixelUtil, hasNative and native or nil)
		end
	end
end)

test("indicator scaling preserves sizes on Legion and Retail through texture reuse", function()
	local source = section("Plater.lua", "\tfunction Plater.AddIndicator (", "\n\tfunction Plater.ClearIndicators")
	for _, modern in ipairs({false, true}) do
		local env = environment(modern and 100205 or 70300)
		env.tinsert = table.insert
		env.Plater = {
			db = {profile = {indicator_scale = 1.5, indicator_anchor = {side = 5}}},
			SetAnchor = function() end,
		}
		env.DF = {ParseColors = function() return 1, 0.5, 0 end}
		env.PixelUtil = {SetPoint = function() end}
		local created = 0
		local function texture()
			created = created + 1
			local result = {
				SetDrawLayer = function() end, Show = function() end,
				SetTexCoord = function() end, SetVertexColor = function() end,
				SetDesaturated = function() end, SetTexture = function() end,
				SetSize = function(self, w, h) self.width, self.height = w, h end,
				GetSize = function(self) return self.width, self.height end,
			}
			if modern then
				result.SetScale = function(self, scale) self.scale = scale end
			end
			return result
		end
		local plate = {IconIndicators = {Next = 1}, unitFrame = {healthBar = {CreateTexture = texture}}}
		run(source, env)
		local function check(indicator, expectedW, expectedH, ...)
			plate.IconIndicators.Next = 1
			env.Plater.AddIndicator(plate, indicator, ...)
			local icon = plate.IconIndicators[1]
			equal(icon.width * (icon.scale or 1), expectedW)
			equal(icon.height * (icon.scale or 1), expectedH)
			equal(plate.IconIndicators.Next, 2)
		end
		check("elite", 18, 18)
		check("pet", 15, 15)
		check("rare", 18, 18)
		check("custom", 30, 12, "custom-texture", 20, 8, "white", 0, 1, 0, 1)
		env.Plater.db.profile.indicator_scale = 2
		check("elite", 24, 24)
		equal(created, 1)
	end
end)

test("widget API forwarding uses actual widgets and preserves arguments and returns", function()
	local controls = {
		{"button", "button"}, {"dropdown", "dropdown"}, {"textentry", "editbox"},
		{"slider", "slider"}, {"label", "label"}, {"picture", "image"},
		{"panel", "frame"}, {"normal_bar", "statusbar"}, {"split_bar", "statusbar"},
		{"timebar", "statusBar"}, {"help", "button"},
	}
	for _, control in ipairs(controls) do
		local text = read("libs\\DF\\" .. control[1] .. ".lua")
		local meta, body = text:match("(%w+)%s*%[funcName%]%s*=%s*function%(object, %.%.%.%)(.-)\n%s*end")
		assert(meta and body, control[1])
		local env = environment(70300)
		env[meta] = {}
		env.Plater = {}
		env.idx = {
			SetAlpha = function(widget, ...)
				widget.alphaArgs = {n = select("#", ...), ...}
				return "alpha", nil, 42
			end,
			SetJustifyH = function(widget, value) widget.justify = value end,
		}
		run("for funcName, funcAddress in pairs(idx) do\n" ..
			meta .. "[funcName] = function(object, ...)" .. body .. "\nend\nend", env)
		for _, name in ipairs({false, "Plater", "Widget'WithQuote"}) do
			local widget = {GetName = function() return name or nil end}
			local object = {[control[2]] = widget}
			local result = {n = 0}
			local function capture(...)
				result = {n = select("#", ...), ...}
			end
			capture(env[meta].SetAlpha(object, 0.4, nil, "last"))
			equal(result.n, 3)
			equal(result[1], "alpha")
			equal(result[2], nil)
			equal(result[3], 42)
			equal(widget.alphaArgs.n, 3)
			equal(widget.alphaArgs[1], 0.4)
			equal(widget.alphaArgs[3], "last")
			env[meta].SetJustifyH(object, "left")
			equal(widget.justify, "left")
			equal(env.Plater.alphaArgs, nil)
		end
	end
end)

test("Legion widget prototypes do not inherit wrappers from another addon", function()
	local source = section("libs\\DF\\fw.lua", "DF.GlobalWidgetControlNames = {", "\nfunction DF:AddMemberForWidget")
	for _, legion in ipairs({true, false}) do
		local env = environment(legion and 70300 or 100205)
		env.DF = {IsLegion = function() return legion end}
		local oldPrototype = {SetJustifyH = function() error("old Details wrapper") end}
		env.DF_TextEntryMetaFunctions = oldPrototype
		run(source, env)
		equal(env.DF.GlobalWidgetControlNames.textentry,
			legion and "DF_TextEntryMetaFunctions_PlaterLegion" or "DF_TextEntryMetaFunctions")
		equal(env.DF_TextEntryMetaFunctions, oldPrototype)
		if legion then
			equal(env[env.DF.GlobalWidgetControlNames.textentry], nil)
		end
	end
end)

test("Legion aura textures render without attached hidden masks", function()
	local source = section("Plater_Auras.lua", "\tfunction platerInternal.CreateAuraIcon", "\n\t--create the animation when the icon is shown")
	for _, legion in ipairs({true, false}) do
		local env = environment(legion and 70300 or 100205)
		env.platerInternal = {IsLegion = legion}
		env.Plater = {db = {profile = {disable_omnicc_on_auras = true}}}
		local function region()
			local object = {masks = {}, shown = true}
			object.Hide = function(self) self.shown = false end
			object.SetTexture = function(self, texture) self.texture = texture end
			object.AddMaskTexture = function(self, mask) self.masks[#self.masks + 1] = mask end
			for _, method in ipairs({"SetSize", "SetScript", "SetMouseClickEnabled",
				"SetAllPoints", "SetColorTexture", "SetPoint", "SetTexCoord", "EnableMouse",
				"SetHideCountdownNumbers", "SetJustifyH"}) do
				object[method] = function() end
			end
			object.CreateTexture = function() return region() end
			object.CreateMaskTexture = function() return region() end
			object.CreateFontString = function() return region() end
			return object
		end
		env.CreateFrame = function() return region() end
		run(source, env)
		local icon = env.platerInternal.CreateAuraIcon({}, "TestAura")
		equal(#icon.Icon.masks, legion and 0 or 1)
		equal(#icon.Border.masks, legion and 0 or 1)
		assert(icon.IconMask and icon.BorderMask)
		assert(not icon.IconMask.shown)
		icon.Icon:SetTexture(135812)
		equal(icon.Icon.texture, 135812)
	end
end)

test("UIParent scaling terminates synchronous size callbacks and tolerates native rounding", function()
	local source = section("Plater.lua", "\tfunction Plater.UpdateUIParentScale", "\n\t--this reset the UIParent levels")
	local env = environment(70300)
	env.abs, env.max = math.abs, math.max
	env.Plater = {db = {profile = {ui_parent_scale_tune = 1.2}}}
	run(source, env)
	local calls, scale = 0, 1
	local plate = {GetEffectiveScale = function() return 0.8 end}
	plate.unitFrame = {
		nameplateScaleAdjust = 1.5,
		GetScale = function() return scale end,
		SetScale = function(_, value)
			calls = calls + 1
			assert(calls < 10, "recursive scale updates")
			scale = value + 0.00000001
			env.Plater.UpdateUIParentScale(plate, 140.00004577637, 27.999977111816)
		end,
	}
	env.Plater.UpdateUIParentScale(plate)
	equal(calls, 1)
	assert(math.abs(scale - 1.44) < 0.000001)
	env.Plater.UpdateUIParentScale(plate)
	equal(calls, 1)
	plate.GetEffectiveScale = function() return 0.2 end
	env.Plater.UpdateUIParentScale(plate)
	equal(calls, 2)
	assert(math.abs(scale - 0.2) < 0.000001)
	plate.GetEffectiveScale = function() return 1 end
	env.Plater.db.profile.ui_parent_scale_tune = 0.1
	plate.unitFrame.nameplateScaleAdjust = "2"
	env.Plater.UpdateUIParentScale(plate)
	equal(calls, 3)
	assert(math.abs(scale - 0.6) < 0.000001)
	env.Plater.UpdateUIParentScale({})
end)

test("nameplate reuse registers only one scale hook", function()
	local source = section("Plater.lua", "\t\t\t\tif not plateFrame.PlaterScaleHookRegistered then", "\n\t\t\t\tPlater.UpdateUIParentScale(plateFrame)")
	local env = environment(70300)
	local hooks = 0
	env.Plater = {UpdateUIParentScale = function() end}
	env.plateFrame = {HookScript = function(_, event, callback)
		equal(event, "OnSizeChanged")
		equal(callback, env.Plater.UpdateUIParentScale)
		hooks = hooks + 1
	end}
	for i = 1, 30 do run(source, env) end
	equal(hooks, 1)
end)

test("Legion unit-added events initialize tokens before any unit-dependent refresh", function()
	local source = section("Plater.lua", "\t\tNAME_PLATE_UNIT_ADDED = function", '\n\t\t\tlocal reaction = UnitReaction (unitID, "player")')
	source = "handler = " .. source:match("= (function.*)") .. "\nend"
	local env = environment(70300)
	env.platerInternal = {IsLegion = true}
	env.MEMBER_UNITID = "namePlateUnitToken"
	local plate = {unitFramePlater = {SetUnit = function() end}}
	local expectedUnit = "nameplate7"
	env.C_NamePlate = {GetNamePlateForUnit = function(unit)
		equal(unit, expectedUnit)
		return plate
	end}
	local calls = 0
	env.Plater = {UpdateSoftInteractTarget = function(frame)
		equal(frame.namePlateUnitToken, expectedUnit)
		equal(frame.unitFrame.namePlateUnitToken, expectedUnit)
		calls = calls + 1
	end}
	run(source, env)
	env.handler("NAME_PLATE_UNIT_ADDED", "nameplate7")
	equal(calls, 1)
	expectedUnit = "nameplate8"
	env.handler("NAME_PLATE_UNIT_ADDED", "nameplate8")
	equal(calls, 2)
end)

test("scheduled refresh skips stale units and inactive plates but refreshes active units", function()
	local source = section("Plater.lua", "\tfunction Plater.RunScheduledUpdate", "\n\t---run a delayed update")
	local env = environment(70300)
	local lookups, events = 0, {}
	local frame = {unitFrame = {PlaterOnScreen = true, customHealthBarWidth = 120, customBorderColor = {1, 0, 0}}}
	env.C_NamePlate = {GetNamePlateForUnit = function(unit)
		assert(type(unit) == "string")
		lookups = lookups + 1
		if unit == "nameplate1" then return frame end
	end}
	env.Plater = {
		StartLogPerformanceCore = function() end, EndLogPerformanceCore = function() end,
		RunFunctionForEvent = function(event, unit)
			equal(unit, "nameplate1")
			events[#events + 1] = event
			frame.unitFrame.customHealthBarWidth = nil
		end,
		UpdatePlateSize = function() end, UpdateBorderColor = function() end,
	}
	run(source, env)
	env.Plater.RunScheduledUpdate({})
	equal(lookups, 0)
	env.Plater.RunScheduledUpdate({unitId = "nameplate2"})
	equal(#events, 0)
	frame.unitFrame.PlaterOnScreen = false
	env.Plater.RunScheduledUpdate({unitId = "nameplate1"})
	equal(#events, 0)
	frame.unitFrame.PlaterOnScreen = true
	env.Plater.RunScheduledUpdate({unitId = "nameplate1"})
	equal(events[1], "NAME_PLATE_UNIT_REMOVED")
	equal(events[2], "NAME_PLATE_UNIT_ADDED")
	equal(frame.unitFrame.customHealthBarWidth, 120)
end)

test("removal handles plates whose add event never completed", function()
	local source = section("Plater.lua", "\t\tNAME_PLATE_UNIT_REMOVED = function", "\n\t\t\tNAMEPLATES_ON_SCREEN_CACHE[unitBarId] = false")
	source = "handler = " .. source:match("= (function.*)") .. "\nend"
	local env = environment(70300)
	local plate, removed = nil, 0
	env.ENABLED_BLIZZARD_PLATEFRAMES = {}
	env.C_NamePlate = {GetNamePlateForUnit = function() return plate end}
	env.Plater = {RemoveFromAuraUpdate = function(unit)
		equal(unit, "nameplate1")
		removed = removed + 1
	end}
	run(source, env)
	env.handler("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	plate = {UnitFrame = {}, unitFrame = {}}
	env.handler("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	equal(env.ENABLED_BLIZZARD_PLATEFRAMES[tostring(plate.UnitFrame)], true)
	equal(removed, 2)
end)

test("refresh-all only includes active Plater plates with initialized tokens", function()
	local source = section("Plater.lua", "\tfunction Plater.FullRefreshAllPlates()", "\n\t--update the player bar")
	local env = environment(70300)
	env.MEMBER_UNITID, env.MEMBER_GUID = "token", "guid"
	local calls = 0
	env.Plater = {
		GetAllShownPlates = function() return {
			{}, {unitFrame = {}},
			{token = "nameplate1", guid = "guid1", unitFrame = {PlaterOnScreen = true}},
		} end,
		RunScheduledUpdate = function(timer)
			calls = calls + 1
			equal(timer.unitId, "nameplate1")
		end,
	}
	run(source, env)
	env.Plater.FullRefreshAllPlates()
	equal(calls, 1)
end)

test("removed units cannot create a scheduled refresh with a nil token", function()
	local source = section("Plater.lua", "\tfunction Plater.ScheduleUpdateForNameplate", "\n\t\t--check if there's already an update scheduled")
	source = source .. "\nerror('unexpected timer scheduling')\nend"
	local env = environment(70300)
	env.Plater = {}
	env.MEMBER_UNITID = "token"
	run(source, env)
	env.Plater.ScheduleUpdateForNameplate({})
	local cancelled = false
	local plate = {HasUpdateScheduled = {Cancel = function() cancelled = true end}}
	env.Plater.ScheduleUpdateForNameplate(plate)
	assert(cancelled)
	equal(plate.HasUpdateScheduled, nil)
end)

test("code tabs stay accessible from script options and hide only during import", function()
	local env = environment(70300)
	local function frame(parent)
		return {
			parent = parent, shown = true, enabled = true,
			SetPoint = function() end,
			Show = function(self) self.shown = true end,
			Hide = function(self) self.shown = false end,
			IsVisible = function(self)
				return self.shown and (not self.parent or self.parent:IsVisible())
			end,
		}
	end
	local root = frame()
	local editor, importer = frame(root), frame(root)
	env.scriptingFrame = {CodeEditorLuaEntry = editor, scriptButtons = {}}
	env.scriptingFrame.IsVisible = function() return root:IsVisible() end
	env.mainFrame = env.scriptingFrame
	env.import_text_editor = importer
	importer.scripts = {}
	importer.SetScript = function(self, event, callback) self.scripts[event] = callback end
	env.codeButtonSize = {100, 20}
	env.tinsert = table.insert
	env.DF = {
		GetTemplate = function() return {} end,
		CreateButton = function(_, parent, callback)
			local button = frame(parent)
			button.callback = callback
			return button
		end,
	}
	env.on_select_code_type = function() end
	local source = section("Plater_ScriptingPanels.lua", "\t\t\t\tlocal code_oninit_button =", "\n\t\t\tfunction scriptingFrame.UpdateScriptsButton")
	run(source, env)
	equal(#env.scriptingFrame.scriptButtons, 5)
	local callbacks = section("Plater_ScriptingPanels.lua",
		'\t\timport_text_editor:SetScript ("OnShow"', "\n\t\tmainFrame.ImportTextEditor =")
	run(callbacks, env)
	local okay = frame(importer)
	for _, importing in ipairs({true, false, true, false}) do
		importer.shown = importing
		importer.scripts[importing and "OnShow" or "OnHide"]()
		for _, button in ipairs(env.scriptingFrame.scriptButtons) do
			equal(button.parent, env.scriptingFrame)
			equal(button:IsVisible(), not importing)
			equal(button.enabled, true)
		end
		equal(editor.shown, not importing)
		equal(okay:IsVisible(), importing)
	end
	editor:Hide()
	for _, button in ipairs(env.scriptingFrame.scriptButtons) do
		assert(button:IsVisible(), "code tab must be accessible when options hide the editor")
	end
	env.on_select_code_type = nil
	-- Modding uses the same dialog without script code-selection buttons.
	env.mainFrame.scriptButtons = nil
	importer.scripts.OnShow()
	importer.scripts.OnHide()
	local shared = section("Plater_ScriptingPanels.lua", "\tlocal create_import_box =", "\n\tlocal create_code_editor =")
	assert(shared:find("mainFrame.CodeEditorLuaEntry:Hide()", 1, true))
	assert(shared:find("mainFrame.CodeEditorLuaEntry:Show()", 1, true))
	local text = read("Plater_ScriptingPanels.lua")
	for _, panel in ipairs({"scriptingFrame", "hookFrame"}) do
		assert(text:find(panel .. '.ImportTextEditor.OkayButton:SetPoint ("topright", ' ..
			panel .. '.ImportTextEditor, "bottomright", 0, -10)', 1, true))
	end
end)

test("selecting a script restores the editor from import and hidden states", function()
	for _, panel in ipairs({"scriptingFrame", "hookFrame"}) do
		local source = section("Plater_ScriptingPanels.lua", "\tfunction " .. panel .. ".EditScript (script_id)",
			panel == "scriptingFrame" and "\n\t--add a trigger" or "\n\t\n\t\n\thookFrame:SetScript")
		local env = environment(70300)
		local function frame(shown)
			return {
				shown = shown,
				Show = function(self) self.shown = true end,
				Hide = function(self) self.shown = false end,
			}
		end
		local ui = {
			ImportTextEditor = frame(true), CodeEditorLuaEntry = frame(false),
			ScriptOptionsPanelAdmin = frame(true), ScriptOptionsPanelUser = frame(true),
			EditScriptFrame = frame(false),
		}
		ui.ImportTextEditor.IsImporting, ui.ImportTextEditor.IsExporting = true, true
		ui.EditScriptFrame.UnlockFrame = function(self) self.unlocked = true end
		local script = {Hooks = {Constructor = "custom code"}}
		ui.GetScriptObject = function() return script end
		local refreshed = 0
		ui.UpdateEditingPanel = function()
			refreshed = refreshed + 1
			assert(ui.CodeEditorLuaEntry.shown)
			assert(not ui.ImportTextEditor.shown)
		end
		env[panel] = ui
		run(source, env)
		ui.EditScript(1)
		equal(env.currentEditingScript, script)
		assert(ui.EditScriptFrame.shown and ui.EditScriptFrame.unlocked)
		assert(ui.CodeEditorLuaEntry.shown)
		assert(not ui.ImportTextEditor.shown)
		equal(ui.ImportTextEditor.IsImporting, nil)
		equal(ui.ImportTextEditor.IsExporting, nil)
		assert(not ui.ScriptOptionsPanelAdmin.shown)
		assert(not ui.ScriptOptionsPanelUser.shown)
		ui.CodeEditorLuaEntry.shown = false
		ui.EditScript(script)
		assert(ui.CodeEditorLuaEntry.shown)
		equal(refreshed, 2)
	end
end)

test("unsupported Legion CVars are omitted from startup and profile restoration", function()
	local startup = section("Plater.lua", "\t\tfunction Plater.ForceCVars()", "\n\t--schedule data update")
	local storage = section("Plater.lua", "\tlocal cvars_to_store = {", "\n\t--keep this separate")
	local unsupported = {
		nameplateNotSelectedAlpha = true, nameplateRemovalAnimation = true,
		nameplateShowFriendlyBuffs = true, nameplateShowPersonalCooldowns = true,
	}
	for _, legion in ipairs({true, false}) do
		local env = environment(legion and 70300 or 100205)
		env.platerInternal = {IsLegion = legion}
		env.IS_WOW_PROJECT_MAINLINE, env.IS_WOW_PROJECT_NOT_MAINLINE = true, false
		env.InCombatLockdown = function() return false end
		env.Plater = {}
		env.GetCVar = function() return "1" end
		local writes = {}
		env.SetCVar = function(name) writes[name] = true end
		run(startup, env)
		env.Plater.ForceCVars()
		assert(writes.nameplateMinAlpha and writes.nameplateSelectedAlpha)
		for name in pairs(unsupported) do
			equal(not not writes[name], not legion)
		end
		local stored = run(storage .. "\nreturn cvars_to_store", env)
		if legion then
			equal(stored.NamePlateClassificationScale, nil)
			equal(stored.nameplateNotSelectedAlpha, nil)
			equal(stored.nameplateRemovalAnimation, nil)
		end
		assert(stored.nameplateMinAlpha)
	end
end)

test("first-run classification scaling is skipped only on Legion", function()
	local source = section("Plater.lua", "\t--> reset the horizontal and vertical scale", "\n\t--> make the selection")
	for _, version in ipairs({70300, 100205, 30403}) do
		local env = environment(version)
		env.platerInternal = {IsLegion = version == 70300}
		env.IS_WOW_PROJECT_MAINLINE = version == 70300 or version == 100205
		env.CVAR_ENABLED = "1"
		local writes = {}
		env.SetCVar = function(name, value) writes[name] = value end
		run(source, env)
		equal(writes.NamePlateHorizontalScale, "1")
		equal(writes.NamePlateVerticalScale, "1")
		equal(writes.NamePlateClassificationScale, version == 100205 and "1" or nil)
	end
end)

test("Quick Hide retains addon behavior without writing Legion removal animation", function()
	local option = section("Plater_OptionsPanel.lua",
		'\t\t\tget = function() return Plater.db.profile.quick_hide end,', '\n\t\t\tnocombat = true,')
	local setter = assert(option:match("set = (function.-\n\t\t\tend),"))
	for _, legion in ipairs({true, false}) do
		local env = environment(legion and 70300 or 100205)
		env.platerInternal = {IsLegion = legion}
		env.CVAR_DISABLED, env.CVAR_ENABLED = "0", "1"
		local writes, refreshes = {}, 0
		env.Plater = {db = {profile = {}}, UpdateAllPlates = function() refreshes = refreshes + 1 end}
		env.SetCVar = function(name, value)
			equal(name, "nameplateRemovalAnimation")
			writes[#writes + 1] = value
		end
		local callback = run("return " .. setter, env)
		callback(nil, nil, true)
		equal(env.Plater.db.profile.quick_hide, true)
		callback(nil, nil, false)
		equal(env.Plater.db.profile.quick_hide, false)
		equal(refreshes, 2)
		equal(#writes, legion and 0 or 2)
		if not legion then
			equal(writes[1], "0")
			equal(writes[2], "1")
		end
	end
end)

test("race filters have usable names with absent, partial, or localized race APIs", function()
	local source = section("libs\\DF\\fw.lua", "DF.RaceCache = {}", "\n--get a list of talents for the current spec")
	for _, mode in ipairs({"absent", "namespace-only", "partial", "localized"}) do
		local env = environment(70300)
		env.tinsert = table.insert
		env.IS_WOW_PROJECT_MAINLINE = true
		env.DF = {RaceList = {[1] = "Human", [2] = "Orc"}, AlliedRaceList = {[27] = "Nightborne"}}
		env.UnitRace = function() return "Localized Human", "Human", 1 end
		if mode ~= "absent" then env.C_CreatureInfo = {} end
		if mode == "partial" or mode == "localized" then
			env.C_CreatureInfo.GetRaceInfo = function(id)
				if id <= 2 then
					return {raceID = id, raceName = mode == "localized" and "Localized Race" or nil}
				end
			end
			env.C_AlliedRaces = {GetRaceInfoByID = function(id)
				if id == 27 then return {raceID = 27} end
			end}
		end
		run(source, env)
		local races = env.DF:GetCharacterRaceList()
		equal(#races, (mode == "partial" or mode == "localized") and 3 or 2)
		for _, race in ipairs(races) do
			assert(type(race.Name) == "string" and #race.Name > 0)
			assert(type(race.FileString) == "string")
			assert(race.Name:sub(1, 15))
		end
		if mode == "partial" then equal(races[1].Name, "Human") end
		if mode == "localized" then equal(races[1].Name, "Localized Race") end
		if mode == "absent" then equal(races[1].Name, "Localized Human") end
		equal(env.DF:GetCharacterRaceList(), races)
	end
end)

test("load conditions assign callbacks before construction and suppress programmatic changes", function()
	local env = environment(70300)
	local calls = 0
	env.callback = function() calls = calls + 1 end
	env.optionsTable = {race = {}}
	env.loadConditionsFrame = {}
	env.detailsFramework = {Dispatch = function(_, func)
		assert(type(func) == "function", "missing callback")
		func()
	end}
	local initialization = section("libs\\DF\\loadconditions.lua",
		"\t\tloadConditionsFrame.OptionsTable = optionsTable", "\n\n\t\tdetailsFramework:ApplyStandardBackdrop")
	run(initialization, env)
	equal(env.loadConditionsFrame.CallbackFunc, env.callback)
	assert(env.loadConditionsFrame.IsRefreshing)
	local callback = section("libs\\DF\\loadconditions.lua",
		"\t\t\tloadConditionsFrame.RunCallback = function()", "\n\n\t\t--when the user click")
	run(callback, env)
	env.loadConditionsFrame.RunCallback()
	equal(calls, 0)
	local frame = env.loadConditionsFrame
	frame.EditingLabel = {SetText = function() end}
	frame.Title = {SetText = function() end}
	frame.Show = function() frame.RunCallback() end
	frame.Refresh = function() frame.RunCallback() end
	env.frameOptions = {name = "Test Mod", title = "Load Conditions"}
	local source = read("libs\\DF\\loadconditions.lua")
	local start = assert(source:find("\n\t--set the options table", 1, true))
	run("function openPanel()\n" .. source:sub(start), env)
	env.openPanel()
	equal(calls, 0)
	equal(frame.IsRefreshing, false)
	frame.RunCallback()
	equal(calls, 1)
	-- Reopening for a different mod must use its callback and table.
	env.callback = function() calls = calls + 10 end
	env.optionsTable = {class = {}}
	env.openPanel()
	equal(calls, 1)
	equal(frame.OptionsTable, env.optionsTable)
	frame.RunCallback()
	equal(calls, 11)
end)

test("both Legion manifests load compatibility before libraries", function()
	for _, path in ipairs({"Plater.toc", "Plater_Legion.toc"}) do
		local text = read(path)
		assert(text:find("## Interface: 70300", 1, true))
		local shim = assert(text:find("Plater_LegionCompat.lua", 1, true))
		local templates = assert(text:find("Plater_LegionCompat.xml", 1, true))
		local libraries = assert(text:find("libs\\libs.xml", 1, true))
		assert(shim < templates and templates < libraries)
	end
end)

print(passed .. " Legion compatibility regression tests passed.")
