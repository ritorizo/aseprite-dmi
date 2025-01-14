--- Editor is a class representing a DMI editor.
--- It provides functionality for editing DMI files.
--- @class Editor
--- @field title string The title of the editor.
--- @field canvas_width number The width of the canvas.
--- @field canvas_height number The height of the canvas.
--- @field max_in_a_row number The maximum number of states in a row.
--- @field max_in_a_column number The maximum number of states in a column.
--- @field focused_widget AnyWidget Widget The currently focused widget.
--- @field hovering_widgets AnyWidget[] A table containing all widgets that are currently being hovered by the mouse.
--- @field scroll number The current scroll position.
--- @field mouse Editor.Mouse The current mouse state.
--- @field dmi Dmi The currently opened DMI file.
--- @field open_sprites (StateSprite)[] A table containing all open sprites.
--- @field widgets (AnyWidget)[] A table containing all state widgets.
--- @field context_widget ContextWidget|nil The state that is currently being right clicked
--- @field beforecommand number The event object for the "beforecommand" event.
--- @field aftercommand number The event object for the "aftercommand" event.
--- @field dialog Dialog The dialog object.
--- @field save_path string|nil The path of the file to be saved.
--- @field open_path string|nil The path of the file to be opened.
--- @field image_cache ImageCache The image cache object.
--- @field loading boolean Whether the editor is currently loading a file.
--- @field modified boolean Whether a state has been modified.
--- @field closed boolean Whether the editor has been closed.
Editor = {}
Editor.__index = Editor

--- @class Editor.Mouse
--- @field position Point The current mouse position.
--- @field leftClick boolean Whether the left mouse button is pressed.
--- @field rightClick boolean Whether the right mouse button is pressed.

--- Creates a new instance of the Editor class.
--- @param title string The title of the editor.
--- @param filename? string The path of the file to be processed.
--- @param dmi? Dmi The DMI object to be opened if not passed `filename` or `Editor.open_path` will be used.
--- @return Editor editor  The newly created Editor instance.
function Editor.new(title, filename, dmi)
	local self            = setmetatable({}, Editor)

	self.title            = title
	self.focused_widget   = nil
	self.hovering_widgets = {}
	self.scroll           = 0
	self.mouse            = { position = Point(0, 0), leftClick = false, rightClick = false }
	self.dmi              = nil
	self.open_sprites     = {}
	self.widgets          = {}
	self.context_widget   = nil
	self.save_path        = nil
	self.open_path        = filename or nil

	self.canvas_width     = 185
	self.canvas_height    = 215
	self.max_in_a_row     = 1
	self.max_in_a_column  = 1

	self.loading          = false
	self.modified         = false

	self.image_cache      = ImageCache.new()

	self.beforecommand    = app.events:on("beforecommand", function(ev) self:onbeforecommand(ev) end)

	self.aftercommand     = app.events:on("aftercommand", function(ev) self:onaftercommand(ev) end)

	self:new_dialog(title)

	if filename then
		self.loading = true
		self.dialog:repaint()
		self:show()
		self:open_file(nil)
	elseif dmi then
		self.loading = true
		self.dialog:repaint()
		self:show()
		self:open_file(dmi)
	else
		error("No filename or dmi passed")
	end

	table.insert(open_editors, self)

	return self
end

--- Creates a new dialog for the editor with the specified title.
--- @param title string The title of the dialog.
function Editor:new_dialog(title)
	self.dialog = Dialog {
		title = title,
		onclose = function() self:close(true) end
	}

	self.dialog:canvas {
		width = self.canvas_width,
		height = self.canvas_height,
		onpaint = function(ev) self:onpaint(ev.context) end,
		onmousedown = function(ev) self:onmousedown(ev) end,
		onmouseup = function(ev) self:onmouseup(ev) end,
		onmousemove = function(ev) self:onmousemove(ev) end,
		onwheel = function(ev) self:onwheel(ev) end
	}

	self.dialog:button {
		text = "Save",
		onclick = function() self:save() end
	}
end

--- Displays a warning dialog asking the user to save changes to the sprite before closing.
--- @return 0|1|2 result 0 if the user cancels the operation, 1 if the user saves the file, 2 if the user doesn't save the file.
function Editor:save_warning()
	local result = 0

	local dialog = Dialog {
		title = "Warning",
	}

	dialog:label {
		text = "Save changes to the sprite",
		focus = true
	}

	dialog:newrow()

	dialog:label {
		text = '"' .. file_name(self:path()) .. '" before closing?',
	}

	dialog:canvas { height = 1 }

	dialog:button {
		text = "&Save",
		focus = true,
		onclick = function()
			self:save(function()
				result = 1
				dialog:close()
			end)
		end
	}

	dialog:button {
		text = "Do&n't Save",
		onclick = function()
			result = 2
			dialog:close()
		end
	}

	dialog:button {
		text = "&Cancel",
		onclick = function()
			dialog:close()
		end
	}

	dialog:show()

	return result
end

--- Function to handle the "onclose" event of the Editor class.
--- Cleans up resources and closes sprites when the editor is closed.
--- @param event boolean True if the event is triggered by the user closing the dialog, false otherwise.
--- @param force? boolean True if the editor should be closed without asking the user to save changes, false otherwise.
--- @return boolean closed Whether the editor has been closed.
function Editor:close(event, force)
	if self.closed then
		return true
	end

	if self:is_modified() and not force then
		if event then
			local bounds = self.dialog.bounds
			self:new_dialog(self.title)
			self.dialog:show { wait = false, bounds = bounds }
		end

		for _, state_sprite in ipairs(self.open_sprites) do
			if state_sprite.sprite.isModified then
				if state_sprite:save_warning() == 0 then
					return false
				end
			end
		end

		if self.modified and self:save_warning() == 0 then
			return false
		end
	end

	self.closed = true
	self.dialog:close()

	for i, editor in ipairs(open_editors) do
		if editor == self then
			table.remove(open_editors, i)
			break
		end
	end

	if self.dmi then
		libdmi.remove_dir(self.dmi.temp, false)
	end

	for _, state_sprite in ipairs(self.open_sprites) do
		if state_sprite.sprite then
			state_sprite.sprite:close()
		end
	end

	app.events:off(self.beforecommand)
	app.events:off(self.aftercommand)

	self.mouse = nil
	self.focused_widget = nil
	self.dialog = nil
	self.widgets = nil
	self.dmi = nil
	self.open_sprites = nil
	self.beforecommand = nil
	self.aftercommand = nil

	return true
end

--- Shows the editor dialog.
function Editor:show()
	self.dialog:show { wait = false }
end

--- Opens a DMI file and displays it in the editor.
--- @param dmi? Dmi The DMI object to be opened if not passed `Editor.open_path` will be used.
function Editor:open_file(dmi)
	if self.dmi then
		libdmi.remove_dir(self.dmi.temp, false)
	end

	for _, state_sprite in ipairs(self.open_sprites) do
		state_sprite.sprite:close()
	end

	self.image_cache:clear()

	self.scroll = 0
	self.dmi = nil
	self.widgets = {}
	self.open_sprites = {}
	self.save_path = nil

	self:repaint()

	if not dmi then
		local dmi, error = libdmi.open_file(self.open_path, TEMP_DIR)
		if not error then
			self.dmi = dmi --[[@as Dmi]]
			self.image_cache:load_previews(self.dmi)
		else
			app.alert { title = "Error", text = { "Failed to open the DMI file", error } }
		end

		self.loading = false
		self:repaint_states()
	else
		self.dmi = dmi
		self.loading = false
		self.image_cache:load_previews(self.dmi)
		self:repaint_states()
	end
end

--- Saves the current DMI file.
--- If the DMI file is not set, the function returns without doing anything.
--- Displays a success or failure message using the Aseprite app.alert function.
--- @param on_save? fun() The callback function to be called after the save button is clicked.
--- @param bounds? Rectangle The bounds of the dialog.
function Editor:save(on_save, bounds)
	if not self.dmi then return false end

	local context = nil --[[@type GraphicsContext|nil]]

	local dialog = Dialog {
		title = "Save File",
	}

	dialog:file {
		id = "save_dmi_file",
		save = true,
		filetypes = { "dmi" },
		filename = self:path(),
		onchange = function()
			self.save_path = dialog.data.save_dmi_file

			local bounds = dialog.bounds
			local width = context --[[@as GraphicsContext]]:measureText(self.save_path).width + 20

			dialog:close()
			self:save(on_save, Rectangle(bounds.x + (bounds.width - width) / 2, bounds.y, width, bounds.height))
		end,
	}

	dialog:label {
		focus = true,
		text = dialog.data.save_dmi_file
	}

	dialog:canvas { height = 1, onpaint = function(ev) context = ev.context end }

	dialog:button {
		text = "&Save",
		focus = true,
		onclick = function()
			if on_save then
				on_save()
			end
			dialog:close()
			local _, error = libdmi.save_file(self.dmi, dialog.data.save_dmi_file)
			if not error then
				self.modified = false
			end
		end
	}

	dialog:button {
		text = "&Cancel",
		onclick = function()
			dialog:close()
		end
	}

	if bounds then
		dialog:show { bounds = bounds }
	else
		dialog:show()
	end
end

--- Returns the path of the file to be saved.
--- If `save_path` is set, it returns that path.
--- Otherwise, if `open_path` is set, it returns that path.
--- If neither `save_path` nor `open_path` is set, it returns the path to a default file named "untitled.dmi" in the user's documents folder.
--- @return string path The path of the file to be saved.
function Editor:path()
	return self.save_path or self.open_path or app.fs.joinPath(app.fs.userDocsPath, "untitled.dmi")
end

--- @type string|nil
local save_file_as = nil

--- This function is called before executing a command in the Aseprite editor. It checks the event name and performs specific actions based on the event type.
--- @param ev table The event object containing information about the event.
function Editor:onbeforecommand(ev)
	if ev.name == "SaveFile" then
		for _, state_sprite in ipairs(self.open_sprites) do
			if app.sprite == state_sprite.sprite then
				if not state_sprite:save() then
					ev.stopPropagation()
				end
				break
			end
		end
	elseif ev.name == "SaveFileAs" then
		for _, state_sprite in ipairs(self.open_sprites) do
			if app.sprite == state_sprite.sprite then
				if save_file_as == nil then
					save_file_as = app.sprite.filename
				end
				break
			end
		end
	end
end

--- Callback function called after a Aseprite command is executed.
--- @param ev table The event object containing information about the command.
function Editor:onaftercommand(ev)
	if ev.name == "SaveFileAs" then
		for i, state_sprite in ipairs(self.open_sprites) do
			if app.sprite == state_sprite.sprite then
				if save_file_as ~= nil and save_file_as ~= app.sprite.filename then
					table.remove(self.open_sprites, i)
				end
				save_file_as = nil
				break
			end
		end
	end
end

--- Removes unused statesprites from the open_sprites.
function Editor:gc_open_sprites()
	local open_sprites = {} --[[@type StateSprite[] ]]
	for _, state_sprite in ipairs(self.open_sprites) do
		if Editor.is_sprite_open(state_sprite.sprite) then
			table.insert(open_sprites, state_sprite)
		end
	end
	self.open_sprites = open_sprites
end

--- Switches the tab to the sprite containing the state.
--- @param sprite Sprite The sprite to be opened.
function Editor.switch_tab(sprite)
	local tries = 0
	local max_tries = #app.sprites + 1
	while app.sprite ~= sprite and tries <= max_tries do
		tries = tries + 1
		app.command.GotoNextTab()
	end
end

--- Checks if the DMI file has been modified.
--- @return boolean modified Whether the DMI file has been modified.
function Editor:is_modified()
	for _, state_sprite in ipairs(self.open_sprites) do
		if state_sprite.sprite.isModified then
			return true
		end
	end
	return self.modified
end

--- Checks if the sprite is open in the Aseprite editor.
--- @param sprite Sprite The sprite to be checked.
function Editor.is_sprite_open(sprite)
	for _, sprite_ in ipairs(app.sprites) do
		if sprite == sprite_ then
			return true
		end
	end
	return false
end
