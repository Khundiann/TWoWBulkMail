local mod = TWoWBulkMail

local pt = mod.libs.pt

local function iterKeys(t, k)
	local nk = next(t, k)
	return nk
end

function mod:PtHasSet(setName)
	return setName and pt:GetSet(setName) ~= nil
end

function mod:PtItemInSet(item, setName)
	return pt:ItemInSet(item, setName) ~= nil
end

function mod:PtSetToItemIds(setName, out)
	local rset = pt:GetSet(setName)
	if type(rset) == "string" then
		local t = pt:GetSetTable(setName)
		if not t then
			return
		end
		for itemId in pairs(t) do
			out[itemId] = true
		end
	elseif type(rset) == "table" then
		for _, subset in pairs(rset) do
			self:PtSetToItemIds(subset, out)
		end
	end
end

function mod:PtIterateSet(setName)
	local tmp = {}
	self:PtSetToItemIds(setName, tmp)
	return iterKeys, tmp, nil
end

function mod:GetSendMailItem()
	if not GetSendMailItem then
		return nil
	end
	return GetSendMailItem(1) or GetSendMailItem()
end

function mod:GetSendMailItemLink()
	if not GetSendMailItemLink then
		return nil
	end
	return GetSendMailItemLink(1) or GetSendMailItemLink()
end
