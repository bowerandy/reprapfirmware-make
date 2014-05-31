#!/bin/bash
#----------------------------------------------------------------------------
#
# Builds RepRapPro and DC42's Ormerod firmware from source
#
# - Downloads Arduino environment from arduino.cc
# - Downloads the selected firmware from github.com
# - Compiles the RepRapFirmware source code
#
# Update 30/05/2014:
#
# - It only compiles changed files for faster recompilation.
# - It shows less output to keep the compilation result clean.
# - Added command line parameter 'clean' to clean project.
# - Added command line parameter 'verbose' to show output.
# - Removed the (not so interesting) ELF file statistics.
# - Probably supports the MacOS platform for jstck...
#
# 3D-ES
#----------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status.
set -e

# Firmware name
FW=RepRapFirmware
LIB=${FW}/Libraries
BUILD=${FW}/Build
RELEASE=${FW}/Release

# Arduino version to use
ARDUINO=arduino-1.5.4
ARDUINO_VERSION=154

# Check if there are script parameters:
#
# - Supports 'clean' to remove the built files.
# - Supports 'verbose' to display script output.
#
if [ $# -gt 0 ]
then
    if [ $1 == "clean" ]
    then
        echo Cleaning ${BUILD} and ${RELEASE}
        rm -rf ${BUILD} ${RELEASE}
        exit
    fi

    if [ $1 == "verbose" ]
    then
        set -x
    fi
fi

# Check if the RepRapFirmware folder is available:
#
# - Ask which firmware version to download.
# - Get the duet branch from the repository.
#
if [ ! -d ${FW} ]; then
    while true; do
        echo "Which firmware version do you want to use?"
        echo ""
        echo "[R] = RepRapPro original"
        echo "[D] = dc42's excellent fork"
        echo ""
        read -p "Please answer R or D: " input
        case $input in
            [Rr]* ) FW_REPO=git://github.com/RepRapPro/${FW}; break;;
            [Dd]* ) FW_REPO=git://github.com/dc42/${FW}; break;;
            * ) echo "Please answer R or D.";;
        esac
    done

    git clone -b duet ${FW_REPO} ${FW}
fi

# Check if the Arduino folder is available:
#
# - Detect if the hardware is 32 or 64 bits.
# - Detect if the system runs Linux or MacOS.
# - Download the archive if no cache found.
# - Extract the archive to this folder.
#
if [ ! -d ${ARDUINO} ]
then
    if [[ $OSTYPE == linux-gnu ]]
    then
        if [ $(uname -m) == x86_64 ]
            then ARCHIVE=${ARDUINO}-linux64.tgz
            else ARCHIVE=${ARDUINO}-linux32.tgz
        fi

        if [ ! -f ${ARCHIVE} ]
            then wget http://downloads.arduino.cc/${ARCHIVE}
        fi

        tar -xvzf ${ARCHIVE}
    fi

    if [[ $OSTYPE == darwin* ]]
    then
        ARCHIVE=${ARDUINO}-macosx.zip

        if [ ! -f ${ARCHIVE} ]
            then wget http://downloads.arduino.cc/${ARCHIVE}
        fi

        unzip -o ${ARCHIVE}

        # Convert the Arduino environment to look like Linux.
	mv Arduino.app/Contents/Resources/Java/* Arduino.app
	mv Arduino.app ${ARDUINO}
    fi
fi

# Check if there are ArduinoCorePatches available:
#
# - These patches are only available with dc42's firmware.
# - Always overwrites patched files because of git pull updates.
# - Preserves the timestamps to prevent it's recompilation.
#
if [ -d ${FW}/ArduinoCorePatches ]
then
    cp -r --preserve=timestamps ${FW}/ArduinoCorePatches/sam ${ARDUINO}/hardware/arduino
fi

# Check if jmgiacalone's libraries are available:
#
# - The dc42 firmware version contains updated libraries.
# - The RepRapPro version does not include these libraries.
#
if [ ! -d ${LIB} ]
then
    git clone git://github.com/jmgiacalone/Arduino-libraries ${LIB}
fi

# Platform defines
PLATFORM=(
    -mcpu=cortex-m3
    -DF_CPU=84000000L
    -DARDUINO=${ARDUINO_VERSION}
    -D__SAM3X8E__
    -mthumb
)

# USB defines
USB_OPT=(
    -DUSB_PID=0x003e
    -DUSB_VID=0x2341
    -DUSBCON
)

# See: http://gcc.gnu.org/onlinedocs/gcc/Option-Summary.html
GCC_OPT=(
    -c # Compile the source files, but do not link
    -g # Produce debugging info in OS native format
    -O3 # Maximum optimization of size vs execution time
    -w # Inhibit all warning messages
    -ffunction-sections # Place each function into its own section
    -fdata-sections # Place each data item into its own section
    -nostdlib # Do not use standard system startup files or libraries
    --param max-inline-insns-single=500 # Max. instructions to inline
    -Dprintf=iprintf # Prevent bloat by using integer printf function
    -MMD # Create dependency output file but only of user header files
    -MP # Add phony target for each dependency other than the main file
)

# See: http://gcc.gnu.org/onlinedocs/gcc/Option-Summary.html
GPP_OPT=(
    -c # Compile the source files, but do not link
    -g # Produce debugging info in OS native format
    -O3 # Maximum optimization of size vs execution time
    -w # Inhibit all warning messages
    -ffunction-sections # Place each function into its own section
    -fdata-sections # Place each data item into its own section
    -nostdlib # Do not use standard system startup files or libraries
    --param max-inline-insns-single=500 # Max. instructions to inline
    -Dprintf=iprintf # Prevent bloat by using integer printf function
    -MMD # Create dependency output file but only of user header files
    -MP # Add phony target for each dependency other than the main file
    -fno-rtti # Don't produce Run-Time Type Information structures
    -fno-exceptions # Disable exception handling to prevent overhead
    -x c++ # Specify the language of the input files
)

# See: http://gcc.gnu.org/onlinedocs/gcc/Option-Summary.html
COM_OPT=(
    -Os
    -mcpu=cortex-m3
    "-T${ARDUINO}/hardware/arduino/sam/variants/arduino_due_x/linker_scripts/gcc/flash.ld"
    "-Wl,-Map,${BUILD}/${FW}.map"
    "-L${BUILD}"
    -lm
    -lgcc
    -mthumb
    -Wl,--cref
    -Wl,--check-sections
    -Wl,--gc-sections
    -Wl,--entry=Reset_Handler
    -Wl,--unresolved-symbols=report-all
    -Wl,--warn-common
    -Wl,--warn-section-align
    -Wl,--warn-unresolved-symbols
    -Wl,--start-group
    ${BUILD}/*.o
    ${ARDUINO}/hardware/arduino/sam/variants/arduino_due_x/libsam_sam3x8e_gcc_rel.a
    -Wl,--end-group
)

# Folders to include.
INC=(
    -I"${FW}/Flash"
    -I"${FW}/Libraries/EMAC"
    -I"${FW}/Libraries/Lwip"
    -I"${FW}/Libraries/MCP4461"
    -I"${FW}/Libraries/SamNonDuePin"
    -I"${FW}/Libraries/SD_HSMCI"
    -I"${FW}/Libraries/SD_HSMCI/utility"
    -I"${FW}/network"
    -I"${ARDUINO}/hardware/arduino/sam/cores/arduino"
    -I"${ARDUINO}/hardware/arduino/sam/variants/arduino_due_x"
    -I"${ARDUINO}/hardware/arduino/sam/system/libsam"
    -I"${ARDUINO}/hardware/arduino/sam/system/libsam/include"
    -I"${ARDUINO}/hardware/arduino/sam/system/CMSIS/Device/ATMEL/"
    -I"${ARDUINO}/hardware/arduino/sam/system/CMSIS/CMSIS/Include/"
    -I"${ARDUINO}/hardware/arduino/sam/libraries/Wire"
)

# Location of the ARM compiler.
GCC_ARM_DIR=${ARDUINO}/hardware/tools/g++_arm_none_eabi

# Cross compiler binary locations.
GCC=${GCC_ARM_DIR}/bin/arm-none-eabi-gcc
GPP=${GCC_ARM_DIR}/bin/arm-none-eabi-g++
COPY=${GCC_ARM_DIR}/bin/arm-none-eabi-objcopy

# Create output folders.
mkdir -p ${BUILD} ${RELEASE}

# Locate and compile all the .c files that need to be compiled.
for file in $(find ${FW} ${ARDUINO}/hardware/arduino/sam/cores -type f -name "*.c")
do
    # Intermediate build output.
    D=${BUILD}/$(basename $file).d
    O=${BUILD}/$(basename $file).o

    # Skip compile if the object is up-to-date.
    if [ ${O} -nt ${file} ]; then continue; fi

    # Show some progress.
    echo Compiling ${file}

    # The C source file is newer than the object output file, we need to compile it.
    ${GCC} ${GCC_OPT[@]} ${PLATFORM[@]} ${USB_OPT[@]} ${INC[@]} ${file} -MF${D} -MT${D} -o${O}
done

# Locate and compile all the .cpp files that need to be compiled.
for file in $(find ${FW} ${ARDUINO}/hardware/arduino/sam -type f -name "*.cpp")
do
    # Intermediate build output.
    D=${BUILD}/$(basename $file).d
    O=${BUILD}/$(basename $file).o

    # Skip compile if the object is up-to-date.
    if [ ${O} -nt ${file} ]; then continue; fi

    # Show some progress.
    echo Compiling ${file}

    # The CPP source file is newer than the object output file, we need to compile it.
    ${GPP} ${GPP_OPT[@]} ${PLATFORM[@]} ${USB_OPT[@]} ${INC[@]} ${file} -MF${D} -MT${D} -o${O}
done

# Combine the objects into an executable file.
${GPP} ${COM_OPT[@]} -o ${BUILD}/${FW}.elf

# Convert the ELF file to the firmware binary.
${COPY} -O binary ${BUILD}/${FW}.elf ${RELEASE}/${FW}.bin

# Show the output file name.
echo Created ${RELEASE}/${FW}.bin

