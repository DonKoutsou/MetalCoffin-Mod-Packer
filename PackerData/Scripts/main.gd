extends Control

class_name Main

@export var mod_Location : ResourcePicker
@export var exec_Path : ResourcePicker
@export var base_Pack : ResourcePicker
@export var unpacked_base : ResourcePicker
@export var mod_export : ResourcePicker

var execPath

static var ignores : Ignores
static var dirs : SaveDirs

#--------------------------------------------------------------
func _ready() -> void:
	execPath = OS.get_executable_path()
	execPath = execPath.replace(execPath.get_file(), "")

	#save ignores in file for user to adjust
	if not FileAccess.file_exists(execPath + "Packer_Ignores.tres"):
		ResourceSaver.save(load("res://PackerData/Resources/Ignores.tres"), execPath + "Packer_Ignores.tres")
	
	if not FileAccess.file_exists(execPath + "SavedDir.tres"):
		ResourceSaver.save(SaveDirs.new(), execPath + "SavedDir.tres")

	print("Ignore table loaded.\nIgnoring :")
	ignores = ResourceLoader.load(execPath + "Packer_Ignores.tres")

	print("Files:")
	for g in ignores.ignored_Files:
		print("    " + g)
	print("Types:")
	for g in ignores.ignored_Types:
		print("    ." + g)
	print("Directories:")
	for g in ignores.ignored_Dirs:
		print("    " + g)
	
	dirs = ResourceLoader.load(execPath + "SavedDir.tres")
	exec_Path.SetFile(dirs.ExecDir)
	mod_Location.SetFile(dirs.ModDir)
	base_Pack.SetFile(dirs.BaseDataDir)
	unpacked_base.SetFile(dirs.UnpackedDataDir)
	mod_export.SetFile(dirs.ModPackDir)

#--------------------------------------------------------------
func GeneratePack() -> void:
	if (dirs.ModDir == ""):
		printerr("Missing Mod Directory")
		return
	if (dirs.UnpackedDataDir == ""):
		printerr("Missing Unpacked Game Data")
		return
	
	if (dirs.ModPackDir.is_empty()):
		printerr("No export directory for mod set")
		return
	
	if (dirs.BaseDataDir == "" or !FileAccess.file_exists(dirs.BaseDataDir)):
		printerr("Wrong Base Pack")
	
	PackerHelper.DeleteDirectoryRecursive(execPath + "Dif") #clean up before starting
	
	ProjectSettings.load_resource_pack(dirs.BaseDataDir)
	
	print("--------- Generating Project Dif ---------")
	PackerHelper._build_diff(dirs.ModDir, dirs.ModDir, dirs.UnpackedDataDir, execPath + "Dif")
	
	#return
	if (!DirAccess.dir_exists_absolute(execPath + "Dif")):
		printerr("No differances found in files, opearation Canceled")
		return
	
	print("--------- Project Dif Created ---------")
	
	ensure_project_godot_exists(execPath + "Dif")
	
	generate_Import_Files(execPath + "Dif")


	#var modFileName = "/{0}.pck".format([dirs.ModDir.get_file()])
	var output = []

	var pack_args = [
		"--headless", 
		"--path", execPath + "Dif",
		"--patches", dirs.BaseDataDir,
		"--export-pack", "Windows", dirs.ModPackDir
	]
	
	print("Packing into PCK...")
	var exit_code = OS.execute(dirs.ExecDir, pack_args, output, true)

	print("--------- Cleaning Up Dif ---------")
	PackerHelper.DeleteDirectoryRecursive(execPath + "Dif")
	
	if exit_code == 0:
		print("Mod pack successfully created at: " + dirs.ModPackDir)
	else:
		print("Packing failed. Error logs: " + str(output))

#--------------------------------------------------------------
##Launch godot on the background to import all the resources and generate the import files
func generate_Import_Files(dir : String):
	#check for godot exec
	if not FileAccess.file_exists(dirs.ExecDir):
		print("Godot Editor binary missing from tool directory!")
		return
	#if (dirs.ModDir == ""):
		#print("Missing Mod Directory")
		#return
	#arguments for executing godot
	#1 headless and editor to open editor hidden
	var import_args = [ "--headless",  "--editor","--path", dir, "--quit"]
	
	print("Importing assets...")
	
	#create a basic project file for godot to use
	ensure_project_godot_exists(dir)
	
	#import assets to generate import files
	var output = []
	
	var exit_code = OS.execute(dirs.ExecDir, import_args, output, true)
	
	if exit_code != 0:
		push_error("Failed to import mod assets. Error logs: " + str(output))
		return
	else:
		print("Import Files Generated")

#--------------------------------------------------------------
func unpack_pck_to_disk() -> void:
	var output_dir = dirs.BaseDataDir.replace(dirs.BaseDataDir.get_file(), "") + "Unpacked"
	unpacked_base.SetFile(output_dir)
	_on_unpacked_base_changed(output_dir)
	
	PackerHelper.DeleteDirectoryRecursive(output_dir)
	# 1. Mount the external PCK file into Godot's virtual filesystem
	var success = ProjectSettings.load_resource_pack(dirs.BaseDataDir)
	if not success:
		print("Failed to load or mount the PCK file.")
		return
	
	print("PCK successfully mounted. Starting recursive extraction...")

	# 2. Start the recursive extraction process from the root virtual directory
	_extract_directory_recursive("res://", output_dir)
	
	PackerHelper.reconstruct_all_uid_files(output_dir)

	print("Extraction complete!")

#--------------------------------------------------------------
# This internal helper function calls itself whenever it finds a subdirectory
func _extract_directory_recursive(virtual_dir_path: String, local_dir_path: String) -> void:
	# Ensure the local directory exists on the physical hard drive
	var da = DirAccess.open("user://") # fallback baseline pointer
	if not da.dir_exists(local_dir_path):
		var make_dir_err = da.make_dir_recursive(local_dir_path)
		if make_dir_err != OK:
			print("Failed to create local directory: ", local_dir_path)
			return

	# Open the virtual folder inside the mounted PCK
	var res_dir = DirAccess.open(virtual_dir_path)
	if not res_dir:
		print("Could not open virtual directory: ", virtual_dir_path)
		return
		
	res_dir.list_dir_begin()
	var item_name = res_dir.get_next()
	
	while item_name != "":
		# Ignore navigation links
		if item_name == "." or item_name == "..":
			item_name = res_dir.get_next()
			continue
			
		var next_virtual_path = virtual_dir_path.path_join(item_name)
		var next_local_path = local_dir_path.path_join(item_name)
		
		if res_dir.current_is_dir():
			if (ignores.CheckDir(next_virtual_path.replace("res://", ""))):
				# 3. IF IT'S A DIRECTORY: Recursively enter it
				_extract_directory_recursive(next_virtual_path, next_local_path)
		else:
			if (ignores.CheckFile(next_virtual_path.get_file())):
				
				# 4. IF IT'S A FILE: Read from virtual memory and write to disk
				var file_read = FileAccess.open(next_virtual_path, FileAccess.READ)
				if file_read:
					var file_data = file_read.get_buffer(file_read.get_length())
					file_read.close()
					
					var file_write = FileAccess.open(next_local_path, FileAccess.WRITE)
					if file_write:
						file_write.store_buffer(file_data)
						file_write.close()
						print("Extracted file: ", next_virtual_path)
						
						if next_virtual_path.ends_with(".import"):
							HandleImportFile(next_virtual_path, next_local_path)
						if next_virtual_path.ends_with(".remap"):
							HandleRemapFile(next_virtual_path, next_local_path)
						if (next_local_path.ends_with(".gdc")):
							PackerHelper.run_opengds_decompiler(next_local_path)
					else:
						print("Error writing physical file: ", next_local_path)
				else:
					print("Error reading virtual file: ", next_virtual_path)
				
		item_name = res_dir.get_next()
		
	res_dir.list_dir_end()

#--------------------------------------------------------------
func HandleImportFile(path : String, localPath : String) -> void:
	var targetPath = PackerHelper.get_target_path_from_import(path)

	var tex = load(targetPath) as Texture2D
	var saveLoc = localPath.get_basename()
	if tex:

		var format = tex.get_format()
		
		if (format >= Image.Format.FORMAT_MAX):
			DirAccess.remove_absolute(localPath)
			printerr("Failed to restor original texture ", saveLoc)
			printerr("Failed format = ", format)
			return
			
		var img : Image = tex.get_image()
		if (img == null or img.is_empty() or format >= Image.Format.FORMAT_MAX):
			DirAccess.remove_absolute(localPath)
			printerr("Failed to restor original texture ", saveLoc)
			printerr("Failed format = ", format)
		else:
			img.save_png(saveLoc) # Saves as a perfectly clean .png file
			print("Restored original texture: | Format {0}".format([format]), saveLoc)
	else:
		DirAccess.remove_absolute(localPath)
		printerr("Failed to restor original texture ", saveLoc)
		
#--------------------------------------------------------------
func HandleRemapFile(path : String, localPath : String) -> void:
	#get the path the remap points to
	var targetPath = PackerHelper.get_target_path_from_remap(path)
	
	#remove the .remap
	var saveLoc = localPath.get_basename()
	
	if (saveLoc.ends_with(".gdc") or saveLoc.ends_with(".gd")):
		DirAccess.remove_absolute(localPath)
		return
		
	if (saveLoc.ends_with(".tscn") or saveLoc.ends_with(".scn")):
		return
		
	#load resource and save it
	var resource = load(targetPath)
	ResourceSaver.save(resource, saveLoc)
	print("Generated Resoure {0} from {1}".format([targetPath.get_file(), path.get_file()]))
	DirAccess.remove_absolute(localPath)

#--------------------------------------------------------------
func ensure_project_godot_exists(mod_path: String):
	# 1. Ensure project.godot exists
	var config_file_path = mod_path.path_join("project.godot")
	if not FileAccess.file_exists(config_file_path):
		var file = FileAccess.open(config_file_path, FileAccess.WRITE)
		file.store_string("[config_version=5]\n\n[application]\nconfig/name=\"ModTemplate\"")
		file.close()

	# 2. Ensure export_presets.cfg exists with a default layout
	var preset_file_path = mod_path.path_join("export_presets.cfg")
	if not FileAccess.file_exists(preset_file_path):
		var file = FileAccess.open(preset_file_path, FileAccess.WRITE)
		
		var preset_template : String
		#Check if base pack is provided
		if (dirs.BaseDataDir != ""):
			var patch_list_str = 'PackedStringArray("%s")' % dirs.BaseDataDir
		
			preset_template = """[preset.0]
			name="Windows"
			platform="Windows Desktop"
			runnable=false
			dedicated_server=false
			custom_features=""
			export_filter="all_resources"
			include_filter=""
			exclude_filter=""
			patch_list={PATCH_LIST}
			export_path="mod_compile.pck"

			[preset.0.options]
			""".replace("{PATCH_LIST}", patch_list_str)
		else:
			# We define a dummy preset named "PackerDefault" matching your CLI argument
			preset_template = """
			[preset.0]
			name="PackerDefault"
			platform="Windows Desktop"
			runnable=false
			dedicated_server=false
			custom_features=""
			export_filter="all_resources"
			include_filter=""
			exclude_filter=""
			export_path="mod_output.pck"

			[preset.0.options]
			"""
		file.store_string(preset_template.strip_edges())
		file.close()

########## UI EVENTS ############
#--------------------------------------------------------------
func _on_godot_exec_changed(t: String) -> void:
	dirs.ExecDir = t
	ResourceSaver.save(dirs, execPath + "SavedDir.tres")
	print("Godot Executable Path changed to {0}".format([t]))	

#--------------------------------------------------------------
func _on_mod_loc_changed(t: String) -> void:
	dirs.ModDir = t
	ResourceSaver.save(dirs, execPath + "SavedDir.tres")
	print("Mod Directory changed to {0}".format([t]))

#--------------------------------------------------------------
func _on_base_pack_changed(t: String) -> void:
	dirs.BaseDataDir = t
	ResourceSaver.save(dirs, execPath + "SavedDir.tres")
	print("Base pack path changed to {0}".format([t]))

#--------------------------------------------------------------
func _on_unpacked_base_changed(t: String) -> void:
	dirs.UnpackedDataDir = t
	ResourceSaver.save(dirs, execPath + "SavedDir.tres")
	print("Unpacked data pack path changed to {0}".format([t]))
	
#--------------------------------------------------------------
func _on_mod_export_changed(t: String) -> void:
	dirs.ModPackDir = t
	ResourceSaver.save(dirs, execPath + "SavedDir.tres")
	print("Mod Export Directory Changed to {0}".format([t]))

#--------------------------------------------------------------
func _on_generate_import_pressed() -> void:
	if (dirs.ModDir == ""):
		printerr("Missing Mod Dir")
		return
	var diag = ConfirmationDialog.new()
	add_child(diag)
	diag.mode = Window.MODE_FULLSCREEN
	diag.dialog_text = "Generate Mod Pack?"
	diag.popup_centered()
	diag.confirmed.connect(generate_Import_Files)

#--------------------------------------------------------------
func _on_generate_pack_pressed() -> void:
	GeneratePack()
	
#--------------------------------------------------------------
func _on_button_pressed() -> void:
	if (dirs.BaseDataDir == "" or !FileAccess.file_exists(dirs.BaseDataDir)):
		printerr("Wrong Base Pack")
	
	unpack_pck_to_disk()
