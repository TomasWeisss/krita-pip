# krita-pip
An implementation of a subset of Python pip to manage packages for developing Krita plugins via
```
.\kritapip.ps1 my_plugin [pip command]
```
**WARNING**: Package dependencies are currently not handled automatically. You can look into 
the `[package].dist-info/METADATA` file for `Requires-Dist:` lines and manually install those packages. 

## Commands

### Install
You can install packages for a plugin by calling
```
.\kritapip.ps1 [plugin] install [package]

# For example
.\kritapip.ps1 my_plugin install numpy
```
or specify a version
```
.\kritapip.ps1 [plugin] install [package==version]

#For example
.\kritapip.ps1 my_plugin install numpy==2.1
# or
.\kritapip.ps1 my_plugin install numpy==2.1.2
```

### Uninstall
Uninstall packages by calling
```
.\kritapip.ps1 [plugin] uninstall [package]

# For example
.\kritapip.ps1 my_plugin uninstall numpy
```

### List
List packages currently installed for a plugin using
```
.\kritapip.ps1 [plugin] list

# For example
.\kritapip.ps1 my_plugin list
```

## Importing
In order to import these packages in your python plugin, you first have to add this code
at the top of your file
```python
import os, sys
plugin_dir = os.path.dirname(os.path.abspath(__file__))
vendor_dir = os.path.join(plugin_dir, "vendor")
if vendor_dir not in sys.path:
    sys.path.insert(0, vendor_dir)
```
You can then import the packages as you normally would.

## Behind the scenes
The script read the PyPI metadata for packages and resolves the best version. It then
downloads the wheel for that package and extracts it into the`[plugin]\vendor\` directory.