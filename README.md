# converter

## Description

This is a script for convering D modeles. Using the omg tools in ddk.

## Usage

Config the the `config.ini` first. Set the ddk path which you want to use in the file.

**```./convert.sh RUN_MODE ORG_FILES_PATH [OPTION]OUT_PATH```**\

>**RUN_MODE**:
>
>- 0: Convert the model with default configuration.
>- 1: Convert the models with the configuration files in config floder.
>
>**ORG_FILES_PATH**: \
>
>The floder which contains the `.protxt` or `.ph` files. Support both absolute path and relative path.
>
>*OUT_PATH*: \
This a optional parameter. Indicate the D models output path. >The script will create a sub-floder with DDK version name. For example : 1_1_T10B810.
