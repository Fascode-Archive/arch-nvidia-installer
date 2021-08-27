## NVIDIA driver installer for Arch Linux
`nvidia.sh`  is the bash script to install NVIDIA driver for Arch Linux.  
Install the package and set up some configuration files.  
Everything is written in a single shell script.

## Usage
Just run the following command:

```bash
    curl -sL -o /tmp/nvidia.sh https://raw.githubusercontent.com/Hayao0819/arch-nvidia-installer/master/nvidia.sh
    sudo bash /tmp/nvidia.sh
```
This script is for Arch Linux only and requires Pacman and mkinitcpio.  
Boot loader setup only supports Grub.Other boot loaders are ignored.  

## LICENSE
This script is licensed under WTFPL.
