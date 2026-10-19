extends RefCounted

class_name PackerHelper

#----------------------------------------------------------------------
##Returns the path the Remap file points to
static func get_target_path_from_remap(remap_file_path: String) -> String:
	var config = ConfigFile.new()
	var err = config.load(remap_file_path)
	
	if err == OK:
		# Check if the [remap] section has the "path" property
		if config.has_section_key("remap", "path"):
			var internal_binary_path = config.get_value("remap", "path")
			return internal_binary_path # Returns something like "res://.godot/exported/..."
	
	print("Failed to parse remap file: ", remap_file_path)
	return ""

#----------------------------------------------------------------------
##Returns the path the import file points to
static func get_target_path_from_import(import_file_path: String) -> String:
	var config = ConfigFile.new()
	var err = config.load(import_file_path)
	
	if err == OK:
		# Check the [remap] section for the compiled binary path
		if config.has_section_key("remap", "path"):
			var compiled_path = config.get_value("remap", "path")
			return compiled_path # Returns e.g. "res://.godot/imported/player.png-4b2a3f...ctex"
			
		if config.has_section_key("remap", "path.bptc"):
			var compiled_path = config.get_value("remap", "path.bptc")
			return compiled_path 
			
		# Fallback: Some files use 'dest_files' array for multiple variants
		if config.has_section_key("remap", "dest_files"):
			var dest_files = config.get_value("remap", "dest_files")
			if dest_files is Array and dest_files.size() > 0:
				return dest_files[0]
				
	print("Failed to read import layout: ", import_file_path)
	return ""

#----------------------------------------------------------------------
##Checks the UID cache an tried to reconstruct the UID files of all the resources in the directory
static func reconstruct_uid(local_unpacked_root_dir: String) -> void:
	# 1. Point to the unpacked .godot cache folder
	var virtual_cache_path = "res://.godot/uid_cache.bin"
	
	if not FileAccess.file_exists(virtual_cache_path):
		print("Warning: uid_cache.bin not found inside the mounted PCK layout.")
		return
		
	print("Parsing binary uid_cache.bin to reconstitute individual .uid files...")
	
	var file = FileAccess.open(virtual_cache_path, FileAccess.READ)
	if not file:
		print("Failed to open binary cache file.")
		return
		
	# 2. Parse the Godot 4 central UID binary format
	# Format Layout: [Int32: Magic/Entry Count] followed by pairs of [Int64: ID] and [String: Path]
	var entry_count = file.get_32()
	
	for i in range(entry_count):
		if file.get_position() >= file.get_length():
			break
			
		var uid_int64 = file.get_64()    # The unique numeric integer ID
		var virtual_path = file.get_pascal_string() # Pascal layout pulls length then characters
		
		if virtual_path.is_empty() or not virtual_path.begins_with("res://"):
			continue
			
		# 3. Convert the 64-bit int back into Godot's standard string text syntax
		var uid_text_string = ResourceUID.id_to_text(uid_int64)
		
		
		# 4. Locate the path destination inside your local extraction directory
		var relative_path = virtual_path.trim_prefix("res://")
		var local_file_path = local_unpacked_root_dir.path_join(relative_path)
		if (FileAccess.file_exists(local_file_path + ".import")):
			continue
		
		write_uid_to_tres(local_file_path, uid_text_string)
		
		#Instead of making a .uid file for .tres files, we add the UID in the .tres file
		
		## 5. Append the .uid extension suffix (e.g., music_manager.gd.uid)
		#var target_uid_file_path = local_file_path + ".uid"
		#
		## Guard: Ensure the nested directory structures exist on the hard drive
		#var parent_dir = target_uid_file_path.get_base_dir()
		#if not DirAccess.dir_exists_absolute(parent_dir):
			#DirAccess.make_dir_recursive_absolute(parent_dir)
			#
		## 6. Save the text line to disk
		#var file_write = FileAccess.open(target_uid_file_path, FileAccess.WRITE)
		#if file_write:
			#file_write.store_string(uid_text_string)
			#file_write.close()
			
	file.close()
	print("Successfully reconstituted all project UID files!")

#----------------------------------------------------------------------
static func write_uid_to_tres(path: String, uid: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var content := file.get_as_text()
	file.close()

	var regex := RegEx.new()
	regex.compile('(?m)^\\[gd_resource([^\\]]*)\\]')

	var match_result := regex.search(content)
	if match_result == null:
		return false

	var header := match_result.get_string(0)
	var attributes := match_result.get_string(1)

	# Remove any existing UID attribute.
	var uid_regex := RegEx.new()
	uid_regex.compile('\\s+uid="[^"]*"')
	attributes = uid_regex.sub(attributes, "", true)

	# Add the new UID.
	attributes += ' uid="' + uid + '"'

	content = content.replace(
		header,
		"[gd_resource" + attributes + "]"
	)

	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(content)
	file.close()
	return true

#----------------------------------------------------------------------
static func run_opengds_decompiler(gdc_physical_path: String) -> void:

	# 1. OS.get_executable_path().get_base_dir() finds the folder where your game is running on disk
	var base_dir = OS.get_executable_path().get_base_dir()
	var opengds_path = base_dir.path_join("OpenGDS.py")
	
	# 2. Formulate the CLI arguments for OpenGDS (e.g., "python OpenGDS.py dcmp <file>")
	var arguments = [opengds_path, "dcmp", gdc_physical_path]
	
	# 3. Call the system Python shell
	var output = []
	
	var local_python_path = OS.get_executable_path().get_base_dir().path_join("python_embed/python.exe")
	var exit_code = OS.execute(local_python_path, arguments, output, true)
	
	if exit_code == 0:
		# 3. Concatenate the output array lines back into one giant code block string
		var full_source_code : String = ""
		for line in output:
			full_source_code += line + "\n"
		
		# 4. Generate the new clean target filename (CardModule.gdc -> CardModule.gd)
		var target_gd_path = gdc_physical_path.left(-4) + ".gd"
		
		# 5. Save the captured code block natively to your unpacked workspace directory
		var file_write = FileAccess.open(target_gd_path, FileAccess.WRITE)
		if file_write:
			file_write.store_string(full_source_code.strip_edges()) # Strip extra leading/trailing whitespace
			file_write.close()
			print("Successfully saved decompiled file to: ", target_gd_path)
			
			# Optional: Erase the compiled binary now that you have the clean source code
			DirAccess.remove_absolute(gdc_physical_path)
		else:
			print("Failed to save final script file to disk: ", target_gd_path)
	else:
		print("OpenGDS failed with exit code: ", exit_code)

#----------------------------------------------------------------------
static func DeleteDirectoryRecursive(path: String) -> void:
	var dir := DirAccess.open(path)

	if dir == null:
		return

	dir.list_dir_begin()

	while true:
		var file_name := dir.get_next()

		if file_name == "":
			break

		if file_name == "." or file_name == "..":
			continue

		var full_path := path.path_join(file_name)

		if dir.current_is_dir():
			DeleteDirectoryRecursive(full_path)
		else:
			DirAccess.remove_absolute(full_path)

	dir.list_dir_end()

	DirAccess.remove_absolute(path)

#----------------------------------------------------------------------
##Builds a new directory only containing the differances between the 2 directories provided
##uses the SHA-256 to compare the files, check `_files_are_identical` function
static func _build_diff(current_mod_dir: String,mod_root: String,base_root: String,staging_root: String) -> void:
	var dir := DirAccess.open(current_mod_dir)

	if dir == null:
		print("Could not open directory: " + current_mod_dir)
		return

	dir.list_dir_begin()

	while true:
		var file_name := dir.get_next()

		if file_name == "":
			break

		if file_name == "." or file_name == "..":
			continue

		if file_name == ".godot":
			continue

		var mod_path := current_mod_dir.path_join(file_name)

		# Calculate path relative to the mod project root.
		var relative_path := mod_path.trim_prefix(mod_root)
		relative_path = relative_path.trim_prefix("/")

		var base_path := base_root.path_join(relative_path)
		var staging_path := staging_root.path_join(relative_path)

		if dir.current_is_dir():
			if (Main.ignores.CheckDir(relative_path)):
				_build_diff(
					mod_path,
					mod_root,
					base_root,
					staging_root,
				)
		else:
			# project.godot belongs to the temporary project and
			# shouldn't be considered a mod asset.
			if relative_path == "project.godot":
				continue
			
			if (!Main.ignores.CheckFile(relative_path)):
				continue
			
			var is_new := not FileAccess.file_exists(base_path)
			var is_changed := false
			var is_script := mod_path.ends_with(".gd")

			if not is_new:
				is_changed = not _files_are_identical(
					mod_path,
					base_path
				)

			if is_new or is_changed or is_script:
			
				_copy_file(
					mod_path,
					staging_path,
				)

				if (mod_path.ends_with(".tres")):
					#var loadedRes : Resource = load("res://" + relative_path)
					var deps = ResourceLoader.get_dependencies(mod_path)
					if (deps.size() > 0):
						print("--------- Dependencies Found - Packing ---------")
						SaveDep(deps, mod_root, staging_root)
						print("--------- Dependencies Packed ---------")
				

	dir.list_dir_end()

#----------------------------------------------------------------------
##Used in the build dif function to carry over to the new dif directory the dependancies of each file
static func SaveDep(dependencies : PackedStringArray, mod_dir : String, staging_root : String) -> void:
	for dependency in dependencies:
		var dependencyLoc : String
		
		if dependency.contains("::"):
			dependencyLoc = dependency.get_slice("::", 2)
		else:		
			dependencyLoc = dependency
		
		var dependency_staging_path := dependencyLoc.replace("res:/", staging_root)
		dependencyLoc = dependencyLoc.replace("res:/", mod_dir)

		
		if (!FileAccess.file_exists(dependency_staging_path)):
			_copy_file(
				dependencyLoc,
				dependency_staging_path,
				true
			)
		
		if (dependencyLoc.ends_with(".tres")):
			SaveDep(ResourceLoader.get_dependencies(dependencyLoc), mod_dir, staging_root)
			
#----------------------------------------------------------------------
##Passes both files through a hash function and checks the resault
static func _files_are_identical(file_a: String,file_b: String) -> bool:

	var hash_a := FileAccess.get_sha256(file_a)
	var hash_b := FileAccess.get_sha256(file_b)

	return hash_a == hash_b

#----------------------------------------------------------------------
##Copies source file to destinaction without loading it
static func _copy_file(source: String, destination: String, is_Deependency : bool = false) -> void:
	var parent := destination.get_base_dir()

	DirAccess.make_dir_recursive_absolute(parent)

	var data := FileAccess.get_file_as_bytes(source)

	var file := FileAccess.open(
		destination,
		FileAccess.WRITE
	)

	if file == null:
		print("Failed to create: " + destination)
		return

	var result = file.store_buffer(data)
	if (!result):
		print("File copying had errors")
	file.close()
	
	if (is_Deependency):
		print("       + DEPENDENCY --- " + source)
	else:
		print("  + " + source)
	
	if (source.ends_with(".tres")):
		var uidPath = source + ".uid"
		var destinationUID = destination + ".uid"
		if (!FileAccess.file_exists(destinationUID)):
			_copy_file(
				uidPath,
				destinationUID,
				is_Deependency
			)

#----------------------------------------------------------------------
func is_python_installed() -> bool:
	var output: Array[String] = []
	
	# Execute a lightweight version query flag
	# On Windows, using cmd.exe ensures we don't throw an uncatchable native crash 
	# if the 'python' keyword doesn't exist at all.
	var arguments: Array[String] = ["/c", "python --version"]
	var exit_code = OS.execute("cmd.exe", arguments, output, true)
	
	if exit_code == 0 and output.size() > 0:
		print("Python detected on system: ", output[0].strip_edges())
		return true
	else:
		print("Python was not found or is not configured in the system PATH.")
		return false
