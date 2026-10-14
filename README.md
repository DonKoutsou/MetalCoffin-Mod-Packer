# Metal Coffin Modding Tool

This repository contains the custom Godot engine tool used for creating and packaging mods for Metal Coffin.

## Instructions
Launching the executable provided in the release allows you to use the tool.
After the initial launch 2 files will be generated in the executable directory.

| File | Description |
|---------|-------------|
| SavedDir.tres | Directories configured in the tool are saved here. |
| Packer_Ignores.tres | This is the configuration used by the tool to ignore certain directories or filetypes. Can be modified, but not recomended |

Once the tool is running you will need to configure the paths

| Path | Description |
|---------|-------------|
| Godot Executable | This is the path to the Godot executable. The Godot executable it delivered with the tool so it will be found in the exe's directory. A custom version can be used but its not recomended |
| Base Pack | This is the path to the .pck file that can be found in the game's directory. Locate Metal Coffin's files and in the same folder as the .exe you will find the .pck |

Leave the rest empty for now.
Press the `Unpack Game` button and let the process finish.

Once finished there will be an `Unpacked` folder in the game's directory and the `Unpacked Base Files` directory will have been automatically filled.
Copy the `Unpacked` folder to a location of your choosing and rename it to the Mod's name. Use this copy as a base to your mod. Change textures, change scripts, resources etc.

Once finished, open the tool again and configure the directory of your Mod in the `Mod Location` entry. Once that is done press the `Generate Pack` button and wait.
A dif will be made to see what changed from the original files on your mod and from that dif a .pck will be created in the in the directory of the Tool.

Place that new .pck in `C:\Users\Admin\Documents\My Games\MetalCoffin\Mods` and start the game. If this directory does not exist for you make sure to run the game at least once for it to apear.

## Other Tools
The unpacked files can be manually modified or the Official tools can be used instead.
* [Card Builder](https://github.com/DonKoutsou/Metal_Coffin_Card_Builder)
* [Item Builder](https://github.com/DonKoutsou/Metal_Coffin_Item_Builder)
* [Dialogue Editor](https://github.com/DonKoutsou/Metal_Coffin_Dialogue_Editor)
* [Captain Creator](https://github.com/DonKoutsou/Metal_Coffin_Captain_Creator)

## Credits
This project relies on the following open-source software:
* OpenGDS — Used to handle the decompilation of game scripts, allowing modders to inspect and hook into the game's codebase. https://github.com/ABDO10DZ/OpenGDS
* Godot Engine — The core foundation of this toolkit.
