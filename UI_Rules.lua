local mod = TWoWBulkMail

local tablet = mod.libs.tablet
local dewdrop = mod.libs.dewdrop

local fmt = string.format

local function splitDotPath(path)
	local parts = {}
	if not path then
		return parts
	end
	for cat in string.gfind(path, "([^%.]+)") do
		table.insert(parts, cat)
	end
	return parts
end

local function tabletClose(tabletID)
	mod:SafeTabletClose(tabletID)
end

local function uiClose(tabletID)
	mod:ScheduleEvent(tabletClose, 0, tabletID)
end

local shown = {}
local curRuleSet
local curDDMode = "rules"
local curOptDest
local parseCopper

local itemInputDDTable, itemTypesDDTable, ptSetsDDTable, bagItemsDDTable

local function addRule(ruletype, value)
	curRuleSet[ruletype] = curRuleSet[ruletype] or {}

	local removed
	for i, v in ipairs(curRuleSet[ruletype]) do
		if v == value then
			table.remove(curRuleSet[ruletype], i)
			removed = true
			break
		end
	end

	if not removed then
		table.insert(curRuleSet[ruletype], value)
	end

	tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
	mod:RulesMarkAltered()
end

local function createItemInputDDTable(force)
	if force then
		itemInputDDTable = nil
	end
	if itemInputDDTable then
		return
	end

	itemInputDDTable = {
		text = mod.L["Item ID"],
		hasArrow = true,
		hasEditBox = true,
		tooltipTitle = mod.L["ItemID(s)"],
		tooltipText = mod.L["Usage: <itemID> [itemID2, ...]"],
		editBoxFunc = function(text)
			if type(text) ~= "string" then
				return
			end
			for num in string.gfind(text, "(%d+)") do
				addRule("items", tonumber(num))
				mod:ItemCacheRemember(num)
			end
		end,
	}
end

local function createBlizzardCategoryDDTable(force)
	if force then
		itemTypesDDTable = nil
	end
	if itemTypesDDTable then
		return
	end

	itemTypesDDTable = { text = mod.L["Item Type"], hasArrow = true, subMenu = {} }
	for itype, subtypes in pairs(mod.state.auctionItemClasses or {}) do
		itemTypesDDTable.subMenu[itype] = {
			text = itype,
			hasArrow = table.getn(subtypes) > 0,
			func = addRule,
			arg1 = "itemTypes",
			arg2 = { type = itype, subtype = table.getn(subtypes) == 0 and itype or nil },
		}

		if table.getn(subtypes) > 0 then
			local supertype = itemTypesDDTable.subMenu[itype]
			supertype.subMenu = {}
			for _, isubtype in ipairs(subtypes) do
				supertype.subMenu[isubtype] = {
					text = isubtype,
					func = addRule,
					arg1 = "itemTypes",
					arg2 = { type = itype, subtype = isubtype },
				}
			end
		end
	end
end

local function buildPT2SetNames()
	local names = {}
	local pt = mod.libs.pt
	if not pt.k then
		return names
	end

	for _, moduleData in pairs(pt.k) do
		if type(moduleData) == "table" then
			for setName in pairs(moduleData) do
				names[setName] = true
			end
		end
	end

	return names
end

local function createPT2SetsDDTable(force)
	if force then
		ptSetsDDTable = nil
	end
	if ptSetsDDTable then
		return
	end

	ptSetsDDTable = { text = mod.L["Periodic Table Set"], hasArrow = true, subMenu = {} }

	local setNames = buildPT2SetNames()
	for setName in pairs(setNames) do
		local group, rest = string.match(setName, "^(.-)%s%-%s(.+)$")
		local pathtable = {}
		if group and rest then
			table.insert(pathtable, group)
			for part in string.gfind(rest, "([^%.]+)") do
				table.insert(pathtable, part)
			end
		else
			pathtable = splitDotPath(setName)
		end

		local curmenu = ptSetsDDTable.subMenu
		local pathSoFar = ""
		for i, cat in ipairs(pathtable) do
			if pathSoFar == "" then
				pathSoFar = cat
			else
				pathSoFar = pathSoFar .. "." .. cat
			end

			if not curmenu[cat] then
				curmenu[cat] = {
					text = cat,
					hasArrow = true,
					subMenu = {},
					__ptPath = pathSoFar,
				}
			end

			if i == table.getn(pathtable) then
				curmenu[cat].__ptSetName = setName
			end

			curmenu = curmenu[cat].subMenu
		end
	end
end

local dupeCheck = {}
local function updateDynamicARDTables()
	bagItemsDDTable = {
		text = mod.L["Items from Bags"],
		hasArrow = true,
		subMenu = {},
		tooltipTitle = mod.L["Bag Items"],
		tooltipText = mod.L["Mailable items in your bags."],
	}

	for k in pairs(dupeCheck) do
		dupeCheck[k] = nil
	end

	for bag, slot, item in mod:BagIter() do
		local itemId = tonumber(string.match(item or "", "item:(%d+)"))
		if itemId and not dupeCheck[itemId] then
			dupeCheck[itemId] = true
			mod.libs.gratuity:SetBagItem(bag, slot)
			if
				not mod.libs.gratuity:MultiFind(
					2,
					4,
					nil,
					true,
					ITEM_SOULBOUND,
					ITEM_BIND_QUEST,
					ITEM_CONJURED,
					ITEM_BIND_ON_PICKUP
				) or mod.libs.gratuity:Find(ITEM_BIND_ON_EQUIP, 2, 4, nil, true, true)
			then
				table.insert(bagItemsDDTable.subMenu, {
					text = select(2, GetItemInfo(itemId)),
					checked = true,
					checkIcon = select(10, GetItemInfo(itemId)),
					func = addRule,
					arg1 = "items",
					arg2 = itemId,
				})
			end
		end
	end
end

function mod:RegisterAddRuleDewdrop()
	if not mod.state.addRuleAnchor then
		mod.state.addRuleAnchor = CreateFrame("Frame", "TWoWBulkMailAddRuleAnchor", UIParent)
		mod.state.addRuleAnchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		mod.state.addRuleAnchor:SetWidth(1)
		mod.state.addRuleAnchor:SetHeight(1)
		mod.state.addRuleAnchor:SetAlpha(0)
		mod.state.addRuleAnchor:Show()
	end

	dewdrop:Register(mod.state.addRuleAnchor, "children", function(level, value)
		if curDDMode == "options" then
			local dest = curOptDest
			local opt = dest and mod:GetDestinationOptions(dest) or nil
			if not opt then
				dewdrop:AddLine("text", "No destination selected.", "isTitle", true)
				return
			end

			if level == 1 then
				dewdrop:AddLine("text", fmt("Options: %s", tostring(dest)), "isTitle", true)
				dewdrop:AddLine()

				dewdrop:AddLine("text", "Send as", "isTitle", true)
				dewdrop:AddLine("text", "Normal", "hasCheck", true, "checked", opt.sendAs ~= "cod", "func", function()
					opt.sendAs = "normal"
					opt.codAmount = 0
					mod:RulesMarkAltered()
					tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
				end)
				dewdrop:AddLine("text", "COD", "hasCheck", true, "checked", opt.sendAs == "cod", "func", function()
					opt.sendAs = "cod"
					if not opt.codAmount or opt.codAmount <= 0 then
						opt.codAmount = 1
					end
					opt.moneyMode = "none"
					opt.moneyAmount = 0
					mod:RulesMarkAltered()
					tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
				end)
				if opt.sendAs == "cod" then
					dewdrop:AddLine(
						"text",
						fmt(
							"COD amount: %s",
							mod.libs.abacus and mod.libs.abacus:FormatMoneyFull(opt.codAmount or 0, nil, nil)
								or tostring(opt.codAmount or 0)
						),
						"hasArrow",
						true,
						"hasEditBox",
						true,
						"editBoxFunc",
						function(text)
							local copper = parseCopper(text)
							if not copper or copper <= 0 then
								mod:Print("Invalid COD amount.")
								return
							end
							opt.codAmount = copper
							mod:RulesMarkAltered()
							tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
						end
					)
				end

				dewdrop:AddLine()
				dewdrop:AddLine("text", "Attach money", "isTitle", true)
				dewdrop:AddLine(
					"text",
					"None",
					"hasCheck",
					true,
					"checked",
					opt.moneyMode ~= "amount",
					"func",
					function()
						opt.moneyMode = "none"
						opt.moneyAmount = 0
						mod:RulesMarkAltered()
						tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
					end
				)
				dewdrop:AddLine(
					"text",
					"Fixed amount",
					"hasCheck",
					true,
					"checked",
					opt.moneyMode == "amount",
					"func",
					function()
						opt.moneyMode = "amount"
						if not opt.moneyAmount or opt.moneyAmount <= 0 then
							opt.moneyAmount = 1
						end
						opt.sendAs = "normal"
						opt.codAmount = 0
						mod:RulesMarkAltered()
						tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
					end
				)
				if opt.moneyMode == "amount" then
					dewdrop:AddLine(
						"text",
						fmt(
							"Money amount: %s",
							mod.libs.abacus and mod.libs.abacus:FormatMoneyFull(opt.moneyAmount or 0, nil, nil)
								or tostring(opt.moneyAmount or 0)
						),
						"hasArrow",
						true,
						"hasEditBox",
						true,
						"editBoxFunc",
						function(text)
							local copper = parseCopper(text)
							if not copper or copper <= 0 then
								mod:Print("Invalid money amount.")
								return
							end
							opt.moneyAmount = copper
							mod:RulesMarkAltered()
							tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
						end
					)
				end

				dewdrop:AddLine()
				dewdrop:AddLine(
					"text",
					fmt("Subject: %s", (opt.subject and opt.subject ~= "" and opt.subject) or "<empty>"),
					"hasArrow",
					true,
					"hasEditBox",
					true,
					"editBoxFunc",
					function(text)
						if type(text) ~= "string" then
							return
						end
						opt.subject = string.gsub(text, "^%s*(.-)%s*$", "%1")
						mod:RulesMarkAltered()
						tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
					end
				)
				dewdrop:AddLine(
					"text",
					fmt("Body: %s", (opt.body and opt.body ~= "" and opt.body) or "<empty>"),
					"hasArrow",
					true,
					"hasEditBox",
					true,
					"editBoxFunc",
					function(text)
						if type(text) ~= "string" then
							return
						end
						opt.body = string.gsub(text, "^%s*(.-)%s*$", "%1")
						mod:RulesMarkAltered()
						tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
					end
				)

				dewdrop:AddLine()
				dewdrop:AddLine(
					"text",
					fmt(
						"Max mails per open: %s",
						(opt.maxMailsPerOpen and opt.maxMailsPerOpen > 0) and tostring(opt.maxMailsPerOpen)
							or "Unlimited"
					),
					"hasArrow",
					true,
					"hasEditBox",
					true,
					"editBoxFunc",
					function(text)
						local trimmed = type(text) == "string" and string.gsub(text, "^%s*(.-)%s*$", "%1") or ""
						if trimmed == "" then
							opt.maxMailsPerOpen = 0
							mod:RulesMarkAltered()
							tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
							return
						end

						local n = tonumber(string.match(trimmed, "^(%d+)$"))
						if not n then
							mod:Print("Invalid max mails per open.")
							return
						end
						opt.maxMailsPerOpen = n
						mod:RulesMarkAltered()
						tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
					end
				)

				dewdrop:AddLine()
				dewdrop:AddLine("text", "Close", "func", function()
					dewdrop:Close()
				end)
			end
			return
		end

		if level == 1 then
			dewdrop:AddLine("text", mod.L["Add rule"], "isTitle", true)
			dewdrop:AddLine()

			dewdrop:AddLine(
				"text",
				bagItemsDDTable.text,
				"hasArrow",
				true,
				"value",
				"bags",
				"tooltipTitle",
				bagItemsDDTable.tooltipTitle,
				"tooltipText",
				bagItemsDDTable.tooltipText
			)

			dewdrop:AddLine(
				"text",
				itemInputDDTable.text,
				"hasArrow",
				true,
				"hasEditBox",
				true,
				"editBoxFunc",
				itemInputDDTable.editBoxFunc,
				"tooltipTitle",
				itemInputDDTable.tooltipTitle,
				"tooltipText",
				itemInputDDTable.tooltipText
			)

			dewdrop:AddLine("text", itemTypesDDTable.text, "hasArrow", true, "value", "types")
			dewdrop:AddLine("text", ptSetsDDTable.text, "hasArrow", true, "value", "pt")
			return
		end

		if value == "bags" then
			for _, entry in ipairs(bagItemsDDTable.subMenu or {}) do
				dewdrop:AddLine(
					"text",
					entry.text,
					"hasCheck",
					entry.hasCheck,
					"checked",
					entry.checked,
					"checkIcon",
					entry.checkIcon,
					"func",
					entry.func,
					"arg1",
					entry.arg1,
					"arg2",
					entry.arg2
				)
			end
			return
		end

		if value == "types" then
			for itype, node in pairs(itemTypesDDTable.subMenu or {}) do
				local subtypes = mod.state.auctionItemClasses and mod.state.auctionItemClasses[itype] or {}
				if table.getn(subtypes) > 0 then
					dewdrop:AddLine("text", itype, "hasArrow", true, "value", "types:" .. itype)
				else
					dewdrop:AddLine(
						"text",
						itype,
						"func",
						addRule,
						"arg1",
						"itemTypes",
						"arg2",
						{ type = itype, subtype = nil }
					)
				end
			end
			return
		end

		if type(value) == "string" and string.sub(value, 1, 6) == "types:" then
			local itype = string.sub(value, 7)
			dewdrop:AddLine(
				"text",
				fmt("%s (All)", itype),
				"func",
				addRule,
				"arg1",
				"itemTypes",
				"arg2",
				{ type = itype, subtype = nil }
			)
			dewdrop:AddLine()
			for _, isubtype in ipairs(mod.state.auctionItemClasses and mod.state.auctionItemClasses[itype] or {}) do
				dewdrop:AddLine(
					"text",
					isubtype,
					"func",
					addRule,
					"arg1",
					"itemTypes",
					"arg2",
					{ type = itype, subtype = isubtype }
				)
			end
			return
		end

		local function addPtChildren(subMenu, prefix, node)
			if node and node.__ptSetName then
				dewdrop:AddLine("text", "Add this set", "func", addRule, "arg1", "ptSets", "arg2", node.__ptSetName)
				if subMenu and next(subMenu) then
					dewdrop:AddLine()
				end
			end

			local keys = {}
			for k in pairs(subMenu or {}) do
				table.insert(keys, k)
			end
			table.sort(keys)
			for _, k in ipairs(keys) do
				local child = subMenu[k]
				if child and child.subMenu and next(child.subMenu) then
					dewdrop:AddLine(
						"text",
						k,
						"hasArrow",
						true,
						"value",
						"pt:" .. (child.__ptPath or (prefix ~= "" and (prefix .. "." .. k) or k))
					)
				else
					dewdrop:AddLine(
						"text",
						k,
						"func",
						addRule,
						"arg1",
						"ptSets",
						"arg2",
						child and child.__ptSetName or (prefix ~= "" and (prefix .. "." .. k) or k)
					)
				end
			end
		end

		if value == "pt" then
			addPtChildren(ptSetsDDTable.subMenu, "", nil)
			return
		end

		if type(value) == "string" and string.sub(value, 1, 3) == "pt:" then
			local path = string.sub(value, 4)
			local parts = splitDotPath(path)
			local cur = ptSetsDDTable.subMenu
			local node = nil
			for _, part in ipairs(parts) do
				node = cur and cur[part] or nil
				cur = node and node.subMenu or nil
			end
			addPtChildren(cur, path, node)
			return
		end
	end, "cursorX", true, "cursorY", true, "dontHook", true)
end

local function headerClickFunc(dest)
	if IsAltKeyDown() and dest ~= "globalExclude" then
		mod.state.confirmedDestToRemove = dest
		StaticPopup_Show("TWOWBULKMAIL_REMOVE_DESTINATION")
	else
		shown[dest] = not shown[dest]
	end
	tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
end

local function showRulesetDD(ruleset)
	curDDMode = "rules"
	curRuleSet = ruleset
	updateDynamicARDTables()
	createItemInputDDTable()
	createBlizzardCategoryDDTable()
	createPT2SetsDDTable()
	dewdrop:Open(mod.state.addRuleAnchor)
end

parseCopper = function(text)
	if type(text) ~= "string" then
		return nil
	end

	local trimmed = string.gsub(text, "^%s*(.-)%s*$", "%1")
	if trimmed == "" then
		return nil
	end

	local _, _, g = string.find(trimmed, "(%d+)%s*[gG]")
	local _, _, s = string.find(trimmed, "(%d+)%s*[sS]")
	local _, _, c = string.find(trimmed, "(%d+)%s*[cC]")
	g = g and tonumber(g) or 0
	s = s and tonumber(s) or 0
	c = c and tonumber(c) or 0
	if g > 0 or s > 0 or c > 0 then
		return g * 10000 + s * 100 + c
	end

	local _, _, n = string.find(trimmed, "(%d+)")
	return n and tonumber(n) or nil
end

local function showOptionsDD(dest)
	curDDMode = "options"
	curOptDest = dest
	dewdrop:Open(mod.state.addRuleAnchor)
end

local function newDest()
	StaticPopup_Show("TWOWBULKMAIL_ADD_DESTINATION")
end

local function toggleMatchPolicy()
	if mod.db.char.matchPolicy == "first" then
		mod.db.char.matchPolicy = "last"
	else
		mod.db.char.matchPolicy = "first"
	end
	mod:RulesMarkAltered()
	tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
end

local function moveDestUp(dest)
	mod:MoveDestination(dest, -1)
	tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
end

local function moveDestDown(dest)
	mod:MoveDestination(dest, 1)
	tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
end

local function listRules(category, ruleset)
	if not ruleset or not next(ruleset) then
		category:AddLine("text", mod.L["None"], "indentation", 20, "textR", 1, "textG", 1, "textB", 1)
		return
	end

	for ruletype, rules in pairs(ruleset) do
		for idx, rule in ipairs(rules) do
			local rulesTable = rules
			local ruleIndex = idx
			local args = {
				indentation = 20,
				hasCheck = false,
				checked = false,
				func = function()
					if IsAltKeyDown() then
						table.remove(rulesTable, ruleIndex)
						tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
						mod:RulesMarkAltered()
					end
				end,
			}

			if ruletype == "items" then
				local itemName, icon = mod:ItemCacheGet(rule)
				args.text = itemName or fmt("ItemID: %s", tostring(rule))
				args.hasCheck = true
				args.checked = true
				args.checkIcon = icon
			elseif ruletype == "itemTypes" then
				if rule.subtype and rule.subtype ~= rule.type then
					args.text = fmt("Item Type: %s - %s", rule.type, rule.subtype)
				else
					args.text = fmt("Item Type: %s", rule.type)
				end
				args.textR, args.textG, args.textB = 250 / 255, 223 / 255, 168 / 255
			elseif ruletype == "ptSets" then
				args.text = fmt("PT2 Set: %s", rule)
				args.textR, args.textG, args.textB = 200 / 255, 200 / 255, 255 / 255
			else
				args.text = tostring(rule)
			end

			category:AddLine(
				"text",
				args.text,
				"indentation",
				args.indentation,
				"hasCheck",
				args.hasCheck,
				"checked",
				args.checked,
				"checkIcon",
				args.checkIcon,
				"func",
				args.func,
				"textR",
				args.textR,
				"textG",
				args.textG,
				"textB",
				args.textB
			)
		end
	end
end

local function fillAutoSendEditTablet()
	tablet:SetTitle(mod.L["AutoSend Rules"])

	for _, dest in ipairs(mod.state.reverseDestCache or {}) do
		local rulesets = mod.state.autoSendRules and mod.state.autoSendRules[dest] or nil
		if rulesets and mod.state.destCache[dest] then
			local cat = tablet:AddCategory(
				"id",
				dest,
				"text",
				dest,
				"showWithoutChildren",
				true,
				"hideBlankLine",
				true,
				"checked",
				true,
				"hasCheck",
				true,
				"checkIcon",
				fmt("Interface\\Buttons\\UI-%sButton-Up", shown[dest] and "Minus" or "Plus"),
				"func",
				headerClickFunc,
				"arg1",
				dest
			)

			if shown[dest] then
				cat:AddLine("text", mod.L["Move Up"], "indentation", 10, "func", moveDestUp, "arg1", dest)
				cat:AddLine("text", mod.L["Move Down"], "indentation", 10, "func", moveDestDown, "arg1", dest)
				local optShownKey = "opt:" .. dest
				cat:AddLine(
					"text",
					"Options",
					"indentation",
					10,
					"checked",
					true,
					"hasCheck",
					true,
					"checkIcon",
					fmt("Interface\\Buttons\\UI-%sButton-Up", shown[optShownKey] and "Minus" or "Plus"),
					"func",
					function()
						shown[optShownKey] = not shown[optShownKey]
						tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
					end
				)
				if shown[optShownKey] then
					local opt = mod:GetDestinationOptions(dest)
					local sendAsText = (opt and opt.sendAs == "cod") and "COD" or "Normal"
					local moneyText = (opt and opt.moneyMode == "amount") and "Fixed amount" or "None"
					local codText = opt
							and opt.sendAs == "cod"
							and opt.codAmount
							and opt.codAmount > 0
							and (mod.libs.abacus and mod.libs.abacus:FormatMoneyFull(opt.codAmount, nil, nil) or tostring(
								opt.codAmount
							))
						or nil
					local moneyAmtText = opt
							and opt.moneyMode == "amount"
							and opt.moneyAmount
							and opt.moneyAmount > 0
							and (mod.libs.abacus and mod.libs.abacus:FormatMoneyFull(opt.moneyAmount, nil, nil) or tostring(
								opt.moneyAmount
							))
						or nil
					local maxText = (opt and opt.maxMailsPerOpen and opt.maxMailsPerOpen > 0)
							and tostring(opt.maxMailsPerOpen)
						or "Unlimited"

					cat:AddLine(
						"text",
						fmt("Send as: %s", sendAsText),
						"indentation",
						20,
						"func",
						showOptionsDD,
						"arg1",
						dest
					)
					if codText then
						cat:AddLine(
							"text",
							fmt("COD amount: %s", codText),
							"indentation",
							20,
							"func",
							showOptionsDD,
							"arg1",
							dest
						)
					end
					cat:AddLine(
						"text",
						fmt("Attach money: %s", moneyText),
						"indentation",
						20,
						"func",
						showOptionsDD,
						"arg1",
						dest
					)
					if moneyAmtText then
						cat:AddLine(
							"text",
							fmt("Money amount: %s", moneyAmtText),
							"indentation",
							20,
							"func",
							showOptionsDD,
							"arg1",
							dest
						)
					end
					cat:AddLine(
						"text",
						fmt("Subject: %s", (opt and opt.subject and opt.subject ~= "" and opt.subject) or "<empty>"),
						"indentation",
						20,
						"func",
						showOptionsDD,
						"arg1",
						dest
					)
					cat:AddLine(
						"text",
						fmt("Body: %s", (opt and opt.body and opt.body ~= "" and opt.body) or "<empty>"),
						"indentation",
						20,
						"func",
						showOptionsDD,
						"arg1",
						dest
					)
					cat:AddLine(
						"text",
						fmt("Max mails per open: %s", maxText),
						"indentation",
						20,
						"func",
						showOptionsDD,
						"arg1",
						dest
					)
				end
				cat:AddLine(
					"text",
					mod.L["Include"],
					"indentation",
					10,
					"func",
					showRulesetDD,
					"arg1",
					rulesets.include
				)
				listRules(cat, rulesets.include)
				cat:AddLine(
					"text",
					mod.L["Exclude"],
					"indentation",
					10,
					"func",
					showRulesetDD,
					"arg1",
					rulesets.exclude
				)
				listRules(cat, rulesets.exclude)
				cat:AddLine()
				cat:AddLine()
			end
		end
	end

	local cat = tablet:AddCategory(
		"id",
		"globalExclude",
		"text",
		mod.L["Global Exclude"],
		"showWithoutChildren",
		true,
		"hideBlankLine",
		true,
		"checked",
		true,
		"hasCheck",
		true,
		"checkIcon",
		fmt("Interface\\Buttons\\UI-%sButton-Up", shown.globalExclude and "Minus" or "Plus"),
		"func",
		headerClickFunc,
		"arg1",
		"globalExclude"
	)

	if shown.globalExclude then
		cat:AddLine("text", mod.L["Exclude"], "indentation", 10, "func", showRulesetDD, "arg1", mod.state.globalExclude)
		listRules(cat, mod.state.globalExclude)
	end

	cat = tablet:AddCategory("id", "actions")
	cat:AddLine("text", mod.L["New Destination"], "func", newDest)
	cat:AddLine(
		"text",
		fmt("%s: %s", mod.L["Match Policy"], mod.db and mod.db.char and (mod.db.char.matchPolicy or "last") or "last"),
		"func",
		toggleMatchPolicy
	)
	cat:AddLine("text", mod.L["Close"], "func", uiClose, "arg1", "TWoWBulkMail_AutoSendEditTablet")
	tablet:SetHint(
		mod.L["Click Include/Exclude headers to modify a ruleset. Alt-Click destinations and rules to delete them."]
	)
end

function mod:RegisterAutoSendEditTablet()
	tablet:Register(
		"TWoWBulkMail_AutoSendEditTablet",
		"detachedData",
		self.db.profile.rules_tablet_data,
		"children",
		fillAutoSendEditTablet,
		"cantAttach",
		true,
		"clickable",
		true,
		"showTitleWhenDetached",
		true,
		"showHintWhenDetached",
		true,
		"dontHook",
		true,
		"strata",
		"DIALOG"
	)
end

StaticPopupDialogs["TWOWBULKMAIL_ADD_DESTINATION"] = {
	text = mod.L["TWoW BulkMail - New AutoSend Destination"],
	button1 = mod.L["Accept"],
	button2 = mod.L["Cancel"],
	hasEditBox = 1,
	maxLetters = 20,
	OnAccept = function()
		mod:AddDestination(_G[this:GetParent():GetName() .. "EditBox"]:GetText())
		tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
	end,
	OnShow = function()
		_G[this:GetName() .. "EditBox"]:SetFocus()
	end,
	OnHide = function()
		if ChatFrameEditBox:IsVisible() then
			ChatFrameEditBox:SetFocus()
		end
		_G[this:GetName() .. "EditBox"]:SetText("")
	end,
	EditBoxOnEnterPressed = function()
		mod:AddDestination(_G[this:GetParent():GetName() .. "EditBox"]:GetText())
		tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
		mod:RulesMarkAltered()
		_G.this:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function()
		_G.this:GetParent():Hide()
	end,
	timeout = 0,
	exclusive = 1,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs["TWOWBULKMAIL_REMOVE_DESTINATION"] = {
	text = mod.L["TWoW BulkMail - Confirm removal of destination"],
	button1 = mod.L["Accept"],
	button2 = mod.L["Cancel"],
	OnAccept = function()
		mod:RemoveDestination(mod.state.confirmedDestToRemove)
		tablet:Refresh("TWoWBulkMail_AutoSendEditTablet")
		mod.state.confirmedDestToRemove = nil
		mod:RulesMarkAltered()
	end,
	OnHide = function()
		mod.state.confirmedDestToRemove = nil
	end,
	timeout = 0,
	exclusive = 1,
	hideOnEscape = 1,
}
