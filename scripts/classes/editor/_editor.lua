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
--- @param complete? fun() The callback function to be called when the editor is created.
--- @return Editor editor  The newly created Editor instance.
function Editor.new(title, filename, dmi, complete)
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

	self.dialog           = Dialog {
		title = title,
		onclose = function() self:onclose() end
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

	if filename then
		self.loading = true
		self.dialog:repaint()
		self:show()
		self:open_file(nil, complete)
	elseif dmi then
		self.loading = true
		self.dialog:repaint()
		self:show()
		self:open_file(dmi, complete)
	else
		error("No filename or dmi passed")
	end

	return self
end

--- Function to handle the "onclose" event of the Editor class.
--- Cleans up resources and closes sprites when the editor is closed.
function Editor:onclose()
	if self.modified then
		local result = app.alert {
			title = "Warning",
			text = { 'Saving changes to the sprite', 'Save "' .. file_name(self:path()) .. '" before closing?'},
			buttons = { "&Save", "Do&n't Save", "&Cancel" }
		}

		if result == 1 then
			self:save()
		end
	end

	if self.dmi then
		lib:remove_dir(self.dmi.temp)
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
end

--- Shows the editor dialog.
function Editor:show()
	self.dialog:show { wait = false }
end

--- Opens a DMI file and displays it in the editor.
--- @param dmi? Dmi The DMI object to be opened if not passed `Editor.open_path` will be used.
--- @param complete? fun() The callback function to be called when the file is opened.
function Editor:open_file(dmi, complete)
	if self.dmi then
		lib:remove_dir(self.dmi.temp)
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
		lib:open_file(self.open_path, function(dmi)
			self.dmi = dmi --[[@as Dmi]]
			self.loading = false
			self.image_cache:load_previews(self.dmi)
			self:repaint_states()
			if complete then
				complete()
			end
		end)
	else
		self.dmi = dmi --[[@as Dmi]]
		self.loading = false
		self.image_cache:load_previews(self.dmi)
		self:repaint_states()
		if complete then
			complete()
		end
	end
end

--- Saves the current DMI file.
--- If the DMI file is not set, the function returns without doing anything.
--- Displays a success or failure message using the Aseprite app.alert function.
function Editor:save()
	if not self.dmi then return end

	local save_dialog = Dialog {
		title = "Save File",
		parent = self.dialog
	}

	save_dialog:file {
		id = "save_dmi_file",
		save = true,
		filetypes = { "dmi" },
		filename = self:path(),
		onchange = function()
			self.save_path = save_dialog.data["save_dmi_file"]
			save_dialog:close()
			self:save()
		end,
	}

	save_dialog:label {
		text = save_dialog.data["save_dmi_file"],
	}

	save_dialog:button {
		text = "&Save",
		onclick = function()
			save_dialog:close()
			lib:save_file(self.dmi, save_dialog.data["save_dmi_file"], function(success, error)
				if not success then
					app.alert { title = "Save File", text = { "Failed to save", error } }
				else
					self.modified = false
				end
			end)
		end
	}

	save_dialog:button {
		text = "&Cancel",
		onclick = function()
			save_dialog:close()
		end
	}

	save_dialog:show()
end

--- Returns the path of the file to be saved.
--- If `save_path` is set, it returns that path.
--- Otherwise, if `open_path` is set, it returns that path.
--- If neither `save_path` nor `open_path` is set, it returns the path to a default file named "untitled.dmi" in the user's documents folder.
--- @return string path The path of the file to be saved.
function Editor:path()
	return self.save_path or self.open_path or app.fs.joinPath(app.fs.userDocsPath, "untitled.dmi")
end

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
	elseif ev.name == "SpriteSize" then
		for _, state_sprite in ipairs(self.open_sprites) do
			if app.sprite == state_sprite.sprite then
				ev.stopPropagation()
				app.alert { title = self.title, text = "Changing sprite size is not supported yet" }
				break
			end
		end
	elseif ev.name == "CanvasSize" then
		for _, state_sprite in ipairs(self.open_sprites) do
			if app.sprite == state_sprite.sprite then
				ev.stopPropagation()
				app.alert { title = self.title, text = "Changing canvas size is not supported yet" }
				break
			end
		end
	else
		-- print(json.encode(ev))
	end
end

--- Callback function called after a Aseprite command is executed.
--- @param ev table The event object containing information about the command.
function Editor:onaftercommand(ev)

end

--- Removes unused statesprites from the editor.
function Editor:remove_nil_statesprites()
	for index, state_sprite in ipairs(self.open_sprites) do
		if not state_sprite.sprite or not state_sprite.state then
			table.remove(self.open_sprites, index)
		end
	end
end

--- Switches the tab to the sprite containing the state.
--- @param sprite Sprite The sprite to be opened.
function Editor.switch_tab(sprite)
	local listener = nil
	listener = app.events:on("sitechange", function()
		if app.sprite == sprite then
				app.events:off(listener --[[@as number]])
		else
			app.command.GotoNextTab()
		end
	end)
	app.command.GotoNextTab()
end