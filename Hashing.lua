  local key = "TestKey"

local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' 

local MOD = 2^32
local MODM = MOD-1

local function memoize(f)
	local mt = {}
	local t = setmetatable({}, mt)
	function mt:__index(k)
		local v = f(k)
		t[k] = v
		return v
	end
	return t
end

local function make_bitop_uncached(t, m)
	local function bitop(a, b)
		local res,p = 0,1
		while a ~= 0 and b ~= 0 do
			local am, bm = a % m, b % m
			res = res + t[am][bm] * p
			a = (a - am) / m
			b = (b - bm) / m
			p = p*m
		end
		res = res + (a + b) * p
		return res
	end
	return bitop
end

local function make_bitop(t)
	local op1 = make_bitop_uncached(t,2^1)
	local op2 = memoize(function(a) return memoize(function(b) return op1(a, b) end) end)
	return make_bitop_uncached(op2, 2 ^ (t.n or 1))
end

local bxor1 = make_bitop({[0] = {[0] = 0,[1] = 1}, [1] = {[0] = 1, [1] = 0}, n = 4})

local function bxor(a, b, c, ...)
	local z = nil
	if b then
		a = a % MOD
		b = b % MOD
		z = bxor1(a, b)
		if c then z = bxor(z, c, ...) end
		return z
	elseif a then return a % MOD
	else return 0 end
end

local function band(a, b, c, ...)
	local z
	if b then
		a = a % MOD
		b = b % MOD
		z = ((a + b) - bxor1(a,b)) / 2
		if c then z = bit32_band(z, c, ...) end
		return z
	elseif a then return a % MOD
	else return MODM end
end

local function bnot(x) return (-1 - x) % MOD end

local function rshift1(a, disp)
	if disp < 0 then return lshift(a,-disp) end
	return math.floor(a % 2 ^ 32 / 2 ^ disp)
end

local function rshift(x, disp)
	if disp > 31 or disp < -31 then return 0 end
	return rshift1(x % MOD, disp)
end

local function lshift(a, disp)
	if disp < 0 then return rshift(a,-disp) end 
	return (a * 2 ^ disp) % 2 ^ 32
end

local function rrotate(x, disp)
    x = x % MOD
    disp = disp % 32
    local low = band(x, 2 ^ disp - 1)
    return rshift(x, disp) + lshift(low, 32 - disp)
end

local k = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
	0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
	0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
	0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
	0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
	0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
	0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
	0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
	0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function str2hexa(s)
	return (string.gsub(s, ".", function(c) return string.format("%02x", string.byte(c)) end))
end

local function num2s(l, n)
	local s = ""
	for i = 1, n do
		local rem = l % 256
		s = string.char(rem) .. s
		l = (l - rem) / 256
	end
	return s
end

local function s232num(s, i)
	local n = 0
	for i = i, i + 3 do n = n*256 + string.byte(s, i) end
	return n
end

local function preproc(msg, len)
	local extra = 64 - ((len + 9) % 64)
	len = num2s(8 * len, 8)
	msg = msg .. "\128" .. string.rep("\0", extra) .. len
	assert(#msg % 64 == 0)
	return msg
end

local function initH256(H)
	H[1] = 0x6a09e667
	H[2] = 0xbb67ae85
	H[3] = 0x3c6ef372
	H[4] = 0xa54ff53a
	H[5] = 0x510e527f
	H[6] = 0x9b05688c
	H[7] = 0x1f83d9ab
	H[8] = 0x5be0cd19
	return H
end

local function digestblock(msg, i, H)
	local w = {}
	for j = 1, 16 do w[j] = s232num(msg, i + (j - 1)*4) end
	for j = 17, 64 do
		local v = w[j - 15]
		local s0 = bxor(rrotate(v, 7), rrotate(v, 18), rshift(v, 3))
		v = w[j - 2]
		w[j] = w[j - 16] + s0 + w[j - 7] + bxor(rrotate(v, 17), rrotate(v, 19), rshift(v, 10))
	end

	local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
	for i = 1, 64 do
		local s0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
		local maj = bxor(band(a, b), band(a, c), band(b, c))
		local t2 = s0 + maj
		local s1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
		local ch = bxor (band(e, f), band(bnot(e), g))
		local t1 = h + s1 + ch + k[i] + w[i]
		h, g, f, e, d, c, b, a = g, f, e, d + t1, c, b, a, t1 + t2
	end

	H[1] = band(H[1] + a)
	H[2] = band(H[2] + b)
	H[3] = band(H[3] + c)
	H[4] = band(H[4] + d)
	H[5] = band(H[5] + e)
	H[6] = band(H[6] + f)
	H[7] = band(H[7] + g)
	H[8] = band(H[8] + h)
end

-- Made this global
function sha256(msg)
	msg = preproc(msg, #msg)
	local H = initH256({})
	for i = 1, #msg, 64 do digestblock(msg, i, H) end
	return str2hexa(num2s(H[1], 4) .. num2s(H[2], 4) .. num2s(H[3], 4) .. num2s(H[4], 4) ..
		num2s(H[5], 4) .. num2s(H[6], 4) .. num2s(H[7], 4) .. num2s(H[8], 4))
end


function enc(data)
    return ((data:gsub('.', function(x) 
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

function dec(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
            return string.char(c)
    end))
end



getgenv().user = true
local loader = "LS1JbXBvcnRhbnQKaWYgZ2FtZS5QbGFjZUlkID09IDk0OTgwMDYxNjUgdGhlbgoJbG9jYWwgT3Jpb25MaWIgPSBsb2Fkc3RyaW5nKGdhbWU6SHR0cEdldCgoJ2h0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS9zaGxleHdhcmUvT3Jpb24vbWFpbi9zb3VyY2UnKSkpKCkKbG9jYWwgV2luZG93ID0gT3Jpb25MaWI6TWFrZVdpbmRvdyh7TmFtZSA9ICLwn5KWIERhcmtzZW5zZSB8IFtVUERdIFRhcHBpbmcgU2ltdWxhdG9yISDwn5KWIiwgSGlkZVByZW1pdW0gPSB0cnVlLCBJbnRyb1RleHQgPSAiRGFya3NlbnNlIixTYXZlQ29uZmlnID0gdHJ1ZSwgQ29uZmlnRm9sZGVyID0gIkRhcmtzZW5zZSJ9KQoKLS1WYWx1ZXMKZ2V0Z2VudigpLmF1dG9UYXAgPSB0cnVlIApnZXRnZW52KCkuYXV0b1JlYmlydGggPSB0cnVlIApnZXRnZW52KCkuYXV0b0hhdGNoUmVndWxhciA9IHRydWUgCmdldGdlbnYoKS5hdXRvSGF0Y2hSZWd1bGFyMSA9IHRydWUgCmdldGdlbnYoKS5hdXRvSGF0Y2hSZWd1bGFyMiA9IHRydWUgCmdldGdlbnYoKS5hdXRvSGF0Y2hSZWd1bGFyMyA9IHRydWUgCmdldGdlbnYoKS5hdXRvSGF0Y2hSZWd1bGFyNCA9IHRydWUgCmdldGdlbnYoKS5hdXRvSGF0Y2hSZWd1bGFyNSA9IHRydWUgCmdldGdlbnYoKS5hdXRvSGF0Y2hSZWd1bGFyNiA9IHRydWUgCgoKCgoKCi0tRnVuY3Rpb24gCmZ1bmN0aW9uIGF1dG9UYXAoKQoJd2hpbGUgZ2V0Z2VudigpLmF1dG9UYXAgPT0gdHJ1ZSBkbwoJCWdhbWU6R2V0U2VydmljZSgiUmVwbGljYXRlZFN0b3JhZ2UiKS5FdmVudHMuVGFwOkZpcmVTZXJ2ZXIoIk1haW4iKQoJCXdhaXQoLjAwMDAwMDAwMDAwMDEpCgllbmQKZW5kCgpmdW5jdGlvbiBhdXRvUmViaXJ0aCgpCgl3aGlsZSBnZXRnZW52KCkuYXV0b1JlYmlydGggPT0gdHJ1ZSBkbwoJCWdhbWU6R2V0U2VydmljZSgiUmVwbGljYXRlZFN0b3JhZ2UiKS5FdmVudHMuUmViaXJ0aDpGaXJlU2VydmVyKDEpCgkJd2FpdCguMDAwMDAwMDAwMDAwMSkKCWVuZAplbmQKCmZ1bmN0aW9uIGF1dG9IYXRjaFJlZ3VsYXIoKQoJd2hpbGUgZ2V0Z2VudigpLmF1dG9IYXRjaFJlZ3VsYXIgPT0gdHJ1ZSBkbwoJCWdhbWU6R2V0U2VydmljZSgiUmVwbGljYXRlZFN0b3JhZ2UiKS5FdmVudHMuSGF0Y2hFZ2c6SW52b2tlU2VydmVyKHt9LCJTdGFydGVyIiwxKQoJCXdhaXQoLjAwMDAwMDAwMDAwMDEpCgllbmQKZW5kCgpmdW5jdGlvbiBhdXRvSGF0Y2hSZWd1bGFyMSgpCgl3aGlsZSBnZXRnZW52KCkuYXV0b0hhdGNoUmVndWxhcjEgPT0gdHJ1ZSBkbwoJCWdhbWU6R2V0U2VydmljZSgiUmVwbGljYXRlZFN0b3JhZ2UiKS5FdmVudHMuSGF0Y2hFZ2c6SW52b2tlU2VydmVyKHt9LCJXb29kIEVnZyIsMSkKCQl3YWl0KC4wMDAwMDEpCgllbmQKZW5kCgpmdW5jdGlvbiBhdXRvSGF0Y2hSZWd1bGFyMigpCgl3aGlsZSBnZXRnZW52KCkuYXV0b0hhdGNoUmVndWxhcjIgPT0gdHJ1ZSBkbwogICAgICAgIGdhbWU6R2V0U2VydmljZSgiUmVwbGljYXRlZFN0b3JhZ2UiKS5FdmVudHMuSGF0Y2hFZ2c6SW52b2tlU2VydmVyKHt9LCJKdW5nbGUgRWdnIiwxKQoJCXdhaXQoLjAwMDAxKQoJZW5kCmVuZAoKZnVuY3Rpb24gYXV0b0hhdGNoUmVndWxhcjMoKQoJd2hpbGUgZ2V0Z2VudigpLmF1dG9IYXRjaFJlZ3VsYXIzID09IHRydWUgZG8KCQlnYW1lOkdldFNlcnZpY2UoIlJlcGxpY2F0ZWRTdG9yYWdlIikuRXZlbnRzLkhhdGNoRWdnOkludm9rZVNlcnZlcih7fSwiRm9yZXN0IEVnZyIsMSkKCQl3YWl0KC4wMDAwMSkKCWVuZAplbmQKCmZ1bmN0aW9uIGF1dG9IYXRjaFJlZ3VsYXI0KCkKCXdoaWxlIGdldGdlbnYoKS5hdXRvSGF0Y2hSZWd1bGFyNCA9PSB0cnVlIGRvCiAgICAgICAgZ2FtZTpHZXRTZXJ2aWNlKCJSZXBsaWNhdGVkU3RvcmFnZSIpLkV2ZW50cy5IYXRjaEVnZzpJbnZva2VTZXJ2ZXIoe30sIkJlZSBFZ2ciLDEpIAoJCXdhaXQoLjAwMDAxKQoJZW5kCmVuZAoKZnVuY3Rpb24gYXV0b0hhdGNoUmVndWxhcjUoKQoJd2hpbGUgZ2V0Z2VudigpLmF1dG9IYXRjaFJlZ3VsYXI1ID09IHRydWUgZG8KCQlnYW1lOkdldFNlcnZpY2UoIlJlcGxpY2F0ZWRTdG9yYWdlIikuRXZlbnRzLkhhdGNoRWdnOkludm9rZVNlcnZlcih7fSwiU3dhbXAgRWdnIiwxKQoJCXdhaXQoLjAwMDAxKQoJZW5kCmVuZAoKZnVuY3Rpb24gYXV0b0hhdGNoUmVndWxhcjYoKQoJd2hpbGUgZ2V0Z2VudigpLmF1dG9IYXRjaFJlZ3VsYXI2ID09IHRydWUgZG8KICAgICAgICBnYW1lOkdldFNlcnZpY2UoIlJlcGxpY2F0ZWRTdG9yYWdlIikuRXZlbnRzLkhhdGNoRWdnOkludm9rZVNlcnZlcih7fSwiU25vdyBFZ2ciLDEpCgkJd2FpdCguMDAwMDEpCgllbmQKZW5kCgoKLS1UYWJzCmxvY2FsIEZhcm1UYWIgPSBXaW5kb3c6TWFrZVRhYih7CglOYW1lID0gIkF1dG9GYXJtIiwKCUljb24gPSAicmJ4YXNzZXRpZDovLzQ0ODMzNDU5OTgiLAoJUHJlbWl1bU9ubHkgPSBmYWxzZQp9KQoKbG9jYWwgRWdnVGFiID0gV2luZG93Ok1ha2VUYWIoewoJTmFtZSA9ICJFZ2dzIiwKCUljb24gPSAicmJ4YXNzZXRpZDovLzQ0ODMzNDU5OTgiLAoJUHJlbWl1bU9ubHkgPSBmYWxzZQp9KQoKLS1Ub2dnbGUgCkZhcm1UYWI6QWRkVG9nZ2xlKHsKCU5hbWUgPSAiQXV0byBUYXAiLAoJRGVmYXVsdCA9IGZhbHNlLAoJQ2FsbGJhY2sgPSBmdW5jdGlvbihWYWx1ZSkKCQlnZXRnZW52KCkuYXV0b1RhcCA9IFZhbHVlCgkJYXV0b1RhcCgpCgllbmQKfSkKCkZhcm1UYWI6QWRkVG9nZ2xlKHsKCU5hbWUgPSAiQXV0byBSZWJpcnRoIChidWdneSkiLAoJRGVmYXVsdCA9IGZhbHNlLAoJQ2FsbGJhY2sgPSBmdW5jdGlvbihWYWx1ZSkKCQlnZXRnZW52KCkuYXV0b1JlYmlydGggPSBWYWx1ZQoJCWF1dG9SZWJpcnRoKCkKCWVuZAp9KQoKRWdnVGFiOkFkZFRvZ2dsZSh7CglOYW1lID0gIkF1dG8gSGF0Y2ggUmVndWxhciAoMjAwIGNvaW5zKSIsCglEZWZhdWx0ID0gZmFsc2UsCglDYWxsYmFjayA9IGZ1bmN0aW9uKFZhbHVlKQoJCWdldGdlbnYoKS5hdXRvSGF0Y2hSZWd1bGFyID0gVmFsdWUKCQlhdXRvSGF0Y2hSZWd1bGFyKCkKCWVuZAp9KQoKRWdnVGFiOkFkZFRvZ2dsZSh7CglOYW1lID0gIkF1dG8gSGF0Y2ggV29vZCAoMjUwMCBjb2lucykiLAoJRGVmYXVsdCA9IGZhbHNlLAoJQ2FsbGJhY2sgPSBmdW5jdGlvbihWYWx1ZSkKCQlnZXRnZW52KCkuYXV0b0hhdGNoUmVndWxhcjEgPSBWYWx1ZQoJCWF1dG9IYXRjaFJlZ3VsYXIxKCkKCWVuZAp9KQoKRWdnVGFiOkFkZFRvZ2dsZSh7CglOYW1lID0gIkF1dG8gSGF0Y2ggSnVuZ2xlICgxNTAwMCBjb2lucykiLAoJRGVmYXVsdCA9IGZhbHNlLAoJQ2FsbGJhY2sgPSBmdW5jdGlvbihWYWx1ZSkKCQlnZXRnZW52KCkuYXV0b0hhdGNoUmVndWxhcjIgPSBWYWx1ZQoJCWF1dG9IYXRjaFJlZ3VsYXIyKCkKCWVuZAp9KQoKRWdnVGFiOkFkZFRvZ2dsZSh7CglOYW1lID0gIkF1dG8gSGF0Y2ggRm9ycmVzdCAoMS41IG1pbCBjb2lucykiLAoJRGVmYXVsdCA9IGZhbHNlLAoJQ2FsbGJhY2sgPSBmdW5jdGlvbihWYWx1ZSkKCQlnZXRnZW52KCkuYXV0b0hhdGNoUmVndWxhcjMgPSBWYWx1ZQoJCWF1dG9IYXRjaFJlZ3VsYXIzKCkKCWVuZAp9KQoKRWdnVGFiOkFkZFRvZ2dsZSh7CglOYW1lID0gIkF1dG8gSGF0Y2ggQmVlICg1IG1pbCBjb2lucykiLAoJRGVmYXVsdCA9IGZhbHNlLAoJQ2FsbGJhY2sgPSBmdW5jdGlvbihWYWx1ZSkKCQlnZXRnZW52KCkuYXV0b0hhdGNoUmVndWxhcjQgPSBWYWx1ZQoJCWF1dG9IYXRjaFJlZ3VsYXI0KCkKCWVuZAp9KQoKRWdnVGFiOkFkZFRvZ2dsZSh7CglOYW1lID0gIkF1dG8gSGF0Y2ggU3dhbXAgKDgwIG1pbCBjb2lucykiLAoJRGVmYXVsdCA9IGZhbHNlLAoJQ2FsbGJhY2sgPSBmdW5jdGlvbihWYWx1ZSkKCQlnZXRnZW52KCkuYXV0b0hhdGNoUmVndWxhcjUgPSBWYWx1ZQoJCWF1dG9IYXRjaFJlZ3VsYXI1KCkKCWVuZAp9KQoKRWdnVGFiOkFkZFRvZ2dsZSh7CglOYW1lID0gIkF1dG8gSGF0Y2ggU25vdyAoODAwIG1pbCBjb2lucykiLAoJRGVmYXVsdCA9IGZhbHNlLAoJQ2FsbGJhY2sgPSBmdW5jdGlvbihWYWx1ZSkKCQlnZXRnZW52KCkuYXV0b0hhdGNoUmVndWxhcjYgPSBWYWx1ZQoJCWF1dG9IYXRjaFJlZ3VsYXI2KCkKCWVuZAp9KQoKZW5kCk9yaW9uTGliOkluaXQoKQk="
local correctkey = tostring(game:HttpGet("https://pastebin.com/raw/XQEen0AU"))
if key == nil then
    game.Players.LocalPlayer:Kick("Please input a key")
    return
end

if ekey == dec(correctkey) then
    loadstring((dec(loader)))()
end



