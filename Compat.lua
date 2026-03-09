if not select then
	function select(index, ...)
		if index == "#" then
			return arg.n
		end

		local position = index
		if position < 0 then
			position = arg.n + position + 1
		end

		if position < 1 or position > arg.n then
			return
		end

		return unpack(arg, position, arg.n)
	end
end

-- WoW 1.12 / Lua 5.0 compatibility: string.match was introduced later.
if not string.match then
	function string.match(text, pattern, init)
		if text == nil or pattern == nil then
			return nil
		end

		local startPos, endPos, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9 = string.find(text, pattern, init)
		if not startPos then
			return nil
		end

		if cap1 ~= nil then
			return cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9
		end

		return string.sub(text, startPos, endPos)
	end
end

if not InCombatLockdown then
	function InCombatLockdown()
		return false
	end
end

if not strtrim then
	function strtrim(text)
		if text == nil then
			return nil
		end

		return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
	end
end

if not string.trim then
	function string:trim()
		return strtrim(self)
	end
end
