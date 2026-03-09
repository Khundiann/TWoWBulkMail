local mod = TWoWBulkMail

local tablet = mod.libs.tablet

local fmt = string.format
local strmatch = string.match

local function tabletClose(tabletID)
	mod:SafeTabletClose(tabletID)
end

local function uiClose(tabletID)
	mod:ScheduleEvent(tabletClose, 0, tabletID)
end

local function onSendQueueItemSelect(bag, slot)
	if not (bag and slot and arg1 == "LeftButton") then
		return
	end

	if IsAltKeyDown() then
		mod:SendCacheToggle(bag, slot)
	elseif IsShiftKeyDown() and ChatFrameEditBox:IsVisible() then
		ChatFrameEditBox:Insert(GetContainerItemLink(bag, slot))
	elseif IsControlKeyDown() and not IsShiftKeyDown() then
		DressUpItemLink(GetContainerItemLink(bag, slot))
	else
		SetItemRef(
			strmatch(GetContainerItemLink(bag, slot), "(item:%d+:%d+:%d+:%d+)"),
			GetContainerItemLink(bag, slot),
			arg1
		)
	end
end

local function onDropClick()
	if CursorHasItem() then
		local cursorItem = mod.state.cursorItem
		if not (cursorItem and cursorItem[1] and cursorItem[2]) then
			mod:Print("Drop failed: could not identify the cursor item. Pick it up again, then click the drop area.")
			return
		end

		local bag, slot = cursorItem[1], cursorItem[2]
		ClearCursor()
		mod.state.cursorItem = nil

		mod:ScheduleEvent(function()
			mod:SendCacheAdd(bag, slot)
			mod:RefreshSendQueueGUI()
		end, 0)
	end

	mod:RefreshSendQueueGUI()
end

local function onSendClick()
	if mod.state.sendCache then
		mod:SendMailMailButton_OnClick()
	end
end

local function onPauseResumeClick()
	mod:ToggleSendPause()
end

local function onStopClick()
	mod:StopSendPipeline("stopped by user")
end

local function onAutoSendRulesClick()
	if mod:IsTabletOpen("TWoWBulkMail_AutoSendEditTablet") then
		mod:SafeTabletClose("TWoWBulkMail_AutoSendEditTablet")
	else
		mod.libs.tablet:Open("TWoWBulkMail_AutoSendEditTablet")
	end
end

local function toggleLastRunDetails()
	mod.state.sendUI = mod.state.sendUI or {}
	mod.state.sendUI.showLastRunDetails = not mod.state.sendUI.showLastRunDetails
	mod:RefreshSendQueueGUI()
end

local function formatJobText(job)
	if not job then
		return "<unknown>"
	end
	local link = job.link or "<no link>"
	if job.qty and job.qty > 1 and type(link) == "string" then
		return fmt("%s(%d)", link, job.qty)
	end
	return link
end

function mod:RegisterSendQueueGUI()
	if tablet:IsRegistered("TWoWBulkMail_SendQueueTablet") then
		return
	end

	tablet:Register(
		"TWoWBulkMail_SendQueueTablet",
		"detachedData",
		self.db.profile.tablet_data,
		"strata",
		"HIGH",
		"cantAttach",
		true,
		"dontHook",
		true,
		"showTitleWhenDetached",
		true,
		"children",
		function()
			tablet:SetTitle("TWoW Bulk Mail Send Queue")

			local status = mod.state.sendStatus or {}
			local pipeline = mod.state.sendPipeline
			local sendCache = mod.state.sendCache
			local hasQueue = sendCache and next(sendCache)
			local canSend = false
			if hasQueue then
				canSend = true
				local defaultDest = mod.db and mod.db.char and mod.db.char.defaultDestination or nil
				if mod.state.sendDest ~= "" then
					canSend = true
				elseif not defaultDest then
					for bag, slots in pairs(sendCache) do
						for slot in pairs(slots) do
							local link = GetContainerItemLink(bag, slot)
							if link and not mod:RulesCacheDest(link) then
								canSend = false
								break
							end
						end
						if not canSend then
							break
						end
					end
				end
			end

			local statusText = "Status: Idle"
			if pipeline and pipeline.sending then
				if pipeline.paused then
					statusText = fmt("Status: Paused (%d/%d)", pipeline.sent or 0, pipeline.total or 0)
				else
					statusText = fmt("Status: Sending (%d/%d)", pipeline.sent or 0, pipeline.total or 0)
				end
			elseif status.state == "stopped" then
				statusText = fmt("Status: Stopped - %s", status.error or "unknown error")
			elseif status.state == "done" then
				statusText = fmt("Status: Completed (%d/%d)", status.total or 0, status.total or 0)
			end

			local cat = tablet:AddCategory("columns", 1)
			if pipeline and pipeline.sending then
				cat:AddLine("text", mod.L["Send"], "textR", 0.5, "textG", 0.5, "textB", 0.5)
				cat:AddLine("text", pipeline.paused and "Resume" or "Pause", "func", onPauseResumeClick)
				cat:AddLine("text", "Stop", "func", onStopClick)
			elseif hasQueue and canSend then
				cat:AddLine("text", mod.L["Send"], "func", onSendClick)
				cat:AddLine("text", "Pause", "textR", 0.5, "textG", 0.5, "textB", 0.5)
				cat:AddLine("text", "Stop", "textR", 0.5, "textG", 0.5, "textB", 0.5)
			else
				cat:AddLine("text", mod.L["Send"], "textR", 0.5, "textG", 0.5, "textB", 0.5)
				cat:AddLine("text", "Pause", "textR", 0.5, "textG", 0.5, "textB", 0.5)
				cat:AddLine("text", "Stop", "textR", 0.5, "textG", 0.5, "textB", 0.5)
			end
			if hasQueue or (pipeline and pipeline.sending) then
				cat:AddLine("text", mod.L["Clear"], "func", mod.SendCacheCleanup, "arg1", mod)
			else
				cat:AddLine("text", mod.L["Clear"], "textR", 0.5, "textG", 0.5, "textB", 0.5)
			end
			cat:AddLine("text", mod.L["AutoSend Rules"], "func", onAutoSendRulesClick)
			cat:AddLine()

			cat:AddLine("text", statusText)
			if (pipeline and pipeline.sending) or (status.currentDest or status.currentItem) then
				local curDest = status.currentDest or ""
				local curItem = status.currentItem or ""
				if curDest ~= "" or curItem ~= "" then
					cat:AddLine("text", fmt("Current: %s %s", curDest, curItem))
				end
			end
			cat:AddLine()

			local lastRun = mod.state.lastSendRun
			if lastRun and lastRun.jobs and lastRun.order then
				local ui = mod.state.sendUI or {}
				local sent, failed, skipped, pending = 0, 0, 0, 0
				for _, id in ipairs(lastRun.order) do
					local j = lastRun.jobs[id]
					if j then
						if j.status == "sent" then
							sent = sent + 1
						elseif j.status == "failed" then
							failed = failed + 1
						elseif j.status == "skipped" then
							skipped = skipped + 1
						else
							pending = pending + 1
						end
					end
				end

				local summary =
					fmt("Last run: sent %d, failed %d, skipped %d, pending %d", sent, failed, skipped, pending)
				local rc = tablet:AddCategory("columns", 1, "text", "Last run", "showWithoutChildren", true)
				rc:AddLine("text", summary)
				if lastRun.stopReason then
					rc:AddLine("text", "Stopped: " .. tostring(lastRun.stopReason))
				end
				rc:AddLine(
					"text",
					ui.showLastRunDetails and "Hide details" or "Show details",
					"func",
					toggleLastRunDetails
				)

				if ui.showLastRunDetails then
					local rcd = tablet:AddCategory("columns", 2, "showWithoutChildren", true, "child_indentation", 5)
					for _, id in ipairs(lastRun.order) do
						local j = lastRun.jobs[id]
						if j then
							local statusLabel = tostring(j.status or "unknown")
							if j.status == "sent" then
								rcd:AddLine(
									"text",
									formatJobText(j),
									"text2",
									statusLabel,
									"text2R",
									0.2,
									"text2G",
									1,
									"text2B",
									0.2
								)
							elseif j.status == "failed" then
								rcd:AddLine(
									"text",
									formatJobText(j),
									"text2",
									statusLabel,
									"text2R",
									1,
									"text2G",
									0.2,
									"text2B",
									0.2,
									"func",
									function()
										mod:Print(
											fmt(
												"Last run: %s -> %s%s",
												formatJobText(j),
												statusLabel,
												j.error and (": " .. tostring(j.error)) or ""
											)
										)
									end
								)
							elseif j.status == "skipped" then
								rcd:AddLine(
									"text",
									formatJobText(j),
									"text2",
									statusLabel,
									"text2R",
									1,
									"text2G",
									0.8,
									"text2B",
									0.2,
									"func",
									function()
										mod:Print(
											fmt(
												"Last run: %s -> %s%s",
												formatJobText(j),
												statusLabel,
												j.error and (": " .. tostring(j.error)) or ""
											)
										)
									end
								)
							else
								rcd:AddLine(
									"text",
									formatJobText(j),
									"text2",
									statusLabel,
									"text2R",
									0.7,
									"text2G",
									0.7,
									"text2B",
									0.7
								)
							end
						end
					end
				end
				cat:AddLine()
			end

			local cat = tablet:AddCategory(
				"columns",
				2,
				"text",
				mod.L["Items to be sent (Alt-Click to add/remove):"],
				"showWithoutChildren",
				true,
				"child_indentation",
				5
			)

			if hasQueue then
				for bag, slots in pairs(sendCache) do
					for slot in pairs(slots) do
						local itemLink = GetContainerItemLink(bag, slot)
						if itemLink then
							local itemId = tonumber(strmatch(itemLink, "item:(%d+)"))
							if itemId then
								mod:ItemCacheRemember(itemId)
							end
							local itemText = GetItemInfo(itemLink) or itemLink
							local texture, qty = GetContainerItemInfo(bag, slot)
							if qty and qty > 1 and type(itemText) == "string" then
								itemText = fmt("%s(%d)", itemText, qty)
							end
							local destText = ""
							if mod.state.sendDest == "" then
								local dest = mod:RulesResolve(itemLink)
								destText = dest or mod.db.char.defaultDestination or ""
							end
							cat:AddLine(
								"text",
								itemText,
								"text2",
								destText,
								"checked",
								true,
								"hasCheck",
								true,
								"checkIcon",
								texture,
								"func",
								onSendQueueItemSelect,
								"arg1",
								bag,
								"arg2",
								slot
							)
						end
					end
				end
			else
				cat:AddLine("text", mod.L["No items selected"])
			end

			cat = tablet:AddCategory("columns", 1)
			cat:AddLine("text", mod.L["Drop items here for Sending"], "justify", "CENTER", "func", onDropClick)

			cat = tablet:AddCategory("columns", 1)
			cat:AddLine()
			cat:AddLine("text", mod.L["Close"], "func", uiClose, "arg1", "TWoWBulkMail_SendQueueTablet")
		end
	)
end

function mod:ShowSendQueueGUI()
	if not tablet:IsRegistered("TWoWBulkMail_SendQueueTablet") then
		self:RegisterSendQueueGUI()
	end
	if self:IsTabletOpen("TWoWBulkMail_SendQueueTablet") then
		return tablet:Refresh("TWoWBulkMail_SendQueueTablet")
	end
	return tablet:Open("TWoWBulkMail_SendQueueTablet")
end

function mod:HideSendQueueGUI()
	return self:SafeTabletClose("TWoWBulkMail_SendQueueTablet")
end

function mod:RefreshSendQueueGUI()
	if not tablet:IsRegistered("TWoWBulkMail_SendQueueTablet") then
		self:RegisterSendQueueGUI()
	end
	tablet:Refresh("TWoWBulkMail_SendQueueTablet")
end
