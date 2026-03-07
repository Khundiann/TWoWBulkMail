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
