local AceLibrary = AceLibrary

TWoWBulkMail = TWoWBulkMail
	or AceLibrary("AceAddon-2.0"):new("AceDB-2.0", "AceEvent-2.0", "AceHook-2.1", "AceConsole-2.0")
local mod = TWoWBulkMail

mod.VERSION = "0.0.1-dev"

mod.L = setmetatable({}, {
	__index = function(_, k)
		return k
	end,
})

mod.libs = {
	tablet = AceLibrary("Tablet-2.0"),
	dewdrop = AceLibrary("Dewdrop-2.0"),
	abacus = AceLibrary("Abacus-2.0"),
	gratuity = AceLibrary("Gratuity-2.0"),
	pt = AceLibrary("PeriodicTable-2.0"),
}

mod.state = mod.state or {}

function mod:OnInitialize()
	self:InitDB()
	self:InitCommands()
end

function mod:OnEnable()
	self:InitEvents()
	self:InitUI()
end

function mod:OnDisable()
	self:ShutdownUI()
	self:UnregisterAllEvents()
	self:UnhookAll()
end
