local mod = TWoWBulkMail

local L = mod.L

local strmatch = string.match

mod.state.rulesCache = mod.state.rulesCache or {}
mod.state.rulesAltered = true

local function normalizeTypeKey(t)
	if type(t) ~= "string" then
		return nil, nil
	end
	if string.sub(t, -1) == "s" then
		return t, string.sub(t, 1, -2)
	end
	return t, t .. "s"
end

local function iterDestinationsInOrder()
	local list = mod.state.reverseDestCache
	local i = 0
	return function()
		if not list then
			return nil
		end
		while true do
			i = i + 1
			local dest = list[i]
			if not dest then
				return nil
			end
			if dest ~= "*" and mod.state.destCache and mod.state.destCache[dest] then
				return dest
			end
		end
	end
end

function mod:RulesResolve(item)
	if mod.state.rulesAltered then
		self:RulesCacheBuild()
	end

	if not item then
		return nil
	end

	local itemId = type(item) == "number" and item or tonumber(strmatch(item, "item:(%d+)"))
	if not itemId then
		return nil
	end

	local globalExclude = mod.state.globalExclude
	for _, xId in ipairs(globalExclude.items) do
		if itemId == xId then
			return nil
		end
	end
	for _, xset in ipairs(globalExclude.ptSets) do
		if self:PtItemInSet(itemId, xset) then
			return nil
		end
	end

	local function getItemInfoStrings()
		local strings = {}
		local a = { GetItemInfo(itemId) }
		for _, v in ipairs(a) do
			if type(v) == "string" and v ~= "" then
				strings[v] = true
				local v1, v2 = normalizeTypeKey(v)
				if v2 then
					strings[v2] = true
				end
			end
		end
		return strings
	end

	local infoStrings = getItemInfoStrings()
	if type(item) == "string" and mod.libs and mod.libs.gratuity and not next(infoStrings) then
		mod.libs.gratuity:SetHyperlink(item)
		infoStrings = getItemInfoStrings()
	end

	local policy = self.db and self.db.char and self.db.char.matchPolicy or "last"
	local resolvedDest, resolvedWhy

	for dest in iterDestinationsInOrder() do
		if dest ~= UnitName("player") then
			local rules = mod.state.rulesCache[dest]
			local cand
			if rules and rules[itemId] then
				cand = "ItemID"
			elseif rules then
				for s in pairs(infoStrings) do
					if rules[s] == true then
						cand = "ItemType"
						break
					end
					if type(rules[s]) == "table" then
						for sub in pairs(infoStrings) do
							if rules[s][sub] then
								cand = "ItemSubtype"
								break
							end
						end
					end
					if cand then
						break
					end
				end
			end

			if cand then
				local xrules = mod.state.autoSendRules[dest] and mod.state.autoSendRules[dest].exclude
				if xrules then
					for _, xId in ipairs(xrules.items) do
						if itemId == xId then
							cand = nil
							break
						end
					end
					if cand then
						for _, xset in ipairs(xrules.ptSets) do
							if self:PtItemInSet(itemId, xset) then
								cand = nil
								break
							end
						end
					end
				end
			end

			if cand then
				local why
				local include = mod.state.autoSendRules[dest] and mod.state.autoSendRules[dest].include
				if include then
					for _, id in ipairs(include.items) do
						if tonumber(id) == itemId then
							why = string.format("ItemID %d", itemId)
							break
						end
					end
					if not why then
						for _, setName in ipairs(include.ptSets) do
							if self:PtItemInSet(itemId, setName) then
								why = string.format("PT2 %s", setName)
								break
							end
						end
					end
					if not why then
						for _, t in ipairs(include.itemTypes) do
							local t1, t2 = normalizeTypeKey(t.type)
							if (t1 and infoStrings[t1]) or (t2 and infoStrings[t2]) then
								if t.subtype and infoStrings[t.subtype] then
									why = string.format("Type %s / %s", t.type, t.subtype)
								else
									why = string.format("Type %s", t.type)
								end
							end
							if why then
								break
							end
						end
					end
				end

				resolvedDest = dest
				resolvedWhy = why or "Matched rule"
				if policy == "first" then
					break
				end
			end
		end
	end

	return resolvedDest, resolvedWhy
end

function mod:RulesCacheBuild()
	local autoSendRules = mod.state.autoSendRules
	local globalExclude = mod.state.globalExclude
	local auctionItemClasses = mod.state.auctionItemClasses
	local rulesCache = mod.state.rulesCache

	if next(rulesCache) and not mod.state.rulesAltered then
		return
	end

	for k in pairs(rulesCache) do
		rulesCache[k] = nil
	end

	for dest, rules in pairs(autoSendRules) do
		rulesCache[dest] = {}

		for _, itemId in ipairs(rules.include.items) do
			rulesCache[dest][tonumber(itemId)] = true
		end

		for _, setName in ipairs(rules.include.ptSets) do
			for itemId in self:PtIterateSet(setName) do
				rulesCache[dest][tonumber(itemId)] = true
			end
		end

		for _, itemTypeTable in ipairs(rules.include.itemTypes) do
			local itype, isubtype = itemTypeTable.type, itemTypeTable.subtype
			local t1, t2 = normalizeTypeKey(itype)
			if isubtype then
				if t1 then
					rulesCache[dest][t1] = rulesCache[dest][t1] or {}
					rulesCache[dest][t1][isubtype] = true
				end
				if t2 then
					rulesCache[dest][t2] = rulesCache[dest][t2] or {}
					rulesCache[dest][t2][isubtype] = true
				end
			else
				if t1 then
					rulesCache[dest][t1] = true
				end
				if t2 then
					rulesCache[dest][t2] = true
				end
			end
		end

		for _, itemId in ipairs(rules.exclude.items) do
			rulesCache[dest][tonumber(itemId)] = nil
		end
		for _, itemId in ipairs(globalExclude.items) do
			rulesCache[dest][tonumber(itemId)] = nil
		end

		for _, setName in ipairs(rules.exclude.ptSets) do
			for itemId in self:PtIterateSet(setName) do
				rulesCache[dest][itemId] = nil
			end
		end
		for _, setName in ipairs(globalExclude.ptSets) do
			for itemId in self:PtIterateSet(setName) do
				rulesCache[dest][itemId] = nil
			end
		end

		for _, itemTypeTable in ipairs(rules.exclude.itemTypes) do
			local rtype, rsubtype = itemTypeTable.type, itemTypeTable.subtype
			local t1, t2 = normalizeTypeKey(rtype)
			if rsubtype and t1 and type(rulesCache[dest][t1]) == "table" then
				rulesCache[dest][t1][rsubtype] = nil
			elseif t1 then
				rulesCache[dest][t1] = nil
			end
			if rsubtype and t2 and type(rulesCache[dest][t2]) == "table" then
				rulesCache[dest][t2][rsubtype] = nil
			elseif t2 then
				rulesCache[dest][t2] = nil
			end
		end
		for _, itemTypeTable in ipairs(globalExclude.itemTypes) do
			local rtype, rsubtype = itemTypeTable.type, itemTypeTable.subtype
			local t1, t2 = normalizeTypeKey(rtype)
			if rsubtype and t1 and type(rulesCache[dest][t1]) == "table" then
				rulesCache[dest][t1][rsubtype] = nil
			elseif t1 then
				rulesCache[dest][t1] = nil
			end
			if rsubtype and t2 and type(rulesCache[dest][t2]) == "table" then
				rulesCache[dest][t2][rsubtype] = nil
			elseif t2 then
				rulesCache[dest][t2] = nil
			end
		end
	end

	mod.state.rulesAltered = false
end

function mod:RulesCacheDest(item)
	if mod.state.rulesAltered then
		self:RulesCacheBuild()
	end

	if not item then
		return nil
	end

	local itemId = type(item) == "number" and item or tonumber(strmatch(item, "item:(%d+)"))
	if not itemId then
		return nil
	end

	local globalExclude = mod.state.globalExclude
	for _, xId in ipairs(globalExclude.items) do
		if itemId == xId then
			return nil
		end
	end
	for _, xset in ipairs(globalExclude.ptSets) do
		if self:PtItemInSet(itemId, xset) then
			return nil
		end
	end

	local dest = self:RulesResolve(item)
	return dest
end

function mod:RulesMarkAltered()
	mod.state.rulesAltered = true
end

function mod:RulesValidateDefaultDestOrDest(arg1)
	if self.db.char.defaultDestination then
		return true
	end
	if not strmatch(arg1 or "", "^|[cC]") and not self:PtHasSet(arg1) then
		return true
	end
	return false
end

function mod:RulesPrintNoDefault()
	self:Print(L["No default destination set."])
	self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
end
