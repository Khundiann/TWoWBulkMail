local mod = TWoWBulkMail

local fmt = string.format
local strsub = string.sub

mod.state.sendCache = mod.state.sendCache or {}
mod.state.destSendCache = mod.state.destSendCache or {}
mod.state.numItems = mod.state.numItems or 0
mod.state.cacheLock = false
mod.state.sendDest = ""

local iterbag, iterslot
local function iter()
	if iterslot > GetContainerNumSlots(iterbag) then
		iterbag, iterslot = iterbag + 1, 1
	end
	if iterbag > NUM_BAG_SLOTS then
		return
	end
	for b = iterbag, NUM_BAG_SLOTS do
		for s = iterslot, GetContainerNumSlots(b) do
			iterslot = s + 1
			local link = GetContainerItemLink(b, s)
			if link then
				return b, s, link
			end
		end
		iterbag, iterslot = b + 1, 1
	end
end

function mod:BagIter()
	iterbag, iterslot = 0, 1
	return iter
end

function mod:UpdateSendCost()
	if self.state.sendCache and next(self.state.sendCache) then
		local numMails = self.state.numItems
		if self:GetSendMailItem() then
			numMails = numMails + 1
		end
		return MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice() * numMails)
	end
	return MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice())
end

local function getBagSlotFrame(bag, slot)
	if bag >= 0 and bag < NUM_CONTAINER_FRAMES and slot > 0 and slot <= MAX_CONTAINER_ITEMS then
		local bagslots = GetContainerNumSlots(bag)
		if bagslots > 0 then
			return _G["ContainerFrame" .. (bag + 1) .. "Item" .. (bagslots - slot + 1)]
		end
	end
end

local function shadeBagSlot(bag, slot, shade)
	local frame = getBagSlotFrame(bag, slot)
	if frame then
		SetItemButtonDesaturated(frame, shade)
	end
end

function mod:SendCacheAdd(bag, slot, squelch)
	if type(slot) ~= "number" then
		bag, slot, squelch = bag:GetParent():GetID(), bag:GetID(), slot
	end

	local sendCache = self.state.sendCache
	if GetContainerItemInfo(bag, slot) and not (sendCache[bag] and sendCache[bag][slot]) then
		self.libs.gratuity:SetBagItem(bag, slot)
		if
			not self.libs.gratuity:MultiFind(
				2,
				4,
				nil,
				true,
				ITEM_SOULBOUND,
				ITEM_BIND_QUEST,
				ITEM_CONJURED,
				ITEM_BIND_ON_PICKUP
			) or self.libs.gratuity:Find(ITEM_BIND_ON_EQUIP, 2, 4, nil, true, true)
		then
			sendCache[bag] = sendCache[bag] or {}
			sendCache[bag][slot] = true
			self.state.numItems = self.state.numItems + 1
			shadeBagSlot(bag, slot, true)
			if not squelch then
				self:RefreshSendQueueGUI()
			end
			SendMailFrame_CanSend()
		elseif not squelch then
			self:Print("Item cannot be mailed: %s.", GetContainerItemLink(bag, slot))
		end
	end
	self:UpdateSendCost()
end

function mod:SendCacheRemove(bag, slot)
	bag, slot = (slot and bag or bag:GetParent():GetID()), (slot or bag:GetID())
	local sendCache = self.state.sendCache
	if sendCache and sendCache[bag] then
		if sendCache[bag][slot] then
			sendCache[bag][slot] = nil
			self.state.numItems = self.state.numItems - 1
			shadeBagSlot(bag, slot, false)
		end
		if not next(sendCache[bag]) then
			sendCache[bag] = nil
		end
	end
	self:RefreshSendQueueGUI()
	self:UpdateSendCost()
	SendMailFrame_CanSend()
end

function mod:SendCacheToggle(bag, slot)
	bag, slot = (slot and bag or bag:GetParent():GetID()), (slot or bag:GetID())
	local sendCache = self.state.sendCache
	if sendCache and sendCache[bag] and sendCache[bag][slot] then
		return self:SendCacheRemove(bag, slot)
	end
	return self:SendCacheAdd(bag, slot)
end

function mod:SendCacheCleanup(autoOnly)
	local sendCache = self.state.sendCache
	if sendCache then
		for bag, slots in pairs(sendCache) do
			for slot in pairs(slots) do
				local item = GetContainerItemLink(bag, slot)
				if not autoOnly or self:RulesCacheDest(item) then
					self:SendCacheRemove(bag, slot)
				end
			end
		end
	end
	self.state.cacheLock = false
	self:RefreshSendQueueGUI()
end

function mod:SendCacheBuild(dest)
	if self.state.cacheLock then
		self:RefreshSendQueueGUI()
		return
	end

	self:SendCacheCleanup(true)
	if self.db.char.isSink or (dest ~= "" and not self.state.destCache[dest]) then
		return self:RefreshSendQueueGUI()
	end

	for bag, slot, item in self:BagIter() do
		local target = self:RulesCacheDest(item)
		if target and (dest == "" or dest == target) then
			self:SendCacheAdd(bag, slot, true)
		end
	end

	self:RefreshSendQueueGUI()
end

function mod:OrganizeSendCache()
	local sendCache = self.state.sendCache
	self.state.destSendCache = {}

	for bag, slots in pairs(sendCache) do
		for slot in pairs(slots) do
			local dest = (self.state.sendDest ~= "" and self.state.sendDest)
				or self:RulesCacheDest(GetContainerItemLink(bag, slot))
				or self.db.char.defaultDestination
			if dest then
				self.state.destSendCache[dest] = self.state.destSendCache[dest] or {}
				table.insert(self.state.destSendCache[dest], { bag, slot })
			else
				self:RulesPrintNoDefault()
			end
		end
	end
end

function mod:ShadeContainerFrame(frame)
	local bag = tonumber(strsub(frame:GetName(), 15))
	if bag then
		bag = bag - 1
	else
		return
	end

	local sendCache = self.state.sendCache
	if bag and sendCache and sendCache[bag] then
		for slot, send in pairs(sendCache[bag]) do
			if send then
				shadeBagSlot(bag, slot, true)
			end
		end
	end
end

function mod:PickupContainerItem(bag, slot)
	local hadCursor = CursorHasItem() and true or false
	local texture = GetContainerItemInfo(bag, slot)
	local hadItem = texture and true or false

	local ret = nil
	if self.hooks and self.hooks.PickupContainerItem then
		ret = self.hooks.PickupContainerItem(bag, slot)
	else
		return
	end

	if not hadCursor and hadItem and CursorHasItem() then
		self.state.cursorItem = { bag, slot }
	elseif hadCursor and not CursorHasItem() then
		self.state.cursorItem = nil
	end

	return ret
end

function mod:CURSOR_UPDATE()
	self.state.cursorItem = nil
end

function mod:GetLockedContainerItem()
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			if select(3, GetContainerItemInfo(bag, slot)) then
				return bag, slot
			end
		end
	end
end

function mod:DebugQueueSummary()
	local sendCache = self.state.sendCache
	local count = 0
	for _, slots in pairs(sendCache) do
		for _ in pairs(slots) do
			count = count + 1
		end
	end
	self:Print(fmt("Queue: %d items", count))
end
