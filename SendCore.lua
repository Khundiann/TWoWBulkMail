local mod = TWoWBulkMail

local L = mod.L

local SUFFIX_CHAR = "\32"

local strsub = string.sub
local strmatch = string.match
local strlen = strlen
local strsplit = strsplit

local function getOriginalGlobal(name, fallback)
	local tm = _G and _G.TurtleMail or nil
	if tm and tm.orig and type(tm.orig[name]) == "function" then
		return tm.orig[name]
	end
	return fallback
end

function mod:GetOriginalGlobal(name, fallback)
	return getOriginalGlobal(name, fallback)
end

function mod:ItemCacheInit()
	_G.TWoWBulkMailItemCache = _G.TWoWBulkMailItemCache or {}
	self.state.itemCache = _G.TWoWBulkMailItemCache
end

function mod:ItemCacheRemember(itemId)
	if not itemId then
		return
	end
	itemId = tonumber(itemId)
	if not itemId then
		return
	end

	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	if not name then
		return
	end

	local cache = self.state.itemCache or _G.TWoWBulkMailItemCache
	if not cache then
		return
	end

	cache[itemId] = cache[itemId] or {}
	cache[itemId].name = name
	if icon then
		cache[itemId].icon = icon
	end
end

function mod:ItemCacheGet(itemId)
	if not itemId then
		return
	end
	itemId = tonumber(itemId)
	if not itemId then
		return
	end

	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	if name then
		self:ItemCacheRemember(itemId)
		return name, icon
	end

	local cache = self.state.itemCache or _G.TWoWBulkMailItemCache
	if cache and cache[itemId] then
		return cache[itemId].name, cache[itemId].icon
	end
end

function mod:SafeTabletClose(tabletID)
	local tablet = self.libs and self.libs.tablet or nil
	if not (tablet and tablet.Close) then
		return
	end

	if not tabletID then
		return tablet:Close()
	end

	local info = tablet.registry and tablet.registry[tabletID] or nil
	if not info then
		return
	end

	local detachedData = info.detachedData
	if detachedData and detachedData.detached then
		local tooltip = info.tooltip
		if tooltip then
			if tooltip.Hide and tooltip:IsShown() then
				tooltip:Hide()
			end
			tooltip.notInUse = true
			if tooltip.registration then
				tooltip.registration.tooltip = nil
			end
			tooltip.registration = nil
		end
		info.tooltip = nil
		detachedData.detached = nil
		return
	end

	return tablet:Close(tabletID)
end

function mod:IsTabletOpen(tabletID)
	local tablet = self.libs and self.libs.tablet or nil
	if not (tablet and tablet.registry and tabletID) then
		return false
	end

	local info = tablet.registry[tabletID]
	if not info then
		return false
	end

	if info.tooltip and info.tooltip.IsShown and info.tooltip:IsShown() then
		return true
	end

	local detachedData = info.detachedData
	if detachedData and detachedData.detached and info.tooltip and info.tooltip.IsShown and info.tooltip:IsShown() then
		return true
	end

	return false
end

function mod:InitDB()
	self:ItemCacheInit()
	self:RegisterDB("TWoWBulkMailDB")
	self:RegisterDefaults("profile", {
		tablet_data = { detached = true, anchor = "TOPLEFT", offsetx = 340, offsety = -104 },
		rules_tablet_data = { detached = true, anchor = "TOPLEFT", offsetx = 580, offsety = -104 },
	})
	self:RegisterDefaults("realm", {
		autoSendRules = {
			["*"] = {
				include = {
					items = {},
					itemTypes = {},
					ptSets = {},
				},
				exclude = {
					items = {},
					itemTypes = {},
					ptSets = {},
				},
				options = {
					sendAs = "normal", -- "normal" | "cod"
					codAmount = 0, -- copper
					moneyMode = "none", -- "none" | "amount"
					moneyAmount = 0, -- copper
					subject = "",
					body = "",
					maxMailsPerOpen = 0, -- 0 = unlimited
				},
			},
		},
	})
	self:RegisterDefaults("char", {
		defaultDestination = nil,
		isSink = false,
		attachMulti = true,
		matchPolicy = "last",
		globalExclude = {
			items = {},
			itemTypes = {},
			ptSets = {},
		},
	})

	mod.state.autoSendRules = self.db.realm.autoSendRules
	mod.state.globalExclude = self.db.char.globalExclude

	mod.state.destCache = {}
	mod.state.reverseDestCache = {}
	for dest in pairs(mod.state.autoSendRules) do
		mod.state.destCache[dest] = true
		table.insert(mod.state.reverseDestCache, dest)
	end

	mod.state.auctionItemClasses = {}
	for i, itype in ipairs({ GetAuctionItemClasses() }) do
		mod.state.auctionItemClasses[itype] = { GetAuctionItemSubClasses(i) }
	end

	mod.state.sendCache = mod.state.sendCache or {}
	mod.state.destSendCache = mod.state.destSendCache or {}
	mod.state.numItems = mod.state.numItems or 0
	mod.state.cacheLock = false
	mod.state.sendDest = ""
	mod.state.suffix = SUFFIX_CHAR
	mod.state.rulesAltered = true
end

function mod:GetDestinationOptions(dest)
	if not dest or dest == "" then
		return nil
	end

	local rules = self.state.autoSendRules and self.state.autoSendRules[dest] or nil
	if not rules then
		return nil
	end

	rules.options = rules.options or {}
	local opt = rules.options
	if not opt.sendAs then
		opt.sendAs = "normal"
	end
	if type(opt.codAmount) ~= "number" then
		opt.codAmount = tonumber(opt.codAmount) or 0
	end
	if not opt.moneyMode then
		opt.moneyMode = "none"
	end
	if type(opt.moneyAmount) ~= "number" then
		opt.moneyAmount = tonumber(opt.moneyAmount) or 0
	end
	if type(opt.subject) ~= "string" then
		opt.subject = ""
	end
	if type(opt.body) ~= "string" then
		opt.body = ""
	end
	if type(opt.maxMailsPerOpen) ~= "number" then
		opt.maxMailsPerOpen = tonumber(opt.maxMailsPerOpen) or 0
	end

	return opt
end

function mod:MoveDestination(dest, delta)
	if not dest or dest == "" then
		return
	end

	local list = self.state.reverseDestCache
	if not list then
		return
	end

	local idx
	for i = 1, table.getn(list) do
		if list[i] == dest then
			idx = i
			break
		end
	end
	if not idx then
		return
	end

	local newIdx = idx + (delta or 0)
	if newIdx < 1 or newIdx > table.getn(list) then
		return
	end

	local tmp = list[idx]
	list[idx] = list[newIdx]
	list[newIdx] = tmp

	self:RulesMarkAltered()
end

function mod:InitCommands()
	self.opts = {
		type = "group",
		args = {
			defaultdest = {
				name = L["Default destination"],
				type = "text",
				aliases = L["dd"],
				desc = L["Set the default recipient of your AutoSend rules"],
				get = function()
					return self.db.char.defaultDestination
				end,
				set = function(dest)
					self.db.char.defaultDestination = dest
				end,
				usage = "<destination>",
			},
			autosend = {
				name = L["AutoSend"],
				type = "group",
				aliases = L["as"],
				desc = L["AutoSend Options"],
				args = {
					edit = {
						name = L["edit"],
						type = "execute",
						aliases = L["rules, list, ls"],
						desc = L["Edit AutoSend definitions."],
						func = function()
							if self:IsTabletOpen("TWoWBulkMail_AutoSendEditTablet") then
								self:SafeTabletClose("TWoWBulkMail_AutoSendEditTablet")
							else
								self.libs.tablet:Open("TWoWBulkMail_AutoSendEditTablet")
							end
						end,
					},
					add = {
						name = L["add"],
						type = "text",
						aliases = L["+"],
						desc = L["Add an item rule by itemlink or PeriodicTable-2.0 set manually."],
						input = true,
						set = "AddAutoSendRule",
						usage = L["[destination] <itemlink|PeriodicTable.Set> [itemlink2|Set2 itemlink3|Set3 ...]"],
						get = false,
						validate = function(arg1)
							return self:RulesValidateDefaultDestOrDest(arg1)
						end,
						error = L["Please supply a destination for the item(s), or set a default destination with |cff00ffaa/bulkmail defaultdest|r."],
					},
					rmdest = {
						name = L["rmdest"],
						type = "text",
						aliases = L["rmd"],
						desc = L["Remove all rules corresponding to a particular destination."],
						input = true,
						set = "RemoveDestination",
						usage = L["<destination>"],
						get = false,
						validate = function(dest)
							return mod.state.destCache[dest]
						end,
					},
					clear = {
						name = L["clear"],
						type = "execute",
						desc = L["Clear all rules for this realm."],
						func = function()
							self:ResetDB("realm")
							mod.state.autoSendRules = self.db.realm.autoSendRules
							mod.state.destCache = {}
							mod.state.reverseDestCache = {}
							for dest in pairs(mod.state.autoSendRules) do
								mod.state.destCache[dest] = true
								table.insert(mod.state.reverseDestCache, dest)
							end
							self.libs.tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
							self:RulesMarkAltered()
						end,
						confirm = true,
					},
				},
			},
			sink = {
				name = L["Sink"],
				type = "toggle",
				desc = L["Disable AutoSend queue auto-filling for this character."],
				get = function()
					return self.db.char.isSink
				end,
				set = function(v)
					self.db.char.isSink = v
				end,
			},
			attachmulti = {
				name = L["Attach multiple items"],
				type = "toggle",
				desc = L["Attach as many items as possible per mail."],
				get = function()
					return self.db.char.attachMulti
				end,
				set = function(v)
					self.db.char.attachMulti = v
				end,
			},
			gui = {
				type = "execute",
				name = "GUI",
				desc = "Open the send queue window.",
				func = function()
					self:ShowSendQueueGUI()
				end,
			},
			status = {
				type = "execute",
				name = "Status",
				desc = "Print basic addon status.",
				func = function()
					self:Print("TWoWBulkMail " .. (self.VERSION or "") .. " loaded.")
				end,
			},
		},
	}

	self:RegisterChatCommand({ "/twbm", "/twbulkmail", "/bm", "/bulkmail" }, self.opts)
end

function mod:InitEvents()
	self:RegisterEvent("MAIL_SHOW")
	self:RegisterEvent("MAIL_CLOSED")
	self:RegisterEvent("MAIL_SEND_SUCCESS")
	self:RegisterEvent("UI_ERROR_MESSAGE")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")

	if MailFrame and MailFrame:IsVisible() then
		self:MAIL_SHOW()
	end
end

function mod:InitUI()
	self:RegisterSendQueueGUI()
	self:RegisterAutoSendEditTablet()
	self:RegisterAddRuleDewdrop()
end

function mod:ShutdownUI()
	if mod.state.addRuleAnchor and self.libs.dewdrop:IsRegistered(mod.state.addRuleAnchor) then
		self.libs.dewdrop:Unregister(mod.state.addRuleAnchor)
	end
	if self.libs.tablet:IsRegistered("TWoWBulkMail_AutoSendEditTablet") then
		self.libs.tablet:Unregister("TWoWBulkMail_AutoSendEditTablet")
	end
	if self.libs.tablet:IsRegistered("TWoWBulkMail_SendQueueTablet") then
		self.libs.tablet:Unregister("TWoWBulkMail_SendQueueTablet")
	end
end

function mod:MAIL_SHOW()
	if mod.state.rulesAltered then
		self:RulesCacheBuild()
	end
	if type(_G.ContainerFrameItemButton_OnModifiedClick) == "function" then
		self:Hook("ContainerFrameItemButton_OnModifiedClick")
	else
		self:Hook("ContainerFrameItemButton_OnClick")
	end
	self:SecureHook("SendMailFrame_CanSend")
	self:SecureHook("ContainerFrame_Update")
	self:SecureHook("MoneyInputFrame_OnTextChanged", SendMailFrame_CanSend)
	self:SecureHook("SetItemRef")
	if SendMailMailButton and SendMailMailButton.HasScript and SendMailMailButton:HasScript("OnClick") then
		self:HookScript(SendMailMailButton, "OnClick", "SendMailMailButton_OnClick")
	end
	if SendMailNameEditBox and SendMailNameEditBox.HasScript and SendMailNameEditBox:HasScript("OnTextChanged") then
		self:HookScript(SendMailNameEditBox, "OnTextChanged", "SendMailNameEditBox_OnTextChanged")
	end
	if type(_G.MailFrameTab_OnClick) == "function" then
		self:Hook("MailFrameTab_OnClick")
	end
	if type(_G.StaticPopup_Show) == "function" then
		self:Hook("StaticPopup_Show")
	end

	SendMailMailButton:Enable()
end

function mod:MAIL_CLOSED()
	self:StopSendPipeline("mailbox closed")
	self:UnhookAll()
	self:SendCacheCleanup()
	self:HideSendQueueGUI()
	self:CancelScheduledEvent("TWoWBulkMail_SendNext")
	self.state.sendStatus = {
		state = "idle",
		sent = 0,
		total = 0,
		currentDest = nil,
		currentItem = nil,
		error = nil,
	}
end

function mod:StaticPopup_Show(which, text_arg1, text_arg2, data)
	local dialog = nil
	if self.hooks and self.hooks.StaticPopup_Show then
		dialog = self.hooks.StaticPopup_Show(which, text_arg1, text_arg2, data)
	end

	local st = self.state.sendPipeline
	if which == "SEND_MONEY" and st and st.sending and st.awaiting and st.expectSendMoney then
		st.expectSendMoney = nil
		local run = self.state.sendRun
		if run and st.current and st.current.id and run.jobs and run.jobs[st.current.id] then
			run.jobs[st.current.id].status = "confirming"
		end

		local okButton = nil
		if dialog and dialog.GetName then
			okButton = dialog.button1 or _G[dialog:GetName() .. "Button1"]
		end
		if okButton and okButton.Click then
			okButton:Click()
		else
			self:StopSendPipeline("Failed to confirm SEND_MONEY popup.")
		end
	end

	return dialog
end

mod.PLAYER_ENTERING_WORLD = mod.MAIL_CLOSED

local function handleContainerClick(
	self,
	hookName,
	a1,
	a2,
	a3,
	a4,
	a5,
	a6,
	a7,
	a8,
	a9,
	a10,
	a11,
	a12,
	a13,
	a14,
	a15,
	a16,
	a17,
	a18,
	a19,
	a20
)
	-- Only intercept the click patterns that BulkMail owns.
	-- Everything else should behave like the default UI.
	if IsControlKeyDown() and IsShiftKeyDown() then
		self:QuickSend(_G.this)
		return
	end
	if IsAltKeyDown() then
		self:SendCacheToggle(_G.this)
		return
	end

	if self.hooks and self.hooks[hookName] then
		return self.hooks[hookName](
			a1,
			a2,
			a3,
			a4,
			a5,
			a6,
			a7,
			a8,
			a9,
			a10,
			a11,
			a12,
			a13,
			a14,
			a15,
			a16,
			a17,
			a18,
			a19,
			a20
		)
	end
end

function mod:ContainerFrameItemButton_OnModifiedClick(
	a1,
	a2,
	a3,
	a4,
	a5,
	a6,
	a7,
	a8,
	a9,
	a10,
	a11,
	a12,
	a13,
	a14,
	a15,
	a16,
	a17,
	a18,
	a19,
	a20
)
	return handleContainerClick(
		self,
		"ContainerFrameItemButton_OnModifiedClick",
		a1,
		a2,
		a3,
		a4,
		a5,
		a6,
		a7,
		a8,
		a9,
		a10,
		a11,
		a12,
		a13,
		a14,
		a15,
		a16,
		a17,
		a18,
		a19,
		a20
	)
end

function mod:ContainerFrameItemButton_OnClick(
	a1,
	a2,
	a3,
	a4,
	a5,
	a6,
	a7,
	a8,
	a9,
	a10,
	a11,
	a12,
	a13,
	a14,
	a15,
	a16,
	a17,
	a18,
	a19,
	a20
)
	return handleContainerClick(
		self,
		"ContainerFrameItemButton_OnClick",
		a1,
		a2,
		a3,
		a4,
		a5,
		a6,
		a7,
		a8,
		a9,
		a10,
		a11,
		a12,
		a13,
		a14,
		a15,
		a16,
		a17,
		a18,
		a19,
		a20
	)
end

function mod:SendMailFrame_CanSend()
	if
		self.state.sendCache and next(self.state.sendCache)
		or self:GetSendMailItem()
		or (SendMailSendMoneyButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney) > 0)
	then
		SendMailMailButton:Enable()
		SendMailCODButton:Enable()
	end
	self:ScheduleEvent("TWoWBulkMail_canSendRefresh", self.RefreshSendQueueGUI, 0.1, self)
end

function mod:ContainerFrame_Update(...)
	self:ShadeContainerFrame(arg1)
end

function mod:SetItemRef(link, ...)
	if SendMailNameEditBox:IsVisible() and IsControlKeyDown() then
		if strsub(link, 1, 6) == "player" then
			local name = strsplit(":", strsub(link, 8))
			if name and strlen(name) > 0 then
				SendMailNameEditBox:SetText(name)
			end
		end
	end
end

function mod:SendMailMailButton_OnClick(frame, a1)
	self.state.cacheLock = true
	self.state.sendDest = SendMailNameEditBox:GetText()

	if not self:GetSendMailItem() and (not self.state.sendCache or not next(self.state.sendCache)) then
		return
	end

	self:OrganizeSendCache()
	self:StartSendPipeline()
end

function mod:MailFrameTab_OnClick(tab, ...)
	local ret = self.hooks.MailFrameTab_OnClick(tab, unpack(arg))

	if SendMailFrame and SendMailFrame:IsShown() then
		self:RulesCacheBuild()
		self:ShowSendQueueGUI()
		self:SendCacheBuild(SendMailNameEditBox:GetText())
	else
		self:HideSendQueueGUI()
	end

	return ret
end

function mod:SendMailNameEditBox_OnTextChanged(frame, a1)
	self:SendCacheBuild(SendMailNameEditBox:GetText())
	if not self.state.cacheLock then
		self.state.sendDest = SendMailNameEditBox:GetText()
	end
	return self.hooks[frame].OnTextChanged(frame, a1)
end

function mod:AddDestination(dest)
	local _ = mod.state.autoSendRules[dest]
	mod.state.destCache[dest] = true
	table.insert(mod.state.reverseDestCache, dest)
	self:RulesMarkAltered()
end

function mod:RemoveDestination(dest)
	mod.state.autoSendRules[dest] = nil
	mod.state.destCache[dest] = nil
	for i = 1, table.getn(mod.state.reverseDestCache) do
		if mod.state.reverseDestCache[i] == dest then
			table.remove(mod.state.reverseDestCache, i)
			break
		end
	end
	self:RulesMarkAltered()
end

function mod:AddAutoSendRule(...)
	local dest = arg and arg[1] or nil
	local start = 2

	if strmatch(dest or "", "^|[cC]") or self:PtHasSet(dest) then
		dest = self.db.char.defaultDestination
		start = 1
	end

	self:AddDestination(dest)

	local n = arg and arg.n or 0
	for i = start, n do
		local v = arg[i]
		local itemId = tonumber(strmatch(v or "", "item:(%d+)"))
		if itemId then
			table.insert(mod.state.autoSendRules[dest].include.items, itemId)
			self.libs.tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
			self:Print("%s - %s", v, dest)
		elseif self:PtHasSet(v) then
			table.insert(mod.state.autoSendRules[dest].include.ptSets, v)
			self.libs.tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
			self:Print("%s - %s", v, dest)
		end
	end

	self:RulesMarkAltered()
end

function mod:StopSendPipeline(reason)
	if not self.state.sendPipeline then
		return
	end

	local st = self.state.sendPipeline
	local run = self.state.sendRun
	if run then
		run.stopReason = reason
		run.finishedAt = time and time() or nil
		if st.current and st.current.id and run.jobs and run.jobs[st.current.id] then
			local job = run.jobs[st.current.id]
			if job.status ~= "sent" then
				job.status = "failed"
				job.error = reason or job.error
			end
		end
	end
	self.state.sendStatus = self.state.sendStatus or {}
	self.state.sendStatus.sent = st.sent or 0
	self.state.sendStatus.total = st.total or 0
	self.state.sendStatus.currentDest = nil
	self.state.sendStatus.currentItem = nil
	if reason and reason ~= "" then
		self.state.sendStatus.state = "stopped"
		self.state.sendStatus.error = reason
	else
		self.state.sendStatus.state = "done"
		self.state.sendStatus.error = nil
	end

	self.state.sendPipeline = nil
	self:CancelScheduledEvent("TWoWBulkMail_SendNext")
	self.state.cacheLock = false

	if CursorHasItem and CursorHasItem() then
		ClearCursor()
	end

	if reason and reason ~= "" then
		self:Print("Send stopped: %s", reason)
	end
	self:RefreshSendQueueGUI()

	if run then
		self.state.lastSendRun = run
	end
	self.state.sendRun = nil
end

function mod:MAIL_SEND_SUCCESS()
	local st = self.state.sendPipeline
	if not (st and st.sending and st.awaiting) then
		return
	end

	st.awaiting = false
	st.sent = (st.sent or 0) + 1
	local run = self.state.sendRun
	if run and st.current and st.current.id and run.jobs and run.jobs[st.current.id] then
		local job = run.jobs[st.current.id]
		job.status = "sent"
		job.error = nil
	end
	if self.state.sendStatus then
		self.state.sendStatus.sent = st.sent or 0
		self.state.sendStatus.total = st.total or 0
		self.state.sendStatus.currentDest = nil
		self.state.sendStatus.currentItem = nil
		self.state.sendStatus.error = nil
		self.state.sendStatus.state = st.paused and "paused" or "sending"
	end

	if st.current and st.current.kind == "bag" then
		self:SendCacheRemove(st.current.bag, st.current.slot)
	end
	st.current = nil

	self:UpdateSendCost()
	self:RefreshSendQueueGUI()

	if st.jobs and next(st.jobs) then
		self:ScheduleEvent("TWoWBulkMail_SendNext", self.SendPipelineNext, 0.2, self)
	else
		self:StopSendPipeline()
	end
end

function mod:UI_ERROR_MESSAGE()
	local st = self.state.sendPipeline
	if not (st and st.sending) then
		return
	end

	local msg = arg1
	if not msg or msg == "" then
		return
	end

	if
		msg == ERR_MAIL_TO_SELF
		or msg == ERR_PLAYER_WRONG_FACTION
		or msg == ERR_MAIL_TARGET_NOT_FOUND
		or msg == ERR_MAIL_REACHED_CAP
	then
		self:StopSendPipeline(msg)
	end
end

function mod:BuildSendPipelineJobs()
	local jobs = {}
	local run = {
		startedAt = time and time() or nil,
		finishedAt = nil,
		stopReason = nil,
		jobs = {},
		order = {},
		nextId = 0,
	}

	local function addJob(job)
		run.nextId = (run.nextId or 0) + 1
		job.id = run.nextId
		table.insert(jobs, job)

		run.jobs[job.id] = {
			id = job.id,
			kind = job.kind,
			dest = job.dest,
			bag = job.bag,
			slot = job.slot,
			link = job.link,
			qty = job.qty,
			status = "pending",
			error = nil,
		}
		table.insert(run.order, job.id)
	end

	if self:GetSendMailItem() then
		addJob({ kind = "attached", link = self:GetSendMailItemLink(), qty = 1 })
	end

	if self.state.destSendCache and next(self.state.destSendCache) then
		for dest, bagslots in pairs(self.state.destSendCache) do
			for i = 1, table.getn(bagslots) do
				local bag, slot = bagslots[i][1], bagslots[i][2]
				local link = GetContainerItemLink(bag, slot)
				local _, qty = GetContainerItemInfo(bag, slot)
				addJob({ kind = "bag", dest = dest, bag = bag, slot = slot, link = link, qty = qty })
			end
		end
	end

	return jobs, run
end

function mod:StartSendPipeline()
	if self.state.sendPipeline and self.state.sendPipeline.sending then
		return
	end

	if not (MailFrame and MailFrame:IsVisible() and SendMailFrame and SendMailFrame:IsShown()) then
		self:Print(L["Open the Send Mail tab first."])
		return
	end

	local jobs, run = self:BuildSendPipelineJobs()
	if not next(jobs) then
		return
	end

	self.state.sendRun = run
	self.state.lastSendRun = nil

	self.state.sendPipeline = {
		sending = true,
		awaiting = false,
		current = nil,
		jobs = jobs,
		total = table.getn(jobs),
		sent = 0,
		toOverride = (self.state.sendDest ~= "" and self.state.sendDest) or nil,
		uiSubject = SendMailSubjectEditBox and SendMailSubjectEditBox:GetText() or "",
		uiBody = SendMailBodyEditBox and SendMailBodyEditBox:GetText() or "",
		uiCod = SendMailCODButton and SendMailCODButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney) or 0,
		uiMoney = SendMailSendMoneyButton and SendMailSendMoneyButton:GetChecked() and MoneyInputFrame_GetCopper(
			SendMailMoney
		) or 0,
		perDestSent = {},
		paused = false,
	}

	self.state.sendStatus = self.state.sendStatus or {}
	self.state.sendStatus.state = "sending"
	self.state.sendStatus.sent = 0
	self.state.sendStatus.total = table.getn(jobs)
	self.state.sendStatus.currentDest = nil
	self.state.sendStatus.currentItem = nil
	self.state.sendStatus.error = nil

	self:SendPipelineNext()
end

function mod:SendPipelineNext()
	local st = self.state.sendPipeline
	if not (st and st.sending) then
		return
	end
	if st.awaiting then
		return
	end
	if st.paused then
		return
	end

	local job = table.remove(st.jobs, 1)
	if not job then
		if self.state.sendRun then
			self.state.sendRun.stopReason = nil
			self.state.sendRun.finishedAt = time and time() or nil
			self.state.lastSendRun = self.state.sendRun
			self.state.sendRun = nil
		end
		self:StopSendPipeline()
		return
	end
	st.current = job

	local dest = st.toOverride
	if not dest or dest == "" then
		if job.dest and job.dest ~= "" then
			dest = job.dest
		elseif self:GetSendMailItem() then
			dest = self:RulesCacheDest(self:GetSendMailItemLink()) or self.db.char.defaultDestination
		end
	end

	if not dest or dest == "" then
		self:RulesPrintNoDefault()
		self:StopSendPipeline("no destination")
		return
	end

	if self.state.sendStatus then
		self.state.sendStatus.state = "sending"
		self.state.sendStatus.sent = st.sent or 0
		self.state.sendStatus.total = st.total or 0
		self.state.sendStatus.currentDest = dest
		if job.kind == "bag" then
			self.state.sendStatus.currentItem = GetContainerItemLink(job.bag, job.slot)
		else
			self.state.sendStatus.currentItem = self:GetSendMailItemLink()
		end
	end

	local run = self.state.sendRun
	if run and job.id and run.jobs and run.jobs[job.id] then
		run.jobs[job.id].dest = dest
		run.jobs[job.id].status = (job.kind == "bag") and "attaching" or "sending"
		run.jobs[job.id].error = nil
		if job.kind == "bag" then
			run.jobs[job.id].link = GetContainerItemLink(job.bag, job.slot) or run.jobs[job.id].link
			local _, qty = GetContainerItemInfo(job.bag, job.slot)
			run.jobs[job.id].qty = qty or run.jobs[job.id].qty
		end
	end

	-- Per-destination options should apply whenever we are sending to a known destination,
	-- even if the user typed the destination manually. We still only overwrite subject/body
	-- when the fields are empty.
	local destOpt = self:GetDestinationOptions(dest)

	if destOpt and destOpt.maxMailsPerOpen and destOpt.maxMailsPerOpen > 0 then
		st.perDestSent[dest] = st.perDestSent[dest] or 0
		if st.perDestSent[dest] >= destOpt.maxMailsPerOpen then
			table.insert(st.jobs, 1, job)
			st.current = nil
			self:StopSendPipeline(
				string.format("Max mails per open reached for %s (%d).", dest, destOpt.maxMailsPerOpen)
			)
			return
		end
	end

	SendMailNameEditBox:SetText(dest)

	local itemName, texture, stackCount
	if job.kind == "bag" then
		local itemLink = GetContainerItemLink(job.bag, job.slot)
		if not itemLink then
			if run and job.id and run.jobs and run.jobs[job.id] then
				run.jobs[job.id].status = "skipped"
				run.jobs[job.id].error = "item missing"
			end
			self:SendCacheRemove(job.bag, job.slot)
			st.current = nil
			self:ScheduleEvent("TWoWBulkMail_SendNext", self.SendPipelineNext, 0, self)
			return
		end

		local clickAttach = self:GetOriginalGlobal("ClickSendMailItemButton", ClickSendMailItemButton)
		local pickupItem = self:GetOriginalGlobal("PickupContainerItem", PickupContainerItem)

		ClearCursor()
		clickAttach()
		ClearCursor()
		pickupItem(job.bag, job.slot)
		clickAttach()

		itemName, texture, stackCount = self:GetSendMailItem()
		if not itemName then
			if CursorHasItem and CursorHasItem() then
				ClearCursor()
			end
			if run and job.id and run.jobs and run.jobs[job.id] then
				run.jobs[job.id].status = "failed"
				run.jobs[job.id].error = L["Failed to attach item to mail."]
			end
			self:StopSendPipeline(string.format("%s: %s", L["Failed to attach item to mail."], itemLink))
			return
		end
	else
		itemName, texture, stackCount = self:GetSendMailItem()
	end

	local baseSubject = st.uiSubject or ""
	if baseSubject == "" and destOpt and type(destOpt.subject) == "string" then
		baseSubject = destOpt.subject
	end

	local subject = baseSubject
	if subject == "" then
		if itemName then
			subject = itemName .. ((stackCount and stackCount > 1) and (" (" .. stackCount .. ")") or "")
		else
			subject = "<no attachments>"
		end
	elseif st.total and st.total > 1 then
		subject = subject .. string.format(" [%d/%d]", (st.sent or 0) + 1, st.total)
	end

	SendMailSubjectEditBox:SetText(subject)

	st.awaiting = true

	-- Important on 1.12/Turtle: attaching items can reset COD/money state.
	-- Apply COD/money as late as possible (right before SendMail).
	local codAmount = st.uiCod or 0
	local moneyAmount = st.uiMoney or 0
	if codAmount <= 0 and moneyAmount <= 0 and destOpt then
		if destOpt.sendAs == "cod" and destOpt.codAmount and destOpt.codAmount > 0 then
			codAmount = destOpt.codAmount
		elseif destOpt.moneyMode == "amount" and destOpt.moneyAmount and destOpt.moneyAmount > 0 then
			moneyAmount = destOpt.moneyAmount
		end
	end

	if codAmount and codAmount > 0 then
		if SendMailSendMoneyButton then
			SendMailSendMoneyButton:SetChecked(nil)
		end
		SendMailCODButton:SetChecked(1)
		if SetSendMailCOD then
			SetSendMailCOD(codAmount)
		else
			MoneyInputFrame_SetCopper(SendMailMoney, codAmount)
		end
	elseif moneyAmount and moneyAmount > 0 then
		SendMailCODButton:SetChecked(nil)
		if SetSendMailCOD then
			SetSendMailCOD(0)
		end
		if SendMailSendMoneyButton then
			SendMailSendMoneyButton:SetChecked(1)
		end
		if SetSendMailMoney then
			SetSendMailMoney(moneyAmount)
		else
			if run and job.id and run.jobs and run.jobs[job.id] then
				run.jobs[job.id].status = "failed"
				run.jobs[job.id].error = "SetSendMailMoney() missing"
			end
			self:StopSendPipeline("SetSendMailMoney() missing; cannot reliably attach money.")
			return
		end
		st.expectSendMoney = true
		if run and job.id and run.jobs and run.jobs[job.id] then
			run.jobs[job.id].status = "confirming"
		end
	else
		if SendMailSendMoneyButton then
			SendMailSendMoneyButton:SetChecked(nil)
		end
		SendMailCODButton:SetChecked(nil)
		if SetSendMailCOD then
			SetSendMailCOD(0)
		end
		if SetSendMailMoney then
			SetSendMailMoney(0)
		else
			MoneyInputFrame_SetCopper(SendMailMoney, 0)
		end
		st.expectSendMoney = nil
	end

	local body = st.uiBody or ""
	if body == "" and destOpt and type(destOpt.body) == "string" then
		body = destOpt.body
	end
	if run and job.id and run.jobs and run.jobs[job.id] then
		run.jobs[job.id].status = "sending"
	end
	SendMail(dest, subject, body)

	if destOpt and destOpt.maxMailsPerOpen and destOpt.maxMailsPerOpen > 0 then
		st.perDestSent[dest] = (st.perDestSent[dest] or 0) + 1
	end
end

function mod:QuickSend(bag, slot)
	if type(slot) ~= "number" then
		bag, slot = bag:GetParent():GetID(), bag:GetID()
	end

	local link = GetContainerItemLink(bag, slot)
	if not link then
		self:Print(L["Cannot determine the item clicked."])
		return
	end

	self.state.cacheLock = true
	if SendMailNameEditBox:GetText() == "" then
		SendMailNameEditBox:SetText(self:RulesCacheDest(link) or self.db.char.defaultDestination or "")
	end

	if SendMailNameEditBox:GetText() ~= "" then
		local clickAttach = self:GetOriginalGlobal("ClickSendMailItemButton", ClickSendMailItemButton)
		local pickupItem = self:GetOriginalGlobal("PickupContainerItem", PickupContainerItem)
		pickupItem(bag, slot)
		clickAttach()
		self:SendMailMailButton_OnClick()
	elseif not self.db.char.defaultDestination then
		self:RulesPrintNoDefault()
		self.state.cacheLock = false
	end
end

function mod:ToggleSendPause()
	local st = self.state.sendPipeline
	if not (st and st.sending) then
		return
	end

	st.paused = not st.paused
	self.state.sendStatus = self.state.sendStatus or {}
	self.state.sendStatus.state = st.paused and "paused" or "sending"
	self.state.sendStatus.sent = st.sent or 0
	self.state.sendStatus.total = st.total or 0
	self.state.sendStatus.error = nil

	if not st.paused then
		self:ScheduleEvent("TWoWBulkMail_SendNext", self.SendPipelineNext, 0, self)
	end
	self:RefreshSendQueueGUI()
end
