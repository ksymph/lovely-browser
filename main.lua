local https = require "https"

local lovely = {} -- callbacks
local gui = {} -- browser gui (quick & dirty)
local cache = {} -- currently loaded games

gui.navbar = {
	w = 4,
	h = 32,
	is_expanded = false,
	text = ""
}

local function collision_point(x1,y1,w,h, x2,y2)
	return x2 >= x1 and x2 <= x1 + w and y2 >= y1 and y2 <= y1 + h
end

local function fetch_app(url)
	local _, contents = https.request(url)
	local filename = url:gsub(".*/", "")
	love.filesystem.write(filename, contents)
	return filename
end

local function load_app(path)
	local app = {
		path = path,
		slug = path:match("([^.]+)"),
		title = path:match("([^.]+)"), -- fallback to .love filename, but this'll get overwritten later if a title is later provided by the app itself
		env = {},
		callbacks = {},
		loaded_modules = {
			-- love builtins
			socket = require "socket",
			https = require "https",
			ffi = require "ffi"
		},
		is_active = true
	}

	setmetatable(app.env, {__index = _G}) -- give access to real globals, hmm
	app.env._G = app.env -- new global assignments routed to env

	app.env.print = function(...)
		print(app.slug .. " says:", ...)
	end

	app.env.require = function(module_name)
		if app.loaded_modules[module_name] then
			return app.loaded_modules[module_name]
		end

		local module_path = module_name:gsub("%.", "/") .. ".lua"
		local module = love.filesystem.load(module_path)

		setfenv(module, app.env)

		app.loaded_modules[module_name] = module() or true

		return app.loaded_modules[module_name]
	end

	app.env.love = setmetatable({}, {
		__index = function(t, k)
			if k == "filesystem" then
				return setmetatable({}, {
					__index = function(t2, k2)
						return love.filesystem[k2]
						-- todo: custom filesystem functions that keeps everything in app subdirectory inside lovely

					end
				})
			end
			return love[k]
		end,
		__newindex = function(t, k, v)
			-- keep love. callback assignments inside app.callbacks
			app.callbacks[k] = v
		end
	})

	-- yes, these mounting shenanigans are necessary
	-- apparently even if there's no conf.lua in the lovely directory or a mounted directory...
	-- love loads the default conf.lua into memory
	-- and mounting an archive with a conf.lua of its own overwrites the default love.conf
	-- and even when you unmount the archive, the overwritten conf.lua sticks around
	-- or something like that
	-- there go three hours of my sanity
	-- (and for the record mounting at root is necessary for running conf and main)
	love.filesystem.mount(app.path, app.slug)
	local main = love.filesystem.load(app.slug .. "/main.lua")
	local conf = love.filesystem.load(app.slug .. "/conf.lua")
	love.filesystem.unmount(app.path)
	love.filesystem.mount(app.path, "")


	local conf_table = {
		window = {},
		audio = {},
		modules = {}
	}
	if conf then
		setfenv(conf, app.env)
		-- run the conf.lua
		conf()
		-- conf.lua works by defining love.conf, so make sure to run that too
		if app.callbacks.conf then
			app.callbacks.conf(conf_table)
		end
	end
	-- todo: fully reset
	love.window.setMode(conf_table.window.width or 800, conf_table.window.height or 600)

	setfenv(main, app.env)
	main()
	if app.callbacks.load then
		app.callbacks.load()
	end
	love.filesystem.unmount(app.path)
	table.insert(cache, app)
end

function lovely.update(dt)
	local mouse_x, mouse_y = love.mouse.getPosition()
	if gui.navbar.is_expanded then
		if mouse_y > gui.navbar.h then
			gui.navbar.is_expanded = false
		end
		if love.mouse.isDown(1) then
			if collision_point(8, 0, 48, gui.navbar.h, mouse_x, mouse_y) then
				-- home

			elseif collision_point(48, 0, 48, gui.navbar.h, mouse_x, mouse_y) then
				-- paste
				gui.navbar.text = love.system.getClipboardText()
			elseif collision_point(86, 0, 48, gui.navbar.h, mouse_x, mouse_y) then
				-- clear
				gui.navbar.text = ""
			end
		end
	else
		if mouse_x < gui.navbar.w and mouse_y < gui.navbar.h then
			gui.navbar.is_expanded = true
		else
			gui.navbar.is_expanded = false
		end
	end
end

function lovely.draw()
	-- works for isolating lovely drawing, but doesn't fully encapsulate app graphical state
	-- won't work with multiple tabs or whatever
	-- todo: think of a nice way to cache app graphics state
	love.graphics.push("all")
	love.graphics.reset()
	if gui.navbar.is_expanded then
		-- background
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), gui.navbar.h)
		-- address bar
		love.graphics.setColor(0.85, 0.85, 0.85, 1)
		love.graphics.rectangle("fill", 128,3, love.graphics.getWidth()-142,gui.navbar.h-6)
		-- buttons
		love.graphics.setColor(0, 0, 0)
		love.graphics.print(gui.navbar.text, 132, 6)
		love.graphics.print("home", 12, 6)
		love.graphics.print("paste", 52, 6)
		love.graphics.print("clear", 90, 6)
	else
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.rectangle("fill", 0, 0, gui.navbar.w, gui.navbar.h)
	end
	love.graphics.pop()
end

function lovely.keypressed(key)
	if gui.navbar.is_expanded then
		if key == "return" then
			local app_path
			if gui.navbar.text:sub(1, 6) == "local:" then
				app_path = gui.navbar.text:sub(7)
			else
				app_path = fetch_app(gui.navbar.text)
			end
			cache = {}
			load_app(app_path)
		elseif key == "backspace" then
			gui.navbar.text = gui.navbar.text:sub(1, -2)
		else
			gui.navbar.text = gui.navbar.text .. key
		end
	end
end

local love_callbacks = {
	"audiodisconnected",
	"directorydropped",
	"displayrotated",
	"draw",
	"dropbegan",
	"dropcompleted",
	"dropmoved",
	"errhand",
	"errorhandler",
	"filedropped",
	"focus",
	"gamepadaxis",
	"gamepadpressed",
	"gamepadreleased",
	"joystickadded",
	"joystickaxis",
	"joystickhat",
	"joystickpressed",
	"joystickreleased",
	"joystickremoved",
	"joysticksensorupdated",
	"keypressed",
	"keyreleased",
	--"load",
	"localechanged",
	"lowmemory",
	"mousefocus",
	"mousemoved",
	"mousepressed",
	"mousereleased",
	"occluded",
	"quit",
	"resize",
	--"run",
	"sensorupdated",
	"textedited",
	"textinput",
	"threaderror",
	"touchmoved",
	"touchpressed",
	"touchreleased",
	"update",
	"visible",
	"wheelmoved"
}

for _,callback in ipairs(love_callbacks) do
	love[callback] = function(...)
		for _,app in ipairs(cache) do
			if app.is_active and app.callbacks[callback] then
				local should_run = not gui.navbar.is_expanded or callback == "draw"

				if should_run then
					love.filesystem.mount(app.path, "")

					-- Use a protected call to ensure unmount happens even if the app errors.
					local success = pcall(app.callbacks[callback], ...)
					love.filesystem.unmount(app.path)
				end
			end
		end
		if lovely[callback] then
			lovely[callback](...)
		end
	end
end
